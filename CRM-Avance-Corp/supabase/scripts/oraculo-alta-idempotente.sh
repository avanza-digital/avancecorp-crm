#!/usr/bin/env bash
# ORÁCULO «el alta de contrato es idempotente por clave» (migración 20260905190000) — SOLO en el BANCO.
# Reproduce el incidente del 05/09/2026 (dos contratos idénticos por un reintento con el número cambiado)
# por la puerta VIVA crm.crear_contrato_con_cuenta_pdf_v2 con el ROL SQL authenticated (prueba también grants).
# Corrido ANTES de aplicar la migración, las secciones A, B, D, G y H deben salir ROJAS (es el mutante que
# prueba que el ensayo mide el hueco); DESPUÉS, todo VERDE.
# Uso: S=/ruta/scratchpad ./oraculo-alta-idempotente.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
PA="f3a00000-0000-0000-0000-${RUN}000001"
CCI="002${RUN}00000000000"     # 20 dígitos
ROJO=0
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
for k in sys.argv[2].split('.'):
    d=d.get(k) if isinstance(d,dict) else None
print('' if d is None else (json.dumps(d) if isinstance(d,(dict,list)) else d))" "$1" "$2" 2>/dev/null; }
# alta <actor> <clave|''> <numero> [fecha_inicio]
alta() {
  local clave=""; [[ -n "$2" ]] && clave=", 'clave_idempotencia', '$2'"
  local fi="${4:-2026-03-11}"
  run_as "$1" "select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object('cliente_id','$PA','numero_contrato','$3','capital',20000,'moneda','PEN','tasa_anual',15,
      'modalidad','mensual','tipo_interes','simple','categoria','nuevo','fecha_inicio','$fi','fecha_vencimiento','2027-03-11',
      'notas_internas','oraculo alta idempotente r$RUN' $clave),
    jsonb_build_array(
      jsonb_build_object('numero_cuota',1,'fecha_programada','2026-04-11','monto_programado',250,'tipo','cuota'),
      jsonb_build_object('numero_cuota',2,'fecha_programada','2027-03-11','monto_programado',20000,'tipo','retorno')),
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','IDEM$RUN','cci','$CCI',
      'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null))"
}
n_contratos() { q "select count(*) from public.contratos where numero_contrato in ($1)"; }
n_memoria()   { q "select count(*) from private.contrato_altas_idempotentes where actor_id='$1' and clave='$2'"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select count(*) from public.perfiles where id='$PA' and rol='cliente' and activo")" == "1" ]] && ok "fixture: cliente PA activo con asesor V" || rojo "fixture PA"
H="$(q "select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='crear_contrato_con_cuenta_pdf_v2'")"
case "$H" in
  079d047f00d6355929615b1c49060b47) echo "  puerta = texto de la migración 20260905190000 (todo debe salir VERDE)";;
  68cc6c91e84061c0bdf6a62306085c14) echo "  puerta = texto VIVO de producción, SIN idempotencia (A, B, D, G y H deben salir ROJAS: mutante)";;
  *) echo "  ⚠️ puerta con md5 desconocido: $H";;
esac
psql "$PG" -q -c "update crm.multiempresa_flags set activo=false, actualizado_en=now() where nombre in ('resolver_en_puertas','inversiones_escritura');" >/dev/null

