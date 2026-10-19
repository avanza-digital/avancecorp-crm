-- Recorrido por hechos. Primera conversión: asistencia + entrevista de la misma cita.
-- Instalación en observación. No activa bloqueos ni reconstruye evidencias antiguas.
begin;
set local search_path='';
set local quote_all_identifiers=off;
do $$ begin
  if md5(pg_get_functiondef('crm.eliminar_lead_error_carga(uuid,text)'::regprocedure))<>'15ce9327e21306ec9682552815936e71' then
    raise exception 'La puerta de eliminacion cambio; revisar su version vigente antes de ampliar la copia' using errcode='55000';
  end if;
  perform private.assert_sla_nucleo();
end $$;

create table crm.recorrido_control (
  id boolean primary key default true check (id),
  modo text not null default 'observacion' check (modo in ('apagado','observacion','exigir')),
  cohorte_desde timestamptz check (isfinite(cohorte_desde)),
  revision integer not null default 1 check (revision > 0),
  motivo text not null default 'Instalacion en observacion' check (length(btrim(motivo)) between 8 and 1000),
  actualizado_por uuid references public.perfiles(id),
  actualizado_en timestamptz not null default clock_timestamp() check (isfinite(actualizado_en)),
  check (modo <> 'exigir' or cohorte_desde is not null)
);
alter table crm.recorrido_control enable row level security;
revoke all on crm.recorrido_control from public, anon, authenticated, service_role;
create trigger audit_recorrido_control after insert or update or delete on crm.recorrido_control
  for each row execute function private.log_audit_crm();
insert into crm.recorrido_control(id) values (true);
comment on table crm.recorrido_control is 'Estado administrativo de esta instalacion, no un tenant ni una empresa de inversion. Corte inmutable; auditoria before/after existente. Solo puerta gerencial.';

create table crm.actividad_ciclo_contexto (
  actividad_id uuid primary key references crm.actividades(id) on delete cascade,
  lead_id uuid not null references crm.leads(id),
  ciclo_n integer check (ciclo_n > 0),
  estado_ciclo text not null check (estado_ciclo in ('ciclo','base_sin_ciclo')),
  registrado_en timestamptz not null check (isfinite(registrado_en)),
  gesto_oficina_id uuid,
  oficina_tarea_id uuid references crm.tareas(id),
  foreign key (lead_id, ciclo_n) references crm.lead_sla_ciclos(lead_id, ciclo_n),
  check ((gesto_oficina_id is null) = (oficina_tarea_id is null)),
  check ((estado_ciclo='ciclo' and ciclo_n is not null) or (estado_ciclo='base_sin_ciclo' and ciclo_n is null))
);
alter table crm.actividad_ciclo_contexto enable row level security;
revoke all on crm.actividad_ciclo_contexto from public, anon, authenticated, service_role;
create index actividad_ciclo_contexto_lead_ciclo_idx on crm.actividad_ciclo_contexto(lead_id,ciclo_n,registrado_en);
create trigger audit_actividad_ciclo_contexto after insert or update or delete on crm.actividad_ciclo_contexto
  for each row execute function private.log_audit_crm();
comment on table crm.actividad_ciclo_contexto is 'Clave causal inmutable 1:1 de actividades. El hecho sigue en actividades; no se aceptan ciclos, horas ni marcas de oficina desde metadata del cliente.';

create function private.recorrido_contexto_guard() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' then
    -- Misma autorización de copia exacta, actor y transacción de la puerta oficial.
    if private.borrado_lead_error_autoriza(tg_table_name,to_jsonb(old)) then
      return old;
    end if;
  end if;
  if tg_op<>'INSERT' or pg_trigger_depth()<2
    or current_setting('crm.recorrido_contexto_writer',true) is distinct from 'on'
    or current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid) then
    raise exception 'El contexto del recorrido solo lo registra el servidor' using errcode='42501';
  end if;
  if not exists(select 1 from crm.actividades a where a.id=new.actividad_id and a.lead_id=new.lead_id) then
    raise exception 'Contexto ajeno a la actividad' using errcode='23514';
  end if;
  return new;
end $$;
create trigger recorrido_contexto_guard before insert or update or delete on crm.actividad_ciclo_contexto
  for each row execute function private.recorrido_contexto_guard();
create trigger recorrido_contexto_no_truncate before truncate on crm.actividad_ciclo_contexto
  for each statement execute function private.recorrido_contexto_guard();

create function private.recorrido_bloquear_insert() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  -- BEFORE evita subir KEY SHARE de la FK a UPDATE en dos inserts internos
  -- concurrentes. El AFTER vuelve a leer bajo el lock ya adquirido.
  perform 1 from crm.leads where id=new.lead_id for update;
  return new;
end $$;
create trigger trg_02_recorrido_lock before insert on crm.actividades for each row
  when (new.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'))
  execute function private.recorrido_bloquear_insert();

create function private.recorrido_capturar_actividad() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  v_ciclo integer; v_hora timestamptz; v_lead crm.leads%rowtype;
  v_writer text:=coalesce(current_setting('crm.recorrido_contexto_writer',true),'off');
  v_oficina jsonb; v_gesto uuid; v_tarea uuid;
begin
  -- Incluso los writers internos se serializan con la reapertura del lead.
  select * into strict v_lead from crm.leads where id=new.lead_id for update;
  v_ciclo:=v_lead.ciclo_actual;
  v_hora:=clock_timestamp();
  if not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id and c.ciclo_n=v_ciclo) then
    -- B8: una base cargada nace descartada SIN ciclo SLA. Registrar un intento
    -- no la reactiva. Se conserva su recepción real, sin inventar un ciclo.
    -- bases_carga_nace_dormido también exige la válvula de CARGA, apagada al
    -- gestionar después. Aquí comprobamos su estado persistido y ausencia de
    -- ciclos; origen/motivo están protegidos por el guard vigente de bases.
    if v_lead.origen='base_cargada' and v_lead.etapa='descartado'
      and v_lead.motivo_descarte='base_cargada' and v_lead.activo
      and not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id) then
      v_ciclo:=null;
    else
      raise exception 'Falta el ciclo del recorrido de la actividad' using errcode='23514';
    end if;
  end if;
  v_oficina:=nullif(current_setting('crm.recorrido_oficina',true),'')::jsonb;
  if new.tipo='reunion_realizada' and v_oficina->>'lead_id'=new.lead_id::text
    and v_oficina->>'tarea_id'=new.metadata->>'tarea_id' then
    v_gesto:=(v_oficina->>'operacion_id')::uuid;
    v_tarea:=(v_oficina->>'tarea_id')::uuid;
  end if;
  perform set_config('crm.recorrido_contexto_writer','on',true);
  insert into crm.actividad_ciclo_contexto(actividad_id,lead_id,ciclo_n,estado_ciclo,registrado_en,gesto_oficina_id,oficina_tarea_id)
    values(new.id,new.lead_id,v_ciclo,case when v_ciclo is null then 'base_sin_ciclo' else 'ciclo' end,v_hora,v_gesto,v_tarea);
  perform set_config('crm.recorrido_contexto_writer',v_writer,true);
  return null;
