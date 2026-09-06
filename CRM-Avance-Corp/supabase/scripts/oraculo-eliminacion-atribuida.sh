#!/usr/bin/env bash
# ORÁCULO «la eliminación de contrato queda auditada a nombre del actor» (migración 20260905233000) — SOLO en el BANCO.
# Modela el botón «Eliminar contrato» de Gerencia: la edge llama a crm.contrato_eliminacion_preparar/finalizar con
# service_role (auth.uid() NULL). Aquí se llama como postgres SIN claim: el mismo estado. Con el texto VIVO, el
# DELETE de public.contratos queda en audit_log con usuario_id NULL (A) o con la claim que hubiera (B): ROJO = el
# mutante que prueba que el ensayo mide el hueco. Con la migración, queda a nombre del actor (p_actor_id) y la
# claim previa se restaura: TODO VERDE. C comprueba que la puerta no perdió identidad ni ACL; D, que la
# autorización (token + solicitado_por) sigue exactamente igual. E mide el ÚNICO cambio de comportamiento:
# al borrar una RENOVACIÓN, el trigger restaurador hace un UPDATE anidado sobre el origen que
# proteger_campos_inmutables re-congela salvo para superadmin (es_superadmin() lee auth.uid()); como la FK
# renovado_a_id es NO ACTION, y ANTES aún, proteger_cuotas_contrato_cerrado (cronograma_pagos, también con bypass
# es_superadmin()) frena la restauración de las cuotas: hoy el DELETE falla P0001 para todos; con la migración un
# SUPERADMIN pasa ambos guards, restaura y borra (E2, ROJO con el vivo = mutante), un ADMIN sigue en P0001 (E1,
# igual en ambos: limitación pre-existente).
# Uso: S=/ruta/scratchpad ./oraculo-eliminacion-atribuida.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
V='f3000000-0000-0000-0000-000000000001'
PA="f3a00000-0000-0000-0000-${RUN}000001"
ADM="f3c00000-0000-0000-0000-${RUN}000001"    # admin efímero: la puerta exige es_admin() como actor
SUPER="f3d00000-0000-0000-0000-${RUN}000001"  # superadmin efímero: el único que restaura el origen de una renovación
CCI="002${RUN}00000000000"
SIG="crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)"
H_PROD='8e78cb04c7c5b6d561cd3c6c15b7f270'
H_NUEVO="$(awk '/functiondef NUEVO/ {print $4}' "$AQUI/eliminacion/huellas-generadas.txt" 2>/dev/null)"
ROJO=0
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
pg()   { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "$1" 2>&1; }   # como postgres, SIN claim (= service_role de la edge); verbose = imprime el SQLSTATE
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
for k in sys.argv[2].split('.'):
    d=d.get(k) if isinstance(d,dict) else None
print('' if d is None else (json.dumps(d) if isinstance(d,(dict,list)) else d))" "$1" "$2" 2>/dev/null; }
# alta <numero> [ini=2026-03-11] [venc=2027-03-11] [cuota=2026-04-11] — contrato del régimen anterior (sin PDF), como V, para PA
alta() {
  local ini="${2:-2026-03-11}" venc="${3:-2027-03-11}" cuota="${4:-2026-04-11}"
  run_as "$V" "select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object('cliente_id','$PA','numero_contrato','$1','capital',20000,'moneda','PEN','tasa_anual',15,
      'modalidad','mensual','tipo_interes','simple','categoria','nuevo','fecha_inicio','$ini','fecha_vencimiento','$venc',
      'notas_internas','oraculo eliminacion atribuida r$RUN'),
    jsonb_build_array(
      jsonb_build_object('numero_cuota',1,'fecha_programada','$cuota','monto_programado',250,'tipo','cuota'),
      jsonb_build_object('numero_cuota',2,'fecha_programada','$venc','monto_programado',20000,'tipo','retorno')),
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','ELIM$RUN','cci','$CCI',
      'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null))"
}
# alta_renov <numero> <origen_id> — RENOVACIÓN del origen (régimen anterior), como V: crear_contrato deja al origen
# en estado 'renovado' con renovado_a_id = nuevo y una fila en crm.operaciones_cartera.
alta_renov() {
  run_as "$V" "select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object('cliente_id','$PA','numero_contrato','$1','capital',20000,'moneda','PEN','tasa_anual',15,
      'modalidad','mensual','tipo_interes','simple','categoria','renovacion','contrato_origen_id','$2',
      'capital_renovado',20000,'capital_adicional',0,'fecha_inicio','2026-03-11','fecha_vencimiento','2027-03-11',
      'notas_internas','oraculo eliminacion atribuida (renovacion) r$RUN'),
    jsonb_build_array(
      jsonb_build_object('numero_cuota',1,'fecha_programada','2026-04-11','monto_programado',250,'tipo','cuota'),
      jsonb_build_object('numero_cuota',2,'fecha_programada','2027-03-11','monto_programado',20000,'tipo','retorno')),
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','ELIM$RUN','cci','$CCI',
      'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null))"
}
origen() { q "select coalesce(renovado_a_id::text,'NULL')||'|'||estado||'|'||coalesce(cerrado_en::text,'NULL')||'|'||coalesce(cerrado_por::text,'NULL') from public.contratos where id='$1'"; }
audit_delete_usuario() { q "select coalesce(usuario_id::text,'NULL') from public.audit_log where tabla='contratos' and fila_id::text='$1' and operacion='DELETE' order by ts desc limit 1"; }

