#!/usr/bin/env bash
# ORÁCULO F2.b [D-13] — «un solo lead» y «el puente manda» en TODAS las puertas con la bandera encendida — SOLO en el BANCO.
# Presupone b1..b5 (+ D-10 opcional) y D-13, y la siembra siembra-banco-f3.sql (actores V/S/G, leads L1..L5 sin DNI).
# Presupone D-10 aplicada (D-13 transforma la reserva tal como la deja D-10).
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d13.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
L1="f31ead00-0000-0000-0000-${RUN}000001"; L2="f31ead00-0000-0000-0000-${RUN}000002"; L3="f31ead00-0000-0000-0000-${RUN}000003"
DZ="2${RUN}1"; DY="2${RUN}2"; DB="2${RUN}3"; DC="2${RUN}4"; DL="2${RUN}5"; DZ2="2${RUN}6"; DW2="2${RUN}7"; DX="2${RUN}8"; DL2="2${RUN}9"; DE="1${RUN}1"; DR="1${RUN}2"; DD="1${RUN}3"; DU="1${RUN}4"; DU2="1${RUN}5"; DU3="1${RUN}6"; DS="1${RUN}7"; DS3="1${RUN}8"; DP6="1${RUN}9"; DH="0${RUN}1"; DN9="0${RUN}2"; DA4="0${RUN}3"; DB4="0${RUN}4"; DX5="0${RUN}5"; DY5="0${RUN}6"; DU4="0${RUN}7"; DF1="0${RUN}8"; DF2="0${RUN}9"; DF3="3${RUN}0"; DV1="4${RUN}6"; DI2="4${RUN}7"; DP4="4${RUN}8"; DNV="4${RUN}9"
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR" ; }
flag() { local i; for i in 1 2 3 4 5; do psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null 2>&1; [[ "$(psql "$PG" -qtA -c "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'" 2>/dev/null)" == "$( [[ "$1" == "true" ]] && echo t || echo f )" ]] && return 0; echo "  (bandera: reintento $i)"; sleep 3; done; echo "  ❌ bandera: no se pudo poner en $1" >&2; ROJO=$((ROJO+1)); }
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
sellar() { run_as "$V" "select crm.marcar_efectos_conversion('$1','$2','$3')"; }
fijar() { run_as "$V" "select crm.fijar_dni_lead_fn('$1', ${2:-null})"; }
rescatar() { run_as "$G" "select crm.rescatar_descartes(array['$1']::uuid[], array['$V']::uuid[], false)"; }
deshacer() { run_as "$G" "select crm.deshacer_descarte('$1')"; }
lead_off() { flag false; sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D13 $3 r$RUN','9${RUN}$2','$4',1000,'landing','nuevo',null,${5:-null})"; flag true; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
if [[ "$(q "select to_regprocedure('private.persona_en_conversion(uuid,uuid)') is not null")" == "t" ]]; then echo "  D-13 instalada (todo debe salir VERDE)"; else echo "  ⚠️ D-13 NO instalada: corrida MUTANTE (T1..T5 deben salir ROJOS)"; fi
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
R="$(sellar "$L2" "$CLB" "$TKB")"; echo "$R" | grep -q "no se sella" && [[ "$(q "select efectos_iniciados_en is null from crm.conversion_reservas where lead_id='$L2'")" == "t" ]] && ok "[T6 Codex #1] sellar la reserva de L2 después de que naciera otro lead de IB → P0409 «no se sella» (sin cuenta de portal huérfana)" || rojo "T6 sellado: $(echo "$R" | head -c 200)"
R="$(verificar "9${RUN}96" "$DB")"; [[ "$(j "$R" estado)" == "ya_es_cliente" && "$(j "$R" asesor)" != "$VNOM" ]] && ok "[T1 auditor N3] con la reserva caducada, «asesor» ya no es quien reservó (es el responsable o el centinela)" || rojo "N3: $R"
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
R="$(tomar "9${RUN}88" "'$DX'")"; [[ "$(j "$R" estado)" == "ya_es_cliente" ]] && ok "[T3 Codex #3] DNI tecleado DISTINTO y sin dueño: el DNI del blanco también se juzga → ya_es_cliente" || rojo "T3 dos documentos: $(echo "$R" | head -c 200)"
sys "delete from crm.inversionista_leads where inversionista_id='$IL' and lead_id='$H'"
R="$(tomar "9${RUN}88" "'$DL'")"; [[ "$(j "$R" estado)" == "tomado_ok" && "$(q "select etapa||' '||coalesce(vendedor_id::text,'-') from crm.leads where id='$LL'")" == "nuevo $V" ]] && ok "[T3] sin el puente, la misma toma → tomado_ok (LL nuevo, de V): el veredicto era por el puente (par mutante)" || rojo "T3 sin puente: $(echo "$R" | head -c 200) · $(q "select etapa, vendedor_id from crm.leads where id='$LL'")"
[[ "$(q "select inversionista_id from crm.leads where id='$LL'")" == "$IL" && "$(q "select count(*) from crm.inversionista_leads where lead_id='$LL' and inversionista_id='$IL' and rol='canonico'")" == "1" ]] && ok "[T3 Codex #5] al tomarse, LL quedó ENLAZADO a IL con puente canónico (visible a reserva, sellado y conversiones)" || rojo "T3 enlace al tomar: $(q "select inversionista_id from crm.leads where id='$LL'")"
LL2="$(uuid)"; lead_off "$LL2" 87 LEGADO2 "$DL2"; sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LL2'"; psql "$PG" -q -c "begin; alter table crm.leads disable trigger trg_leads_zz_sello_descarte; update crm.leads set descartado_en = now() - interval '400 days' where id='$LL2'; alter table crm.leads enable trigger trg_leads_zz_sello_descarte; commit;" >/dev/null 2>&1
AUL="$(uuid)"; sim_perfil "$AUL" "$DL2" "l2$RUN@x.pe"
R="$(tomar "9${RUN}87")"; [[ "$(j "$R" estado)" == "ya_es_cliente" && "$(q "select etapa from crm.leads where id='$LL2'")" == "descartado" ]] && ok "[T3 Codex #4] blanco cuyo DNI es de un CLIENTE del Portal (ya_es_cliente sin vía) → no se toma" || rojo "T3 sin vía: $(echo "$R" | head -c 200)"

echo "== (5) Conversiones: el puente del propio lead manda =="
IZ2="$(resolver "$DZ2")"; LH2="$(uuid)"; lead_nuevo "$LH2" 82 >/dev/null; puente "$IZ2" "$LH2" historico
R="$(coop "$LH2" "$DW2" 5)"; echo "$R" | grep -q "según su puente" && [[ "$(q "select etapa from crm.leads where id='$LH2'")" == "nuevo" ]] && ok "[T5] convertir_lead_externo(LH2, documento de OTRA persona) → P0409 «según su puente», LH2 intacto" || rojo "T5: $(echo "$R" | head -c 220)"
AUW="$(uuid)"; sim_perfil "$AUW" "$DW2" "w$RUN@x.pe"
R="$(run_as "$V" "select crm.convertir_lead('$LH2','$AUW')")"; echo "$R" | grep -q "según su puente" && [[ "$(q "select etapa from crm.leads where id='$LH2'")" == "nuevo" ]] && ok "[T4] convertir_lead(LH2, perfil con documento de OTRA persona) → P0409 «según su puente», LH2 intacto" || rojo "T4: $(echo "$R" | head -c 220)"
R="$(coop "$LH2" "$DZ2" 6)"; [[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LH2'")" == "convertido $IZ2" ]] && ok "[T5] con el documento de SU persona (la del puente) → convierte y enlaza a IZ2" || rojo "T5 positivo: $(echo "$R" | head -c 220)"
L4="f31ead00-0000-0000-0000-${RUN}000004"; R="$(reservar "$V" "$L4" "$DE" "$(pay "e$RUN@x.pe" E 4)")"; [[ "$(j "$R" estado)" == "reclamado" ]] && ok "fixture: reserva viva de L4 (sin DNI) para la persona de $DE" || rojo "reserva L4: $(echo "$R" | head -c 160)"
R="$(run_as "$V" "select crm.convertir_lead('$L4','$AUW')")"; echo "$R" | grep -q "reservado para otra persona" && [[ "$(q "select etapa from crm.leads where id='$L4'")" == "nuevo" ]] && ok "[T4 Codex #2] convertir_lead directo de un lead reservado para OTRA persona → P0409, L4 intacto" || rojo "T4 reserva ajena: $(echo "$R" | head -c 220)"
echo "== (7) Reactivaciones: rescate de supervisión y deshacer descarte =="
LR="$(uuid)"; lead_off "$LR" 86 RESCATE "$DR" "'$V'"; run_as "$V" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LR'" >/dev/null
EP="$(q "select la.id from crm.lead_asignaciones la where la.lead_id='$LR' and la.resultado='descartado' order by la.resultado_en desc limit 1")"; IR="$(resolver "$DR")"; HR="$(uuid)"; lead_nuevo "$HR" 79 >/dev/null; puente "$IR" "$HR" historico
[[ -n "$EP" && "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LR'")" == "descartado -" ]] && ok "fixture: LR descartado con episodio (DNI $DR, sin enlace); IR con HR solo en el puente" || rojo "fixture LR/EP: EP=$EP"
R="$(rescatar "$EP")"; echo "$R" | grep -q "ya es cliente o ya tiene su lead" && [[ "$(q "select etapa from crm.leads where id='$LR'")" == "descartado" ]] && ok "[T7 auditor M1] rescatar_descartes → P0409 (persona con lead en el puente), LR sigue descartado" || rojo "T7 rescatar: $(echo "$R" | head -c 220)"
sys "delete from crm.inversionista_leads where inversionista_id='$IR' and lead_id='$HR'"
R="$(rescatar "$EP")"; [[ "$(j "$R" rescatados)" == "1" && "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LR'")" == "nuevo $IR" && "$(q "select count(*) from crm.inversionista_leads where lead_id='$LR' and rol='canonico'")" == "1" ]] && ok "[T7] sin el puente, el rescate reabre LR y lo ENLAZA a IR (puente canónico)" || rojo "T7 rescate positivo: $(echo "$R" | head -c 200) · $(q "select etapa, inversionista_id from crm.leads where id='$LR'")"
LD="$(uuid)"; lead_off "$LD" 85 DESHACER "$DD"; R="$(run_as "$G" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LD'")"; ID="$(resolver "$DD")"; HD="$(uuid)"; lead_nuevo "$HD" 78 >/dev/null; puente "$ID" "$HD" historico
[[ "$(q "select etapa||' '||coalesce(descartado_por::text,'-') from crm.leads where id='$LD'")" == "descartado $G" ]] && ok "fixture: LD descartado por G hace un instante (DNI $DD, sin enlace); ID con HD solo en el puente" || rojo "fixture LD: $(q "select etapa, descartado_por from crm.leads where id='$LD'") $(echo "$R" | head -c 120)"
R="$(deshacer "$LD")"; echo "$R" | grep -q "ya es cliente o ya tiene su lead" && [[ "$(q "select etapa from crm.leads where id='$LD'")" == "descartado" ]] && ok "[T8 auditor M1] deshacer_descarte → P0409 (persona con lead en el puente), LD sigue descartado" || rojo "T8 deshacer: $(echo "$R" | head -c 220)"
sys "delete from crm.inversionista_leads where inversionista_id='$ID' and lead_id='$HD'"
R="$(deshacer "$LD")"; [[ "$(j "$R" etapa)" == "nuevo" && "$(q "select inversionista_id from crm.leads where id='$LD'")" == "$ID" ]] && ok "[T8] sin el puente, deshacer reabre LD y lo ENLAZA a ID" || rojo "T8 deshacer positivo: $(echo "$R" | head -c 200)"
echo "== (8) UPDATE de DNI de un lead solo-puente =="
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; update crm.leads set dni='$DU' where id='$LH'; commit;" 2>&1)"; echo "$R" | grep -q "P0409" && [[ "$(q "select dni is null from crm.leads where id='$LH'")" == "t" ]] && ok "[T2 Codex #7] cambiar el DNI de un lead que está en un puente → P0409 «solo Gerencia lo corrige», DNI intacto" || rojo "UPDATE dni solo-puente: $(echo "$R" | head -c 200)"

echo "== (9) Refutación de Codex sobre la v2.1: sueltos por documento, UPDATE directo, puente sin DNI, sellado, cliente inactivo =="
# #1 — un lead SUELTO vivo con DNI (nació con la bandera apagada, antes de que existiera la persona) cuenta por documento
LS3="$(uuid)"; lead_off "$LS3" 71 SUELTO "$DS3" "'$V'"
IS3="$(resolver "$DS3")"; LO="$(uuid)"; lead_nuevo "$LO" 72 >/dev/null
[[ "$(q "select inversionista_id is null from crm.leads where id='$LS3'")" == "t" && "$(q "select count(*) from private.leads_de_personas(array['$IS3'::uuid])")" == "1" ]] && ok "fixture: LS3 vivo con DNI $DS3 y SIN enlace (nació apagada); la persona nace después y lo cuenta por documento" || rojo "fixture LS3"
R="$(reservar "$V" "$LO" "$DS3" "$(pay "s$RUN@x.pe" S 3)")"; echo "$R" | grep -q "ya tiene su lead" && echo "$R" | grep -q "$LS3" && ok "[#1] reservar OTRO lead con el DNI de un suelto vivo → P0409, lead_id = el suelto (T9, reserva de D-10 por documento)" || rojo "#1 reserva por documento: $(echo "$R" | head -c 200)"
R="$(coop "$LO" "$DS3" 9)"; echo "$R" | grep -q "ya tiene un lead" && [[ "$(q "select etapa from crm.leads where id='$LO'")" == "nuevo" ]] && ok "[#1] convertir_lead_externo de otro lead con ese DNI → P0409 (T5 por documento)" || rojo "#1 coop: $(echo "$R" | head -c 200)"
R="$(coop "$LS3" "$DS3" 8)"; [[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LS3'")" == "convertido $IS3" ]] && ok "[#1] el propio suelto sí convierte (queda enlazado a su persona)" || rojo "#1 suelto convierte: $(echo "$R" | head -c 200)"
# T6 por documento: reserva en curso y un suelto vivo con el DNI nacido con la bandera apagada → no se sella
LS5="$(uuid)"; lead_nuevo "$LS5" 73 >/dev/null; R="$(reservar "$V" "$LS5" "$DS" "$(pay "t$RUN@x.pe" T 5)")"; CLS="$(j "$R" claim_id)"; TKS="$(j "$R" token)"
LS6="$(uuid)"; lead_off "$LS6" 74 SUELTO2 "$DS" "'$V'"
R="$(sellar "$LS5" "$CLS" "$TKS")"; echo "$R" | grep -q "no se sella" && ok "[#1/#3 T6] sellar con un suelto vivo del mismo DNI (nacido apagada) → P0409 «no se sella»: sin cuenta huérfana" || rojo "T6 por documento: $(echo "$R" | head -c 200)"
# #7 — UPDATE directo de etapa (Gerencia) con la bandera encendida → solo por RPC
LD3="$(uuid)"; lead_off "$LD3" 75 DIRECTO "$DU4"; sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LD3'"
R="$(run_as "$G" "update crm.leads set etapa='nuevo', motivo_descarte=null where id='$LD3'")"; echo "$R" | grep -q "solo por sus puertas" && [[ "$(q "select etapa from crm.leads where id='$LD3'")" == "descartado" ]] && ok "[#7] UPDATE directo descartado→nuevo (Gerencia) → P0409 «solo por sus puertas», sigue descartado" || rojo "#7 UPDATE directo: $(echo "$R" | head -c 200)"
sys "update crm.leads set etapa='nuevo', motivo_descarte=null where id='$LD3'"; [[ "$(q "select etapa from crm.leads where id='$LD3'")" == "nuevo" ]] && ok "[#7] bajo válvula (Gerencia privilegiada) sí pasa" || rojo "#7 válvula"
# #6 — puente conocido sin DNI: descartado sin DNI con puente histórico a una persona que ya tiene su lead canónico
IP6="$(resolver "$DP6")"; LP1="$(uuid)"; psql "$PG" -q -c "begin; insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LP1','D13 CANON r$RUN','9${RUN}76','$DP6',1000,'landing','nuevo',null,'$V'); commit;" 2>&1 | grep ERROR
LP2="$(uuid)"; lead_nuevo "$LP2" 77 >/dev/null; run_as "$V" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LP2'" >/dev/null; psql "$PG" -q -c "begin; alter table crm.leads disable trigger trg_leads_zz_sello_descarte; update crm.leads set descartado_en = now() - interval '400 days' where id='$LP2'; alter table crm.leads enable trigger trg_leads_zz_sello_descarte; commit;" >/dev/null 2>&1; puente "$IP6" "$LP2" historico
[[ "$(q "select inversionista_id from crm.leads where id='$LP1'")" == "$IP6" && "$(q "select dni is null and etapa='descartado' from crm.leads where id='$LP2'")" == "t" ]] && ok "fixture: IP6 con LP1 canónico (enlazado al nacer) y LP2 descartado SIN DNI solo en el puente" || rojo "fixture #6"
R="$(tomar "9${RUN}77")"; [[ "$(j "$R" estado)" == "ya_es_cliente" && "$(q "select etapa from crm.leads where id='$LP2'")" == "descartado" ]] && ok "[#6] tomar LP2 (sin DNI, por teléfono): el PUENTE identifica a la persona, que ya tiene LP1 → ya_es_cliente, no se toma" || rojo "#6 tomar: $(echo "$R" | head -c 200)"
LP3="$(uuid)"; sys "insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LP3','D13 PUENTE-SIN-DNI r$RUN','9${RUN}70',1000,'landing','nuevo',null,null)"; run_as "$G" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LP3'" >/dev/null; puente "$IP6" "$LP3" historico
R="$(deshacer "$LP3")"; echo "$R" | grep -q "ya es cliente o ya tiene su lead" && ok "[#6] deshacer un descartado sin DNI con puente a persona que ya tiene lead → P0409" || rojo "#6 deshacer: $(echo "$R" | head -c 220)"
# Codex 13 — el puente histórico del propio lead pasa a canónico al enlazar (persona sin otro canónico)
IH="$(resolver "$DH")"; LH3="$(uuid)"; lead_off "$LH3" 69 HIST "$DH"; sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LH3'"; psql "$PG" -q -c "begin; alter table crm.leads disable trigger trg_leads_zz_sello_descarte; update crm.leads set descartado_en = now() - interval '400 days' where id='$LH3'; alter table crm.leads enable trigger trg_leads_zz_sello_descarte; commit;" >/dev/null 2>&1; puente "$IH" "$LH3" historico
R="$(tomar "9${RUN}69" "'$DH'")"; [[ "$(j "$R" estado)" == "tomado_ok" && "$(q "select inversionista_id from crm.leads where id='$LH3'")" == "$IH" && "$(q "select rol from crm.inversionista_leads where lead_id='$LH3'")" == "canonico" ]] && ok "[Codex 13] tomar el único lead (histórico) de la persona → tomado_ok, ENLAZADO y su puente pasa a canónico" || rojo "Codex 13: $(echo "$R" | head -c 200) · $(q "select inversionista_id, (select rol from crm.inversionista_leads where lead_id='$LH3') from crm.leads where id='$LH3'")"
# Codex 9 — cliente INACTIVO: la persona tiene perfil (activo=false); su descartado no se reabre
IN9="$(resolver "$DN9")"; AU9="$(uuid)"; sim_perfil "$AU9" "$DN9" "n9$RUN@x.pe"; sys "update public.perfiles set activo=false where id='$AU9'"; sys "update crm.inversionistas set perfil_id='$AU9' where id='$IN9'"
LN9="$(uuid)"; lead_off "$LN9" 68 INACTIVO "$DN9"; sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LN9'"; psql "$PG" -q -c "begin; alter table crm.leads disable trigger trg_leads_zz_sello_descarte; update crm.leads set descartado_en = now() - interval '400 days' where id='$LN9'; alter table crm.leads enable trigger trg_leads_zz_sello_descarte; commit;" >/dev/null 2>&1
R="$(tomar "9${RUN}68")"; [[ "$(j "$R" estado)" == "ya_es_cliente" && "$(q "select etapa from crm.leads where id='$LN9'")" == "descartado" ]] && ok "[Codex 9] descartado de una persona que ya es cliente (perfil INACTIVO) → ya_es_cliente, no se toma" || rojo "Codex 9: $(echo "$R" | head -c 200)"
# #4 — reserva caducada, conversión directa para OTRA persona, y luego el sellado con el claim viejo
LA4="$(uuid)"; lead_nuevo "$LA4" 67 >/dev/null; R="$(reservar "$V" "$LA4" "$DA4" "$(pay "a4$RUN@x.pe" A4 7)")"; CLA4="$(j "$R" claim_id)"; TKA4="$(j "$R" token)"
sys "update crm.conversion_reservas set expira_en = now() - interval '1 minute' where lead_id='$LA4'"; AUB4="$(uuid)"; sim_perfil "$AUB4" "$DB4" "b4$RUN@x.pe"
R="$(run_as "$V" "select crm.convertir_lead('$LA4','$AUB4')")"; [[ "$(q "select etapa from crm.leads where id='$LA4'")" == "convertido" ]] && ok "fixture #4: con la reserva caducada, convertir_lead directo para OTRA persona pasa (hoy)" || rojo "fixture #4: $(echo "$R" | head -c 200)"
R="$(sellar "$LA4" "$CLA4" "$TKA4")"; echo "$R" | grep -q -E "no está disponible para esta conversión|no se sella|cambió mientras se sellaba|ya no esta viva" && ok "[#4 T6] sellar con el claim viejo un lead ya convertido para otra persona → rechazado (sin Auth)" || rojo "#4 sellar: $(echo "$R" | head -c 200)"
# #5 — reserva reemplazada por otra persona (caducada la primera) → el claim viejo no sella la reserva nueva
LX5="$(uuid)"; lead_nuevo "$LX5" 66 >/dev/null; R="$(reservar "$V" "$LX5" "$DX5" "$(pay "x5$RUN@x.pe" X5 6)")"; CLX="$(j "$R" claim_id)"; TKX="$(j "$R" token)"
sys "update crm.conversion_reservas set expira_en = now() - interval '1 minute' where lead_id='$LX5'"
R="$(reservar "$V" "$LX5" "$DY5" "$(pay "y5$RUN@x.pe" Y5 5)")"; [[ "$(j "$R" estado)" == "reclamado" ]] && ok "fixture #5: la reserva caducada de LX5 se reemplaza por otra persona" || rojo "fixture #5: $(echo "$R" | head -c 200)"
R="$(sellar "$LX5" "$CLX" "$TKX")"; echo "$R" | grep -q -E "cambió mientras se sellaba|no corresponde a este claim|claim o token inválidos" && [[ "$(q "select efectos_iniciados_en is null from crm.conversion_reservas where lead_id='$LX5'")" == "t" ]] && ok "[#5 T6] sellar con el claim de la reserva anterior → rechazado; la reserva nueva sigue sin sellar" || rojo "#5 sellar: $(echo "$R" | head -c 200)"
echo "== (10) Refutación de Codex sobre la v3.1: puerta del DNI, sellado (DNI/token), conversión en curso en otro lead, veto por puente, cliente inactivo, documento no verificado =="
# B1 — el DNI de un lead se fija por su puerta
LF="$(uuid)"; lead_nuevo "$LF" 65 >/dev/null
R="$(run_as "$V" "update crm.leads set dni='$DF1' where id='$LF'")"; echo "$R" | grep -q "por su puerta" && [[ "$(q "select dni is null from crm.leads where id='$LF'")" == "t" ]] && ok "[B1] UPDATE directo de dni con la bandera encendida → P0409 «por su puerta», DNI intacto" || rojo "B1 UPDATE directo: $(echo "$R" | head -c 200)"
R="$(fijar "$LF" "'$DF1'")"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" enlazado)" == "False" && "$(q "select dni||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LF'")" == "$DF1 -" ]] && ok "[B1] fijar_dni_lead_fn con un DNI sin persona → ok, sin enlace" || rojo "B1 fijar libre: $(echo "$R" | head -c 200)"
IF2="$(resolver "$DF2")"; LF2="$(uuid)"; lead_nuevo "$LF2" 64 >/dev/null
R="$(fijar "$LF2" "'$DF2'")"; [[ "$(j "$R" enlazado)" == "True" && "$(q "select inversionista_id from crm.leads where id='$LF2'")" == "$IF2" && "$(q "select count(*) from crm.inversionista_leads where lead_id='$LF2' and rol='canonico'")" == "1" ]] && ok "[B1] fijar el DNI de una persona reconocida SIN otro lead → ok y ENLAZADO con puente canónico" || rojo "B1 fijar enlaza: $(echo "$R" | head -c 200)"
LF3="$(uuid)"; lead_nuevo "$LF3" 63 >/dev/null
R="$(fijar "$LF3" "'$DF2'")"; echo "$R" | grep -q "ya es cliente o ya tiene su lead" && [[ "$(q "select dni is null from crm.leads where id='$LF3'")" == "t" ]] && ok "[B1] fijar el DNI de una persona que YA tiene su lead → P0409, DNI intacto" || rojo "B1 fijar persona con lead: $(echo "$R" | head -c 200)"
R="$(fijar "$LF2" "'$DF3'")"; echo "$R" | grep -q "solo lo corrige Gerencia" && ok "[B1] cambiar el DNI de un lead ya enlazado por la puerta → P0409 (corrección de Gerencia)" || rojo "B1 enlazado: $(echo "$R" | head -c 200)"
# B2 — el DNI de un lead con reserva en curso no se cambia; el sellado exige que el DNI actual sea el de la persona
LB2="$(uuid)"; lead_nuevo "$LB2" 62 >/dev/null; R="$(reservar "$V" "$LB2" "$DP4" "$(pay "p4$RUN@x.pe" P4 3)")"; CLP="$(j "$R" claim_id)"; TKP="$(j "$R" token)"
R="$(fijar "$LB2" "'$DF3'")"; echo "$R" | grep -q "conversión en curso" && ok "[B2] fijar otro DNI en un lead con reserva viva → P0409 «conversión en curso»" || rojo "B2 fijar con reserva: $(echo "$R" | head -c 200)"
sys "update crm.leads set dni='$DF3' where id='$LB2'"
R="$(sellar "$LB2" "$CLP" "$TKP")"; echo "$R" | grep -q "con otro documento" && [[ "$(q "select efectos_iniciados_en is null from crm.conversion_reservas where lead_id='$LB2'")" == "t" ]] && ok "[B2 T6] si el DNI del lead ya no es el de la persona reservada (cambiado bajo válvula) → no se sella" || rojo "B2 sellar: $(echo "$R" | head -c 200)"
# B4 — conversión directa de OTRO lead de la persona mientras su saga (sellada) sigue abierta
LA5="$(uuid)"; lead_nuevo "$LA5" 61 >/dev/null; R="$(reservar "$V" "$LA5" "$DI2" "$(pay "i2$RUN@x.pe" I2 2)")"; CLI="$(j "$R" claim_id)"; TKI="$(j "$R" token)"; II2="$(j "$R" inversionista_id)"
R="$(sellar "$LA5" "$CLI" "$TKI")"; [[ "$(j "$R" ok)" == "True" ]] && ok "fixture B4: LA5 reservada y SELLADA para la persona de $DI2" || rojo "fixture B4: $(echo "$R" | head -c 160)"
AUI="$(uuid)"; sim_perfil "$AUI" "$DI2" "i2$RUN@x.pe"; LB5="$(uuid)"; lead_nuevo "$LB5" 60 >/dev/null
R="$(run_as "$V" "select crm.convertir_lead('$LB5','$AUI')")"; echo "$R" | grep -q "en curso en otro lead" && [[ "$(q "select etapa from crm.leads where id='$LB5'")" == "nuevo" ]] && ok "[B4 T4] convertir_lead directo de OTRO lead hacia el perfil de la persona con saga abierta → P0409 «en curso en otro lead»" || rojo "B4: $(echo "$R" | head -c 200)"
# M1 — persona vetada hallada solo por puente: no se reabre
IV1="$(resolver "$DV1")"; sys "update crm.inversionistas set no_contactar=true, no_contactar_en=now(), no_contactar_por='$G' where id='$IV1'"
LV1="$(uuid)"; lead_nuevo "$LV1" 59 >/dev/null; run_as "$V" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LV1'" >/dev/null; psql "$PG" -q -c "begin; alter table crm.leads disable trigger trg_leads_zz_sello_descarte; update crm.leads set descartado_en = now() - interval '400 days' where id='$LV1'; alter table crm.leads enable trigger trg_leads_zz_sello_descarte; commit;" >/dev/null 2>&1; puente "$IV1" "$LV1" historico
R="$(tomar "9${RUN}59")"; [[ "$(j "$R" estado)" == "no_contactar" && "$(q "select etapa from crm.leads where id='$LV1'")" == "descartado" ]] && ok "[M1] tomar un descartado SIN DNI cuyo puente lleva a una persona VETADA → veredicto no_contactar, no se toma" || rojo "M1: $(echo "$R" | head -c 200)"
# M2 — cliente del Portal INACTIVO sin ficha de persona: su descartado no se retoma; INSERT para una persona que ya es cliente → P0481
AUX2="$(uuid)"; sim_perfil "$AUX2" "$DNV" "nv$RUN@x.pe"; sys "update public.perfiles set activo=false where id='$AUX2'"
LX2="$(uuid)"; lead_off "$LX2" 58 INACTIVO2 "$DNV"; sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LX2'"; psql "$PG" -q -c "begin; alter table crm.leads disable trigger trg_leads_zz_sello_descarte; update crm.leads set descartado_en = now() - interval '400 days' where id='$LX2'; alter table crm.leads enable trigger trg_leads_zz_sello_descarte; commit;" >/dev/null 2>&1
R="$(tomar "9${RUN}58")"; [[ "$(j "$R" estado)" == "ya_es_cliente" && "$(q "select etapa from crm.leads where id='$LX2'")" == "descartado" ]] && ok "[M2] descartado con el DNI de un cliente INACTIVO sin ficha → ya_es_cliente, no se toma" || rojo "M2 tomar: $(echo "$R" | head -c 200)"
LI9="$(uuid)"; R="$(insertar "$LI9" "9${RUN}57" N9 "'$DN9'")"; echo "$R" | grep -q "P0481" && echo "$R" | grep -q "ya_es_cliente" && ok "[M2 T2] INSERT de un lead para una persona que ya es cliente (perfil enlazado, sin otros leads) → P0481 ya_es_cliente" || rojo "M2 INSERT: $(echo "$R" | head -c 200)"
# M3 — un identificador NO verificado no atribuye sueltos: convertir otro lead de esa persona por su documento verificado pasa
# (el resolver nunca crea identidades sin verificar —Codex v4.1—: se crea verificada y se desverifica bajo válvula, como quedaría un identificador degradado)
INV="$(resolver "$DF3")"; sys "update crm.inversionista_identificadores set verificado=false where inversionista_id='$INV' and documento_normalizado='$DF3'"; [[ -n "$INV" && "$(q "select verificado from crm.inversionista_identificadores where inversionista_id='$INV' and documento_normalizado='$DF3'")" == "f" ]] && ok "fixture M3: persona con DNI $DF3 NO verificado (desverificado bajo válvula); LB2 (suelto vivo) lleva ese DNI" || rojo "fixture M3: INV=$INV"
[[ "$(q "select count(*) from private.leads_de_personas(array['$INV'::uuid])")" == "0" ]] && ok "[M3] leads_de_personas no atribuye el suelto por un documento no verificado (alineado con el resolver)" || rojo "M3: $(q "select count(*) from private.leads_de_personas(array['$INV'::uuid])")"
echo "== (11) Helpers directos (auditor v4.3 N2) y guarda de aislamiento (Codex v4.3 [2]) =="
LXB="$(uuid)"; DXB="4${RUN}1"; lead_off "$LXB" 45 XB "$DXB" "'$V'"; PXB="$(resolver "$DXB")"
[[ -n "$PXB" && "$(q "select private.lead_persona_reabrir('$LXB'::uuid)")" == "$PXB" ]] && ok "fixture: LXB vivo (de V) con DNI $DXB nacido apagado; su persona PXB se resuelve por documento" || rojo "fixture XB: $PXB"
[[ "$(q "select private.lead_dentro_de_bloqueo('$LXB', jsonb_build_object('claves', jsonb_build_array('DNI:$DXB'), 'personas', jsonb_build_array('$PXB')))")" == "t" ]] && ok "[N2] lead con DNI A y bloqueo {DNI:A, PXB} → dentro" || rojo "N2 dentro"
[[ "$(q "select private.lead_dentro_de_bloqueo('$LXB', jsonb_build_object('claves', jsonb_build_array('DNI:4${RUN}2'), 'personas', jsonb_build_array('$PXB')))")" == "f" ]] && ok "[N2] bloqueo con OTRO documento (el ABA A→B→A) → fuera" || rojo "N2 ABA"
[[ "$(q "select private.lead_dentro_de_bloqueo('$LXB', jsonb_build_object('claves', jsonb_build_array('DNI:$DXB'), 'personas', '[]'::jsonb))")" == "f" ]] && ok "[N2] persona no bloqueada → fuera" || rojo "N2 persona"
LYB="$(uuid)"; lead_nuevo "$LYB" 46
[[ "$(q "select private.lead_dentro_de_bloqueo('$LYB', jsonb_build_object('claves', '[]'::jsonb, 'personas', '[]'::jsonb))")" == "t" ]] && ok "[N2] lead sin DNI ni persona con bloqueo vacío → dentro (no hay carrera por documento)" || rojo "N2 vacío"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -c "begin isolation level repeatable read; select private.bloquear_personas_de_leads(array['$LXB']::uuid[], null); rollback;" 2>&1)"; echo "$R" | grep -q "READ COMMITTED" && ok "[Codex v4.3 #2] bloquear_personas_de_leads en REPEATABLE READ → 0A000 (requiere READ COMMITTED)" || rojo "aislamiento helper: $(echo "$R" | head -c 200)"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin isolation level repeatable read; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$V\",\"role\":\"authenticated\"}', true); select crm.fijar_dni_lead_fn('$LXB', '4${RUN}3'); rollback;" 2>&1)"; echo "$R" | grep -q "READ COMMITTED" && [[ "$(q "select dni from crm.leads where id='$LXB'")" == "$DXB" ]] && ok "[Codex v4.3 #2] la puerta del DNI en REPEATABLE READ → 0A000 y el DNI queda intacto" || rojo "aislamiento puerta: $(echo "$R" | head -c 200)"

echo "== (6) Paridad con la bandera APAGADA =="
flag false
R="$(verificar "9${RUN}98" "$DZ")"; [[ "$(j "$R" estado)" == "libre" ]] && ok "OFF: verificar con el DNI de IZ → libre (la rama de identidad no corre)" || rojo "OFF verificar: $R"
LI5="$(uuid)"; R="$(insertar "$LI5" "9${RUN}98" Z "'$DZ'")"; [[ "$(q "select count(*) from crm.leads where id='$LI5' and inversionista_id is null")" == "1" ]] && ok "OFF: el INSERT con el DNI de IZ pasa, sin enlace (como hoy)" || rojo "OFF INSERT: $(echo "$R" | head -c 200)"
R="$(coop "$LI5" "$DW2" 7)"; [[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LI5'")" == "convertido -" ]] && ok "OFF: conversión coop como hoy (sin identidad)" || rojo "OFF coop: $(echo "$R" | head -c 200)"
# OFF: tomar / deshacer reabren SIN enlazar (auditor N1); DNIs frescos: el índice de DNI de vivos no admite dos leads vivos con el mismo DNI
LL3="$(uuid)"; sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LL3','D13 LEGADO3 r$RUN','9${RUN}84','$DU2',1000,'landing','nuevo',null,null)"; sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LL3'"; psql "$PG" -q -c "begin; alter table crm.leads disable trigger trg_leads_zz_sello_descarte; update crm.leads set descartado_en = now() - interval '400 days' where id='$LL3'; alter table crm.leads enable trigger trg_leads_zz_sello_descarte; commit;" >/dev/null 2>&1
R="$(tomar "9${RUN}84" "'$DU2'")"; [[ "$(j "$R" estado)" == "tomado_ok" && "$(q "select inversionista_id is null from crm.leads where id='$LL3'")" == "t" && "$(q "select count(*) from crm.inversionista_leads where lead_id='$LL3'")" == "0" ]] && ok "OFF: tomar un descartado viejo con DNI → tomado_ok SIN enlace ni puente (como hoy; la rama de identidad no corre)" || rojo "OFF tomar: $(echo "$R" | head -c 200) · $(q "select inversionista_id from crm.leads where id='$LL3'")"
LD2="$(uuid)"; sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LD2','D13 DESHACER-OFF r$RUN','9${RUN}83','$DU3',1000,'landing','nuevo',null,null)"; run_as "$G" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LD2'" >/dev/null
R="$(deshacer "$LD2")"; [[ "$(j "$R" etapa)" == "nuevo" && "$(q "select inversionista_id is null from crm.leads where id='$LD2'")" == "t" ]] && ok "OFF: deshacer descarte reabre SIN enlazar (como hoy)" || rojo "OFF deshacer: $(echo "$R" | head -c 200)"

psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false; flag_inv false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b D-13: VERDE — un solo lead (enlace ∪ puente ∪ sueltos por documento) y persona en conversión en todas las puertas; reabrir/tomar enlaza y solo por RPC; el sellado revalida pareja, lead y un solo lead; paridad apagada."; exit 0
else echo "ORÁCULO F2.b D-13: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
