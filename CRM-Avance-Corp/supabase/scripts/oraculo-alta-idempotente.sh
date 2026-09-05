#!/usr/bin/env bash
# ORÁCULO «el alta de contrato es idempotente por clave» (migración 20260905190000) — SOLO en el BANCO.
# Reproduce el incidente del 05/09/2026 (dos contratos idénticos por un reintento con el número cambiado)
# por la puerta VIVA crm.crear_contrato_con_cuenta_pdf_v2 con el ROL SQL authenticated (prueba también grants).
# Corrido ANTES de aplicar la migración, las secciones A, B, D, G, H, J, K y L deben salir ROJAS (es el mutante
# que prueba que el ensayo mide el hueco); DESPUÉS, todo VERDE. La sección L ensaya además la puerta oficial de
# eliminación como postgres con un admin efímero: el mismo camino que scripts/remediacion-duplicado-2026-01-000253.sql.
# Uso: S=/ruta/scratchpad ./oraculo-alta-idempotente.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
# Deja el banco como estaba en lo global (banderas multiempresa restauradas); los fixtures son por RUN.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
PA="f3a00000-0000-0000-0000-${RUN}000001"
W="f3b00000-0000-0000-0000-${RUN}000009"      # vendedor efímero de esta corrida (para revocarlo sin tocar a V)
PB="f3a00000-0000-0000-0000-${RUN}000002"     # cliente efímero cuyo ASESOR es W (la reserva PDF exige cartera)
ADM="f3c00000-0000-0000-0000-${RUN}000001"    # admin efímero: la puerta oficial de eliminación exige es_admin()
CCI="002${RUN}00000000000"     # 20 dígitos
H_NUEVO='1876ea59e10d48743390fb2059267d23'; H_PROD='68cc6c91e84061c0bdf6a62306085c14'
ROJO=0
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR"; }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
for k in sys.argv[2].split('.'):
    d=d.get(k) if isinstance(d,dict) else None
print('' if d is None else (json.dumps(d) if isinstance(d,(dict,list)) else d))" "$1" "$2" 2>/dev/null; }
# alta <actor> <clave|''> <numero> [capital=20000] [cliente=PA]
alta() {
  local clave=""; [[ -n "$2" ]] && clave=", 'clave_idempotencia', '$2'"
  local cap="${4:-20000}"; local cli="${5:-$PA}"
  run_as "$1" "select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object('cliente_id','$cli','numero_contrato','$3','capital',$cap,'moneda','PEN','tasa_anual',15,
      'modalidad','mensual','tipo_interes','simple','categoria','nuevo','fecha_inicio','2026-03-11','fecha_vencimiento','2027-03-11',
      'notas_internas','oraculo alta idempotente r$RUN' $clave),
    jsonb_build_array(
      jsonb_build_object('numero_cuota',1,'fecha_programada','2026-04-11','monto_programado',250,'tipo','cuota'),
      jsonb_build_object('numero_cuota',2,'fecha_programada','2027-03-11','monto_programado',$cap,'tipo','retorno')),
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','IDEM$RUN','cci','$CCI',
      'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null))"
}
n_contratos() { q "select count(*) from public.contratos where numero_contrato in ($1)"; }
n_memoria()   { q "select count(*) from private.contrato_altas_idempotentes where actor_id='$1' and clave='$2'"; }

echo "== Preflight (RUN=$RUN) =="
FLAG_RP="$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")"
FLAG_IE="$(q "select activo from crm.multiempresa_flags where nombre='inversiones_escritura'")"
restaurar_flags() { psql "$PG" -q -c "update crm.multiempresa_flags set activo='${FLAG_RP:-f}' where nombre='resolver_en_puertas'; update crm.multiempresa_flags set activo='${FLAG_IE:-f}' where nombre='inversiones_escritura';" >/dev/null; }
trap restaurar_flags EXIT
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select count(*) from public.perfiles where id='$PA' and rol='cliente' and activo")" == "1" ]] && ok "fixture: cliente PA activo con asesor V" || rojo "fixture PA"
# Vendedor efímero W (perfil comercial + miembro vendedor del equipo bajo SUP): se revoca en K sin tocar a V.
psql "$PG" -q -c "insert into auth.users (id) values ('$W') on conflict (id) do nothing;" >/dev/null 2>&1
sys "insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$W','IDEM VENDEDOR r$RUN','comercial','DNI','8${RUN}9') on conflict (id) do update set activo = true;
     insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por) values ('$W','vendedor','$SUP',true,'$SUP') on conflict (perfil_id) do update set activo = true, rol_crm='vendedor';"