echo "== Preflight (RUN=$RUN) =="
FLAG_RP="$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")"
limpiar() {
  psql "$PG" -q -c "update crm.multiempresa_flags set activo='${FLAG_RP:-f}' where nombre='resolver_en_puertas';" >/dev/null
  # Los actores efímeros de esta corrida: primero sus preparaciones pendientes (FK a perfiles), luego perfil y usuario.
  psql "$PG" -q -c "delete from private.contrato_eliminaciones where solicitado_por in ('$ADM','$SUPER'); delete from public.perfiles where id in ('$ADM','$SUPER'); delete from auth.users where id in ('$ADM','$SUPER');" >/dev/null 2>&1 || true
}
trap limpiar EXIT
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select count(*) from public.perfiles where id='$PA' and rol='cliente' and activo")" == "1" ]] && ok "fixture: cliente PA activo con asesor V" || rojo "fixture PA"
psql "$PG" -q -c "insert into auth.users (id) values ('$ADM'), ('$SUPER') on conflict (id) do nothing;" >/dev/null 2>&1
sys "insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$ADM','ELIM ADMIN r$RUN','admin','DNI','8${RUN}1') on conflict (id) do update set activo = true, rol='admin';
     insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$SUPER','ELIM SUPERADMIN r$RUN','superadmin','DNI','8${RUN}2') on conflict (id) do update set activo = true, rol='superadmin';"
[[ "$(q "select count(*) from public.perfiles where id='$ADM' and rol='admin' and activo")" == "1" ]] && ok "fixture: admin efímero ADM" || rojo "fixture ADM"
[[ "$(q "select count(*) from public.perfiles where id='$SUPER' and rol='superadmin' and activo")" == "1" ]] && ok "fixture: superadmin efímero SUPER" || rojo "fixture SUPER"
psql "$PG" -q -c "update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';" >/dev/null
H="$(q "select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='contrato_eliminacion_finalizar'")"
case "$H" in
  "$H_NUEVO") echo "  puerta = texto de la migración 20260905233000 (todo debe salir VERDE)";;
  "$H_PROD")  echo "  puerta = texto VIVO de producción, SIN atribución (A y B deben salir ROJAS: mutante)";;
  *) echo "  ⚠️ puerta con md5(functiondef) desconocido: $H";;
esac

