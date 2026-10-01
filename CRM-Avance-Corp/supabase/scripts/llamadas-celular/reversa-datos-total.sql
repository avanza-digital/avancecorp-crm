-- Reversa de 20261001145242_crm_llamadas_celular_datos.sql · variante TOTAL (borra las tablas).
--
-- SE NIEGA si hay llamadas o asignaciones registradas: la evidencia no se destruye con una
-- reversa; primero se decide qué hacer con ella (exportar, conservar con `reversa-datos.sql`).
-- Pensada para el banco y para una rama en la que la migración se aplicó y se descarta.
--
-- Molde: scripts/cuentas-gloria/reversa-retirar-cuenta-cliente.sql. Uso:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-datos-total.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
declare
  v_eventos bigint;
  v_asignaciones bigint;
begin
  if to_regclass('crm.llamadas_celular_eventos') is null then
    raise exception 'REVERSA_LLAMADAS_TOTAL: la migración 20261001145242 no está aplicada';
  end if;
  lock table crm.llamadas_celular_eventos, crm.celulares_asignaciones in access exclusive mode;
  select count(*) into v_eventos from crm.llamadas_celular_eventos;
  select count(*) into v_asignaciones from crm.celulares_asignaciones;
  if v_eventos > 0 or v_asignaciones > 0 then
    raise exception 'REVERSA_LLAMADAS_TOTAL: hay % llamadas y % asignaciones registradas; la evidencia no se borra con una reversa',
      v_eventos, v_asignaciones;
  end if;
end;
$precondicion$;

-- La consulta a cron.job va ANIDADA: en la misma condición se analiza aunque pg_cron no exista.
do $reloj$
begin
  if to_regprocedure('cron.unschedule(text)') is not null then
    if exists (select 1 from cron.job j where j.jobname = 'crm-llamadas-celular-caducidad') then
      perform cron.unschedule('crm-llamadas-celular-caducidad');
    end if;
  end if;
end;
$reloj$;

drop function if exists private.caducar_llamadas_celular();

-- Las tablas: enlaces → eventos → asignaciones → política (los triggers caen con ellas).
drop table if exists crm.llamadas_celular_enlaces;
drop table if exists crm.llamadas_celular_eventos;
drop table if exists crm.celulares_asignaciones;
drop table if exists crm.llamadas_celular_politica;

drop function if exists private.trg_llamadas_celular_enlaces_candado();
drop function if exists private.trg_llamadas_celular_eventos_candado();
drop function if exists private.trg_celulares_asignaciones_candado();
drop function if exists private.trg_llamadas_celular_politica_candado();
drop function if exists private.trg_llamadas_celular_sin_vaciar();

do $postcheck$
begin
  if to_regclass('crm.llamadas_celular_politica') is not null
     or to_regclass('crm.celulares_asignaciones') is not null
     or to_regclass('crm.llamadas_celular_eventos') is not null
     or to_regclass('crm.llamadas_celular_enlaces') is not null
     or to_regprocedure('private.caducar_llamadas_celular()') is not null
     or to_regprocedure('private.trg_llamadas_celular_sin_vaciar()') is not null then
    raise exception 'REVERSA_LLAMADAS_TOTAL: quedaron objetos sin retirar';
  end if;
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    if exists (select 1 from cron.job j where j.jobname = 'crm-llamadas-celular-caducidad') then
      raise exception 'REVERSA_LLAMADAS_TOTAL: el job de retención sigue programado';
    end if;
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;
