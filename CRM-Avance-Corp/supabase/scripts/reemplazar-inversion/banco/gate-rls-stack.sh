#!/usr/bin/env bash
# Gate de RLS ENTERO (supabase/scripts/test-rls.mjs) contra el STACK LOCAL propio de «Reemplazar inversión»
# (project_id avancecorp-reemplazo-inv, API 127.0.0.1:56521, base 127.0.0.1:56522) con el esquema de producción cargado.
# Copia de supabase/scripts/banco/gate-rls-una-pasada.sh con dos cambios: el directorio de trabajo es el worktree (no el
# taller compartido) y el stack se lee con --workdir. Igual que el original: limpia, siembra y prueba en la MISMA pasada
# con una contraseña de usar y tirar, no imprime credenciales y aborta si la URL no es local.
#
# Uso:  bash gate-rls-stack.sh <etiqueta>       (STACK_DIR=~/dev/banco-reemplazar-inversion/stack por defecto)
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$AQUI/../../../.." && pwd)"          # CRM-Avance-Corp del worktree
BANCO="$RAIZ/supabase/scripts/banco"
STACK_DIR="${STACK_DIR:-$HOME/dev/banco-reemplazar-inversion/stack}"
ETIQUETA="${1:-corrida}"
cd "$RAIZ"

eval "$(supabase status -o env --workdir "$STACK_DIR" 2>/dev/null)"
case "${API_URL:-}" in
  http://127.0.0.1:56521|http://localhost:56521) ;;
  *) echo "ABORTADO: la URL no es la del stack propio (${API_URL:-vacia})"; exit 2 ;;
esac

export SUPABASE_URL="$API_URL"
# shellcheck disable=SC2154
export SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
export SUPABASE_ANON_KEY="$ANON_KEY"
export SUPABASE_PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}"
export CRM_BANCO_PSQL_URL="$DB_URL"
CRM_DEMO_PASSWORD="banco-local-$(openssl rand -hex 12)"
export CRM_DEMO_PASSWORD
LOGS="${LOGS:-$HOME/dev/banco-reemplazar-inversion}"

echo "=== $ETIQUETA — stack local: $SUPABASE_URL ==="
echo "--- limpieza entre corridas ---"
# DIVERGENCIA (17/10/2026): banco/limpiar-entre-corridas.sql es anterior al candado private.bloquear_borrado_domicilio_legal
# y en la segunda corrida muere en «El domicilio legal registrado no se puede borrar». Aquí corre con los triggers apagados
# (solo en este stack desechable); la limpieza borra lo mismo.
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -c "set session_replication_role = replica" -f "$BANCO/limpiar-entre-corridas.sql" >/dev/null \
  || { echo "limpieza FALLO"; exit 1; }
echo "--- grant temporal de lectura ---"
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -c "grant select on crm.periodos_cerrados to service_role;" >/dev/null
echo "--- semilla ---"
if ! npm run seed:demo >"$LOGS/_seed-$ETIQUETA.log" 2>&1; then
  psql "$DB_URL" -Atq -c "revoke select on crm.periodos_cerrados from service_role;" >/dev/null
  echo "la semilla FALLO (log en $LOGS/_seed-$ETIQUETA.log); grant temporal retirado"
  tail -5 "$LOGS/_seed-$ETIQUETA.log"
  exit 1
fi
tail -2 "$LOGS/_seed-$ETIQUETA.log"
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -c "revoke select on crm.periodos_cerrados from service_role;" >/dev/null
echo "--- grant temporal retirado ---"
echo "--- baja histórica de vendInactive ---"
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -f "$BANCO/baja-historica-vendinactive.sql" >/dev/null
echo "--- gate de RLS ---"
npm run test:rls 2>&1 | tee "$LOGS/_rls-$ETIQUETA.log" | tail -6
echo "(log completo en $LOGS/_rls-$ETIQUETA.log)"
