#!/usr/bin/env bash

set -euo pipefail

readonly QA_DB_HOST='127.0.0.1'
readonly QA_DB_PORT='55322'
readonly QA_DB_USER='postgres'
readonly QA_ADMIN_DB='postgres'
readonly QA_TEST_DB='crm_contrato_pdf_test'
readonly QA_CONTAINER='supabase_db_crm-avance-corp-local'
readonly QA_CONTAINER_IMAGE_PREFIX='public.ecr.aws/supabase/postgres:'

qa_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly qa_script_dir
qa_supabase_dir="$(cd "$qa_script_dir/.." && pwd -P)"
readonly qa_supabase_dir

readonly QA_CONFIG="$qa_supabase_dir/config.toml"
readonly QA_TEST_V2="$qa_script_dir/test-contrato-pdf-v2.sql"
readonly QA_MIGRATION_V2="$qa_supabase_dir/migrations/20260818014534_crm_contrato_pdf_v2_reserva.sql"
readonly QA_MIGRATION_REVISIONES="$qa_supabase_dir/migrations/20260818200741_crm_contratos_correccion_pdf_eliminacion.sql"
readonly QA_MIGRATION_V3="$qa_supabase_dir/migrations/20260818200743_crm_contrato_pdf_plantilla_v3.sql"
readonly QA_MIGRATION_V4="$qa_supabase_dir/migrations/20260818204908_crm_contrato_pdf_plantilla_v4_firma.sql"
readonly QA_MIGRATION_V5="$qa_supabase_dir/migrations/20260818233729_crm_contrato_pdf_plantilla_v5_firma_kirk.sql"
readonly QA_MIGRATION_REGIMEN="$qa_supabase_dir/migrations/20260820190500_crm_documento_regimen_por_fecha_de_firma.sql"

qa_created=0
qa_created_oid=''
qa_database_marker=''

