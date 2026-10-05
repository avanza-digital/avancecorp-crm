#!/usr/bin/env bash
# B9 · concurrencia de repartir y recoger (20261004222602) con DOS sesiones reales (una transacción no puede probarla).
# Solo banco LOCAL de Docker (127.0.0.1, secreto JWT de desarrollo del CLI, sin SSL). ESCRIBE y CONFIRMA datos de prueba
# (bases «B9 conc …», teléfonos 9<run>9nnn): limpiar después con supabase/scripts/banco/limpiar-entre-corridas.sql (o la corrida
# del gate, que la ejecuta). La identidad unificada (resolver_en_puertas) se enciende como en producción y se deja como estaba.
# Escenarios (candados de B9: operación → fila de la base NOWAIT → leads en orden de id SKIP LOCKED):
#   (1) dos repartos de la MISMA base: el segundo falla AL INSTANTE (55P03) y el reintento reparte OTROS contactos;
#   (2) recoger mientras se reparte la misma base: 55P03 al instante;
#   (3) intento del analista con el lead tomado y reparto individual de ese lead a otro: 55P03 al instante (no espera); el
#       reintento, ya con el intento confirmado, da 22023 en_gestion (B6);
#   (4) un lead sin repartir tomado por otra transacción: el bloque NO espera, lo salta («ocupado») y reparte los siguientes;
#   (5) reparto primero e intento del analista ANTERIOR después: el intento espera y muere con P0002 (ya no es suyo);
#   (6) reparto primero e intento del analista NUEVO después: el intento espera y entra; el contacto queda «trabajado»;
#   (7) reactivar con el lead tomado y reparto: 55P03 al instante; y al revés, reparto primero: la reactivación del analista
#       anterior espera y muere con P0002;
#   (8) intento con el lead tomado y recoger: recoger NO espera, lo deja (omitido) y recoge los demás;
#   (9) doble clic (mismo id de operación a la vez): el segundo espera al primero y recibe el MISMO recibo (un solo recibo);
#   (10) repartir en REPEATABLE READ → 0A000;
#   (11) vetar con el lead tomado por el reparto: el veto (identidad encendida) toma los leads NOWAIT —su protocolo—: 40001 al
#       instante, sin interbloqueo; el reintento entra (el contacto queda no_contactar, repartido);
#   (12) 5 rondas simultáneas (bloque, individual, recoger, intentos, otra base) sin interbloqueos;
#   r1 (Codex P2: bloquear SOLO lo necesario): (13) mientras un bloque de 2 tiene sus candados, otro proceso toma SIN ESPERAR
#   (NOWAIT) un contacto sin repartir que el bloque no necesitaba; (14) mientras se recoge, un contacto TOCADO del analista
#   (no recogible) no está bloqueado; (15) base armada desde el CRM casi toda en descanso: mientras un bloque de 1 tiene su
#   candado, el analista anterior registra un intento en otro contacto elegible SIN esperar (latencia medida);
#   r2 (Codex: presupuesto de candados), con la sesión del reparto INSTRUMENTADA en su transacción deshecha (una pausa de la foto,
#   entre la foto y los candados): (16) 5 intentos confirmados en esa ventana → el bloque de 2 los salta («ocupado» 5) y una
#   tercera sesión cuenta los candados que retiene (SKIP LOCKED): 7 = 5 rechazados + 2 repartidos; (17) 60 intentos en esa
#   ventana y un bloque de 1 → presupuesto (51) agotado → 55P03 «Los contactos están cambiando; reintenta», nada se reparte.
# Al final: 0 interbloqueos (40P01), 0 errores inesperados y ninguna doble asignación (cada pertenencia repartida coincide con
# el analista del lead, salvo lo movido a propósito; un lead en una sola base viva).
# Uso: bash supabase/scripts/base-gestion/b9-concurrencia.sh --puerto 58122
set -uo pipefail
PUERTO=""
while [ $# -gt 0 ]; do case "$1" in --puerto) PUERTO="$2"; shift 2 ;; *) echo "uso: $0 --puerto <puerto>"; exit 2 ;; esac; done
[ -n "$PUERTO" ] || { echo "uso: $0 --puerto <puerto>"; exit 2; }
export PGPASSWORD="${PGPASSWORD:-postgres}"
Q() { psql -X -h 127.0.0.1 -p "$PUERTO" -U postgres -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
SALIDA=$(mktemp -d)
trap 'rm -rf "$SALIDA"' EXIT

local_ok=$(Q -c "select (md5(coalesce(current_setting('app.settings.jwt_secret', true), '')) = '2a60121f68a3f2b1fb7de7040cb89646' and (select not s.ssl from pg_stat_ssl s where s.pid = pg_backend_pid()) and to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)') is not null)::int")
[ "$local_ok" = "1" ] || { echo "ABORTADO: no es un banco LOCAL de Docker con B9 aplicada"; exit 2; }

RUN=$((RANDOM % 9000 + 1000))
P() { printf '9%s9%03d' "$RUN" "$1"; }          # teléfono de 9 dígitos
u() { Q -c "select id from auth.users where email = '$1.crm@demo.avancecorp.pe'"; }
S1=$(u sup1); G=$(u gerencia); V1=$(u vend1); V2=$(u vend2)
[ -n "$S1" ] && [ -n "$G" ] && [ -n "$V1" ] && [ -n "$V2" ] || { echo "ABORTADO: faltan actores de seed:demo"; exit 2; }
BANDERA_ANTES=$(Q -c "select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'")
Q -c "update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas'" >/dev/null
restaurar() { Q -c "update crm.multiempresa_flags set activo = '${BANDERA_ANTES:-f}'::boolean where nombre = 'resolver_en_puertas'" >/dev/null; }
trap 'restaurar; rm -rf "$SALIDA"' EXIT

como() { printf "begin;\nselect set_config('request.jwt.claim.sub', '%s', true), set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true);\nset local role authenticated;\n" "$1" "$1"; }
filas() { # filas <desde> <hasta>: JSON de un lote con capital
  python3 -c "import json,sys; print(json.dumps([{'fila': i, 'nombre': 'B9 conc %d' % i, 'telefono': '9%s9%03d' % ('$RUN', i), 'capital': '5000'} for i in range(int(sys.argv[1]), int(sys.argv[2]) + 1)]))" "$1" "$2"
}
# Bases de la corrida (confirmadas): X y Y de S1, con 40 y 10 contactos.
BX=$( { como "$S1"; echo "select crm.crear_base(gen_random_uuid(), 'B9 conc X $RUN', 'archivo', null, 'x.csv')->>'base_id';"; echo "commit;"; } | Q | tail -1)
BY=$( { como "$S1"; echo "select crm.crear_base(gen_random_uuid(), 'B9 conc Y $RUN', 'archivo', null, 'y.csv')->>'base_id';"; echo "commit;"; } | Q | tail -1)
[ -n "$BX" ] && [ -n "$BY" ] || { echo "ABORTADO: no se crearon las bases"; exit 1; }
{ como "$S1"; echo "select crm.cargar_base_lote(gen_random_uuid(), '$BX', '$(filas 1 40)'::jsonb) is not null;"; echo "select crm.cargar_base_lote(gen_random_uuid(), '$BY', '$(filas 101 110)'::jsonb) is not null;"; echo "commit;"; } | Q >/dev/null \
  || { echo "ABORTADO: no se cargaron los contactos"; exit 1; }
L() { Q -c "select id from crm.leads where telefono = '+51$(P "$1")'"; }
# Orden de llegada fijo (como el de la carga, pero determinista): contacto n → n minutos «antes».
Q -c "update crm.base_carga_leads bl set creado_en = now() - make_interval(mins => 1000 - right(l.telefono, 3)::int) from crm.leads l where l.id = bl.lead_id and l.telefono like '+519${RUN}9%'" >/dev/null

corre() { # corre <actor|postgres> <sql que devuelve algo | STMT:sentencia> <espera_antes> <espera_despues> <archivo>: «R …» y «MS <duración>»
  ( sleep "$3"; t0=$(python3 -c 'import time; print(time.time())')
    { case "$1" in postgres) echo "begin;" ;; *) como "$1" ;; esac
      case "$2" in STMT:*) echo "${2#STMT:};"; echo "select 'R ok';" ;; *) echo "select 'R ' || ($2)::text;" ;; esac
      echo "select pg_sleep($4);"; echo "commit;"; } | Q > "$5" 2>&1
    echo "rc=$?" >> "$5"; echo "MS $(python3 -c "import time; print(int((time.time() - $t0) * 1000))")" >> "$5" ) &
}
cat > "$SALIDA/ver.py" <<'PY'
import sys, json, os
nombres = {os.environ['V1']: 'v1', os.environ['V2']: 'v2'}
f = sys.argv[1]
lineas = open(f).read().splitlines()
r = [l[2:] for l in lineas if l.startswith('R ')]
err = [l for l in lineas if 'ERROR:' in l]
if not r:
    print(err[0].split('ERROR:', 1)[1].strip() if err else '(sin respuesta)')
    sys.exit()
