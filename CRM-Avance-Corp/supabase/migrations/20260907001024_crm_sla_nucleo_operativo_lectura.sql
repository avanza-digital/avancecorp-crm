-- SLA-R2 / N1: nucleo de lectura. No publica reglas, activa el modulo ni
-- concede prorrogas. Captura, comandos y configuracion se entregan despues.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
begin
  if to_regprocedure('crm.estado_sla_leads_fn()') is null
     or to_regprocedure('private.sla_politica_vigente(timestamptz)') is null
     or to_regprocedure('private.persona_vetada(uuid)') is null then
    raise exception 'SLA N1: faltan las fuentes canonicas';
  end if;
  if md5(pg_get_functiondef('crm.estado_sla_leads_fn()'::regprocedure))
     <> '11808483d300a97fb6ff8b3be2dab1fa' then
    raise exception 'SLA N1: estado v1 cambio; reconciliar antes de instalar';
  end if;
end;
$preflight$;

create temporary table sla_n1_fuentes on commit drop as
select p.oid, p.proowner, p.proacl, pg_get_functiondef(p.oid) as definicion
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where (n.nspname='private' and p.proname in ('rol_crm','es_lector_global','vendedor_ids_visibles',
  'sla_politica_vigente','persona_vetada','metricas_sla_global_core','citas_episodios','conversion_episodios','capital_episodios'))
  or p.oid='crm.estado_sla_leads_fn()'::regprocedure;

-- Entradas persistidas del dominio. Sin politica inicial ni acceso API directo.
create table crm.sla_politica_etapas_operacion (
  politica_id uuid not null,
  etapa text not null,
  seguimiento_minutos integer not null check (seguimiento_minutos between 1 and 43200),
  prorroga_minutos integer not null check (prorroga_minutos = 0 or prorroga_minutos between 1441 and 43200),
  prorroga_max integer not null check (prorroga_max between 0 and 5),
  tope_extra_minutos integer not null check (tope_extra_minutos between 0 and 43200),
  pausa_habilitada boolean not null,
  pausa_margen_minutos integer not null check (pausa_margen_minutos between 0 and 10080),
  primary key (politica_id, etapa),
  foreign key (politica_id, etapa) references crm.sla_politica_etapas(politica_id, etapa) on delete restrict,
  check ((prorroga_minutos = 0) = (prorroga_max = 0)),
  check (prorroga_max = 0 or tope_extra_minutos > 0),
  check (etapa in ('contactado','propuesta_enviada') or prorroga_max = 0),
  check (pausa_habilitada or pausa_margen_minutos = 0)
);

create table crm.lead_sla_etapa_ajustes (
  id uuid primary key default gen_random_uuid(),
  etapa_sla_id uuid not null references crm.lead_sla_etapas(id) on delete restrict,
  origen_actividad_id uuid not null references crm.actividades(id) on delete restrict,
  secuencia integer not null check (secuencia > 0),
  minutos_reales integer not null check (minutos_reales > 0),
  limite_antes timestamptz not null check (isfinite(limite_antes)),
  limite_despues timestamptz not null check (isfinite(limite_despues)),
  creado_por uuid not null references public.perfiles(id) on delete restrict,
  creado_en timestamptz not null default clock_timestamp() check (isfinite(creado_en)),
  unique (etapa_sla_id, origen_actividad_id),
  unique (etapa_sla_id, secuencia),
  check (limite_despues = limite_antes + minutos_reales * interval '1 minute')
);
create index lead_sla_etapa_ajustes_actividad_idx on crm.lead_sla_etapa_ajustes(origen_actividad_id);
create index lead_sla_etapa_ajustes_autor_idx on crm.lead_sla_etapa_ajustes(creado_por);

create table crm.tarea_sla_contexto (
  tarea_id uuid primary key references crm.tareas(id) on delete restrict,
  lead_id uuid not null,
  ciclo_n integer not null,
  fuente text not null check (fuente in ('evento','reconstruido')),
  registrado_en timestamptz not null default clock_timestamp() check (isfinite(registrado_en)),
  foreign key (lead_id, ciclo_n) references crm.lead_sla_ciclos(lead_id, ciclo_n) on delete restrict
);
create index tarea_sla_contexto_ciclo_idx on crm.tarea_sla_contexto(lead_id, ciclo_n);

