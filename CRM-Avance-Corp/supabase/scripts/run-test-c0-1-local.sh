#!/usr/bin/env bash

# Runner hermetico para el banco adversario C0.1.
#
# Crea un cluster PostgreSQL 17 propio, sin TCP, y no acepta ningun selector de
# conexion externo. La propuesta y el banco se ejecutan solo desde snapshots
# temporales. Ejecuta el caso real, los mutantes internos del banco y una matriz
# de 17 mutantes de los dos cuerpos candidatos sobre bases nuevas e independientes.

set -Eeuo pipefail
IFS=$'\n\t'

EVIDENCE_DIR=""
if [[ $# -eq 2 && "$1" == "--evidence-dir" ]]; then
  EVIDENCE_DIR="$2"
  if [[ ! "$EVIDENCE_DIR" =~ ^/private/tmp/c01-evidence-[A-Za-z0-9._-]+$ ]]; then
    printf '%s\n' \
      'C0.1 local: --evidence-dir debe ser /private/tmp/c01-evidence-<nombre-seguro>.' >&2
    exit 64
  fi
  if [[ -e "$EVIDENCE_DIR" ]]; then
    printf 'C0.1 local: el directorio de evidencia ya existe: %s\n' \
      "$EVIDENCE_DIR" >&2
    exit 73
  fi
elif [[ $# -ne 0 ]]; then
  printf 'uso: %s [--evidence-dir /private/tmp/c01-evidence-<nombre>]\n' \
    "${0##*/}" >&2
  exit 64
fi

if [[ -n ${PGHOST-} || -n ${PGPORT-} || -n ${PGDATABASE-}
   || -n ${PGUSER-} || -n ${PGSERVICE-} || -n ${PGSERVICEFILE-}
   || -n ${PGPASSWORD-} || -n ${PGPASSFILE-} || -n ${PGOPTIONS-}
   || -n ${DATABASE_URL-}
   || -n ${SUPABASE_DB_URL-} ]]; then
  printf '%s\n' \
    'C0.1 local rehusa variables de conexion: limpie PG*/DATABASE_URL/SUPABASE_DB_URL.' >&2
  exit 64
fi

unset PGHOST PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE
unset PGPASSWORD PGPASSFILE PGOPTIONS DATABASE_URL SUPABASE_DB_URL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CRM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
WORKTREE_ROOT="$(cd "$CRM_ROOT/.." && pwd -P)"

MIGRATIONS_DIR="$CRM_ROOT/supabase/migrations"
BOOTSTRAP_SOURCE="$SCRIPT_DIR/test-c0-1-bootstrap.sql"
EXTRACTOR_SOURCE="$SCRIPT_DIR/c0-1-extraer-funciones.mjs"
MUTATOR_SOURCE="$SCRIPT_DIR/c0-1-generar-mutantes.mjs"
MUTANT_RUNNER_SOURCE="$SCRIPT_DIR/c0-1-run-mutantes.sh"
PROPOSAL_SOURCE="$WORKTREE_ROOT/artifacts/sql-proposals/C0.1-metricas-vendedores-nucleo-unico.sql"
ROLLBACK_SOURCE="$WORKTREE_ROOT/artifacts/sql-proposals/C0.1-metricas-vendedores-nucleo-unico.rollback.sql"
BANK_SOURCE="$WORKTREE_ROOT/artifacts/sql-proposals/C0.1-banco-adversario.sql"
CONFIG_SOURCE="$CRM_ROOT/supabase/config.toml"

for required in \
  "$BOOTSTRAP_SOURCE" \
  "$EXTRACTOR_SOURCE" \
  "$MUTATOR_SOURCE" \
  "$MUTANT_RUNNER_SOURCE" \
  "$PROPOSAL_SOURCE" \
  "$ROLLBACK_SOURCE" \
  "$BANK_SOURCE" \
  "$CONFIG_SOURCE"
do
  if [[ ! -f "$required" ]]; then
    printf 'C0.1 local: falta %s\n' "$required" >&2
    exit 66
  fi
done
if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  printf 'C0.1 local: falta %s\n' "$MIGRATIONS_DIR" >&2
  exit 66
fi

if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' 'C0.1 local requiere Node.js para extraer y materializar snapshots.' >&2
  exit 69
fi

node --input-type=module - "$CONFIG_SOURCE" <<'NODE'
import { readFileSync } from 'node:fs';

const text = readFileSync(process.argv[2], 'utf8');
const lines = text.split(/\r?\n/);
const start = lines.findIndex((line) => /^\[api\]\s*$/.test(line));
const end = start < 0
  ? -1
  : lines.findIndex((line, index) => index > start && /^\[[^\]]+\]\s*$/.test(line));
const api = start < 0 ? [] : lines.slice(start + 1, end < 0 ? undefined : end);
const raw = api
  .map((line) => /^\s*schemas\s*=\s*(\[[^\n]+\])\s*$/.exec(line)?.[1] ?? null)
  .find((value) => value != null);
if (raw == null) throw new Error('config.toml no declara api.schemas');
const schemas = JSON.parse(raw);
if (!Array.isArray(schemas)
    || !schemas.includes('crm')
    || schemas.includes('private')) {
  throw new Error(`frontera PostgREST inesperada: ${JSON.stringify(schemas)}`);
}
NODE

log() {
  printf '[C0.1 local] %s\n' "$*" >&2
}

fail() {
  printf '[C0.1 local] ERROR: %s\n' "$*" >&2
  exit 1
}

find_pg17_bin() {
  local candidates=""
  local candidate=""
  local tool=""
  local ok=""
  local pg_config_path=""
  local initdb_path=""

  pg_config_path="$(command -v pg_config 2>/dev/null || true)"
  if [[ -n "$pg_config_path" ]]; then
    candidates="$($pg_config_path --bindir 2>/dev/null || true)"
  fi
  initdb_path="$(command -v initdb 2>/dev/null || true)"
  if [[ -n "$initdb_path" ]]; then
    candidates="${candidates}${candidates:+$'\n'}$(dirname "$initdb_path")"
  fi
  candidates="${candidates}${candidates:+$'\n'}/opt/homebrew/opt/postgresql@17/bin"
  candidates="${candidates}${candidates:+$'\n'}/usr/local/opt/postgresql@17/bin"
  candidates="${candidates}${candidates:+$'\n'}/Applications/Postgres.app/Contents/Versions/17/bin"

  while IFS= read -r candidate; do
    [[ -n "$candidate" && -x "$candidate/postgres" ]] || continue
    ok=true
    for tool in postgres initdb pg_ctl psql createdb dropdb; do
      if [[ ! -x "$candidate/$tool" ]]; then
        ok=false
        break
      fi
    done
    [[ "$ok" == true ]] || continue
    if "$candidate/postgres" --version 2>/dev/null \
      | grep -Eq 'PostgreSQL\) 17\.'; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done <<< "$candidates"
  return 1
}

PG_BIN="$(find_pg17_bin || true)"
if [[ -z "$PG_BIN" ]]; then
  fail 'no se encontro un juego completo de binarios PostgreSQL 17.'
fi

INITDB="$PG_BIN/initdb"
PG_CTL="$PG_BIN/pg_ctl"
POSTGRES="$PG_BIN/postgres"
PSQL="$PG_BIN/psql"
CREATEDB="$PG_BIN/createdb"
DROPDB="$PG_BIN/dropdb"

# /tmp evita que TMPDIR o una ruta recibida del entorno amplien el alcance del
# borrado. El marcador impide limpiar un directorio distinto del creado aqui.
RUN_DIR="$(mktemp -d /tmp/crm-c01-local.XXXXXXXX)"
RUN_MARKER="$RUN_DIR/.c01-runner-owned"
PGDATA="$RUN_DIR/pgdata"
SOCKET_DIR="$RUN_DIR/socket"
SERVER_LOG="$RUN_DIR/postgres.log"
PORT=55432
CLUSTER_STARTED=false
DB_CREATED=false

RUN_SUFFIX="$(printf '%s' "${RUN_DIR##*.}" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cd 'a-z0-9' \
  | cut -c1-16)"
if [[ -z "$RUN_SUFFIX" ]]; then
  RUN_SUFFIX="p$$"
fi
DB_NAME="crm_c01_${RUN_SUFFIX}"
if [[ ! "$DB_NAME" =~ ^crm_c01_[a-z0-9_]+$ ]]; then
  fail "nombre desechable invalido: $DB_NAME"
fi

printf '%s\n' "$DB_NAME" > "$RUN_MARKER"
chmod 600 "$RUN_MARKER"

cleanup() {
  local status="${1:-0}"
  local cleanup_failed=false
  local cluster_running=false
  local postmaster_pid=""
  local postmaster_may_live=false
  trap - EXIT INT TERM

  if [[ -f "$PGDATA/PG_VERSION" \
     && "$(<"$PGDATA/PG_VERSION")" == 17 ]]; then
    if "$PG_CTL" -D "$PGDATA" status >/dev/null 2>&1; then
      cluster_running=true
    elif [[ -s "$PGDATA/postmaster.pid" ]]; then
      IFS= read -r postmaster_pid < "$PGDATA/postmaster.pid" || true
      if [[ "$postmaster_pid" =~ ^[0-9]+$ ]] \
         && kill -0 "$postmaster_pid" >/dev/null 2>&1; then
        # pg_ctl no pudo atribuir con certeza el PID. No se senala ni se borra
        # su PGDATA: conservar el diagnostico es mas seguro que matar otro PID.
        postmaster_may_live=true
      fi
    fi
  fi

  if [[ "$cluster_running" == true ]]; then
    if [[ "$DB_CREATED" == true && "$DB_NAME" =~ ^crm_c01_[a-z0-9_]+$ ]]; then
      if ! "$DROPDB" -h "$SOCKET_DIR" -p "$PORT" -U postgres \
        --if-exists "$DB_NAME" >/dev/null 2>&1; then
        printf '[C0.1 local] no se pudo borrar la base exacta %s\n' "$DB_NAME" >&2
        cleanup_failed=true
      fi
    fi
    if ! "$PG_CTL" -D "$PGDATA" -m fast -w stop >/dev/null 2>&1; then
      if ! "$PG_CTL" -D "$PGDATA" -m immediate -w stop >/dev/null 2>&1; then
        printf '[C0.1 local] no se pudo detener el cluster propio %s\n' "$PGDATA" >&2
        cleanup_failed=true
      fi
    fi
  fi

  if [[ "$postmaster_may_live" == true ]] \
     || "$PG_CTL" -D "$PGDATA" status >/dev/null 2>&1; then
    printf '[C0.1 local] el postmaster propio puede seguir vivo; no se borra %s\n' \
      "$PGDATA" >&2
    cleanup_failed=true
  elif [[ -s "$PGDATA/postmaster.pid" ]]; then
    IFS= read -r postmaster_pid < "$PGDATA/postmaster.pid" || true
    if [[ "$postmaster_pid" =~ ^[0-9]+$ ]] \
       && kill -0 "$postmaster_pid" >/dev/null 2>&1; then
      printf '[C0.1 local] PID %s sigue vivo; no se borra %s\n' \
        "$postmaster_pid" "$PGDATA" >&2
      cleanup_failed=true
    fi
  fi
  CLUSTER_STARTED=false

  if [[ -d "$RUN_DIR" \
     && "$RUN_DIR" == /tmp/crm-c01-local.* \
     && -f "$RUN_MARKER" \
     && "$(<"$RUN_MARKER")" == "$DB_NAME" ]]; then
    if [[ "$cleanup_failed" == false ]]; then
      rm -rf -- "$RUN_DIR"
    else
      printf '[C0.1 local] se conserva diagnostico local en %s\n' "$RUN_DIR" >&2
    fi
  else
    printf '[C0.1 local] marcador de cleanup no coincide; no se borra %s\n' "$RUN_DIR" >&2
    cleanup_failed=true
  fi

  if [[ "$cleanup_failed" == true && "$status" -eq 0 ]]; then
    status=1
  fi
  exit "$status"
}

trap 'cleanup $?' EXIT
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

snapshot_file() {
  local source="$1"
  local destination="$2"
  local attempt=1
  while [[ "$attempt" -le 3 ]]; do
    cp "$source" "$destination"
    if cmp -s "$source" "$destination"; then
      return 0
    fi
    attempt=$((attempt + 1))
  done
  fail "el archivo cambio mientras se copiaba: $source"
}

BOOTSTRAP_SNAPSHOT="$RUN_DIR/bootstrap.sql"
EXTRACTOR_SNAPSHOT="$RUN_DIR/extraer-funciones.mjs"
MUTATOR_SNAPSHOT="$RUN_DIR/generar-mutantes.mjs"
MUTANT_RUNNER_SNAPSHOT="$RUN_DIR/run-mutantes.sh"
PROPOSAL_SNAPSHOT="$RUN_DIR/propuesta.snapshot.sql"
ROLLBACK_SNAPSHOT="$RUN_DIR/rollback.snapshot.sql"
BANK_SNAPSHOT="$RUN_DIR/banco.snapshot.sql"

snapshot_file "$BOOTSTRAP_SOURCE" "$BOOTSTRAP_SNAPSHOT"
snapshot_file "$EXTRACTOR_SOURCE" "$EXTRACTOR_SNAPSHOT"
snapshot_file "$MUTATOR_SOURCE" "$MUTATOR_SNAPSHOT"
snapshot_file "$MUTANT_RUNNER_SOURCE" "$MUTANT_RUNNER_SNAPSHOT"
snapshot_file "$PROPOSAL_SOURCE" "$PROPOSAL_SNAPSHOT"
snapshot_file "$ROLLBACK_SOURCE" "$ROLLBACK_SNAPSHOT"
snapshot_file "$BANK_SOURCE" "$BANK_SNAPSHOT"

# El runner debe fallar antes de crear el cluster si la propuesta vuelve a usar
# locks de catalogo que el rol postgres de Supabase administrado no puede tomar,
# o si pierde alguna de las dieciocho exclusiones por objeto.
node --input-type=module - "$PROPOSAL_SNAPSHOT" <<'NODE'
import { readFileSync } from 'node:fs';

const propuesta = readFileSync(process.argv[2], 'utf8');
if (/\block\s+table\b[^;]*\bpg_(?:authid|auth_members|namespace|proc)\b/is.test(propuesta)) {
  throw new Error('la propuesta reintrodujo LOCK TABLE sobre catalogos del sistema');
}
for (const ancla of [
  'do $object_locks$',
  'pg_advisory_xact_lock',
  "'alter function %s cost %s'",
  'pg_current_xact_id()',
  'v_objetos_marcados is distinct from 18',
]) {
  if (!propuesta.includes(ancla)) {
    throw new Error(`falta la guarda de exclusion por objeto: ${ancla}`);
  }
}
const inicio = propuesta.indexOf('do $object_locks$');
const fin = propuesta.indexOf('$object_locks$;', inicio);
if (inicio < 0 || fin < 0) throw new Error('bloque object_locks incompleto');
const bloque = propuesta.slice(inicio, fin);
const firmas = [...bloque.matchAll(/\(\s*'((?:crm|private)\.[^']+)'\s*,\s*'__CAPTURAR_/g)]
  .map((match) => match[1]);
if (firmas.length !== 18 || new Set(firmas).size !== 18) {
  throw new Error(`object_locks no contiene 18 firmas unicas (${firmas.length})`);
}
NODE

# La biblioteca se carga solo desde la copia privada e inmutable de esta corrida.
# Sus funciones comparten exclusivamente el cluster, socket y snapshots creados
# por este runner; no ofrece una entrada ejecutable independiente.
source "$MUTANT_RUNNER_SNAPSHOT"

# El banco debe establecer el caso real antes del bloque de mutantes internos.
node --input-type=module - "$BANK_SNAPSHOT" <<'NODE'
import { readFileSync } from 'node:fs';

const banco = readFileSync(process.argv[2], 'utf8');
const real = banco.indexOf('do $baseline$');
const mutantes = banco.indexOf('do $cobertura$');
if (real < 0 || mutantes < 0 || real >= mutantes) {
  throw new Error('el banco ya no ejecuta el caso real antes de sus mutantes');
}
NODE

mkdir -m 700 "$PGDATA" "$SOCKET_DIR"
log "PostgreSQL $($POSTGRES --version) · cluster propio $RUN_DIR"

if ! "$INITDB" -D "$PGDATA" -U postgres --encoding=UTF8 --locale=C \
  --auth-local=trust --auth-host=reject --no-instructions \
  >"$RUN_DIR/initdb.log" 2>&1; then
  sed -n '1,240p' "$RUN_DIR/initdb.log" >&2
  fail 'initdb fallo.'
fi

if [[ "$SOCKET_DIR" == *"'"* ]]; then
  fail 'la ruta del socket contiene una comilla no admitida.'
fi
{
  printf '%s\n' "listen_addresses = ''"
  printf "unix_socket_directories = '%s'\n" "$SOCKET_DIR"
  printf '%s\n' 'unix_socket_permissions = 0700'
  printf 'port = %s\n' "$PORT"
  printf '%s\n' 'max_connections = 20'
} >> "$PGDATA/postgresql.conf"

if ! "$PG_CTL" -D "$PGDATA" -l "$SERVER_LOG" -w start \
  >"$RUN_DIR/pg-ctl-start.log" 2>&1; then
  if "$PG_CTL" -D "$PGDATA" status >/dev/null 2>&1; then
    CLUSTER_STARTED=true
  fi
  sed -n '1,240p' "$RUN_DIR/pg-ctl-start.log" >&2
  sed -n '1,240p' "$SERVER_LOG" >&2
  fail 'PostgreSQL 17 local no inicio.'
fi
CLUSTER_STARTED=true

SERVER_IDENTITY="$($PSQL -X -qAt -F '|' \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d postgres \
  -c "select current_setting('server_version_num')::int / 10000, current_user, inet_server_addr() is null, current_setting('listen_addresses'), current_setting('unix_socket_directories')")"
EXPECTED_IDENTITY="17|postgres|t||$SOCKET_DIR"
if [[ "$SERVER_IDENTITY" != "$EXPECTED_IDENTITY" ]]; then
  fail "frontera de conexion inesperada: $SERVER_IDENTITY"
fi

log 'frontera verificada: PG17, usuario postgres, socket Unix privado, TCP desactivado.'

$PSQL -X -v ON_ERROR_STOP=1 -q \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d postgres <<'SQL'
create role anon
  nosuperuser nocreatedb nocreaterole noinherit nologin noreplication nobypassrls;
create role authenticated
  nosuperuser nocreatedb nocreaterole noinherit nologin noreplication nobypassrls;
create role service_role
  nosuperuser nocreatedb nocreaterole noinherit nologin noreplication bypassrls;
SQL

"$CREATEDB" -h "$SOCKET_DIR" -p "$PORT" -U postgres \
  --owner=postgres --template=template0 --encoding=UTF8 "$DB_NAME"
DB_CREATED=true

if ! $PSQL -X -v ON_ERROR_STOP=1 -q \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
  -f "$BOOTSTRAP_SNAPSHOT" >"$RUN_DIR/bootstrap.log" 2>&1; then
  sed -n '1,320p' "$RUN_DIR/bootstrap.log" >&2
  fail 'el bootstrap minimo fallo.'
fi

EXTRACTED_SQL="$RUN_DIR/funciones-extraidas.sql"
EXTRACTED_MANIFEST="$RUN_DIR/funciones-extraidas.manifest"
if ! node "$EXTRACTOR_SNAPSHOT" "$MIGRATIONS_DIR" "$EXTRACTED_SQL" \
  > "$EXTRACTED_MANIFEST" 2> "$RUN_DIR/extractor.err"; then
  sed -n '1,240p' "$RUN_DIR/extractor.err" >&2
  fail 'no se pudieron extraer las funciones canonicas.'
fi
if [[ ! -s "$EXTRACTED_SQL" || ! -s "$EXTRACTED_MANIFEST" ]]; then
  fail 'la extraccion canonica quedo vacia.'
fi

if ! $PSQL -X -v ON_ERROR_STOP=1 -q \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
  -f "$EXTRACTED_SQL" >"$RUN_DIR/funciones.log" 2>&1; then
  sed -n '1,360p' "$RUN_DIR/funciones.log" >&2
  fail 'las funciones canonicas no cargaron.'
fi

# Replica los ACL directos de las migraciones de origen. Las funciones privadas
# no exponen EXECUTE salvo los tres helpers usados por policies; los wrappers
# publicos conservan su allowlist propia. C0.1 exige una allowlist aun mas
# estrecha para metricas_vendedores_fn: solo authenticated.
$PSQL -X -v ON_ERROR_STOP=1 -q \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" <<'SQL'
revoke all on schema crm, private from public, anon;
grant usage on schema crm, private to authenticated, service_role;

revoke all on function private.rol_crm(uuid) from public, anon;
revoke all on function private.vendedor_ids_visibles(uuid) from public, anon;
revoke all on function private.es_lector_global() from public, anon;
grant execute on function private.rol_crm(uuid) to authenticated;
grant execute on function private.vendedor_ids_visibles(uuid) to authenticated;
grant execute on function private.es_lector_global() to authenticated;

revoke all on function private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])
  from public, anon, authenticated, service_role;
