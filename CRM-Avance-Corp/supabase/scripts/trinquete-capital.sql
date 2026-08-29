-- TRINQUETE DE CAPITAL (P-055 F4) — corre en cada ciclo de banco.
-- La regla ESTRUCTURAL: fuera de private.capital_episodios, NINGUNA funcion
-- agrega las columnas-fuente crudas del capital. Tope alcanzado el 29/08: CERO.
-- Este numero NO puede subir jamas; toda excepcion exige editar este archivo
-- con su justificacion (queda en el diff).
do $trinquete$
declare
  v_hoy int;
  v_tope constant int := 0;  -- ⬇ CERO desde 2026-08-29. NO SUBE.
  v_lista text;
begin
  select count(*), string_agg(n.nspname||'.'||p.proname, ', ')
    into v_hoy, v_lista
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('crm', 'public', 'private')
    and p.prokind = 'f'
    and p.proname not in ('capital_episodios')
    and (p.prosrc ~* 'sum\s*\(\s*(c|ct|ce|c0)\.(capital|monto)\b'
      or p.prosrc ~* 'sum\s*\(\s*(o|o0)\.(capital_renovado|capital_adicional)\b');

  if v_hoy > v_tope then
    raise exception 'TRINQUETE ROTO: % calculadora(s) de capital fuera del nucleo [%]. Toda suma de capital nace en private.capital_episodios.', v_hoy, v_lista;
  end if;
  raise notice 'TRINQUETE OK: 0 calculadoras de capital fuera del nucleo';
end
$trinquete$;