[[ "$(q "select count(*) from crm.equipo where perfil_id='$W' and activo")" == "1" ]] && ok "fixture: vendedor efímero W activo" || rojo "fixture W"
psql "$PG" -q -c "insert into auth.users (id) values ('$PB'), ('$ADM') on conflict (id) do nothing;" >/dev/null 2>&1
sys "insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, asesor_perfil_id) values ('$PB','IDEM CLIENTE DE W r$RUN','cliente','DNI','7${RUN}2','$W') on conflict (id) do nothing;
     insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$ADM','IDEM ADMIN r$RUN','admin','DNI','8${RUN}1') on conflict (id) do update set activo = true;"
[[ "$(q "select count(*) from public.perfiles where id='$PB' and rol='cliente' and activo and asesor_perfil_id='$W'")" == "1" ]] && ok "fixture: cliente PB con asesor W" || rojo "fixture PB"
[[ "$(q "select count(*) from public.perfiles where id='$ADM' and rol='admin' and activo")" == "1" ]] && ok "fixture: admin efímero ADM" || rojo "fixture ADM"
H="$(q "select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='crear_contrato_con_cuenta_pdf_v2'")"
case "$H" in
  "$H_NUEVO") echo "  puerta = texto de la migración 20260905190000 (todo debe salir VERDE)";;
  "$H_PROD")  echo "  puerta = texto VIVO de producción, SIN idempotencia (A, B, D, G, H, J, K y L deben salir ROJAS: mutante)";;
  *) echo "  ⚠️ puerta con md5 desconocido: $H";;
esac
psql "$PG" -q -c "update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');" >/dev/null

echo "== A) EL INCIDENTE: misma clave, el analista cambia el NÚMERO y reintenta =="
K1="$(uuid)"; NA1="IDEM-$RUN-A1"; NA2="IDEM-$RUN-A2"
O1="$(alta "$V" "$K1" "$NA1")"; A1="$(j "$O1" id)"
[[ -n "$A1" ]] && ok "primer alta creada ($NA1 → ${A1:0:8}…)" || rojo "primer alta no se creó: $O1"
O2="$(alta "$V" "$K1" "$NA2")"
echo "$O2" | grep -q "ya creó el contrato $NA1 con otros datos" && ok "el reintento con el número cambiado NO crea otro: P0409 nombra el contrato ya creado ($NA1)" || rojo "el reintento con otro número no fue rechazado con el número: ${O2:0:200}"
echo "$O2" | grep -q "P0409" && ok "código P0409" || rojo "sin P0409"
[[ "$(n_contratos "'$NA1','$NA2'")" == "1" ]] && ok "hay UN solo contrato para el cliente en este intento" || rojo "hay $(n_contratos "'$NA1','$NA2'") contratos: el duplicado del 05/09"

echo "== B) misma clave y MISMOS datos (el reintento «ingenuo» o el timeout) =="
O3="$(alta "$V" "$K1" "$NA1")"
[[ "$(j "$O3" id)" == "$A1" ]] && ok "devuelve el mismo contrato (antes: 400 «El N de contrato ya existe»)" || rojo "no devolvió el mismo contrato: ${O3:0:160}"
[[ "$(j "$O3" idempotente)" == "True" || "$(j "$O3" idempotente)" == "true" ]] && ok "la respuesta repetida lleva idempotente=true" || rojo "sin marca idempotente en el replay"
[[ "$(j "$O3" numero_contrato)" == "$NA1" ]] && ok "con el número del alta registrada" || rojo "número inesperado: $(j "$O3" numero_contrato)"

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

