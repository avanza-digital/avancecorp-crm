#!/usr/bin/env bash
# Pruebas de 20261018032400 (recuperar las cinco ventas recargadas) en el banco Docker reemplazo-inv-db (esquema de
# producción del 17/10/2026 con «Reemplazar inversión» aplicada; sin datos de producción). UNA corrida, en UNA transacción
# que termina en ROLLBACK: la siembra de la batería de la Fase 1 (lo anterior a su bloque 0) + test-recuperar-ventas.sql,
# que siembra los cinco casos con las puertas reales, prueba los rechazos del preflight, lo que detecta el postflight
# (inyecciones «durante» la migración) y dos aplicaciones que deben pasar (cada una en una subtransacción que se deshace),
# aplica la migración (BASE), comprueba el resultado y ensaya la REVERSA (reversa.sql, en una subtransacción que se deshace).
# El texto de la migración se parte SOLO por sus marcas: «-- ── CASOS (inicio)» / «-- ── CASOS (fin)», el último BEGIN antes
# de los casos (preámbulo: candados y ajustes de su segunda transacción, sin el «set transaction isolation level») y el
# último «commit;» (después solo puede quedar soltar el candado de sesión). Del bloque CASOS se conserva la tabla temporal
# tal cual la crea la migración (sus columnas se leen de ahí) y su INSERT de producción se cambia por los casos sembrados.
# La aplicación corre como postgres (el rol de `supabase db query --linked`).
# Con MUTANTE_MIGRACION=<archivo> usa ese texto de migración en vez del real (lo usa mutantes.py). Con PROBAR_GUARDAR=<carpeta>
# deja ahí el SQL generado y la salida de psql.
# Salida: 0 = PASS (psql en 0 y el marcador final) · 1 = una aserción FALLA, o saltó una defensa de la propia migración
# (PREFLIGHT/RECUPERAR/POSTFLIGHT) en la aplicación base · 3 = ERROR DE ENSAYO (conexión, contraseña, el texto no se deja
# partir por sus marcas, un error que no es una aserción ni una defensa). mutantes.py solo da por muerto un mutante con 1.
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
FASE1="$AQUI/../reemplazar-inversion/test-reemplazar-inversion.sql"
MIGRACION="${MUTANTE_MIGRACION:-$AQUI/../../migrations/20261018032400_crm_recuperar_ventas_recargadas.sql}"
C="${BANCO_CONTENEDOR:-reemplazo-inv-db}"
# La contraseña del banco local NO va en el repo: BANCO_PGPASSWORD, o la de conexion.env (fuera del repo, la de montar.sh).
if [[ -z "${BANCO_PGPASSWORD:-}" ]]; then
  BANCO_PGPASSWORD="$(sed -n 's/^PGPASSWORD=//p' "${BANCO_DIR:-$HOME/dev/banco-reemplazar-inversion}/conexion.env" 2>/dev/null | head -1)"