try:
    d = json.loads(r[0])
except Exception:
    print(r[0]); sys.exit()
if 'recogidos' in d:
    print('%s|%s|%s' % (d['recogidos'], d['omitidos'], d['pendientes']))
elif 'repartidos' in d:
    por = ','.join('%s:%s' % (nombres.get(x['analista_id'], '?'), x['cantidad']) for x in d['por_analista'])
    om = ','.join(('%s:%s' % (x['motivo'], x['cantidad'])) if x.get('lead_id') is None else ('id:%s' % x['motivo']) for x in d['omitidos'])
    print('%s|%s|%s' % (d['repartidos'], por, om))
else:
    print(r[0])
PY
export V1 V2
ver() { python3 "$SALIDA/ver.py" "$1"; }
ms() { grep '^MS ' "$1" | sed 's/^MS //'; }
detalle() { grep -o 'DETAIL: .*' "$1" | head -1 | sed 's/^DETAIL: *//'; }
FALLOS=0
chequea() { if [ "$2" = "$3" ]; then echo "PASS $1 · $3"; else echo "FAIL $1 · esperado $2 · obtenido $3"; FALLOS=$((FALLOS + 1)); fi; }
rapido() { local m; m=$(ms "$2"); if [ -n "$m" ] && [ "$m" -lt 1000 ]; then echo "PASS $1 · $m ms"; else echo "FAIL $1 · tardó ${m:-?} ms (debía fallar o pasar sin esperar)"; FALLOS=$((FALLOS + 1)); fi; }
espero() { local m; m=$(ms "$2"); if [ -n "$m" ] && [ "$m" -ge 1000 ]; then echo "PASS $1 · esperó $m ms"; else echo "FAIL $1 · tardó ${m:-?} ms (debía esperar al otro)"; FALLOS=$((FALLOS + 1)); fi; }
bq() { printf '{"modo": "bloque", "asignaciones": [{"analista_id": "%s", "cantidad": %s}]}' "$1" "$2"; }
ind() { printf '{"modo": "individual", "asignaciones": [{"lead_id": "%s", "analista_id": "%s"}]}' "$1" "$2"; }
rep() { printf "crm.repartir_base(gen_random_uuid(), '%s', '%s'::jsonb)" "$1" "$2"; }
rec() { printf "crm.recoger_de_base(gen_random_uuid(), '%s', '%s')" "$1" "$2"; }
duenio() { Q -c "select coalesce(case l.vendedor_id when '$V1' then 'v1' when '$V2' then 'v2' end, 'b') from crm.leads l where l.id = '$1'"; }

