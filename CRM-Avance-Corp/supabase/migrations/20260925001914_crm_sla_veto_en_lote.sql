-- SLA: el veto de contacto se consulta UNA vez por lote, no lead por lead.
--
-- Por qué: las cuatro RPC que se quedan sin tiempo (avisos_sla_resumen_v2_fn,
-- cola_accion_v2_fn, gestion_diaria_avisos_fn y gestion_diaria_equipo_fn; ~60
-- tiempos agotados al día contra el tope de 8 s) pasan todas por
-- private.sla_operacion_autorizada → private.sla_operacion_leads. Medido en
-- producción el 24/09/2026 sobre la cartera global (2302 leads):
--   private.sla_operacion_leads ................... 6 628 ms
--     de eso, 2302 × private.persona_vetada(id) ... 5 658 ms
--   private.leads_vetados_persona(todos) en lote ...    57 ms
--
-- Qué cambia: solo cómo se calcula la columna `vetado`. Antes, una llamada a
-- persona_vetada(id) por fila; ahora, una llamada a leads_vetados_persona con
-- todos los leads del lote. Es el mismo predicado: persona_vetada(id) ES
-- exists(leads_vetados_persona(array[id])), y ese predicado mira un lead a la
-- vez. El resto del cuerpo es byte a byte el vivo (md5 6151f055…).
--
-- Cómo se prueba aquí mismo: antes de reemplazar, una función CANDIDATA con el
-- cuerpo nuevo se compara con la vieja en UNA sola sentencia: las lecturas de las
-- funciones STABLE comparten la foto de esa sentencia, y la bandera
-- resolver_en_puertas queda fija por su candado compartido (D-19: todo escritor
-- de la bandera toma el exclusivo). Así no hay falsos rojos por escrituras
-- concurrentes. Dos ámbitos:
-- la cartera global y la lista explícita de todos los leads con p_global=false.
-- Una sola fila distinta aborta la migración. La candidata muere antes del commit.
--
-- Reversa: supabase/scripts/rollback-sla-veto-en-lote.sql (repone el cuerpo
-- vivo 6151f055…, con su preflight y postflight).
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';

do $preflight$ begin
  if md5(pg_get_functiondef('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)'::regprocedure))<>'6151f05563abd1b9cf3cd58e60596086' then
    raise exception 'SLA: cambió la fuente sla_operacion_leads';
  end if;
  if md5(pg_get_functiondef('private.persona_vetada(uuid)'::regprocedure))<>'a70efe776fc56fd34d47e364e2e55571' then
    raise exception 'SLA: cambió la fuente persona_vetada';
  end if;
  if md5(pg_get_functiondef('private.leads_vetados_persona(uuid[])'::regprocedure))<>'06edc44442b249c2baf2a9a11f68b2ff' then
    raise exception 'SLA: cambió la fuente leads_vetados_persona';
  end if;
  if to_regprocedure('private.sla_operacion_leads_candidata(uuid[],boolean,uuid[],timestamptz)') is not null then
    raise exception 'SLA: ya existe una candidata; limpiar antes de seguir';
  end if;
  perform private.assert_sla_nucleo();
  perform private.assert_sla_avisos();
end; $preflight$;

-- 1) Candidata: el cuerpo nuevo con otro nombre (muere antes del commit).
CREATE FUNCTION private.sla_operacion_leads_candidata(p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamp with time zone)
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
    ), vetados as materialized (
      -- El veto de contacto va en UNA llamada por lote. Consultarlo fila por fila
      -- se llevaba 5,7 de los 6,6 s de la cartera global (medido el 24/09/2026).
      select v.id from private.leads_vetados_persona(array(select x.lead_id from hechos x)) as v(id)
    )
    select f.*, r.seguimiento_minutos,r.pausa_habilitada,r.pausa_margen_minutos,
      er.politica_id as politica_prorroga,coalesce(er.prorroga_max,0) as prorroga_max,
      coalesce(er.tope_extra_minutos,ar.tope_extra_minutos) as extra,
      coalesce(er.politica_id,ar.politica_id) as politica_techo,
      a.creado_en as ultima_gestion_en,a.tipo as ultima_gestion_tipo,
      a.creado_por as autor_id,a.autor_nombre,
      j.minutos,j.usadas,j.ingresos,
      t.motivos_tarea,t.primera_comercial,t.primera_agenda,
      exists (select 1 from vetados vt where vt.id=f.lead_id) as vetado
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