echo "== G) la memoria: fila por (actor, clave), huella y replay con el estado documental de HOY =="
[[ "$(n_memoria "$V" "$K1")" == "1" ]] && ok "una fila de memoria para (V, K1) → ${A1:0:8}…" || rojo "memoria ausente o repetida para (V,K1): $(n_memoria "$V" "$K1")"
[[ "$(q "select contrato_id from private.contrato_altas_idempotentes where actor_id='$V' and clave='$K1'")" == "$A1" ]] && ok "la fila apunta al contrato del primer alta" || rojo "la fila apunta a otro contrato"
[[ "$(q "select huella ~ '^[0-9a-f]{32}$' from private.contrato_altas_idempotentes where actor_id='$V' and clave='$K1'")" == "t" ]] && ok "la fila guarda la huella md5 de lo pedido" || rojo "sin huella"
[[ "$(j "$O3" pdf.estado)" == "sin_reserva" && "$(j "$O3" pdf.contrato_id)" == "$A1" ]] && ok "el replay devuelve el pdf del contrato A1 recalculado (sin_reserva)" || rojo "pdf del replay inesperado: $(j "$O3" pdf)"
[[ "$(j "$O3" cuenta_bancaria_id)" != "" && "$(j "$O3" cuenta_bancaria_id)" == "$(j "$O1" cuenta_bancaria_id)" ]] && ok "misma cuenta de pago en el replay" || rojo "cuenta distinta en el replay"

echo "== H) concurrencia: dos envíos simultáneos con la misma clave y los mismos datos =="
K7="$(uuid)"; NH="IDEM-$RUN-H"
alta "$V" "$K7" "$NH" > "$S/idem-h1.out" 2>&1 &
alta "$V" "$K7" "$NH" > "$S/idem-h2.out" 2>&1 &
wait
H1="$(j "$(cat "$S/idem-h1.out")" id)"; H2="$(j "$(cat "$S/idem-h2.out")" id)"
[[ -n "$H1" && "$H1" == "$H2" ]] && ok "los dos envíos devuelven el MISMO contrato (${H1:0:8}…)" || rojo "concurrencia: h1=${H1:0:8} h2=${H2:0:8} · $(head -c 120 "$S/idem-h1.out") · $(head -c 120 "$S/idem-h2.out")"
[[ "$(n_contratos "'$NH'")" == "1" ]] && ok "un solo contrato $NH" || rojo "$(n_contratos "'$NH'") contratos $NH"

echo "== J) misma clave, mismo número, OTRO capital (el analista editó tras un alta que sí se creó) =="
O9="$(alta "$V" "$K1" "$NA1" 25000)"
echo "$O9" | grep -q "ya creó el contrato $NA1 con otros datos" && ok "P0409 con el número del contrato ya creado; ni replay ni alta nueva" || rojo "no rechazó el cambio de datos: ${O9:0:200}"
[[ "$(q "select capital from public.contratos where id='$A1'")" == "20000.00" ]] && ok "el contrato A1 conserva sus datos (20 000)" || rojo "A1 cambió: $(q "select capital from public.contratos where id='$A1'")"
[[ "$(n_contratos "'$NA1'")" == "1" ]] && ok "sigue habiendo un solo $NA1" || rojo "se creó otro $NA1"

echo "== K) el replay pasa por la autorización VIGENTE: vendedor revocado no recupera nada =="
KW="$(uuid)"; NK="IDEM-$RUN-K"
O10="$(alta "$W" "$KW" "$NK" 20000 "$PB")"; W1="$(j "$O10" id)"
[[ -n "$W1" ]] && ok "W (activo, asesor de PB) crea $NK → ${W1:0:8}…" || rojo "W no pudo crear: ${O10:0:160}"
# Revocar a W pasa por trg_equipo_validar_usuarios_jerarquia, que exige a SU supervisor activo: si otro oráculo del
# banco compartido dejó a SUP inactivo en este instante, se reactiva antes (es un actor F3 sembrado, no un dato global).
sys "update crm.equipo set activo=true where perfil_id='$SUP' and not activo"
sys "update crm.equipo set activo=false where perfil_id='$W'"
[[ "$(q "select activo from crm.equipo where perfil_id='$W'")" == "f" ]] || rojo "no se pudo revocar a W (¿SUP inactivo por otro oráculo?)"
O11="$(alta "$W" "$KW" "$NK" 20000 "$PB")"
echo "$O11" | grep -qE "42501|fuera de tu cartera|No autorizado|permission" && ok "W revocado: el replay se rechaza (42501), no devuelve el contrato" || rojo "W revocado recuperó el alta: ${O11:0:160}"
[[ "$(n_contratos "'$NK'")" == "1" ]] && ok "y tampoco creó otro" || rojo "W revocado creó otro $NK"
sys "update crm.equipo set activo=true where perfil_id='$W'"
O12="$(alta "$W" "$KW" "$NK" 20000 "$PB")"
[[ "$(j "$O12" id)" == "$W1" ]] && ok "W reactivado vuelve a recibir el mismo contrato" || rojo "W reactivado no recuperó: ${O12:0:160}"