create table crm.sla_operacion_control (
  id boolean primary key default true check (id),
  modo text not null default 'legado' check (modo in ('legado','observacion','activo')),
  revision integer not null default 0 check (revision >= 0),
  primera_activacion_en timestamptz check (isfinite(primera_activacion_en)),
  politica_adopcion_id uuid references crm.sla_politicas(id) on delete restrict,
  cambiado_por uuid references public.perfiles(id) on delete restrict,
  cambiado_en timestamptz not null default clock_timestamp() check (isfinite(cambiado_en)),
  check ((primera_activacion_en is null) = (politica_adopcion_id is null)),
  check (modo <> 'activo' or primera_activacion_en is not null)
);

-- Solo el propietario de migracion puede sembrar estos hechos en N1.
-- No se instala un writer de captura ni se concede un ajuste automaticamente.
create function private.trg_sla_nucleo_entrada_guard()
returns trigger language plpgsql security invoker set search_path = ''
as $function$
declare v_lead uuid;
begin
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'Los hechos SLA no se borran' using errcode='55000';
  end if;
  if tg_table_name = 'sla_operacion_control' then
    if tg_op = 'UPDATE' and (
      (old.primera_activacion_en is not null and
       (new.primera_activacion_en is distinct from old.primera_activacion_en
        or new.politica_adopcion_id is distinct from old.politica_adopcion_id))
      or new.revision <> old.revision + 1
    ) then
      raise exception 'Adopcion inmutable o revision invalida' using errcode='55000';
    end if;
    if new.politica_adopcion_id is not null and
       (select count(*) from crm.sla_politica_etapas_operacion r
        where r.politica_id=new.politica_adopcion_id) <> 4 then
      raise exception 'La adopcion requiere cuatro reglas completas' using errcode='23514';
    end if;
  elsif tg_op = 'UPDATE' then
    raise exception 'Entrada SLA inmutable' using errcode='55000';
  elsif tg_table_name = 'sla_politica_etapas_operacion' then
    if exists (select 1 from crm.lead_sla_etapas e where e.politica_id=new.politica_id) then
      raise exception 'Una politica usada por episodios no admite reglas retroactivas' using errcode='55000';
    end if;
  elsif tg_table_name = 'tarea_sla_contexto' then
    select t.lead_id into v_lead from crm.tareas t where t.id=new.tarea_id;
    if v_lead is distinct from new.lead_id then
      raise exception 'Contexto ajeno a la tarea' using errcode='23514';
    end if;
  elsif tg_table_name = 'lead_sla_etapa_ajustes' then
    if not exists (
      select 1 from crm.lead_sla_etapas e join crm.actividades a on a.id=new.origen_actividad_id
      where e.id=new.etapa_sla_id and e.lead_id=a.lead_id
        and a.creado_por=new.creado_por
    ) then
      raise exception 'Ajuste sin correspondencia actividad/episodio/autor' using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_sla_nucleo_entrada_guard() from public,anon,authenticated,service_role;

do $tables$
declare v_name text;
begin
  foreach v_name in array array['sla_politica_etapas_operacion','lead_sla_etapa_ajustes','tarea_sla_contexto','sla_operacion_control'] loop
    execute format('alter table crm.%I enable row level security', v_name);
    execute format('revoke all on table crm.%I from public,anon,authenticated,service_role', v_name);
    execute format('create trigger trg_sla_nucleo_guard before insert or update or delete on crm.%I for each row execute function private.trg_sla_nucleo_entrada_guard()', v_name);
    execute format('create trigger trg_sla_nucleo_no_truncate before truncate on crm.%I for each statement execute function private.trg_sla_nucleo_entrada_guard()', v_name);
    execute format('create trigger trg_audit_%I after insert or update or delete on crm.%I for each row execute function private.log_audit_crm()', v_name, v_name);
  end loop;
end;
$tables$;
insert into crm.sla_operacion_control(id) values(true);

comment on table crm.sla_politica_etapas_operacion is 'SLA-R2: reglas de una version publicada. N1 no publica ninguna; solo lectura por el nucleo.';
comment on table crm.lead_sla_etapa_ajustes is 'SLA-R2: hechos de prorroga con causa. N1 no concede ni captura ajustes.';
comment on table crm.tarea_sla_contexto is 'SLA-R2: ciclo causal de tareas. N1 no reconstruye ni captura stock; ausencia no equivale a contexto valido.';
comment on table crm.sla_operacion_control is 'SLA-R2: control inicial legado. N1 no expone una puerta de activacion.';

