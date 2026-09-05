#!/usr/bin/env bash
# ORÁCULO F2.b [D-13] — «un solo lead» y «el puente manda» en TODAS las puertas con la bandera encendida — SOLO en el BANCO.
# Presupone b1..b5 (+ D-10 opcional) y D-13, y la siembra siembra-banco-f3.sql (actores V/S/G, leads L1..L5 sin DNI).
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d13.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
L1="f31ead00-0000-0000-0000-${RUN}000001"; L2="f31ead00-0000-0000-0000-${RUN}000002"; L3="f31ead00-0000-0000-0000-${RUN}000003"
DZ="2${RUN}1"; DY="2${RUN}2"; DB="2${RUN}3"; DC="2${RUN}4"; DL="2${RUN}5"; DZ2="2${RUN}6"; DW2="2${RUN}7"
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
pay()  { echo "{\"correo\":\"$1\",\"nombre_completo\":\"D13 $2\",\"telefono\":\"9${RUN}0$3\",\"domicilio\":\"Av. Prueba 123, Lima\"}"; }
reservar() { run_as "$1" "select crm.reservar_conversion_lead('$2','DNI','$3','$4'::jsonb)"; }
coop() { run_as "$V" "select crm.convertir_lead_externo('$1','qorilazo',1000,'PEN','DNI','$2','D13 PERSONA','TRX-D13-${RUN}-$3')"; }
verificar() { run_as "$V" "select crm.verificar_disponibilidad_lead('$1','$2')"; }
crear() { run_as "$V" "select crm.crear_lead_si_disponible(p_nombre_completo => 'D13 ALTA $3 r$RUN', p_telefono => '$1', p_origen => 'otro', p_monto_estimado => 1000, p_moneda => 'PEN', p_dni => '$2')"; }
# INSERT directo como el importador / el puente (postgres, sin válvula): los triggers de nacimiento disparan igual (crm.leads tiene grants por columna: authenticated no inserta a mano)
insertar() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D13 INS $3 r$RUN','$2',$4,1000,'landing','nuevo',null,'$V'); commit;" 2>&1; }
tomar() { run_as "$V" "select crm.tomar_lead_libre('$1', ${2:-null})"; }
lead_nuevo() { psql "$PG" -q -c "begin; insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D13 LEAD $2 r$RUN','9${RUN}$2',1000,'landing','nuevo',null,'$V'); commit;" 2>&1 | grep -E "ERROR"; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$1') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','D13 CLIENTE $2 r$RUN','cliente','DNI','$2','$3','$V',true); commit;" 2>&1 | grep -E "ERROR"; }
inv_de() { q "select private.inversionista_por_documento('DNI','$1')"; }
resolver() { q "select private.inversionista_resolver('DNI','$1',true,'ensayo-d13')"; }
puente() { sys "insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values ('$1','$2','$3')"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select to_regprocedure('private.persona_en_conversion(uuid,uuid)') is not null")" == "t" ]] || { echo "falta D-13" >&2; exit 2; }
flag true; flag_inv false
VNOM="$(q "select nombre_completo from public.perfiles where id='$V'")"