echo "== L) lápida: el contrato de un intento fue eliminado; el replay NO lo recrea =="
KL="$(uuid)"; NL="IDEM-$RUN-L"
O13="$(alta "$V" "$KL" "$NL")"; L1="$(j "$O13" id)"
[[ -n "$L1" ]] && ok "alta $NL → ${L1:0:8}…" || rojo "alta L no se creó: ${O13:0:160}"
# Borrar SOLO por la puerta oficial (un DELETE directo lo frena el trigger del cronograma con P0002):
# preparar (autoriza como ADM, manifiesto de archivos) + finalizar, como postgres — el mismo camino
# que el SQL de remediación del duplicado real.
PREP="$(psql "$PG" -qtA -c "select crm.contrato_eliminacion_preparar('$L1','$ADM')" 2>&1)"; TOK="$(j "$PREP" token)"
[[ -n "$TOK" && "$(j "$PREP" objetos)" == "[]" ]] && ok "puerta oficial: preparación autorizada para ADM, sin archivos que borrar" || rojo "preparación falló: ${PREP:0:160}"
FIN="$(psql "$PG" -qtA -c "select crm.contrato_eliminacion_finalizar('$L1','$TOK','$ADM')" 2>&1)"
[[ "$(j "$FIN" ok)" == "True" || "$(j "$FIN" ok)" == "true" ]] && ok "puerta oficial: contrato eliminado (cascada cronograma/cuenta, auditoría)" || rojo "finalización falló: ${FIN:0:160}"
[[ "$(q "select contrato_id is null from private.contrato_altas_idempotentes where actor_id='$V' and clave='$KL'")" == "t" ]] && ok "la memoria queda como lápida (contrato_id NULL) tras borrar el contrato" || rojo "la memoria no quedó como lápida: $(q "select contrato_id from private.contrato_altas_idempotentes where actor_id='$V' and clave='$KL'")"
O14="$(alta "$V" "$KL" "$NL")"
echo "$O14" | grep -q "fue eliminado después" && ok "el replay recibe P0409 «eliminado», no recrea" || rojo "el replay tras el borrado no avisó: ${O14:0:160}"
[[ "$(n_contratos "'$NL'")" == "0" ]] && ok "no existe ningún $NL (no se recreó)" || rojo "se recreó $NL"

echo "== I) higiene: tabla privada cerrada, puerta con los mismos grants y dueño =="
[[ "$(q "select relrowsecurity and relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname='contrato_altas_idempotentes'")" == "t" ]] && ok "RLS forzada en private.contrato_altas_idempotentes" || rojo "tabla sin RLS forzada (o inexistente)"
[[ "$(q "select count(*) from information_schema.role_table_grants where table_schema='private' and table_name='contrato_altas_idempotentes' and grantee in ('anon','authenticated','service_role','PUBLIC')")" == "0" ]] && ok "sin grants para la API" || rojo "grants de API en la tabla"
[[ "$(q "select proacl::text from pg_proc where oid='crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure")" == "{postgres=X/postgres,authenticated=X/postgres}" ]] && ok "ACL de la puerta intacta ({postgres,authenticated})" || rojo "ACL cambió: $(q "select proacl::text from pg_proc where oid='crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure")"
[[ "$(q "select p.proowner::regrole::text || '|' || p.prosecdef || '|' || array_to_string(p.proconfig,',') from pg_proc p where p.oid='crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure")" == 'postgres|true|search_path=""' ]] && ok "dueño postgres, DEFINER, search_path vacío" || rojo "dueño/definer/search_path cambiaron"
O8="$(run_as "$V" "select count(*) from private.contrato_altas_idempotentes")"
echo "$O8" | grep -qiE "permission denied|42501" && ok "authenticated no lee la memoria directamente" || rojo "authenticated pudo leer la memoria: ${O8:0:120}"

echo
[[ "$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")" == "${FLAG_RP:-f}" ]] || echo "  (las banderas se restauran al salir)"
if [[ $ROJO -eq 0 ]]; then echo "ORÁCULO ALTA IDEMPOTENTE: TODO VERDE (RUN=$RUN)"; else echo "ORÁCULO ALTA IDEMPOTENTE: $ROJO ROJO(S) (RUN=$RUN)" >&2; fi
exit $ROJO