-- Proyeccion comun. No autoriza: aplica un ambito ya resuelto por la ventana.
create function private.sla_hechos_actuales(p_lead_ids uuid[], p_global boolean, p_visibles uuid[])
returns table (
  lead_id uuid, etapa_actual text, vendedor_id uuid, supervisor_id uuid,
  creado_en timestamptz, ciclo_n integer, ciclo_inicio timestamptz,
  asignacion_id uuid, asignacion_inicio timestamptz, etapa_sla_id uuid,
  etapa_inicio timestamptz, limite_original timestamptz, politica_etapa_id uuid,
  base jsonb, activo boolean, asignacion_coherente boolean, etapa_coherente boolean,
  nombre_completo text, analista_nombre text
)
language sql stable security invoker set search_path = ''
as $function$
  select l.id, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.creado_en,
    l.ciclo_actual, c.iniciado_en, a.id, a.asignado_en, e.id, e.iniciado_en,
    e.limite_en, e.politica_id,
    case when c.id is null or pc.id is null then null else jsonb_build_object(
      'lead_id',l.id,
      'ciclo_politica_id',c.politica_id,'ciclo_politica_version',pc.version,
      'primera_gestion_limite_en',c.primera_gestion_limite_en,'primera_gestion_en',c.primera_gestion_en,
      'primer_contacto_limite_en',c.primer_contacto_limite_en,'primer_contacto_en',c.primer_contacto_en,
      'ciclo_aproximado',c.aproximado,
      'asignacion_id',a.id,'asignacion_politica_id',a.sla_politica_asignacion_id,'asignacion_politica_version',pa.version,
      'asignacion_primera_gestion_limite_en',a.primera_gestion_limite_en,'asignacion_primera_gestion_en',ah.primera_gestion_en,
      'asignacion_primer_contacto_limite_en',a.primer_contacto_limite_en,'asignacion_primer_contacto_en',ah.primer_contacto_en,
      'etapa_politica_id',e.politica_id,'etapa_politica_version',pe.version,'etapa',e.etapa,
      'etapa_iniciada_en',e.iniciado_en,'etapa_limite_en',e.limite_en,'etapa_objetivo_minutos',re.maximo_minutos,
      'etapa_aproximada',e.aproximado
    ) end,l.activo,
    a.ciclo_n=l.ciclo_actual and a.analista_id is not distinct from l.vendedor_id,
    e.etapa=l.etapa,l.nombre_completo,dueno.nombre_completo
  from crm.leads l
  left join public.perfiles dueno on dueno.id=l.vendedor_id
  left join crm.lead_sla_ciclos c on c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
  left join crm.sla_politicas pc on pc.id=c.politica_id
  left join lateral (
    select la.* from crm.lead_asignaciones la
    where la.lead_id=l.id and la.finalizado_en is null
    order by la.episodio_n desc limit 1
  ) a on true
  left join crm.sla_politicas pa on pa.id=a.sla_politica_asignacion_id
  left join crm.lead_asignacion_sla_hitos ah on ah.lead_asignacion_id=a.id
  left join crm.lead_sla_etapas e on e.lead_id=l.id and e.ciclo_n=l.ciclo_actual and e.finalizado_en is null
  left join crm.sla_politicas pe on pe.id=e.politica_id
  left join crm.sla_politica_etapas re on re.politica_id=e.politica_id and re.etapa=e.etapa
  where (l.activo is true or p_lead_ids is not null)
    and (p_lead_ids is null or l.id=any(p_lead_ids))
    and (p_global is true or l.vendedor_id=any(p_visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id=any(p_visibles)))
  order by l.id;
$function$;
revoke all on function private.sla_hechos_actuales(uuid[],boolean,uuid[]) from public,anon,authenticated,service_role;

-- Fuente de hechos de agenda del dominio, sin contadores de citas a crudo.
create function private.sla_tareas_hechos(p_lead_ids uuid[], p_global boolean, p_visibles uuid[])
returns table (lead_id uuid, tarea_id uuid, tipo text, titulo text, vence_en timestamptz,
  reprogramaciones integer, responsable_id uuid, autor_id uuid, autor_nombre text,
  contexto_fuente text, motivo_dato text)
