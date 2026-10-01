-- REVERSA de 20260930235917_crm_potencial_lead_caducidad (fase 2).
-- Desprograma el job (si existe) y quita las cuatro funciones. Los eventos con motivo 'caducidad'
-- ya escritos SE QUEDAN: son historial inmutable, y los niveles bajados no se «suben» solos (una
-- persona vuelve a marcar si quiere). Conserva la fila de schema_migrations: anotarlo en
-- MIGRACIONES.md. Debe correr ANTES que la reversa de la fase 1.
-- Codex f2 r1 F3: todo lo que nombra cron.job va en un IF propio (plpgsql prepara cada expresión al
-- llegar a ella), para que funcione también en una base sin pg_cron.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if (
    pg_catalog.to_regprocedure('private.potencial_caducar(date,timestamp with time zone,integer)') is not null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is not null
  ) is not true then
    raise exception 'REVERSA potencial_caducidad: la fase 2 no está aplicada';
  end if;
  if pg_catalog.to_regclass('cron.job') is not null and pg_catalog.to_regprocedure('cron.unschedule(text)') is not null then
    if exists (select 1 from cron.job where jobname = 'crm-potencial-lead-caducidad') then
      perform cron.unschedule('crm-potencial-lead-caducidad');
    end if;
  end if;
end;
$chk$;

drop function private.potencial_caducar(date, timestamptz, integer);
drop function private.potencial_nivel_tras(crm.nivel_potencial, integer);
drop function private.potencial_reloj(uuid, timestamptz, timestamptz);
drop function private.dias_lunes_a_sabado(date, date);

do $post$
begin
  if (
    pg_catalog.to_regprocedure('private.potencial_caducar(date,timestamp with time zone,integer)') is null
    and pg_catalog.to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is null
    and pg_catalog.to_regprocedure('private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)') is null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is null
  ) is not true then
    raise exception 'REVERSA potencial_caducidad: quedaron funciones';
  end if;
  if pg_catalog.to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname = 'crm-potencial-lead-caducidad') then
      raise exception 'REVERSA potencial_caducidad: quedó el job';
    end if;
  end if;
  raise notice 'REVERSA potencial_caducidad OK: sin job ni funciones (el historial se conserva).';
end;
$post$;
commit;
