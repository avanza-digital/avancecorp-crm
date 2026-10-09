#!/usr/bin/env bash
# Transporte de 20261009180000 como lo manda `supabase db query --linked -f`: el archivo ENTERO en UN solo mensaje
# (Simple Query, `psql -c`), como `postgres` y desde una sesión cuyo default_transaction_isolation es 'repeatable read'
# (la migración y la reversa abren su transacción en READ COMMITTED de forma explícita). SOLO banco local de Docker.
#
#   T1 la migración → «OK: 20261009180000 aplicada», guarda con el cuerpo nuevo.
#   T2 MISMA SESIÓN: la migración otra vez → P0409; ROLLBACK; en esa misma sesión, 0 candados de aviso.
#   T3 el registrador → registra.                    T4 el registrador otra vez → idempotente.
#   T5 la reversa → la guarda vuelve EXACTAMENTE a la de 20261009120000.
#   T6 MISMA SESIÓN: la reversa otra vez → P0409; ROLLBACK; 0 candados de aviso en esa sesión.
#   T7 el registrador sin la migración puesta → se niega.
#   T8 MISMA SESIÓN: una copia de la migración con el postflight forzado a fallar → error del postflight; ROLLBACK; 0
#      candados de aviso en esa sesión y NADA aplicado (la guarda y su comentario, los de 20261009120000).
#   T9 la migración de nuevo → «OK: 20261009180000 aplicada».
# Los pasos de MISMA SESIÓN prueban el candado de transacción: si la aplicación falla, la conexión puede seguir abierta (o
# volver a un pool) y no puede quedar ningún candado tomado. Además, tras cada paso, OTRA conexión comprueba que no queda
# ningún candado de aviso en todo el banco.
# Espera el banco con la migración SIN aplicar (la guarda de 20261009120000) y lo deja con la migración aplicada.
#
# Uso: bash transporte.sh [contenedor]      (por defecto supabase_db_avancecorp-categoria-20261008)
set -uo pipefail
C="${1:-supabase_db_avancecorp-categoria-20261008}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
MIGRACION="$AQUI/../../migrations/20261009180000_crm_categoria_sin_operacion_solo_nuevo.sql"
VIEJA=8fdd5f1a3d74c073d5fe3327968132b9     # md5 de pg_get_functiondef de la guarda de 20261009120000 (producción 09/10)
COMENTARIO_VIEJO='Una categoría solo cambia en READ COMMITTED (25001). Si el contrato tiene operación de cartera, su categoría no puede quedar distinta de la operación (23514 «La categoría la decide la operación de cartera»). Sin operación no restringe (contratos antiguos).'
consulta() { docker exec -i -e PGPASSWORD=postgres "$C" psql -X -q -At -U supabase_admin -h 127.0.0.1 -d postgres -c "$1"; }
psql_rr() { docker exec -i -e PGPASSWORD=postgres -e 'PGOPTIONS=-c default_transaction_isolation=repeatable\ read' "$C" \
  psql -X -U postgres -h 127.0.0.1 -d postgres "$@"; }