language sql stable security invoker set search_path = ''
as $function$
  select h.lead_id,t.id,t.tipo,t.titulo,t.vence_en,t.reprogramaciones::integer,
    t.vendedor_id,t.creado_por,p.nombre_completo,c.fuente,
    case when not isfinite(t.vence_en) then 'fecha_tarea_invalida'
      when c.tarea_id is null or c.lead_id<>h.lead_id then 'contexto_tarea_ambiguo'
      when c.ciclo_n<>h.ciclo_n then 'tarea_ciclo_anterior_pendiente'
      when t.vendedor_id is distinct from h.vendedor_id
        or t.asignado_supervisor_id is distinct from h.supervisor_id then 'tenencia_tarea_incoherente'
      else null end
  from private.sla_hechos_actuales(p_lead_ids,p_global,p_visibles) h
  join crm.tareas t on t.lead_id=h.lead_id and t.activo and t.estado='pendiente'
  left join crm.tarea_sla_contexto c on c.tarea_id=t.id
  left join public.perfiles p on p.id=t.creado_por;
$function$;
revoke all on function private.sla_tareas_hechos(uuid[],boolean,uuid[]) from public,anon,authenticated,service_role;

-- Regla compartida de ganancia. Solo decide: no escribe ni autoriza.
create function private.sla_evaluar_prorroga(
  p_etapa text, p_tipo_actividad text, p_autor_id uuid, p_mismo_episodio boolean,
  p_modo text, p_primera_activacion timestamptz, p_evento_en timestamptz,
  p_limite timestamptz, p_techo timestamptz, p_duracion integer,
  p_maximo integer, p_usadas integer, p_ya_ajustada boolean
)
returns table (elegible boolean, motivo text, minutos_reales integer, limite_despues timestamptz)
language plpgsql stable security invoker set search_path = ''
as $function$
declare v_motivo text; v_ganancia integer;
begin
  if p_evento_en is null or not isfinite(p_evento_en) then
    raise exception 'Instante de evento invalido' using errcode='22023';
  end if;
  v_motivo := case
    when p_modo is distinct from 'activo' then 'modo_no_activo'
    when p_autor_id is null then 'sin_autor_humano'
    when p_mismo_episodio is distinct from true then 'episodio_distinto'
    when p_tipo_actividad is null or p_tipo_actividad not in ('llamada_realizada','whatsapp_recibido','reunion_realizada') then 'sin_conversacion'
    when p_etapa is null or p_etapa not in ('contactado','propuesta_enviada') then 'etapa_sin_prorroga'
    when p_duracion is null or p_maximo is null then 'politica_sin_reglas'
    when p_primera_activacion is null or not isfinite(p_primera_activacion) then 'sin_activacion'
    when p_evento_en<p_primera_activacion then 'evento_anterior_activacion'
    when p_ya_ajustada is true then 'evento_ya_ajustado'
    else null end;
  if v_motivo is null then
    if p_usadas is null or p_usadas<0 or p_maximo not between 0 and 5
       or p_limite is null or p_techo is null or not isfinite(p_limite) or not isfinite(p_techo)
       or p_duracion not between 0 and 43200 or (p_duracion>0 and p_duracion<=1440)
       or ((p_maximo=0) <> (p_duracion=0)) or p_ya_ajustada is null then
      raise exception 'Presupuesto de prorroga incoherente' using errcode='22023';
    end if;
    v_motivo := case when p_usadas>=p_maximo or p_limite>=p_techo then 'presupuesto_agotado'
      when p_evento_en<p_limite-interval '24 hours' or p_evento_en>=p_limite then 'fuera_ventana'
      else null end;
  end if;
  if v_motivo is not null then
    return query select false,v_motivo,0,null::timestamptz;
    return;
  end if;
  v_ganancia := least(p_duracion,floor(extract(epoch from (p_techo-p_limite))/60)::integer);
  return query select v_ganancia>0,
    case when v_ganancia>0 then 'conversacion_en_ventana' else 'presupuesto_agotado' end,
    greatest(v_ganancia,0),case when v_ganancia>0 then p_limite+v_ganancia*interval '1 minute' else null end;
end;
$function$;
revoke all on function private.sla_evaluar_prorroga(text,text,uuid,boolean,text,timestamptz,timestamptz,timestamptz,timestamptz,integer,integer,integer,boolean) from public,anon,authenticated,service_role;

-- Hecho de configuracion comun a la ventana y al evaluador. Una version parcial
-- no es operativa: se exige la presencia de cada etapa, sin fallback de version.
create function private.sla_politica_operativa(p_ahora timestamptz)
returns table (politica_id uuid, version integer)
language sql stable security invoker set search_path = ''
as $function$
  select p.id,p.version from crm.sla_politicas p
  where p.id=private.sla_politica_vigente(p_ahora)
    and not exists (
      select e.etapa from (values ('nuevo'),('contactado'),('reunion_agendada'),('propuesta_enviada')) e(etapa)
      except select r.etapa from crm.sla_politica_etapas_operacion r where r.politica_id=p.id
    );
