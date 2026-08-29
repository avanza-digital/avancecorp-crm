-- TRINQUETE DE CAPITAL (F4 del P-055) — borrador, corre en el gate del banco.
-- Regla ESTRUCTURAL (no lista blanca): fuera de `private`, ninguna funcion
-- puede AGREGAR las columnas-fuente crudas del capital. La constante SOLO
-- BAJA: hoy 16; meta 0 al cierre de la Fase 4. Toda excepcion exige editar
-- este archivo con su justificacion (queda en el diff).
do $trinquete$
declare
  v_hoy int;
  v_tope constant int := 16;  -- ⬇ SOLO PUEDE BAJAR. 2026-08-29: los 16 de D8.
begin
  select count(*) into v_hoy
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('crm', 'public')
    and p.prokind = 'f'
    and p.prosrc ~* 'sum\s*\(\s*(coalesce\s*\(\s*)?([a-z_]+\.)?"?capital';

  if v_hoy > v_tope then
    raise exception 'TRINQUETE: % funciones agregan capital fuera de private (tope %). Una calculadora nueva nacio fuera del nucleo.', v_hoy, v_tope;
  end if;
  if v_hoy < v_tope then
    raise notice 'TRINQUETE: % < tope % — apretar la constante en este archivo.', v_hoy, v_tope;
  end if;
  raise notice 'TRINQUETE OK: % calculadoras de capital fuera de private (tope %)', v_hoy, v_tope;
end
$trinquete$;
