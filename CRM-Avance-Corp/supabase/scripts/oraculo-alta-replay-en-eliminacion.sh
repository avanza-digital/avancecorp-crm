#!/usr/bin/env bash
# ORÁCULO «el replay del alta no devuelve un contrato en eliminación» (migración 20260905234500, m3) — SOLO en el BANCO.
# A reproduce el hueco: alta con clave K, Gerencia PREPARA la eliminación (la edge aún no finalizó) y el analista
# reintenta con K. Con el texto VIVO (v2.1) el replay devuelve el contrato como «alta recuperada» (idempotente=true):
# ROJO = mutante. Con la migración responde 55000 «en proceso de eliminación», como el alta. Luego se finaliza el
# borrado y el replay debe seguir siendo lápida (P0409 ALTA_ELIMINADA). B: el replay normal sigue igual. C: higiene.
# Uso: S=/ruta/scratchpad ./oraculo-alta-replay-en-eliminacion.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
V='f3000000-0000-0000-0000-000000000001'
PA="f3a00000-0000-0000-0000-${RUN}000001"
ADM="f3c00000-0000-0000-0000-${RUN}000001"
CCI="002${RUN}00000000000"
SIG="crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)"
H_PROD="$(awk '/functiondef PROD/ {print $4}' "$AQUI/idempotencia-m3/huellas-generadas.txt" 2>/dev/null)"
H_NUEVO="$(awk '/functiondef NUEVO/ {print $4}' "$AQUI/idempotencia-m3/huellas-generadas.txt" 2>/dev/null)"
ROJO=0
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
pg()   { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "$1" 2>&1; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR"; }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
for k in sys.argv[2].split('.'):
    d=d.get(k) if isinstance(d,dict) else None
print('' if d is None else (json.dumps(d) if isinstance(d,(dict,list)) else d))" "$1" "$2" 2>/dev/null; }
# alta <clave> <numero> — régimen anterior (sin PDF), como V, para PA
alta() {
  run_as "$V" "select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object('cliente_id','$PA','numero_contrato','$2','capital',20000,'moneda','PEN','tasa_anual',15,
      'modalidad','mensual','tipo_interes','simple','categoria','nuevo','fecha_inicio','2026-03-11','fecha_vencimiento','2027-03-11',
      'notas_internas','oraculo replay en eliminacion r$RUN','clave_idempotencia','$1'),
    jsonb_build_array(
      jsonb_build_object('numero_cuota',1,'fecha_programada','2026-04-11','monto_programado',250,'tipo','cuota'),
      jsonb_build_object('numero_cuota',2,'fecha_programada','2027-03-11','monto_programado',20000,'tipo','retorno')),
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','RPL$RUN','cci','$CCI',
      'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null))"
}

echo "== Preflight (RUN=$RUN) =="
FLAG_RP="$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")"
restaurar_flags() { psql "$PG" -q -c "update crm.multiempresa_flags set activo='${FLAG_RP:-f}' where nombre='resolver_en_puertas';" >/dev/null; }
trap restaurar_flags EXIT
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select count(*) from public.perfiles where id='$PA' and rol='cliente' and activo")" == "1" ]] && ok "fixture: cliente PA activo con asesor V" || rojo "fixture PA"
psql "$PG" -q -c "insert into auth.users (id) values ('$ADM') on conflict (id) do nothing;" >/dev/null 2>&1
sys "insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$ADM','RPL ADMIN r$RUN','admin','DNI','8${RUN}1') on conflict (id) do update set activo = true, rol='admin';"
[[ "$(q "select count(*) from public.perfiles where id='$ADM' and rol='admin' and activo")" == "1" ]] && ok "fixture: admin efímero ADM" || rojo "fixture ADM"
psql "$PG" -q -c "update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';" >/dev/null
H="$(q "select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='crear_contrato_con_cuenta_pdf_v2'")"
case "$H" in
  "$H_NUEVO") echo "  puerta = texto de la migración 20260905234500 (todo debe salir VERDE)";;
  "$H_PROD")  echo "  puerta = texto VIVO (v2.1 de idempotencia), sin m3 (A debe salir ROJA: mutante)";;
  *) echo "  ⚠️ puerta con md5(functiondef) desconocido: $H";;
esac

