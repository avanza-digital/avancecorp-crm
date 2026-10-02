-- REVERSA de 20260930213647_crm_potencial_lead.
-- Solo mientras la función no se usó: se niega si hay una sola marca o evento, o si la bandera
-- está encendida (regla de la casa: en producción no se borra lo que tiene datos; con datos se
-- CIERRA con la bandera y se observa). Conserva la fila de schema_migrations: anotar la reversa
-- en MIGRACIONES.md.
-- Codex r1 F2: los candados se toman ANTES de comprobar el vacío y se sostienen hasta el commit.
-- Una marca en vuelo termina antes (y la reversa la ve y se niega) o espera a la reversa (y
-- muere porque la puerta ya no existe).
-- Codex r2 R2-3 (medido en el banco): DROP TABLE de las tablas nuevas toma AccessExclusiveLock
-- sobre crm.leads y public.perfiles (las tablas a las que apuntan sus FK). Una marca en vuelo
-- tiene RowShare sobre crm.leads (FOR SHARE); si la reversa bloqueara primero las tablas nuevas,
-- se formaba un ciclo. Orden fijo: bandera → crm.leads y public.perfiles → tablas nuevas.
-- ⚠️ Mientras dura (milisegundos, o hasta 3 s esperando) nadie lee crm.leads ni public.perfiles
-- (portal): correr en horario bajo; si salta el lock_timeout, reintentar.
begin;
set local lock_timeout = '3s';
do $chk$
begin
  if (
    pg_catalog.to_regclass('crm.lead_potencial') is not null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is not null
  ) is not true then
    raise exception 'REVERSA potencial_lead: la migración no está aplicada (faltan las tablas)';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'private' and p.proname = 'potencial_caducar') then
    raise exception 'REVERSA potencial_lead: la fase 2 (caducidad) sigue aplicada; corre antes reversa-caducidad.sql';
  end if;
  -- El filtro de Leads (fase 3B) lee crm.lead_potencial desde private.cartera_potencial_fn: sin la
  -- tabla, la cartera entera fallaría con la bandera encendida (auditor-rls f3b). Primero su reversa.
  if pg_catalog.to_regprocedure('private.cartera_potencial_fn()') is not null then
    raise exception 'REVERSA potencial_lead: el filtro de Leads (fase 3B) sigue aplicado; corre antes reversa-filtro.sql';
  end if;
end;
$chk$;

select 1 from crm.multiempresa_flags where nombre = 'potencial_lead' for update;
lock table crm.leads, public.perfiles in access exclusive mode;
lock table crm.lead_potencial, crm.lead_potencial_eventos in access exclusive mode;

do $vacio$
begin
  if (
    (select count(*) from crm.lead_potencial) = 0
    and (select count(*) from crm.lead_potencial_eventos) = 0
    and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'potencial_lead'), false) = false
  ) is not true then
    raise exception 'REVERSA potencial_lead: hay marcas, eventos o la bandera está encendida; apaga la bandera y no borres datos';
  end if;
end;
$vacio$;

drop function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial);
drop function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial);
drop function private.potencial_rechazo(uuid, uuid);
drop function private.potencial_bloquear_lead(uuid);
drop table crm.lead_potencial_eventos;
drop table crm.lead_potencial;
drop function private.potencial_evento_inmutable();
drop type crm.nivel_potencial;
delete from crm.multiempresa_flags where nombre = 'potencial_lead' and activo = false;

do $post$
begin
  if (
    pg_catalog.to_regtype('crm.nivel_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is null
    and not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                    where (n.nspname = 'crm' and p.proname = 'marcar_potencial_lead_fn')
                       or (n.nspname = 'private' and p.proname in ('potencial_rechazo', 'potencial_marcar_nucleo',
                                                                   'potencial_evento_inmutable', 'potencial_bloquear_lead')))
    and not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'REVERSA potencial_lead: quedaron objetos';
  end if;
  raise notice 'REVERSA potencial_lead OK: sin objetos ni bandera.';
end;
$post$;
commit;
