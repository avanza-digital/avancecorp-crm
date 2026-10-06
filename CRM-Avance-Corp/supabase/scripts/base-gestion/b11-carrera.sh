#!/usr/bin/env bash
# B11 · Ensayo de DOS SESIONES del freno «no hay cierres de base» (Codex r1, P1). Solo banco LOCAL de Docker.
# Parte de un banco CON B11 aplicada y lo deja CON B11. Migración y reversa van como `postgres`; el andamio (un cierre de
# base falso de enero de 2020, en `replica`) como el superusuario del stack. No acepta URL ni credenciales.
#   A · control SIN el candado: un cierre de base se confirma mientras la migración ya pasó su freno → la carrera existe.
#   B · el mismo candado en modo espera: la instantánea nace DESPUÉS del candado → el freno ve el cierre y se niega.
#   C · la migración final (NOWAIT) con un escritor a medias → se niega al instante, sin aplicar nada.
#   D · la migración final con la ventana abierta 2 s → el escritor que llega en medio espera al commit.
#   E · la reversa final → se niega con un cierre de base confirmado y con un escritor a medias.
# Uso: bash supabase/scripts/base-gestion/b11-carrera.sh --puerto <puerto>
set -uo pipefail
[ "${1:-}" = "--puerto" ] && [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "Uso: b11-carrera.sh --puerto <puerto>"; exit 64; }
PUERTO="$2"
AQUI="$(cd "$(dirname "$0")" && pwd)"
MIG="$AQUI/../../migrations/20261006042144_crm_bases_cargadas_conversion.sql"; REV="$AQUI/reversa-b11.sql"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
sql() { PGPASSWORD=postgres psql -X -q -At -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$PUERTO" -U "$1" -d postgres "${@:2}" 2>&1; }
q() { sql supabase_admin "$@"; }
qp() { sql postgres "$@"; }
huella() { q -F' | ' -c "select count(*), md5(string_agg(n.nspname || '.' || p.proname || '|' || md5(p.prosrc), E'\n' order by n.nspname, p.proname, p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('crm', 'private')"; }
pausa() { perl -e "select(undef,undef,undef,$1)"; }
retirar() { q -c "begin; set local session_replication_role = replica; delete from crm.conversion_acreditaciones where motivo = 'b11-carrera'; commit;" >/dev/null; }
cierres() { q -c "select count(*) from crm.conversion_acreditaciones where origen = 'base_cargada'"; }
FALLOS=0
ok() { if printf '%s' "$3" | grep -q "$2"; then echo "PASS · $1"; else FALLOS=$((FALLOS + 1)); echo "FAIL · $1 → $(printf '%s' "$3" | tail -2 | cut -c1-220)"; fi; }
vale() { if [ "$2" = "$3" ]; then echo "PASS · $1"; else FALLOS=$((FALLOS + 1)); echo "FAIL · $1 ($2 ≠ $3)"; fi; }

cat > "$T/escritor.sql" <<'SQL'
begin;
set local session_replication_role = replica;
insert into crm.conversion_acreditaciones
select (jsonb_populate_record(null::crm.conversion_acreditaciones, to_jsonb(t) || jsonb_build_object(
          'id', gen_random_uuid(), 'lead_id', gen_random_uuid(), 'episodio_id', gen_random_uuid(), 'fuente_id', gen_random_uuid(),
          'inversionista_id', null, 'origen', 'base_cargada', 'motivo', 'b11-carrera',
          'fecha_comercial', '2020-01-15', 'periodo_comercial', '2020-01-01',
          'confirmado_en', '2020-01-15T15:00:00Z', 'vinculado_en', '2020-01-15T15:00:00Z', 'acreditado_en', '2020-01-15T15:00:00Z',
          'plazo_hasta', private.conversion_plazo_hasta('2020-01-01'::date), 'sellado_en', null, 'incluida_en_sello', null))).*
from (select * from crm.conversion_acreditaciones order by creado_en limit 1) t;
select pg_sleep(:espera);
:final;
SQL
escritor() { q -v espera="$1" -v final="$2" -f "$T/escritor.sql" >/dev/null; }

python3 - "$MIG" "$T" <<'PY'
import sys
mig = open(sys.argv[1]).read(); T = sys.argv[2]
i = mig.index('lock table crm.lead_asignaciones'); j = mig.index('\n', i) + 1
fin_pre = '$preflight$;\n'; assert mig.count(fin_pre) == 1 and mig.count(' nowait;') == 1
dormir = fin_pre + 'select pg_sleep(2);\n'
open(T + '/sin-candado-lenta.sql', 'w').write((mig[:i] + mig[j:]).replace(fin_pre, dormir))
open(T + '/candado-espera.sql', 'w').write(mig.replace(' nowait;', ';'))
open(T + '/final-lenta.sql', 'w').write(mig.replace(fin_pre, dormir))
PY

[ "$(q -c "select count(*) from crm.conversion_acreditaciones")" -gt 0 ] || { echo "NOT RUN: el banco no tiene ninguna acreditación que clonar (correr antes seed:demo)"; exit 2; }
ok "0 · reversa final (deja el banco sin B11)" "^t$" "$(qp -c "$(cat "$REV")" | tail -1)"; H0="$(huella)"

echo "A · control SIN el candado"
qp -c "$(cat "$T/sin-candado-lenta.sql")" > "$T/a.out" & pausa 0.8; escritor 0 commit; wait
ok "sin candado, la migración se confirma…" "^t$" "$(cat "$T/a.out")"
vale "…con un cierre de base confirmado dentro: la carrera existe" "$(cierres)" "1"
retirar; ok "    limpieza: reversa" "^t$" "$(qp -c "$(cat "$REV")" | tail -1)"

echo "B · el candado en modo espera"
escritor 1.5 commit & pausa 0.5
ok "tras esperar al escritor, el freno VE su cierre y se niega" "ya existe un cierre de un contacto de base" "$(qp -c "$(cat "$T/candado-espera.sql")")"; wait
vale "no se aplicó nada" "$(huella)" "$H0"; retirar

echo "C · migración final (NOWAIT) con un escritor a medias"
escritor 1.5 rollback & pausa 0.5
ok "se niega al instante" "could not obtain lock on relation" "$(qp -c "$(cat "$MIG")")"; wait
vale "no se aplicó nada" "$(huella)" "$H0"
vale "sin candados consultivos retenidos" "$(q -c "select count(*) from pg_locks where locktype = 'advisory'")" "0"

echo "D · migración final con la ventana abierta 2 s"
qp -c "$(cat "$T/final-lenta.sql")" > "$T/d.out" & pausa 0.8
t0=$(perl -MTime::HiRes=time -e 'print time'); escritor 0 commit; t1=$(perl -MTime::HiRes=time -e 'print time'); wait
ok "la migración se confirma" "^t$" "$(cat "$T/d.out")"
vale "el escritor esperó al commit de la migración" "$(perl -e "print(($t1 - $t0) > 0.8 ? 'espero' : 'no espero')")" "espero"
vale "su cierre nace después de B11" "$(cierres)" "1"; H1="$(huella)"

echo "E · reversa final (NOWAIT)"
ok "con un cierre de base confirmado, se niega" "ya hay cierres de contactos de base" "$(qp -c "$(cat "$REV")")"; retirar
escritor 1.5 rollback & pausa 0.5
ok "con un escritor a medias, se niega al instante" "could not obtain lock on relation" "$(qp -c "$(cat "$REV")")"; wait
vale "el banco sigue con B11" "$(huella)" "$H1"
vale "sin cierres falsos ni candados" "$(cierres)-$(q -c "select count(*) from pg_locks where locktype = 'advisory'")" "0-0"
[ "$FALLOS" -eq 0 ] && echo "B11 carrera: PASS" || { echo "B11 carrera: FAIL ($FALLOS)"; exit 1; }
