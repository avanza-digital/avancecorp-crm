#!/usr/bin/env bash

set -euo pipefail

readonly QA_DB_HOST='127.0.0.1'
readonly QA_DB_PORT='55322'
readonly QA_DB_USER='postgres'
readonly QA_DB_PASSWORD='postgres'
readonly QA_ADMIN_DB='postgres'
readonly QA_TEST_DB='crm_ficha_security_test'
readonly QA_CONTAINER='supabase_db_crm-avance-corp-local'
readonly QA_CONTAINER_IMAGE_PREFIX='public.ecr.aws/supabase/postgres:'

qa_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly qa_script_dir
qa_supabase_dir="$(cd "$qa_script_dir/.." && pwd -P)"
readonly qa_supabase_dir

readonly QA_CONFIG="$qa_supabase_dir/config.toml"
readonly QA_TEST_SQL="$qa_script_dir/test-ficha-cliente-security-hardening.sql"
readonly QA_MIGRATION="$qa_supabase_dir/migrations/20260826164831_crm_ficha_cliente_security_hardening.sql"

qa_created=0
qa_created_oid=''
qa_database_marker=''

usage() {
  cat <<'USAGE'
Uso:
  run-test-ficha-cliente-security-local.sh --preflight
  run-test-ficha-cliente-security-local.sh --run

--preflight  Verifica fuentes, contenedor, loopback e inexistencia de la DB.
--run        Crea crm_ficha_security_test desde template0, ejecuta el oráculo
             F41 y elimina solo esa base si conserva su OID y marcador.

No ejecuta reset, db push, enlaces remotos ni reutiliza datos existentes.
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
  PGPASSWORD="$QA_DB_PASSWORD" psql \
    -X \
    -w \
    --host="$QA_DB_HOST" \
    --port="$QA_DB_PORT" \
    --username="$QA_DB_USER" \
    --dbname="$QA_ADMIN_DB" \
    "$@"
}

database_identity() {
  psql_admin -A -t -q -F '|' -c \
    "select oid::text, coalesce(shobj_description(oid, 'pg_database'), '')
       from pg_catalog.pg_database
      where datname = '$QA_TEST_DB';"
}