echo "=== B9 concurrencia · run $RUN · banco 127.0.0.1:$PUERTO ==="
# (1) dos repartos de la misma base.
corre "$S1" "$(rep "$BX" "$(bq "$V1" 2)")" 0 2 "$SALIDA/1a"
corre "$S1" "$(rep "$BX" "$(bq "$V2" 2)")" 0.5 0 "$SALIDA/1b"
wait
chequea '(1) reparto A (v1 2)' '2|v1:2|' "$(ver "$SALIDA/1a")"
chequea '(1) reparto B mientras A reparte → 55P03 «Hay otra operación en curso de esta base; reintenta»' 'Hay otra operación en curso de esta base; reintenta' "$(ver "$SALIDA/1b")"
rapido '(1) … B falla sin esperar a A' "$SALIDA/1b"
corre "$S1" "$(rep "$BX" "$(bq "$V2" 2)")" 0 0 "$SALIDA/1c"
wait
chequea '(1) reintento de B: reparte OTROS dos (v2 2)' '2|v2:2|' "$(ver "$SALIDA/1c")"
chequea '(1) … los cuatro primeros: v1 v1 v2 v2' 'v1 v1 v2 v2' "$(echo $(duenio "$(L 1)") $(duenio "$(L 2)") $(duenio "$(L 3)") $(duenio "$(L 4)"))"
# (2) recoger mientras se reparte la misma base.
corre "$S1" "$(rep "$BX" "$(bq "$V1" 1)")" 0 2 "$SALIDA/2a"
corre "$S1" "$(rec "$BX" "$V2")" 0.5 0 "$SALIDA/2b"
wait
chequea '(2) reparto (v1 1)' '1|v1:1|' "$(ver "$SALIDA/2a")"
chequea '(2) recoger durante el reparto → 55P03' 'Hay otra operación en curso de esta base; reintenta' "$(ver "$SALIDA/2b")"
rapido '(2) … sin esperar' "$SALIDA/2b"
# (3) intento con el lead tomado, reparto individual del mismo a otro.
X3=$(L 1)   # de v1 desde (1)
corre "$V1" "crm.registrar_intento_base(gen_random_uuid(), '$X3', 'no_contesto', null, null)" 0 2 "$SALIDA/3a"
corre "$S1" "$(rep "$BX" "$(ind "$X3" "$V2")")" 0.5 0 "$SALIDA/3b"
wait
chequea '(3) intento de v1' '{"ok": true' "$(grep '^R ' "$SALIDA/3a" | cut -c3-13)"
chequea '(3) reparto individual del lead tomado → 55P03 al instante' 'Otra operación está usando alguno de esos contactos; reintenta' "$(ver "$SALIDA/3b")"
rapido '(3) … sin esperar al intento' "$SALIDA/3b"
corre "$S1" "$(rep "$BX" "$(ind "$X3" "$V2")")" 0 0 "$SALIDA/3c"
wait
chequea '(3) reintento con el intento confirmado → 22023 en_gestion (B6)' "{\"rechazados\": [{\"motivo\": \"en_gestion\", \"lead_id\": \"$X3\"}]}" "$(detalle "$SALIDA/3c")"
# (4) un lead sin repartir tomado por otra transacción: el bloque lo salta sin esperar.
Y4=$(L 6)   # el más antiguo sin repartir (1-5 repartidos)
corre postgres "STMT:select 1 from crm.leads where id = '$Y4' for update" 0 2 "$SALIDA/4a"
corre "$S1" "$(rep "$BX" "$(bq "$V1" 2)")" 0.5 0 "$SALIDA/4b"
wait
chequea '(4) bloque de 2 con el más antiguo tomado → reparte los dos siguientes, omitido «ocupado»' '2|v1:2|ocupado:1' "$(ver "$SALIDA/4b")"
rapido '(4) … sin esperar' "$SALIDA/4b"
chequea '(4) … el tomado sigue sin repartir; 7 y 8 a v1' 'b v1 v1' "$(echo $(duenio "$Y4") $(duenio "$(L 7)") $(duenio "$(L 8)"))"
# (5) reparto primero, intento del analista ANTERIOR después.
X5=$(L 3)   # de v2 desde (1)
corre "$S1" "$(rep "$BX" "$(ind "$X5" "$V1")")" 0 2 "$SALIDA/5a"
corre "$V2" "crm.registrar_intento_base(gen_random_uuid(), '$X5', 'no_contesto', null, null)" 0.5 0 "$SALIDA/5b"
wait
chequea '(5) reparto individual de v2 a v1' '1|v1:1|' "$(ver "$SALIDA/5a")"
chequea '(5) el intento de v2 (anterior) espera y muere con P0002' 'Lead no encontrado o fuera de tu ambito' "$(ver "$SALIDA/5b")"
espero '(5) … el intento esperó al reparto' "$SALIDA/5b"
# (6) reparto primero, intento del analista NUEVO después.
X6=$(L 9)   # sin repartir
corre "$S1" "$(rep "$BX" "$(ind "$X6" "$V1")")" 0 2 "$SALIDA/6a"
corre "$V1" "crm.registrar_intento_base(gen_random_uuid(), '$X6', 'no_contesto', null, null)" 0.5 0 "$SALIDA/6b"
wait
chequea '(6) reparto individual a v1' '1|v1:1|' "$(ver "$SALIDA/6a")"
chequea '(6) el intento de v1 espera y entra' '{"ok": true' "$(grep '^R ' "$SALIDA/6b" | cut -c3-13)"
espero '(6) … el intento esperó al reparto' "$SALIDA/6b"
chequea '(6) … el contacto queda «trabajado» (el intento quedó DESPUÉS de asignado_en)' 'trabajado' \
  "$( { como "$S1"; echo "select x.estado from crm.contactos_de_base('$BX', 'todos') x where x.lead_id = '$X6';"; echo "commit;"; } | Q | tail -1)"
