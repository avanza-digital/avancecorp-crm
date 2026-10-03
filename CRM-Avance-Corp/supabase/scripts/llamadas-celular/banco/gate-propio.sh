#!/usr/bin/env bash
# Copia de supabase/scripts/banco/gate-rls-una-pasada.sh apuntada al worktree y al stack PROPIOS
# (project_id avancecorp-llamadas-20261002, puertos 563xx). Aborta si la URL no es la del stack propio.
set -uo pipefail
WT=/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/llamadas-f2-20261002/CRM-Avance-Corp
STACK=/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/llamadas-banco-20261002-NO-VERSIONAR/stack
OUT=/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/llamadas-banco-20261002-NO-VERSIONAR
ETIQUETA="${1:-corrida}"
cd "$WT"
AQUI="$WT/supabase/scripts/banco"
eval "$(cd "$STACK" && npx supabase@2.114.0 status --workdir . -o env 2>/dev/null)"
case "${API_URL:-}" in
  http://127.0.0.1:563*|http://localhost:563*) ;;
  *) echo "ABORTADO: la URL no es la del stack propio (${API_URL:-vacia})"; exit 2 ;;
esac
export SUPABASE_URL="$API_URL"
export SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
export SUPABASE_ANON_KEY="$ANON_KEY"
export SUPABASE_PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}"
export CRM_BANCO_PSQL_URL="$DB_URL"
CRM_DEMO_PASSWORD="banco-local-$(openssl rand -hex 12)"
export CRM_DEMO_PASSWORD
echo "=== $ETIQUETA — stack propio: $SUPABASE_URL ==="
# Limpieza con los candados de inmutabilidad dormidos (solo en este banco desechable): el domicilio
# legal y las tablas de llamadas no se dejan borrar por diseño.
docker cp "$AQUI/limpiar-entre-corridas.sql" supabase_db_avancecorp-llamadas-20261002:/tmp/limpiar.sql >/dev/null
docker exec -e PGPASSWORD=postgres -e PGOPTIONS='-c session_replication_role=replica' supabase_db_avancecorp-llamadas-20261002 \
  psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -Atq -f /tmp/limpiar.sql >/dev/null 2>"$OUT/_limpiar-$ETIQUETA.log" \
  || { echo "limpieza FALLO"; tail -3 "$OUT/_limpiar-$ETIQUETA.log"; exit 1; }
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -c "grant select on crm.periodos_cerrados to service_role;" >/dev/null
if ! npm run seed:demo >"$OUT/_seed-$ETIQUETA.log" 2>&1; then
  psql "$DB_URL" -Atq -c "revoke select on crm.periodos_cerrados from service_role;" >/dev/null
  echo "la semilla FALLO (log en $OUT/_seed-$ETIQUETA.log)"; tail -8 "$OUT/_seed-$ETIQUETA.log"; exit 1
fi
tail -2 "$OUT/_seed-$ETIQUETA.log"
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -c "revoke select on crm.periodos_cerrados from service_role;" >/dev/null
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -f "$AQUI/baja-historica-vendinactive.sql" >/dev/null
npm run test:rls > "$OUT/_rls-$ETIQUETA.log" 2>&1
tail -4 "$OUT/_rls-$ETIQUETA.log"
