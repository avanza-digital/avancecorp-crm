#!/usr/bin/env bash
# Carrera E4 de «Reemplazar inversión»: un PAGO en curso contra el reemplazo (Codex r2, hueco de concurrencia). Necesita
# filas CONFIRMADAS que las dos conexiones vean, así que corre en una base DESECHABLE copiada del banco (pg_dump → pg_restore
# en el mismo contenedor, sin pg_cron ni pg_net: sus procesos de fondo impiden clonar con TEMPLATE; el único error esperado
# es el COMMENT de pg_net): confirma la siembra de la batería ahí, corre la carrera y borra la base. El banco no se toca.
#   C2 marca pagada la cuota 1 del contrato 2026-01-910003 y la deja SIN confirmar 3 s (la fila queda bloqueada).
#   C1 pide el reemplazo de ese contrato. Con el cronograma bloqueado ANTES de mirarlo, C1 espera a C2 y ve la cuota
#   pagada → P0409 «cuotas pagadas». Sin ese bloqueo, C1 la vería pendiente, borraría el cronograma con el pago y
#   terminaría OK (el pago se perdería).
#   MUTANTE=1 instala el núcleo sin el bloqueo (dentro de la sesión de C1) para mostrar que la carrera lo detecta.
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$AQUI/../.." && pwd)"
C="${BANCO_CONTENEDOR:-reemplazo-inv-db}"
# La contraseña del banco local NO va en el repo: BANCO_PGPASSWORD, o la de conexion.env (fuera del repo, la de montar.sh).
if [[ -z "${BANCO_PGPASSWORD:-}" ]]; then
  BANCO_PGPASSWORD="$(sed -n 's/^PGPASSWORD=//p' "${BANCO_DIR:-$HOME/dev/banco-reemplazar-inversion}/conexion.env" 2>/dev/null | head -1)"
fi
[[ -n "${BANCO_PGPASSWORD:-}" ]] || { echo "Falta BANCO_PGPASSWORD (o conexion.env en BANCO_DIR)" >&2; exit 2; }
BD="carrera_pago_$$"
T="$(mktemp -d)"
PSQL_ADMIN=(docker exec -i -e PGPASSWORD="$BANCO_PGPASSWORD" "$C" psql -U supabase_admin -h 127.0.0.1 -qAt)
limpiar() { "${PSQL_ADMIN[@]}" -d template1 -c "drop database if exists $BD with (force)" > /dev/null 2>&1; rm -rf "$T"
  docker exec "$C" rm -f "/tmp/$BD.dump" "/tmp/$BD.lista" "/tmp/$BD.err" > /dev/null 2>&1; }
trap limpiar EXIT

docker exec -e PGPASSWORD="$BANCO_PGPASSWORD" -e BD="$BD" "$C" bash -c '
  pg_dump -U supabase_admin -h 127.0.0.1 -d postgres -Fc -f "/tmp/$BD.dump" &&
  pg_restore -l "/tmp/$BD.dump" | grep -viE "pg_cron| cron |SCHEMA - cron|EXTENSION - pg_net| net " > "/tmp/$BD.lista" &&
  psql -U supabase_admin -h 127.0.0.1 -d template1 -qAt -v ON_ERROR_STOP=1 -c "create database $BD" &&
  { pg_restore -U supabase_admin -h 127.0.0.1 -d "$BD" -L "/tmp/$BD.lista" "/tmp/$BD.dump" 2> "/tmp/$BD.err"; true; }
  n=$(grep -c "error:" "/tmp/$BD.err"); c=$(grep -c "COMMENT ON EXTENSION pg_net" "/tmp/$BD.err")
  [ "$n" -le 1 ] && [ "$n" -eq "$c" ]' || { echo "FALLA: no se pudo copiar el banco a $BD"; exit 2; }

