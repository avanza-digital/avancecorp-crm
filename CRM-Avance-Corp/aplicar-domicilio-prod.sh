#!/usr/bin/env bash
# Aplica a PRODUCCIÓN la migración del domicilio legal (20260819162752).
# Ensayada al completo en el banco `domicilio-legal`: postflight OK con datos,
# oráculo 10/10, gate RLS 352✓ (bloque nuevo 32/32), asesores con delta de 2.
#
# Hace CUATRO cosas y para en la primera que falle:
#   1. aplica el fichero VERBATIM (mismo byte que el repo)
#   2. lo registra en el índice (db query ejecuta pero NO registra)
#   3. RETIRA el permiso de uso: las funciones quedan creadas pero inalcanzables
#      hasta que se publique la pantalla — así no queda abierta una escritura
#      irreversible sin interfaz que la ordene
#   4. cuenta objetos para comprobar de verdad que se aplicó
set -euo pipefail
cd "$(dirname "$0")"
export SUPABASE_ACCESS_TOKEN="$(security find-generic-password -s 'Supabase CLI' -w)"
S=$(mktemp -d)

echo "── 1/4 · aplicando la migración ──────────────────────────────"
npx --yes supabase@latest db query --linked \
  --file supabase/migrations/20260819162752_crm_domicilio_legal_faltante.sql

echo "── 2/4 · registrando en el índice ────────────────────────────"
printf "insert into supabase_migrations.schema_migrations(version) values ('20260819162752') on conflict do nothing;\n" > "$S/reg.sql"
npx --yes supabase@latest db query --linked --file "$S/reg.sql"

echo "── 3/4 · retirando el permiso hasta que salga la pantalla ─────"
cat > "$S/cerrar.sql" <<'SQL'
revoke execute on function crm.datos_legales_contrato_fn(uuid) from authenticated;
revoke execute on function crm.completar_domicilio_cliente(uuid, text) from authenticated;
SQL
npx --yes supabase@latest db query --linked --file "$S/cerrar.sql"

echo "── 4/4 · comprobando por CONTEO (la respuesta no es evidencia) ─"
cat > "$S/ver.sql" <<'SQL'
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='crm'
       and p.proname in ('normalizar_domicilio_legal','datos_legales_contrato_fn','completar_domicilio_cliente')) as funciones_nuevas_esperado_3,
  (select count(*) from supabase_migrations.schema_migrations where version='20260819162752') as registrada_esperado_1,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm') as fn_crm_esperado_110,
  has_function_privilege('authenticated','crm.completar_domicilio_cliente(uuid, text)','execute') as permiso_debe_ser_false;
SQL
npx --yes supabase@latest db query --linked --file "$S/ver.sql"
rm -rf "$S"
echo
echo "✅ listo. Esperado: 3 funciones · registrada 1 · fn_crm 110 · permiso false"
