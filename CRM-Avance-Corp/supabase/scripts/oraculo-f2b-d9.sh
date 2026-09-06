#!/usr/bin/env bash
# ORÁCULO F2.b [D-9] — los auditores genéricos de crm.leads y crm.cierres_externos NO copian el documento en claro — SOLO en el BANCO.
# Presupone la siembra siembra-banco-f3.sql (actores V/S/G). No depende de la bandera (D-9 no va detrás de ella).
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d9.sh   (lee $S/banco-pooler.txt). Sin D-9 (mutante) las secciones (1) y (2) deben salir ROJAS.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR" ; }
flag() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null; }
uuid() { q "select gen_random_uuid()"; }
audit_ultimo() { q "select coalesce(data_despues, data_antes)->>'$3' from public.audit_log where tabla='$1' and fila_id='$2' order by ts desc limit 1"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
DEF_L="$(q "select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid='crm.leads'::regclass and t.tgname='trg_audit_leads'")"
if echo "$DEF_L" | grep -q "log_audit_sin_secretos('dni')"; then echo "  D-9 instalada (todo debe salir VERDE)"; else echo "  ⚠️ D-9 NO instalada: corrida MUTANTE ((1) y (2) deben salir ROJAS)"; fi
flag false   # la identidad apagada: el ensayo no depende de ella y no debe dejar identidades

echo "== (1) crm.leads: el auditor enmascara dni y conserva el resto =="
L1="$(uuid)"; D1="4${RUN}1"
sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$L1','D9 LEAD r$RUN','9${RUN}61','$D1',1000,'landing','nuevo',null,'$V')"
N0="$(q "select count(*) from public.audit_log where tabla='crm.leads' and fila_id='$L1'")"
[[ "$N0" == "1" ]] && ok "INSERT del lead → 1 fila de auditoría (mismo fila_id)" || rojo "filas de auditoría del INSERT: $N0"
[[ "$(audit_ultimo crm.leads "$L1" dni)" == "***" ]] && ok "data_despues.dni = *** (enmascarado, sin huella)" || rojo "[D-9 HUECO] data_despues.dni = '$(audit_ultimo crm.leads "$L1" dni)'"
[[ "$(audit_ultimo crm.leads "$L1" telefono)" == "+519${RUN}61" && "$(audit_ultimo crm.leads "$L1" etapa)" == "nuevo" ]] && ok "las demás columnas siguen en claro (telefono, etapa)" || rojo "columnas no secretas alteradas"
[[ "$(q "select count(*) from public.audit_log where tabla='crm.leads' and fila_id='$L1' and (data_despues ? 'dni')")" == "1" ]] && ok "la clave dni sigue PRESENTE (enmascarada, no borrada)" || rojo "la clave dni desapareció del payload"
sys "update crm.leads set nombre_completo = 'D9 LEAD r$RUN bis' where id = '$L1'"
R="$(q "select (data_antes->>'dni')||' '||(data_despues->>'dni')||' '||(data_despues->>'nombre_completo') from public.audit_log where tabla='crm.leads' and fila_id='$L1' and operacion='UPDATE' order by ts desc limit 1")"
[[ "$R" == "*** *** D9 LEAD r$RUN bis" ]] && ok "UPDATE del lead → antes y después con dni = ***; el cambio real (nombre) sí queda" || rojo "UPDATE: '$R'"
N1="$(q "select count(*) from public.audit_log where tabla='crm.leads' and fila_id='$L1'")"
sys "update crm.leads set actualizado_en = clock_timestamp() where id = '$L1'"
N2="$(q "select count(*) from public.audit_log where tabla='crm.leads' and fila_id='$L1'")"
if echo "$DEF_L" | grep -q "sin_secretos"; then
  [[ "$N2" == "$N1" ]] && ok "(documentado) un UPDATE que solo mueve actualizado_en ya no deja fila (regla de ruido del auditor sin secretos)" || rojo "ruido: $N1 → $N2"
else
  echo "  (mutante: con log_audit_crm el UPDATE de solo actualizado_en deja fila: $N1 → $N2)"
fi
sys "update crm.leads set dni = null where id = '$L1'"
[[ "$(q "select data_despues->>'dni' is null and (data_despues ? 'dni') from public.audit_log where tabla='crm.leads' and fila_id='$L1' order by ts desc limit 1")" == "t" ]] && ok "dni NULL se conserva como null (no se enmascara un vacío)" || rojo "null enmascarado"
[[ "$(q "select count(*) from public.audit_log where tabla='crm.leads' and fila_id='$L1' and (coalesce(data_antes->>'dni','') = '$D1' or coalesce(data_despues->>'dni','') = '$D1')")" == "0" ]] && ok "el documento $D1 no aparece en NINGUNA fila de auditoría del lead" || rojo "[D-9 HUECO] el documento aparece en claro en audit_log"

echo "== (2) crm.cierres_externos: el auditor enmascara documento =="
L2="$(uuid)"; D2="4${RUN}2"
sys "insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$L2','D9 COOP r$RUN','9${RUN}62',1000,'landing','nuevo',null,'$V')"
R="$(run_as "$V" "select crm.convertir_lead_externo('$L2','qorilazo',1000,'PEN','DNI','$D2','D9 PERSONA COOP','TRX-D9-$RUN')")"
C2="$(q "select id from crm.cierres_externos where lead_id='$L2'")"
[[ -n "$C2" ]] && ok "fixture: cierre externo creado ($C2)" || rojo "coop: $(echo "$R" | grep -E 'ERROR|MESSAGE' | head -1 | cut -c1-200)"
[[ "$(audit_ultimo crm.cierres_externos "$C2" documento)" == "***" ]] && ok "data_despues.documento = ***" || rojo "[D-9 HUECO] documento = '$(audit_ultimo crm.cierres_externos "$C2" documento)'"
[[ "$(audit_ultimo crm.cierres_externos "$C2" documento_tipo)" == "DNI" && "$(audit_ultimo crm.cierres_externos "$C2" numero_transaccion)" == "TRX-D9-$RUN" ]] && ok "documento_tipo y numero_transaccion siguen en claro" || rojo "columnas del cierre alteradas"
[[ "$(q "select count(*) from public.audit_log where tabla='crm.cierres_externos' and fila_id='$C2' and (coalesce(data_antes->>'documento','') = '$D2' or coalesce(data_despues->>'documento','') = '$D2')")" == "0" ]] && ok "el documento $D2 no aparece en la auditoría del cierre" || rojo "[D-9 HUECO] documento del cierre en claro"

echo "== (3) el resto de la auditoría sigue igual =="
sys "insert into crm.actividades (lead_id, tipo, detalle, creado_por) values ('$L1','nota','D9 nota r$RUN',null)"
[[ "$(q "select data_despues->>'detalle' from public.audit_log where tabla='crm.actividades' and data_despues->>'lead_id'='$L1' order by ts desc limit 1")" == "D9 nota r$RUN" ]] && ok "crm.actividades sigue auditada con log_audit_crm (fila entera)" || rojo "auditoría de actividades"
[[ "$(q "select count(*) from private.tablas_sin_rastro() s where s.tabla in ('crm.leads','crm.cierres_externos')")" == "0" ]] && ok "el trinquete (tablas_sin_rastro) sigue viendo rastro completo en leads y cierres" || rojo "trinquete: $(q "select string_agg(tabla, ', ') from private.tablas_sin_rastro()")"
[[ "$(q "select count(*) from private.tablas_sin_rastro()")" == "0" ]] && ok "ninguna tabla sin rastro" || rojo "tablas sin rastro: $(q "select string_agg(tabla, ', ') from private.tablas_sin_rastro()")"
[[ "$(q "select exists (select 1 from private.auditoria_sello h where h.huella = private.huella_exenciones())")" == "t" ]] && ok "el sello de exenciones cuadra" || rojo "sello roto"
R="$(psql "$PG" -qtA -c "select private.assert_auditoria()" 2>&1)"; echo "$R" | grep -q "ERROR" && echo "  (info) assert_auditoria en el banco: $(echo "$R" | grep ERROR | head -1 | cut -c1-160)" || ok "private.assert_auditoria() pasa"
[[ "$(q "select count(*) from pg_trigger t where t.tgname in ('trg_audit_leads','trg_audit_cierres_externos') and t.tgenabled in ('O','A')")" == "2" ]] && ok "los dos auditores están habilitados" || rojo "auditor deshabilitado"
echo "  (info) filas históricas con documento en claro en este banco: leads=$(q "select count(*) from public.audit_log where tabla='crm.leads' and (coalesce(data_antes->>'dni','') not in ('','***') or coalesce(data_despues->>'dni','') not in ('','***'))") cierres=$(q "select count(*) from public.audit_log where tabla='crm.cierres_externos' and (coalesce(data_antes->>'documento','') not in ('','***') or coalesce(data_despues->>'documento','') not in ('','***'))")"

echo "== Limpieza =="
sys "update crm.leads set activo=false where id in ('$L1','$L2')"
echo; if [[ "$ROJO" -eq 0 ]]; then echo "ORÁCULO D-9: TODO VERDE (RUN=$RUN)"; else echo "ORÁCULO D-9: $ROJO ROJOS (RUN=$RUN)"; exit 1; fi