$function$;
revoke all on function private.sla_politica_operativa(timestamptz) from public,anon,authenticated,service_role;

-- Hechos del ledger de etapas: presupuesto consumido e ingresos en el ciclo.
-- No son estadisticas de citas ni conversiones; no se lee leads o tareas aqui.
create function private.sla_etapa_hechos(p_etapa_sla_id uuid,p_lead_id uuid,p_ciclo_n integer,p_etapa text)
returns table (minutos integer,usadas integer,ingresos integer)
language sql stable security invoker set search_path = ''
as $function$
  select coalesce(sum(j.minutos_reales),0)::integer,count(*)::integer,
    (select count(*)::integer from crm.lead_sla_etapas e
     where e.lead_id=p_lead_id and e.ciclo_n=p_ciclo_n and e.etapa=p_etapa)
  from crm.lead_sla_etapa_ajustes j where j.etapa_sla_id=p_etapa_sla_id;
$function$;
revoke all on function private.sla_etapa_hechos(uuid,uuid,integer,text) from public,anon,authenticated,service_role;

create function private.sla_operacion_leads(p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamptz)
returns table (lead_id uuid, estado jsonb, accion_atencion jsonb, accion_supervision jsonb, senales jsonb, presentacion jsonb)
language plpgsql stable security invoker set search_path = ''
as $function$
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
        (jsonb_agg(jsonb_build_object('id',t.tarea_id,'vence_en',t.vence_en) order by t.vence_en,t.tarea_id)
          filter (where isfinite(t.vence_en)))->0 as primera_agenda
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
      v_primera:=least(
        case when h.base->>'primera_gestion_en' is null then (h.base->>'primera_gestion_limite_en')::timestamptz end,
        case when h.base->>'primer_contacto_en' is null then (h.base->>'primer_contacto_limite_en')::timestamptz end,
        -- La base conserva el snapshot historico para v1. Un episodio de otro
        -- ciclo o responsable no impone primera atencion al analista actual;
        -- su incoherencia sigue visible y los hitos del ciclo siguen vigentes.
        case when h.asignacion_coherente is true and h.base->>'asignacion_primera_gestion_en' is null
          then (h.base->>'asignacion_primera_gestion_limite_en')::timestamptz end,
        case when h.asignacion_coherente is true and h.base->>'asignacion_primer_contacto_en' is null
          then (h.base->>'asignacion_primer_contacto_limite_en')::timestamptz end
      );
      if v_primera is not null then
        v_bucket:='primera_atencion';v_prioridad:=10;v_accion_en:=v_primera;
        v_severidad:=case when p_ahora>=v_primera then 'critica' else 'media' end;
      elsif h.primera_agenda is not null and (h.primera_agenda->>'vence_en')::timestamptz<=p_ahora then
        v_bucket:='tarea_vencida';v_prioridad:=20;v_tarea:=h.primera_agenda;v_severidad:='critica';
      elsif h.primera_agenda is not null
        and ((h.primera_agenda->>'vence_en')::timestamptz at time zone 'America/Lima')::date=(p_ahora at time zone 'America/Lima')::date then
        v_bucket:='tarea_hoy';v_prioridad:=30;v_tarea:=h.primera_agenda;v_severidad:='media';
      elsif v_pendiente then
        v_bucket:='seguimiento';v_prioridad:=40;v_accion_en:=v_seguimiento_limite;v_severidad:='media';
      elsif estado->>'evaluacion'='parcial' then
        v_bucket:='datos_incompletos';v_prioridad:=60;v_accion_en:=h.creado_en;v_severidad:='media';
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
      'primera_atencion',v_usable and v_primera is not null,
      'tareas_vencidas',v_usable and coalesce((h.primera_agenda->>'vence_en')::timestamptz<=p_ahora,false),
      'seguimientos_pendientes',v_usable and coalesce(v_pendiente,false),
      'revisiones',v_usable and coalesce(v_revision,false),
      'datos_incompletos',v_usable and estado->>'evaluacion'='parcial',
      'por_repartir',v_usable and h.vendedor_id is null
    );
    presentacion:=jsonb_build_object('id',h.lead_id,'nombre_completo',h.nombre_completo,
      'etapa',h.etapa_actual,'analista_id',h.vendedor_id,'analista_nombre',h.analista_nombre);
    lead_id:=h.lead_id;accion_atencion:=v_accion;accion_supervision:=v_sup;
    return next;
  end loop;