# (7) reactivar y repartir.
X7=$(L 2)   # de v1 desde (1), sin tocar
corre "$V1" "crm.reactivar_lead_base(gen_random_uuid(), '$X7', null)" 0 2 "$SALIDA/7a"
corre "$S1" "$(rep "$BX" "$(ind "$X7" "$V2")")" 0.5 0 "$SALIDA/7b"
wait
chequea '(7) reactivar (v1)' '{"ok": true' "$(grep '^R ' "$SALIDA/7a" | cut -c3-13)"
chequea '(7) reparto del lead que se reactiva → 55P03 al instante' 'Otra operación está usando alguno de esos contactos; reintenta' "$(ver "$SALIDA/7b")"
rapido '(7) … sin esperar' "$SALIDA/7b"
X7B=$(L 7)  # de v1 desde (4), sin tocar
corre "$S1" "$(rep "$BX" "$(ind "$X7B" "$V2")")" 0 2 "$SALIDA/7c"
corre "$V1" "crm.reactivar_lead_base(gen_random_uuid(), '$X7B', null)" 0.5 0 "$SALIDA/7d"
wait
chequea '(7) reparto primero (v1 → v2)' '1|v2:1|' "$(ver "$SALIDA/7c")"
chequea '(7) la reactivación de v1 espera y muere con P0002' 'Lead no encontrado o fuera de tu ambito' "$(ver "$SALIDA/7d")"
espero '(7) … la reactivación esperó al reparto' "$SALIDA/7d"
# (8) intento con el lead tomado y recoger.
X8=$(L 8)   # de v1 desde (4), sin tocar
corre "$V1" "crm.registrar_intento_base(gen_random_uuid(), '$X8', 'no_contesto', null, null)" 0 2 "$SALIDA/8a"
corre "$S1" "$(rec "$BX" "$V1")" 0.5 0 "$SALIDA/8b"
wait
# v1 tiene en X: 1 (tocado en 3), 2 (reactivado en 7: sigue suyo, no recogible), 3 (de 5), 5 (de 2), 8 (tomado), 9 (tocado en 6).
chequea '(8) recoger con el lead tomado: lo deja y recoge los sin tocar (3 y 5)' '2|4|0' "$(ver "$SALIDA/8b")"
rapido '(8) … recoger no esperó' "$SALIDA/8b"
chequea '(8) … 3 y 5 a la bandeja; 8 sigue con v1' 'b b v1' "$(echo $(duenio "$X5") $(duenio "$(L 5)") $(duenio "$X8"))"
# (9) doble clic: mismo id de operación a la vez.
OP9=$(Q -c "select gen_random_uuid()")
corre "$S1" "crm.repartir_base('$OP9', '$BX', '$(bq "$V2" 1)'::jsonb)" 0 2 "$SALIDA/9a"
corre "$S1" "crm.repartir_base('$OP9', '$BX', '$(bq "$V2" 1)'::jsonb)" 0.5 0 "$SALIDA/9b"
wait
chequea '(9) primer clic' '1|v2:1|' "$(ver "$SALIDA/9a")"
chequea '(9) el segundo clic recibe la MISMA respuesta' "$(grep '^R ' "$SALIDA/9a")" "$(grep '^R ' "$SALIDA/9b")"
espero '(9) … tras esperar al primero' "$SALIDA/9b"
chequea '(9) … un solo recibo' '1' "$(Q -c "select count(*) from crm.base_carga_operaciones where operacion_id = '$OP9'")"
# (10) REPEATABLE READ.
{ printf "begin isolation level repeatable read;\nselect set_config('request.jwt.claim.sub', '%s', true), set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true);\nset local role authenticated;\n" "$S1" "$S1"
  echo "select 'R ' || ($(rep "$BX" "$(bq "$V1" 1)"))::text;"; echo "commit;"; } | Q > "$SALIDA/10" 2>&1
