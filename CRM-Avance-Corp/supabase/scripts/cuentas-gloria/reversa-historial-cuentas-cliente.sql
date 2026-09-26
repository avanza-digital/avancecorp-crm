-- REVERSA de 20260926193424_crm_historial_cuentas_cliente.
-- Borra SOLO las dos funciones nuevas (lectura; ninguna otra función, vista ni política las
-- usa). No toca datos. Se niega si algo del catálogo depende de ellas.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if exists (
    select 1 from pg_catalog.pg_depend d
    where d.refobjid in (
      coalesce(to_regprocedure('crm.historial_cuentas_cliente_fn(uuid)')::oid, 0),
      coalesce(to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)')::oid, 0))
      and d.deptype = 'n'
  ) then
    raise exception 'REVERSA: hay objetos que dependen del historial; revisar antes de borrar';
  end if;
end $chk$;
drop function if exists crm.historial_cuentas_cliente_fn(uuid);
drop function if exists private.historial_cuentas_cliente_autorizado(uuid);
notify pgrst, 'reload schema';
commit;
