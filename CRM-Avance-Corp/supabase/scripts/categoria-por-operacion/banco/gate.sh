#!/usr/bin/env bash
# Gate RLS de UNA pasada (semilla + test-rls.mjs) contra el banco PROPIO de «categoría por operación».
# Copia de supabase/scripts/banco/gate-rls-una-pasada.sh con el stack propio: las credenciales las da `supabase status`
# del stack local; no se imprimen ni se escriben. Se niega si la API no es local.
# Ojo: la limpieza entre corridas BORRA crm.equipo y los leads; el mundo de banco/mundo.sql pierde a sus personas.
# Uso: gate.sh <dir del stack (el que tiene supabase/config.toml)> <etiqueta>
# Los registros (_seed-*, _rls-*, _rojos-*) quedan en el dir del stack, fuera del repo.
set -uo pipefail
STACK="${1:?dir del stack}"; ETIQUETA="${2:?etiqueta}"
CRM="$(cd "$(dirname "$0")/../../../.." && pwd)"          # CRM-Avance-Corp del worktree
B="$(cd "$STACK" && pwd)"   # salida de los registros
AQUI="$CRM/supabase/scripts/banco"
cd "$CRM"
eval "$(supabase status -o env --workdir "$STACK" 2>/dev/null)"
case "${API_URL:-}" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "ABORTADO: la URL no es local (${API_URL:-vacia})"; exit 2 ;;
esac
PROYECTO="$(grep -m1 '^project_id' "$STACK/supabase/config.toml" | cut -d'"' -f2)"
export SUPABASE_URL="$API_URL"
export SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
export SUPABASE_ANON_KEY="$ANON_KEY"
export SUPABASE_PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}"
export CRM_BANCO_PSQL_URL="$DB_URL"
CRM_DEMO_PASSWORD="banco-local-$(openssl rand -hex 12)"; export CRM_DEMO_PASSWORD
echo "=== $ETIQUETA — banco local: $SUPABASE_URL ($PROYECTO) ==="
# PostgREST tiene que haber cargado su caché de esquema (tras montar el banco tarda unos segundos): sin eso la semilla
# muere con «Could not query the database for the schema cache».
for _ in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "apikey: $ANON_KEY" "$API_URL/rest/v1/")" = "200" ] && break
  sleep 2
done
docker exec -i -e PGPASSWORD=postgres "supabase_db_$PROYECTO" psql -X -U supabase_admin -h 127.0.0.1 -d postgres -q -c \
  "begin; set local session_replication_role = replica; update public.perfiles set domicilio = null where rol = 'cliente' and domicilio is not null; commit;" >/dev/null \
  || { echo "reset de domicilio FALLO"; exit 1; }
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -f "$AQUI/limpiar-entre-corridas.sql" >/dev/null 2>"$B/_limpieza-$ETIQUETA.err" || { echo "limpieza FALLO"; tail -3 "$B/_limpieza-$ETIQUETA.err"; exit 1; }
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -c "grant select on crm.periodos_cerrados to service_role;" >/dev/null
if ! npm run seed:demo >"$B/_seed-$ETIQUETA.log" 2>&1; then
  psql "$DB_URL" -Atq -c "revoke select on crm.periodos_cerrados from service_role;" >/dev/null
  echo "la semilla FALLO (log en _seed-$ETIQUETA.log); grant temporal retirado"; tail -5 "$B/_seed-$ETIQUETA.log"; exit 1
fi
tail -2 "$B/_seed-$ETIQUETA.log"
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -c "revoke select on crm.periodos_cerrados from service_role;" >/dev/null
psql "$DB_URL" -v ON_ERROR_STOP=1 -Atq -f "$AQUI/baja-historica-vendinactive.sql" >/dev/null
echo "--- gate de RLS ---"
npm run test:rls >"$B/_rls-$ETIQUETA.log" 2>&1
echo "salida del gate: $?"; tail -2 "$B/_rls-$ETIQUETA.log"
# Lista normalizada de rojos (para comparar dos corridas con diff).
grep -E "^\s*✗" "$B/_rls-$ETIQUETA.log" \
  | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/g; s/C[0-9]{3}-[0-9]+/C<id>/g; s/X1-[0-9]+/X1-<id>/g; s/"creado_en":"[^"]*"/"creado_en":"<t>"/g; s/IDEM-[0-9A-F]+/IDEM-<n>/g; s/"cci":"[0-9]+"/"cci":"<n>"/g' \
  | sort > "$B/_rojos-$ETIQUETA.txt"
echo "rojos: $(wc -l < "$B/_rojos-$ETIQUETA.txt" | tr -d ' ') (lista normalizada en _rojos-$ETIQUETA.txt)"