python3 -I - "$AQUI/test-reemplazar-inversion.sql" "$RAIZ/migrations/20261017162053_crm_reemplazar_inversion.sql" "$T" "${MUTANTE:-0}" <<'EOF'
import re, sys
bateria, migracion, T, mutante = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == '1'
t = open(bateria, encoding='utf-8').read()
i_siembra = t.index('-- ── Siembra (triggers apagados SOLO aquí)')
i_bloque0 = t.index('-- ── 0 · Reproducción del defecto')
cabecera = t[:i_siembra]                     # \set, begin y los helpers pg_temp
marca = '\\set ON_ERROR_STOP on\nbegin;\n'
assert cabecera.count(marca) == 1
helpers = cabecera.split(marca, 1)[1]
# pg_temp.k (número de contrato → id) se define después de la siembra: se toma de ahí.
mk = re.search(r'create function pg_temp\.k\(.*?\$\$;\n', t, re.S)
helpers += mk.group(0)
# La siembra se CONFIRMA en la base desechable (los helpers pg_temp se pierden al cerrar la sesión: C1 los vuelve a crear).
open(f'{T}/siembra.sql', 'w', encoding='utf-8').write(t[:i_bloque0] + 'commit;\n')
mut = ''
if mutante:
    m = re.search(r'create function private\.reemplazar_inversion_avance\(.*?\n\$function\$;\n', open(migracion, encoding='utf-8').read(), re.S)
    ddl = 'create or replace function' + m.group(0)[len('create function'):]
    ancla = '  perform 1 from public.cronograma_pagos cp where cp.contrato_id = p_fuente order by cp.id for update;\n'
    assert ddl.count(ancla) == 1
    mut = ddl.replace(ancla, '')
open(f'{T}/c1.sql', 'w', encoding='utf-8').write('\\set ON_ERROR_STOP on\nbegin;\n' + mut + helpers + r"""
-- C2 ya tiene la cuota bloqueada (candado consultivo de sesión 777778 = «listo»).
do $$ begin while not exists (select 1 from pg_locks where locktype = 'advisory' and classid = 0 and objid = 777778 and granted) loop perform pg_sleep(0.05); end loop; end $$;
do $demo$
declare r jsonb;
begin
  r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', pg_temp.k('2026-01-910003'), 'Carrera de pago',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-919998', 3000, 'PEN', 15, date '2026-10-07'), pg_temp.cuenta(98));
  raise notice 'RESULTADO OK %', r ->> 'contrato_id';
exception when others then
  raise notice 'RESULTADO % «%»', sqlstate, sqlerrm;
end $demo$;
rollback;
""")
open(f'{T}/c2.sql', 'w', encoding='utf-8').write(r"""
begin;
set local session_replication_role = replica;
update public.cronograma_pagos set estado = 'pagado', monto_pagado = monto_programado, fecha_pago_real = date '2026-10-15'
  where contrato_id = (select id from public.contratos where numero_contrato = '2026-01-910003') and numero_cuota = 1;
select pg_advisory_lock(777778);
select pg_sleep(3);
commit;
select pg_advisory_unlock(777778);
""")
EOF

"${PSQL_ADMIN[@]}" -d "$BD" -v ON_ERROR_STOP=1 -f - < "$T/siembra.sql" > "$T/siembra.out" 2>&1 || { echo "FALLA: siembra"; tail -5 "$T/siembra.out"; exit 2; }
"${PSQL_ADMIN[@]}" -d "$BD" -f - < "$T/c2.sql" > "$T/c2.out" 2>&1 &
P2=$!
"${PSQL_ADMIN[@]}" -d "$BD" -f - < "$T/c1.sql" > "$T/c1.out" 2>&1
wait "$P2"
RES=$(grep -o 'RESULTADO.*' "$T/c1.out" | head -1)
ESPERADO='RESULTADO P0409 .*cuotas pagadas'
[[ "${MUTANTE:-0}" == "1" ]] && ESPERADO='RESULTADO OK'
if [[ "$RES" =~ $ESPERADO ]]; then
  echo "  PASS  E4 pago en curso$([[ "${MUTANTE:-0}" == "1" ]] && echo ' (MUTANTE sin bloqueo: el pago se pierde)') → $RES"
  exit 0
fi
echo "  FALLA E4 pago en curso → ${RES:-sin resultado}"; tail -5 "$T/c1.out"; exit 1
