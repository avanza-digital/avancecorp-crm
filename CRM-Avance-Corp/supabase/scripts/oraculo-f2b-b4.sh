#!/usr/bin/env bash
# ORÁCULO F2.b sub-lote b4 — «la conversión Avance reserva por la persona» — SOLO en el BANCO.
# Ejercita la sobrecarga de reserva por persona, el sellado con identidad, la saga de conversión
# (cierre transaccional), la retoma de Gerencia, la coop frente a una Avance en curso en OTRO lead,
# el gate de inversiones y la paridad con la bandera apagada.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-b4.sh   (lee $S/banco-pooler.txt). Presupone E1 + b3 + b4.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
L1="f31ead00-0000-0000-0000-${RUN}000001"; L2="f31ead00-0000-0000-0000-${RUN}000002"
L3="f31ead00-0000-0000-0000-${RUN}000003"; L4="f31ead00-0000-0000-0000-${RUN}000004"; L5="f31ead00-0000-0000-0000-${RUN}000005"
DA="7${RUN}5"; DB="7${RUN}6"; DC="7${RUN}7"; DD="7${RUN}8"; ROJO=0
AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
flag() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null; }
flag_inv() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='inversiones_escritura';" >/dev/null; }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]); print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
pay()  { echo "{\"correo\":\"$1\",\"nombre_completo\":\"B4 $2\",\"telefono\":\"9${RUN}0$3\",\"domicilio\":\"Av. Prueba 123, Lima\"}"; }
reservar() { run_as "$1" "select crm.reservar_conversion_lead('$2','DNI','$3','$4'::jsonb)"; }
saga() { run_as "$1" "select crm.saga_conversion_fn('$2','$3'::jsonb)"; }
coop() { run_as "$V" "select crm.convertir_lead_externo('$1','qorilazo',1000,'PEN','DNI','$2','B4 PERSONA','TRX-B4-${RUN}-$3')"; }
sim_auth()  { psql "$PG" -q -c "insert into auth.users (id, email, raw_app_meta_data) values ('$1', '$2', jsonb_build_object('claim_id','$3')) on conflict (id) do nothing;" 2>/dev/null; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','B4 CLIENTE $2 r$RUN','cliente','DNI','$2','$3','$V',true); commit;" 2>&1 | grep -E "ERROR"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select to_regprocedure('crm.saga_conversion_fn(text,jsonb)') is not null")" == "t" ]] || { echo "falta b4" >&2; exit 2; }
flag true; flag_inv false

echo "== Reserva por persona: identidad antes de Auth; saga completa con cierre transaccional =="
R="$(reservar "$V" "$L1" "$DA" "$(pay "a$RUN@x.pe" A 1)")"; CL="$(j "$R" claim_id)"; TK="$(j "$R" token)"; VER="$(j "$R" version)"; INV="$(j "$R" inversionista_id)"
[[ -n "$CL" && -n "$TK" && "$(j "$R" estado)" == "reclamado" && "$(j "$R" ok)" == "True" ]] && ok "reservar(L1, DNI $DA) → identidad + reserva + claim (reclamado)" || rojo "reservar: $R"
[[ "$(q "select count(*) from crm.conversion_reservas where lead_id='$L1' and inversionista_id='$INV' and claim_id='$CL' and hash_payload is not null")" == "1" ]] && ok "la reserva lleva inversionista_id, claim_id y huella (sin documento)" || rojo "reserva sin identidad/claim"
R2="$(coop "$L2" "$DA" 2)"; echo "$R2" | grep -q "en curso en otro lead" && ok "coop sobre OTRO lead de la misma persona con reserva viva → P0409 (Avance en curso)" || rojo "coop pasó: $(echo "$R2"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-140)"
R3="$(reservar "$G" "$L3" "$DA" "$(pay "a$RUN@x.pe" A 1)")"; echo "$R3" | grep -q "en curso en otro lead" && ok "otra reserva (Gerencia, otro lead, misma persona) → P0409" || rojo "segunda reserva pasó: $R3"
R4="$(run_as "$V" "select crm.marcar_efectos_conversion('$L1','$CL','malo')")"; echo "$R4" | grep -q "42501" && ok "sellar con token inválido → 42501" || rojo "sellado con token malo: $R4"
R4="$(run_as "$V" "select crm.marcar_efectos_conversion('$L1','$CL','$TK')")"; [[ "$(j "$R4" ok)" == "True" ]] && ok "sellar con claim+token → efectos_iniciados_en (identidad bloqueada antes)" || rojo "sellado: $R4"
[[ "$(q "select efectos_iniciados_en is not null from crm.conversion_reservas where lead_id='$L1'")" == "t" ]] && ok "reserva sellada" || rojo "no sellada"
AU="$(uuid)"; AUX="$(uuid)"; sim_auth "$AUX" "x$RUN@x.pe" "otro"; R5="$(saga "$V" registrar_auth "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"auth_user_id\":\"$AUX\",\"version\":$VER}")"; echo "$R5" | grep -q "marca de este claim" && ok "Auth sin la marca del claim → rechazado en servidor" || rojo "Auth ajeno aceptado: $R5"
sim_auth "$AU" "a$RUN@x.pe" "$CL"; R5="$(saga "$V" registrar_auth "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"auth_user_id\":\"$AU\",\"version\":$VER}")"; [[ "$(j "$R5" estado)" == "auth_creado" ]] && ok "registrar_auth → auth_creado" || rojo "registrar_auth: $R5"; VER="$(j "$R5" version)"
sim_perfil "$AU" "$DA" "a$RUN@x.pe"; R6="$(saga "$V" perfil_creado "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"perfil_id\":\"$AU\",\"version\":$VER}")"; VER="$(j "$R6" version)"; [[ "$(j "$R6" estado)" == "perfil_creado" ]] && ok "perfil_creado" || rojo "perfil_creado: $R6"
# cierre con un lead que NO es el reservado → P0409 y nada convertido
R7="$(saga "$V" cerrar "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"version\":$VER,\"lead_id\":\"$L3\",\"perfil_id\":\"$AU\",\"domicilio\":\"Av. Prueba 123, Lima\"}")"; echo "$R7" | grep -q "no es el reservado" && [[ "$(q "select etapa from crm.leads where id='$L3'")" == "nuevo" ]] && ok "cerrar con otro lead → P0409, L3 intacto" || rojo "cierre con otro lead: $R7"
R="$(saga "$V" cerrar "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"lead_id\":\"$L1\",\"perfil_id\":\"$AU\",\"domicilio\":\"Av. Prueba 123, Lima\"}")"; echo "$R" | grep -q "Falta version" && ok "cerrar sin version → 22023 (el CAS no se puede omitir)" || rojo "cerrar sin version pasó: $R"
R7="$(saga "$V" cerrar "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"version\":$VER,\"lead_id\":\"$L1\",\"perfil_id\":\"$AU\",\"domicilio\":\"Av. Prueba 123, Lima\"}")"
[[ "$(j "$R7" estado)" == "enlazado" && "$(q "select etapa='convertido' and perfil_id='$AU' and inversionista_id='$INV' from crm.leads where id='$L1'")" == "t" ]] && ok "cerrar → conversión + claim enlazado en UNA transacción (lead convertido, perfil e identidad enlazados)" || rojo "cerrar: $R7"
[[ "$(q "select perfil_id='$AU' from crm.inversionistas where id='$INV'")" == "t" ]] && ok "identidad.perfil_id = perfil de la conversión" || rojo "identidad sin perfil"
R8="$(reservar "$V" "$L1" "$DA" "$(pay "a$RUN@x.pe" A 1)")"; [[ "$(j "$R8" estado)" == "enlazado" && "$(j "$R8" perfil_id)" == "$AU" ]] && ok "reservar de nuevo tras cerrar (respuesta perdida) → enlazado + perfil_id, sin Auth" || rojo "reanudación tras cierre: $R8"