revoke all on function private.roster_metas_vendedores()
  from public, anon, authenticated, service_role;
revoke all on function private.vendedores_sin_supervisor()
  from public, anon, authenticated, service_role;
revoke all on function private.peso_referido_conversion(date)
  from public, anon, authenticated, service_role;
revoke all on function private.etiqueta_mes_es(date)
  from public, anon, authenticated, service_role;
revoke all on function private.cierre_anulado(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.cierre_externo_anulado(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.ajuste_pendiente_por_vendedor()
  from public, anon, authenticated, service_role;
revoke all on function private.conversion_con_ajuste(numeric,numeric)
  from public, anon, authenticated, service_role;
revoke all on function private.cierre_mes_visible(date,uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.metricas_cartera_por_vendedor(date)
  from public, anon, authenticated, service_role;
revoke all on function private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)
  from public, anon, authenticated, service_role;
revoke all on function private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)
  from public, anon, authenticated, service_role;

revoke all on function crm.metricas_cartera_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_cartera_fn(date)
  to authenticated, service_role;
revoke all on function crm.conversion_mensual_sin_cartera_fn(date)
  from public, anon, authenticated, service_role;
revoke all on function crm.conversion_mensual_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.conversion_mensual_fn(date)
  to authenticated, service_role;
revoke all on function crm.metricas_vendedores_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_vendedores_fn()
  to authenticated;
SQL

PAIR_FILE="$RUN_DIR/placeholders-firmas.tsv"
SPECIAL_FILE="$RUN_DIR/placeholders-especiales.tsv"
CANDIDATE_FILE="$RUN_DIR/placeholders-candidatos.tsv"
CANDIDATE_DDL="$RUN_DIR/candidatos-funciones.sql"

node --input-type=module - \
  "$PROPOSAL_SNAPSHOT" "$PAIR_FILE" "$SPECIAL_FILE" \
  "$CANDIDATE_FILE" "$CANDIDATE_DDL" <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';

const [
  entrada,
  paresSalida,
  especialesSalida,
  candidatosSalida,
  ddlSalida,
] = process.argv.slice(2);
const sql = readFileSync(entrada, 'utf8');
const placeholders = new Set(sql.match(/__CAPTURAR_[A-Z0-9_]+__/g) ?? []);
if (placeholders.size === 0) throw new Error('la propuesta no contiene placeholders');
const catalogo = [...placeholders].filter((p) => p.includes('CATALOGO'));

const paresPorPlaceholder = new Map();
const rx = /\(\s*'([^']+)'\s*,\s*'(__CAPTURAR_[A-Z0-9_]+__)'\s*,/g;
let match;
while ((match = rx.exec(sql)) !== null) {
  const previo = paresPorPlaceholder.get(match[2]);
  if (previo != null && previo !== match[1]) {
    throw new Error(`placeholder ${match[2]} apunta a dos firmas`);
  }
  paresPorPlaceholder.set(match[2], match[1]);
}
const candidatos = [...paresPorPlaceholder].filter(([placeholder]) =>
  placeholder.includes('CUERPO') || placeholder.includes('CANDIDATO')
);
if (catalogo.length !== 1 || candidatos.length !== 2) {
  throw new Error('se esperaba un catalogo y dos cuerpos candidatos');
}
// Los hashes candidatos se calibran instalando ambos cuerpos dentro de una
// transaccion que revierte. No pertenecen al fingerprint previo.
paresPorPlaceholder.delete(catalogo[0]);
for (const [placeholder] of candidatos) {
  paresPorPlaceholder.delete(placeholder);
}
const pares = [...paresPorPlaceholder.entries()];
const pairKeys = new Set(paresPorPlaceholder.keys());

