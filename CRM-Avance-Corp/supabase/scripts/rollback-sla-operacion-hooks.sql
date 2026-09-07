-- CONTINGENCIA SELECTIVA N2. No forma parte de las migraciones normales.
-- Primero confirmar modo legado por RPC y detener publicacion/activacion.
-- Conserva datos, recibos, RLS, clocks y locks fuertes de todos los writers.
-- Si no consigue los locks en 5 s, revierte ENTERA; no elevar timeout a ciegas.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- DDL sobre captura y barrera de los INSERT en vuelo. El control es el ultimo
-- lock de fila, igual que los writers; tras obtenerlo se revalida el modo.
lock table crm.leads,crm.tareas,crm.actividades in share row exclusive mode;
do $guard$
declare v_modo text;
begin
  select modo into strict v_modo from crm.sla_operacion_control where id for update;
  if v_modo<>'legado' then raise exception 'Confirma modo legado antes de retirar hooks SLA' using errcode='55000';end if;
  if to_regprocedure('private.sla_gesto_abrir(uuid)') is null then
    raise exception 'N2 no instalado; reconciliar contingencia';end if;
end;
$guard$;

drop trigger if exists trg_tareas_03_sla_contexto on crm.tareas;

-- Comportamiento comercial previo: solo conversaciones suben Nuevo.
-- Se retienen el lock fuerte y la restauracion del setting previo.
create or replace function private.trg_actividades_avance_etapa()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_previo text:=coalesce(current_setting('crm.avance_auto',true),'off');
begin
  if v_previo='on' or new.lead_id is null
    or new.tipo not in ('llamada_realizada','whatsapp_recibido','reunion_realizada') then return null;end if;
  perform 1 from crm.leads where id=new.lead_id for update;
  perform set_config('crm.avance_auto','on',true);
  update crm.leads set etapa='contactado' where id=new.lead_id and activo and etapa='nuevo';
  perform set_config('crm.avance_auto',v_previo,true);
  return null;
end;
$function$;
revoke all on function private.trg_actividades_avance_etapa() from public,anon,authenticated,service_role;

-- Las firmas invocadas por N3/v1 siguen existiendo. Ningun recibo ni gesto
-- comercial falla por un helper retirado; los locks permanecen en sus writers.
create or replace function private.sla_gesto_abrir(p_lead_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  if p_lead_id is not null then
    perform 1 from crm.leads where id=p_lead_id for update;
    if not found then raise exception 'Lead no encontrado' using errcode='P0002';end if;
  end if;
  return null;
end;
$function$;
revoke all on function private.sla_gesto_abrir(uuid) from public,anon,authenticated,service_role;

create or replace function private.sla_gesto_cerrar(p_actividad_id uuid,p_contexto jsonb)
returns uuid language sql security definer set search_path=''
as $function$ select null::uuid; $function$;
revoke all on function private.sla_gesto_cerrar(uuid,jsonb) from public,anon,authenticated,service_role;

-- El gate normal DEBE detectar hooks retirados: cambiar modo hacia activo u
-- observacion lo llama y queda cerrado. Legado sigue disponible. La recuperacion
-- exige nueva migracion revisada + reconstruccion del intervalo, nunca borrar
-- primera_activacion_en, politica_adopcion_id, contextos ni ajustes consumidos.
do $verify$
begin
  if exists(select 1 from pg_trigger where tgrelid='crm.tareas'::regclass
    and tgfoid='private.trg_sla_tarea_contexto()'::regprocedure and not tgisinternal) then
    raise exception 'Captura no retirada';end if;
  if position('for update' in lower(pg_get_functiondef('private.trg_tareas_before_insert()'::regprocedure)))=0 then
    raise exception 'Falta lock fuerte de tarea';end if;
  if position('assert_sla_operacion' in pg_get_functiondef('crm.cambiar_modo_sla_operacion(integer,text)'::regprocedure))=0 then
    raise exception 'Reactivacion no protege hooks incompletos';end if;
end;
$verify$;
commit;