echo "== (1) Persona con lead SOLO en el puente (histórico del backfill, sin enlace vivo) =="
IZ="$(resolver "$DZ")"; LH="$(uuid)"; lead_nuevo "$LH" 81 >/dev/null; puente "$IZ" "$LH" historico
[[ "$(q "select count(*) from crm.inversionista_identificadores where inversionista_id='$IZ' and verificado")" == "1" && "$(q "select inversionista_id is null from crm.leads where id='$LH'")" == "t" ]] && ok "fixture: IZ (documento verificado) con LH solo en el puente" || rojo "fixture IZ/LH"
R="$(verificar "9${RUN}91" "$DZ")"; [[ "$(j "$R" estado)" == "ya_es_cliente" && "$(j "$R" via)" == "identidad" ]] && ok "[T1] verificar_disponibilidad_lead(tel nuevo, DNI de IZ) → ya_es_cliente vía identidad" || rojo "T1 puente: $R"
R="$(crear "9${RUN}92" "$DZ" Z)"; [[ "$(j "$R" estado)" == "ya_es_cliente" ]] && ok "[T1] crear_lead_si_disponible con el DNI de IZ → ya_es_cliente (no crea)" || rojo "crear con puente: $(echo "$R" | head -c 200)"
LI="$(uuid)"; R="$(insertar "$LI" "9${RUN}93" Z "'$DZ'")"; echo "$R" | grep -q "P0481" && echo "$R" | grep -q "ya_es_cliente" && echo "$R" | grep -q "$LH" && ok "[T2] INSERT directo con el DNI de IZ → P0481 ya_es_cliente vía identidad, lead_id = LH (el del puente)" || rojo "T2 puente: $(echo "$R" | head -c 260)"
[[ "$(q "select count(*) from crm.leads where id='$LI'")" == "0" ]] && ok "[T2] el lead no nació" || rojo "T2 nació"

echo "== (2) Enlace vivo (regresión) =="
R="$(coop "$L1" "$DY" 1)"; IY="$(inv_de "$DY")"; [[ -n "$IY" && "$(q "select inversionista_id from crm.leads where id='$L1'")" == "$IY" ]] && ok "fixture: IY convertida en coop, enlace vivo en L1" || rojo "IY: $(echo "$R" | head -c 160)"
R="$(verificar "9${RUN}94" "$DY")"; [[ "$(j "$R" estado)" == "ya_es_cliente" && "$(j "$R" via)" == "identidad" ]] && ok "[T1] enlace vivo → ya_es_cliente vía identidad (como hoy)" || rojo "T1 vivo: $R"
LI2="$(uuid)"; R="$(insertar "$LI2" "9${RUN}95" Y "'$DY'")"; echo "$R" | grep -q "P0481" && echo "$R" | grep -q "$L1" && ok "[T2] INSERT con el DNI de IY → P0481 con lead_id = L1 (enlace vivo primero)" || rojo "T2 vivo: $(echo "$R" | head -c 200)"

