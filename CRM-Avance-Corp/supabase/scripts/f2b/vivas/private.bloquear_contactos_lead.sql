CREATE OR REPLACE FUNCTION private.bloquear_contactos_lead(p_telefonos text[], p_dnis text[])
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_clave text;
begin
  for v_clave in
    select claves.clave
    from (
      select distinct 'telefono:' || private.normalizar_telefono(t.valor) as clave
      from pg_catalog.unnest(coalesce(p_telefonos, array[]::text[])) as t(valor)
      where nullif(pg_catalog.btrim(coalesce(t.valor, '')), '') is not null

      union

      select distinct 'dni:' || pg_catalog.btrim(d.valor) as clave
      from pg_catalog.unnest(coalesce(p_dnis, array[]::text[])) as d(valor)
      where nullif(pg_catalog.btrim(coalesce(d.valor, '')), '') is not null
    ) as claves
    where claves.clave is not null
    order by claves.clave
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('avancecrm:lead:' || v_clave, 0)
    );
  end loop;
end;
$function$