echo "== Cierre transaccional con persona DISTINTA → revierte =="
R="$(reservar "$V" "$L4" "$DB" "$(pay "b$RUN@x.pe" B 2)")"; CLB="$(j "$R" claim_id)"; TKB="$(j "$R" token)"; VERB="$(j "$R" version)"
AUB="$(uuid)"; sim_auth "$AUB" "b$RUN@x.pe" "$CLB"; R="$(saga "$V" registrar_auth "{\"claim_id\":\"$CLB\",\"token\":\"$TKB\",\"auth_user_id\":\"$AUB\",\"version\":$VERB}")"; VERB="$(j "$R" version)"
sim_perfil "$AUB" "$DC" "b$RUN@x.pe"   # perfil con OTRO documento (DC): la conversión resolvería otra persona
R="$(saga "$V" cerrar "{\"claim_id\":\"$CLB\",\"token\":\"$TKB\",\"version\":$VERB,\"lead_id\":\"$L4\",\"perfil_id\":\"$AUB\",\"domicilio\":\"Av. Prueba 123, Lima\"}")"
echo "$R" | grep -q "no es la persona reservada" && [[ "$(q "select etapa from crm.leads where id='$L4'")" == "nuevo" && "$(q "select count(*) from crm.inversionista_identificadores d join crm.inversionistas i on i.id=d.inversionista_id where d.documento_normalizado='$DC' and i.perfil_id is not null")" == "0" ]] && ok "cerrar con perfil de OTRA persona → P0409 y la conversión se REVIERTE (lead sigue nuevo, nada enlazado)" || rojo "cierre con otra persona no revirtió: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-140)"

