#!/bin/bash
# Venta cruzada · Fase 4: concurrencia REAL con dos sesiones de Postgres.
#   (a) El mismo envío dos veces a la vez (doble clic): una sola solicitud; el segundo
#       espera al primero y recibe la misma respuesta.
#   (b) B y C preparan a la vez la misma persona y empresa: una gana; la otra espera y
#       recibe D6 (P0409), sin duplicar.
# Solo en el banco sintético con mundo.sql sembrado (puerto 53322). Deja el banco como
# estaba: borra al final lo que sus dos sesiones confirmaron.
# Uso: bash supabase/scripts/venta-cruzada/concurrencia-fase4.sh
set -euo pipefail
export PGPASSWORD=postgres
PSQL=(psql -X -q -h 127.0.0.1 -p 53322 -U postgres -d postgres -v ON_ERROR_STOP=1 -At)
B=c0000000-0000-4000-8000-000000000006
C=c0000000-0000-4000-8000-000000000007
claims() { echo "select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, false), set_config('request.jwt.claim.sub', '$1', false);"; }

X=$("${PSQL[@]}" -c "select id from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000021'")
[ -n "$X" ] || { echo "Falta el mundo de venta cruzada"; exit 1; }
[ "$("${PSQL[@]}" -c "select count(*) from crm.leads")" -le 200 ] || { echo "Solo en el banco sintético"; exit 1; }
K1=$(uuidgen | tr 'A-Z' 'a-z'); K2=$(uuidgen | tr 'A-Z' 'a-z'); K3=$(uuidgen | tr 'A-Z' 'a-z')
coop() { # empresa numero clave
  echo "jsonb_build_object('inversionista_id','$X','empresa','$1','monto',3000,'moneda','PEN',
    'fecha_comercial',(statement_timestamp() at time zone 'America/Lima')::date,
    'vence_en',((statement_timestamp() at time zone 'America/Lima')::date + interval '12 months')::date,
    'numero_transaccion','$2','referencia','REF $2','evidencia',jsonb_build_object('ruta','$X/$3/comprobante.pdf'))"; }

limpiar() {
  "${PSQL[@]}" >/dev/null <<SQL
begin;
set local session_replication_role = replica;
delete from crm.inversion_solicitudes where id in ('$K1','$K2','$K3');
delete from crm.busquedas_cliente_existente where consultado_por in ('$B','$C') and creado_en > '$T0';
commit;
SQL
}
T0=$("${PSQL[@]}" -c "select now()")
LOG1=$(mktemp); LOG2=$(mktemp)
trap 'limpiar; rm -f "$LOG1" "$LOG2"' EXIT

# Las llaves (búsquedas) se confirman antes, como en la app: son otra llamada.
BB=$("${PSQL[@]}" -c "$(claims $B) select (crm.buscar_cliente_existente_fn('DNI','70000021',null,null)->>'busqueda_id');" | tail -1)
BC=$("${PSQL[@]}" -c "$(claims $C) select (crm.buscar_cliente_existente_fn('DNI','70000021',null,null)->>'busqueda_id');" | tail -1)

# (a) Doble clic: misma clave, mismos datos, a la vez.
"${PSQL[@]}" -c "begin; $(claims $B) select crm.preparar_inversion_cliente_existente_fn('$K1','$BB',$(coop qorilazo VC-CC-1 $K1),'Doble clic del analista en la feria'); select pg_sleep(3); commit;" >"$LOG1" 2>&1 &
P1=$!
sleep 1
A2=$("${PSQL[@]}" -c "begin; $(claims $B) select crm.preparar_inversion_cliente_existente_fn('$K1','$BB',$(coop qorilazo VC-CC-1 $K1),'Doble clic del analista en la feria')->>'solicitud_id'; commit;" 2>&1 | tail -1)
wait $P1
N=$("${PSQL[@]}" -c "select count(*) from crm.inversion_solicitudes where id = '$K1'")
[ "$A2" = "$K1" ] && [ "$N" = "1" ] || { echo "CONCURRENCIA (a) FALLÓ: segunda respuesta '$A2', filas $N"; cat "$LOG1"; exit 1; }
echo "(a) doble clic: una sola solicitud y la misma respuesta ✓"

# (b) B y C a la vez sobre X en Prodelco: una gana, la otra recibe D6.
"${PSQL[@]}" -c "begin; $(claims $B) select crm.preparar_inversion_cliente_existente_fn('$K2','$BB',$(coop prodelco VC-CC-2 $K2),'El cliente pidió invertir con B'); select pg_sleep(3); commit;" >"$LOG2" 2>&1 &
P1=$!
sleep 1
set +e
SALIDA=$("${PSQL[@]}" -c "begin; $(claims $C) select crm.preparar_inversion_cliente_existente_fn('$K3','$BC',$(coop prodelco VC-CC-3 $K3),'El cliente pidió invertir con C'); commit;" 2>&1)
set -e
wait $P1
N2=$("${PSQL[@]}" -c "select count(*) from crm.inversion_solicitudes where id = '$K2'")
N3=$("${PSQL[@]}" -c "select count(*) from crm.inversion_solicitudes where id = '$K3'")
if [ "$N2" = "1" ] && [ "$N3" = "0" ] && grep -q "en preparación" <<<"$SALIDA"; then
  echo "(b) B y C a la vez: gana B y C recibe D6 ✓"
else
  echo "CONCURRENCIA (b) FALLÓ: K2=$N2 K3=$N3 salida de C: $SALIDA"; cat "$LOG2"; exit 1
fi
echo "VENTA_CRUZADA_CONCURRENCIA_OK"