chequea '(10) repartir en REPEATABLE READ → 0A000' 'Repartir requiere READ COMMITTED (aislamiento actual: repeatable read)' "$(ver "$SALIDA/10")"
# (11) vetar con el lead tomado por el reparto: con la identidad encendida el veto toma los leads de la persona NOWAIT (su
#      protocolo, F2.b): falla al instante con 40001 y reintenta; el reintento entra.
X11=$(L 12)  # sin repartir
corre "$S1" "$(rep "$BX" "$(ind "$X11" "$V1")")" 0 2 "$SALIDA/11a"
corre "$S1" "crm.marcar_no_contactar('$X11', 'B9 conc: no')" 0.5 0 "$SALIDA/11b"
wait
chequea '(11) reparto' '1|v1:1|' "$(ver "$SALIDA/11a")"
chequea '(11) el veto con el lead tomado → 40001 de su puerta (sin esperar, sin interbloqueo)' 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo' "$(ver "$SALIDA/11b")"
rapido '(11) … sin esperar' "$SALIDA/11b"
corre "$S1" "crm.marcar_no_contactar('$X11', 'B9 conc: no')" 0 0 "$SALIDA/11c"
wait
chequea '(11) el reintento del veto entra' '{"ok": true' "$(grep '^R ' "$SALIDA/11c" | cut -c3-13)"
chequea '(11) … queda no_contactar, repartido a v1' 'no_contactar|v1' "$( { como "$S1"; echo "select x.estado || '|' || case x.analista_id when '$V1' then 'v1' else '?' end from crm.contactos_de_base('$BX', 'todos') x where x.lead_id = '$X11';"; echo "commit;"; } | Q | tail -1)"
# (12) 5 rondas simultáneas: bloque en X, individual en X (puede chocar: 55P03), recoger en Y, intentos de v1, bloque en Y.
{ como "$S1"; echo "select crm.repartir_base(gen_random_uuid(), '$BY', '$(bq "$V2" 5)'::jsonb) is not null;"; echo "commit;"; } | Q >/dev/null
for ronda in 1 2 3 4 5; do
  LIBRE=$(Q -c "select bl.lead_id from crm.base_carga_leads bl where bl.base_id = '$BX' and bl.analista_id is null and bl.activo order by bl.creado_en desc limit 1")
  MIO=$(Q -c "select bl.lead_id from crm.base_carga_leads bl join crm.leads l on l.id = bl.lead_id where bl.base_id = '$BX' and bl.analista_id = '$V1' and l.vendedor_id = '$V1' and l.etapa = 'descartado' and not l.no_contactar and (l.enfriado_hasta is null or l.enfriado_hasta <= current_date) order by bl.lead_id limit 1")
  corre "$S1" "$(rep "$BX" "$(bq "$V2" 1)")" 0 0.3 "$SALIDA/12-$ronda-a"
  corre "$G" "$(rep "$BX" "$(ind "$LIBRE" "$V1")")" 0 0.3 "$SALIDA/12-$ronda-b"
  corre "$S1" "$(rec "$BY" "$V2")" 0 0.3 "$SALIDA/12-$ronda-c"
  corre "$V1" "crm.registrar_intento_base(gen_random_uuid(), '$MIO', 'no_contesto', null, null)" 0 0.3 "$SALIDA/12-$ronda-d"
  corre "$G" "$(rep "$BY" "$(bq "$V1" 1)")" 0 0.3 "$SALIDA/12-$ronda-e"
  wait