end;
$function$;
revoke all on function private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz) from public,anon,authenticated,service_role;

create function private.sla_operacion_autorizada(p_lead_ids uuid[], p_incluir_operacion boolean)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
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
  select coalesce(jsonb_agg(jsonb_build_object('estado',s.estado,'senales',s.senales,
    'lead',s.presentacion,'accion_revision',s.accion_supervision,'accion',
    case when v_global or v_rol='supervisor' then s.accion_supervision else s.accion_atencion end)
    order by s.lead_id),'[]'::jsonb) into v_filas
  from private.sla_operacion_leads(p_lead_ids,v_global,v_visibles,v_ahora) s;
  return jsonb_build_object('version',2,'modo',v_control.modo,'control_revision',v_control.revision,
    'calculado_en',v_ahora,'primera_activacion_en',v_control.primera_activacion_en,
    'activacion_hipotetica_en',case when v_control.primera_activacion_en is null and v_control.modo='observacion' then v_ahora end,
    'politica_operativa_id',v_politica,'politica_operativa_version',v_version,
    'politica_adopcion_id',v_control.politica_adopcion_id,'filas',v_filas,
    'contexto_ambito',md5(jsonb_build_object('actor',v_uid,'rol',v_rol,'global',v_global,'visibles',v_visibles)::text));
end;
$function$;
revoke all on function private.sla_operacion_autorizada(uuid[],boolean) from public,anon,authenticated,service_role;

