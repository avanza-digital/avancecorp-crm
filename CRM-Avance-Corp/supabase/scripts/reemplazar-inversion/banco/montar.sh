#!/usr/bin/env bash
# Monta DESDE CERO el banco reemplazo-inv (copia adaptada de foto-sla/fase2/banco/montar.sh): Postgres 17.6
# (imagen 17.6.1.105, la de producción) con el ESQUEMA de producción, sin datos. Más chico que el de foto-sla
# (2 GiB): aquí se prueba corrección, no rendimiento. No toca nada que no empiece por reemplazo-inv.
#
#   BANCO_DIR=~/dev/banco-reemplazar-inversion bash montar.sh
#
# BANCO_DIR (fuera del repo) guarda conexion.env y el volcado. Volcado nuevo (solo lectura, desde CRM-Avance-Corp/
# del taller enlazado):
#   supabase db dump --linked --schema public,crm,private,audit --keep-comments -f "$BANCO_DIR/esquema-prod-<fecha>.sql"
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BANCO_DIR="${BANCO_DIR:-$HOME/dev/banco-reemplazar-inversion}"
set -a; source "$BANCO_DIR/conexion.env"; set +a
C="$BANCO_CONTENEDOR"; PUERTO="$BANCO_PUERTO"; VOL="$BANCO_VOLUMEN"; RED="$BANCO_RED"
ESQUEMA="${BANCO_ESQUEMA:-$(ls -1 "$BANCO_DIR"/esquema-prod-*.sql | tail -1)}"
IMAGEN="public.ecr.aws/supabase/postgres:17.6.1.105"

for n in "$C" "$VOL" "$RED"; do
  case "$n" in reemplazo-inv*) ;; *) echo "Todo debe empezar por reemplazo-inv (recibido: $n)" >&2; exit 2;; esac
done
[ -f "$ESQUEMA" ] || { echo "Falta el volcado $ESQUEMA" >&2; exit 2; }
docker ps -a --format '{{.Names}}' | grep -qx "$C" && { echo "Ya existe el contenedor $C: no se toca." >&2; exit 2; }
docker volume ls --format '{{.Name}}' | grep -qx "$VOL" && { echo "Ya existe el volumen $VOL: no se toca." >&2; exit 2; }
lsof -nP -iTCP:"$PUERTO" -sTCP:LISTEN >/dev/null 2>&1 && { echo "El puerto $PUERTO está ocupado." >&2; exit 2; }

esperar() {  # la imagen reinicia Postgres al terminar su inicialización: se exigen dos respuestas seguidas
  local listo=0
  for _ in $(seq 1 120); do
    if docker exec -e PGPASSWORD="$PGPASSWORD" "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -qAt -c "select 1" >/dev/null 2>&1; then
      listo=$((listo + 1)); [ "$listo" -ge 2 ] && return 0
    else
      listo=0
    fi
    sleep 2
  done
  echo "Postgres de $C no respondió a tiempo" >&2; return 1
}
adm() { docker exec -i -e PGPASSWORD="$PGPASSWORD" "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
aplicar() { docker cp "$1" "$C:/tmp/$(basename "$1")" >/dev/null; adm -f "/tmp/$(basename "$1")"; echo "  aplicado $(basename "$1")"; }

docker network inspect "$RED" >/dev/null 2>&1 || docker network create --label proyecto=reemplazo-inv "$RED" >/dev/null
docker volume create --label proyecto=reemplazo-inv "$VOL" >/dev/null
docker run -d --name "$C" --label proyecto=reemplazo-inv --network "$RED" \
  --memory=2g --memory-swap=3g --cpus=2 --shm-size=1g \
  -e POSTGRES_PASSWORD="$PGPASSWORD" -p "127.0.0.1:${PUERTO}:5432" \
  -v "$VOL:/var/lib/postgresql/data" "$IMAGEN" >/dev/null
echo "contenedor $C en 127.0.0.1:$PUERTO; esperando a Postgres…"
esperar

aplicar "$DIR/montar/01-ajustes-servidor.sql"
docker restart -t 60 "$C" >/dev/null; esperar; echo "  reiniciado con los ajustes"
aplicar "$DIR/montar/02-antes-de-cargar.sql"

docker cp "$ESQUEMA" "$C:/tmp/esquema.sql" >/dev/null
LOG="$BANCO_DIR/carga-$C.log"
docker exec -e PGPASSWORD="$PGPASSWORD" "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -q -f /tmp/esquema.sql > "$LOG" 2>&1 || true
errores=$(grep -c 'ERROR' "$LOG" || true)
echo "  volcado cargado: $errores error(es) (se espera 1: la llave a storage.objects, que crea el paso 03)"
grep 'ERROR' "$LOG" | head -5
[ "$errores" -le 1 ] || { echo "Más errores de los esperados: revisa $LOG" >&2; exit 1; }

aplicar "$DIR/montar/03-despues-de-cargar.sql"
aplicar "$DIR/montar/04-paridad-fina.sql"
echo "listo: $C en 127.0.0.1:$PUERTO"
