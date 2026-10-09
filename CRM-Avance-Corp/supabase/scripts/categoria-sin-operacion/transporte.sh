#!/usr/bin/env bash
# Transporte de 20261009180000 como lo manda `supabase db query --linked -f`: el archivo ENTERO en UN solo mensaje
# (Simple Query, `psql -c`), como `postgres` y desde una sesión cuyo default_transaction_isolation es 'repeatable read'
# (la migración y la reversa abren su transacción en READ COMMITTED de forma explícita). SOLO banco local de Docker.
#
#   T1 la migración → postflight OK, guarda con el cuerpo nuevo.        T2 la migración otra vez → P0409, nada cambia.
#   T3 el registrador → registra.                                       T4 el registrador otra vez → idempotente.
#   T5 la reversa → la guarda vuelve EXACTAMENTE a la de 20261009120000. T6 la reversa otra vez → P0409, nada cambia.
#   T7 el registrador sin la migración puesta → se niega.               T8 la migración de nuevo → postflight OK.
# Tras cada paso, otra conexión comprueba que no queda ningún candado de aviso (ni el de sesión de las migraciones).
# Espera el banco con la migración SIN aplicar (la guarda de 20261009120000) y lo deja con la migración aplicada.
#
# Uso: bash transporte.sh [contenedor]      (por defecto supabase_db_avancecorp-categoria-20261008)
set -uo pipefail
C="${1:-supabase_db_avancecorp-categoria-20261008}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
MIGRACION="$AQUI/../../migrations/20261009180000_crm_categoria_sin_operacion_solo_nuevo.sql"
VIEJA=8fdd5f1a3d74c073d5fe3327968132b9     # md5 de pg_get_functiondef de la guarda de 20261009120000 (producción 09/10)
consulta() { docker exec -i -e PGPASSWORD=postgres "$C" psql -X -q -At -U supabase_admin -h 127.0.0.1 -d postgres -c "$1"; }
mensaje() {   # $1 = archivo; corre ENTERO en un mensaje, como postgres, sesión REPEATABLE READ; deja salida en $SALIDA
  SALIDA="$(docker exec -i -e PGPASSWORD=postgres -e 'PGOPTIONS=-c default_transaction_isolation=repeatable\ read' "$C" \
    psql -X -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -c "$(cat "$1")" 2>&1)"; return $?
}
huella() { consulta "begin; set local search_path = public;
  select md5(pg_get_functiondef('private.trg_contrato_categoria_por_operacion()'::regprocedure)); rollback;" | sed -n 1p; }
candados() { consulta "select count(*) from pg_locks where locktype = 'advisory'"; }
registro() { consulta "select count(*) from supabase_migrations.schema_migrations where version = '20261009180000'"; }

[ "$(consulta "select coalesce(current_setting('app.settings.jwt_secret', true), '')")" = \
  "super-secret-jwt-token-with-at-least-32-characters-long" ] || { echo "transporte.sh solo corre en un banco LOCAL"; exit 2; }
[ "$(huella)" = "$VIEJA" ] || { echo "el banco no está en el estado de partida (guarda de 20261009120000)"; exit 2; }
FALLOS=(); N=0
paso() {   # $1 nombre · $2 ¿ok? (0/1) · $3 detalle
  N=$((N + 1)); local resto; resto="$(candados)"
  if [ "$2" = 0 ] && [ "$resto" = 0 ]; then echo "OK    $1 — $3 · $resto candados de aviso"
  else echo "FALLA $1 — $3 · $resto candados de aviso"; FALLOS+=("${1%% *}"); fi
}

mensaje "$MIGRACION"; c=$?; NUEVA="$(huella)"
[ $c = 0 ] && [ "$NUEVA" != "$VIEJA" ] && grep -q "pg_advisory_unlock" <<<"$SALIDA"; paso "T1 la migración" $? "salida $c · huella $NUEVA"
mensaje "$MIGRACION"; c=$?
[ $c != 0 ] && grep -q "P0409\|ya se aplicó" <<<"$SALIDA" && [ "$(huella)" = "$NUEVA" ]
paso "T2 la migración otra vez" $? "salida $c · $(grep -o 'ERROR:.*' <<<"$SALIDA" | head -1 | cut -c1-110)"
mensaje "$AQUI/registrar/20261009180000.sql"; c=$?
[ $c = 0 ] && [ "$(registro)" = 1 ]; paso "T3 el registrador" $? "salida $c · filas $(registro)"
mensaje "$AQUI/registrar/20261009180000.sql"; c=$?
[ $c = 0 ] && [ "$(registro)" = 1 ]; paso "T4 el registrador otra vez (idempotente)" $? "salida $c · filas $(registro)"
mensaje "$AQUI/reversa.sql"; c=$?
[ $c = 0 ] && [ "$(huella)" = "$VIEJA" ]; paso "T5 la reversa" $? "salida $c · huella $(huella)"
mensaje "$AQUI/reversa.sql"; c=$?
[ $c != 0 ] && grep -q "no es la que dejó 20261009180000" <<<"$SALIDA" && [ "$(huella)" = "$VIEJA" ]
paso "T6 la reversa otra vez" $? "salida $c · $(grep -o 'ERROR:.*' <<<"$SALIDA" | head -1 | cut -c1-110)"
mensaje "$AQUI/registrar/20261009180000.sql"; c=$?
[ $c != 0 ] && grep -q "no está aplicada" <<<"$SALIDA"; paso "T7 el registrador sin la migración" $? "salida $c · $(grep -o 'ERROR:.*' <<<"$SALIDA" | head -1 | cut -c1-90)"
mensaje "$MIGRACION"; c=$?
[ $c = 0 ] && [ "$(huella)" = "$NUEVA" ]; paso "T8 la migración de nuevo" $? "salida $c · huella $(huella)"

if [ ${#FALLOS[@]} -gt 0 ]; then echo "TRANSPORTE FALLA: ${FALLOS[*]}"; exit 1; fi
echo "TRANSPORTE OK $N/$N"
