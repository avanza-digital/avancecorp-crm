-- ============================================================================
-- REVERSA de RENTABILIDAD R1 (20260906170000): suelta política, solicitudes, ledger, núcleo y puertas; desregistra la versión.
-- Repetible dos veces. No toca nada de `public` ni ninguna puerta de escritura de contratos (la migración tampoco lo hizo).
-- ⚠️ Se pierde el ledger y las solicitudes: antes de correrla en producción, exportar crm.ledger_rentabilidad y
-- crm.solicitudes_tasa si se quiere conservar el rastro (la reversa hace DROP, no rename).
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r1'));
do $pre$
declare v_n bigint;
begin
  -- No se suelta a ciegas: si hay solicitudes ya CONSUMIDAS (R4) o filas de observación/enforcement en el ledger (R2/R4),
  -- esta reversa no corresponde a R1. (EXECUTE dinámico: la tabla puede no existir ya —reversa repetible—.)
  if to_regclass('crm.solicitudes_tasa') is not null then
    execute 'select count(*) from crm.solicitudes_tasa where estado = ''consumida''' into v_n;
    if v_n > 0 then
      raise exception 'REVERSA R1: hay % solicitudes consumidas (R4 ya aterrizó); revierte primero R4', v_n;
    end if;
  end if;
  if to_regclass('crm.ledger_rentabilidad') is not null then
    execute 'select count(*) from crm.ledger_rentabilidad where origen <> ''backfill_legacy''' into v_n;
    if v_n > 0 then
      raise exception 'REVERSA R1: el ledger tiene % filas de observación/enforcement (R2/R4 ya aterrizaron); revierte primero esas', v_n;
    end if;
  end if;
end
$pre$;
drop function if exists crm.publicar_politica_rentabilidad_fn(integer, jsonb);
drop function if exists crm.responder_tope_tasa_fn(uuid, boolean, text);
drop function if exists crm.resolver_solicitud_tasa_fn(uuid, text, numeric, text);
drop function if exists crm.solicitar_tasa_fn(jsonb);
drop function if exists crm.resolver_tasa_fn(uuid, text, uuid);
-- Primero las funciones que dependen del tipo de fila de la política (resolver_tasa y politica_rentabilidad_vigente
-- devuelven/declaran crm.politica_rentabilidad), luego las tablas (ledger → solicitudes → política, por las FK).
drop function if exists private.vencer_solicitudes_tasa();
drop function if exists private.huella_solicitud_tasa(uuid, text, uuid, uuid, numeric, text, text, text, date, date);
drop function if exists private.puede_operar_tasa_cliente(uuid);
drop function if exists private.resolver_tasa(uuid, text, uuid, timestamptz);
drop function if exists private.politica_rentabilidad_vigente(timestamptz);
drop table if exists crm.ledger_rentabilidad;
drop table if exists crm.solicitudes_tasa;
drop table if exists crm.politica_rentabilidad;
drop function if exists private.trg_solicitudes_tasa_solo_por_puerta();
drop function if exists private.trg_ledger_rentabilidad_append_only();
do $post$
begin
  if to_regclass('crm.politica_rentabilidad') is not null or to_regclass('crm.solicitudes_tasa') is not null
     or to_regclass('crm.ledger_rentabilidad') is not null or to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz)') is not null
     or to_regprocedure('crm.resolver_tasa_fn(uuid,text,uuid)') is not null then
    raise exception 'REVERSA R1: quedó algún objeto vivo';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906170000';
  raise notice 'REVERSA RENTABILIDAD R1 OK (versión 20260906170000 desregistrada si estaba)';
end
$post$;
commit;
