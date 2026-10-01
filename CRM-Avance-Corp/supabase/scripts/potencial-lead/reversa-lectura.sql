-- REVERSA de 20261001151704_crm_potencial_lead_lectura (fase 3, entrega A).
-- Quita la puerta de lectura, su núcleo y sus dos ayudantes. No hay datos que perder: las marcas y
-- su historial son de las fases 1 y 2 y se quedan. Con la puerta quitada, la pantalla recibe
-- «función inexistente» y lo trata como potencial apagado (no pinta nada). Conserva la fila de
-- schema_migrations: anotarlo en MIGRACIONES.md. Debe correr ANTES que las reversas de las fases 2 y 1.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if (
    pg_catalog.to_regprocedure('crm.potencial_leads_fn(uuid[])') is not null
    and pg_catalog.to_regprocedure('private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)') is not null
    and pg_catalog.to_regprocedure('private.potencial_proxima_baja(crm.nivel_potencial,date,date)') is not null
    and pg_catalog.to_regprocedure('private.potencial_proxima_corrida(timestamp with time zone)') is not null
  ) is not true then
    raise exception 'REVERSA potencial_lectura: la puerta de lectura no está aplicada';
  end if;
end;
$chk$;

drop function crm.potencial_leads_fn(uuid[]);
drop function private.potencial_lectura(uuid, uuid[], date, timestamptz, date);
drop function private.potencial_proxima_baja(crm.nivel_potencial, date, date);
drop function private.potencial_proxima_corrida(timestamptz);

do $post$
begin
  if exists (
    select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where (n.nspname = 'crm' and p.proname = 'potencial_leads_fn')
       or (n.nspname = 'private' and p.proname in ('potencial_lectura', 'potencial_proxima_baja', 'potencial_proxima_corrida'))
  ) then
    raise exception 'REVERSA potencial_lectura: quedaron funciones';
  end if;
  raise notice 'REVERSA potencial_lectura OK: sin puerta ni ayudantes de lectura (las marcas se conservan).';
end;
$post$;
commit;
