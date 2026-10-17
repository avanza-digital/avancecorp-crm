#!/usr/bin/env bash
# Carrera E5 de «Reemplazar inversión»: la REVERSA mientras un reemplazo está por confirmarse (Codex r3, P1). Como E4, corre
# en una base DESECHABLE copiada del banco (pg_dump → pg_restore, sin pg_cron ni pg_net) con la siembra confirmada, y la
# borra al terminar. El banco no se toca.
#   T1 reemplaza el contrato 2026-01-910006 (escribe su copia con reemplazada_por) y tarda 3 s en confirmar.
#   T2 corre reversa.sql en ese momento. La reversa tiene que VER esa copia y conservar la columna reemplazada_por: si
#   decidiera con una foto tomada antes de que T1 confirme, retiraría la columna y la cadena de reemplazos perdería el
#   día de registro de la venta.
#   MUTANTE=1 corre la reversa SIN su candado inicial de crm.inversiones_eliminadas: la columna desaparece.
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
C="${BANCO_CONTENEDOR:-reemplazo-inv-db}"
# La contraseña del banco local NO va en el repo: BANCO_PGPASSWORD, o la de conexion.env (fuera del repo, la de montar.sh).
if [[ -z "${BANCO_PGPASSWORD:-}" ]]; then
  BANCO_PGPASSWORD="$(sed -n 's/^PGPASSWORD=//p' "${BANCO_DIR:-$HOME/dev/banco-reemplazar-inversion}/conexion.env" 2>/dev/null | head -1)"
fi
[[ -n "${BANCO_PGPASSWORD:-}" ]] || { echo "Falta BANCO_PGPASSWORD (o conexion.env en BANCO_DIR)" >&2; exit 2; }
BD="carrera_reversa_$$"
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

python3 -I - "$AQUI/test-reemplazar-inversion.sql" "$AQUI/reversa.sql" "$T" "${MUTANTE:-0}" <<'EOF'
import re, sys
bateria, reversa, T, mutante = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == '1'
t = open(bateria, encoding='utf-8').read()
i_siembra = t.index('-- ── Siembra (triggers apagados SOLO aquí)')
i_bloque0 = t.index('-- ── 0 · Reproducción del defecto')
marca = '\\set ON_ERROR_STOP on\nbegin;\n'
cabecera = t[:i_siembra]
assert cabecera.count(marca) == 1
helpers = cabecera.split(marca, 1)[1]
helpers += re.search(r'create function pg_temp\.k\(.*?\$\$;\n', t, re.S).group(0)
open(f'{T}/siembra.sql', 'w', encoding='utf-8').write(t[:i_bloque0] + 'commit;\n')
open(f'{T}/t1.sql', 'w', encoding='utf-8').write('\\set ON_ERROR_STOP on\nbegin;\n' + helpers + r"""
do $demo$
declare r jsonb;
begin
  r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', pg_temp.k('2026-01-910006'), 'Carrera de reversa',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-919997', 7000, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(97));
  raise notice 'T1 reemplazó: %', r ->> 'contrato_id';
end $demo$;
select pg_advisory_lock(777779);   -- «la copia está escrita y sin confirmar»
select pg_sleep(3);
commit;
select pg_advisory_unlock(777779);
""")
r = open(reversa, encoding='utf-8').read()
ancla = 'lock table crm.inversiones_eliminadas in share row exclusive mode;\n'
if mutante:
    assert r.count(ancla) == 1, 'la reversa no tiene su candado inicial'
    r = r.replace(ancla, '')
open(f'{T}/t2.sql', 'w', encoding='utf-8').write(r"""
do $$ begin while not exists (select 1 from pg_locks where locktype = 'advisory' and classid = 0 and objid = 777779 and granted) loop perform pg_sleep(0.05); end loop; end $$;
""" + r)
EOF

"${PSQL_ADMIN[@]}" -d "$BD" -v ON_ERROR_STOP=1 -f - < "$T/siembra.sql" > "$T/siembra.out" 2>&1 || { echo "FALLA: siembra"; tail -5 "$T/siembra.out"; exit 2; }
"${PSQL_ADMIN[@]}" -d "$BD" -f - < "$T/t1.sql" > "$T/t1.out" 2>&1 &
P1=$!
"${PSQL_ADMIN[@]}" -d "$BD" -v ON_ERROR_STOP=1 -f - < "$T/t2.sql" > "$T/t2.out" 2>&1
R2=$?
wait "$P1"
grep -q 'T1 reemplazó' "$T/t1.out" || { echo "FALLA: T1 no reemplazó"; tail -5 "$T/t1.out"; exit 1; }
[[ "$R2" -eq 0 ]] || { echo "FALLA: la reversa falló"; tail -5 "$T/t2.out"; exit 1; }
NUEVO=$(grep -o 'T1 reemplazó: [0-9a-f-]*' "$T/t1.out" | head -1 | sed 's/T1 reemplazó: //')
# Columna, CHECK y contenido: la copia de T1 sigue diciendo qué contrato quedó.
COPIAS=$("${PSQL_ADMIN[@]}" -d "$BD" -c "select case when exists (select 1 from pg_attribute where attrelid = 'crm.inversiones_eliminadas'::regclass and attname = 'reemplazada_por' and not attisdropped) then (select count(*)::text from crm.inversiones_eliminadas e where to_jsonb(e) ->> 'reemplazada_por' = '$NUEVO' and e.fuente_id = (select id from public.contratos where numero_contrato = '2026-01-910006' union all select (to_jsonb(e2) ->> 'fuente_id')::uuid from crm.inversiones_eliminadas e2 where e2.snapshot #>> '{contrato,numero_contrato}' = '2026-01-910006' limit 1)) || ':' || (select count(*)::text from pg_constraint where conrelid = 'crm.inversiones_eliminadas'::regclass and conname = 'inversiones_eliminadas_reemplazo_check') else 'sin columna' end")
if [[ "${MUTANTE:-0}" == "1" ]]; then
  [[ "$COPIAS" == "sin columna" ]] && { echo "  PASS  E5 reversa a la vez que un reemplazo (MUTANTE sin candado: la columna se pierde)"; exit 0; }
else
  [[ "$COPIAS" == "1:1" ]] && { echo "  PASS  E5 reversa a la vez que un reemplazo → columna, CHECK y la copia de T1 (reemplazada por $NUEVO) se conservan"; exit 0; }
fi
echo "  FALLA E5 reversa a la vez que un reemplazo → copia:check = $COPIAS"; tail -3 "$T/t2.out"; exit 1
