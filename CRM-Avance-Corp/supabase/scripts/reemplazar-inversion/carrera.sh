#!/usr/bin/env bash
# Carreras de «Reemplazar inversión» con DOS conexiones reales al banco reemplazo-inv-db (migración aplicada). Nada se
# confirma: C1 siembra con la batería dentro de SU transacción y llama a la puerta real; C2 solo toma candados consultivos
# (no necesitan filas confirmadas) y hace ROLLBACK. Comprueba que los choques llegan como PT409 «vuelve a intentar» y que
# nunca sale un 40P01 o un 55P03 crudo (revisión de concurrencia del 17/10/2026).
#   E1 · C2 tiene el candado GLOBAL del cierre (un sello o un plazo en curso) 7 s → C1 recibe PT409.
#   E2 · C2 imita un alta normal del MISMO cliente (candado de la cuenta, luego el mes) → abrazo mortal: C1 termina bien o
#        con PT409, nunca con 40P01.
#   E3 · C2 tiene el mes de AGOSTO (que la siembra de C1 no toca) y C1 muda una venta de octubre a agosto → PT409
#        «Otra operación está usando el mes 08/2026», ANTES de mirar sellos o plazos.
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
C="${BANCO_CONTENEDOR:-reemplazo-inv-db}"
# La contraseña del banco local NO va en el repo: BANCO_PGPASSWORD, o la de conexion.env (fuera del repo, la de montar.sh).
if [[ -z "${BANCO_PGPASSWORD:-}" ]]; then
  BANCO_PGPASSWORD="$(sed -n 's/^PGPASSWORD=//p' "${BANCO_DIR:-$HOME/dev/banco-reemplazar-inversion}/conexion.env" 2>/dev/null | head -1)"
fi
[[ -n "${BANCO_PGPASSWORD:-}" ]] || { echo "Falta BANCO_PGPASSWORD (o conexion.env en BANCO_DIR)" >&2; exit 2; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PSQL=(docker exec -i -e PGPASSWORD="$BANCO_PGPASSWORD" "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -qAt)

# La siembra y los helpers de la batería (todo antes del bloque 0), sin su ROLLBACK final.
python3 -I - "$AQUI/test-reemplazar-inversion.sql" "$T/siembra.sql" <<'EOF'
import sys
t = open(sys.argv[1], encoding='utf-8').read()
i = t.index('-- ── 0 · Reproducción del defecto')
open(sys.argv[2], 'w', encoding='utf-8').write(t[:i])
EOF

c1() {  # $1 = numero del contrato, $2 = fecha de inicio nueva, $3 = cliente, $4 = capital, $5 = tasa
  cat "$T/siembra.sql"
  cat <<SQL
-- Señal para C2: la siembra terminó (candado consultivo de SESIÓN 777777, visible para la otra conexión).
select pg_advisory_lock(777777);
select pg_sleep(1);
do \$demo\$
declare r jsonb;
begin
  r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', pg_temp.k('$1'), 'Carrera de prueba',
      pg_temp.contrato('$3', '2026-01-919999', $4, 'PEN', $5, date '$2'), pg_temp.cuenta(99));
  raise notice 'RESULTADO OK %', r ->> 'contrato_id';
exception when others then
  raise notice 'RESULTADO % «%»', sqlstate, sqlerrm;
end \$demo\$;
rollback;
select pg_advisory_unlock(777777);
SQL
}
ESPERAR_SENAL="do \$\$ begin while not exists (select 1 from pg_locks where locktype = 'advisory' and classid = 0 and objid = 777777 and granted) loop perform pg_sleep(0.05); end loop; end \$\$;"


correr() {  # $1 = nombre, $2 = c1.sql, $3 = c2.sql, $4 = regex de veredicto aceptado
  "${PSQL[@]}" -f - < "$3" > "$T/c2.out" 2>&1 &
  local p2=$!
  "${PSQL[@]}" -f - < "$2" > "$T/c1.out" 2>&1
  wait "$p2"
  local res
  res=$(grep -o 'RESULTADO.*' "$T/c1.out" | head -1)
  if [[ "$res" =~ $4 ]] && ! grep -qE '40P01|55P03' <<<"$res"; then
    echo "  PASS  $1 → $res"
  else
    echo "  FALLA $1 → ${res:-sin resultado}"; tail -5 "$T/c1.out"; FALLAS=$((FALLAS + 1))
  fi
}
FALLAS=0

# E1
c1 2026-01-910001 2026-10-05 c1000000-0000-4000-8000-000000000001 5000 15 > "$T/e1-c1.sql"
cat > "$T/e1-c2.sql" <<SQL
$ESPERAR_SENAL
begin;
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);
select pg_sleep(9);
rollback;
SQL
correr 'E1 cierre de mes en curso' "$T/e1-c1.sql" "$T/e1-c2.sql" 'RESULTADO PT409 .*vuelve a intentar'

# E2
cat > "$T/e2-c2.sql" <<SQL
$ESPERAR_SENAL
begin;
select pg_advisory_xact_lock(hashtextextended('c1000000-0000-4000-8000-000000000001|PEN|' || lpad('99', 20, '9'), 0));
select pg_sleep(3);
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), (date '2026-10-01' - date '2000-01-01')::integer);
rollback;
SQL
correr 'E2 alta del mismo cliente a la vez' "$T/e1-c1.sql" "$T/e2-c2.sql" 'RESULTADO (OK|PT409 .*vuelve a intentar)'

# E3
c1 2026-01-910002 2026-08-28 c1000000-0000-4000-8000-000000000002 2000 18 > "$T/e3-c1.sql"
cat > "$T/e3-c2.sql" <<SQL
$ESPERAR_SENAL
begin;
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), (date '2026-08-01' - date '2000-01-01')::integer);
select pg_sleep(9);
rollback;
SQL
correr 'E3 mes de destino ocupado' "$T/e3-c1.sql" "$T/e3-c2.sql" 'RESULTADO PT409 .*usando el mes 08/2026'

echo "carreras: $((3 - FALLAS))/3 PASS"
exit "$FALLAS"