mensaje() {   # $1 = archivo; corre ENTERO en un mensaje (sesión REPEATABLE READ); deja la salida en $SALIDA
  SALIDA="$(psql_rr -v ON_ERROR_STOP=1 -c "$(cat "$1")" 2>&1)"; return $?
}
misma_sesion() {   # $1 = archivo; en UNA conexión: el archivo en un mensaje, ROLLBACK y los candados de aviso de ESA sesión
  SALIDA="$(psql_rr -q -c "$(cat "$1")" -c "rollback" \
    -c "select 'CANDADOS_DE_ESTA_SESION=' || count(*) from pg_locks where locktype = 'advisory' and pid = pg_backend_pid()" 2>&1)"
  PROPIOS="$(grep -o 'CANDADOS_DE_ESTA_SESION=[0-9]*' <<<"$SALIDA" | cut -d= -f2)"
}
huella() { consulta "begin; set local search_path = public;
  select md5(pg_get_functiondef('private.trg_contrato_categoria_por_operacion()'::regprocedure)); rollback;" | sed -n 1p; }
comentario() { consulta "select obj_description('private.trg_contrato_categoria_por_operacion()'::regprocedure, 'pg_proc')"; }
candados() { consulta "select count(*) from pg_locks where locktype = 'advisory'"; }
registro() { consulta "select count(*) from supabase_migrations.schema_migrations where version = '20261009180000'"; }
error() { grep -o 'ERROR:.*' <<<"$SALIDA" | head -1 | cut -c1-120; }

[ "$(consulta "select coalesce(current_setting('app.settings.jwt_secret', true), '')")" = \
  "super-secret-jwt-token-with-at-least-32-characters-long" ] || { echo "transporte.sh solo corre en un banco LOCAL"; exit 2; }
[ "$(huella)" = "$VIEJA" ] || { echo "el banco no está en el estado de partida (guarda de 20261009120000)"; exit 2; }
# La copia con el postflight forzado a fallar (T8): pide un comentario que no existe.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ "$(grep -c "'%20261009180000%'" "$MIGRACION")" = 1 ] || { echo "no encuentro el punto del mutante de T8"; exit 2; }
sed "s/'%20261009180000%'/'%mutante-del-transporte%'/" "$MIGRACION" > "$TMP/postflight-falla.sql"
FALLOS=(); N=0
paso() {   # $1 nombre · $2 ¿ok? (0/1) · $3 detalle
  N=$((N + 1)); local resto; resto="$(candados)"
  if [ "$2" = 0 ] && [ "$resto" = 0 ]; then echo "OK    $1 — $3 · $resto candados de aviso en el banco"
  else echo "FALLA $1 — $3 · $resto candados de aviso en el banco"; FALLOS+=("${1%% *}"); fi
}

mensaje "$MIGRACION"; c=$?; NUEVA="$(huella)"
[ $c = 0 ] && [ "$NUEVA" != "$VIEJA" ] && grep -q "OK: 20261009180000 aplicada" <<<"$SALIDA"
paso "T1 la migración" $? "salida $c · huella $NUEVA"
misma_sesion "$MIGRACION"
grep -q "P0409\|ya se aplicó" <<<"$SALIDA" && [ "$PROPIOS" = 0 ] && [ "$(huella)" = "$NUEVA" ]
paso "T2 MISMA SESIÓN: la migración otra vez" $? "$(error) · candados de esa sesión tras el ROLLBACK: ${PROPIOS:-?}"
mensaje "$AQUI/registrar/20261009180000.sql"; c=$?
[ $c = 0 ] && [ "$(registro)" = 1 ]; paso "T3 el registrador" $? "salida $c · filas $(registro)"
mensaje "$AQUI/registrar/20261009180000.sql"; c=$?
[ $c = 0 ] && [ "$(registro)" = 1 ]; paso "T4 el registrador otra vez (idempotente)" $? "salida $c · filas $(registro)"
mensaje "$AQUI/reversa.sql"; c=$?
[ $c = 0 ] && [ "$(huella)" = "$VIEJA" ] && grep -q "la guarda vuelve a la de 20261009120000" <<<"$SALIDA"
paso "T5 la reversa" $? "salida $c · huella $(huella)"
misma_sesion "$AQUI/reversa.sql"
grep -q "no es la que dejó 20261009180000" <<<"$SALIDA" && [ "$PROPIOS" = 0 ] && [ "$(huella)" = "$VIEJA" ]
paso "T6 MISMA SESIÓN: la reversa otra vez" $? "$(error) · candados de esa sesión tras el ROLLBACK: ${PROPIOS:-?}"
mensaje "$AQUI/registrar/20261009180000.sql"; c=$?
[ $c != 0 ] && grep -q "no está aplicada" <<<"$SALIDA"; paso "T7 el registrador sin la migración" $? "salida $c · $(error | cut -c1-90)"
misma_sesion "$TMP/postflight-falla.sql"
grep -q "postflight: falta el comentario de la guarda" <<<"$SALIDA" && [ "$PROPIOS" = 0 ] && [ "$(huella)" = "$VIEJA" ] \
  && [ "$(comentario)" = "$COMENTARIO_VIEJO" ]
paso "T8 MISMA SESIÓN: postflight forzado a fallar" $? "$(error) · candados de esa sesión tras el ROLLBACK: ${PROPIOS:-?} · huella $(huella) (nada aplicado)"
mensaje "$MIGRACION"; c=$?
[ $c = 0 ] && [ "$(huella)" = "$NUEVA" ] && grep -q "OK: 20261009180000 aplicada" <<<"$SALIDA"
paso "T9 la migración de nuevo" $? "salida $c · huella $(huella)"

if [ ${#FALLOS[@]} -gt 0 ]; then echo "TRANSPORTE FALLA: ${FALLOS[*]}"; exit 1; fi
echo "TRANSPORTE OK $N/$N"
