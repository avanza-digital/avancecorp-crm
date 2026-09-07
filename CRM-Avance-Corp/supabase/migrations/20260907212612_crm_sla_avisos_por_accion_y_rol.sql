-- Modelo 3: trabajo del analista y revisión comercial independientes.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $preflight$ begin
  if md5(pg_get_functiondef('private.assert_sla_nucleo()'::regprocedure))<>'6bc541b2e3ba1549b4b4ed419c22d455' then
    raise exception 'SLA: cambió la fuente assert_sla_nucleo';
  end if;
  if md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure))<>'7b5f75dfb6ac3e480659bdef3dc5ac0f' then
    raise exception 'SLA: cambió la fuente avisos_sla_resumen_v2_fn';
  end if;
  if md5(pg_get_functiondef('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)'::regprocedure))<>'f0b81dd1103390cec2db26a9e11f1acf' then
    raise exception 'SLA: cambió la fuente cola_accion_v2_fn';
  end if;
  if md5(pg_get_functiondef('crm.estado_sla_leads_v2_fn(uuid[])'::regprocedure))<>'b50bf8c3f41770618a67d94b01b1ca42' then
    raise exception 'SLA: cambió la fuente estado_sla_leads_v2_fn';
  end if;
  if md5(pg_get_functiondef('private.sla_hechos_actuales(uuid[],boolean,uuid[])'::regprocedure))<>'0591814007ab1ebc39be1708d147f15e' then
    raise exception 'SLA: cambió la fuente sla_hechos_actuales';
  end if;
  if md5(pg_get_functiondef('private.sla_operacion_autorizada(uuid[],boolean)'::regprocedure))<>'08abb868e8cf62389fbbfe2e7d53ef8c' then
    raise exception 'SLA: cambió la fuente sla_operacion_autorizada';
  end if;
  if md5(pg_get_functiondef('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)'::regprocedure))<>'d880268ef586322e0589586cb8cde30d' then
    raise exception 'SLA: cambió la fuente sla_operacion_leads';
  end if;
  if md5(pg_get_functiondef('private.sla_tareas_hechos(uuid[],boolean,uuid[])'::regprocedure))<>'01fc105bddefa202b4a910938c65c052' then
    raise exception 'SLA: cambió la fuente sla_tareas_hechos';
  end if;
  perform private.assert_sla_nucleo();
end; $preflight$;