echo "== (3) La carrera de la saga: reserva por persona de un lead SIN DNI → nadie abre otro lead de esa persona =="
R="$(reservar "$V" "$L2" "$DB" "$(pay "b$RUN@x.pe" B 2)")"; IB="$(j "$R" inversionista_id)"; CLB="$(j "$R" claim_id)"; TKB="$(j "$R" token)"
[[ -n "$IB" && "$(j "$R" estado)" == "reclamado" && "$(q "select count(*) from private.leads_de_identidades(array['$IB'::uuid])")" == "0" ]] && ok "fixture: reserva viva de L2 (sin DNI) para IB; IB sin leads (ni vivo ni puente)" || rojo "reserva L2: $(echo "$R" | head -c 200)"
LI3="$(uuid)"; R="$(insertar "$LI3" "9${RUN}96" B "'$DB'")"; echo "$R" | grep -q "P0481" && echo "$R" | grep -q "ya_es_cliente" && echo "$R" | grep -q "$VNOM" && ok "[T2] INSERT de otro lead con el DNI de IB durante la reserva → P0481 ya_es_cliente, asesor = quien reservó ($VNOM)" || rojo "carrera INSERT: $(echo "$R" | head -c 260)"
R="$(verificar "9${RUN}96" "$DB")"; [[ "$(j "$R" estado)" == "ya_es_cliente" && "$(j "$R" via)" == "identidad" && "$(j "$R" asesor)" == "$VNOM" ]] && ok "[T1] verificar durante la reserva → ya_es_cliente vía identidad, asesor = quien reservó" || rojo "carrera verificar: $R"
R="$(crear "9${RUN}96" "$DB" B)"; [[ "$(j "$R" estado)" == "ya_es_cliente" ]] && ok "[T1] crear_lead_si_disponible durante la reserva → ya_es_cliente" || rojo "carrera crear: $(echo "$R" | head -c 200)"
sys "update crm.conversion_reservas set expira_en = now() - interval '1 minute' where lead_id='$L2'"
R="$(verificar "9${RUN}96" "$DB")"; [[ "$(j "$R" estado)" == "libre" ]] && ok "reserva caducada y NO sellada → la persona vuelve a estar libre (verificar → libre)" || rojo "caducada: $R"
R="$(insertar "$LI3" "9${RUN}96" B "'$DB'")"; [[ "$(q "select inversionista_id from crm.leads where id='$LI3'")" == "$IB" ]] && ok "reserva caducada → el INSERT pasa y el lead nace enlazado a IB" || rojo "caducada INSERT: $(echo "$R" | head -c 200)"
R="$(reservar "$V" "$L3" "$DC" "$(pay "c$RUN@x.pe" C 3)")"; IC="$(j "$R" inversionista_id)"; CLC="$(j "$R" claim_id)"; TKC="$(j "$R" token)"
R="$(run_as "$V" "select crm.marcar_efectos_conversion('$L3','$CLC','$TKC')")"; [[ "$(j "$R" ok)" == "True" ]] && ok "fixture: reserva de L3 para IC SELLADA (efectos iniciados)" || rojo "sellar L3: $(echo "$R" | head -c 200)"
sys "update crm.conversion_reservas set expira_en = now() - interval '1 minute' where lead_id='$L3'"
LI4="$(uuid)"; R="$(insertar "$LI4" "9${RUN}97" C "'$DC'")"; echo "$R" | grep -q "P0481" && ok "[T2] reserva SELLADA con el lead sin convertir bloquea aunque venza la ventana (la cuenta de portal puede existir ya)" || rojo "sellada: $(echo "$R" | head -c 200)"

