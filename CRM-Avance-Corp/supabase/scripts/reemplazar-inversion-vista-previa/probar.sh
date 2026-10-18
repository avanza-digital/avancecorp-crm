#!/usr/bin/env bash
# Pruebas de 20261017211313 (vista previa del mes) en el banco Docker reemplazo-inv-db, con la Fase 1 y esta migración
# aplicadas. Dos corridas, cada una en UNA transacción que termina en ROLLBACK:
#   1. la batería ENTERA de la Fase 1 (el núcleo ahora usa los ayudantes: tiene que seguir dando lo mismo);
#   2. test-vista-previa.sql sobre la misma siembra (lo anterior al bloque 0 de la batería de la Fase 1);
#   3. el candado «nadie más los usa» de reversa.sql (sin MUTANTE_SQL): se niega ante una función PL/pgSQL que llama a un
#      ayudante con MAYÚSCULAS o comillas (PL/pgSQL no deja esa dependencia en pg_depend) y no estorba sin ella.
# Con MUTANTE_SQL=<archivo> se instala ese DDL al principio de las corridas 1 y 2 (lo usa mutantes.py).
# Salida: 0 = todo PASS · 1 = alguna aserción FALLA (una defensa detectó algo) · 3 = ERROR DE ENSAYO (no se llegó a
# probar: conexión, contraseña, un mutante que no instala, un error que no es una aserción). mutantes.py solo da por
# muerto un mutante con salida 1.
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
FASE1="$AQUI/../reemplazar-inversion/test-reemplazar-inversion.sql"
C="${BANCO_CONTENEDOR:-reemplazo-inv-db}"
# La contraseña del banco local NO va en el repo: BANCO_PGPASSWORD, o la de conexion.env (fuera del repo, la de montar.sh).
if [[ -z "${BANCO_PGPASSWORD:-}" ]]; then
  BANCO_PGPASSWORD="$(sed -n 's/^PGPASSWORD=//p' "${BANCO_DIR:-$HOME/dev/banco-reemplazar-inversion}/conexion.env" 2>/dev/null | head -1)"