usage() {
  cat <<'USAGE'
Uso:
  run-test-contrato-pdf-v2-local.sh --preflight
  run-test-contrato-pdf-v2-local.sh --run

--preflight  Comprueba archivos, contenedor, puerto e inexistencia de la DB.
             No crea, modifica ni elimina bases de datos.
--run        Crea crm_contrato_pdf_test, ejecuta el oráculo SQL v2 y elimina
             exclusivamente esa base si conserva su OID y marcador originales.

Este arnés solo usa 127.0.0.1:55322 y el contenedor local
supabase_db_crm-avance-corp-local. No ejecuta reset, db push ni operaciones linked.
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
  psql \
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
    fail "No existe config.toml regular en la ruta esperada"

  grep -Fqx 'project_id = "crm-avance-corp-local"' "$QA_CONFIG" || \
    fail "config.toml no pertenece al proyecto local esperado"

  awk '
    /^\[db\]$/ { in_db = 1; next }
    /^\[/ { in_db = 0 }
    in_db && $1 == "port" && $2 == "=" && $3 == "55322" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$QA_CONFIG" || fail "config.toml no fija [db].port en 55322"
}

verify_sql_sources() {
  local qa_file
  local qa_host_lines
  local qa_sources

  qa_sources=(
    "$QA_TEST_V2"
    "$QA_MIGRATION_V2"
    "$QA_MIGRATION_REVISIONES"
    "$QA_MIGRATION_V3"
    "$QA_MIGRATION_V4"
    "$QA_MIGRATION_V5"
    "$QA_MIGRATION_REGIMEN"
  )

  for qa_file in "${qa_sources[@]}"; do
    [[ -f "$qa_file" && ! -L "$qa_file" ]] || \
      fail "Fuente SQL ausente, no regular o symlink: $qa_file"

    if LC_ALL=C grep -Eiq '(^|[^[:alnum:]_-])([[:alnum:]-]+\.)*supabase\.co([^[:alnum:]_-]|$)' "$qa_file"; then
      fail "Una fuente SQL menciona un destino Supabase remoto: $qa_file"
    fi
    if LC_ALL=C grep -Eq '^[[:space:]]*\\(connect|c)([[:space:]]|$)|^[[:space:]]*\\!|^[[:space:]]*\\copy([[:space:]]|$)' "$qa_file"; then
      fail "Una fuente SQL contiene una metainstrucción de conexión o shell: $qa_file"
    fi
    if LC_ALL=C grep -Eiq 'postgres(ql)?://|copy[[:space:]].*program' "$qa_file"; then
      fail "Una fuente SQL contiene una URI Postgres o COPY PROGRAM: $qa_file"
    fi
  done

  grep -Fqx '\ir ../migrations/20260818014534_crm_contrato_pdf_v2_reserva.sql' "$QA_TEST_V2" || \
    fail "El oráculo v2 ya no incluye exactamente la migración v2"
  grep -Fqx '\ir ../migrations/20260818200741_crm_contratos_correccion_pdf_eliminacion.sql' "$QA_TEST_V2" || \
    fail "El oráculo v2 ya no incluye la migración de revisiones y eliminación"
  grep -Fqx '\ir ../migrations/20260818200743_crm_contrato_pdf_plantilla_v3.sql' "$QA_TEST_V2" || \
    fail "El oráculo v2 ya no incluye exactamente la migración de plantilla v3"
  grep -Fqx '\ir ../migrations/20260818204908_crm_contrato_pdf_plantilla_v4_firma.sql' "$QA_TEST_V2" || \
    fail "El oráculo v2 ya no incluye exactamente la migración de plantilla v4"
  grep -Fqx '\ir ../migrations/20260818233729_crm_contrato_pdf_plantilla_v5_firma_kirk.sql' "$QA_TEST_V2" || \
    fail "El oráculo v2 ya no incluye exactamente la migración de plantilla v5"
  grep -Fqx '\ir ../migrations/20260820190500_crm_documento_regimen_por_fecha_de_firma.sql' "$QA_TEST_V2" || \
    fail "El oráculo v2 ya no incluye exactamente la migración del régimen documental"
  grep -Fq "current_database() <> '$QA_TEST_DB'" "$QA_TEST_V2" || \
    fail "El oráculo SQL perdió su guardia de nombre de base"
  grep -Fqx '\echo CONTRATO_PDF_V2_SQL_OK' "$QA_TEST_V2" || \
    fail "El oráculo v2 perdió su marcador final"

  qa_host_lines="$(LC_ALL=C grep -hE 'host[[:space:]]*=' "${qa_sources[@]}" || true)"
  if [[ -n "$qa_host_lines" ]]; then
    if [[ "$(printf '%s\n' "$qa_host_lines" | wc -l | tr -d '[:space:]')" != '2' ]]; then
      fail "La cantidad de conexiones host= del oráculo dejó de ser la esperada"
    fi
    if printf '%s\n' "$qa_host_lines" | \
      grep -Fv 'host=host.docker.internal port=55322 dbname=crm_contrato_pdf_test user=postgres password=postgres application_name=pdf_v2_claim_' \
      >/dev/null; then
      fail "El oráculo contiene una conexión host= distinta del retorno local permitido"
    fi
  fi
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
  [[ "$qa_container_running" == 'true' ]] || fail "El contenedor local no está activo"

  qa_container_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$QA_CONTAINER")"
  [[ "$qa_container_health" == 'healthy' ]] || \
    fail "El contenedor local no está healthy: $qa_container_health"

  qa_container_image="$(docker inspect --format '{{.Config.Image}}' "$QA_CONTAINER")"
  case "$qa_container_image" in
    "$QA_CONTAINER_IMAGE_PREFIX"*) ;;
    *) fail "La imagen del contenedor no es Supabase Postgres" ;;
  esac

  qa_container_ports="$(docker port "$QA_CONTAINER" '5432/tcp')"
  printf '%s\n' "$qa_container_ports" | grep -Eq '(^|:)55322$' || \
    fail "El contenedor esperado no publica PostgreSQL en 55322"

  qa_host_probe="$(psql_admin -A -t -q -c \
    "select current_database() || '|' || current_user || '|' || inet_server_port()::text;")"
  [[ "$qa_host_probe" == 'postgres|postgres|5432' ]] || \
    fail "127.0.0.1:55322 no respondió como el Postgres local esperado"

  qa_host_system_id="$(psql_admin -A -t -q -c \
    'select system_identifier from pg_catalog.pg_control_system();')"
  qa_container_system_id="$(docker exec "$QA_CONTAINER" psql -X -w -U postgres -d postgres -A -t -q -c \
    'select system_identifier from pg_catalog.pg_control_system();')"
  [[ "$qa_host_system_id" =~ ^[0-9]+$ ]] || \
    fail "No se pudo obtener la identidad del servidor por loopback"
  [[ "$qa_host_system_id" == "$qa_container_system_id" ]] || \
    fail "El puerto 55322 no corresponde al contenedor local esperado"
}

