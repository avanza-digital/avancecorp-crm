#!/usr/bin/env bash
# ORÁCULO F2.b bloque 1 de activación — [D-10] la reserva por persona cuenta el PUENTE en «un solo lead»
# y [D-11] el replay de un claim TERMINAL (`enlazar` de alta, `cerrar` de conversión) tras una fusión — SOLO en el BANCO.
# `run_as` cambia el ROL SQL (authenticated) y las claims: prueba también los grants. Presupone E1..E4 (b1..b5)
# y la siembra siembra-banco-f3.sql (actores V/S/G, leads L1..L5). Corrido ANTES de aplicar D-10 la sección D-10
# debe salir ROJA (es el mutante que prueba que el ensayo mide el hueco); DESPUÉS, todo VERDE.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d10-d11.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
L1="f31ead00-0000-0000-0000-${RUN}000001"; L2="f31ead00-0000-0000-0000-${RUN}000002"; L3="f31ead00-0000-0000-0000-${RUN}000003"
L4="f31ead00-0000-0000-0000-${RUN}000004"; L5="f31ead00-0000-0000-0000-${RUN}000005"
DZ="3${RUN}1"; DY="3${RUN}2"; DA="3${RUN}3"; DCA="3${RUN}4"; DB="3${RUN}5"; DC2="3${RUN}6"; DC3="3${RUN}7"; DW="3${RUN}8"
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR" ; }
flag() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null; }
flag_inv() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='inversiones_escritura';" >/dev/null; }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]); print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
pay()  { echo "{\"correo\":\"$1\",\"nombre_completo\":\"D10 $2\",\"telefono\":\"9${RUN}0$3\",\"domicilio\":\"Av. Prueba 123, Lima\"}"; }
reservar() { run_as "$1" "select crm.reservar_conversion_lead('$2','DNI','$3','$4'::jsonb)"; }
saga() { run_as "$1" "select crm.saga_conversion_fn('$2','$3'::jsonb)"; }
alta() { run_as "$1" "select crm.alta_cliente_identidad_fn('$2', '$3'::jsonb)"; }
coop() { run_as "$V" "select crm.convertir_lead_externo('$1','qorilazo',1000,'PEN','DNI','$2','D10 PERSONA','TRX-D10-${RUN}-$3')"; }
sim_auth()  { psql "$PG" -q -c "insert into auth.users (id, email, raw_app_meta_data) values ('$1', '$2', jsonb_build_object('claim_id','$3')) on conflict (id) do nothing;" 2>/dev/null; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','D10 CLIENTE $2 r$RUN','cliente','DNI','$2','$3','$V',true); commit;" 2>&1 | grep -E "ERROR"; }
lead_nuevo() { psql "$PG" -q -c "begin; insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D10 LEAD $2 r$RUN','9${RUN}$2',1000,'landing','nuevo',null,'$V'); commit;" 2>&1 | grep -E "ERROR"; }
prev()  { run_as "$G" "select crm.fusion_previsualizar_fn('$1','$2')"; }
fus()   { run_as "$G" "select crm.fusionar_inversionistas_fn('$1','$2','$3','$4')"; }
inv_de() { q "select private.inversionista_por_documento('DNI','$1')"; }
ver_de() { q "select version from crm.multiempresa_idempotencia where resultado->>'claim_id'='$1'"; }
claims_bajo() { q "select count(*) from crm.multiempresa_idempotencia where clave='auth_persona:$1'"; }
canon() { q "select private.inversionista_canonica('$1')"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select to_regprocedure('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)') is not null")" == "t" ]] || { echo "falta b5" >&2; exit 2; }
H4="$(q "select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb'")"
case "$H4" in
  b6c1863eec07df43e2023e7e8d729d05) echo "  reserva por persona = texto de D-10 v3 (la sección D-10 debe salir VERDE)";;
  ee743f339363abc6f4dce58e6bda6fac) echo "  reserva por persona = texto de D-10 v2 (sin el puente ajeno del propio lead: ese caso debe salir ROJO)";;
  940c1f37912ebf757c3a573280737c58) echo "  reserva por persona = texto de D-10 v1 (REEMPLAZABA el chequeo vivo: los casos «canónico + históricos» deben salir ROJOS)";;
  6242dfc993a3900ded3e084c9d4a1221) echo "  reserva por persona = texto VIVO de producción, SIN D-10 (la sección D-10 debe salir ROJA: mutante)";;
  *) echo "  ⚠️ reserva por persona con md5 desconocido: $H4";;