create function crm.estado_sla_leads_v2_fn(p_lead_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_resultado jsonb;v_filas jsonb;
begin
  if p_lead_ids is null or cardinality(p_lead_ids)>200 or array_position(p_lead_ids,null) is not null then
    raise exception 'Se requieren hasta 200 IDs sin nulls' using errcode='22023';
  end if;
  v_resultado:=private.sla_operacion_autorizada(p_lead_ids,true);
  select coalesce(jsonb_agg(f.value->'estado' order by f.value->'estado'->>'lead_id'),'[]'::jsonb)
    into v_filas from jsonb_array_elements(v_resultado->'filas') f;
  return jsonb_set(v_resultado-'contexto_ambito','{filas}',v_filas);
end;
$function$;
revoke all on function crm.estado_sla_leads_v2_fn(uuid[]) from public,anon,authenticated,service_role;
grant execute on function crm.estado_sla_leads_v2_fn(uuid[]) to authenticated;

-- Catalogos de lectura del dominio. La ventana sigue resolviendo el ambito;
-- validar un filtro nunca concede visibilidad ni modifica una decision SLA.
create function private.sla_filtros_cola_validos(p_senal text,p_etapa text)
returns boolean language sql stable security invoker set search_path = ''
as $function$
  select p_senal is not null and p_senal in ('todas','primera_atencion','tareas_vencidas',
    'seguimientos_pendientes','revisiones','datos_incompletos','por_repartir')
    and (p_etapa is null or p_etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada'));
$function$;
revoke all on function private.sla_filtros_cola_validos(text,text) from public,anon,authenticated,service_role;

create function crm.cola_accion_v2_fn(
  p_limite integer default 50, p_senal text default 'todas', p_etapa text default null,
  p_analista_id uuid default null, p_cursor jsonb default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
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
  v_contexto:=md5(jsonb_build_object('version',1,'ambito',v_datos->'contexto_ambito',
    'filtros',v_filtros,'limite',p_limite,'modo',v_datos->'modo',
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
    'primera_atencion',count(*) filter (where (f.value#>>'{senales,primera_atencion}')::boolean),
    'tareas_vencidas',count(*) filter (where (f.value#>>'{senales,tareas_vencidas}')::boolean),
    'seguimientos_pendientes',count(*) filter (where (f.value#>>'{senales,seguimientos_pendientes}')::boolean),
    'revisiones',count(*) filter (where (f.value#>>'{senales,revisiones}')::boolean),
    'datos_incompletos',count(*) filter (where (f.value#>>'{senales,datos_incompletos}')::boolean),
    'por_repartir',count(*) filter (where (f.value#>>'{senales,por_repartir}')::boolean))
  into v_totales from jsonb_array_elements(v_filtradas) f;
  with candidatos as (
    select f.value,
      case when p_senal='todas' then f.value->'accion'
        else coalesce(nullif(f.value->'accion','null'::jsonb),f.value->'accion_revision') end as accion
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
  return jsonb_build_object('version',2,'modo',v_datos->'modo','control_revision',v_datos->'control_revision',
    'calculado_en',v_datos->'calculado_en','politica_operativa_id',v_datos->'politica_operativa_id',
    'politica_operativa_version',v_datos->'politica_operativa_version',
    'total_items',v_total,'hay_mas',v_restantes>p_limite,'totales',v_totales,'items',v_items,
    'filtros',v_filtros,'limite',p_limite,'cursor_siguiente',v_siguiente,
    'rango',jsonb_build_object('desde',case when jsonb_array_length(v_items)=0 then 0 else v_anteriores+1 end,
      'hasta',case when jsonb_array_length(v_items)=0 then 0 else v_anteriores+jsonb_array_length(v_items) end));
end;
$function$;
revoke all on function crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb) to authenticated;

-- Adaptador v1: firma, propiedad y ACL se conservan con CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION crm.estado_sla_leads_fn()
 RETURNS TABLE(lead_id uuid, ciclo_politica_id uuid, ciclo_politica_version integer, primera_gestion_limite_en timestamp with time zone, primera_gestion_en timestamp with time zone, primer_contacto_limite_en timestamp with time zone, primer_contacto_en timestamp with time zone, ciclo_aproximado boolean, asignacion_id uuid, asignacion_politica_id uuid, asignacion_politica_version integer, asignacion_primera_gestion_limite_en timestamp with time zone, asignacion_primera_gestion_en timestamp with time zone, asignacion_primer_contacto_limite_en timestamp with time zone, asignacion_primer_contacto_en timestamp with time zone, etapa_politica_id uuid, etapa_politica_version integer, etapa text, etapa_iniciada_en timestamp with time zone, etapa_limite_en timestamp with time zone, etapa_objetivo_minutos integer, etapa_aproximada boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return query
  select r.* from jsonb_to_recordset(private.sla_operacion_autorizada(null,false))
    as r(lead_id uuid, ciclo_politica_id uuid, ciclo_politica_version integer, primera_gestion_limite_en timestamp with time zone, primera_gestion_en timestamp with time zone, primer_contacto_limite_en timestamp with time zone, primer_contacto_en timestamp with time zone, ciclo_aproximado boolean, asignacion_id uuid, asignacion_politica_id uuid, asignacion_politica_version integer, asignacion_primera_gestion_limite_en timestamp with time zone, asignacion_primera_gestion_en timestamp with time zone, asignacion_primer_contacto_limite_en timestamp with time zone, asignacion_primer_contacto_en timestamp with time zone, etapa_politica_id uuid, etapa_politica_version integer, etapa text, etapa_iniciada_en timestamp with time zone, etapa_limite_en timestamp with time zone, etapa_objetivo_minutos integer, etapa_aproximada boolean)
  order by r.lead_id;
end;
$function$;

-- Gate del dominio. Inspecciona los cuerpos ejecutables, no comentarios de
-- dependencias. Los casos de negocio y mutantes viven en tests/sla-nucleo.
create function private.assert_sla_nucleo()
returns text language plpgsql stable security definer set search_path = ''
as $function$
declare v record;v_cuerpo text;v_tabla text;v_rol text;
begin
  for v in select * from (values
    ('crm.estado_sla_leads_fn()','sla_operacion_autorizada'),
    ('crm.estado_sla_leads_v2_fn(uuid[])','sla_operacion_autorizada'),
    ('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)','sla_operacion_autorizada'),
    ('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)','sla_filtros_cola_validos'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads'),
    ('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)','sla_hechos_actuales')
  ) d(firma,dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
      into strict v_cuerpo from pg_proc p where p.oid=v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.'||v.dependencia||'\s*\(') then
      raise exception 'SLA: % dejo de consumir %',v.firma,v.dependencia;
    end if;
    if v.firma like 'crm.%' and v_cuerpo ~ '\mcrm\.(leads|tareas|actividades|lead_sla_etapas)\M' then
      raise exception 'SLA: adaptador % consulta hechos crudos',v.firma;
    end if;
  end loop;
  for v in select p.oid,p.proname,p.prosecdef,p.provolatile,p.proconfig,p.proowner,p.proacl,p.prosrc
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in ('sla_hechos_actuales','sla_tareas_hechos',
      'sla_evaluar_prorroga','sla_politica_operativa','sla_etapa_hechos','sla_operacion_leads','sla_operacion_autorizada','sla_filtros_cola_validos')
  loop
    if v.provolatile<>'s' or not coalesce(v.proconfig@>array['search_path=""'],false)
       or v.prosecdef<>(v.proname='sla_operacion_autorizada') then
      raise exception 'SLA: propiedades incorrectas de %',v.proname;
    end if;
    if exists (select 1 from aclexplode(coalesce(v.proacl,acldefault('f',v.proowner))) a where a.grantee<>v.proowner) then
      raise exception 'SLA: funcion privada % tiene grants externos',v.proname;
    end if;
    if v.proname<>'sla_operacion_autorizada' and v.prosrc ~ '\mauth\s*\.' then
      raise exception 'SLA: nucleo % interpreta autenticacion',v.proname;
    end if;
  end loop;
  foreach v_tabla in array array['sla_politica_etapas_operacion','lead_sla_etapa_ajustes','tarea_sla_contexto','sla_operacion_control'] loop
    if not (select c.relrowsecurity from pg_class c where c.oid=('crm.'||v_tabla)::regclass) then
      raise exception 'SLA: falta RLS en %',v_tabla;
    end if;
    foreach v_rol in array array['anon','authenticated','service_role'] loop
      if has_table_privilege(v_rol,'crm.'||v_tabla,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'SLA: privilegio directo de % en %',v_rol,v_tabla;
      end if;
    end loop;
    if not exists (select 1 from pg_trigger t where t.tgrelid=('crm.'||v_tabla)::regclass
      and t.tgfoid='private.log_audit_crm()'::regprocedure and t.tgenabled in ('O','A')
      and t.tgtype=29 and t.tgqual is null and t.tgattr=''::int2vector) then
      raise exception 'SLA: auditoria incompleta en %',v_tabla;
    end if;
  end loop;
  return 'OK: nucleo SLA privado, adaptadores dependientes, entradas cerradas y auditadas';
end;
$function$;
revoke all on function private.assert_sla_nucleo() from public,anon,authenticated,service_role;

comment on function private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz) is 'Nucleo operativo SLA N1: hechos, seguimiento, cobertura, limites y decisiones. Ambito autorizado y reloj explicitos; sin escrituras.';
comment on function private.sla_operacion_autorizada(uuid[],boolean) is 'Ventana unica de lectura SLA: capacidades existentes y un reloj por consulta. API no elige ambito global ni instante.';
comment on function private.sla_evaluar_prorroga(text,text,uuid,boolean,text,timestamptz,timestamptz,timestamptz,timestamptz,integer,integer,integer,boolean) is 'Regla de prorroga del nucleo SLA. N1 solo decide; futuro writer revalida, bloquea y persiste.';
comment on function crm.estado_sla_leads_v2_fn(uuid[]) is 'SLA N1: estado version 2, hasta 200 IDs visibles. No activa ni modifica datos. No sustituye v1 en pantallas.';
comment on function crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb) is 'SLA N1: cola por capacidad, totales completos antes del limite; consume decisiones del nucleo.';

do $postflight$
declare v_gate text;
begin
  if exists (select 1 from pg_temp.sla_n1_fuentes s left join pg_proc p on p.oid=s.oid
    where p.oid is null or p.proowner<>s.proowner or p.proacl is distinct from s.proacl
      or (p.oid<>'crm.estado_sla_leads_fn()'::regprocedure and pg_get_functiondef(p.oid)<>s.definicion)) then
    raise exception 'SLA N1 altero una fuente canonica o la autoridad de v1';
  end if;
  if exists (select 1 from crm.sla_politica_etapas_operacion)
     or exists (select 1 from crm.lead_sla_etapa_ajustes)
     or exists (select 1 from crm.tarea_sla_contexto)
     or not exists (select 1 from crm.sla_operacion_control where modo='legado' and revision=0
                    and primera_activacion_en is null and politica_adopcion_id is null) then
    raise exception 'SLA N1 debe quedar legado, sin configuracion ni captura';
  end if;
  perform private.assert_sla_nucleo();
  -- En la base CRM real se ejecutan los gates existentes. El banco reducido de
  -- contrato no instala ni suplanta estos gates; su ausencia se informa alli.
  foreach v_gate in array array['assert_analitica_leads_citas','assert_auditoria','assert_analista_vigencia','assert_f7_piezas_cerradas'] loop
    if to_regprocedure('private.'||v_gate||'()') is not null then
      execute format('select private.%I()',v_gate);
    end if;
  end loop;
end;
$postflight$;
commit;