echo "== A) EL HUECO m3: eliminación PREPARADA y no finalizada; el analista reintenta con la misma clave =="
K1="$(uuid)"; NA="RPL-$RUN-A"; O1="$(alta "$K1" "$NA")"; A1="$(j "$O1" id)"
[[ -n "$A1" ]] && ok "alta $NA con clave K1 → ${A1:0:8}…" || rojo "alta A no se creó: ${O1:0:160}"
PREP="$(pg "select crm.contrato_eliminacion_preparar('$A1','$ADM')")"; TOK="$(j "$PREP" token)"
[[ -n "$TOK" && "$(q "select count(*) from private.contrato_eliminaciones where contrato_id='$A1'")" == "1" ]] && ok "Gerencia (ADM) PREPARÓ la eliminación: hay fila pendiente, el contrato aún existe" || rojo "preparar falló: ${PREP:0:160}"
O2="$(alta "$K1" "$NA")"
if echo "$O2" | grep -q "ERROR:  55000: El contrato está en proceso de eliminación" && [[ -z "$(j "$O2" id)" ]]; then ok "el replay con K1 responde 55000 «en proceso de eliminación» y NO devuelve ningún contrato"
elif [[ "$(j "$O2" id)" == "$A1" ]]; then rojo "el replay devolvió el contrato en eliminación como «alta recuperada» (idempotente=$(j "$O2" idempotente))"
else rojo "el replay respondió algo inesperado: ${O2:0:160}"; fi
[[ "$(q "select count(*) from public.contratos where id='$A1'")" == "1" ]] && ok "el contrato sigue existiendo (el replay no lo tocó)" || rojo "el contrato desapareció en el replay"
FIN="$(pg "select crm.contrato_eliminacion_finalizar('$A1','$TOK','$ADM')")"
[[ "$(j "$FIN" ok)" == "True" || "$(j "$FIN" ok)" == "true" ]] && ok "Gerencia FINALIZÓ el borrado" || rojo "finalizar falló: ${FIN:0:160}"
O3="$(alta "$K1" "$NA")"
echo "$O3" | grep -q "fue eliminado después" && ok "tras el borrado, el replay sigue siendo lápida: P0409 ALTA_ELIMINADA, no recrea" || rojo "la lápida dejó de funcionar: ${O3:0:160}"
[[ "$(q "select count(*) from public.contratos where numero_contrato='$NA'")" == "0" ]] && ok "no existe ningún $NA" || rojo "se recreó $NA"

echo "== B) REGRESIÓN: el replay normal (sin eliminación pendiente) sigue devolviendo el mismo contrato =="
K2="$(uuid)"; NB="RPL-$RUN-B"; O4="$(alta "$K2" "$NB")"; B1="$(j "$O4" id)"
[[ -n "$B1" ]] && ok "alta $NB con clave K2 → ${B1:0:8}…" || rojo "alta B no se creó: ${O4:0:160}"
O5="$(alta "$K2" "$NB")"
[[ "$(j "$O5" id)" == "$B1" && ( "$(j "$O5" idempotente)" == "True" || "$(j "$O5" idempotente)" == "true" ) ]] && ok "replay sin eliminación pendiente: el MISMO contrato, idempotente=true" || rojo "el replay normal cambió: ${O5:0:160}"
O6="$(alta "$K2" "RPL-$RUN-B2")"
echo "$O6" | grep -q "con otros datos" && ok "misma clave con otro número sigue siendo P0409 «con otros datos»" || rojo "el rechazo por huella cambió: ${O6:0:120}"
[[ "$(q "select count(*) from public.contratos where numero_contrato like 'RPL-$RUN-B%'")" == "1" ]] && ok "un solo contrato B" || rojo "$(q "select count(*) from public.contratos where numero_contrato like 'RPL-$RUN-B%'") contratos B"

echo "== C) HIGIENE: identidad y ACL exacta de la puerta; la memoria intacta =="
[[ "$H" == "$H_PROD" || "$H" == "$H_NUEVO" ]] && ok "md5(pg_get_functiondef) es el vivo (v2.1) o el de la migración" || rojo "functiondef desconocido"
[[ "$(q "select p.proowner::regrole::text||'|'||p.prosecdef||'|'||array_to_string(p.proconfig,',') from pg_proc p where p.oid='$SIG'::regprocedure")" == 'postgres|true|search_path=""' ]] && ok "dueño postgres, DEFINER, search_path vacío" || rojo "dueño/definer/search_path cambiaron"
[[ "$(q "select proacl::text from pg_proc where oid='$SIG'::regprocedure")" == "{postgres=X/postgres,authenticated=X/postgres}" ]] && ok "ACL exacta {postgres,authenticated}" || rojo "ACL cambió: $(q "select proacl::text from pg_proc where oid='$SIG'::regprocedure")"
[[ "$(q "select relrowsecurity and relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname='contrato_altas_idempotentes'")" == "t" ]] && ok "la memoria private.contrato_altas_idempotentes sigue con RLS forzada" || rojo "la memoria cambió"

echo
if [[ $ROJO -eq 0 ]]; then echo "ORÁCULO REPLAY EN ELIMINACIÓN: TODO VERDE (RUN=$RUN)"; else echo "ORÁCULO REPLAY EN ELIMINACIÓN: $ROJO ROJO(S) (RUN=$RUN)" >&2; fi
exit $ROJO
