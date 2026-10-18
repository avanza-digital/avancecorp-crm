#!/usr/bin/env bash
# Pruebas de 20261018053228 (Reemplazar inversión, Fase 4: cooperativas) en el banco Docker reemplazo-inv-db (esquema de
# producción del 17/10/2026 con la Fase 1 y la vista previa aplicadas; sin datos de producción). UNA corrida, en UNA
# transacción que termina en ROLLBACK: la siembra de la batería de la Fase 1 (lo anterior a su bloque 0) + la MIGRACIÓN
# (su segunda transacción, como postgres: el rol de `supabase db query --linked`) + test-reemplazar-cooperativa.sql.
# Con MUTANTE_MIGRACION=<archivo> usa ese texto en vez del real (lo usa mutantes.py). Con PROBAR_GUARDAR=<carpeta> deja ahí
# el SQL generado y la salida de psql.
# Salida: 0 = PASS (psql en 0 y el marcador final) · 1 = una aserción FALLA, o saltó una defensa de la propia migración
# (PREFLIGHT/POSTFLIGHT) · 3 = ERROR DE ENSAYO (conexión, contraseña, el texto no se deja partir, un error ajeno).
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
FASE1="$AQUI/../reemplazar-inversion/test-reemplazar-inversion.sql"
MIGRACION="${MUTANTE_MIGRACION:-$AQUI/../../migrations/20261018053228_crm_reemplazar_inversion_cooperativa.sql}"
C="${BANCO_CONTENEDOR:-reemplazo-inv-db}"
if [[ -z "${BANCO_PGPASSWORD:-}" ]]; then
  BANCO_PGPASSWORD="$(sed -n 's/^PGPASSWORD=//p' "${BANCO_DIR:-$HOME/dev/banco-reemplazar-inversion}/conexion.env" 2>/dev/null | head -1)"
fi
[[ -n "${BANCO_PGPASSWORD:-}" ]] || { echo "Falta BANCO_PGPASSWORD (o conexion.env en BANCO_DIR)" >&2; exit 2; }
PSQL=(docker exec -i -e PGPASSWORD="$BANCO_PGPASSWORD" "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -f -)
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! python3 -I - "$FASE1" "$AQUI/test-reemplazar-cooperativa.sql" "$MIGRACION" "$T" <<'PYEOF'
import re
import sys

fase1, prueba, migracion, T = sys.argv[1:5]


def falla(msg):
    raise SystemExit('ENSAYO: ' + msg)


# 1. La siembra de la batería de la Fase 1.
t = open(fase1, encoding='utf-8').read()
marca = '\\set ON_ERROR_STOP on\nbegin;\n'
if t.count(marca) != 1 or not t.rstrip().endswith('rollback;'):
    falla('la batería de la Fase 1 cambió de forma')
siembra = t.split(marca, 1)[1]
siembra = siembra[:siembra.index('-- ── 0 · Reproducción del defecto')]

# 2. La migración: su segunda transacción (desde el segundo «begin;» hasta el «commit;» final), como postgres.
m = open(migracion, encoding='utf-8').read()
begins = [x.start() for x in re.finditer(r'(?m)^begin;[ \t]*$', m)]
commits = [x.start() for x in re.finditer(r'(?m)^commit;[ \t]*$', m)]
if len(begins) != 2 or len(commits) != 2 or commits[1] < begins[1]:
    falla('la migración no tiene la forma esperada (dos transacciones: candado de sesión y cuerpo)')
cuerpo = m[begins[1] + len('begin;'):commits[1]]
cola = re.sub(r'(?m)^[ \t]*--.*$', '', m[commits[1]:])
if not re.fullmatch(r'\s*commit;\s*(select\s+(pg_catalog\.)?pg_advisory_unlock\s*\([^;]*\)\s*;\s*)*', cola, re.I):
    falla('después del commit final queda algo más que soltar el candado de sesión')
aplicacion = ('-- ── (probar.sh) La migración, como postgres ──\nset local role postgres;\n' + cuerpo + 'reset role;\nreset search_path;\n')

p = open(prueba, encoding='utf-8').read()
marca_m = '-- @@ MIGRACION @@\n'
if p.count(marca_m) != 1:
    falla('falta la marca de la migración en el test')
antes, despues = p.split(marca_m)
open(f'{T}/coop.sql', 'w', encoding='utf-8').write(marca + siembra + antes + aplicacion + despues + '\nrollback;\n')
PYEOF
then
  echo "  ERROR DE ENSAYO generar → no se pudo partir la migración o el test"
  exit 3
fi

primer_error() { grep -m1 -E 'ERROR|FATAL|Error response|No such container' "$1" | sed 's/^psql:<stdin>:[0-9]*: //' | cut -c1-300; }
"${PSQL[@]}" < "$T/coop.sql" > "$T/coop.out" 2>&1
rc=$?
[[ -n "${PROBAR_GUARDAR:-}" ]] && mkdir -p "$PROBAR_GUARDAR" && cp "$T/coop.sql" "$T/coop.out" "$PROBAR_GUARDAR/"
fin=$(grep -oE 'PASS reemplazar_cooperativa: [0-9]+ bloques[^;]*' "$T/coop.out" | tail -1)
pases=$(grep -c 'NOTICE:  PASS ' "$T/coop.out")
err=$(primer_error "$T/coop.out")
if [[ $rc -eq 0 && -n "$fin" ]]; then
  echo "  PASS  cooperativa → $fin ($pases avisos PASS)"
  exit 0
elif [[ "$err" == ERROR:\ \ FALLA* ]]; then
  echo "  FALLA cooperativa → $err"
  exit 1
elif [[ "$err" =~ ^ERROR:\ \ (PREFLIGHT\ reemplazar_cooperativa|POSTFLIGHT\ reemplazar_cooperativa) ]]; then
  echo "  FALLA cooperativa (defensa de la migración) → $err"
  exit 1
else
  echo "  ERROR DE ENSAYO cooperativa (psql $rc) → $err"
  exit 3
fi