fi
[[ -n "${BANCO_PGPASSWORD:-}" ]] || { echo "Falta BANCO_PGPASSWORD (o conexion.env en BANCO_DIR)" >&2; exit 2; }
PSQL=(docker exec -i -e PGPASSWORD="$BANCO_PGPASSWORD" "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -f -)
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! python3 -I - "$FASE1" "$AQUI/test-recuperar-ventas.sql" "$MIGRACION" "$T" "$AQUI/reversa.sql" <<'EOF'
import re
import sys

fase1, prueba, migracion, T, reversa = sys.argv[1:6]


def fin_de_sentencia(s, i):
    """Posición justo después del ';' que cierra la sentencia que empieza en i (salta '...', "...", $tag$...$tag$ y --)."""
    n, j = len(s), i
    while j < n:
        ch = s[j]
        if ch == "'":
            j += 1
            while j < n and not (s[j] == "'" and not s.startswith("''", j)):
                j += 2 if s.startswith("''", j) else 1
            j += 1
        elif ch == '"':
            j = s.index('"', j + 1) + 1
        elif s.startswith('--', j):
            k = s.find('\n', j)
            j = n if k < 0 else k + 1
        elif ch == '$' and re.match(r'\$[A-Za-z_]*\$', s[j:]):
            tag = re.match(r'\$[A-Za-z_]*\$', s[j:]).group(0)
            j = s.index(tag, j + len(tag)) + len(tag)
        elif ch == ';':
            return j + 1
        else:
            j += 1
    raise SystemExit('ENSAYO: una sentencia sin «;» al partir la migración')


def falla(msg):
    raise SystemExit('ENSAYO: ' + msg)


# 1. La siembra de la batería de la Fase 1.
t = open(fase1, encoding='utf-8').read()
marca = '\\set ON_ERROR_STOP on\nbegin;\n'
if t.count(marca) != 1 or not t.rstrip().endswith('rollback;'):
    falla('la batería de la Fase 1 cambió de forma')
siembra = t.split(marca, 1)[1]
siembra = siembra[:siembra.index('-- ── 0 · Reproducción del defecto')]

# 2. La migración, partida por sus marcas.
m = open(migracion, encoding='utf-8').read()
INI, FIN = '-- ── CASOS (inicio)', '-- ── CASOS (fin)'
if m.count(INI) != 1 or m.count(FIN) != 1:
    falla('las marcas CASOS (inicio)/(fin) no aparecen exactamente una vez')
i_ini = m.index(INI)
i_fin = m.index('\n', m.index(FIN)) + 1
commits = [x.start() for x in re.finditer(r'(?m)^commit;[ \t]*$', m)]
if not commits or commits[-1] < i_fin:
    falla('no hay «commit;» final después de los casos')
i_commit = commits[-1]
cola = re.sub(r'(?m)^[ \t]*--.*$', '', m[i_commit:])
if not re.fullmatch(r'\s*commit;\s*(select\s+(pg_catalog\.)?pg_advisory_unlock\s*\([^;]*\)\s*;\s*)*', cola, re.I):
    falla('después del commit final queda algo más que soltar el candado de sesión')
begins = list(re.finditer(r'(?im)^begin\b[^;\n]*;[ \t]*\n', m[:i_ini]))
if not begins:
    falla('no hay BEGIN antes de los casos')
preambulo = m[begins[-1].end():i_ini]
if re.search(r'(?im)^\s*(begin|commit|rollback)\s*;', preambulo):
    falla('el preámbulo de la segunda transacción tiene control de transacciones')
# «set transaction isolation level» solo vale como primera sentencia: la prueba exige READ COMMITTED (el default).
preambulo = re.sub(r'(?im)^[ \t]*set[ \t]+transaction[ \t]+isolation[ \t]+level[^;]*;[ \t]*\n', '', preambulo)

# 3. El bloque CASOS: la MISMA tabla temporal (columnas leídas de la migración) con los casos sembrados en el banco.
bloque = m[i_ini:i_fin]
mc = re.search(r'(?is)create\s+temporary\s+table\s+recuperar_casos\s*\(', bloque)
if not mc:
    falla('el bloque CASOS no crea la tabla temporal recuperar_casos')
fin_crear = fin_de_sentencia(bloque, mc.start())
crear = bloque[mc.start():fin_crear]
interior, partes, nivel, actual = crear[crear.index('(') + 1:crear.rindex(')')], [], 0, ''
for ch in interior:
    nivel += (ch == '(') - (ch == ')')
    if ch == ',' and nivel == 0:
        partes.append(actual)
        actual = ''
    else:
        actual += ch
partes.append(actual)
columnas = [p.split()[0] for p in partes
            if p.strip() and not re.match(r'(?i)\s*(primary|unique|check|constraint|foreign|exclude)\b', p)]
resto = re.sub(r'(?m)^[ \t]*--.*$', '', bloque[:mc.start()] + bloque[fin_crear:]).strip()
if not re.match(r'(?is)insert\s+into\s+pg_temp\.recuperar_casos\b', resto) or fin_de_sentencia(resto, 0) != len(resto):
    falla('el bloque CASOS tiene algo más que la tabla temporal y su INSERT')
lista = ', '.join(columnas)
casos = (INI + ' · SINTÉTICOS (probar.sh): la misma tabla temporal, con los casos sembrados en el banco ──\n' + crear + '\n'
         f'insert into pg_temp.recuperar_casos ({lista})\n  select {lista} from pg_temp.casos_sembrados order by caso;\n'
         + FIN + ' ──\n')
cuerpo = casos + m[i_fin:i_commit]

# 4. El texto queda en pg_temp.migracion_sql (para las aplicaciones dentro de subtransacciones) y la aplicación BASE va en
#    la marca del test, como sentencias de primer nivel.
# 3b. La REVERSA: su segunda transacción (desde su segundo «begin;» hasta su «commit;» final, sin el «set transaction
#     isolation level»), para ensayarla DESPUÉS de la aplicación base (D9) dentro de una subtransacción que se deshace.
r = open(reversa, encoding='utf-8').read()
begins_r = [x.start() for x in re.finditer(r'(?m)^begin;[ \t]*$', r)]
commits_r = [x.start() for x in re.finditer(r'(?m)^commit;[ \t]*$', r)]
if len(begins_r) != 2 or len(commits_r) != 2 or commits_r[1] < begins_r[1]:
    falla('la reversa no tiene la forma esperada (dos transacciones: candado de sesión y cuerpo)')
cuerpo_rev = re.sub(r'(?im)^[ \t]*set[ \t]+transaction[ \t]+isolation[ \t]+level[^;]*;[ \t]*\n', '', r[begins_r[1] + len('begin;'):commits_r[1]])

tag = '$migracion_banco$'
if tag in preambulo or tag in cuerpo or tag in cuerpo_rev:
    falla('el texto de la migración contiene la etiqueta ' + tag)
textos = ('create temporary table migracion_sql (parte text primary key, sql text not null);\n'
          f"insert into pg_temp.migracion_sql values ('preambulo', {tag}{preambulo}{tag}), ('cuerpo', {tag}{cuerpo}{tag}), ('reversa', {tag}{cuerpo_rev}{tag});\n")
p = open(prueba, encoding='utf-8').read()
marca_m = '-- @@ MIGRACION @@\n'
if p.count(marca_m) != 1:
    falla('falta la marca de la migración en el test')
antes, despues = p.split(marca_m)
base = ('-- ── (probar.sh) Aplicación BASE de la migración, como postgres: preámbulo + cuerpo con los casos sembrados ──\n'
        'set local role postgres;\n' + preambulo + cuerpo + 'reset role;\n')
open(f'{T}/recuperar.sql', 'w', encoding='utf-8').write(marca + siembra + textos + antes + base + despues + '\nrollback;\n')
EOF
then
  echo "  ERROR DE ENSAYO generar → no se pudo partir la migración o el test"
  exit 3
fi

primer_error() { grep -m1 -E 'ERROR|FATAL|Error response|No such container' "$1" | sed 's/^psql:<stdin>:[0-9]*: //' | cut -c1-260; }
"${PSQL[@]}" < "$T/recuperar.sql" > "$T/recuperar.out" 2>&1
rc=$?
# PROBAR_GUARDAR=<carpeta>: deja ahí el SQL generado y la salida completa de psql (para depurar).
[[ -n "${PROBAR_GUARDAR:-}" ]] && mkdir -p "$PROBAR_GUARDAR" && cp "$T/recuperar.sql" "$T/recuperar.out" "$PROBAR_GUARDAR/"
fin=$(grep -oE 'PASS recuperar_ventas: [0-9]+ bloques[^;]*' "$T/recuperar.out" | tail -1)
pases=$(grep -c 'NOTICE:  PASS ' "$T/recuperar.out")
err=$(primer_error "$T/recuperar.out")
# PASS solo con psql en 0 Y el marcador final; FALLA si el primer error es una aserción del test o una defensa de la
# migración en la aplicación base; lo demás, ensayo.
if [[ $rc -eq 0 && -n "$fin" ]]; then
  echo "  PASS  recuperar → $fin ($pases avisos PASS)"
  exit 0
elif [[ "$err" == ERROR:\ \ FALLA* ]]; then
  echo "  FALLA recuperar → $err"
  exit 1
elif [[ "$err" =~ ^ERROR:\ \ (PREFLIGHT\ recuperar_ventas|RECUPERAR\ |POSTFLIGHT\ recuperar_ventas|cierre_anulado:\ el\ ancla) ]]; then
  echo "  FALLA recuperar (defensa de la migración en la aplicación base) → $err"
  exit 1
else
  echo "  ERROR DE ENSAYO recuperar (psql $rc) → $err"
  exit 3
fi