const cubiertos = new Set([
  ...pairKeys,
  catalogo[0],
  ...candidatos.map(([placeholder]) => placeholder),
]);
if (cubiertos.size !== placeholders.size
    || [...placeholders].some((p) => !cubiertos.has(p))) {
  throw new Error('hay placeholders sin estrategia de captura local');
}

function regexEscape(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const ddls = [];
for (const [placeholder, signature] of candidatos) {
  const qualifiedName = signature.slice(0, signature.indexOf('('));
  const inicioRx = new RegExp(
    `create\\s+or\\s+replace\\s+function\\s+${regexEscape(qualifiedName)}\\s*\\(`,
    'ig',
  );
  const inicios = [...sql.matchAll(inicioRx)];
  if (inicios.length !== 1 || inicios[0].index == null) {
    throw new Error(`${signature}: se esperaba un unico cuerpo candidato`);
  }
  const inicio = inicios[0].index;
  const aperturaMatch = /\bas\s+(\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$)/i.exec(
    sql.slice(inicio),
  );
  if (!aperturaMatch) throw new Error(`${signature}: falta dollar quote`);
  const tag = aperturaMatch[1];
  const apertura = inicio + aperturaMatch.index + aperturaMatch[0].length;
  const cierre = sql.indexOf(`${tag};`, apertura);
  if (cierre < 0) throw new Error(`${signature}: dollar quote sin cerrar`);
  ddls.push({
    placeholder,
    signature,
    inicio,
    ddl: sql.slice(inicio, cierre + tag.length + 1),
  });
}
ddls.sort((a, b) => a.inicio - b.inicio);

writeFileSync(
  paresSalida,
  `${pares.map(([p, f]) => `${p}\t${f}`).join('\n')}\n`,
  { flag: 'wx' },
);
writeFileSync(
  especialesSalida,
  `catalogo\t${catalogo[0]}\n`,
  { flag: 'wx' },
);
writeFileSync(
  candidatosSalida,
  `${ddls.map(({ placeholder, signature }) => `${placeholder}\t${signature}`).join('\n')}\n`,
  { flag: 'wx' },
);
writeFileSync(
  ddlSalida,
  `${ddls.map(({ ddl }) => ddl).join('\n\n')}\n`,
  { flag: 'wx' },
);
NODE

REPLACEMENTS_FILE="$RUN_DIR/reemplazos.tsv"
: > "$REPLACEMENTS_FILE"

while IFS=$'\t' read -r placeholder signature; do
  [[ -n "$placeholder" && -n "$signature" ]] || continue
  if ! printf '%s\n' "$signature" \
    | grep -Eq "^(crm|private)\\.[a-z0-9_]+\\([^'\\\";[:space:]]*\\)$"; then
    fail "firma no segura en captura: $signature"
  fi
  hash="$($PSQL -X -qAt \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    -c "select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('$signature')")"
  if [[ ! "$hash" =~ ^[0-9a-f]{32}$ ]]; then
    fail "no se capturo md5(prosrc) desde catalogo para $signature"
  fi
  printf '%s\t%s\n' "$placeholder" "$hash" >> "$REPLACEMENTS_FILE"
done < "$PAIR_FILE"

CATALOG_SQL="$RUN_DIR/capturar-catalogo.sql"
{
  printf '%s\n' '\set ON_ERROR_STOP on' 'with deps(firma) as (values'
  first=true
  while IFS=$'\t' read -r _placeholder signature; do
    [[ -n "$signature" ]] || continue
    if [[ "$first" == true ]]; then
      first=false
    else
      printf '%s\n' ','
    fi
    printf "  ('%s')" "$signature"
  done < "$PAIR_FILE"
  printf '%s\n' '' '), filas as ('
  cat <<'SQL'
  select pg_catalog.jsonb_build_object(
    'firma', d.firma,
    'owner', propietario.rolname,
    'language', lenguaje.lanname,
    'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
    'result', pg_catalog.pg_get_function_result(p.oid),
    'kind', p.prokind::text,
    'security_definer', p.prosecdef,
    'leakproof', p.proleakproof,
    'strict', p.proisstrict,
    'returns_set', p.proretset,
    'volatility', p.provolatile::text,
    'parallel', p.proparallel::text,
    'config', pg_catalog.to_jsonb(p.proconfig),
    'acl', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantee', coalesce(receptor.rolname, 'PUBLIC'),
            'grantor', otorgante.rolname,
            'privilege', a.privilege_type,
            'grantable', a.is_grantable
          ) order by
            coalesce(receptor.rolname, 'PUBLIC'),
            otorgante.rolname,
            a.privilege_type,
            a.is_grantable
        )
        from pg_catalog.aclexplode(
          coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
        ) a
        left join pg_catalog.pg_roles receptor on receptor.oid = a.grantee
        join pg_catalog.pg_roles otorgante on otorgante.oid = a.grantor
      ),
      '[]'::jsonb
    )
  )::text as fila
  from deps d
  join pg_catalog.pg_proc p
    on p.oid = pg_catalog.to_regprocedure(d.firma)
  join pg_catalog.pg_roles propietario on propietario.oid = p.proowner
  join pg_catalog.pg_language lenguaje on lenguaje.oid = p.prolang
)
select pg_catalog.md5(
  pg_catalog.string_agg(fila, E'\n' order by fila)
)
from filas;
SQL
} > "$CATALOG_SQL"

