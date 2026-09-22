#!/usr/bin/env bash
# Corre el gate de RLS ENTERO contra el BANCO LOCAL de Docker: limpia, siembra y
# prueba en la MISMA pasada, para que siembra y prueba compartan la contrasena
# de usar y tirar (si se corren por separado, cada corrida genera una distinta y
# los 13 logins fallan).
#
# Las credenciales del stack las lee el propio guion de `supabase status -o env`;
# no aparecen en ninguna linea de comandos, no se imprimen y no se escriben a
# disco. Y este guion NO puede apuntar a produccion: aborta si la URL no es
# 127.0.0.1 o localhost.
#
# La contrasena de los usuarios de prueba es de USAR Y TIRAR: la genera este
# guion en cada corrida y solo existe dentro del banco local, cuyos usuarios los
# siembra el propio arnes. No es ninguna credencial real de nadie.
#
# Los tres pasos fuera de banda estan documentados en supabase/scripts/LEEME-seed.md:
#   · punto 3 de la receta: la limpieza entre corridas (el seed no es
#     re-ejecutable a medias);
#   · punto 3 de la adenda: el grant temporal de lectura sobre
#     crm.periodos_cerrados, que el trigger INVOKER del contrato fixture
#     necesita y que se retira al terminar;
#   · «Baja historica de vendInactive»: el estado HEREDADO que el esquema
#     —con razon— no deja construir por escritura normal.
#
# Uso:  bash gate-rls-completo.sh <etiqueta>
set -uo pipefail
cd /Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp

ETIQUETA="${1:-corrida}"
AQUI="$(cd "$(dirname "$0")" && pwd)"

eval "$(supabase status -o env)"

case "${API_URL:-}" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "ABORTADO: la URL no es local (${API_URL:-vacia})"; exit 2 ;;
esac

export SUPABASE_URL="$API_URL"
# shellcheck disable=SC2154
export SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
export SUPABASE_ANON_KEY="$ANON_KEY"
export SUPABASE_PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}"
# La cadena psql del banco la da el propio stack; el gate la usa para las
# revocaciones FUERA DE BANDA de P04.
export CRM_BANCO_PSQL_URL="$DB_URL"
CRM_DEMO_PASSWORD="banco-local-$(openssl rand -hex 12)"
export CRM_DEMO_PASSWORD

echo "=== $ETIQUETA — banco local: $SUPABASE_URL ==="

echo "--- limpieza entre corridas (LEEME-seed, punto 3) ---"
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -f "$AQUI/limpiar-entre-corridas.sql" >/dev/null

echo "--- grant temporal de lectura (LEEME-seed, adenda punto 3) ---"
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq \
  -c "grant select on crm.periodos_cerrados to service_role;" >/dev/null

echo "--- semilla ---"
if ! npm run seed:demo >"$AQUI/_seed-$ETIQUETA.log" 2>&1; then
  psql "$DB_URL" -Atq -c "revoke select on crm.periodos_cerrados from service_role;" >/dev/null
  echo "la semilla FALLO (log en _seed-$ETIQUETA.log); grant temporal retirado"
  tail -5 "$AQUI/_seed-$ETIQUETA.log"
  exit 1
fi
tail -2 "$AQUI/_seed-$ETIQUETA.log"

psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq \
  -c "revoke select on crm.periodos_cerrados from service_role;" >/dev/null
echo "--- grant temporal retirado ---"

echo "--- baja historica de vendInactive (LEEME-seed) ---"
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -f "$AQUI/baja-historica-vendinactive.sql" >/dev/null

echo "--- gate de RLS ---"
npm run test:rls 2>&1 | tee "$AQUI/_rls-$ETIQUETA.log" | tail -4
echo "(log completo en _rls-$ETIQUETA.log)"
