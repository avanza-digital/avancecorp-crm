-- REVERSA de 20260926193424_crm_historial_cuentas_cliente.
-- Borra SOLO las dos funciones nuevas (lectura; ninguna otra función, vista ni política las
-- usa). No toca datos. Se niega si algo del catálogo depende de ellas.
begin;
set local lock_timeout = '5s';
do $firma$
declare v_firma text;
begin
  -- Firma completa de las dos funciones: cuerpo, SECURITY, search_path y comentario.
  select pg_catalog.string_agg(p.proname || '|' || pg_catalog.md5(p.prosrc) || '|' || p.prosecdef
           || '|' || pg_catalog.array_to_string(p.proconfig, ',') || '|'
           || pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')), ';' order by p.proname)
    into v_firma
  from pg_catalog.pg_proc p
  where p.oid in (to_regprocedure('crm.historial_cuentas_cliente_fn(uuid)'),
                  to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)'));
  if v_firma is distinct from 'historial_cuentas_cliente_autorizado|22019f9bee83548f756ef3de03157b1a|true|search_path=""|1b76d52290ff6fc83a529431ef9ffc17;historial_cuentas_cliente_fn|83f7b235db051264bd6672450248912e|false|search_path=""|e83e854caa962f70c2dfd229ec72142f' then
    raise exception 'REVERSA: las funciones vivas no son exactamente la F2 (20260926193424); revierte antes la F2b';
  end if;
end;
$firma$;
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