esac
flag true; flag_inv false

echo "== [D-10] «un solo lead» en la reserva por persona cuenta el PUENTE =="
IZ="$(q "select private.inversionista_resolver('DNI','$DZ',true,'ensayo-d10')")"; LH="$(uuid)"; lead_nuevo "$LH" 81 >/dev/null
sys "insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values ('$IZ','$LH','historico')"
[[ -n "$IZ" && "$(q "select inversionista_id is null from crm.leads where id='$LH'")" == "t" && "$(q "select count(*) from crm.inversionista_leads where inversionista_id='$IZ' and lead_id='$LH' and rol='historico'")" == "1" ]] && ok "fixture: IZ tiene el lead LH SOLO en el puente (histórico del backfill, sin enlace vivo)" || rojo "fixture IZ/LH"
R="$(reservar "$V" "$L1" "$DZ" "$(pay "z$RUN@x.pe" Z 1)")"
if echo "$R" | grep -q "ya tiene su lead"; then
  ok "reservar OTRO lead (L1) para la persona del puente → P0409 «ya tiene su lead»"
  echo "$R" | grep -q "$LH" && ok "el detalle señala el lead del puente (estado ya_es_cliente, lead_id = LH)" || rojo "detalle sin lead_id del puente: $(echo "$R" | grep -i detail | cut -c1-200)"
else
  rojo "[D-10 HUECO] la reserva por persona NO contó el puente: $(echo "$R" | head -c 200)"
fi
[[ "$(claims_bajo "$IZ")" == "0" && "$(q "select count(*) from crm.conversion_reservas where lead_id='$L1' and inversionista_id='$IZ'")" == "0" ]] && ok "sin claim ni reserva abiertos para IZ sobre L1" || rojo "quedó claim/reserva de IZ sobre L1 (claims=$(claims_bajo "$IZ"))"
# [Codex D-10 #2] el puente de ESTE lead manda: LH (sin enlace vivo ni DNI, puente → IZ) con un documento de OTRA persona
R="$(reservar "$V" "$LH" "$DW" "$(pay "w$RUN@x.pe" W 8)")"; IW="$(inv_de "$DW")"
if echo "$R" | grep -q "según su puente"; then ok "[#2] reservar LH con el documento de otra persona (IW) → P0409 «la persona de este lead (según su puente) no es la del documento»"; else rojo "[#2 HUECO] LH se reservó para otra persona: $(echo "$R" | head -c 200)"; fi
[[ -z "$IW" || "$(claims_bajo "$IW")" == "0" ]] && [[ "$(q "select count(*) from crm.conversion_reservas where lead_id='$LH'")" == "0" ]] && ok "[#2] sin claim bajo IW ni reserva de LH" || rojo "[#2] quedó claim/reserva (IW=$IW)"
R="$(reservar "$V" "$LH" "$DZ" "$(pay "z$RUN@x.pe" Z 1)")"
[[ "$(j "$R" ok)" == "True" && "$(j "$R" estado)" == "reclamado" ]] && ok "reservar el PROPIO lead del puente (LH) → pasa (el propio puente histórico no cuenta contra sí mismo) y abre claim" || rojo "reservar LH: $(echo "$R" | head -c 200)"
CLZ="$(j "$R" claim_id)"
R="$(coop "$L2" "$DY" 2)"; IY="$(inv_de "$DY")"; [[ -n "$IY" && "$(q "select etapa||' '||coalesce(inversionista_id::text,'') from crm.leads where id='$L2'")" == "convertido $IY" ]] && ok "fixture: IY convertida en coop con enlace VIVO en L2" || rojo "IY: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
LN="$(uuid)"; lead_nuevo "$LN" 82 >/dev/null
R="$(reservar "$V" "$LN" "$DY" "$(pay "y$RUN@x.pe" Y 2)")"; echo "$R" | grep -q "ya tiene su lead" && echo "$R" | grep -q "$L2" && ok "el camino de hoy sigue: enlace VIVO en otro lead (L2) → P0409 con lead_id = L2" || rojo "enlace vivo: $(echo "$R" | head -c 200)"
# [auditor D-10 M1] canónico VIVO + históricos del backfill: el detalle señala el canónico y un lead ya cerrado conserva su respuesta de hoy
LH2="$(uuid)"; lead_nuevo "$LH2" 83 >/dev/null; sys "insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values ('$IY','$LH2','historico')"
[[ "$(q "select count(*) from private.leads_de_identidades(array['$IY'::uuid])")" == "2" ]] && ok "fixture: IY con L2 (enlace vivo, convertida en coop) + LH2 solo en el puente (histórico)" || rojo "fixture IY históricos"
LN3="$(uuid)"; lead_nuevo "$LN3" 84 >/dev/null
R="$(reservar "$V" "$LN3" "$DY" "$(pay "y$RUN@x.pe" Y 2)")"; echo "$R" | grep -q "ya tiene su lead" && echo "$R" | grep -q "$L2" && ! echo "$R" | grep -q "$LH2" && ok "[M1a] otro lead para IY → P0409 y el detalle señala el CANÓNICO vivo (L2), no el histórico" || rojo "M1a: $(echo "$R" | head -c 260)"
R="$(reservar "$V" "$L2" "$DY" "$(pay "y$RUN@x.pe" Y 2)")"; echo "$R" | grep -q "ya esta cerrado" && ok "[M1b] reservar el propio canónico ya cerrado (coop, sin perfil) → «El lead ya esta cerrado», como hoy (los históricos no lo convierten en ya_es_cliente)" || rojo "M1b: $(echo "$R" | head -c 260)"
flag false
R="$(reservar "$V" "$L3" "$DZ" "$(pay "z$RUN@x.pe" Z 1)")"; echo "$R" | grep -q "P0409" && echo "$R" | grep -qi "apagada" && ok "OFF: la sobrecarga por persona sigue inerte (P0409 apagada, sin leer el puente)" || rojo "OFF: $R"
flag true