echo "== A) EL INCIDENTE: misma clave, el analista cambia el número y reintenta =="
K1="$(uuid)"; NA1="IDEM-$RUN-A1"; NA2="IDEM-$RUN-A2"
O1="$(alta "$V" "$K1" "$NA1")"; A1="$(j "$O1" id)"
[[ -n "$A1" ]] && ok "primer alta creada ($NA1 → ${A1:0:8}…)" || rojo "primer alta no se creó: $O1"
O2="$(alta "$V" "$K1" "$NA2")"; A2="$(j "$O2" id)"
[[ -n "$A2" && "$A2" == "$A1" ]] && ok "el reintento con el número cambiado devuelve el MISMO contrato" || rojo "el reintento creó/devolvió otro contrato (${A2:0:8}…) o falló: ${O2:0:160}"
[[ "$(j "$O2" idempotente)" == "True" || "$(j "$O2" idempotente)" == "true" ]] && ok "la respuesta repetida lleva idempotente=true" || rojo "sin marca idempotente en el replay"
[[ "$(j "$O2" numero_contrato)" == "$NA1" ]] && ok "el número que manda es el del alta registrada ($NA1), no el tecleado después" || rojo "número inesperado en el replay: $(j "$O2" numero_contrato)"
[[ "$(n_contratos "'$NA1','$NA2'")" == "1" ]] && ok "hay UN solo contrato para el cliente en este intento" || rojo "hay $(n_contratos "'$NA1','$NA2'") contratos: el duplicado del 05/09"

echo "== B) misma clave y mismo número (el reintento «ingenuo») =="
O3="$(alta "$V" "$K1" "$NA1")"
[[ "$(j "$O3" id)" == "$A1" ]] && ok "devuelve el mismo contrato (antes: 400 «El N de contrato ya existe»)" || rojo "no devolvió el mismo contrato: ${O3:0:160}"

echo "== C) clave DISTINTA = alta distinta =="
K2="$(uuid)"; NC="IDEM-$RUN-C"
O4="$(alta "$V" "$K2" "$NC")"; C1="$(j "$O4" id)"
[[ -n "$C1" && "$C1" != "$A1" ]] && ok "otra clave crea otro contrato" || rojo "otra clave no creó otro contrato: ${O4:0:160}"
[[ -z "$(j "$O4" idempotente)" ]] && ok "un alta nueva NO lleva la marca idempotente" || rojo "alta nueva marcada como idempotente"

echo "== D) clave inválida: 22023 y nada escrito =="
ND="IDEM-$RUN-D"
O5="$(alta "$V" "no-es-un-uuid" "$ND")"
echo "$O5" | grep -qE "22023|no es válida" && ok "rechazo 22023 «clave de idempotencia … no es válida»" || rojo "no rechazó la clave inválida: ${O5:0:160}"
[[ "$(n_contratos "'$ND'")" == "0" ]] && ok "no se escribió ningún contrato" || rojo "se creó contrato con clave inválida"

echo "== E) sin clave: comportamiento de hoy, byte a byte =="
NE="IDEM-$RUN-E"
O6="$(alta "$V" "" "$NE")"; E1="$(j "$O6" id)"
[[ -n "$E1" ]] && ok "el alta sin clave se crea" || rojo "alta sin clave falló: ${O6:0:160}"
[[ -z "$(j "$O6" idempotente)" ]] && ok "sin marca idempotente" || rojo "marca idempotente sin clave"
[[ "$(j "$O6" pdf.estado)" == "sin_reserva" && "$(j "$O6" pdf.job_id)" == "" ]] && ok "régimen anterior: pdf.estado=sin_reserva, job_id=null (la forma que el front rechazaba)" || rojo "forma del pdf inesperada: $(j "$O6" pdf)"
[[ "$(q "select count(*) from private.contrato_altas_idempotentes where contrato_id='$E1'" 2>/dev/null || echo 0)" == "0" ]] && ok "sin clave no hay fila de memoria" || rojo "fila de memoria sin clave"

echo "== F) otro actor con la MISMA clave no recibe el alta ajena =="
NF="IDEM-$RUN-F"
O7="$(alta "$G" "$K1" "$NF")"; F1="$(j "$O7" id)"
[[ "$F1" != "$A1" ]] && ok "Gerencia con K1 no obtiene el contrato de V ($( [[ -n "$F1" ]] && echo "creó el suyo ${F1:0:8}…" || echo "rechazado: ${O7:0:80}"))" || rojo "otro actor recuperó el alta ajena"