done
INTER=$(cat "$SALIDA"/12-* | grep -c '40P01\|deadlock detected')
RAROS=$(cat "$SALIDA"/12-* | grep 'ERROR:' | grep -v 'Hay otra operación en curso de esta base; reintenta\|Otra operación está usando alguno de esos contactos; reintenta\|Solo hay 0 contactos disponibles\|No insistir\|en descanso' | wc -l | tr -d ' ')
chequea '(12) 5 rondas: 0 interbloqueos' '0' "$INTER"
chequea '(12) … y ningún error fuera de los esperados (55P03 de la misma base, sin disponibles)' '0' "$RAROS"
echo "     (12) resultados: $(for f in "$SALIDA"/12-*; do ver "$f"; done | sort | uniq -c | tr '\n' ';' | tr -s ' ')"

# (13) el bloque bloquea solo lo que necesita.
BZ=$( { como "$S1"; echo "select crm.crear_base(gen_random_uuid(), 'B9 conc Z $RUN', 'archivo', null, 'z.csv')->>'base_id';"; echo "commit;"; } | Q | tail -1)
{ como "$S1"; echo "select crm.cargar_base_lote(gen_random_uuid(), '$BZ', '$(filas 201 210)'::jsonb) is not null;"; echo "commit;"; } | Q >/dev/null
Q -c "update crm.base_carga_leads bl set creado_en = now() - make_interval(mins => 1000 - right(l.telefono, 3)::int) from crm.leads l where l.id = bl.lead_id and bl.base_id = '$BZ'" >/dev/null
corre "$S1" "$(rep "$BZ" "$(bq "$V1" 2)")" 0 2 "$SALIDA/13a"
corre postgres "STMT:select 1 from crm.leads where id = '$(L 210)' for update nowait" 0.5 0 "$SALIDA/13b"
wait
chequea '(13) bloque de 2 en Z' '2|v1:2|' "$(ver "$SALIDA/13a")"
chequea '(13) … mientras tanto, el contacto 10 de Z (no lo necesitaba) se toma sin esperar (NOWAIT)' 'ok' "$(ver "$SALIDA/13b")"
rapido '(13) … al instante' "$SALIDA/13b"
# (14) recoger bloquea solo lo recogible: Z2 tocado por v1 (intento confirmado), Z1 sin tocar.
{ como "$V1"; echo "select crm.registrar_intento_base(gen_random_uuid(), '$(L 202)', 'no_contesto', null, null) is not null;"; echo "commit;"; } | Q >/dev/null
corre "$S1" "$(rec "$BZ" "$V1")" 0 2 "$SALIDA/14a"
corre postgres "STMT:select 1 from crm.leads where id = '$(L 202)' for update nowait" 0.5 0 "$SALIDA/14b"
wait
chequea '(14) recoger en Z: el sin tocar sí, el tocado no' '1|1|0' "$(ver "$SALIDA/14a")"
chequea '(14) … mientras tanto, el tocado (no recogible) se toma sin esperar (NOWAIT)' 'ok' "$(ver "$SALIDA/14b")"
rapido '(14) … al instante' "$SALIDA/14b"
# (15) base armada casi toda en descanso; el analista anterior trabaja otro contacto mientras se reparte.
Q -c "insert into crm.leads (nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
      select 'B9 conc W ' || g, '9${RUN}9' || lpad((300 + g)::text, 3, '0'), 'oficina', 'nuevo', '$V1', 1000, 'PEN', '$V1', true from generate_series(1, 30) g" >/dev/null