echo "== [D-11] replay de un claim TERMINAL tras una fusión — (A) alta directa: «enlazar» =="
R="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"a$RUN@x.pe\",\"nombre_completo\":\"D11 A\"}")"
CLA="$(j "$R" claim_id)"; TKA="$(j "$R" token)"; VERA="$(j "$R" version)"; PA="$(j "$R" inversionista_id)"
[[ -n "$CLA" && -n "$TKA" && -n "$PA" ]] && ok "alta reclamar → claim bajo PA" || rojo "reclamar: $R"
AUA="$(uuid)"; sim_auth "$AUA" "a$RUN@x.pe" "$CLA"
R="$(alta "$G" registrar_auth "{\"claim_id\":\"$CLA\",\"token\":\"$TKA\",\"auth_user_id\":\"$AUA\",\"version\":$VERA}")"; VERA="$(j "$R" version)"
sim_perfil "$AUA" "$DA" "a$RUN@x.pe"
R="$(alta "$G" enlazar "{\"claim_id\":\"$CLA\",\"token\":\"$TKA\",\"version\":$VERA}")"
[[ "$(j "$R" estado)" == "enlazado" && "$(j "$R" inversionista_id)" == "$PA" ]] && ok "enlazar → claim TERMINAL (enlazado) bajo PA, perfil $AUA" || rojo "enlazar: $R"
CA="$(q "select private.inversionista_resolver('DNI','$DCA',true,'ensayo-d11')")"
R="$(prev "$PA" "$CA")"; HA="$(j "$R" hash)"; [[ "$(j "$R" viable)" == "True" && -n "$HA" ]] && ok "PA→CA viable (claim terminal NO bloquea la fusión)" || rojo "prev PA→CA: $R"
R="$(fus "$PA" "$CA" "ensayo D-11 alta r$RUN" "$HA")"; [[ "$(j "$R" ok)" == "True" ]] && ok "fusión PA→CA" || rojo "fusión: $R"
[[ "$(q "select estado from crm.inversionistas where id='$PA'")" == "fusionado" && "$(q "select perfil_id from crm.inversionistas where id='$CA'")" == "$AUA" && "$(inv_de "$DA")" == "$CA" ]] && ok "PA fusionada; CA heredó el perfil; el DNI de PA resuelve a CA" || rojo "estado tras la fusión"
VNOW="$(ver_de "$CLA")"; N_INV0="$(q "select count(*) from crm.inversionistas")"; N_CL0="$(q "select count(*) from crm.multiempresa_idempotencia")"
R="$(alta "$G" enlazar "{\"claim_id\":\"$CLA\",\"token\":\"$TKA\",\"version\":$VNOW}")"
[[ "$(j "$R" estado)" == "enlazado" && "$(j "$R" inversionista_id)" == "$CA" && "$(j "$R" perfil_id)" == "$AUA" ]] && ok "REPLAY enlazar (versión vigente) tras la fusión → enlazado, inversionista_id = CA (canónica), mismo perfil" || rojo "replay enlazar: $R"
[[ "$(claims_bajo "$CA")" == "0" && "$(claims_bajo "$PA")" == "1" && "$(q "select count(*) from crm.inversionistas")" == "$N_INV0" && "$(q "select count(*) from crm.multiempresa_idempotencia")" == "$N_CL0" ]] && ok "el claim sigue bajo PA (historia); nada nuevo bajo CA; ni identidades ni claims nuevos" || rojo "replay creó algo: claims CA=$(claims_bajo "$CA") PA=$(claims_bajo "$PA")"
[[ "$(q "select perfil_id from crm.inversionistas where id='$CA'")" == "$AUA" && "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$CA' and hasta is null")" == "1" ]] && ok "CA conserva perfil y UN tramo abierto (el replay no abre otro)" || rojo "CA perfil/tramos tras el replay"
R="$(alta "$G" enlazar "{\"claim_id\":\"$CLA\",\"token\":\"$TKA\",\"version\":$VERA}")"; echo "$R" | grep -q "40001" && ok "REPLAY con versión VIEJA → 40001 (CAS: «vuelve a reclamar»)" || rojo "versión vieja pasó: $R"
R="$(alta "$G" enlazar "{\"claim_id\":\"$CLA\",\"token\":\"malo\",\"version\":$(ver_de "$CLA")}")"; echo "$R" | grep -q "42501" && ok "REPLAY con token inválido → 42501" || rojo "token malo pasó: $R"
R="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"a$RUN@x.pe\",\"nombre_completo\":\"D11 A\"}")"
[[ "$(j "$R" estado)" == "ya_existia" && "$(j "$R" inversionista_id)" == "$CA" && "$(j "$R" perfil_id)" == "$AUA" && "$(claims_bajo "$CA")" == "0" ]] && ok "«vuelve a reclamar» con el DNI de PA → ya_existia en CA con su perfil, SIN claim nuevo (nadie reanuda el claim de P)" || rojo "reclamar tras fusión: $R"

