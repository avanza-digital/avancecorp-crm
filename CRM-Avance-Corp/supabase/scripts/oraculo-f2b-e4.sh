#!/usr/bin/env bash
# ORÁCULO F2.b E4 — crear_contrato reconoce a la persona (ON) + candado del documento en public.perfiles — SOLO en el BANCO.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-e4.sh   (lee $S/banco-pooler.txt). Presupone E1+E2+E3+E4 y siembra-banco-f3.sql.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
D1="3${RUN}1"; D2="3${RUN}2"; D3="3${RUN}3"; D4="3${RUN}4"; ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
run_claims() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; $1; commit;" 2>&1 | grep -E "ERROR"; }
flag() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null; }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]); print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
sim_auth()  { psql "$PG" -q -c "insert into auth.users (id, email) values ('$1', '$2') on conflict (id) do nothing;" 2>/dev/null; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','E4 CLIENTE $3 r$RUN','cliente','DNI',$2,'$3','$V',true); commit;" 2>&1 | grep -E "ERROR"; }
HOY="$(q "select current_date")"; VENCE="$(q "select (current_date + interval '1 year')::date")"; CUOTA="$(q "select (current_date + interval '1 month')::date")"
contrato() { run_as "$1" "select public.crear_contrato('{\"cliente_id\":\"$2\",\"moneda\":\"PEN\",\"capital\":1000,\"tasa_anual\":10,\"categoria\":\"nuevo\",\"modalidad\":\"mensual\",\"tipo_interes\":\"simple\",\"fecha_inicio\":\"$HOY\",\"fecha_vencimiento\":\"$VENCE\"}'::jsonb, '[{\"numero_cuota\":1,\"fecha_programada\":\"$CUOTA\",\"monto_programado\":8.33,\"tipo\":\"cuota\"}]'::jsonb)"; }
inv_de() { q "select private.inversionista_por_documento('DNI','$1')"; }
n_contratos() { q "select count(*) from public.contratos where cliente_id='$1'"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -1
[[ "$(q "select count(*) from pg_trigger where tgrelid='public.perfiles'::regclass and tgname='trg_perfiles_zz_documento_protegido'")" == "1" ]] || { echo "falta E4" >&2; exit 2; }
flag false
P1="$(uuid)"; sim_auth "$P1" "e4a$RUN@x.pe"; sim_perfil "$P1" "'$D1'" "e4a$RUN@x.pe"
P2="$(uuid)"; sim_auth "$P2" "e4b$RUN@x.pe"; sim_perfil "$P2" "null" "e4b$RUN@x.pe"
P3="$(uuid)"; sim_auth "$P3" "e4c$RUN@x.pe"; sim_perfil "$P3" "'1$RUN'" "e4c$RUN@x.pe"   # 7 dígitos: inválido para DNI, único por corrida
P4="$(uuid)"; sim_auth "$P4" "e4d$RUN@x.pe"; sim_perfil "$P4" "'$D4'" "e4d$RUN@x.pe"
[[ "$(inv_de "$D1")" == "" ]] && ok "fixtures: 4 clientes sin identidad (con documento, sin documento, documento inválido, testigo)" || rojo "fixture con identidad previa"

echo "== ON: crear un contrato reconoce a la persona =="
flag true
R="$(contrato "$V" "$P1")"; I1="$(inv_de "$D1")"
[[ "$(n_contratos "$P1")" == "1" && -n "$I1" && "$(q "select perfil_id from crm.inversionistas where id='$I1'")" == "$P1" ]] && ok "contrato creado y el cliente quedó enlazado a su persona (identidad nueva con su documento)" || rojo "contrato/enlace P1: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
[[ "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$I1' and hasta is null and responsable_id='$V'")" == "1" ]] && ok "tramo de responsable abierto con el asesor del perfil" || rojo "sin tramo"
[[ "$(q "select count(*) from crm.inversionista_identificadores where inversionista_id='$I1' and fuente='contrato' and estado='vigente' and verificado")" == "1" ]] && ok "identificador vigente y verificado con fuente=contrato" || rojo "identificador"
R="$(contrato "$V" "$P1")"; [[ "$(n_contratos "$P1")" == "2" && "$(q "select count(*) from crm.inversionistas where perfil_id='$P1' and estado<>'fusionado'")" == "1" ]] && ok "segundo contrato del mismo cliente: misma persona, sin duplicar identidad" || rojo "segundo contrato: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
R="$(contrato "$V" "$P2")"; echo "$R" | grep -q "no tiene documento" && [[ "$(n_contratos "$P2")" == "0" ]] && ok "cliente SIN documento → P0409 y sin contrato (fail-closed)" || rojo "sin documento: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
R="$(contrato "$V" "$P3")"; echo "$R" | grep -q "22023" && [[ "$(n_contratos "$P3")" == "0" ]] && ok "cliente con documento INVÁLIDO → 22023 y sin contrato" || rojo "documento inválido: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
R="$(contrato "$V" "$(uuid)")"; echo "$R" | grep -q "42501" && ok "cliente inexistente → 42501 como hoy (la precedencia no cambia)" || rojo "inexistente: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
# [Codex] perfiles_dni_cliente_key es único sobre el DNI CRUDO: otro formato del mismo documento sí entra al Portal
P5="$(uuid)"; sim_auth "$P5" "e4e$RUN@x.pe"; flag false; sim_perfil "$P5" "' $D1'" "e4e$RUN@x.pe" >/dev/null; flag true
R="$(contrato "$V" "$P5")"; echo "$R" | grep -q "P0409" && [[ "$(n_contratos "$P5")" == "0" ]] && ok "perfil con el documento (otro formato) de OTRA persona ya enlazada → P0409 y sin contrato" || rojo "documento ajeno: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"

echo "== ON: candado del documento en el Portal =="
R="$(sys "update public.perfiles set dni='$D2' where id='$P1'")"; echo "$R" | grep -q "solo se corrige desde el CRM" && [[ "$(q "select dni from public.perfiles where id='$P1'")" == "$D1" ]] && ok "UPDATE del DNI de un cliente reconocido (sin la GUC, como el Portal) → P0409, intacto" || rojo "candado: $R"
R="$(run_as "$P1" "update public.perfiles set id='$(uuid)', dni='$D2' where id='$P1'")"; echo "$R" | grep -q "solo se corrige desde el CRM" && [[ "$(q "select dni from public.perfiles where id='$P1'")" == "$D1" ]] && ok "[Codex B-1] el propio cliente envía id+dni juntos → el candado (por OLD.id) lo rechaza; intacto" || rojo "B-1: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
R="$(sys "update public.perfiles set tipo_documento='CE', dni='00${RUN}55' where id='$P1'")"; echo "$R" | grep -q "solo se corrige desde el CRM" && ok "cambio de tipo+número → P0409" || rojo "tipo: $R"
R="$(sys "update public.perfiles set dni=' $D1 ' where id='$P1'")"; [[ -z "$R" ]] && ok "mismo documento con otro formato → pasa (no es un cambio)" || rojo "formato: $R"
R="$(sys "update public.perfiles set dni='$D3' where id='$P4'")"; [[ -z "$R" && "$(q "select dni from public.perfiles where id='$P4'")" == "$D3" ]] && ok "cliente NO reconocido → el Portal sigue pudiendo cambiar su DNI" || rojo "no enlazado: $R"
R="$(sys "select set_config('crm.correccion_documento','on',true); update public.perfiles set dni='$D2' where id='$P1'")"; echo "$R" | grep -q "solo se corrige" && ok "solo la GUC propia SIN la válvula → P0409 (el candado exige las dos marcas)" || rojo "GUC sola: $R"
R="$(sys "select set_config('crm.op_privilegiada','on',true); select set_config('crm.correccion_documento','on',true); update public.perfiles set dni='$D2' where id='$P1'")"; [[ -z "$R" && "$(q "select dni from public.perfiles where id='$P1'")" == "$D2" ]] && ok "bajo válvula + GUC de la corrección → pasa (la corrección de Gerencia sigue realineando)" || rojo "GUC: $R"
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); select set_config('crm.correccion_documento','on',true); update public.perfiles set dni='$D1' where id='$P1'; commit;" >/dev/null 2>&1
R="$(run_claims "$G" "select crm.actualizar_cliente_gerencia('$P1', '{\"dni\":\"$D2\"}'::jsonb)")"; echo "$R" | grep -q "P0409" && ok "edición de cliente del CRM (b3) sigue rechazando el cambio de documento" || rojo "actualizar_cliente_gerencia: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"

echo "== [Codex B-2] wrapper bancario crm.crear_contrato_con_cuenta: prepuerta antes de sus locks =="
P7="$(uuid)"; sim_auth "$P7" "e4g$RUN@x.pe"; flag false; sim_perfil "$P7" "'3${RUN}7'" "e4g$RUN@x.pe"; flag true
sys "update public.perfiles set banco='BCP', tipo_cuenta='ahorros', numero_cuenta='1234567890', cci='00212345678901234567', titular_distinto=false where id='$P7'"
CUENTA='{"tipo":"perfil","cuenta_esperada":{"banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"1234567890","cci":"00212345678901234567","titular_distinto":false,"beneficiario_nombre":null,"beneficiario_dni":null}}'
wrapper() { run_claims "$1" "select crm.crear_contrato_con_cuenta('{\"cliente_id\":\"$2\",\"moneda\":\"PEN\",\"capital\":1000,\"tasa_anual\":10,\"categoria\":\"nuevo\",\"modalidad\":\"mensual\",\"tipo_interes\":\"simple\",\"fecha_inicio\":\"$HOY\",\"fecha_vencimiento\":\"$VENCE\"}'::jsonb, '[{\"numero_cuota\":1,\"fecha_programada\":\"$CUOTA\",\"monto_programado\":8.33,\"tipo\":\"cuota\"}]'::jsonb, '$CUENTA'::jsonb)"; }
R="$(wrapper "$V" "$P7")"; I7="$(inv_de "3${RUN}7")"; [[ "$(n_contratos "$P7")" == "1" && -n "$I7" ]] && ok "wrapper bancario (rama perfil): contrato creado y persona reconocida" || rojo "wrapper: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-180)"
# intercalado: A retiene la IDENTIDAD de P7 y luego escribe su perfil; B (wrapper) debe esperar en la prepuerta, NO retener el perfil antes → sin 40P01
psql "$PG" -qtA -c "begin; select id from crm.inversionistas where id='$I7' for update; select pg_sleep(3); update public.perfiles set nombre_completo='E4 CLIENTE G r$RUN (tocado)' where id='$P7'; commit;" > "$S/e4_race_a.out" 2>&1 &
A_PID=$!; sleep 1
R="$(wrapper "$V" "$P7")"; echo "$R" > "$S/e4_race_b.out"; wait $A_PID
if grep -q "40P01\|deadlock" "$S/e4_race_a.out" || echo "$R" | grep -q "40P01\|deadlock"; then rojo "[Codex B-2] deadlock entre el wrapper y una sesión identidad→perfil"; else [[ "$(n_contratos "$P7")" == "2" && "$(q "select nombre_completo ilike '%(tocado)' from public.perfiles where id='$P7'")" == "t" ]] && ok "[Codex B-2] wrapper ‖ sesión identidad→perfil: sin deadlock, ambos terminan (el wrapper espera en la prepuerta, no reteniendo el perfil)" || rojo "B-2: contratos=$(n_contratos "$P7") B=[$(tr '\n' ' ' < "$S/e4_race_b.out" | cut -c1-200)] A=[$(tr '\n' ' ' < "$S/e4_race_a.out" | cut -c1-120)]"; fi
echo "== Paridad con bandera APAGADA =="
flag false
P6="$(uuid)"; sim_auth "$P6" "e4f$RUN@x.pe"; sim_perfil "$P6" "'3${RUN}6'" "e4f$RUN@x.pe"
R="$(contrato "$V" "$P6")"; [[ "$(n_contratos "$P6")" == "1" && "$(inv_de "3${RUN}6")" == "" ]] && ok "OFF: el contrato se crea como hoy y NO nace identidad" || rojo "OFF contrato: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
R="$(sys "update public.perfiles set dni='$D2' where id='$P1'")"; [[ -z "$R" ]] && ok "OFF: el candado es inerte (el Portal cambia el DNI de un cliente reconocido, como hoy)" || rojo "OFF candado: $R"
P8="$(uuid)"; sim_auth "$P8" "e4h$RUN@x.pe"; sim_perfil "$P8" "'3${RUN}8'" "e4h$RUN@x.pe"; sys "update public.perfiles set banco='BCP', tipo_cuenta='ahorros', numero_cuenta='1234567890', cci='00212345678901234567', titular_distinto=false where id='$P8'"
R="$(wrapper "$V" "$P8")"; [[ "$(n_contratos "$P8")" == "1" && "$(inv_de "3${RUN}8")" == "" ]] && ok "OFF: el wrapper bancario crea el contrato como hoy y NO nace identidad" || rojo "OFF wrapper: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
sys "update public.perfiles set dni='$D1' where id='$P1'" >/dev/null
flag true
psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b E4: VERDE — crear_contrato reconoce a la persona (fail-closed sin documento), candado del documento del Portal bajo la GUC de la corrección; paridad apagada."; exit 0
else echo "ORÁCULO F2.b E4: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