CATALOG_HASH="$($PSQL -X -qAt -v ON_ERROR_STOP=1 \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
  -f "$CATALOG_SQL")"
if [[ ! "$CATALOG_HASH" =~ ^[0-9a-f]{32}$ ]]; then
  fail 'no se capturo el fingerprint agregado desde el catalogo local.'
fi
CATALOG_PLACEHOLDER="$(awk -F $'\t' '$1 == "catalogo" { print $2 }' "$SPECIAL_FILE")"
printf '%s\t%s\n' "$CATALOG_PLACEHOLDER" "$CATALOG_HASH" >> "$REPLACEMENTS_FILE"

# Calibracion transaccional: instala los dos cuerpos candidatos en su orden,
# consulta pg_proc.prosrc y revierte. Ambos hashes nacen del catalogo del motor,
# no de una aproximacion textual del runner.
CANDIDATE_BEFORE="$RUN_DIR/candidatos-antes.tsv"
: > "$CANDIDATE_BEFORE"
BASELINE_CANDIDATE_DDL="$RUN_DIR/candidatos-baseline.sql"
: > "$BASELINE_CANDIDATE_DDL"
while IFS=$'\t' read -r _placeholder signature; do
  [[ -n "$signature" ]] || continue
  if ! printf '%s\n' "$signature" \
    | grep -Eq "^(crm|private)\\.[a-z0-9_]+\\([^'\\\";[:space:]]*\\)$"; then
    fail "firma candidata no segura: $signature"
  fi
  hash="$($PSQL -X -qAt \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    -c "select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('$signature')")"
  [[ "$hash" =~ ^[0-9a-f]{32}$ ]] \
    || fail "no se capturo el cuerpo previo de $signature"
  printf '%s\t%s\n' "$signature" "$hash" >> "$CANDIDATE_BEFORE"

  definition="$($PSQL -X -qAt \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    -c "select pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('$signature'))")"
  if [[ "$definition" != CREATE\ OR\ REPLACE\ FUNCTION* ]]; then
    fail "no se capturo el DDL canonico completo de $signature"
  fi
  # pg_get_functiondef no promete incluir el terminador en todas las salidas.
  # Un ';' adicional es una sentencia vacia valida cuando el motor ya lo incluyo.
  printf '%s\n;\n' "$definition" >> "$BASELINE_CANDIDATE_DDL"