verify_config() {
  [[ -f "$QA_CONFIG" && ! -L "$QA_CONFIG" ]] || \
    fail 'No existe config.toml regular en la ruta esperada'
  grep -Fqx 'project_id = "crm-avance-corp-local"' "$QA_CONFIG" || \
    fail 'config.toml no pertenece al proyecto local esperado'
  awk '
    /^\[db\]$/ { in_db = 1; next }
    /^\[/ { in_db = 0 }
    in_db && $1 == "port" && $2 == "=" && $3 == "55322" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$QA_CONFIG" || fail 'config.toml no fija [db].port en 55322'
}

verify_sql_sources() {
  local qa_file
  local qa_host_lines

  for qa_file in "$QA_TEST_SQL" "$QA_MIGRATION"; do
    [[ -f "$qa_file" && ! -L "$qa_file" ]] || \
      fail "Fuente SQL ausente, no regular o symlink: $qa_file"
    if LC_ALL=C grep -Eiq '(^|[^[:alnum:]_-])([[:alnum:]-]+\.)*supabase\.co([^[:alnum:]_-]|$)' "$qa_file"; then
      fail "Una fuente SQL menciona un destino Supabase remoto: $qa_file"
    fi
    if LC_ALL=C grep -Eq '^[[:space:]]*\\(connect|c)([[:space:]]|$)|^[[:space:]]*\\!|^[[:space:]]*\\copy([[:space:]]|$)' "$qa_file"; then
      fail "Una fuente SQL contiene una conexión o shell: $qa_file"
    fi
    if LC_ALL=C grep -Eiq 'postgres(ql)?://|copy[[:space:]].*program' "$qa_file"; then
      fail "Una fuente SQL contiene URI Postgres o COPY PROGRAM: $qa_file"
    fi
  done

  grep -Fqx '\ir ../migrations/20260826164831_crm_ficha_cliente_security_hardening.sql' "$QA_TEST_SQL" || \
    fail 'El oráculo no incluye exactamente la migración F41'
  grep -Fq "current_database() <> '$QA_TEST_DB'" "$QA_TEST_SQL" || \
    fail 'El oráculo perdió la guardia de nombre de base'
  grep -Fqx '\echo FICHA_CLIENTE_SECURITY_HARDENING_SQL_OK' "$QA_TEST_SQL" || \
    fail 'El oráculo perdió su marcador final'

  qa_host_lines="$(LC_ALL=C grep -hE 'host[[:space:]]*=' "$QA_TEST_SQL" "$QA_MIGRATION" || true)"
  [[ "$(printf '%s\n' "$qa_host_lines" | sed '/^$/d' | wc -l | tr -d '[:space:]')" == '1' ]] || \
    fail 'La cantidad de conexiones host= del oráculo no es exactamente una'
  [[ "$qa_host_lines" == "\\set test_conn 'host=host.docker.internal port=55322 dbname=crm_ficha_security_test user=postgres password=postgres application_name=f41_security_race'" ]] || \
    fail 'El retorno dblink no coincide con el loopback local permitido'
}

verify_local_target() {
  local qa_container_image
  local qa_container_running
  local qa_container_health
  local qa_container_ports
  local qa_host_system_id
  local qa_container_system_id
  local qa_host_probe

  qa_container_running="$(docker inspect --format '{{.State.Running}}' "$QA_CONTAINER" 2>/dev/null)" || \
    fail "No existe el contenedor local esperado: $QA_CONTAINER"
  [[ "$qa_container_running" == 'true' ]] || fail 'El contenedor local no está activo'

  qa_container_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$QA_CONTAINER")"
  [[ "$qa_container_health" == 'healthy' ]] || \
    fail "El contenedor local no está healthy: $qa_container_health"

  qa_container_image="$(docker inspect --format '{{.Config.Image}}' "$QA_CONTAINER")"
  case "$qa_container_image" in
    "$QA_CONTAINER_IMAGE_PREFIX"*) ;;
    *) fail 'La imagen del contenedor no es Supabase Postgres' ;;
  esac

  qa_container_ports="$(docker port "$QA_CONTAINER" '5432/tcp')"
  printf '%s\n' "$qa_container_ports" | grep -Eq '(^|:)55322$' || \
    fail 'El contenedor esperado no publica PostgreSQL en 55322'

  qa_host_probe="$(psql_admin -A -t -q -c \
    "select current_database() || '|' || current_user || '|' || inet_server_port()::text;")"
  [[ "$qa_host_probe" == 'postgres|postgres|5432' ]] || \
    fail '127.0.0.1:55322 no respondió como el Postgres local esperado'

  qa_host_system_id="$(psql_admin -A -t -q -c \
    'select system_identifier from pg_catalog.pg_control_system();')"
  qa_container_system_id="$(docker exec "$QA_CONTAINER" psql -X -w -U postgres -d postgres -A -t -q -c \
    'select system_identifier from pg_catalog.pg_control_system();')"
  [[ "$qa_host_system_id" =~ ^[0-9]+$ ]] || \
    fail 'No se pudo leer la identidad del servidor por loopback'
  [[ "$qa_host_system_id" == "$qa_container_system_id" ]] || \
    fail 'El puerto 55322 no corresponde al contenedor local esperado'
}

assert_test_database_absent() {
  [[ -z "$(database_identity)" ]] || \
    fail "La base $QA_TEST_DB ya existe; se rehúsa reutilizarla o eliminarla"
}