CREATE OR REPLACE FUNCTION private.sla_operacion_leads(p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamp with time zone)
 RETURNS TABLE(lead_id uuid, estado jsonb, accion_atencion jsonb, accion_supervision jsonb, senales jsonb, presentacion jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_control crm.sla_operacion_control%rowtype;
  v_operativa uuid; v_adopcion uuid; v_activacion timestamptz;
  h record; v_motivos text[]; v_revision_motivos text[];
  v_referencia timestamptz; v_seguimiento_limite timestamptz; v_seguimiento_vencido boolean;
  v_compromiso jsonb; v_validez text; v_hasta timestamptz; v_cobertura boolean;
  v_techo timestamptz; v_prorrogado timestamptz; v_operativo timestamptz;
  v_revision_limite boolean; v_revision boolean; v_reprogramaciones boolean;
  v_pendiente boolean; v_terminal boolean; v_vetado boolean; v_usable boolean;
  v_primera timestamptz; v_tarea jsonb; v_accion jsonb; v_sup jsonb;
  v_avisos jsonb; v_principal jsonb;
  v_inicial boolean; v_programada boolean; v_seguimiento_operativo boolean;
  v_cambio timestamptz;
  v_bucket text; v_prioridad integer; v_severidad text; v_accion_en timestamptz;
begin
  if p_ahora is null or not isfinite(p_ahora) or p_global is null or p_visibles is null
     or array_position(p_visibles,null) is not null or array_position(p_lead_ids,null) is not null then
    raise exception 'Ambito o instante SLA invalido' using errcode='22023';
  end if;
  select * into strict v_control from crm.sla_operacion_control where id;
  select p.politica_id into v_operativa from private.sla_politica_operativa(p_ahora) p;
  v_activacion:=coalesce(v_control.primera_activacion_en,
    case when v_control.modo='observacion' then p_ahora end);
  v_adopcion:=coalesce(v_control.politica_adopcion_id,
    case when v_control.modo='observacion' then v_operativa end);

  for h in
    with hechos as materialized (
      select * from private.sla_hechos_actuales(p_lead_ids,p_global,p_visibles)
    ), tareas as materialized (
      select * from private.sla_tareas_hechos(p_lead_ids,p_global,p_visibles)
    )
    select f.*, r.seguimiento_minutos,r.pausa_habilitada,r.pausa_margen_minutos,
      er.politica_id as politica_prorroga,coalesce(er.prorroga_max,0) as prorroga_max,
      coalesce(er.tope_extra_minutos,ar.tope_extra_minutos) as extra,
      coalesce(er.politica_id,ar.politica_id) as politica_techo,
      a.creado_en as ultima_gestion_en,a.tipo as ultima_gestion_tipo,
      a.creado_por as autor_id,a.autor_nombre,
      j.minutos,j.usadas,j.ingresos,
      t.motivos_tarea,t.primera_comercial,t.primera_agenda,
      private.persona_vetada(f.lead_id) as vetado
    from hechos f
    left join crm.sla_politica_etapas_operacion r on r.politica_id=v_operativa and r.etapa=f.etapa_actual
    left join crm.sla_politica_etapas_operacion er on er.politica_id=f.politica_etapa_id and er.etapa=f.etapa_actual
    left join crm.sla_politica_etapas_operacion ar on ar.politica_id=v_adopcion and ar.etapa=f.etapa_actual
    left join lateral (
      select a.creado_en,a.tipo,a.creado_por,p.nombre_completo as autor_nombre
      from crm.actividades a left join public.perfiles p on p.id=a.creado_por
      where a.lead_id=f.lead_id and f.ciclo_inicio is not null and f.asignacion_inicio is not null
        and f.asignacion_coherente is true
        and a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
        and isfinite(a.creado_en) and a.creado_en>=greatest(f.ciclo_inicio,f.asignacion_inicio)
        and a.creado_en<=p_ahora
      order by a.creado_en desc,a.id desc limit 1
    ) a on true
    cross join lateral private.sla_etapa_hechos(f.etapa_sla_id,f.lead_id,f.ciclo_n,f.etapa_actual) j
    left join lateral (
      select array_agg(distinct t.motivo_dato) filter (
          where t.tipo in ('llamada','whatsapp','reunion') and t.motivo_dato is not null) as motivos_tarea,
        (jsonb_agg(jsonb_build_object('id',t.tarea_id,'lead_id',t.lead_id,'tipo',t.tipo,
          'titulo',t.titulo,'vence_en',t.vence_en,'reprogramaciones',t.reprogramaciones,
          'responsable_id',t.responsable_id,'autor_id',t.autor_id,'autor_nombre',t.autor_nombre,
          'contexto_fuente',t.contexto_fuente) order by t.vence_en,t.tarea_id)
          filter (where t.tipo in ('llamada','whatsapp','reunion') and t.motivo_dato is null))->0 as primera_comercial,
        (jsonb_agg(jsonb_build_object('id',t.tarea_id,'tipo',t.tipo,'titulo',t.titulo,'vence_en',t.vence_en) order by t.vence_en,t.tarea_id)
          filter (where isfinite(t.vence_en) and t.motivo_dato is null))->0 as primera_agenda
      from tareas t where t.lead_id=f.lead_id
    ) t on true
    order by f.lead_id
  loop
    v_terminal:=h.etapa_actual not in ('nuevo','contactado','reunion_agendada','propuesta_enviada');
    v_vetado:=coalesce(h.vetado,true);
    v_motivos:='{}'::text[];
    v_revision_motivos:='{}'::text[];
    if h.base is null then v_motivos:=array_append(v_motivos,'sin_foto_sla'); end if;
    if h.asignacion_id is null then v_motivos:=array_append(v_motivos,'sin_asignacion'); end if;
    if h.asignacion_coherente is false then v_motivos:=array_append(v_motivos,'asignacion_sla_incoherente'); end if;
    if h.etapa_sla_id is null and not v_terminal then v_motivos:=array_append(v_motivos,'sin_episodio_etapa'); end if;
    if h.etapa_coherente is false then v_motivos:=array_append(v_motivos,'etapa_sla_incoherente'); end if;
    if v_operativa is null then v_motivos:=array_append(v_motivos,'politica_operativa_ausente'); end if;
    if v_activacion is null then v_motivos:=array_append(v_motivos,'operacion_no_activada'); end if;
    if v_terminal then v_motivos:=array_append(v_motivos,'lead_terminal'); end if;
    if h.activo is not true then v_motivos:=array_append(v_motivos,'lead_inactivo'); end if;
    if v_vetado then v_motivos:=array_append(v_motivos,'restriccion_contacto'); end if;
    v_motivos:=v_motivos||coalesce(h.motivos_tarea,'{}'::text[]);
    v_usable:=h.activo is true and not v_terminal and not v_vetado;
    v_referencia:=null;
    if h.ciclo_inicio is not null and h.asignacion_inicio is not null and h.asignacion_coherente is true then
      v_referencia:=greatest(h.ciclo_inicio,h.asignacion_inicio,h.ultima_gestion_en);
      if not isfinite(v_referencia) or v_referencia>p_ahora then
        v_referencia:=null;
        v_motivos:=array_append(v_motivos,'referencia_gestion_invalida');
      end if;
    end if;
    v_seguimiento_limite:=case when v_usable and v_referencia is not null
      and h.seguimiento_minutos is not null and v_activacion is not null
      then greatest(v_referencia+h.seguimiento_minutos*interval '1 minute',v_activacion) end;
    v_seguimiento_vencido:=p_ahora>=v_seguimiento_limite;
    v_techo:=case when h.etapa_coherente is true and isfinite(h.limite_original) and h.extra is not null
      then h.limite_original+h.extra*interval '1 minute' end;
    v_prorrogado:=case when isfinite(h.limite_original)
      then h.limite_original+h.minutos*interval '1 minute' end;
    if (h.politica_prorroga is null and h.usadas>0) or h.usadas>h.prorroga_max
       or v_prorrogado>v_techo then
      raise exception 'Hechos de ajustes SLA fuera del presupuesto' using errcode='23514';
    end if;

    v_compromiso:=case when cardinality(h.motivos_tarea) is null then h.primera_comercial end;
    v_validez:=case
      when not v_usable then 'no_aplica'
      when h.pausa_habilitada is null or v_activacion is null or v_techo is null
        or h.asignacion_coherente is false then 'datos_incompletos'
      when cardinality(h.motivos_tarea)>0 then 'datos_incompletos'
      when not h.pausa_habilitada then 'deshabilitado'
      when v_compromiso is null then 'sin_tarea'
      when (v_compromiso->>'reprogramaciones')::integer>=3 then 'reprogramaciones_agotadas'
      else 'valido' end;
    v_hasta:=case when v_validez='valido'
      then least((v_compromiso->>'vence_en')::timestamptz+h.pausa_margen_minutos*interval '1 minute',v_techo) end;
    v_cobertura:=case when v_validez in ('no_aplica','datos_incompletos') then null
      else v_hasta is not null and p_ahora<v_hasta end;
    v_pendiente:=v_seguimiento_vencido and (v_cobertura is distinct from true);
    v_operativo:=case when not v_usable or v_techo is null or v_prorrogado is null
        or v_validez='datos_incompletos' then null
      else least(greatest(v_prorrogado,coalesce(v_hasta,v_prorrogado)),v_techo) end;
    v_revision_limite:=case when not v_usable then null
      when v_techo is not null and p_ahora>=v_techo then true
      else p_ahora>=v_operativo end;
    v_reprogramaciones:=case when not v_usable then null
      when cardinality(h.motivos_tarea)>0 then null
      else coalesce((v_compromiso->>'reprogramaciones')::integer>=3,false) end;
    if v_revision_limite then v_revision_motivos:=array_append(v_revision_motivos,'limite_operativo_agotado'); end if;
    if v_reprogramaciones then v_revision_motivos:=array_append(v_revision_motivos,'reprogramaciones_agotadas'); end if;
    if v_usable and h.etapa_sla_id is not null and h.ingresos>=3 then
      v_revision_motivos:=array_append(v_revision_motivos,'reingreso_etapa');
    end if;
    v_revision:=case when not v_usable then null else
      v_revision_limite or v_reprogramaciones or (h.etapa_sla_id is not null and h.ingresos>=3) end;

    -- Agenda organiza el siguiente intento; la cobertura sigue gobernando
    -- los límites/prórrogas anteriores. Una revisión no adelanta una tarea.
    v_inicial:=h.asignacion_coherente is true
      and h.base->>'asignacion_primera_gestion_en' is not null
      and isfinite((h.base->>'asignacion_primera_gestion_en')::timestamptz)
      and (h.base->>'asignacion_primera_gestion_en')::timestamptz
        between greatest(h.ciclo_inicio,h.asignacion_inicio) and p_ahora;
    if h.asignacion_coherente is true and (
      (h.base->>'asignacion_primera_gestion_en' is not null and not coalesce(v_inicial,false))
      or (h.base->>'asignacion_primera_gestion_en' is null
        and not coalesce(isfinite((h.base->>'asignacion_primera_gestion_limite_en')::timestamptz),false))
    ) then v_motivos:=array_append(v_motivos,'primera_gestion_invalida'); end if;
    v_programada:=v_usable and h.asignacion_coherente is true
      and cardinality(h.motivos_tarea) is null
      and h.primera_comercial is not null
      and (h.primera_comercial->>'vence_en')::timestamptz>p_ahora;
    v_seguimiento_operativo:=v_inicial and v_seguimiento_vencido
      and not coalesce(v_programada,false);

    estado:=jsonb_build_object(
      'lead_id',h.lead_id,'base',h.base,'etapa_sla_id',h.etapa_sla_id,'ciclo_n',h.ciclo_n,'asignacion_id',h.asignacion_id,
      'evaluacion',case when not v_usable then 'no_aplica' when cardinality(v_motivos)>0
        or v_validez='datos_incompletos' then 'parcial' else 'completa' end,
      'motivos_datos',to_jsonb(v_motivos),
      'seguimiento',jsonb_build_object('referencia_en',v_referencia,'ultima_gestion_en',h.ultima_gestion_en,
        'ultima_gestion_tipo',h.ultima_gestion_tipo,'autor_id',h.autor_id,'autor_nombre',h.autor_nombre,
        'umbral_minutos',h.seguimiento_minutos,'limite_en',v_seguimiento_limite,'vencido',v_seguimiento_vencido,'accion_pendiente',v_pendiente),
      'compromiso',jsonb_build_object('tarea',v_compromiso,'validez',v_validez,'hasta_en',v_hasta,'cobertura_activa',v_cobertura),
      'etapa',jsonb_build_object('limite_original_en',h.limite_original,'limite_prorrogado_en',v_prorrogado,
        'minutos_prorrogados',case when h.etapa_sla_id is not null then h.minutos end,
        'prorrogas_usadas',case when h.etapa_sla_id is not null then h.usadas end,
        'prorrogas_restantes',case when h.etapa_sla_id is not null then greatest(h.prorroga_max-h.usadas,0) end,
        'politica_prorroga_id',h.politica_prorroga,'politica_techo_id',h.politica_techo,
        'techo_origen',case when h.politica_techo is null then null when h.politica_prorroga is not null then 'episodio' else 'adopcion' end,
        'techo_en',v_techo,'limite_operativo_en',v_operativo,'fuera_plazo',p_ahora>=h.limite_original,
        'episodios_en_ciclo',case when h.etapa_sla_id is not null then h.ingresos end,
        'revision_requerida',v_revision,'motivos_revision',to_jsonb(v_revision_motivos))
    );

    -- Dos perspectivas de la MISMA fila. La ventana elige segun capacidad.
    v_accion:=null; v_sup:=null; v_bucket:=null; v_prioridad:=null;
    v_severidad:=null; v_accion_en:=null; v_tarea:=null; v_primera:=null;
    if v_usable and h.vendedor_id is not null then
      -- Modelo 3: primera gestión del responsable actual. La respuesta real
      -- del cliente y los hitos del ciclo permanecen en base para métricas/v1.
      v_primera:=case when h.asignacion_coherente is true
        and h.base->>'asignacion_primera_gestion_en' is null
        and isfinite((h.base->>'asignacion_primera_gestion_limite_en')::timestamptz)
        then (h.base->>'asignacion_primera_gestion_limite_en')::timestamptz end;
      if estado->>'evaluacion'='parcial' then
        v_bucket:='datos_incompletos';v_prioridad:=60;v_accion_en:=h.creado_en;v_severidad:='media';
      elsif h.primera_agenda is not null and (h.primera_agenda->>'vence_en')::timestamptz<=p_ahora then
        v_bucket:='tarea_vencida';v_prioridad:=20;v_tarea:=h.primera_agenda;v_severidad:='critica';
      elsif v_primera is not null then
        v_bucket:='primera_atencion';v_prioridad:=10;v_accion_en:=v_primera;
        v_severidad:=case when p_ahora>=v_primera then 'critica' else 'media' end;
      elsif v_seguimiento_operativo then
        v_bucket:='seguimiento';v_prioridad:=40;v_accion_en:=v_seguimiento_limite;v_severidad:='media';
      elsif h.primera_agenda is not null
        and ((h.primera_agenda->>'vence_en')::timestamptz at time zone 'America/Lima')::date=(p_ahora at time zone 'America/Lima')::date then
        v_bucket:='tarea_hoy';v_prioridad:=30;v_tarea:=h.primera_agenda;v_severidad:='media';
      elsif h.primera_agenda is not null then
        v_bucket:='proxima_tarea';v_prioridad:=70;v_tarea:=h.primera_agenda;v_severidad:='baja';
      end if;
      if v_bucket is not null then
        v_accion:=jsonb_build_object('lead_id',h.lead_id,'bucket',v_bucket,'severidad',v_severidad,
          'prioridad',v_prioridad,'referencia_en',coalesce(v_accion_en,(v_tarea->>'vence_en')::timestamptz),
          'tarea_id',v_tarea->>'id');
      end if;
    end if;
    v_sup:=v_accion;
    if v_usable and h.vendedor_id is null then
      v_sup:=jsonb_build_object('lead_id',h.lead_id,'bucket','por_repartir','severidad','media',
        'prioridad',0,'referencia_en',h.creado_en,'tarea_id',null);
    elsif v_usable and v_revision and (v_prioridad is null or v_prioridad>50) then
      v_sup:=jsonb_build_object('lead_id',h.lead_id,'bucket','revision_comercial','severidad','critica',
        'prioridad',50,'referencia_en',coalesce(v_operativo,h.etapa_inicio,h.creado_en),
        'tarea_id',v_compromiso->>'id');
    end if;
    senales:=jsonb_build_object(
      'primera_atencion',v_usable and coalesce(p_ahora>=v_primera,false),
      'tareas_vencidas',v_usable and coalesce((h.primera_agenda->>'vence_en')::timestamptz<=p_ahora,false),
      'seguimientos_pendientes',v_usable and coalesce(v_seguimiento_operativo,false),
      'revisiones',v_usable and coalesce(v_revision,false),
      'datos_incompletos',v_usable and estado->>'evaluacion'='parcial',
      'por_repartir',v_usable and h.vendedor_id is null
    );
    -- Avisos independientes: una actividad vencida no queda oculta por la
    -- cobertura del seguimiento ni por la prioridad de primera atencion.
    -- Son proyecciones de las decisiones anteriores, sin otro reloj ni SLA.
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',md5(jsonb_build_array(h.lead_id,h.ciclo_n,h.asignacion_id,h.etapa_sla_id,
        a.bucket,a.tarea_id,a.referencia_en)::text),
      'lead_id',h.lead_id,'bucket',a.bucket,'prioridad',a.prioridad,
      'severidad',a.severidad,'referencia_en',a.referencia_en,'tarea_id',a.tarea_id,
      'solo_supervision',a.solo_supervision) order by a.prioridad),'[]'::jsonb)
      into v_avisos
    from (values
      ('por_repartir',0,'media',h.creado_en,null::text,true,
        (senales->>'por_repartir')::boolean),
      ('primera_atencion',10,'critica',v_primera,null::text,false,
        (senales->>'primera_atencion')::boolean),
      ('tarea_vencida',20,'critica',(h.primera_agenda->>'vence_en')::timestamptz,h.primera_agenda->>'id',false,
        (senales->>'tareas_vencidas')::boolean),
      ('seguimiento',40,'media',v_seguimiento_limite,null::text,false,
        (senales->>'seguimientos_pendientes')::boolean),
      ('revision_comercial',50,'critica',coalesce(v_operativo,h.etapa_inicio,h.creado_en),v_compromiso->>'id',true,
        (senales->>'revisiones')::boolean),
      ('datos_incompletos',60,'media',h.creado_en,null::text,false,
        (senales->>'datos_incompletos')::boolean)
    ) a(bucket,prioridad,severidad,referencia_en,tarea_id,solo_supervision,pendiente)
    where a.pendiente is true;
    select a.value into v_principal from jsonb_array_elements(v_avisos) a
      where a.value->>'bucket'=v_accion->>'bucket' limit 1;
    select min(c.en) into v_cambio from (values
      (v_primera),(v_seguimiento_limite),(v_hasta),(v_operativo),(v_techo),
      ((h.primera_agenda->>'vence_en')::timestamptz),
      (case when h.primera_agenda is not null
        then (((p_ahora at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima') end)
    ) c(en) where v_usable and isfinite(c.en) and c.en>p_ahora;
    estado:=estado||jsonb_build_object('avisos',v_avisos,'operacion',jsonb_build_object(
      'modelo',3,'aviso_principal',v_principal,
      'proxima_accion',case when v_usable and h.asignacion_coherente is true then h.primera_agenda end,
      'proximo_cambio_en',v_cambio));

    presentacion:=jsonb_build_object('id',h.lead_id,'nombre_completo',h.nombre_completo,
      'etapa',h.etapa_actual,'analista_id',h.vendedor_id,'analista_nombre',h.analista_nombre);
    lead_id:=h.lead_id;accion_atencion:=v_accion;accion_supervision:=v_sup;
    return next;
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.sla_operacion_autorizada(p_lead_ids uuid[], p_incluir_operacion boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=(select auth.uid()); v_rol text; v_global boolean; v_visibles uuid[];
  v_ahora timestamptz:=statement_timestamp(); v_filas jsonb;
  v_control crm.sla_operacion_control%rowtype; v_politica uuid; v_version integer;
begin
  v_rol:=private.rol_crm(v_uid);
  v_global:=private.es_lector_global();
  if v_uid is null or (v_rol is null and not coalesce(v_global,false)) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_incluir_operacion is null or array_position(p_lead_ids,null) is not null then
    raise exception 'Entrada SLA invalida' using errcode='22023';
  end if;
  v_global:=(v_rol='gerencia') or coalesce(v_global,false);
  v_visibles:=array(select x from private.vendedor_ids_visibles(v_uid) x order by x);
  if not p_incluir_operacion then
    select coalesce(jsonb_agg(h.base order by h.lead_id),'[]'::jsonb) into v_filas
    from private.sla_hechos_actuales(p_lead_ids,v_global,v_visibles) h where h.base is not null;
    return v_filas;
  end if;
  select * into strict v_control from crm.sla_operacion_control where id;
  select p.politica_id,p.version into v_politica,v_version from private.sla_politica_operativa(v_ahora) p;
  select coalesce(jsonb_agg(jsonb_build_object('estado',jsonb_set(s.estado,'{avisos}',a.avisos)
      ||jsonb_build_object('avisos_mostrados',a.mostrados),
    'senales',s.senales||jsonb_build_object('pendientes',jsonb_array_length(a.avisos)>0,
      'revisiones',(v_global or v_rol='supervisor') and (s.senales->>'revisiones')::boolean,
      'por_repartir',(v_global or v_rol='supervisor') and (s.senales->>'por_repartir')::boolean),
    'accion_pendiente',a.mostrados->0,
    'lead',s.presentacion,'accion_revision',s.accion_supervision,'accion',
    case when v_global or v_rol='supervisor' then s.accion_supervision else s.accion_atencion end)
    order by s.lead_id),'[]'::jsonb) into v_filas
  from private.sla_operacion_leads(p_lead_ids,v_global,v_visibles,v_ahora) s
  cross join lateral (
    select coalesce(jsonb_agg(av.value order by (av.value->>'prioridad')::integer),'[]'::jsonb) as avisos,
      coalesce(jsonb_agg(av.value order by
        case when av.value->>'id'=s.estado#>>'{operacion,aviso_principal,id}' then 0 else 1 end,
        (av.value->>'prioridad')::integer) filter (where
          av.value->>'id'=s.estado#>>'{operacion,aviso_principal,id}'
          or (av.value->>'solo_supervision')::boolean is true),'[]'::jsonb) as mostrados
    from jsonb_array_elements(s.estado->'avisos') av
    where v_global or v_rol='supervisor' or (av.value->>'solo_supervision')::boolean is false
  ) a;
  return jsonb_build_object('version',2,'modelo_avisos',3,
    'proximo_cambio_en',(select min((f.value#>>'{estado,operacion,proximo_cambio_en}')::timestamptz)
      from jsonb_array_elements(v_filas) f),
    'modo',v_control.modo,'control_revision',v_control.revision,
    'calculado_en',v_ahora,'primera_activacion_en',v_control.primera_activacion_en,
    'activacion_hipotetica_en',case when v_control.primera_activacion_en is null and v_control.modo='observacion' then v_ahora end,
    'politica_operativa_id',v_politica,'politica_operativa_version',v_version,
    'politica_adopcion_id',v_control.politica_adopcion_id,'filas',v_filas,
    'contexto_ambito',md5(jsonb_build_object('actor',v_uid,'rol',v_rol,'global',v_global,'visibles',v_visibles)::text));
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.cola_accion_v2_fn(p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_datos jsonb;v_totales jsonb;v_total integer;v_items jsonb;v_filtradas jsonb;
  v_filtros jsonb;v_contexto text;v_prioridad integer;v_referencia timestamptz;v_lead uuid;
  v_restantes integer;v_anteriores integer;v_siguiente jsonb;v_ultima jsonb;
begin
  if p_limite is null or p_limite not between 1 and 200
    or private.sla_filtros_cola_validos(p_senal,p_etapa) is not true then
    raise exception 'Filtros SLA invalidos o limite fuera de 1 a 200' using errcode='22023';
  end if;
  -- La ventana resuelve autoridad, hechos y reloj. Los filtros solo reducen
  -- las filas recibidas; un cursor es posicion de lectura, nunca autoridad.
  v_datos:=private.sla_operacion_autorizada(null,true);
  v_filtros:=jsonb_build_object('senal',p_senal,'etapa',p_etapa,'analista_id',p_analista_id);
  v_contexto:=md5(jsonb_build_object('version',2,'modelo_avisos',v_datos->'modelo_avisos','ambito',v_datos->'contexto_ambito',
    'filtros',v_filtros,'limite',p_limite,'modo',v_datos->'modo',
    'orden',(select md5(coalesce(jsonb_agg(jsonb_build_array(f.value#>>'{lead,id}',
      f.value->'accion',f.value->'accion_pendiente',f.value->'senales')
      order by f.value#>>'{lead,id}'),'[]'::jsonb)::text)
      from jsonb_array_elements(v_datos->'filas') f),
    'revision',v_datos->'control_revision','politica',v_datos->'politica_operativa_id')::text);
  if p_cursor is not null then
    if jsonb_typeof(p_cursor)<>'object' then
      raise exception 'Cursor SLA invalido' using errcode='22023';
    end if;
    if (select count(*) from jsonb_object_keys(p_cursor))<>5
      or not p_cursor ?& array['version','contexto','prioridad','referencia_en','lead_id']
      or p_cursor->'version'<>'1'::jsonb
      or jsonb_typeof(p_cursor->'contexto')<>'string'
      or jsonb_typeof(p_cursor->'prioridad')<>'number'
      or jsonb_typeof(p_cursor->'referencia_en') not in ('string','null')
      or jsonb_typeof(p_cursor->'lead_id')<>'string' then
      raise exception 'Cursor SLA invalido' using errcode='22023';
    end if;
    if p_cursor->>'contexto' is distinct from v_contexto then
      raise exception 'Cursor incompatible; reinicia la paginacion' using errcode='22023';
    end if;
    begin
      v_prioridad:=(p_cursor->>'prioridad')::integer;
      v_referencia:=(p_cursor->>'referencia_en')::timestamptz;
      v_lead:=(p_cursor->>'lead_id')::uuid;
      if (p_cursor->>'prioridad') !~ '^[0-9]+$'
        or v_prioridad not in (0,10,20,30,40,50,60,70)
        or v_lead is null or (v_referencia is not null and not isfinite(v_referencia)) then
        raise exception 'Cursor SLA invalido' using errcode='22023';
      end if;
    exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format or numeric_value_out_of_range then
      raise exception 'Cursor SLA invalido' using errcode='22023';
    end;
  end if;
  select coalesce(jsonb_agg(f.value),'[]'::jsonb) into v_filtradas
  from jsonb_array_elements(v_datos->'filas') f
  where (p_etapa is null or f.value#>>'{lead,etapa}'=p_etapa)
    and (p_analista_id is null or f.value#>>'{lead,analista_id}'=p_analista_id::text);
  select jsonb_build_object(
    'pendientes',count(*) filter (where (f.value#>>'{senales,pendientes}')::boolean),
    'primera_atencion',count(*) filter (where (f.value#>>'{senales,primera_atencion}')::boolean),
    'tareas_vencidas',count(*) filter (where (f.value#>>'{senales,tareas_vencidas}')::boolean),
    'seguimientos_pendientes',count(*) filter (where (f.value#>>'{senales,seguimientos_pendientes}')::boolean),
    'revisiones',count(*) filter (where (f.value#>>'{senales,revisiones}')::boolean),
    'datos_incompletos',count(*) filter (where (f.value#>>'{senales,datos_incompletos}')::boolean),
    'por_repartir',count(*) filter (where (f.value#>>'{senales,por_repartir}')::boolean))
  into v_totales from jsonb_array_elements(v_filtradas) f;
  with candidatos as (
    select f.value,
      case when p_senal='pendientes' then f.value->'accion_pendiente'
        when p_senal='todas' then f.value->'accion'
        else coalesce((select a.value from jsonb_array_elements(f.value#>'{estado,avisos}') a
          where a.value->>'bucket'=case p_senal
            when 'tareas_vencidas' then 'tarea_vencida' when 'seguimientos_pendientes' then 'seguimiento'
            when 'revisiones' then 'revision_comercial' else p_senal end limit 1),
          nullif(f.value->'accion','null'::jsonb),f.value->'accion_revision') end as accion
    from jsonb_array_elements(v_filtradas) f
    where (p_senal='todas' and f.value->'accion'<>'null'::jsonb)
      or (p_senal<>'todas' and (f.value->'senales'->>p_senal)::boolean is true)
  )
  select coalesce(jsonb_agg(c.accion||jsonb_build_object(
    'estado',c.value->'estado','lead',c.value->'lead','senales',c.value->'senales')),'[]'::jsonb)
    into v_filtradas from candidatos c;
  v_total:=jsonb_array_length(v_filtradas);
  with ordenadas as (
    select f.value,(f.value->>'prioridad')::integer as prioridad,
      (f.value->>'referencia_en')::timestamptz as referencia,(f.value->>'lead_id')::uuid as lead_id
    from jsonb_array_elements(v_filtradas) f
  ), posteriores as (
    select o.* from ordenadas o where p_cursor is null or
      (o.prioridad,coalesce(o.referencia,'infinity'::timestamptz),o.lead_id)>
      (v_prioridad,coalesce(v_referencia,'infinity'::timestamptz),v_lead)
  ), pagina as (
    select p.* from posteriores p order by p.prioridad,p.referencia nulls last,p.lead_id limit p_limite
  )
  select (select count(*) from posteriores),
    coalesce((select jsonb_agg(p.value order by p.prioridad,p.referencia nulls last,p.lead_id) from pagina p),'[]'::jsonb)
    into v_restantes,v_items;
  v_anteriores:=v_total-v_restantes;
  if v_restantes>p_limite then
    v_ultima:=v_items->(jsonb_array_length(v_items)-1);
    v_siguiente:=jsonb_build_object('version',1,'contexto',v_contexto,'prioridad',v_ultima->'prioridad',
      'referencia_en',v_ultima->'referencia_en','lead_id',v_ultima->'lead_id');
  end if;
  return jsonb_build_object('version',2,'modelo_avisos',v_datos->'modelo_avisos',
    'proximo_cambio_en',v_datos->'proximo_cambio_en','modo',v_datos->'modo','control_revision',v_datos->'control_revision',
    'calculado_en',v_datos->'calculado_en','politica_operativa_id',v_datos->'politica_operativa_id',
    'politica_operativa_version',v_datos->'politica_operativa_version',
    'total_items',v_total,'hay_mas',v_restantes>p_limite,'totales',v_totales,'items',v_items,
    'filtros',v_filtros,'limite',p_limite,'cursor_siguiente',v_siguiente,
    'rango',jsonb_build_object('desde',case when jsonb_array_length(v_items)=0 then 0 else v_anteriores+1 end,
      'hasta',case when jsonb_array_length(v_items)=0 then 0 else v_anteriores+jsonb_array_length(v_items) end));
end;
$function$
;

select private.assert_sla_nucleo();
commit;