done < "$CANDIDATE_FILE"

CALIBRATION_SQL="$RUN_DIR/calibrar-cuerpos.sql"
{
  printf '%s\n' '\set ON_ERROR_STOP on' 'begin;'
  printf '\\i %s\n' "$CANDIDATE_DDL"
  while IFS=$'\t' read -r _placeholder signature; do
    [[ -n "$signature" ]] || continue
    printf "select '%s' || E'\\\\t' || pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('%s');\n" \
      "$signature" "$signature"
  done < "$CANDIDATE_FILE"
  printf '%s\n' 'rollback;'
} > "$CALIBRATION_SQL"
CANDIDATE_HASHES="$RUN_DIR/candidatos-hashes.tsv"
if ! $PSQL -X -qAt -v ON_ERROR_STOP=1 \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
  -f "$CALIBRATION_SQL" > "$CANDIDATE_HASHES"; then
  fail 'fallo la calibracion transaccional de los cuerpos candidatos.'
fi

CANDIDATE_AFTER="$RUN_DIR/candidatos-despues.tsv"
: > "$CANDIDATE_AFTER"
while IFS=$'\t' read -r placeholder signature; do
  [[ -n "$placeholder" && -n "$signature" ]] || continue
  hash="$(awk -F $'\t' -v firma="$signature" \
    '$1 == firma { print $2 }' "$CANDIDATE_HASHES")"
  [[ "$hash" =~ ^[0-9a-f]{32}$ ]] \
    || fail "no se calibro el cuerpo candidato de $signature"
  printf '%s\t%s\n' "$placeholder" "$hash" >> "$REPLACEMENTS_FILE"

  after_hash="$($PSQL -X -qAt \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    -c "select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('$signature')")"
  printf '%s\t%s\n' "$signature" "$after_hash" >> "$CANDIDATE_AFTER"