echo "== (4) tomar_lead_libre: un descartado legado del mismo DNI que una persona con un lead solo en el puente =="
flag false
# descartado VIEJO por el camino real: nace nuevo (bandera apagada: sin enlace), se descarta (el sello estampa hoy) y se retrodata
# con el trigger del sello apagado un instante (banco; trigger NOMBRADO, nunca «disable trigger user»).
LL="$(uuid)"; sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LL','D13 LEGADO r$RUN','9${RUN}88','$DL',1000,'landing','nuevo',null,null)"
sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LL'"
psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); alter table crm.leads disable trigger trg_leads_zz_sello_descarte; update crm.leads set descartado_en = now() - interval '400 days' where id='$LL'; alter table crm.leads enable trigger trg_leads_zz_sello_descarte; commit;" 2>&1 | grep -E "ERROR"
flag true
[[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-')||' '||(descartado_en < now() - interval '300 days')::text from crm.leads where id='$LL'")" == "descartado - true" ]] && ok "fixture: LL descartado legado hace 400 días (DNI $DL) SIN enlace (nació con la bandera apagada)" || rojo "fixture LL: $(q "select etapa, inversionista_id, descartado_en from crm.leads where id='$LL'")"
IL="$(resolver "$DL")"; H="$(uuid)"; lead_nuevo "$H" 89 >/dev/null; puente "$IL" "$H" historico
[[ "$(q "select count(*) from private.leads_de_identidades(array['$IL'::uuid])")" == "1" ]] && ok "fixture: IL (persona de $DL) con el lead H solo en el puente (histórico)" || rojo "fixture IL/H"
R="$(tomar "9${RUN}88" "'$DL'")"; [[ "$(j "$R" estado)" == "ya_es_cliente" && "$(j "$R" via)" == "identidad" ]] && ok "[T3] tomar_lead_libre(tel de LL, DNI) → veredicto ya_es_cliente vía identidad (no se toma)" || rojo "T3 tomar: $(echo "$R" | head -c 200)"
[[ "$(q "select etapa||' '||coalesce(vendedor_id::text,'-') from crm.leads where id='$LL'")" == "descartado -" ]] && ok "[T3] LL intacto (sigue descartado y sin dueño)" || rojo "T3 LL cambió"
R="$(tomar "9${RUN}88")"; [[ "$(j "$R" estado)" == "ya_es_cliente" ]] && ok "[T3] toma por TELÉFONO solo: el DNI del blanco también juzga → ya_es_cliente" || rojo "T3 por teléfono: $(echo "$R" | head -c 200)"
sys "delete from crm.inversionista_leads where inversionista_id='$IL' and lead_id='$H'"
R="$(tomar "9${RUN}88" "'$DL'")"; [[ "$(j "$R" estado)" == "tomado_ok" && "$(q "select etapa||' '||coalesce(vendedor_id::text,'-') from crm.leads where id='$LL'")" == "nuevo $V" ]] && ok "[T3] sin el puente, la misma toma → tomado_ok (LL nuevo, de V): el veredicto era por el puente (par mutante)" || rojo "T3 sin puente: $(echo "$R" | head -c 200) · $(q "select etapa, vendedor_id from crm.leads where id='$LL'")"

echo "== (5) Conversiones: el puente del propio lead manda =="
IZ2="$(resolver "$DZ2")"; LH2="$(uuid)"; lead_nuevo "$LH2" 82 >/dev/null; puente "$IZ2" "$LH2" historico
R="$(coop "$LH2" "$DW2" 5)"; echo "$R" | grep -q "según su puente" && [[ "$(q "select etapa from crm.leads where id='$LH2'")" == "nuevo" ]] && ok "[T5] convertir_lead_externo(LH2, documento de OTRA persona) → P0409 «según su puente», LH2 intacto" || rojo "T5: $(echo "$R" | head -c 220)"
AUW="$(uuid)"; sim_perfil "$AUW" "$DW2" "w$RUN@x.pe"
R="$(run_as "$V" "select crm.convertir_lead('$LH2','$AUW')")"; echo "$R" | grep -q "según su puente" && [[ "$(q "select etapa from crm.leads where id='$LH2'")" == "nuevo" ]] && ok "[T4] convertir_lead(LH2, perfil con documento de OTRA persona) → P0409 «según su puente», LH2 intacto" || rojo "T4: $(echo "$R" | head -c 220)"
R="$(coop "$LH2" "$DZ2" 6)"; [[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LH2'")" == "convertido $IZ2" ]] && ok "[T5] con el documento de SU persona (la del puente) → convierte y enlaza a IZ2" || rojo "T5 positivo: $(echo "$R" | head -c 220)"

echo "== (6) Paridad con la bandera APAGADA =="
flag false
R="$(verificar "9${RUN}98" "$DZ")"; [[ "$(j "$R" estado)" == "libre" ]] && ok "OFF: verificar con el DNI de IZ → libre (la rama de identidad no corre)" || rojo "OFF verificar: $R"
LI5="$(uuid)"; R="$(insertar "$LI5" "9${RUN}98" Z "'$DZ'")"; [[ "$(q "select count(*) from crm.leads where id='$LI5' and inversionista_id is null")" == "1" ]] && ok "OFF: el INSERT con el DNI de IZ pasa, sin enlace (como hoy)" || rojo "OFF INSERT: $(echo "$R" | head -c 200)"
R="$(coop "$LI5" "$DW2" 7)"; [[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LI5'")" == "convertido -" ]] && ok "OFF: conversión coop como hoy (sin identidad)" || rojo "OFF coop: $(echo "$R" | head -c 200)"

psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false; flag_inv false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b D-13: VERDE — un solo lead (enlace vivo ∪ puente) y persona en conversión en el verificador, el nacimiento del lead y la toma; el puente del propio lead manda en las conversiones; paridad apagada."; exit 0
else echo "ORÁCULO F2.b D-13: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