end $$;
create trigger trg_02_recorrido_contexto after insert on crm.actividades for each row
  when (new.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'))
  execute function private.recorrido_capturar_actividad();

create function private.recorrido_serializar_invalidacion() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_lead uuid:=old.lead_id;
begin
  if v_lead is not null then
    -- Las puertas normales ya poseen este lock. NOWAIT impide una espera
    -- circular si un writer privilegiado llega primero por tarea/actividad.
    perform 1 from crm.leads where id=v_lead for update nowait;
    if tg_op='UPDATE' and new.lead_id is distinct from old.lead_id then
      raise exception 'La evidencia no cambia de lead' using errcode='23514';
    end if;
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;
create trigger trg_00_recorrido_invalidacion before update or delete on crm.actividades for each row
  execute function private.recorrido_serializar_invalidacion();
create trigger trg_tareas_00_recorrido_invalidacion before update or delete on crm.tareas for each row
  execute function private.recorrido_serializar_invalidacion();

create function private.recorrido_control_guard() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op<>'UPDATE'
    or current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid)
    or current_setting('crm.recorrido_control_writer',true) is distinct from 'on' then
    raise exception 'El modo cambia solo por la puerta del recorrido' using errcode='42501';
  end if;
  if new.id is distinct from old.id or new.revision<>old.revision+1
    or (old.cohorte_desde is not null and new.cohorte_desde is distinct from old.cohorte_desde)
    or (old.cohorte_desde is null and new.cohorte_desde<statement_timestamp()) then
    raise exception 'Corte inmutable o revision invalida' using errcode='23514';
  end if;
  return new;
end $$;
create trigger recorrido_control_guard before insert or update or delete on crm.recorrido_control
  for each row execute function private.recorrido_control_guard();
create trigger recorrido_control_no_truncate before truncate on crm.recorrido_control
  for each statement execute function private.recorrido_control_guard();