Q -c "update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes' where telefono like '+519${RUN}93%'" >/dev/null
IDSW=$(Q -c "select string_agg(id::text, ',' order by telefono) from crm.leads where telefono like '+519${RUN}93%'")
BW=$( { como "$S1"; echo "select crm.armar_base_crm(gen_random_uuid(), 'B9 conc W $RUN', null, '{$IDSW}'::uuid[])->>'base_id';"; echo "commit;"; } | Q | tail -1)
Q -c "update crm.base_carga_leads bl set creado_en = now() - make_interval(mins => 1000 - right(l.telefono, 3)::int) from crm.leads l where l.id = bl.lead_id and bl.base_id = '$BW'" >/dev/null
Q -c "update crm.leads set enfriado_hasta = current_date + 20 where telefono like '+519${RUN}93%' and right(telefono, 3)::int > 303" >/dev/null   # 27 de 30 en descanso
corre "$S1" "$(rep "$BW" "$(bq "$V2" 1)")" 0 2 "$SALIDA/15a"
corre "$V1" "crm.registrar_intento_base(gen_random_uuid(), '$(L 303)', 'no_contesto', null, null)" 0.5 0 "$SALIDA/15b"
wait
chequea '(15) bloque de 1 en W (27 de 30 en descanso)' '1|v2:1|en_descanso:27' "$(ver "$SALIDA/15a")"
chequea '(15) … el intento del analista anterior en otro elegible entra' '{"ok": true' "$(grep '^R ' "$SALIDA/15b" | cut -c3-13)"
rapido '(15) … sin esperar al reparto (latencia del intento)' "$SALIDA/15b"

# (16)–(17) la carrera de Codex r2: intentos confirmados entre la foto y los candados.
carrera() { # carrera <base> <cantidad> <archivo>: el reparto con su foto en pausa 4 s, luego retiene 3 s y se DESHACE
  ( { printf "begin;\ncreate temp table _pausa (x int);\n"
      printf "create or replace function private.bases_carga_reparto_motivo(p_activo boolean, p_en_ambito boolean, p_etapa text, p_no_contactar boolean, p_enfriado_hasta date, p_en_gestion boolean, p_hoy date) returns text language plpgsql set search_path = '' as \$f\$ begin if not exists (select 1 from pg_temp._pausa) then insert into pg_temp._pausa values (1); perform pg_catalog.pg_sleep(4); end if; return case when p_activo is not true then 'inactivo' when p_en_ambito is not true then 'fuera_de_ambito' when p_etapa is distinct from 'descartado' then 'no_descartado' when p_no_contactar is not false then 'no_contactar' when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso' when p_en_gestion is true then 'en_gestion' end; end \$f\$;\n"
      printf "select set_config('request.jwt.claim.sub', '%s', true), set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true);\nset local role authenticated;\n" "$S1" "$S1"
      echo "select 'R ' || ($(rep "$1" "$(bq "$V1" "$2")"))::text;"; echo "select pg_sleep(3);"; echo "rollback;"; } | Q > "$3" 2>&1; echo "rc=$?" >> "$3" ) &
}
intentos() { # intentos <archivo> <n1> <n2>: S1 registra intentos (confirmados uno a uno) en los contactos n1..n2
  ( sleep 0.5; for n in $(seq "$2" "$3"); do echo "begin; select set_config('request.jwt.claim.sub', '$S1', true), set_config('request.jwt.claims', '{\"sub\":\"$S1\",\"role\":\"authenticated\"}', true); set local role authenticated; select crm.registrar_intento_base(gen_random_uuid(), '$(L "$n")', 'no_contesto', null, null) is not null; commit;"; done | Q > "$1" 2>&1; echo "rc=$?" >> "$1" ) &
}
BR1=$( { como "$S1"; echo "select crm.crear_base(gen_random_uuid(), 'B9 conc R1 $RUN', 'archivo', null, 'r1.csv')->>'base_id';"; echo "commit;"; } | Q | tail -1)
{ como "$S1"; echo "select crm.cargar_base_lote(gen_random_uuid(), '$BR1', '$(filas 401 410)'::jsonb) is not null;"; echo "commit;"; } | Q >/dev/null
Q -c "update crm.base_carga_leads bl set creado_en = now() - make_interval(mins => 1000 - right(l.telefono, 3)::int) from crm.leads l where l.id = bl.lead_id and bl.base_id = '$BR1'" >/dev/null
carrera "$BR1" 2 "$SALIDA/16a"
intentos "$SALIDA/16b" 401 405
( sleep 5.5; Q -c "begin; select (select count(*) from crm.base_carga_leads where base_id = '$BR1') - (select count(*) from (select l.id from crm.leads l where l.id in (select lead_id from crm.base_carga_leads where base_id = '$BR1') for update skip locked) z); rollback;" > "$SALIDA/16c" 2>&1 ) &
wait
chequea '(16) los 5 intentos se confirmaron en la ventana de la foto' 'rc=0' "$(tail -1 "$SALIDA/16b")"
chequea '(16) bloque de 2 con 5 que caen bajo candado → reparte 2, «ocupado» 5' '2|v1:2|ocupado:5' "$(ver "$SALIDA/16a")"
chequea '(16) candados retenidos por el reparto (sondeo SKIP LOCKED de otra sesión): 7 = 5 rechazados + 2 movidos' '7' "$(grep -E '^[0-9]+$' "$SALIDA/16c" | head -1)"
BR2=$( { como "$S1"; echo "select crm.crear_base(gen_random_uuid(), 'B9 conc R2 $RUN', 'archivo', null, 'r2.csv')->>'base_id';"; echo "commit;"; } | Q | tail -1)
{ como "$S1"; echo "select crm.cargar_base_lote(gen_random_uuid(), '$BR2', '$(filas 501 570)'::jsonb) is not null;"; echo "commit;"; } | Q >/dev/null
Q -c "update crm.base_carga_leads bl set creado_en = now() - make_interval(mins => 1000 - right(l.telefono, 3)::int) from crm.leads l where l.id = bl.lead_id and bl.base_id = '$BR2'" >/dev/null
carrera "$BR2" 1 "$SALIDA/17a"
intentos "$SALIDA/17b" 501 560
wait
chequea '(17) los 60 intentos se confirmaron en la ventana de la foto' 'rc=0' "$(tail -1 "$SALIDA/17b")"
chequea '(17) bloque de 1 con 60 que caen bajo candado → presupuesto (51) agotado → 55P03, nada repartido' 'Los contactos están cambiando; reintenta|0' \
  "$(ver "$SALIDA/17a")|$(Q -c "select count(*) from crm.base_carga_leads where base_id = '$BR2' and analista_id is not null")"

