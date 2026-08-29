#!/usr/bin/env bash

set -euo pipefail

readonly FICHA_DB_HOST='127.0.0.1'
readonly FICHA_DB_PORT='55322'
readonly FICHA_DB_USER='postgres'
readonly FICHA_ADMIN_DB='postgres'
readonly FICHA_TEST_DB='crm_ficha360_scope_test'
readonly FICHA_DB_MARKER='avancecorp:ficha360:oracle:v1'

ficha_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly ficha_script_dir
ficha_supabase_dir="$(cd "$ficha_script_dir/.." && pwd -P)"
readonly ficha_supabase_dir
ficha_repo_dir="$(cd "$ficha_supabase_dir/.." && pwd -P)"
readonly ficha_repo_dir

readonly FICHA_CONFIG="$ficha_supabase_dir/config.toml"
readonly FICHA_ORACLE="$ficha_script_dir/test-ficha-360-scope-local.sql"
readonly FICHA_MIGRATION="$ficha_supabase_dir/migrations/20260829183627_crm_ficha_360_scope_historial.sql"

ficha_created=0
ficha_created_oid=''

usage() {
  cat <<'USAGE'
Uso:
  npm run test:ficha-360:db:preflight
  npm run test:ficha-360:db

El preflight es de solo lectura. La ejecución crea exclusivamente la base
local crm_ficha360_scope_test en 127.0.0.1:55322, corre el oráculo, db lint y
advisors, y elimina esa base tras verificar su OID y marcador. No admite un
destino configurable ni ejecuta reset, push o comandos linked.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Falta el comando requerido: $1"
}

psql_admin() {
  PGPASSWORD='postgres' psql \
    -X \
    -w \
    --host="$FICHA_DB_HOST" \
    --port="$FICHA_DB_PORT" \
    --username="$FICHA_DB_USER" \
    --dbname="$FICHA_ADMIN_DB" \
    "$@"
}

database_identity() {
  psql_admin -A -t -q -F '|' -c \
    "select oid::text, coalesce(shobj_description(oid, 'pg_database'), '')
       from pg_catalog.pg_database
      where datname = '$FICHA_TEST_DB';"
}