create function crm.recorrido_configurar_fn(p_modo text,p_motivo text,p_revision integer,p_cohorte_desde timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_control crm.recorrido_control%rowtype;
  v_writer text:=coalesce(current_setting('crm.recorrido_control_writer',true),'off');
begin
  if not private.es_gerencia_crm_activa() then raise exception 'No autorizado' using errcode='42501'; end if;
  if p_modo is null or p_modo not in ('apagado','observacion','exigir')
    or p_motivo is null or length(btrim(p_motivo)) not between 8 and 1000
    or p_revision is null or (p_cohorte_desde is not null and not isfinite(p_cohorte_desde)) then
    raise exception 'Indica modo, motivo y revision validos' using errcode='22023';
  end if;
  select * into strict v_control from crm.recorrido_control where id for update;
  if v_control.revision<>p_revision then raise exception 'El modo cambio; consulta de nuevo' using errcode='40001'; end if;
  if v_control.cohorte_desde is not null and p_cohorte_desde is not null and p_cohorte_desde<>v_control.cohorte_desde then
    raise exception 'El corte de activacion no se reinicia' using errcode='22023';
  end if;
  if v_control.cohorte_desde is null and p_cohorte_desde is not null and p_cohorte_desde<clock_timestamp() then
    raise exception 'La activacion inicial solo admite ciclos nuevos; antiguos requieren politica explicita' using errcode='22023';
  end if;
  perform set_config('crm.recorrido_control_writer','on',true);
  update crm.recorrido_control set modo=p_modo, motivo=btrim(p_motivo), revision=revision+1,
    cohorte_desde=coalesce(cohorte_desde,p_cohorte_desde,case when p_modo='exigir' then clock_timestamp() end),
    actualizado_por=(select auth.uid()),actualizado_en=clock_timestamp()
    where id returning * into v_control;
  perform set_config('crm.recorrido_control_writer',v_writer,true);
  return to_jsonb(v_control)-'id';
end $$;

-- Sin locks de hechos. VOLATILE permite snapshot nuevo cuando el guard llama
-- en una sentencia POSTERIOR a adquirir el lock del lead.
create function private.recorrido_evaluar(p_lead_ids uuid[])
returns table(lead_id uuid,resultado jsonb)
language sql volatile set search_path='' as $$
with leads as materialized (
  select l.id,l.ciclo_actual,l.etapa,l.vendedor_id,l.activo,c.iniciado_en,
    (select count(*)=1 and min(h.ciclo_n)=1 from crm.lead_sla_ciclos h where h.lead_id=l.id) unico_ciclo
  from crm.leads l left join crm.lead_sla_ciclos c on c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
  where l.id=any(p_lead_ids)
), actividades as materialized (
  select a.id,a.lead_id,a.tipo,a.metadata,a.creado_en,x.registrado_en,x.gesto_oficina_id,x.oficina_tarea_id,
    case when x.actividad_id is not null then x.ciclo_n=l.ciclo_actual
      when l.unico_ciclo and l.ciclo_actual=1 then true
      when exists(select 1 from crm.tarea_sla_contexto tc where tc.tarea_id::text=a.metadata->>'tarea_id'
          and tc.lead_id=a.lead_id and tc.ciclo_n=l.ciclo_actual) then true
      when exists(select 1 from crm.lead_sla_etapa_ajustes aj join crm.lead_sla_etapas e on e.id=aj.etapa_sla_id
          where aj.origen_actividad_id=a.id and e.lead_id=a.lead_id and e.ciclo_n=l.ciclo_actual) then true
      else false end del_ciclo
  from leads l join crm.actividades a on a.lead_id=l.id
    left join crm.actividad_ciclo_contexto x on x.actividad_id=a.id
  where a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
    and not (a.metadata ? 'deshecho_en')
), citas as materialized (
  select t.id,t.lead_id,t.estado,t.vence_en,t.resultado_reunion,t.resultado_actividad_id,
    tc.ciclo_n=l.ciclo_actual del_ciclo,
    a.id asistencia_id,
    -- La evidencia nueva tiene hora de recepción real; no confía en backdates.
    -- Historia sin sello se conserva como ambigua para la política de antiguos.
    a.id is not null and a.registrado_en is not null and t.vence_en<=a.registrado_en asistencia_valida,
    a.id is not null and a.registrado_en is not null and t.vence_en<=a.registrado_en
      and t.resultado_reunion in ('interesado','seguimiento','propuesta','inicia_registro','no_interesado') entrevista_valida
  from leads l join crm.tareas t on t.lead_id=l.id
    left join crm.tarea_sla_contexto tc on tc.tarea_id=t.id and tc.lead_id=l.id
    left join actividades a on a.id=t.resultado_actividad_id and a.lead_id=l.id and a.del_ciclo
      and a.tipo='reunion_realizada' and a.metadata->>'tarea_id'=t.id::text and t.estado='completada'
  where t.tipo='reunion' and t.activo and t.estado in ('pendiente','completada')
), hechos as (
  select l.*,
    (select a.id from actividades a where a.lead_id=l.id and a.del_ciclo order by a.registrado_en nulls last,a.id limit 1) gestion_id,
    (select a.id from actividades a where a.lead_id=l.id and a.del_ciclo
      and (a.tipo in ('llamada_realizada','whatsapp_recibido') or a.gesto_oficina_id is not null)
      order by a.registrado_en nulls last,a.id limit 1) contacto_id,
    (select t.id from citas t where t.lead_id=l.id and t.del_ciclo
      order by t.entrevista_valida desc nulls last,t.vence_en,t.id limit 1) cita_id,
    (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.entrevista_valida
      order by t.vence_en,t.id limit 1) entrevista_tarea_id,
    (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.asistencia_valida
      order by t.entrevista_valida desc,t.vence_en,t.id limit 1) asistencia_tarea_id,
    (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.estado='pendiente'
      order by t.vence_en,t.id limit 1) pendiente_tarea_id,
    exists(select 1 from citas t where t.lead_id=l.id and
      (t.del_ciclo is null or (t.del_ciclo and t.estado='completada' and t.asistencia_id is not null
         and exists(select 1 from actividades a where a.id=t.asistencia_id and a.registrado_en is null)))) historico_ambiguo
  from leads l
)
select h.id,jsonb_build_object(
  'lead_id',h.id,'ciclo_n',h.ciclo_actual,'ciclo_inicio',h.iniciado_en,
  'aplica',h.activo and h.etapa not in ('convertido','descartado'),
  'estado',case when h.entrevista_tarea_id is not null then 'completo'
    when h.iniciado_en is null or h.historico_ambiguo then 'ambiguo' else 'incompleto' end,
  'habilita_conversion',h.entrevista_tarea_id is not null,
  'pasos',jsonb_build_object('gestionado',h.gestion_id is not null,'contactado',h.contacto_id is not null,
    'cita_agendada',h.cita_id is not null,'asistencia',h.asistencia_tarea_id is not null,'entrevista',h.entrevista_tarea_id is not null),
  'evidencias',jsonb_build_object('gestion_id',h.gestion_id,'contacto_id',h.contacto_id,'cita_id',h.cita_id,
    'entrevista_tarea_id',h.entrevista_tarea_id,
    'asistencia_tarea_id',h.asistencia_tarea_id,
    'asistencia_id',(select t.asistencia_id from citas t where t.id=h.asistencia_tarea_id)),
  'pendiente',case when h.entrevista_tarea_id is not null then 'listo'
    when h.vendedor_id is null then 'asignar_analista'
    when h.pendiente_tarea_id is not null then case when
      (select t.vence_en>clock_timestamp() from citas t where t.id=h.pendiente_tarea_id) then 'esperar_cita' else 'cerrar_entrevista' end
    when h.historico_ambiguo or h.iniciado_en is null then 'revisar_historial'
    when h.asistencia_tarea_id is not null then 'revisar_entrevista' else 'agendar_cita' end,
  'tarea_pendiente_id',h.pendiente_tarea_id,
  'cita_pendiente_en',(select t.vence_en from citas t where t.id=h.pendiente_tarea_id)
)
from hechos h;
$$;

create function crm.recorrido_leads_fn(p_lead_ids uuid[]) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_amb record;v_ids uuid[];v_filas jsonb;v_control crm.recorrido_control%rowtype;
begin
  select * into strict v_amb from private.sla_operacion_ambito(p_lead_ids,false);
  if p_lead_ids is null or cardinality(p_lead_ids)>100 then
    raise exception 'Consulta entre cero y cien leads por lote' using errcode='22023';end if;
  select array_agg(l.id) into v_ids from crm.leads l where l.id=any(p_lead_ids) and l.activo
    and (v_amb.es_global or l.vendedor_id=any(v_amb.visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id=any(v_amb.visibles)));
  select * into strict v_control from crm.recorrido_control where id;
  select coalesce(jsonb_agg(e.resultado||jsonb_build_object('exigible',coalesce(v_control.modo='exigir'
      and (e.resultado->>'ciclo_inicio')::timestamptz>=v_control.cohorte_desde
      and (e.resultado->>'aplica')::boolean,false)) order by e.lead_id),'[]'::jsonb)
    into v_filas from private.recorrido_evaluar(coalesce(v_ids,'{}'::uuid[])) e;
  return jsonb_build_object('version',1,'modo',v_control.modo,'revision',v_control.revision,
    'cohorte_desde',v_control.cohorte_desde,'filas',v_filas);
end $$;

-- Compatibilidad: misma puerta auditada, ahora conoce y conserva la relación causal.
CREATE OR REPLACE FUNCTION crm.eliminar_lead_error_carga(p_lead_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  c_dias_max constant integer := 30;
  v_uid uuid := (select auth.uid());
  v_roles jsonb;
  v_rol text;
  v_motivo text := private.motivo_normalizado(p_motivo);
  v_lead crm.leads%rowtype;
  v_inv uuid[];
  v_inv0 uuid[];
  v_no text[] := '{}';
  v_meses text;
  v_nuevas text;
  v_copia jsonb;
  v_filas jsonb;
  v_id uuid;
  v_n bigint;
  v_cuadre jsonb := '{}'::jsonb;
  v_previa text := pg_catalog.current_setting('crm.borrado_lead_error', true);
begin
  if v_uid is null then
    raise exception 'Inicia sesión para eliminar un lead' using errcode = '42501';
  end if;
  v_roles := private.eliminar_inversion_roles(v_uid);
  v_rol := case when coalesce((v_roles ->> 'gerencia')::boolean, false) then 'gerencia' else v_roles ->> 'portal' end;
  if v_rol is null then
    raise exception 'Solo gerencia o un admin del portal pueden eliminar un lead' using errcode = '42501';
  end if;
  if p_lead_id is null then
    raise exception 'Falta el lead a eliminar' using errcode = '22023';
  end if;
  if pg_catalog.char_length(v_motivo) < 10 then
    raise exception 'Escribe el motivo de la eliminación (al menos 10 caracteres)' using errcode = '22023';
  end if;
  if pg_catalog.char_length(v_motivo) > 500 then
    raise exception 'El motivo admite como máximo 500 caracteres' using errcode = '22023';
  end if;
  -- Cada sentencia necesita su propia instantánea: la copia tiene que ver lo que existe DESPUÉS de los bloqueos, y la
  -- comprobación del mes cerrado tiene que ver un cierre recién confirmado.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Esta operación necesita aislamiento READ COMMITTED' using errcode = '55000';
  end if;

  -- Fail-closed: toda llave foránea hacia lo que se borra tiene que estar en esta lista, con sus columnas de origen y
  -- de destino y su acción ON DELETE (catálogo de producción, 15/10/2026).
  select pg_catalog.string_agg(k.clave, ', ' order by k.clave) into v_nuevas
  from (
    select c.conrelid::regclass::text || ':'
             || (select pg_catalog.string_agg(a.attname::text, ',' order by u.ord)
                 from pg_catalog.unnest(c.conkey) with ordinality u(attnum, ord)
                 join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = u.attnum)
             || ':' || c.confrelid::regclass::text || ':'
             || (select pg_catalog.string_agg(a.attname::text, ',' order by u.ord)
                 from pg_catalog.unnest(c.confkey) with ordinality u(attnum, ord)
                 join pg_catalog.pg_attribute a on a.attrelid = c.confrelid and a.attnum = u.attnum)
             || ':' || c.confdeltype::text as clave
    from pg_catalog.pg_constraint c
    where c.contype = 'f'
      and c.confrelid in ('crm.leads'::regclass, 'crm.tareas'::regclass, 'crm.actividades'::regclass, 'crm.actividad_ciclo_contexto'::regclass,
                          'crm.lead_asignaciones'::regclass, 'crm.lead_sla_ciclos'::regclass, 'crm.lead_sla_etapas'::regclass,
                          'crm.tarea_sla_contexto'::regclass, 'crm.lead_asignacion_sla_hitos'::regclass,
                          'crm.lead_sla_etapa_ajustes'::regclass, 'crm.actividades_cliente'::regclass,
                          'crm.sla_operacion_recibos'::regclass, 'crm.lead_potencial'::regclass,
                          'crm.lead_potencial_eventos'::regclass, 'crm.base_carga_leads'::regclass,
                          'crm.llamadas_celular_eventos'::regclass, 'crm.llamadas_celular_enlaces'::regclass,
                          'private.llamadas_celular_intenciones'::regclass,
                          'crm.inversionistas'::regclass, 'crm.inversionista_leads'::regclass,
                          'crm.inversionista_identificadores'::regclass, 'crm.inversionista_responsables'::regclass,
                          'crm.inversionista_gestiones'::regclass, 'crm.cartera_lecturas'::regclass,
                          'crm.inversionista_datos_contacto'::regclass, 'crm.inversion_solicitudes'::regclass,
                          'crm.solicitudes_tasa'::regclass, 'crm.envios_push_tasa'::regclass)
  ) k
  where k.clave <> all (array[
    'crm.actividades:lead_id:crm.leads:id:c',
    'crm.actividad_ciclo_contexto:actividad_id:crm.actividades:id:c',
    'crm.actividad_ciclo_contexto:lead_id:crm.leads:id:a',
    'crm.actividad_ciclo_contexto:lead_id,ciclo_n:crm.lead_sla_ciclos:lead_id,ciclo_n:a',
    'crm.actividad_ciclo_contexto:oficina_tarea_id:crm.tareas:id:a',
    'crm.actividades_cliente:tarea_id:crm.tareas:id:n',
    'crm.ajustes_mes_cerrado:lead_id:crm.leads:id:r',
    'crm.backfill_multiempresa_mapa:inversionista_id:crm.inversionistas:id:a',
    'crm.base_carga_leads:lead_id:crm.leads:id:a',
    'crm.busquedas_cliente_existente:inversionista_id:crm.inversionistas:id:a',
    'crm.busquedas_cliente_existente:lead_id:crm.leads:id:a',
    'crm.cartera_lecturas:inversionista_id:crm.inversionistas:id:a',
    'crm.cierres_avance_anulados:lead_id:crm.leads:id:r',
    'crm.cierres_externos:inversionista_id:crm.inversionistas:id:a',
    'crm.cierres_externos:lead_id:crm.leads:id:r',
    'crm.conversion_acreditaciones:episodio_id:crm.lead_asignaciones:id:a',
    'crm.conversion_acreditaciones:inversionista_id:crm.inversionistas:id:a',
    'crm.conversion_acreditaciones:lead_id:crm.leads:id:a',
    'crm.conversion_reservas:inversionista_id:crm.inversionistas:id:a',
    'crm.conversion_reservas:lead_id:crm.leads:id:r',
    'crm.envios_push_tasa:solicitud_id:crm.solicitudes_tasa:id:a',
    'crm.inversion_cotitular_origenes:identificador_origen_id:crm.inversionista_identificadores:id:a',
    'crm.inversion_cotitular_origenes:persona_origen_id:crm.inversionistas:id:a',
    'crm.inversion_solicitud_correcciones:solicitud_id:crm.inversion_solicitudes:id:a',
    'crm.inversion_solicitud_origenes:solicitud_id:crm.inversion_solicitudes:id:a',
    'crm.inversion_solicitud_revisiones:solicitud_id:crm.inversion_solicitudes:id:a',
    'crm.inversion_solicitudes:inversionista_id:crm.inversionistas:id:a',
    'crm.inversion_solicitudes:lead_origen_id:crm.leads:id:a',
    'crm.inversion_titulares:inversionista_id:crm.inversionistas:id:a',
    'crm.inversiones:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_datos_contacto:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_fusiones:canonico_id:crm.inversionistas:id:a',
    'crm.inversionista_fusiones:fusionado_id:crm.inversionistas:id:a',
    'crm.inversionista_gestiones:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_gestiones:tarea_id:crm.tareas:id:a',
    'crm.inversionista_identificadores:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_leads:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_leads:lead_id:crm.leads:id:a',
    'crm.inversionista_operaciones:identificador_anterior_id:crm.inversionista_identificadores:id:a',
    'crm.inversionista_operaciones:identificador_nuevo_id:crm.inversionista_identificadores:id:a',
    'crm.inversionista_operaciones:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_operaciones:lead_id:crm.leads:id:a',
    'crm.inversionista_responsables:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionistas:inversionista_canonico_id:crm.inversionistas:id:a',
    'crm.lead_asignacion_sla_hitos:lead_asignacion_id:crm.lead_asignaciones:id:r',
    'crm.lead_asignaciones:lead_id:crm.leads:id:r',
    'crm.lead_potencial:lead_id:crm.leads:id:a',
    'crm.lead_potencial_eventos:lead_id:crm.leads:id:a',
    'crm.lead_sla_ciclos:lead_id:crm.leads:id:r',
    'crm.lead_sla_etapa_ajustes:etapa_sla_id:crm.lead_sla_etapas:id:r',
    'crm.lead_sla_etapa_ajustes:origen_actividad_id:crm.actividades:id:r',
    'crm.lead_sla_etapas:lead_id,ciclo_n:crm.lead_sla_ciclos:lead_id,ciclo_n:r',
    'crm.lead_sla_etapas:lead_id:crm.leads:id:r',
    'crm.leads:inversionista_id:crm.inversionistas:id:a',
    'crm.ledger_rentabilidad:solicitud_id:crm.solicitudes_tasa:id:r',
    'crm.llamadas_celular_enlaces:actividad_id:crm.actividades:id:n',
    'crm.llamadas_celular_enlaces:evento_id:crm.llamadas_celular_eventos:id:c',
    'crm.llamadas_celular_enlaces:lead_id:crm.leads:id:c',
    'crm.llamadas_celular_eventos:lead_id:crm.leads:id:c',
    'crm.postventa_operaciones:inversionista_id:crm.inversionistas:id:a',
    'crm.postventa_retiros:inversionista_id:crm.inversionistas:id:a',
    'crm.sla_operacion_recibos:lead_id:crm.leads:id:a',
    'crm.solicitudes_tasa:lead_id:crm.leads:id:r',
    'crm.tarea_sla_contexto:lead_id,ciclo_n:crm.lead_sla_ciclos:lead_id,ciclo_n:r',
    'crm.tarea_sla_contexto:tarea_id:crm.tareas:id:r',
    'crm.tareas:inversionista_id:crm.inversionistas:id:a',
    'crm.tareas:lead_id:crm.leads:id:c',
    'crm.tareas:reagendada_de:crm.tareas:id:n',
    'crm.tareas:resultado_actividad_id:crm.actividades:id:n',
    'private.llamadas_celular_intenciones:actividad_id:crm.actividades:id:c',
    'private.llamadas_celular_intenciones:lead_id:crm.leads:id:c'
  ]);
  if v_nuevas is not null then
    raise exception 'Hay tablas nuevas enlazadas al lead que esta eliminación no conoce (%); hay que revisarla antes', v_nuevas
      using errcode = '55000';
  end if;

  -- Mismo candado que crm.cerrar_periodo, tomado ANTES de las filas (mismo orden que el cierre: sin abrazo mortal).
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

  -- Fichas candidatas (sin bloqueo) y, en el mismo orden que crm.reservar_conversion_lead, primero la ficha y después el
  -- lead: así no hay abrazo mortal entre la conversión y esta eliminación.
  select coalesce(pg_catalog.array_agg(distinct z.i), '{}') into v_inv0
  from (select l.inversionista_id as i from crm.leads l where l.id = p_lead_id and l.inversionista_id is not null
        union select il.inversionista_id from crm.inversionista_leads il where il.lead_id = p_lead_id) z;
  perform 1 from crm.inversionistas x where x.id = any (v_inv0) order by x.id for update;
  -- El lead (bloquea también toda fila nueva que quiera colgarse de él: su FK necesita KEY SHARE).
  select * into v_lead from crm.leads l where l.id = p_lead_id for update;
  if not found then
    raise exception 'El lead no existe o ya fue eliminado' using errcode = 'P0002';
  end if;
  -- Sus enlaces se bloquean ANTES de decidir qué fichas son suyas: nadie puede moverlos a otro lead a mitad de camino.
  perform 1 from crm.inversionista_leads x where x.lead_id = p_lead_id order by x.id for update;
  select coalesce(pg_catalog.array_agg(distinct z.i), '{}') into v_inv
  from (select v_lead.inversionista_id as i where v_lead.inversionista_id is not null
        union select il.inversionista_id from crm.inversionista_leads il where il.lead_id = p_lead_id) z;
  if (v_inv <@ v_inv0) is not true then
    raise exception 'El lead cambió mientras se eliminaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  -- Todo lo que decide si sus fichas se pueden borrar, también bloqueado antes de validar.
  perform 1 from crm.inversionista_leads x where x.inversionista_id = any (v_inv) order by x.id for update;
  perform 1 from crm.inversionista_gestiones x where x.inversionista_id = any (v_inv) order by x.id for update;
  -- Los padres de cada nivel, en sentencias ANTERIORES a la copia.
  perform 1 from crm.lead_asignaciones x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.lead_sla_ciclos x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.lead_sla_etapas x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.tareas x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.actividades x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.llamadas_celular_eventos x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.inversionista_identificadores x where x.inversionista_id = any (v_inv) order by x.id for update;
  perform 1 from crm.inversion_solicitudes x
  where x.lead_origen_id = p_lead_id or x.inversionista_id = any (v_inv) order by x.id for update;
  perform 1 from crm.solicitudes_tasa x where x.lead_id = p_lead_id order by x.id for update;

  -- Un CLIENTE nunca se borra.
  if v_lead.contrato_id is not null then v_no := v_no || 'tiene un contrato enlazado'::text; end if;
  if v_lead.perfil_id is not null then v_no := v_no || 'está enlazado a un perfil de cliente'::text; end if;
  if v_lead.convertido_en is not null
     or exists (select 1 from crm.lead_asignaciones a where a.lead_id = p_lead_id and a.resultado = 'convertido') then
    v_no := v_no || 'tiene una conversión registrada'::text;
  end if;
  if exists (select 1 from crm.conversion_acreditaciones x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene una conversión acreditada'::text; end if;
  if exists (select 1 from crm.conversion_reservas x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene una reserva de conversión'::text; end if;
  if exists (select 1 from crm.cierres_externos x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene un cierre en cooperativa'::text; end if;
  if exists (select 1 from crm.cierres_avance_anulados x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene un cierre anulado'::text; end if;
  if exists (select 1 from crm.ajustes_mes_cerrado x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene un ajuste de mes cerrado'::text; end if;
  -- Historia del lead que no se borra con él.
  if exists (select 1 from crm.inversionista_operaciones x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene operaciones de inversionista registradas'::text; end if;
  if exists (select 1 from crm.busquedas_cliente_existente x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene búsquedas de cliente existente registradas'::text; end if;
  if exists (select 1 from crm.inversionista_gestiones g join crm.tareas t on t.id = g.tarea_id where t.lead_id = p_lead_id) then
    v_no := v_no || 'tiene gestiones de inversionista'::text; end if;
  -- Solicitudes de inversión (por lead de origen o de sus fichas): solo canceladas, sin inversión ni historia.
  if exists (select 1 from crm.inversion_solicitudes s
             where (s.lead_origen_id = p_lead_id or s.inversionista_id = any (v_inv))
               and (s.estado is distinct from 'cancelada' or s.inversion_id is not null
                    or s.confirmado_por is not null or s.resultado is not null)) then
    v_no := v_no || 'tiene una solicitud de inversión en curso (cancélala primero)'::text;
  end if;
  if exists (select 1 from crm.inversion_solicitudes s
             where (s.lead_origen_id = p_lead_id or s.inversionista_id = any (v_inv))
               and (exists (select 1 from crm.inversion_solicitud_correcciones c where c.solicitud_id = s.id)
                    or exists (select 1 from crm.inversion_solicitud_revisiones c where c.solicitud_id = s.id)
                    or exists (select 1 from crm.inversion_solicitud_origenes c where c.solicitud_id = s.id))) then
    v_no := v_no || 'tiene una solicitud de inversión con revisiones o fuentes registradas'::text;
  end if;
  -- Pertenencia en los dos extremos: la solicitud tiene que ser de ESTE lead y de SU ficha.
  if exists (select 1 from crm.inversion_solicitudes s where s.lead_origen_id = p_lead_id and s.inversionista_id <> all (v_inv)) then
    v_no := v_no || 'tiene una solicitud de inversión de otra persona'::text;
  end if;
  if exists (select 1 from crm.inversion_solicitudes s
             where s.inversionista_id = any (v_inv) and s.lead_origen_id is not null and s.lead_origen_id <> p_lead_id) then
    v_no := v_no || 'su ficha de inversionista tiene solicitudes de otro lead'::text;
  end if;
  -- Solicitudes de tasa: solo si nunca se usaron.
  if exists (select 1 from crm.solicitudes_tasa t
             where t.lead_id = p_lead_id
               and (t.estado = 'consumida' or t.contrato_id is not null
                    or exists (select 1 from crm.ledger_rentabilidad r where r.solicitud_id = t.id))) then
    v_no := v_no || 'tiene una solicitud de tasa ya usada'::text;
  end if;
  if exists (select 1 from crm.solicitudes_tasa t
             where t.lead_id = p_lead_id
               and (t.cliente_id is not null or t.contrato_origen_id is not null or t.categoria is distinct from 'nuevo')) then
    v_no := v_no || 'tiene una solicitud de tasa de un cliente'::text;
  end if;
  -- Fichas de inversionista: solo si cada una es de este lead y no tiene dinero ni historia propia.
  if pg_catalog.cardinality(v_inv) > 0 then
    if exists (select 1 from crm.inversionistas i where i.id = any (v_inv) and i.perfil_id is not null)
       or exists (select 1 from crm.multiempresa_idempotencia m
                  where m.clave = any (select 'auth_persona:' || x::text from pg_catalog.unnest(v_inv) x)) then
      v_no := v_no || 'su ficha de inversionista tiene acceso de cliente (o un alta al portal en proceso)'::text; end if;
    -- Una ficha anterior al lead es una persona que ya existía, no un error de carga. Solo se acepta la que nació CON el
    -- lead: en producción, 1–2 ms antes y con el documento del propio lead (fuente «documento_lead»). Cualquier otra
    -- ficha más vieja que el lead se rechaza (Codex r2: la cercanía en el tiempo no prueba que nacieran juntas).
    if exists (select 1 from crm.inversionistas i
               where i.id = any (v_inv) and i.creado_en < v_lead.creado_en
                 and (i.creado_en < v_lead.creado_en - interval '1 second'
                      or exists (select 1 from crm.inversionista_identificadores d
                                 where d.inversionista_id = i.id and d.fuente is distinct from 'documento_lead')
                      or not exists (select 1 from crm.inversionista_identificadores d where d.inversionista_id = i.id))) then
      v_no := v_no || 'su ficha de inversionista ya existía antes del lead'::text; end if;
    if exists (select 1 from crm.inversionistas i where i.id = any (v_inv) and i.no_contactar) then
      v_no := v_no || 'la persona de su ficha pidió no ser contactada'::text; end if;
    if exists (select 1 from crm.leads o where o.inversionista_id = any (v_inv) and o.id <> p_lead_id)
       or exists (select 1 from crm.inversionista_leads o where o.inversionista_id = any (v_inv) and o.lead_id <> p_lead_id) then
      v_no := v_no || 'su ficha de inversionista también pertenece a otro lead'::text; end if;
    if exists (select 1 from crm.inversiones x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.inversion_titulares x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.cierres_externos x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.conversion_reservas x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.conversion_acreditaciones x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.postventa_operaciones x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.postventa_retiros x where x.inversionista_id = any (v_inv)) then
      v_no := v_no || 'su ficha de inversionista tiene inversiones o cierres'::text; end if;
    if exists (select 1 from crm.inversionistas i
               where i.id = any (v_inv) and (i.inversionista_canonico_id is not null or i.fusionado_en is not null))
       or exists (select 1 from crm.inversionistas o where o.inversionista_canonico_id = any (v_inv))
       or exists (select 1 from crm.inversionista_fusiones x where x.canonico_id = any (v_inv) or x.fusionado_id = any (v_inv)) then
      v_no := v_no || 'su ficha de inversionista está fusionada con otra'::text; end if;
    if exists (select 1 from crm.inversion_cotitular_origenes x
               where x.persona_origen_id = any (v_inv)
                  or x.identificador_origen_id in (select d.id from crm.inversionista_identificadores d where d.inversionista_id = any (v_inv)))
       or exists (select 1 from crm.inversionista_operaciones x
                  where x.inversionista_id = any (v_inv)
                     or x.identificador_anterior_id in (select d.id from crm.inversionista_identificadores d where d.inversionista_id = any (v_inv))
                     or x.identificador_nuevo_id in (select d.id from crm.inversionista_identificadores d where d.inversionista_id = any (v_inv)))
       or exists (select 1 from crm.tareas x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.busquedas_cliente_existente x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.backfill_multiempresa_mapa x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.inversionista_gestiones x where x.inversionista_id = any (v_inv) and x.tarea_id is not null) then
      v_no := v_no || 'su ficha de inversionista tiene historia propia (cotitulares, operaciones, tareas o búsquedas)'::text; end if;
  end if;
  -- Filas de OTROS leads que apuntan a las suyas (su ON DELETE SET NULL las reescribiría sin copia).
  if exists (select 1 from crm.tareas o
             where o.lead_id is distinct from p_lead_id
               and (o.reagendada_de in (select t.id from crm.tareas t where t.lead_id = p_lead_id)
                    or o.resultado_actividad_id in (select a.id from crm.actividades a where a.lead_id = p_lead_id)))
     or exists (select 1 from crm.llamadas_celular_enlaces o
                where o.lead_id is distinct from p_lead_id
                  and o.actividad_id in (select a.id from crm.actividades a where a.lead_id = p_lead_id)) then
    v_no := v_no || 'otro lead tiene tareas o llamadas enlazadas a las suyas'::text;
  end if;
  if v_lead.creado_en < pg_catalog.clock_timestamp() - pg_catalog.make_interval(days => c_dias_max) then
    v_no := v_no || pg_catalog.format('se creó hace más de %s días (%s)', c_dias_max,
                      pg_catalog.to_char(v_lead.creado_en at time zone 'America/Lima', 'DD/MM/YYYY'));
  end if;
  -- Mes cerrado (el candado de crm.cerrar_periodo ya está tomado arriba).
  select pg_catalog.string_agg(pg_catalog.to_char(pc.periodo, 'MM/YYYY'), ', ' order by pc.periodo) into v_meses
  from crm.periodos_cerrados pc
  where pc.periodo >= pg_catalog.date_trunc('month', v_lead.creado_en at time zone 'America/Lima')::date;
  if v_meses is not null then
    v_no := v_no || pg_catalog.format('aparece en un mes cerrado (%s)', v_meses);
  end if;
  if pg_catalog.cardinality(v_no) > 0 then
    raise exception 'No se puede eliminar este lead: %.', pg_catalog.array_to_string(v_no, '; ') using errcode = 'P0409';
  end if;

  -- Copia completa (cada fila bloqueada FOR UPDATE: lo copiado es exactamente lo que se borra).
  v_copia := pg_catalog.jsonb_build_object(
    'version', 3,
    'lead', pg_catalog.to_jsonb(v_lead),
    'tareas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.tareas x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'actividades_cliente', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.actividades_cliente x
            where x.tarea_id in (select t.id from crm.tareas t where t.lead_id = p_lead_id) for update) r), '[]'::jsonb),
    'tarea_sla_contexto', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.tarea_id)
      from (select * from crm.tarea_sla_contexto x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'actividad_ciclo_contexto', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.actividad_id)
      from (select * from crm.actividad_ciclo_contexto x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'actividades', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.actividades x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_asignaciones', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.lead_asignaciones x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_asignacion_sla_hitos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.lead_asignacion_id)
      from (select * from crm.lead_asignacion_sla_hitos x
            where x.lead_asignacion_id in (select a.id from crm.lead_asignaciones a where a.lead_id = p_lead_id)
            for update) r), '[]'::jsonb),
    'lead_sla_ciclos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.ciclo_n)
      from (select * from crm.lead_sla_ciclos x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_sla_etapas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.lead_sla_etapas x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_sla_etapa_ajustes', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.lead_sla_etapa_ajustes x
            where x.etapa_sla_id in (select e.id from crm.lead_sla_etapas e where e.lead_id = p_lead_id) for update) r),
      '[]'::jsonb),
    'sla_operacion_recibos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r))
      from (select * from crm.sla_operacion_recibos x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_potencial', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r))
      from (select * from crm.lead_potencial x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_potencial_eventos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r))
      from (select * from crm.lead_potencial_eventos x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'base_carga_leads', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.base_carga_leads x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'llamadas_celular_eventos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.llamadas_celular_eventos x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'llamadas_celular_enlaces', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.llamadas_celular_enlaces x
            where x.lead_id = p_lead_id
               or x.evento_id in (select e.id from crm.llamadas_celular_eventos e where e.lead_id = p_lead_id)
            for update) r), '[]'::jsonb),
    'llamadas_celular_intenciones', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from private.llamadas_celular_intenciones x
            where x.lead_id = p_lead_id
               or x.actividad_id in (select a.id from crm.actividades a where a.lead_id = p_lead_id)
            for update) r), '[]'::jsonb))
  || pg_catalog.jsonb_build_object(
    'solicitudes_tasa', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.solicitudes_tasa x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'envios_push_tasa', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.envios_push_tasa x
            where x.solicitud_id in (select t.id from crm.solicitudes_tasa t where t.lead_id = p_lead_id) for update) r),
      '[]'::jsonb),
    'inversion_solicitudes', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversion_solicitudes x
            where x.lead_origen_id = p_lead_id or x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_leads', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionista_leads x
            where x.lead_id = p_lead_id or x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionistas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionistas x where x.id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_identificadores', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionista_identificadores x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_responsables', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionista_responsables x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_gestiones', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionista_gestiones x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'cartera_lecturas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.cartera_lecturas x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_datos_contacto', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.inversionista_id)
      from (select * from crm.inversionista_datos_contacto x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb));
  select pg_catalog.jsonb_object_agg(e.key, pg_catalog.jsonb_array_length(e.value)) into v_filas
  from pg_catalog.jsonb_each(v_copia) e where pg_catalog.jsonb_typeof(e.value) = 'array';

  -- Un CHECK fallido devolvería «Failing row contains (…)» con la copia (datos personales): se responde sin detalle.
  begin
    insert into crm.leads_eliminados (lead_id, motivo, eliminado_por, rol_actor, copia, filas)
    values (p_lead_id, v_motivo, v_uid, v_rol, v_copia, v_filas)
    returning id into v_id;
  exception when check_violation or not_null_violation or unique_violation then
    raise exception 'No se pudo guardar la copia del lead; no se eliminó nada' using errcode = '55000';
  end;

  -- Permiso de borrado de ESTE lead, solo en esta transacción; los candados exigen además la fila en la copia.
  perform pg_catalog.set_config('crm.borrado_lead_error', p_lead_id::text, true);

  -- Orden por llaves foráneas (RESTRICT/NO ACTION primero). Cada DELETE tiene que borrar EXACTAMENTE lo copiado.
  delete from crm.actividad_ciclo_contexto x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('actividad_ciclo_contexto', v_n);
  delete from crm.tarea_sla_contexto x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('tarea_sla_contexto', v_n);
  delete from crm.lead_asignacion_sla_hitos x
  where x.lead_asignacion_id in (select a.id from crm.lead_asignaciones a where a.lead_id = p_lead_id);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_asignacion_sla_hitos', v_n);
  delete from crm.lead_sla_etapa_ajustes x
  where x.etapa_sla_id in (select e.id from crm.lead_sla_etapas e where e.lead_id = p_lead_id);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_sla_etapa_ajustes', v_n);
  delete from crm.actividades_cliente x where x.tarea_id in (select t.id from crm.tareas t where t.lead_id = p_lead_id);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('actividades_cliente', v_n);
  delete from crm.tareas x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('tareas', v_n);
  delete from crm.sla_operacion_recibos x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('sla_operacion_recibos', v_n);
  delete from crm.lead_potencial_eventos x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_potencial_eventos', v_n);
  delete from crm.lead_potencial x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_potencial', v_n);
  delete from crm.base_carga_leads x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('base_carga_leads', v_n);
  delete from crm.actividades x where x.lead_id = p_lead_id;   -- cascada: intenciones; los enlaces quedan sin actividad
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('actividades', v_n);
  delete from crm.lead_sla_etapas x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_sla_etapas', v_n);
  delete from crm.lead_sla_ciclos x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_sla_ciclos', v_n);
  delete from crm.lead_asignaciones x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_asignaciones', v_n);
  delete from crm.envios_push_tasa x
  where x.solicitud_id in (select t.id from crm.solicitudes_tasa t where t.lead_id = p_lead_id);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('envios_push_tasa', v_n);
  delete from crm.solicitudes_tasa x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('solicitudes_tasa', v_n);
  delete from crm.inversion_solicitudes x where x.lead_origen_id = p_lead_id or x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversion_solicitudes', v_n);
  delete from crm.inversionista_leads x where x.lead_id = p_lead_id or x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_leads', v_n);
  delete from crm.leads x where x.id = p_lead_id;               -- cascada: llamadas del celular (sus candados la aceptan)
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'La eliminación no cuadró con la copia; no se aplicó nada' using errcode = '55000';
  end if;
  -- Las fichas de inversionista, ya sin lead.
  delete from crm.inversionista_identificadores x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_identificadores', v_n);
  delete from crm.inversionista_responsables x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_responsables', v_n);
  delete from crm.inversionista_gestiones x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_gestiones', v_n);
  delete from crm.cartera_lecturas x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('cartera_lecturas', v_n);
  delete from crm.inversionista_datos_contacto x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_datos_contacto', v_n);
  delete from crm.inversionistas x where x.id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionistas', v_n);

  perform pg_catalog.set_config('crm.borrado_lead_error', coalesce(v_previa, ''), true);

  -- Un alta al portal que empezó mientras se borraba (su saga no tiene FK a la ficha): se deshace todo y se reintenta.
  if exists (select 1 from crm.multiempresa_idempotencia m
             where m.clave = any (select 'auth_persona:' || x::text from pg_catalog.unnest(v_inv) x)) then
    raise exception 'La ficha empezó un alta al portal mientras se eliminaba; no se aplicó nada' using errcode = '40001';
  end if;

  -- Cuadre: lo borrado = lo copiado, tabla por tabla; y de las cascadas no queda ninguna fila copiada.
  if exists (select 1 from pg_catalog.jsonb_each(v_cuadre) d where d.value <> v_filas -> d.key)
     or exists (select 1 from crm.llamadas_celular_eventos x
                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_eventos') e))
     or exists (select 1 from crm.llamadas_celular_enlaces x
                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_enlaces') e))
     or exists (select 1 from private.llamadas_celular_intenciones x
                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_intenciones') e)) then
    raise exception 'La eliminación no cuadró con la copia; no se aplicó nada' using errcode = '55000';
  end if;

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'copia_id', v_id, 'filas', v_filas);
end $function$;

revoke all on function private.recorrido_contexto_guard(),private.recorrido_bloquear_insert(),private.recorrido_capturar_actividad(),
  private.recorrido_serializar_invalidacion(),private.recorrido_control_guard(),private.recorrido_evaluar(uuid[])
  from public,anon,authenticated,service_role;
revoke all on function crm.recorrido_configurar_fn(text,text,integer,timestamptz),crm.recorrido_leads_fn(uuid[])
  from public,anon,authenticated,service_role;
grant execute on function crm.recorrido_configurar_fn(text,text,integer,timestamptz),crm.recorrido_leads_fn(uuid[])
  to authenticated;
notify pgrst,'reload schema';
commit;
