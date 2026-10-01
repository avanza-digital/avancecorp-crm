-- ENCENDER la marca de potencial del lead (bandera 'potencial_lead').
-- Lo lanza Miguel con `!` cuando la pantalla (fase 3, entrega A) YA está publicada. Desde ese instante
-- la puerta de marcar escribe y la de lectura entrega marcas. UN solo UPDATE, en su propia transacción
-- corta. Se niega si falta alguna pieza: sin la tarea diaria las marcas no bajarían solas, y sin la
-- puerta de lectura la pantalla no las vería. Para apagar: apagar-bandera.sql.
-- El cambio toma el candado exclusivo `crm_flag_potencial_lead` (disparador que serializa las banderas).
-- Bitácora: trg_audit_multiempresa_flags lo registra en public.audit_log; desde `db query` el actor
-- queda vacío, así que hay que anotar en MIGRACIONES.md quién la encendió y cuándo.
-- Después, verificar-lectura.sql debe decir «bandera true».
begin;
set local lock_timeout = '30s';
do $chk$
begin
  if (
    pg_catalog.to_regprocedure('crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)') is not null
    and pg_catalog.to_regprocedure('crm.potencial_leads_fn(uuid[])') is not null
    and pg_catalog.to_regprocedure('private.potencial_caducar(date,timestamp with time zone,integer)') is not null
    and exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'ENCENDER potencial_lead: falta la fase 1, la fase 2, la puerta de lectura o la fila de la bandera; no se enciende';
  end if;
  if pg_catalog.to_regclass('cron.job') is null then
    raise exception 'ENCENDER potencial_lead: no hay pg_cron; sin la tarea diaria las marcas no bajarían solas';
  end if;
  if not exists (select 1 from cron.job j
                 where j.jobname = 'crm-potencial-lead-caducidad' and j.active and j.schedule = '10,40 10 * * *') then
    raise exception 'ENCENDER potencial_lead: la tarea crm-potencial-lead-caducidad no está activa con su horario; no se enciende';
  end if;
end;
$chk$;
update crm.multiempresa_flags set activo = true, actualizado_en = pg_catalog.now() where nombre = 'potencial_lead';
do $post$
begin
  if (select f.activo from crm.multiempresa_flags f where f.nombre = 'potencial_lead') is not true then
    raise exception 'ENCENDER potencial_lead: la bandera no quedó encendida';
  end if;
  raise notice 'ENCENDER potencial_lead OK: bandera encendida; marcas existentes %.', (select pg_catalog.count(*) from crm.lead_potencial);
end;
$post$;
commit;