done < "$CANDIDATE_FILE"
if ! cmp -s "$CANDIDATE_BEFORE" "$CANDIDATE_AFTER"; then
  fail 'la calibracion de los cuerpos no revirtio los targets originales.'
fi

MATERIALIZED_PROPOSAL="$RUN_DIR/propuesta.materializada.sql"
MATERIALIZED_COUNT="$(node --input-type=module - \
  "$PROPOSAL_SNAPSHOT" "$REPLACEMENTS_FILE" "$MATERIALIZED_PROPOSAL" <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';

const [entrada, reemplazosEntrada, salida] = process.argv.slice(2);
let sql = readFileSync(entrada, 'utf8');
const originales = new Set(sql.match(/__CAPTURAR_[A-Z0-9_]+__/g) ?? []);
const reemplazos = new Map(
  readFileSync(reemplazosEntrada, 'utf8')
    .trim()
    .split('\n')
    .filter(Boolean)
    .map((linea) => linea.split('\t')),
);
if (reemplazos.size !== originales.size
    || [...originales].some((p) => !reemplazos.has(p))) {
  throw new Error(`capturas incompletas: ${reemplazos.size}/${originales.size}`);
}
for (const [placeholder, value] of reemplazos) {
  if (!/^[0-9a-f]{32}$/.test(value)) {
    throw new Error(`captura no md5 para ${placeholder}`);
  }
  if (!sql.includes(placeholder)) throw new Error(`captura ajena: ${placeholder}`);
  sql = sql.split(placeholder).join(value);
}
if (/__CAPTURAR_[A-Z0-9_]+__/.test(sql)) {
  throw new Error('la copia materializada conserva placeholders');
}
writeFileSync(salida, sql, { flag: 'wx' });
process.stdout.write(`${originales.size}\n`);
NODE
)"