-- 2) Paridad en UNA sentencia: la vieja y la candidata ven la misma foto.
create temporary table sla_veto_paridad on commit drop as
with ambitos(n, ids, global, visibles) as (
  select 1, null::uuid[], true, '{}'::uuid[]
  union all
  select 2, (select array_agg(l.id order by l.id) from crm.leads l), false,
    (select coalesce(array_agg(distinct x.id order by x.id), '{}'::uuid[]) from (
       select l.vendedor_id as id from crm.leads l where l.vendedor_id is not null
       union
       select l.asignado_supervisor_id from crm.leads l where l.asignado_supervisor_id is not null) x)
), vieja as (
  select a.n, s.* from ambitos a
  cross join lateral private.sla_operacion_leads(a.ids, a.global, a.visibles, now()) s
), nueva as (
  select a.n, s.* from ambitos a
  cross join lateral private.sla_operacion_leads_candidata(a.ids, a.global, a.visibles, now()) s
)
select coalesce(v.n, c.n) as ambito,
  count(*) as filas,
  count(*) filter (where v.lead_id is null or c.lead_id is null
    or (v.estado, v.accion_atencion, v.accion_supervision, v.senales, v.presentacion)
       is distinct from (c.estado, c.accion_atencion, c.accion_supervision, c.senales, c.presentacion)) as distintas,
  count(*) filter (where v.estado->'motivos_datos' ? 'restriccion_contacto') as vetadas
from vieja v
full join nueva c on c.n = v.n and c.lead_id = v.lead_id
group by 1;

do $paridad$
declare v_distintas bigint; v_filas bigint; v_ambitos integer; v_vetadas bigint;
begin
  select coalesce(sum(p.distintas),0), coalesce(sum(p.filas),0), count(*), coalesce(sum(p.vetadas),0)
    into v_distintas, v_filas, v_ambitos, v_vetadas from pg_temp.sla_veto_paridad p;
  if v_ambitos <> 2 or v_filas = 0 then
    raise exception 'SLA: paridad vacía (ámbitos %, filas %): no prueba nada', v_ambitos, v_filas;
  end if;
  -- La columna que cambia es `vetado`: sin ningún lead vetado en el lote, la
  -- paridad no diría nada de ella (el 24/09 prod tenía 10).
  if v_vetadas = 0 then
    raise exception 'SLA: ningún lead vetado en la paridad: no ejercita la columna que cambia';
  end if;
  if v_distintas <> 0 then
    raise exception 'SLA: la candidata difiere de la vieja en % filas', v_distintas;
  end if;
end; $paridad$;

-- 3) El reemplazo: mismo cuerpo que la candidata ya probada.
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
    ), vetados as materialized (
      -- El veto de contacto va en UNA llamada por lote. Consultarlo fila por fila
      -- se llevaba 5,7 de los 6,6 s de la cartera global (medido el 24/09/2026).
      select v.id from private.leads_vetados_persona(array(select x.lead_id from hechos x)) as v(id)
    )
    select f.*, r.seguimiento_minutos,r.pausa_habilitada,r.pausa_margen_minutos,
      er.politica_id as politica_prorroga,coalesce(er.prorroga_max,0) as prorroga_max,
      coalesce(er.tope_extra_minutos,ar.tope_extra_minutos) as extra,
      coalesce(er.politica_id,ar.politica_id) as politica_techo,
      a.creado_en as ultima_gestion_en,a.tipo as ultima_gestion_tipo,
      a.creado_por as autor_id,a.autor_nombre,
      j.minutos,j.usadas,j.ingresos,
      t.motivos_tarea,t.primera_comercial,t.primera_agenda,
      exists (select 1 from vetados vt where vt.id=f.lead_id) as vetado
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

-- La candidata probada y el cuerpo instalado son el MISMO texto.
do $identidad$ begin
  if (select p.prosrc from pg_proc p where p.oid = 'private.sla_operacion_leads_candidata(uuid[],boolean,uuid[],timestamptz)'::regprocedure)
     is distinct from
     (select p.prosrc from pg_proc p where p.oid = 'private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)'::regprocedure) then
    raise exception 'SLA: el cuerpo instalado no es el que pasó la paridad';
  end if;
end; $identidad$;

drop function private.sla_operacion_leads_candidata(uuid[],boolean,uuid[],timestamptz);

do $postflight$ begin
  if md5(pg_get_functiondef('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)'::regprocedure))<>'12749d608bb0a296f763e000f18c03de' then
    raise exception 'SLA: el cuerpo instalado no es el previsto';
  end if;
  if to_regprocedure('private.sla_operacion_leads_candidata(uuid[],boolean,uuid[],timestamptz)') is not null then
    raise exception 'SLA: la candidata sigue viva';
  end if;
  perform private.assert_sla_nucleo();
  perform private.assert_sla_avisos();
end; $postflight$;

-- 4) La medida, ya con el cuerpo nuevo (el veredicto viaja como FILA).
create temporary table sla_veto_medida on commit drop as
select 0::bigint as ms, 0::bigint as filas;
do $medida$
declare t0 timestamptz; n bigint;
begin
  t0 := clock_timestamp();
  select count(*) into n from private.sla_operacion_leads(null, true, '{}'::uuid[], now());
  update pg_temp.sla_veto_medida
     set ms = (extract(epoch from clock_timestamp() - t0) * 1000)::bigint, filas = n;
end; $medida$;

select 'SLA_VETO_EN_LOTE_OK' as veredicto,
  (select string_agg(format('ámbito %s: %s filas, %s distintas, %s vetadas', ambito, filas, distintas, vetadas), ' · ' order by ambito)
     from pg_temp.sla_veto_paridad) as paridad,
  (select format('%s filas en %s ms', filas, ms) from pg_temp.sla_veto_medida) as medida_global;
commit;