echo "== A) EL BOTÓN DE GERENCIA: la edge (service_role, sin claim) prepara y finaliza; el DELETE debe quedar a nombre del actor =="
NA="ELIM-$RUN-A"; OA="$(alta "$NA")"; A1="$(j "$OA" id)"
[[ -n "$A1" ]] && ok "alta $NA → ${A1:0:8}…" || rojo "alta A no se creó: ${OA:0:160}"
PREP="$(pg "select crm.contrato_eliminacion_preparar('$A1','$ADM')")"; TOK="$(j "$PREP" token)"
[[ -n "$TOK" ]] && ok "preparar como postgres sin claim: autorizado para ADM (token)" || rojo "preparar falló: ${PREP:0:160}"
FIN="$(pg "select crm.contrato_eliminacion_finalizar('$A1','$TOK','$ADM')")"
[[ "$(j "$FIN" ok)" == "True" || "$(j "$FIN" ok)" == "true" ]] && ok "finalizar: contrato eliminado" || rojo "finalizar falló: ${FIN:0:160}"
[[ "$(q "select count(*) from public.contratos where id='$A1'")" == "0" && "$(q "select count(*) from public.cronograma_pagos where contrato_id='$A1'")" == "0" ]] && ok "no queda contrato ni cronograma" || rojo "quedaron restos de $NA"
UA="$(audit_delete_usuario "$A1")"
[[ "$UA" == "$ADM" ]] && ok "audit_log: el DELETE quedó a nombre de ADM (antes: NULL)" || rojo "audit_log.usuario_id del DELETE = $UA (esperado ADM $ADM)"
# Y la claim vuelve a estar vacía al salir cuando no había ninguna (misma transacción, como la edge):
NA2="ELIM-$RUN-A2"; OA2="$(alta "$NA2")"; A2="$(j "$OA2" id)"
RA2="$(pg "do \$\$ declare t uuid; begin
  t := (crm.contrato_eliminacion_preparar('$A2','$ADM')->>'token')::uuid;
  perform crm.contrato_eliminacion_finalizar('$A2',t,'$ADM');
  raise notice 'CLAIM_DESPUES=[%]', coalesce(current_setting('request.jwt.claim.sub', true),'');
end \$\$;")"
echo "$RA2" | grep -q "CLAIM_DESPUES=\[\]" && ok "sin claim previa, al salir de finalizar la claim vuelve a estar vacía (auth.uid() NULL otra vez)" || rojo "la claim quedó pegada: $(echo "$RA2" | grep -o 'CLAIM_DESPUES=\[[^]]*\]')"
[[ "$(audit_delete_usuario "$A2")" == "$ADM" ]] && ok "y ese DELETE también quedó a nombre de ADM" || rojo "DELETE de A2 sin atribuir"

echo "== B) LA CLAIM PREVIA SE RESPETA Y SE RESTAURA: entra como V, el DELETE se atribuye a ADM, al salir vuelve a ser V =="
NB="ELIM-$RUN-B"; OB="$(alta "$NB")"; B1="$(j "$OB" id)"
[[ -n "$B1" ]] && ok "alta $NB → ${B1:0:8}…" || rojo "alta B no se creó: ${OB:0:160}"
RB="$(pg "do \$\$ declare t uuid; begin
  perform set_config('request.jwt.claim.sub','$V',true);
  t := (crm.contrato_eliminacion_preparar('$B1','$ADM')->>'token')::uuid;
  perform crm.contrato_eliminacion_finalizar('$B1',t,'$ADM');
  raise notice 'CLAIM_DESPUES=%', coalesce(current_setting('request.jwt.claim.sub', true),'<null>');
end \$\$;")"
echo "$RB" | grep -q "CLAIM_DESPUES=$V" && ok "la claim previa (V) se restauró al salir de finalizar" || rojo "la claim no se restauró: $(echo "$RB" | grep -o 'CLAIM_DESPUES=[^ ]*' || echo "${RB:0:120}")"
UB="$(audit_delete_usuario "$B1")"
[[ "$UB" == "$ADM" ]] && ok "audit_log: el DELETE quedó a nombre de ADM, no de la claim previa V" || rojo "audit_log.usuario_id del DELETE = $UB (esperado ADM; con el texto vivo sale V)"