echo "== Coop primero → Avance después; veto; Gerencia retoma tras el tope =="
flag_inv true; R="$(coop "$L5" "$DD" 5)"; [[ "$(q "select etapa from crm.leads where id='$L5'")" == "convertido" ]] && ok "coop convirtió L5 (persona $DD) con inversiones_escritura ON" || rojo "coop L5: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-120)"
[[ "$(q "select count(*) from crm.inversiones inv join crm.inversionista_identificadores d on d.inversionista_id=inv.inversionista_id where d.documento_normalizado='$DD'")" == "1" ]] && ok "inversión escrita (bandera de F4 encendida)" || rojo "sin inversión con la bandera ON"
flag_inv false
LX="$(uuid)"; psql "$PG" -q -c "begin; insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LX','B4 LX r$RUN','9${RUN}77',1000,'landing','nuevo',null,'$V'); commit;" 2>/dev/null
R="$(reservar "$V" "$LX" "$DD" "$(pay "d$RUN@x.pe" D 4)")"; echo "$R" | grep -q "ya tiene su lead" && ok "reservar Avance para una persona ya convertida en coop (otro lead) → P0409 un-solo-lead" || rojo "reserva tras coop pasó: $R"
run_as "$V" "select crm.marcar_no_contactar('$L5','ensayo b4')" >/dev/null
R="$(reservar "$V" "$LX" "$DD" "$(pay "d$RUN@x.pe" D 4)")"; echo "$R" | grep -q "P0429" && ok "persona vetada → P0429 antes de Auth" || rojo "vetada reservó: $R"
run_as "$G" "select crm.levantar_no_contactar('$L5','limpieza b4')" >/dev/null
# Gerencia retoma: reserva sellada, claim en auth_creado, tope vencido.
LY="$(uuid)"; DE="7${RUN}9"; psql "$PG" -q -c "begin; insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LY','B4 LY r$RUN','9${RUN}78',1000,'landing','nuevo',null,'$V'); commit;" 2>/dev/null
R="$(reservar "$V" "$LY" "$DE" "$(pay "e$RUN@x.pe" E 5)")"; CLE="$(j "$R" claim_id)"; TKE="$(j "$R" token)"; VERE="$(j "$R" version)"
run_as "$V" "select crm.marcar_efectos_conversion('$LY','$CLE','$TKE')" >/dev/null
AUE="$(uuid)"; sim_auth "$AUE" "e$RUN@x.pe" "$CLE"; saga "$V" registrar_auth "{\"claim_id\":\"$CLE\",\"token\":\"$TKE\",\"auth_user_id\":\"$AUE\",\"version\":$VERE}" >/dev/null
psql "$PG" -q -c "update crm.conversion_reservas set vence_absoluto_en = now() - interval '1 minute', expira_en = now() - interval '1 minute' where lead_id='$LY'; update crm.multiempresa_idempotencia set resultado = resultado || jsonb_build_object('lease_hasta',(now()-interval '1 minute')::text) where resultado->>'claim_id'='$CLE';"
R="$(reservar "$V" "$LY" "$DE" "$(pay "e$RUN@x.pe" E 5)")"; echo "$R" | grep -q "P0409" && ok "vendedor tras el tope: no puede retomar la reserva sellada (P0409)" || rojo "vendedor retomó tras el tope: $R"
R="$(run_as "$V" "select crm.retomar_conversion_gerencia_fn('$LY')")"; echo "$R" | grep -q "42501" && ok "retomar: vendedor → 42501" || rojo "vendedor retomó como gerencia"
R="$(run_as "$G" "select crm.retomar_conversion_gerencia_fn('$LY')")"; [[ "$(j "$R" estado)" == "auth_creado" && "$(j "$R" auth_user_id)" == "$AUE" && -n "$(j "$R" token)" ]] && ok "Gerencia retoma: nuevo token, estado auth_creado, auth_user_id para reutilizar (el edge verifica la marca)" || rojo "retomar gerencia: $R"
TKE="$(j "$R" token)"; VERE="$(j "$R" version)"; sim_perfil "$AUE" "$DE" "e$RUN@x.pe"
R="$(saga "$G" cerrar "{\"claim_id\":\"$CLE\",\"token\":\"$TKE\",\"version\":$VERE,\"lead_id\":\"$LY\",\"perfil_id\":\"$AUE\",\"domicilio\":\"Av. Prueba 123, Lima\"}")"; [[ "$(j "$R" estado)" == "enlazado" && "$(q "select etapa from crm.leads where id='$LY'")" == "convertido" ]] && ok "Gerencia cierra la conversión retomada" || rojo "cierre retomado: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-140)"