PLACEHOLDER_COUNT="$(wc -l < "$REPLACEMENTS_FILE" | tr -d ' ')"
if [[ "$MATERIALIZED_COUNT" != "$PLACEHOLDER_COUNT" ]]; then
  fail "materializacion inconsistente ($MATERIALIZED_COUNT/$PLACEHOLDER_COUNT)."
fi
log "$PLACEHOLDER_COUNT placeholders capturados automaticamente desde el catalogo local."

MIGRATION_WRAPPER="$RUN_DIR/aplicar-propuesta.sql"
{
  printf '%s\n' '\set ON_ERROR_STOP on'
  printf '%s\n' "select 'C01_MIGRATION_SESSION=' || pg_catalog.pg_backend_pid();"
  printf '\\i %s\n' "$MATERIALIZED_PROPOSAL"
} > "$MIGRATION_WRAPPER"

if ! $PSQL -X -qAt -v ON_ERROR_STOP=1 \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
  -f "$MIGRATION_WRAPPER" >"$RUN_DIR/migracion.log" 2>&1; then
  sed -n '1,1200p' "$RUN_DIR/migracion.log" >&2
  fail 'la propuesta real materializada fallo; no se ejecuta el banco.'
fi

while IFS=$'\t' read -r placeholder signature; do
  [[ -n "$placeholder" && -n "$signature" ]] || continue
  expected_hash="$(awk -F $'\t' -v buscado="$placeholder" \
    '$1 == buscado { print $2 }' "$REPLACEMENTS_FILE")"
  installed_hash="$($PSQL -X -qAt \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    -c "select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('$signature')")"
  if [[ "$installed_hash" != "$expected_hash" ]]; then
    fail "readback de $signature no coincide ($installed_hash vs $expected_hash)."
  fi
done < "$CANDIDATE_FILE"

BANK_WRAPPER="$RUN_DIR/ejecutar-banco.sql"
{
  printf '%s\n' '\set ON_ERROR_STOP on'
  printf '%s\n' "select 'C01_BANK_SESSION=' || pg_catalog.pg_backend_pid();"
  printf '\\i %s\n' "$BANK_SNAPSHOT"
} > "$BANK_WRAPPER"

if ! $PSQL -X -qAt -v ON_ERROR_STOP=1 \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
  -f "$BANK_WRAPPER" >"$RUN_DIR/banco.log" 2>&1; then
  sed -n '1,1800p' "$RUN_DIR/banco.log" >&2
  fail 'el banco adversario fallo.'