echo "== G) la memoria: fila por (actor, clave) y replay con el estado documental de HOY =="
[[ "$(n_memoria "$V" "$K1")" == "1" ]] && ok "una fila de memoria para (V, K1) → ${A1:0:8}…" || rojo "memoria ausente o repetida para (V,K1): $(n_memoria "$V" "$K1")"
[[ "$(q "select contrato_id from private.contrato_altas_idempotentes where actor_id='$V' and clave='$K1'")" == "$A1" ]] && ok "la fila apunta al contrato del primer alta" || rojo "la fila apunta a otro contrato"
[[ "$(j "$O3" pdf.estado)" == "sin_reserva" && "$(j "$O3" pdf.contrato_id)" == "$A1" ]] && ok "el replay devuelve el pdf del contrato A1 recalculado (sin_reserva)" || rojo "pdf del replay inesperado: $(j "$O3" pdf)"
[[ "$(j "$O3" cuenta_bancaria_id)" != "" && "$(j "$O3" cuenta_bancaria_id)" == "$(j "$O1" cuenta_bancaria_id)" ]] && ok "misma cuenta de pago en el replay" || rojo "cuenta distinta en el replay"

echo "== H) concurrencia: dos envíos simultáneos con la misma clave y el mismo número =="
K7="$(uuid)"; NH="IDEM-$RUN-H"
alta "$V" "$K7" "$NH" > "$S/idem-h1.out" 2>&1 &
alta "$V" "$K7" "$NH" > "$S/idem-h2.out" 2>&1 &
wait
H1="$(j "$(cat "$S/idem-h1.out")" id)"; H2="$(j "$(cat "$S/idem-h2.out")" id)"
[[ -n "$H1" && "$H1" == "$H2" ]] && ok "los dos envíos devuelven el MISMO contrato (${H1:0:8}…)" || rojo "concurrencia: h1=${H1:0:8} h2=${H2:0:8} · $(head -c 120 "$S/idem-h1.out") · $(head -c 120 "$S/idem-h2.out")"
[[ "$(n_contratos "'$NH'")" == "1" ]] && ok "un solo contrato $NH" || rojo "$(n_contratos "'$NH'") contratos $NH"

echo "== I) higiene: tabla privada cerrada, puerta con los mismos grants y dueño =="
[[ "$(q "select relrowsecurity and relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname='contrato_altas_idempotentes'")" == "t" ]] && ok "RLS forzada en private.contrato_altas_idempotentes" || rojo "tabla sin RLS forzada (o inexistente)"
[[ "$(q "select count(*) from information_schema.role_table_grants where table_schema='private' and table_name='contrato_altas_idempotentes' and grantee in ('anon','authenticated','service_role','PUBLIC')")" == "0" ]] && ok "sin grants para la API" || rojo "grants de API en la tabla"
[[ "$(q "select proacl::text from pg_proc where oid='crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure")" == "{postgres=X/postgres,authenticated=X/postgres}" ]] && ok "ACL de la puerta intacta ({postgres,authenticated})" || rojo "ACL cambió: $(q "select proacl::text from pg_proc where oid='crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure")"
[[ "$(q "select p.proowner::regrole::text || '|' || p.prosecdef || '|' || array_to_string(p.proconfig,',') from pg_proc p where p.oid='crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure")" == 'postgres|true|search_path=""' ]] && ok "dueño postgres, DEFINER, search_path vacío" || rojo "dueño/definer/search_path cambiaron"
O8="$(run_as "$V" "select count(*) from private.contrato_altas_idempotentes")"
echo "$O8" | grep -qiE "permission denied|42501" && ok "authenticated no lee la memoria directamente" || rojo "authenticated pudo leer la memoria: ${O8:0:120}"

echo
if [[ $ROJO -eq 0 ]]; then echo "ORÁCULO ALTA IDEMPOTENTE: TODO VERDE (RUN=$RUN)"; else echo "ORÁCULO ALTA IDEMPOTENTE: $ROJO ROJO(S) (RUN=$RUN)" >&2; fi
exit $ROJO