fi
[[ -n "${BANCO_PGPASSWORD:-}" ]] || { echo "Falta BANCO_PGPASSWORD (o conexion.env en BANCO_DIR)" >&2; exit 2; }
PSQL=(docker exec -i -e PGPASSWORD="$BANCO_PGPASSWORD" "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -f -)
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

python3 -I - "$FASE1" "$AQUI/test-vista-previa.sql" "${MUTANTE_SQL:-}" "$T" "$AQUI/reversa.sql" <<'EOF'
import sys
fase1, previa, mutante, T, reversa = sys.argv[1:6]
t = open(fase1, encoding='utf-8').read()
marca = '\\set ON_ERROR_STOP on\nbegin;\n'
assert t.count(marca) == 1 and t.rstrip().endswith('rollback;')
cabecera, cuerpo = t.split(marca, 1)
mut = open(mutante, encoding='utf-8').read() if mutante else ''
# 1. La batería entera de la Fase 1.
open(f'{T}/fase1.sql', 'w', encoding='utf-8').write(marca + mut + cuerpo)
# 2. La siembra de la Fase 1 + las pruebas de la vista previa.
siembra = cuerpo[:cuerpo.index('-- ── 0 · Reproducción del defecto')]
open(f'{T}/previa.sql', 'w', encoding='utf-8').write(marca + mut + siembra + open(previa, encoding='utf-8').read() + '\nrollback;\n')
# 3. El candado de la reversa, tal cual está en reversa.sql y en su orden: ajustes, preflight y núcleo de vuelta a la
#    Fase 1 (que ya no llama a los ayudantes) y recién entonces «nadie más los usa». Todo en ROLLBACK.
r = open(reversa, encoding='utf-8').read()
inicio = r.index("set local lock_timeout = '5s';\nset local statement_timeout")
nadie = r[inicio:r.index('$nadie$;') + len('$nadie$;')]
usa = ('create function pg_temp.usa_ayudante(p uuid) returns text language plpgsql as $f$ '
       'begin return (%s(p))::text; end $f$;\n')
for nombre, llamada in [('mayusculas', 'PRIVATE.CONTRATO_TIENE_CUOTAS_PAGADAS'), ('comillas', '"private"."reemplazo_dia_registro_venta"')]:
    open(f'{T}/nadie_{nombre}.sql', 'w', encoding='utf-8').write(marca + (usa % llamada) + nadie + '\nrollback;\n')
open(f'{T}/nadie_sin_consumidor.sql', 'w', encoding='utf-8').write(marca + nadie + "\ndo $$ begin raise notice 'PASS nadie: sin consumidor no estorba'; end $$;\nrollback;\n")
EOF

FALLAS=0
ENSAYO=0
primer_error() { grep -m1 -E 'ERROR|FATAL|Error response|No such container' "$1" | sed 's/^psql:<stdin>:[0-9]*: //' | cut -c1-220; }
# PASS solo con psql en 0 Y el marcador final; FALLA solo si el error es una aserción de la batería; lo demás, ensayo.
for corrida in fase1 previa; do
  "${PSQL[@]}" < "$T/$corrida.sql" > "$T/$corrida.out" 2>&1
  rc=$?
  fin=$(grep -oE 'PASS (reemplazar_inversion|vista_previa): [0-9]+ bloques[^;]*' "$T/$corrida.out" | tail -1)
  if [[ $rc -eq 0 && -n "$fin" ]]; then
    echo "  PASS  $corrida → $fin"
  elif grep -q 'ERROR:  FALLA' "$T/$corrida.out"; then
    echo "  FALLA $corrida → $(primer_error "$T/$corrida.out")"
    FALLAS=$((FALLAS + 1))
  else
    echo "  ERROR DE ENSAYO $corrida (psql $rc) → $(primer_error "$T/$corrida.out")"
    ENSAYO=$((ENSAYO + 1))
  fi
done
if [[ -z "${MUTANTE_SQL:-}" ]]; then
  # Con consumidor: PASS = la reversa se niega; FALLA = psql termina en 0 SIN negarse; cualquier otra cosa, ensayo.
  for corrida in nadie_mayusculas nadie_comillas; do
    "${PSQL[@]}" < "$T/$corrida.sql" > "$T/$corrida.out" 2>&1
    rc=$?
    if [[ $rc -ne 0 ]] && grep -q 'REVERSA vista_previa: otra función usa la vista previa o sus ayudantes' "$T/$corrida.out"; then
      echo "  PASS  $corrida → la reversa se niega"
    elif [[ $rc -eq 0 ]]; then
      echo "  FALLA $corrida → la reversa NO vio la llamada al ayudante"; FALLAS=$((FALLAS + 1))
    else
      echo "  ERROR DE ENSAYO $corrida (psql $rc) → $(primer_error "$T/$corrida.out")"; ENSAYO=$((ENSAYO + 1))
    fi
  done
  # Sin consumidor: PASS = psql en 0 y el marcador; FALLA = la reversa se niega igual; lo demás, ensayo.
  "${PSQL[@]}" < "$T/nadie_sin_consumidor.sql" > "$T/nadie_sin_consumidor.out" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]] && grep -q 'PASS nadie' "$T/nadie_sin_consumidor.out"; then
    echo "  PASS  nadie_sin_consumidor → sin consumidor no estorba"
  elif grep -q 'REVERSA vista_previa: otra función usa' "$T/nadie_sin_consumidor.out"; then
    echo "  FALLA nadie_sin_consumidor → la reversa se niega sin consumidor"; FALLAS=$((FALLAS + 1))
  else
    echo "  ERROR DE ENSAYO nadie_sin_consumidor (psql $rc) → $(primer_error "$T/nadie_sin_consumidor.out")"; ENSAYO=$((ENSAYO + 1))
  fi
fi
(( ENSAYO > 0 )) && exit 3
(( FALLAS > 0 )) && exit 1
exit 0