echo "== E) RENOVACIÓN: el UPDATE anidado del trigger restaurador pasa por proteger_campos_inmutables (lee auth.uid()) =="
# E1 · ADMIN: hoy y con la migración, proteger_cuotas_contrato_cerrado frena la restauración de las cuotas del origen (P0001).
OE1="$(alta "ELIM-$RUN-E1O" 2026-01-11 2026-03-11 2026-02-11)"; E1O="$(j "$OE1" id)"
OE1N="$(alta_renov "ELIM-$RUN-E1N" "$E1O")"; E1N="$(j "$OE1N" id)"
[[ -n "$E1O" && -n "$E1N" ]] && ok "E1: origen ${E1O:0:8}… renovado por ${E1N:0:8}… (origen: $(origen "$E1O" | cut -d'|' -f2))" || rojo "E1: no se pudo montar la renovación: ${OE1N:0:160}"
[[ "$(origen "$E1O" | cut -d'|' -f1)" == "$E1N" ]] && ok "E1: el origen apunta al nuevo (renovado_a_id) y está cerrado" || rojo "E1: el origen no quedó enlazado: $(origen "$E1O")"
PE1="$(pg "select crm.contrato_eliminacion_preparar('$E1N','$ADM')")"; TE1="$(j "$PE1" token)"
FE1="$(pg "select crm.contrato_eliminacion_finalizar('$E1N','$TE1','$ADM')")"
echo "$FE1" | grep -q "P0001: El contrato está cerrado (renovado)" && ok "E1: como ADMIN el borrado de la renovación falla P0001 «contrato cerrado (renovado): sus cuotas…» (el guard de cuotas frena la restauración; limitación PRE-EXISTENTE, igual con y sin migración)" || rojo "E1: como admin no dio el P0001 esperado: ${FE1:0:140}"
[[ "$(q "select count(*) from public.contratos where id='$E1N'")" == "1" && "$(origen "$E1O" | cut -d'|' -f1)" == "$E1N" ]] && ok "E1: nada cambió (la renovación sigue, el origen sigue enlazado)" || rojo "E1: el estado cambió tras el P0001"
pg "delete from private.contrato_eliminaciones where contrato_id='$E1N'" >/dev/null   # soltar la preparación de ADM para la siguiente prueba
# E2 · SUPERADMIN: con la claim del actor, es_superadmin() es true en los dos guards (cuotas y campos inmutables) → el origen
#      se restaura y el DELETE sale. Con el texto VIVO la claim es NULL → mismo P0001 que E1: ROJO = mutante.
OE2="$(alta "ELIM-$RUN-E2O" 2026-01-11 2026-03-11 2026-02-11)"; E2O="$(j "$OE2" id)"
OE2N="$(alta_renov "ELIM-$RUN-E2N" "$E2O")"; E2N="$(j "$OE2N" id)"
[[ -n "$E2O" && -n "$E2N" && "$(origen "$E2O" | cut -d'|' -f1)" == "$E2N" ]] && ok "E2: origen ${E2O:0:8}… renovado por ${E2N:0:8}…" || rojo "E2: no se pudo montar la renovación: ${OE2N:0:160}"
PE2="$(pg "select crm.contrato_eliminacion_preparar('$E2N','$SUPER')")"; TE2="$(j "$PE2" token)"
FE2="$(pg "select crm.contrato_eliminacion_finalizar('$E2N','$TE2','$SUPER')")"
if [[ "$(j "$FE2" ok)" == "True" || "$(j "$FE2" ok)" == "true" ]]; then
  ok "E2: como SUPERADMIN el borrado de la renovación SALE (el guard dejó pasar la restauración del origen)"
  ORG="$(origen "$E2O")"
  [[ "$(echo "$ORG" | cut -d'|' -f1)" == "NULL" && "$(echo "$ORG" | cut -d'|' -f3)" == "NULL" && "$(echo "$ORG" | cut -d'|' -f4)" == "NULL" ]] && ok "E2: el origen quedó restaurado (renovado_a_id, cerrado_en, cerrado_por = NULL; estado $(echo "$ORG" | cut -d'|' -f2))" || rojo "E2: el origen NO se restauró: $ORG"
  [[ "$(q "select count(*) from public.cronograma_pagos where contrato_id='$E2O' and estado='trasladado'")" == "0" ]] && ok "E2: las cuotas del origen ya no están 'trasladado'" || rojo "E2: quedaron cuotas trasladadas en el origen"
  [[ "$(q "select count(*) from crm.operaciones_cartera where contrato_nuevo_id='$E2N'")" == "0" && "$(q "select count(*) from public.contratos where id='$E2N'")" == "0" ]] && ok "E2: la operación de cartera y la renovación desaparecieron" || rojo "E2: quedaron restos de la renovación"
  [[ "$(audit_delete_usuario "$E2N")" == "$SUPER" ]] && ok "E2: audit_log: el DELETE de la renovación quedó a nombre de SUPER" || rojo "E2: DELETE sin atribuir a SUPER: $(audit_delete_usuario "$E2N")"
  UPD="$(q "select coalesce(usuario_id::text,'NULL') from public.audit_log where tabla='contratos' and fila_id::text='$E2O' and operacion='UPDATE' order by ts desc limit 1")"
  [[ "$UPD" == "$SUPER" ]] && ok "E2: audit_log: el UPDATE anidado que restauró el origen también quedó a nombre de SUPER" || rojo "E2: el UPDATE del origen quedó a nombre de $UPD"