echo "== [D-11] (B) conversión Avance: «cerrar» =="
R="$(reservar "$V" "$L4" "$DB" "$(pay "b$RUN@x.pe" B 4)")"; CLB="$(j "$R" claim_id)"; TKB="$(j "$R" token)"; VERB="$(j "$R" version)"; IB="$(j "$R" inversionista_id)"
[[ -n "$CLB" && "$(j "$R" estado)" == "reclamado" ]] && ok "reservar(L4, $DB) → identidad IB + claim" || rojo "reservar L4: $R"
R="$(run_as "$V" "select crm.marcar_efectos_conversion('$L4','$CLB','$TKB')")"; [[ "$(j "$R" ok)" == "True" && "$(q "select efectos_iniciados_en is not null from crm.conversion_reservas where lead_id='$L4'")" == "t" ]] && ok "[Codex #6] sellado con claim+token → ok y efectos_iniciados_en escrito (la reserva queda SELLADA antes de Auth)" || rojo "sellado L4: $(echo "$R" | head -c 200)"
AUB="$(uuid)"; sim_auth "$AUB" "b$RUN@x.pe" "$CLB"; R="$(saga "$V" registrar_auth "{\"claim_id\":\"$CLB\",\"token\":\"$TKB\",\"auth_user_id\":\"$AUB\",\"version\":$VERB}")"; VERB="$(j "$R" version)"
sim_perfil "$AUB" "$DB" "b$RUN@x.pe"; R="$(saga "$V" perfil_creado "{\"claim_id\":\"$CLB\",\"token\":\"$TKB\",\"perfil_id\":\"$AUB\",\"version\":$VERB}")"; VERB="$(j "$R" version)"
R="$(saga "$V" cerrar "{\"claim_id\":\"$CLB\",\"token\":\"$TKB\",\"version\":$VERB,\"lead_id\":\"$L4\",\"perfil_id\":\"$AUB\",\"domicilio\":\"Av. Prueba 123, Lima\"}")"
[[ "$(j "$R" estado)" == "enlazado" && "$(q "select etapa='convertido' and perfil_id='$AUB' and inversionista_id='$IB' from crm.leads where id='$L4'")" == "t" ]] && ok "cerrar → L4 convertida, claim TERMINAL bajo IB" || rojo "cerrar: $R"
CB="$(q "select private.inversionista_resolver('DNI','$DC2',true,'ensayo-d11')")"
R="$(prev "$IB" "$CB")"; echo "$R" | grep -q "reserva de conversión viva" && ok "(observación) la reserva sellada de L4 sigue en su ventana de 5 min y bloquea la fusión: Gerencia espera" || rojo "prev IB→CB sin el bloqueo de la reserva: $(echo "$R" | head -c 200)"
sys "update crm.conversion_reservas set expira_en = now() - interval '1 minute' where lead_id='$L4'"
R="$(prev "$IB" "$CB")"; HB="$(j "$R" hash)"; [[ "$(j "$R" viable)" == "True" ]] && ok "pasada la ventana: IB→CB viable" || rojo "prev IB→CB: $R"
N_ACT0="$(q "select count(*) from crm.actividades where lead_id='$L4'")"
R="$(fus "$IB" "$CB" "ensayo D-11 conversión r$RUN" "$HB")"; [[ "$(j "$R" ok)" == "True" && "$(q "select inversionista_id from crm.leads where id='$L4'")" == "$CB" && "$(q "select inversionista_id from crm.conversion_reservas where lead_id='$L4'")" == "$CB" ]] && ok "fusión IB→CB: lead y reserva reapuntados a CB" || rojo "fusión IB→CB: $R"
N_ACT1="$(q "select count(*) from crm.actividades where lead_id='$L4'")"; VNOW="$(ver_de "$CLB")"; N_CL0="$(q "select count(*) from crm.multiempresa_idempotencia")"
R="$(saga "$V" cerrar "{\"claim_id\":\"$CLB\",\"token\":\"$TKB\",\"version\":$VNOW,\"lead_id\":\"$L4\",\"perfil_id\":\"$AUB\",\"domicilio\":\"Av. Prueba 123, Lima\"}")"
[[ "$(j "$R" estado)" == "enlazado" && "$(j "$R" reintento)" == "True" && "$(j "$R" inversionista_id)" == "$CB" && "$(j "$R" perfil_id)" == "$AUB" ]] && ok "REPLAY cerrar (versión vigente) tras la fusión → enlazado, reintento, inversionista_id = CB (canónica)" || rojo "replay cerrar: $R"
[[ "$(q "select etapa='convertido' and perfil_id='$AUB' and inversionista_id='$CB' from crm.leads where id='$L4'")" == "t" && "$(q "select count(*) from crm.actividades where lead_id='$L4'")" == "$N_ACT1" && "$(claims_bajo "$CB")" == "0" && "$(q "select count(*) from crm.multiempresa_idempotencia")" == "$N_CL0" ]] && ok "L4 intacta (convertida, CB), sin actividad repetida, sin claim bajo CB" || rojo "el replay dejó rastro: act $N_ACT1→$(q "select count(*) from crm.actividades where lead_id='$L4'") claims CB=$(claims_bajo "$CB")"
R="$(saga "$V" cerrar "{\"claim_id\":\"$CLB\",\"token\":\"$TKB\",\"version\":$VERB,\"lead_id\":\"$L4\",\"perfil_id\":\"$AUB\",\"domicilio\":\"Av. Prueba 123, Lima\"}")"; echo "$R" | grep -q "40001" && ok "REPLAY cerrar con versión VIEJA → 40001" || rojo "cerrar versión vieja pasó: $R"
R="$(saga "$V" cerrar "{\"claim_id\":\"$CLB\",\"token\":\"malo\",\"version\":$(ver_de "$CLB"),\"lead_id\":\"$L4\",\"perfil_id\":\"$AUB\"}")"; echo "$R" | grep -q "42501" && ok "REPLAY cerrar con token inválido → 42501" || rojo "cerrar token malo pasó: $R"
R="$(reservar "$V" "$L4" "$DB" "$(pay "b$RUN@x.pe" B 4)")"; [[ "$(j "$R" estado)" == "enlazado" && "$(j "$R" reanudar)" == "True" && "$(j "$R" inversionista_id)" == "$CB" && "$(j "$R" perfil_id)" == "$AUB" && "$(claims_bajo "$CB")" == "0" ]] && ok "reservar L4 tras la fusión (respuesta perdida) → enlazado por la etapa del lead, en CB, sin claim nuevo" || rojo "reservar L4 tras fusión: $R"
R="$(run_as "$V" "select crm.marcar_efectos_conversion('$L4','$CLB','$TKB')")"; echo "$R" | grep -q "no corresponde a este claim" && ok "(documentado, Codex) re-sellar tras la fusión → P0409 (reserva en CB, claim bajo IB): no es un camino del edge, que reanuda por reservar y recibe enlazado" || rojo "re-sellar tras fusión: $(echo "$R" | head -c 200)"
R="$(reservar "$V" "$L5" "$DB" "$(pay "b$RUN@x.pe" B 4)")"; echo "$R" | grep -q "ya tiene su lead" && echo "$R" | grep -q "$L4" && ok "reservar OTRO lead (L5) para la persona fusionada → P0409 con lead_id = L4 (enlace vivo reapuntado)" || rojo "L5 tras fusión: $(echo "$R" | head -c 200)"
# [auditor D-10 M1b] canónico Avance convertido + histórico: reservar el canónico sigue respondiendo enlazado (respuesta perdida)
LH3="$(uuid)"; lead_nuevo "$LH3" 85 >/dev/null; sys "insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values ('$CB','$LH3','historico')"
R="$(reservar "$V" "$L4" "$DB" "$(pay "b$RUN@x.pe" B 4)")"; [[ "$(j "$R" estado)" == "enlazado" && "$(j "$R" perfil_id)" == "$AUB" ]] && ok "[M1b] canónico Avance convertido + histórico en el puente → reservar L4 sigue en enlazado (no P0409)" || rojo "M1b Avance: $(echo "$R" | head -c 200)"
R="$(reservar "$V" "$L5" "$DB" "$(pay "b$RUN@x.pe" B 4)")"; echo "$R" | grep -q "ya tiene su lead" && echo "$R" | grep -q "$L4" && ! echo "$R" | grep -q "$LH3" && ok "[M1a] otro lead (L5) → P0409 con lead_id = L4 (vivo), no LH3 (histórico)" || rojo "M1a Avance: $(echo "$R" | head -c 200)"

echo "== [D-11] (C) un claim NO terminal sí bloquea la fusión =="
CC="$(q "select private.inversionista_resolver('DNI','$DC3',true,'ensayo-d11')")"
[[ "$(q "select resultado->>'estado' from crm.multiempresa_idempotencia where clave='auth_persona:$IZ'")" == "reclamado" ]] && ok "IZ tiene su claim de LH en «reclamado» (no terminal)" || rojo "claim de IZ no está en reclamado"
R="$(prev "$IZ" "$CC")"; [[ "$(j "$R" viable)" == "False" ]] && echo "$R" | grep -q "claim de Auth no terminal" && ok "IZ→CC no viable: «alta o conversión en curso (claim de Auth no terminal)»" || rojo "prev IZ→CC: $(echo "$R" | head -c 200)"

psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false; flag_inv false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b D-10/D-11: VERDE — la reserva por persona cuenta el puente; el replay de un claim terminal (enlazar/cerrar) tras una fusión es idempotente y proyecta la canónica; un claim no terminal bloquea la fusión."; exit 0
else echo "ORÁCULO F2.b D-10/D-11: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