echo "== Paridad con bandera APAGADA =="
flag false
R="$(reservar "$V" "$L3" "$DC" "$(pay "c$RUN@x.pe" C 3)")"; echo "$R" | grep -q "P0409" && echo "$R" | grep -qi "apagada" && ok "OFF: la sobrecarga por persona es inerte (P0409 apagada)" || rojo "OFF: sobrecarga actuó: $R"
R="$(run_as "$V" "select crm.reservar_conversion_lead('$L3')")"; [[ "$(j "$R" ok)" == "True" && "$(q "select inversionista_id is null from crm.conversion_reservas where lead_id='$L3'")" == "t" ]] && ok "OFF: la reserva de 1 argumento funciona como hoy (sin identidad)" || rojo "OFF: reserva 1-arg: $R"
R="$(run_as "$V" "select crm.marcar_efectos_conversion('$L3')")"; [[ "$(j "$R" ok)" == "True" ]] && ok "OFF: sellado de 1 argumento como hoy" || rojo "OFF: sellado: $R"
R="$(saga "$V" registrar_auth "{\"claim_id\":\"$CL\",\"token\":\"x\",\"auth_user_id\":\"$AU\",\"version\":1}")"; echo "$R" | grep -qi "apagada" && ok "OFF: saga_conversion_fn inerte" || rojo "OFF: saga actuó: $R"
R="$(run_as "$G" "select crm.retomar_conversion_gerencia_fn('$LY')")"; echo "$R" | grep -qi "apagada" && ok "OFF: retomar inerte" || rojo "OFF: retomar actuó: $R"
LZ="$(uuid)"; psql "$PG" -q -c "begin; insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LZ','B4 LZ r$RUN','9${RUN}79',1000,'landing','nuevo',null,'$V'); commit;" 2>/dev/null
R="$(coop "$LZ" "6${RUN}5" Z)"; [[ "$(q "select etapa from crm.leads where id='$LZ'")" == "convertido" && "$(q "select count(*) from crm.inversionista_identificadores where documento_normalizado='6${RUN}5'")" == "0" ]] && ok "OFF: conversión coop como hoy (sin identidad, sin inversiones)" || rojo "OFF: coop: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-120)"
flag true

psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false; flag_inv false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b b4: VERDE — reserva por persona, sellado con identidad, cierre transaccional, retoma de Gerencia, coop↔Avance por identidad, inversiones con la bandera de F4; paridad apagada."; exit 0
else echo "ORÁCULO F2.b b4: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