# Invariantes finales de la corrida.
DOBLES=$(Q -c "select count(*) from crm.base_carga_leads bl join crm.leads l on l.id = bl.lead_id
                where bl.base_id in ('$BX', '$BY', '$BZ', '$BW', '$BR1', '$BR2') and bl.activo and bl.analista_id is not null and l.vendedor_id is distinct from bl.analista_id")
chequea 'INVARIANTE ninguna pertenencia repartida a un analista distinto del que tiene el lead' '0' "$DOBLES"
chequea 'INVARIANTE pertenencias coherentes (analista, cuándo y quién a la vez)' '0' "$(Q -c "select count(*) from crm.base_carga_leads bl where bl.base_id in ('$BX', '$BY', '$BZ', '$BW', '$BR1', '$BR2') and ((bl.analista_id is null) <> (bl.asignado_en is null) or (bl.analista_id is null) <> (bl.asignado_por is null))")"
chequea 'INVARIANTE ninguno con analista y bandeja a la vez; ninguno sin dueño' '0' "$(Q -c "select count(*) from crm.leads l join crm.base_carga_leads bl on bl.lead_id = l.id where bl.base_id in ('$BX', '$BY', '$BZ', '$BW', '$BR1', '$BR2') and ((l.vendedor_id is not null and l.asignado_supervisor_id is not null) or (l.vendedor_id is null and l.asignado_supervisor_id is null))")"
chequea 'INVARIANTE ningún ciclo SLA ni episodio en los contactos de archivo que siguen descartados' '0' "$(Q -c "select count(*) from crm.base_carga_leads bl join crm.leads l on l.id = bl.lead_id where bl.base_id in ('$BX', '$BY', '$BZ', '$BW', '$BR1', '$BR2') and l.etapa = 'descartado' and l.origen = 'base_cargada' and (exists (select 1 from crm.lead_sla_ciclos s where s.lead_id = l.id) or exists (select 1 from crm.lead_asignaciones a where a.lead_id = l.id))")"
chequea 'INVARIANTE 0 interbloqueos en toda la corrida' '0' "$(cat "$SALIDA"/* | grep -c '40P01\|deadlock detected')"
echo "=== B9 concurrencia: $([ "$FALLOS" -eq 0 ] && echo 'todo PASS' || echo "$FALLOS FAIL") ==="
[ "$FALLOS" -eq 0 ]