cleanup_database() {
  local qa_status=$?
  local qa_identity
  local qa_current_oid
  local qa_current_marker

  trap - EXIT INT TERM
  set +e
  if [[ "$qa_created" == '1' ]]; then
    if ! verify_local_target; then
      printf 'ERROR: cambió el destino; se conserva %s para revisión manual\n' "$QA_TEST_DB" >&2
      [[ "$qa_status" -ne 0 ]] || qa_status=1
      exit "$qa_status"
    fi
    qa_identity="$(database_identity)"
    if [[ -z "$qa_identity" ]]; then
      printf 'AVISO: %s ya no existe; no se eliminó otra base\n' "$QA_TEST_DB" >&2
    else
      IFS='|' read -r qa_current_oid qa_current_marker <<<"$qa_identity"
      if [[ -z "$qa_created_oid" || "$qa_current_oid" != "$qa_created_oid" || "$qa_current_marker" != "$qa_database_marker" ]]; then
        printf 'ERROR: cambió la identidad de %s; se conserva para revisión manual\n' "$QA_TEST_DB" >&2
        [[ "$qa_status" -ne 0 ]] || qa_status=1
        exit "$qa_status"
      fi
      if ! PGPASSWORD="$QA_DB_PASSWORD" dropdb \
        --force \
        --host="$QA_DB_HOST" \
        --port="$QA_DB_PORT" \
        --username="$QA_DB_USER" \
        "$QA_TEST_DB"; then
        printf 'ERROR: no se pudo eliminar la base efímera verificada %s\n' "$QA_TEST_DB" >&2
        [[ "$qa_status" -ne 0 ]] || qa_status=1
      elif [[ -n "$(database_identity)" ]]; then
        printf 'ERROR: la base efímera sigue existiendo después de dropdb\n' >&2
        [[ "$qa_status" -ne 0 ]] || qa_status=1
      else
        printf 'Limpieza verificada: %s (OID %s) eliminada.\n' "$QA_TEST_DB" "$qa_created_oid"
      fi
    fi
  fi
  exit "$qa_status"
}

run_oracle() {
  local qa_output

  PGPASSWORD="$QA_DB_PASSWORD" createdb \
    --host="$QA_DB_HOST" \
    --port="$QA_DB_PORT" \
    --username="$QA_DB_USER" \
    --owner="$QA_DB_USER" \
    --template=template0 \
    --encoding=UTF8 \
    "$QA_TEST_DB"
  qa_created=1
  qa_database_marker="f41-security-qa-$$-$(date -u '+%Y%m%dT%H%M%SZ')"
  psql_admin -q -c "comment on database $QA_TEST_DB is '$qa_database_marker';"
  qa_created_oid="$(database_identity | cut -d '|' -f 1)"
  [[ "$qa_created_oid" =~ ^[0-9]+$ ]] || \
    fail 'No se pudo registrar el OID de la base recién creada'

  qa_output="$(PGPASSWORD="$QA_DB_PASSWORD" psql \
    -X \
    -w \
    --host="$QA_DB_HOST" \
    --port="$QA_DB_PORT" \
    --username="$QA_DB_USER" \
    --dbname="$QA_TEST_DB" \
    --file="$QA_TEST_SQL")"
  printf '%s\n' "$qa_output"
  printf '%s\n' "$qa_output" | grep -Fqx 'FICHA_CLIENTE_SECURITY_HARDENING_SQL_OK' || \
    fail 'El oráculo F41 no emitió su marcador final'
  printf 'FICHA_CLIENTE_SECURITY_RUNNER_OK\n'
}

main() {
  local qa_mode=''
  [[ $# -eq 1 ]] || { usage >&2; exit 64; }
  qa_mode="$1"
  [[ "$qa_mode" == '--preflight' || "$qa_mode" == '--run' ]] || {
    usage >&2
    exit 64
  }

  for qa_command in psql createdb dropdb docker grep awk sed wc cut date; do
    require_command "$qa_command"
  done
  verify_config
  verify_sql_sources
  verify_local_target
  assert_test_database_absent

  if [[ "$qa_mode" == '--preflight' ]]; then
    printf 'FICHA_CLIENTE_SECURITY_PREFLIGHT_OK\n'
    return
  fi

  trap cleanup_database EXIT INT TERM
  run_oracle
}

main "$@"