assert_test_database_absent() {
  local qa_identity
  qa_identity="$(database_identity)"
  [[ -z "$qa_identity" ]] || \
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
      printf 'ERROR: cambió la identidad del destino; se conserva %s para revisión manual\n' \
        "$QA_TEST_DB" >&2
      [[ "$qa_status" -ne 0 ]] || qa_status=1
      exit "$qa_status"
    fi

    qa_identity="$(database_identity)"
    if [[ -z "$qa_identity" ]]; then
      printf 'AVISO: %s ya no existe; el arnés no eliminó otra base\n' "$QA_TEST_DB" >&2
    else
      IFS='|' read -r qa_current_oid qa_current_marker <<<"$qa_identity"
      if [[ -z "$qa_created_oid" || "$qa_current_oid" != "$qa_created_oid" || "$qa_current_marker" != "$qa_database_marker" ]]; then
        printf 'ERROR: la identidad de %s cambió; se conserva para revisión manual\n' \
          "$QA_TEST_DB" >&2
        [[ "$qa_status" -ne 0 ]] || qa_status=1
        exit "$qa_status"
      fi

      if ! dropdb \
        --force \
        --host="$QA_DB_HOST" \
        --port="$QA_DB_PORT" \
        --username="$QA_DB_USER" \
        "$QA_TEST_DB"; then
        printf 'ERROR: no se pudo eliminar la base efímera verificada %s\n' \
          "$QA_TEST_DB" >&2
        [[ "$qa_status" -ne 0 ]] || qa_status=1
      elif [[ -n "$(database_identity)" ]]; then
        printf 'ERROR: la base efímera sigue existiendo después de dropdb\n' >&2
        [[ "$qa_status" -ne 0 ]] || qa_status=1
      else
        printf 'Limpieza verificada: %s (OID %s) eliminada.\n' \
          "$QA_TEST_DB" "$qa_created_oid"
      fi
    fi
  fi

  exit "$qa_status"
}

run_oracle() {
  local qa_output

  createdb \
    --host="$QA_DB_HOST" \
    --port="$QA_DB_PORT" \
    --username="$QA_DB_USER" \
    --owner="$QA_DB_USER" \
    --template=template0 \
    --encoding=UTF8 \
    "$QA_TEST_DB"
  qa_created=1

  qa_database_marker="contrato-pdf-v2-qa-$$-$(date -u '+%Y%m%dT%H%M%SZ')"
  psql_admin -q -c \
    "comment on database $QA_TEST_DB is '$qa_database_marker';"

  qa_created_oid="$(database_identity | cut -d '|' -f 1)"
  [[ "$qa_created_oid" =~ ^[0-9]+$ ]] || \
    fail "No se pudo registrar el OID de la base recién creada"

  qa_output="$(psql \
    -X \
    -w \
    --host="$QA_DB_HOST" \
    --port="$QA_DB_PORT" \
    --username="$QA_DB_USER" \
    --dbname="$QA_TEST_DB" \
    --file="$QA_TEST_V2")"
  printf '%s\n' "$qa_output"

  printf '%s\n' "$qa_output" | grep -Fqx 'CONTRATO_PDF_V2_SQL_OK' || \
    fail "El oráculo v2 no emitió su marcador final"

  printf 'CONTRATO_PDF_V2_RUNNER_OK\n'
}

main() {
  local qa_mode=''

  if [[ $# -ne 1 ]]; then
    usage >&2
    exit 64
  fi
  case "$1" in
    --preflight) qa_mode='preflight' ;;
    --run) qa_mode='run' ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac

  require_command awk
  require_command cut
  require_command createdb
  require_command date
  require_command docker
  require_command dropdb
  require_command grep
  require_command psql
  require_command tr
  require_command wc

  unset PGDATABASE PGHOST PGPORT PGSERVICE PGSERVICEFILE PGUSER
  export PGPASSWORD='postgres'
  export PGCONNECT_TIMEOUT='5'
  export PGSSLMODE='disable'

  verify_config
  verify_sql_sources
  verify_local_target
  assert_test_database_absent

  if [[ "$qa_mode" == 'preflight' ]]; then
    printf 'CONTRATO_PDF_V2_PREFLIGHT_OK destino=%s:%s base=%s\n' \
      "$QA_DB_HOST" "$QA_DB_PORT" "$QA_TEST_DB"
    exit 0
  fi

  trap cleanup_database EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  run_oracle
}

main "$@"