verify_sources() {
  local ficha_file
  for ficha_file in "$FICHA_CONFIG" "$FICHA_ORACLE" "$FICHA_MIGRATION"; do
    [[ -f "$ficha_file" && ! -L "$ficha_file" ]] || \
      fail "Fuente ausente, no regular o symlink: $ficha_file"
  done

  grep -Fqx 'project_id = "crm-avance-corp-local"' "$FICHA_CONFIG" || \
    fail 'config.toml no pertenece al proyecto local esperado'
  awk '
    /^\[db\]$/ { in_db = 1; next }
    /^\[/ { in_db = 0 }
    in_db && $1 == "port" && $2 == "=" && $3 == "55322" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$FICHA_CONFIG" || fail 'config.toml no fija [db].port en 55322'

  grep -Fqx '\ir ../migrations/20260829183627_crm_ficha_360_scope_historial.sql' "$FICHA_ORACLE" || \
    fail 'El oráculo ya no incluye exactamente la migración Ficha 360'
  grep -Fq 'FICHA_360_SCOPE_LOCAL_OK' "$FICHA_ORACLE" || \
    fail 'El oráculo perdió su marcador final'

  for ficha_file in "$FICHA_ORACLE" "$FICHA_MIGRATION"; do
    if LC_ALL=C grep -Eiq 'supabase\.co|postgres(ql)?://|copy[[:space:]].*program' "$ficha_file"; then
      fail "Una fuente SQL contiene un destino remoto o COPY PROGRAM: $ficha_file"
    fi
    if LC_ALL=C grep -Eq '^[[:space:]]*\\(connect|c)([[:space:]]|$)|^[[:space:]]*\\!|^[[:space:]]*\\copy([[:space:]]|$)' "$ficha_file"; then
      fail "Una fuente SQL contiene una metainstrucción de conexión o shell: $ficha_file"
    fi
  done
}

verify_local_target() {
  local ficha_probe
  ficha_probe="$(psql_admin -A -t -q -c \
    "select current_database() || '|' || current_user || '|' || inet_server_port()::text;")"
  [[ "$ficha_probe" == 'postgres|postgres|5432' ]] || \
    fail "El puerto $FICHA_DB_PORT no respondió como el Postgres local esperado: $ficha_probe"
}

verify_absent() {
  [[ -z "$(database_identity)" ]] || \
    fail "La base reservada $FICHA_TEST_DB ya existe; no se modificará"
}

cleanup() {
  local ficha_identity
  local ficha_oid
  local ficha_marker
  [[ "$ficha_created" == '1' ]] || return 0

  ficha_identity="$(database_identity)"
  ficha_oid="${ficha_identity%%|*}"
  ficha_marker="${ficha_identity#*|}"
  if [[ "$ficha_oid" != "$ficha_created_oid" || "$ficha_marker" != "$FICHA_DB_MARKER" ]]; then
    printf 'ERROR: la base temporal cambió de identidad; no se elimina: %s\n' "$ficha_identity" >&2
    return 1
  fi

  psql_admin -q -c \
    "select pg_catalog.pg_terminate_backend(pid)
       from pg_catalog.pg_stat_activity
      where datname = '$FICHA_TEST_DB'
        and pid <> pg_catalog.pg_backend_pid();" >/dev/null
  PGPASSWORD='postgres' dropdb \
    --host="$FICHA_DB_HOST" \
    --port="$FICHA_DB_PORT" \
    --username="$FICHA_DB_USER" \
    "$FICHA_TEST_DB"
  ficha_created=0
}

run_oracle() {
  local ficha_output
  local ficha_identity

  PGPASSWORD='postgres' createdb \
    --host="$FICHA_DB_HOST" \
    --port="$FICHA_DB_PORT" \
    --username="$FICHA_DB_USER" \
    "$FICHA_TEST_DB"
  psql_admin -q -c \
    "comment on database $FICHA_TEST_DB is '$FICHA_DB_MARKER';"
  ficha_created=1
  ficha_identity="$(database_identity)"
  ficha_created_oid="${ficha_identity%%|*}"
  [[ -n "$ficha_created_oid" && "${ficha_identity#*|}" == "$FICHA_DB_MARKER" ]] || \
    fail 'No se pudo sellar la identidad de la base temporal'

  ficha_output="$(
    PGPASSWORD='postgres' psql \
      -X \
      -w \
      --host="$FICHA_DB_HOST" \
      --port="$FICHA_DB_PORT" \
      --username="$FICHA_DB_USER" \
      --dbname="$FICHA_TEST_DB" \
      --file="$FICHA_ORACLE"
  )"
  printf '%s\n' "$ficha_output"
  grep -Fq 'FICHA_360_SCOPE_LOCAL_OK' <<<"$ficha_output" || \
    fail 'El oráculo no emitió su marcador de éxito'

  (
    cd "$ficha_repo_dir"
    npx supabase@2.114.0 db lint \
      --db-url "postgresql://postgres:postgres@$FICHA_DB_HOST:$FICHA_DB_PORT/$FICHA_TEST_DB" \
      --schema crm,private \
      --level error \
      --fail-on error
    npx supabase@2.114.0 db advisors \
      --db-url "postgresql://postgres:postgres@$FICHA_DB_HOST:$FICHA_DB_PORT/$FICHA_TEST_DB" \
      --type all \
      --level warn \
      --fail-on error
  )

  printf 'FICHA_360_DB_GATE_OK\n'
}

main() {
  require_command psql
  require_command createdb
  require_command dropdb
  require_command node
  require_command npx
  verify_sources
  verify_local_target

  case "${1:-}" in
    --preflight)
      verify_absent
      printf 'FICHA_360_DB_PREFLIGHT_OK\n'
      ;;
    --run)
      verify_absent
      trap cleanup EXIT HUP INT TERM
      run_oracle
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
}

main "$@"
