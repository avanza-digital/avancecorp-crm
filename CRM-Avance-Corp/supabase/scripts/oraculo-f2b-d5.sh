#!/usr/bin/env bash
# ORÁCULO F2.b [D-5] — las RPC de UN argumento de la conversión se cierran con la identidad encendida (apagada: intactas)
# y Gerencia abandona una conversión sellada sin cuenta — SOLO en el BANCO. Presupone b1..b5, D-10, D-13 y siembra-banco-f3.sql.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d5.sh   (lee $S/banco-pooler.txt). Sin D-5 = corrida MUTANTE: T1/T2 y todo lo de abandonar salen ROJOS.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
AJENO='f3aaaaaa-0000-0000-0000-000000000099'
L1="f31ead00-0000-0000-0000-${RUN}000001"; L2="f31ead00-0000-0000-0000-${RUN}000002"; L3="f31ead00-0000-0000-0000-${RUN}000003"; L4="f31ead00-0000-0000-0000-${RUN}000004"; L5="f31ead00-0000-0000-0000-${RUN}000005"
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR" ; }
flag() { local i; for i in 1 2 3 4 5; do psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null 2>&1; [[ "$(psql "$PG" -qtA -c "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'" 2>/dev/null)" == "$( [[ "$1" == "true" ]] && echo t || echo f )" ]] && return 0; echo "  (bandera: reintento $i)"; sleep 3; done; echo "  ❌ bandera: no se pudo poner en $1" >&2; ROJO=$((ROJO+1)); }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]); print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
pay()  { echo "{\"correo\":\"$1\",\"nombre_completo\":\"D5 $2\",\"telefono\":\"9${RUN}0$3\",\"domicilio\":\"Av. Prueba 123, Lima\"}"; }
reservar1() { run_as "${2:-$V}" "select crm.reservar_conversion_lead('$1')"; }
sellar1()   { run_as "${2:-$V}" "select crm.marcar_efectos_conversion('$1')"; }
reservar4() { run_as "$V" "select crm.reservar_conversion_lead('$1','DNI','$2','$3'::jsonb)"; }
sellar3()   { run_as "$V" "select crm.marcar_efectos_conversion('$1','$2','$3')"; }
abandonar() { run_as "${3:-$G}" "select crm.abandonar_conversion_gerencia_fn('$1', $2)"; }
retomar()   { run_as "$G" "select crm.retomar_conversion_gerencia_fn('$1')"; }
verificar() { run_as "$V" "select crm.verificar_disponibilidad_lead('$1','$2')"; }
lead_de() { sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D5 $3 r$RUN','9${RUN}$2',${4:-null},1000,'landing','nuevo','$V','$V')"; }
vencer() { sys "update crm.conversion_reservas set vence_absoluto_en = now() - interval '1 minute', expira_en = now() - interval '1 minute' where lead_id='$1'"; sys "update crm.multiempresa_idempotencia set resultado = resultado || jsonb_build_object('lease_hasta', (now() - interval '1 minute')) where clave = 'auth_persona:' || '$2'"; }
# sella por persona: reserva de 4 args + sellado de 3; deja en las globales INV/CL/TK
sellar_persona() { local R; R="$(reservar4 "$1" "$2" "$(pay "$3@x.pe" "$3" "$4")")"; INV="$(j "$R" inversionista_id)"; CL="$(j "$R" claim_id)"; TK="$(j "$R" token)"; [[ "$(j "$R" estado)" == "reclamado" ]] || { rojo "reserva por persona de $1: $(echo "$R" | head -c 200)"; return 1; }; R="$(sellar3 "$1" "$CL" "$TK")"; [[ "$(j "$R" ok)" == "True" ]] || { rojo "sellado de $1: $(echo "$R" | head -c 200)"; return 1; }; return 0; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
if [[ "$(q "select to_regprocedure('crm.abandonar_conversion_gerencia_fn(uuid,text)') is not null")" == "t" ]]; then echo "  D-5 instalada (todo debe salir VERDE)"; else echo "  ⚠️ D-5 NO instalada: corrida MUTANTE (T1/T2 y abandonar salen ROJOS)"; fi
flag false

echo "== (1) Bandera APAGADA: las firmas de un argumento están intactas =="
R="$(reservar1 "$L1")"; [[ "$(j "$R" ok)" == "True" && -n "$(j "$R" expira_en)" && "$(q "select count(*) from crm.conversion_reservas where lead_id='$L1' and inversionista_id is null")" == "1" ]] && ok "[O1] OFF: reservar_conversion_lead(lead) por V → ok, reserva por lead (sin persona), como hoy" || rojo "O1: $(echo "$R" | head -c 200)"
R="$(sellar1 "$L1")"; [[ "$(j "$R" ok)" == "True" && "$(q "select efectos_iniciados_en is not null from crm.conversion_reservas where lead_id='$L1'")" == "t" ]] && ok "[O2] OFF: marcar_efectos_conversion(lead) → ok, reserva sellada, como hoy" || rojo "O2: $(echo "$R" | head -c 200)"
R="$(reservar1 "$L2" "$AJENO")"; echo "$R" | grep -q "42501" && ok "[O3] sin autorización → 42501 (la autorización de siempre va ANTES de la guarda de la bandera)" || rojo "O3: $(echo "$R" | head -c 200)"
R="$(abandonar "$L1" "'motivo de prueba'")"; echo "$R" | grep -q "apagada" && echo "$R" | grep -q "P0409" && ok "[O4] OFF: abandonar_conversion_gerencia_fn → P0409 «apagada» (superficie inerte, como retomar)" || rojo "O4: $(echo "$R" | head -c 200)"
sys "delete from crm.conversion_reservas where lead_id='$L1'"

echo "== (2) Bandera ENCENDIDA: las firmas de un argumento se cierran; las de b4 siguen =="
flag true
R="$(reservar1 "$L2")"; echo "$R" | grep -q "P0409" && echo "$R" | grep -q "va por persona" && echo "$R" | grep -q "p_tipo_documento" && [[ "$(q "select count(*) from crm.conversion_reservas where lead_id='$L2'")" == "0" ]] && ok "[T1] ON: reservar_conversion_lead(lead) → P0409 «la conversión va por persona» (con la firma nueva en HINT), sin reserva" || rojo "T1: $(echo "$R" | head -c 260)"
R="$(sellar1 "$L2")"; echo "$R" | grep -q "P0409" && echo "$R" | grep -q "va por persona" && echo "$R" | grep -q "p_claim_id" && ok "[T2] ON: marcar_efectos_conversion(lead) → P0409 «va por persona» (HINT con claim + token)" || rojo "T2: $(echo "$R" | head -c 260)"
R="$(reservar1 "$L2" "$AJENO")"; echo "$R" | grep -q "42501" && ok "[T3] ON: sin autorización sigue siendo 42501 (antes que la bandera)" || rojo "T3: $(echo "$R" | head -c 200)"
D2="6${RUN}2"; sellar_persona "$L2" "$D2" "p2$RUN" 2 && ok "[T4] ON (regresión b4): reserva por persona + sellado con claim y token siguen funcionando (L2 sellado para la persona $INV)"
I2="$INV"; CL2="$CL"
[[ "$(q "select private.persona_en_conversion('$I2'::uuid, null)")" == "t" ]] && ok "fixture: la persona I2 está «en conversión» (reserva sellada, lead sin convertir)" || rojo "fixture persona_en_conversion"

echo "== (3) Gerencia abandona una conversión sellada sin cuenta =="
R="$(abandonar "$L2" "'Cliente desistió antes de crear la cuenta'" "$V")"; echo "$R" | grep -q "42501" && ok "[A1] un analista no abandona → 42501" || rojo "A1: $(echo "$R" | head -c 200)"
R="$(abandonar "$L3" "'Cliente desistió antes de crear la cuenta'")"; echo "$R" | grep -q "P0002" && ok "[A2] lead sin reserva por persona → P0002" || rojo "A2: $(echo "$R" | head -c 200)"
R="$(abandonar "$L2" "'abc'")"; echo "$R" | grep -q "22023" && ok "[A3] motivo corto → 22023 (obligatorio, 5..300)" || rojo "A3: $(echo "$R" | head -c 200)"
R="$(abandonar "$L2" "null")"; echo "$R" | grep -q "22023" && ok "[A3] motivo nulo → 22023" || rojo "A3 null: $(echo "$R" | head -c 200)"
R="$(abandonar "$L2" "'Cliente desistió antes de crear la cuenta'")"; echo "$R" | grep -q "sigue viva" && [[ "$(q "select count(*) from crm.conversion_reservas where lead_id='$L2'")" == "1" ]] && ok "[A4] reserva y claim vigentes → P0409 «sigue viva» (nunca expulsa a una ejecución viva), nada borrado" || rojo "A4: $(echo "$R" | head -c 200)"
vencer "$L2" "$I2"
NA0="$(q "select count(*) from public.audit_log where (tabla like '%conversion_reservas' or tabla like '%multiempresa_idempotencia') and operacion='DELETE'")"
R="$(abandonar "$L2" "'Cliente desistió antes de crear la cuenta'")"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" estado_previo)" == "reclamado" && "$(j "$R" inversionista_id)" == "$I2" && "$(j "$R" claim_id)" == "$CL2" ]] && ok "[A5] vencidos reserva y lease, con claim en «reclamado» → abandonada (estado_previo reclamado, persona y claim en la respuesta)" || rojo "A5: $(echo "$R" | head -c 260)"
[[ "$(q "select count(*) from crm.conversion_reservas where lead_id='$L2'")" == "0" && "$(q "select count(*) from crm.multiempresa_idempotencia where clave='auth_persona:$I2'")" == "0" ]] && ok "[A5] reserva y claim borrados" || rojo "A5 borrado: $(q "select count(*) from crm.conversion_reservas where lead_id='$L2'") $(q "select count(*) from crm.multiempresa_idempotencia where clave='auth_persona:$I2'")"
[[ "$(q "select private.persona_en_conversion('$I2'::uuid, null)")" == "f" ]] && ok "[A5] la persona ya NO está «en conversión»" || rojo "A5 persona_en_conversion sigue t"
NA1="$(q "select count(*) from public.audit_log where (tabla like '%conversion_reservas' or tabla like '%multiempresa_idempotencia') and operacion='DELETE'")"; (( NA1 - NA0 >= 2 )) && ok "[A5] audit_log registra los dos DELETE (reserva y claim): +$((NA1-NA0))" || rojo "A5 audit_log: $NA0 → $NA1"
[[ "$(q "select count(*) from crm.actividades a where a.lead_id='$L2' and a.tipo='nota' and a.metadata->>'evento'='conversion_abandonada' and a.metadata->>'estado_previo'='reclamado' and a.creado_por='$G' and a.detalle like 'Conversión abandonada por Gerencia: Cliente desistió%'")" == "1" ]] && ok "[A5] nota administrativa en el lead (evento conversion_abandonada, atribuida a Gerencia, con el motivo)" || rojo "A5 nota: $(q "select tipo, detalle, metadata from crm.actividades where lead_id='$L2' order by creado_en desc limit 1")"
R="$(verificar "9${RUN}77" "$D2")"; [[ "$(j "$R" estado)" == "libre" ]] && ok "[A5] la persona vuelve a estar libre para la operación (verificar con su DNI → libre)" || rojo "A5 libre: $R"
R="$(abandonar "$L2" "'Cliente desistió antes de crear la cuenta'")"; echo "$R" | grep -q "P0002" && ok "[A6] repetir → P0002 (ya no hay reserva)" || rojo "A6: $(echo "$R" | head -c 200)"
# Auditor v1 #1 (ALTO): la cuenta de Auth existe con la marca del claim pero la saga sigue en «reclamado» (el edge murió entre createUser y registrar_auth)
L8="$(uuid)"; lead_de "$L8" 68 OCHO; D8="6${RUN}8"; sellar_persona "$L8" "$D8" "p8$RUN" 8; I8="$INV"; CL8="$CL"; vencer "$L8" "$I8"; AU8="$(uuid)"
sys "insert into auth.users (id, raw_app_meta_data) values ('$AU8', jsonb_build_object('claim_id','$CL8')) on conflict do nothing"
R="$(abandonar "$L8" "'Auth creado sin registrar: no debe abandonarse'")"; echo "$R" | grep -q "aún sin registrar" && [[ "$(q "select count(*) from crm.conversion_reservas where lead_id='$L8'")" == "1" && "$(q "select count(*) from crm.multiempresa_idempotencia where clave='auth_persona:$I8'")" == "1" ]] && ok "[A12 auditor #1] claim «reclamado» pero auth.users lleva la marca del claim → P0409 «retoma», nada borrado (sin cuenta huérfana)" || rojo "A12: $(echo "$R" | head -c 260)"
sys "delete from auth.users where id='$AU8'"
R="$(abandonar "$L8" "'Sin la cuenta, sí se abandona'")"; [[ "$(j "$R" ok)" == "True" ]] && ok "[A12] sin esa cuenta, la misma reserva sí se abandona (par mutante)" || rojo "A12 par: $(echo "$R" | head -c 200)"
R="$(abandonar "$L8" "'Doble clic de Gerencia'")"; echo "$R" | grep -q "P0002" && ok "[A13 auditor #3] doble clic: la segunda llamada → P0002 (ya no hay reserva), texto honesto" || rojo "A13: $(echo "$R" | head -c 200)"
D4="6${RUN}4"; sellar_persona "$L4" "$D4" "p4$RUN" 4; I4="$INV"; AU4="$(uuid)"
sys "update crm.multiempresa_idempotencia set resultado = resultado || jsonb_build_object('estado','auth_creado','auth_user_id','$AU4') where clave='auth_persona:$I4'"; vencer "$L4" "$I4"
R="$(abandonar "$L4" "'La cuenta existe: no debería abandonarse'")"; echo "$R" | grep -q "retoma la conversión" && [[ "$(q "select count(*) from crm.conversion_reservas where lead_id='$L4'")" == "1" ]] && ok "[A7] claim en «auth_creado» (ya existe la cuenta de acceso) → P0409 «retoma la conversión», nada borrado" || rojo "A7: $(echo "$R" | head -c 260)"
R="$(retomar "$L4")"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" estado)" == "auth_creado" && "$(j "$R" reanudar)" == "True" ]] && ok "[A7] Gerencia RETOMA esa misma conversión (b4 intacto tras D-5): estado auth_creado, reanudar" || rojo "A7 retomar: $(echo "$R" | head -c 260)"
D5="6${RUN}5"; sellar_persona "$L5" "$D5" "p5$RUN" 5; I5="$INV"; vencer "$L5" "$I5"
sys "update crm.multiempresa_idempotencia set resultado = resultado || jsonb_build_object('estado','enlazado') where clave='auth_persona:$I5'"
R="$(abandonar "$L5" "'La conversión ya se consumó'")"; echo "$R" | grep -q "ya se consumó" && ok "[A8] claim «enlazado» → P0409 «ya se consumó», nada borrado" || rojo "A8: $(echo "$R" | head -c 200)"
L6="$(uuid)"; lead_de "$L6" 66 SEIS; D6="6${RUN}6"; sellar_persona "$L6" "$D6" "p6$RUN" 6; I6="$INV"; vencer "$L6" "$I6"; sys "update crm.conversion_reservas set claim_id = gen_random_uuid() where lead_id='$L6'"
R="$(abandonar "$L6" "'Reserva y claim no corresponden'")"; echo "$R" | grep -q "no corresponden" && [[ "$(q "select count(*) from crm.multiempresa_idempotencia where clave='auth_persona:$I6'")" == "1" ]] && ok "[A9] la reserva apunta a OTRO claim → P0409 «no corresponden», nada borrado" || rojo "A9: $(echo "$R" | head -c 200)"
L7="$(uuid)"; lead_de "$L7" 67 SIETE; D7="6${RUN}7"; sellar_persona "$L7" "$D7" "p7$RUN" 7; I7="$INV"
R="$(sys "update crm.leads set etapa='convertido', convertido_en=now() where id='$L7'")"; if [[ -z "$R" && "$(q "select etapa from crm.leads where id='$L7'")" == "convertido" ]]; then vencer "$L7" "$I7"; R="$(abandonar "$L7" "'Ya está convertido'")"; echo "$R" | grep -q "ya está convertido" && ok "[A10] lead ya convertido → P0409 (la conversión se consumó)" || rojo "A10: $(echo "$R" | head -c 200)"; else echo "  (A10 omitido: el banco no deja marcar convertido a mano: $(echo "$R" | head -c 120))"; fi
R="$(run_as "$V" "select crm.abandonar_conversion_gerencia_fn('$L4','motivo')")"; echo "$R" | grep -q "42501" && ok "[A11] analista con la firma completa → 42501" || rojo "A11: $(echo "$R" | head -c 200)"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role service_role; select crm.abandonar_conversion_gerencia_fn('$L4','motivo largo'); rollback;" 2>&1)"; echo "$R" | grep -q "42501" && ok "[A11] service_role sin EXECUTE → 42501" || rojo "A11 service_role: $(echo "$R" | head -c 200)"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role anon; select crm.abandonar_conversion_gerencia_fn('$L4','motivo largo'); rollback;" 2>&1)"; echo "$R" | grep -q "42501" && ok "[A11] anon sin EXECUTE → 42501" || rojo "A11 anon: $(echo "$R" | head -c 200)"

echo "== Limpieza =="
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); delete from crm.conversion_reservas where lead_id in ('$L1','$L2','$L3','$L4','$L5','${L6:-$L5}','${L7:-$L5}'); delete from crm.multiempresa_idempotencia where clave in ('auth_persona:${I2:-x}','auth_persona:${I4:-x}','auth_persona:${I5:-x}','auth_persona:${I6:-x}','auth_persona:${I7:-x}','auth_persona:${I8:-x}'); delete from crm.conversion_reservas where lead_id = '${L8:-00000000-0000-0000-0000-000000000000}'; update crm.leads set activo=false where nombre_completo like 'D5 %' and activo; commit;" >/dev/null 2>&1
psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b D-5: VERDE — apagada, las firmas de un argumento son las de hoy; encendida se cierran (P0409) y las de b4 siguen; Gerencia abandona solo una conversión sellada sin cuenta y vencida (borra reserva y claim, nota y bitácora, persona libre); con cuenta/ficha → retomar."; else echo "ORÁCULO F2.b D-5: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