else
  rojo "E2: como SUPERADMIN el borrado de la renovación NO salió (${FE2:0:100}) — con el texto vivo la claim es NULL y los guards no reconocen al superadmin: es el hueco"
fi

echo "== C) HIGIENE: la puerta conserva identidad y ACL exacta; la API no la alcanza =="
[[ "$H" == "$H_PROD" || "$H" == "$H_NUEVO" ]] && ok "md5(pg_get_functiondef) es el vivo o el de la migración" || rojo "functiondef desconocido"
[[ "$(q "select p.proowner::regrole::text||'|'||p.prosecdef||'|'||array_to_string(p.proconfig,',') from pg_proc p where p.oid='$SIG'::regprocedure")" == 'postgres|true|search_path=""' ]] && ok "dueño postgres, DEFINER, search_path vacío" || rojo "dueño/definer/search_path cambiaron"
[[ "$(q "select proacl::text from pg_proc where oid='$SIG'::regprocedure")" == "{postgres=X/postgres,service_role=X/postgres}" ]] && ok "ACL exacta {postgres,service_role}" || rojo "ACL cambió: $(q "select proacl::text from pg_proc where oid='$SIG'::regprocedure")"
[[ "$(q "select has_function_privilege('authenticated','$SIG','EXECUTE') or has_function_privilege('anon','$SIG','EXECUTE')")" == "f" ]] && ok "ni authenticated ni anon pueden ejecutarla" || rojo "authenticated/anon pueden ejecutar finalizar"

echo "== D) LA AUTORIZACIÓN NO CAMBIÓ: token equivocado y actor distinto siguen rechazados =="
ND="ELIM-$RUN-D"; OD="$(alta "$ND")"; D1="$(j "$OD" id)"
PREPD="$(pg "select crm.contrato_eliminacion_preparar('$D1','$ADM')")"; TOKD="$(j "$PREPD" token)"
BAD="$(pg "select crm.contrato_eliminacion_finalizar('$D1','00000000-0000-0000-0000-000000000000','$ADM')")"
echo "$BAD" | grep -q "P0002" && ok "token equivocado → P0002" || rojo "token equivocado no rechazado: ${BAD:0:120}"
OTRO="$(pg "select crm.contrato_eliminacion_finalizar('$D1','$TOKD','$V')")"
echo "$OTRO" | grep -q "P0002" && ok "actor distinto al solicitante → P0002" || rojo "actor distinto no rechazado: ${OTRO:0:120}"
[[ "$(q "select count(*) from public.contratos where id='$D1'")" == "1" ]] && ok "el contrato D sigue vivo tras los rechazos" || rojo "D desapareció tras un rechazo"
FIND="$(pg "select crm.contrato_eliminacion_finalizar('$D1','$TOKD','$ADM')")"
[[ "$(j "$FIND" ok)" == "True" || "$(j "$FIND" ok)" == "true" ]] && ok "limpieza: D eliminado por la puerta con el token correcto" || rojo "no se pudo limpiar D: ${FIND:0:120}"

echo
if [[ $ROJO -eq 0 ]]; then echo "ORÁCULO ELIMINACIÓN ATRIBUIDA: TODO VERDE (RUN=$RUN)"; else echo "ORÁCULO ELIMINACIÓN ATRIBUIDA: $ROJO ROJO(S) (RUN=$RUN)" >&2; fi
exit $ROJO
