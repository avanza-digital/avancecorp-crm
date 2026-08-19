#!/usr/bin/env bash
# Aplica a PRODUCCIÓN la migración 20260819211815 — el domicilio legal con una
# sola puerta y el listón a la altura del dato.
#
# ⚠️ ORDEN: esta vez la PANTALLA va PRIMERO y el servidor después. Es al revés
# que por la mañana, y no es un capricho: aquí no hay funciones nuevas que el
# front necesite, sino una validación que se APRIETA. Con la pantalla nueva y el
# servidor viejo no se rompe nada (el navegador frena antes y el servidor habría
# aceptado). Al revés, el vendedor teclearía algo que su pantalla admite y el
# servidor le rechazaría al guardar.
#
# Ensayado al completo en el banco `domicilio-una-puerta`: postflight 1 y 3 OK
# con datos, oráculo 10/10, gate RLS 352✓ (bloque del domicilio 32/32), asesores
# con delta CERO.
#
# La sonda POSTFLIGHT 2 avisa en vez de aprobar cuando no hay domicilios que
# medir. Aquí SÍ los hay: medido contra producción el 2026-08-19 → 22
# domicilios, 0 por debajo de 15 caracteres, 0 sin número. Debe salir OK, no
# WARNING. Si sale WARNING, algo va mal: PARA.
set -euo pipefail
cd "$(dirname "$0")"
export SUPABASE_ACCESS_TOKEN="$(security find-generic-password -s 'Supabase CLI' -w)"
S=$(mktemp -d)

echo "── 1/3 · aplicando (lee el POSTFLIGHT 2: tiene que decir OK, no WARNING) ──"
npx --yes supabase@latest db query --linked \
  --file supabase/migrations/20260819211815_crm_domicilio_una_sola_puerta.sql

echo "── 2/3 · registrando en el índice ────────────────────────────────────────"
printf "insert into supabase_migrations.schema_migrations(version) values ('20260819211815') on conflict do nothing;\n" > "$S/reg.sql"
npx --yes supabase@latest db query --linked --file "$S/reg.sql"

echo "── 3/3 · comprobando por CONTEO, no por lo que dijo el comando ───────────"
cat > "$S/ver.sql" <<'SQL'
-- El listón se comprueba EJECUTÁNDOLO: cada relleno tiene que levantar 22023 y
-- una dirección real tiene que pasar intacta. Mirar el catálogo no prueba nada.
do $$
declare
  v_basura text[] := array['LIMA.','PENDIENTE','no tiene','Av. República de Panamá 3635'];
  v_caso text; v_coladas text[] := '{}';
begin
  foreach v_caso in array v_basura loop
    begin
      perform crm.normalizar_domicilio_legal(v_caso);
      v_coladas := v_coladas || v_caso;
    exception when sqlstate '22023' then null;
    end;
  end loop;
  if cardinality(v_coladas) > 0 then
    raise exception 'EL LISTÓN NO FRENA: %', array_to_string(v_coladas, ' | ');
  end if;
  if crm.normalizar_domicilio_legal('AV. MAESTRO PERUANO 225 URB. CARABAYLLO, COMAS, LIMA')
     <> 'AV. MAESTRO PERUANO 225 URB. CARABAYLLO, COMAS, LIMA' then
    raise exception 'UNA DIRECCIÓN REAL NO PASA EL LISTÓN';
  end if;
  raise notice 'LISTÓN OK: los 4 rellenos se rechazan y la dirección real pasa intacta.';
end $$;

select
  (select count(*) from supabase_migrations.schema_migrations where version='20260819211815') as registrada_esperado_1,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='crm'
      and p.proname in ('convertir_lead_con_domicilio','actualizar_cliente_gerencia_con_domicilio','completar_domicilio_cliente')
      and strpos(pg_get_functiondef(p.oid), 'crm.normalizar_domicilio_legal') > 0) as puertas_alineadas_esperado_3,
  (select count(*) from public.perfiles where rol='cliente' and activo and domicilio is null) as clientes_sin_domicilio;
SQL
npx --yes supabase@latest db query --linked --file "$S/ver.sql"
rm -rf "$S"
echo
echo "✅ esperado: LISTÓN OK · registrada 1 · puertas alineadas 3"
echo "   El último número es el marcador: esta mañana eran 332."