fi

MIGRATION_SESSION="$(grep -E '^C01_MIGRATION_SESSION=[0-9]+$' "$RUN_DIR/migracion.log" \
  | sed -n '1p' | cut -d= -f2)"
BANK_SESSION="$(grep -E '^C01_BANK_SESSION=[0-9]+$' "$RUN_DIR/banco.log" \
  | sed -n '1p' | cut -d= -f2)"
if [[ -z "$MIGRATION_SESSION" || -z "$BANK_SESSION"
   || "$MIGRATION_SESSION" == "$BANK_SESSION" ]]; then
  fail 'no se pudo demostrar que propuesta y banco usaron sesiones distintas.'
fi

OK_COUNT="$(grep -c '^C0\.1_BANCO_ADVERSARIO_OK$' "$RUN_DIR/banco.log" || true)"
if [[ "$OK_COUNT" -ne 1 ]]; then
  sed -n '1,1800p' "$RUN_DIR/banco.log" >&2
  fail "el banco no emitio exactamente un OK (conteo=$OK_COUNT)."
fi
if grep -q 'sobrevivio' "$RUN_DIR/banco.log"; then
  sed -n '1,1800p' "$RUN_DIR/banco.log" >&2
  fail 'un mutante interno sobrevivio.'
fi

log "caso real y mutantes internos verdes; sesiones $MIGRATION_SESSION/$BANK_SESSION."

# Reversibilidad ejecutada, no documental: vuelve exactamente a los dos hashes
# baseline, demuestra que la guarda impide repetir la reversa sobre un estado
# distinto del candidato y reinstala C0.1 antes de correr los mutantes externos.
if ! $PSQL -X -v ON_ERROR_STOP=1 -q \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
  -f "$ROLLBACK_SNAPSHOT" >"$RUN_DIR/rollback.log" 2>&1; then
  sed -n '1,1200p' "$RUN_DIR/rollback.log" >&2
  fail 'el rollback exacto C0.1 fallo.'
fi

while IFS=$'\t' read -r signature baseline_hash; do
  [[ -n "$signature" && -n "$baseline_hash" ]] || continue
  installed_hash="$($PSQL -X -qAt \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    -c "select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('$signature')")"
  if [[ "$installed_hash" != "$baseline_hash" ]]; then
    fail "readback rollback de $signature no coincide ($installed_hash vs $baseline_hash)."
  fi
done < "$CANDIDATE_BEFORE"

if $PSQL -X -v ON_ERROR_STOP=1 -q \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
  -f "$ROLLBACK_SNAPSHOT" >"$RUN_DIR/rollback-repetido.log" 2>&1; then
  fail 'el rollback se dejo ejecutar por segunda vez fuera del cuerpo candidato.'
fi
if ! grep -q 'no conserva el candidato aprobado' "$RUN_DIR/rollback-repetido.log"; then
  sed -n '1,320p' "$RUN_DIR/rollback-repetido.log" >&2
  fail 'el segundo rollback fallo por una razon distinta de la guarda esperada.'
fi

if ! $PSQL -X -v ON_ERROR_STOP=1 -q \
  -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
  -f "$MATERIALIZED_PROPOSAL" >"$RUN_DIR/reaplicar-propuesta.log" 2>&1; then
  sed -n '1,1200p' "$RUN_DIR/reaplicar-propuesta.log" >&2
  fail 'C0.1 no pudo reinstalarse despues del rollback exacto.'
fi

while IFS=$'\t' read -r placeholder signature; do
  [[ -n "$placeholder" && -n "$signature" ]] || continue
  expected_hash="$(awk -F $'\t' -v buscado="$placeholder" \
    '$1 == buscado { print $2 }' "$REPLACEMENTS_FILE")"
  installed_hash="$($PSQL -X -qAt \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    -c "select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('$signature')")"
  if [[ "$installed_hash" != "$expected_hash" ]]; then
    fail "readback tras reinstalar $signature no coincide ($installed_hash vs $expected_hash)."
  fi
done < "$CANDIDATE_FILE"

log 'roundtrip forward→rollback→forward verde; la segunda reversa aborto fail-closed.'
run_c01_body_mutants
if [[ -n "$EVIDENCE_DIR" ]]; then
  mkdir -m 700 "$EVIDENCE_DIR"
  cp "$PROPOSAL_SNAPSHOT" "$EVIDENCE_DIR/propuesta-fuente.sql"
  cp "$ROLLBACK_SNAPSHOT" "$EVIDENCE_DIR/rollback-exacto.sql"
  cp "$MATERIALIZED_PROPOSAL" "$EVIDENCE_DIR/propuesta-materializada-local.sql"
  cp "$REPLACEMENTS_FILE" "$EVIDENCE_DIR/reemplazos-local.tsv"
  cp "$CANDIDATE_HASHES" "$EVIDENCE_DIR/candidatos-hashes-local.tsv"
  cp "$EXTRACTED_MANIFEST" "$EVIDENCE_DIR/funciones-extraidas.manifest"
  chmod 600 "$EVIDENCE_DIR"/*
  (
    cd "$EVIDENCE_DIR"
    shasum -a 256 \
      propuesta-fuente.sql \
      rollback-exacto.sql \
      propuesta-materializada-local.sql \
      reemplazos-local.tsv \
      candidatos-hashes-local.tsv \
      funciones-extraidas.manifest \
      > SHA256SUMS
    chmod 600 SHA256SUMS
  )
  log "evidencia sin datos exportada a $EVIDENCE_DIR"
fi
printf '%s\n' 'C0.1_BANCO_ADVERSARIO_OK'
