-- ORACULO F2 ACCESO — SOLO en banco. Verifica que el mapa y las funciones del
-- backfill estan CERRADOS a la Data API (contrato §14). Hace rollback.
begin;
do $ora$
declare v_rol text;
begin
  -- El mapa: cero privilegio directo para los 3 roles de la API.
  foreach v_rol in array array['anon','authenticated','service_role'] loop
    if has_table_privilege(v_rol,'crm.backfill_multiempresa_mapa','SELECT')
       or has_table_privilege(v_rol,'crm.backfill_multiempresa_mapa','INSERT')
       or has_table_privilege(v_rol,'crm.backfill_multiempresa_mapa','UPDATE')
       or has_table_privilege(v_rol,'crm.backfill_multiempresa_mapa','DELETE') then
      raise exception 'ORACULO F2 ACCESO: % alcanza el mapa por la Data API', v_rol;
    end if;
    if has_function_privilege(v_rol,'private.backfill_multiempresa_ejecutar()','EXECUTE') then
      raise exception 'ORACULO F2 ACCESO: % puede ejecutar el backfill', v_rol;
    end if;
  end loop;
  -- RLS activa + policy de solo-gerencia (defensa en profundidad).
  if not (select relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='crm' and c.relname='backfill_multiempresa_mapa') then
    raise exception 'ORACULO F2 ACCESO: el mapa sin RLS';
  end if;
  if not exists (select 1 from pg_policies where schemaname='crm' and tablename='backfill_multiempresa_mapa' and cmd='SELECT') then
    raise exception 'ORACULO F2 ACCESO: el mapa sin policy SELECT gateada';
  end if;
  raise notice 'ORACULO F2 ACCESO VERDE: mapa y backfill cerrados a la Data API; RLS + policy gerencia.';
end
$ora$;
rollback;
