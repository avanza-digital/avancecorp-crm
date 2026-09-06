#!/usr/bin/env bash
# ORÁCULO F2.b [D-3] — el veto de la persona es COHERENTE: tareas de perfil, ficha del cliente (actividades_cliente) y
# leads sueltos/puente con su documento — SOLO en el BANCO. Presupone b1..b5 + D-13 y la siembra siembra-banco-f3.sql (V/S/G).
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d3.sh   (lee $S/banco-pooler.txt). Sin D-3 (mutante) las secciones (2)-(4) deben salir ROJAS.
# Nota de forma: uq_leads_dni_vivo solo admite UN lead vivo por DNI; por eso el lead enlazado de la persona (LE) se cierra en la coop
# y el SUELTO (LS, nacido con la bandera apagada) es el vivo. Las identidades nacidas de un lead no quedan verificadas: la persona
# se crea VERIFICADA por la coop (como en producción).
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
# como postgres pero con la identidad del usuario en las claims (auth.uid() = $1): para tablas sin policy de INSERT (actividades_cliente)
as_uid() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR" ; }
flag() { local i; for i in 1 2 3 4 5; do psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null 2>&1; [[ "$(psql "$PG" -qtA -c "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'" 2>/dev/null)" == "$( [[ "$1" == "true" ]] && echo t || echo f )" ]] && return 0; echo "  (bandera: reintento $i)"; sleep 3; done; echo "  ❌ bandera: no se pudo poner en $1" >&2; ROJO=$((ROJO+1)); }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]); print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
inv_de() { q "select private.inversionista_por_documento('DNI','$1')"; }
# lead nacido con la bandera ENCENDIDA (INSERT directo como el importador): con DNI de una persona verificada sin perfil, nace enlazado
lead_on() { sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D3 $3 r$RUN','9${RUN}$2',$4,1000,'landing','nuevo',null,'$V')"; }
# lead con DNI nacido con la bandera APAGADA: queda SUELTO (sin enlace) aunque exista la persona
lead_off() { flag false; sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D3 $3 r$RUN','9${RUN}$2',$4,1000,'landing','nuevo',null,'$V')"; flag true; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$1') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','D3 CLIENTE $2 r$RUN','cliente','DNI',$3,'$4','$V',true); commit;" 2>&1 | grep -E "ERROR"; }
# devuelven el id de la tarea o la línea ERROR (sin las líneas de contexto de psql ni el eco de las claims)
tarea_lead() { run_as "$1" "insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por) values ('$2','llamada','D3 tarea lead r$RUN', now() + interval '1 day', '$1') returning id" | grep -vE '^(LOCATION|DETAIL|HINT|CONTEXT|\{)' | tail -1; }
tarea_perfil() { run_as "$1" "insert into crm.tareas (perfil_id, tipo, titulo, vence_en, creado_por) values ('$2','llamada','D3 tarea cliente r$RUN', now() + interval '1 day', '$1') returning id" | grep -vE '^(LOCATION|DETAIL|HINT|CONTEXT|\{)' | tail -1; }
act_cliente() { as_uid "$1" "insert into crm.actividades_cliente (cliente_id, vendedor_id, tipo, detalle, creado_por) values ('$2','$1','$3','D3 act r$RUN','$1') returning id"; }
estado_tarea() { q "select estado||' '||coalesce(cancelada_por,'-') from crm.tareas where id='$1'"; }
veto_de() { q "select no_contactar from crm.leads where id='$1'"; }
marcar() { run_as "$1" "select crm.marcar_no_contactar('$2', 'ensayo D-3 r$RUN')"; }
levantar() { run_as "$G" "select crm.levantar_no_contactar('$1', 'ensayo D-3 r$RUN')"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
if [[ "$(q "select to_regprocedure('private.persona_vetada_perfil(uuid)') is not null")" == "t" ]]; then echo "  D-3 instalada (todo debe salir VERDE)"; else echo "  ⚠️ D-3 NO instalada: corrida MUTANTE ((2)-(4) deben salir ROJAS)"; fi
flag true

echo "== (1) Fixture: persona P (coop en LE: convertido y enlazado), SUELTO vivo LS (mismo DNI, nacido con OFF), puente-only LP, perfil PF, 3 tareas pendientes =="
D="3${RUN}1"; LE="$(uuid)"; LS="$(uuid)"; LP="$(uuid)"; PF="$(uuid)"
lead_on "$LE" 31 LE null
R="$(run_as "$V" "select crm.convertir_lead_externo('$LE','qorilazo',1000,'PEN','DNI','$D','D3 PERSONA P','TRX-D3-$RUN')")"; IP="$(inv_de "$D")"
[[ -n "$IP" && "$(q "select etapa='convertido' and inversionista_id='$IP' from crm.leads where id='$LE'")" == "t" ]] && ok "P=$IP nació VERIFICADA en la coop; LE convertido y enlazado" || rojo "fixture LE/P: $(echo "$R" | grep -E 'ERROR|MESSAGE' | head -1 | cut -c1-200)"
lead_off "$LS" 32 LS "'$D'"
[[ "$(q "select inversionista_id is null and dni='$D' and activo and etapa='nuevo' from crm.leads where id='$LS'")" == "t" ]] && ok "LS es un lead SUELTO y VIVO con el mismo DNI (nacido con la bandera apagada)" || rojo "fixture LS"
lead_on "$LP" 33 LP null; sys "insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values ('$IP','$LP','historico')"
[[ "$(q "select inversionista_id is null from crm.leads where id='$LP'")" == "t" && "$(q "select count(*) from crm.inversionista_leads where inversionista_id='$IP' and lead_id='$LP'")" == "1" ]] && ok "LP está SOLO en el puente de P (sin DNI ni enlace)" || rojo "fixture LP"
sim_perfil "$PF" P "'$D'" "d3p$RUN@x.pe"; sys "update crm.inversionistas set perfil_id='$PF' where id='$IP'"
[[ "$(q "select perfil_id from crm.inversionistas where id='$IP'")" == "$PF" ]] && ok "PF es el perfil cliente de P (asesor V)" || rojo "fixture PF"
TLS="$(tarea_lead "$V" "$LS")"; TLP="$(tarea_lead "$V" "$LP")"; TPF="$(tarea_perfil "$V" "$PF")"
[[ "$(estado_tarea "$TLS")" == "pendiente -" && "$(estado_tarea "$TLP")" == "pendiente -" && "$(estado_tarea "$TPF")" == "pendiente -" ]] && ok "3 tareas pendientes (LS, LP y la de cliente PF)" || rojo "tareas: LS=$(estado_tarea "$TLS") LP=$(estado_tarea "$TLP") PF=$(estado_tarea "$TPF") ($TLS|$TLP|$TPF)"
[[ "$(q "select private.persona_vetada_perfil('$PF')" 2>/dev/null)" != "t" ]] && ok "antes del veto: persona_vetada_perfil(PF) no es true" || rojo "vetada antes de tiempo"

echo "== (2) marcar_no_contactar(LS) por V (rama del suelto): la persona, LE (enlazado), LS (suelto) y LP (puente) quedan vetados; las 3 tareas canceladas por sistema =="
R="$(marcar "$V" "$LS")"
[[ "$(j "$R" ok)" == "True" && "$(j "$R" inversionista_id)" == "$IP" ]] && ok "marcar → ok sobre la persona P (resuelta por documento)" || rojo "marcar: $(echo "$R" | head -c 200)"
[[ "$(j "$R" leads_afectados)" == "3" ]] && ok "leads_afectados = 3 (enlace + suelto + puente)" || rojo "[D-3 HUECO] leads_afectados = $(j "$R" leads_afectados) (esperaba 3)"
[[ "$(q "select no_contactar from crm.inversionistas where id='$IP'")" == "t" ]] && ok "P.no_contactar = true" || rojo "P sin veto"
[[ "$(veto_de "$LE")" == "t" ]] && ok "LE (enlazado, convertido) vetado" || rojo "LE sin veto"
[[ "$(veto_de "$LS")" == "t" ]] && ok "LS (suelto con su documento) vetado" || rojo "[D-3 HUECO] LS suelto sin veto"
[[ "$(veto_de "$LP")" == "t" ]] && ok "LP (solo puente) vetado" || rojo "[D-3 HUECO] LP puente sin veto"
[[ "$(estado_tarea "$TLS")" == "cancelada sistema" && "$(estado_tarea "$TLP")" == "cancelada sistema" ]] && ok "las tareas de LS y LP canceladas por sistema" || rojo "[D-3 HUECO] tareas: LS=$(estado_tarea "$TLS") LP=$(estado_tarea "$TLP")"
[[ "$(estado_tarea "$TPF")" == "cancelada sistema" ]] && ok "la tarea de CLIENTE (perfil PF) cancelada por sistema" || rojo "[D-3 HUECO] tarea de cliente: $(estado_tarea "$TPF")"
[[ "$(q "select private.persona_vetada_perfil('$PF')" 2>/dev/null)" == "t" ]] && ok "persona_vetada_perfil(PF) = true (por el enlace perfil↔persona)" || rojo "[D-3 HUECO] persona_vetada_perfil(PF) ≠ true"
[[ "$(q "select count(*) from private.leads_vetados_persona(array['$LP'::uuid])")" == "1" ]] && ok "el gate por lead ve el PUENTE: leads_vetados_persona(LP) lo incluye" || rojo "[D-3 HUECO] leads_vetados_persona no ve el puente"

echo "== (3) Gates con la persona vetada =="
R="$(tarea_perfil "$V" "$PF")"; echo "$R" | grep -q "P0429" && ok "tarea de CLIENTE nueva para PF → P0429" || rojo "[D-3 HUECO] tarea de cliente pasó: $(echo "$R" | head -c 160)"
R="$(tarea_lead "$V" "$LS")"; echo "$R" | grep -q "P0429" && ok "tarea nueva sobre el suelto LS → P0429 (b2, por documento)" || rojo "tarea LS pasó: $(echo "$R" | head -c 160)"
R="$(tarea_lead "$V" "$LP")"; echo "$R" | grep -q "P0429" && ok "tarea nueva sobre el puente LP → P0429 (D-3: el gate ve el puente)" || rojo "[D-3 HUECO] tarea LP pasó: $(echo "$R" | head -c 160)"
R="$(act_cliente "$V" "$PF" llamada_realizada)"; echo "$R" | grep -q "P0429" && ok "actividades_cliente de CONTACTO (llamada_realizada) → P0429" || rojo "[D-3 HUECO] contacto en la ficha pasó: $(echo "$R" | head -c 160)"
R="$(act_cliente "$V" "$PF" nota)"; echo "$R" | grep -q "ERROR" && rojo "nota en la ficha rechazada: $(echo "$R" | head -c 160)" || ok "actividades_cliente tipo nota → entra (no es contacto)"
R="$(sys "insert into crm.actividades_cliente (cliente_id, vendedor_id, tipo, detalle, creado_por) values ('$PF','$V','whatsapp_enviado','D3 valvula r$RUN',null)")"; [[ -z "$R" ]] && ok "writer interno (auth.uid NULL, válvula) → entra" || rojo "writer interno rechazado: $R"
LN="$(uuid)"; R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LN','D3 NUEVO r$RUN','9${RUN}34','$D',1000,'landing','nuevo',null,'$V'); commit;" 2>&1)"; echo "$R" | grep -q "P0429" && ok "un lead nuevo con el DNI de P → P0429 (b1 hereda el veto)" || rojo "lead nuevo con DNI vetado: $(echo "$R" | head -c 160)"

echo "== (4) levantar_no_contactar(LS) por Gerencia: todo el conjunto se levanta; las tareas siguen canceladas =="
R="$(levantar "$LS")"
[[ "$(j "$R" ok)" == "True" && "$(j "$R" leads_afectados)" == "3" ]] && ok "levantar → ok, leads_afectados = 3" || rojo "[D-3 HUECO] levantar: $(echo "$R" | head -c 200)"
[[ "$(q "select no_contactar from crm.inversionistas where id='$IP'")" == "f" && "$(veto_de "$LE")" == "f" && "$(veto_de "$LS")" == "f" && "$(veto_de "$LP")" == "f" ]] && ok "P, LE, LS y LP sin veto" || rojo "[D-3 HUECO] veto residual: LE=$(veto_de "$LE") LS=$(veto_de "$LS") LP=$(veto_de "$LP")"
[[ "$(estado_tarea "$TPF")" == "cancelada sistema" ]] && ok "la tarea de cliente sigue cancelada (levantar no revive)" || rojo "tarea revivida"
R="$(tarea_perfil "$V" "$PF")"; echo "$R" | grep -q "ERROR" && rojo "tras levantar, la tarea de cliente sigue bloqueada: $(echo "$R" | head -c 160)" || ok "tras levantar, PF admite tareas de cliente otra vez"
R="$(act_cliente "$V" "$PF" llamada_realizada)"; echo "$R" | grep -q "ERROR" && rojo "tras levantar, contacto en la ficha bloqueado: $(echo "$R" | head -c 160)" || ok "tras levantar, la ficha admite contacto"

echo "== (4b) [auditor M1] documento → persona: marcar sobre el lead ENLAZADO espera detrás de quien tiene el candado del documento (la puerta del DNI de D-13) =="
psql "$PG" -q -c "begin; select private.identidad_bloquear_documento('DNI','$D'); select pg_sleep(5); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1; T0=$(date +%s)
R="$(marcar "$V" "$LE")"; T1=$(date +%s)
[[ "$(j "$R" ok)" == "True" && $((T1-T0)) -ge 3 ]] && ok "marcar(LE enlazado) esperó $((T1-T0)) s al candado del documento de P (documento → persona) y luego marcó" || rojo "[D-3 HUECO M1] marcar no esperó al candado documental ($((T1-T0)) s): $(echo "$R" | head -c 160)"
wait $BG 2>/dev/null
R="$(levantar "$LE")"; [[ "$(j "$R" ok)" == "True" ]] && ok "levantar tras el ensayo del candado" || rojo "levantar (4b): $(echo "$R" | head -c 160)"

echo "== (5) Veto visto desde un perfil por DOCUMENTO (perfil sin enlace a la identidad) =="
D2="3${RUN}5"; PF2="$(uuid)"; IP2="$(q "select private.inversionista_resolver('DNI','$D2',true,'ensayo-d3')")"
sim_perfil "$PF2" Q "'$D2'" "d3q$RUN@x.pe"
[[ -n "$IP2" && "$(q "select perfil_id is null from crm.inversionistas where id='$IP2'")" == "t" ]] && ok "fixture: persona Q ($IP2) sin perfil enlazado; PF2 tiene su documento" || rojo "fixture Q/PF2"
[[ "$(q "select private.persona_vetada_perfil('$PF2')" 2>/dev/null)" != "t" ]] && ok "Q sin veto → persona_vetada_perfil(PF2) no es true" || rojo "PF2 vetado antes de tiempo"
sys "update crm.inversionistas set no_contactar=true, no_contactar_en=now(), no_contactar_por='$G' where id='$IP2'"
[[ "$(q "select private.persona_vetada_perfil('$PF2')" 2>/dev/null)" == "t" ]] && ok "Q vetada → persona_vetada_perfil(PF2) = true por DOCUMENTO" || rojo "[D-3 HUECO] veto por documento no visto desde el perfil"
R="$(tarea_perfil "$V" "$PF2")"; echo "$R" | grep -q "P0429" && ok "tarea de cliente para PF2 → P0429" || rojo "[D-3 HUECO] tarea PF2 pasó: $(echo "$R" | head -c 160)"
sys "update crm.inversionistas set no_contactar=false, no_contactar_en=null, no_contactar_por=null where id='$IP2'"
# [auditor M3] marcar por un lead de Q también cancela la tarea de cliente de PF2, unido a Q solo por el DOCUMENTO
LQ="$(uuid)"; lead_on "$LQ" 37 LQ "'$D2'"
TPF2="$(tarea_perfil "$V" "$PF2")"; [[ "$(estado_tarea "$TPF2")" == "pendiente -" && "$(q "select inversionista_id from crm.leads where id='$LQ'")" == "$IP2" ]] && ok "fixture: LQ enlazado a Q y tarea de cliente pendiente en PF2 (perfil por documento)" || rojo "fixture LQ/TPF2: $TPF2"
R="$(marcar "$V" "$LQ")"; [[ "$(j "$R" ok)" == "True" && "$(estado_tarea "$TPF2")" == "cancelada sistema" ]] && ok "[M3] marcar(LQ) cancela la tarea de cliente del perfil unido por DOCUMENTO" || rojo "[D-3 HUECO M3] tarea de PF2: $(estado_tarea "$TPF2") $(echo "$R" | head -c 120)"
run_as "$G" "select crm.levantar_no_contactar('$LQ','fin M3 r$RUN')" >/dev/null; sys "update crm.leads set activo=false where id='$LQ'" >/dev/null

echo "== (5b) [Codex #7] marcar/levantar desde el lead SOLO-PUENTE (LP, sin DNI ni enlace) resuelven a la persona =="
R="$(marcar "$V" "$LP")"
[[ "$(j "$R" ok)" == "True" && "$(j "$R" inversionista_id)" == "$IP" && "$(j "$R" leads_afectados)" == "3" && "$(q "select no_contactar from crm.inversionistas where id='$IP'")" == "t" && "$(veto_de "$LS")" == "t" ]] && ok "marcar(LP) → P vetada por el puente, leads_afectados = 3 (LE, LS, LP)" || rojo "[D-3 HUECO #7] marcar(LP): $(echo "$R" | head -c 200) P=$(q "select no_contactar from crm.inversionistas where id='$IP'")"
R="$(levantar "$LP")"
[[ "$(j "$R" ok)" == "True" && "$(j "$R" inversionista_id)" == "$IP" && "$(q "select no_contactar from crm.inversionistas where id='$IP'")" == "f" && "$(veto_de "$LS")" == "f" && "$(q "select count(*) from private.leads_vetados_persona(array['$LP'::uuid])")" == "0" ]] && ok "levantar(LP) → P y su conjunto sin veto; el gate ya no ve a LP vetado" || rojo "[D-3 HUECO #7] levantar(LP): $(echo "$R" | head -c 200)"
echo "== (5c) [Codex #1] los leads se toman SIN esperar: con LS retenido por otra sesión, marcar → 40001 en el acto =="
psql "$PG" -q -c "begin; select 1 from crm.leads where id='$LS' for update; select pg_sleep(6); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1; T0=$(date +%s)
R="$(marcar "$V" "$LE")"; T1=$(date +%s)
echo "$R" | grep -q "40001" && [[ $((T1-T0)) -le 3 ]] && ok "marcar(LE) con LS retenido → 40001 «otra sesión está trabajando uno de los leads» en $((T1-T0)) s (sin esperar)" || rojo "[D-3 HUECO #1] marcar esperó o pasó: $((T1-T0)) s $(echo "$R" | grep -E 'ERROR|ok' | head -1 | cut -c1-140)"
wait $BG 2>/dev/null
[[ "$(q "select no_contactar from crm.inversionistas where id='$IP'")" == "f" && "$(veto_de "$LE")" == "f" ]] && ok "el 40001 no dejó veto a medias" || rojo "veto a medias tras 40001"
echo "== (5c bis) [Codex N1/#5] la tarea de cliente no espera a la persona: con P retenida por otra sesión, agendar → 40001; con una tarea retenida, marcar → 40001 =="
psql "$PG" -q -c "begin; select 1 from crm.inversionistas where id='$IP' for update; select pg_sleep(6); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1; T0=$(date +%s)
R="$(tarea_perfil "$V" "$PF")"; T1=$(date +%s)
echo "$R" | grep -q "40001" && [[ $((T1-T0)) -le 3 ]] && ok "tarea de cliente con la persona retenida → 40001 en $((T1-T0)) s (sin esperar con la tarea en la mano)" || rojo "[D-3 HUECO N1] tarea de cliente esperó o pasó: $((T1-T0)) s $(echo "$R" | head -c 140)"
wait $BG 2>/dev/null
TX="$(tarea_perfil "$V" "$PF")"; [[ -n "$TX" && ! "$TX" =~ ERROR ]] && ok "fixture: tarea de cliente TX pendiente en PF" || rojo "fixture TX: $TX"
psql "$PG" -q -c "begin; select 1 from crm.tareas where id='$TX' for update; select pg_sleep(6); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1; T0=$(date +%s)
R="$(marcar "$V" "$LE")"; T1=$(date +%s)
echo "$R" | grep -q "40001" && [[ $((T1-T0)) -le 3 ]] && ok "marcar con una tarea de la persona retenida → 40001 en $((T1-T0)) s" || rojo "[D-3 HUECO N1] marcar esperó o pasó: $((T1-T0)) s $(echo "$R" | grep -E 'ERROR|ok' | head -1 | cut -c1-140)"
wait $BG 2>/dev/null
[[ "$(q "select no_contactar from crm.inversionistas where id='$IP'")" == "f" ]] && ok "sin veto a medias" || rojo "veto a medias"
sys "update crm.tareas set estado='cancelada', cancelada_por='sistema' where id='$TX'" >/dev/null

echo "== (5d) [Codex #12] el motivo no puede llevar el documento de la persona =="
R="$(run_as "$V" "select crm.marcar_no_contactar('$LE', 'no llamar al DNI $D')")"; echo "$R" | grep -q "22023" && [[ "$(q "select no_contactar from crm.inversionistas where id='$IP'")" == "f" ]] && ok "marcar con el DNI en el motivo → 22023, sin veto" || rojo "motivo con DNI pasó: $(echo "$R" | head -c 160)"

echo "== (6) Paridad con la bandera APAGADA =="
LNULO="$(run_as "$G" "insert into crm.actividades (lead_id, tipo, detalle, creado_por) values (null, 'llamada_realizada', 'D3 paridad r$RUN', '$G')")"; flag false
R="$(run_as "$G" "insert into crm.actividades (lead_id, tipo, detalle, creado_por) values (null, 'llamada_realizada', 'D3 paridad r$RUN', '$G')")"; echo "$R" | grep -q "42501" && ! echo "$R" | grep -q "42703" && ok "[Codex #10] OFF: una actividad sin lead → 42501 (policy), como hoy; nunca 42703 (el trigger compartido sigue byte a byte)" || rojo "[D-3 HUECO #10] actividad sin lead con OFF: $(echo "$R" | grep -E 'ERROR' | head -1 | cut -c1-140)"
flag true; flag false
flag false
LO="$(uuid)"; DO="3${RUN}6"
sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$LO','D3 OFF r$RUN','9${RUN}36','$DO',1000,'landing','nuevo',null,'$V')"
R="$(marcar "$V" "$LO")"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" leads_afectados)" == "1" && -z "$(j "$R" inversionista_id)" ]] && ok "OFF: marcar actúa solo sobre el lead (leads_afectados = 1, sin persona), como hoy" || rojo "OFF marcar: $(echo "$R" | head -c 200)"
sys "update crm.inversionistas set no_contactar=true, no_contactar_en=now(), no_contactar_por='$G' where id='$IP'"
R="$(tarea_perfil "$V" "$PF")"; echo "$R" | grep -q "ERROR" && rojo "OFF: la tarea de cliente se bloqueó con la bandera apagada: $(echo "$R" | head -c 160)" || ok "OFF: la tarea de cliente entra aunque la persona esté vetada (sin gate, como hoy)"
R="$(act_cliente "$V" "$PF" llamada_realizada)"; echo "$R" | grep -q "ERROR" && rojo "OFF: la ficha se bloqueó: $(echo "$R" | head -c 160)" || ok "OFF: la ficha admite contacto aunque la persona esté vetada (como hoy)"
[[ "$(q "select private.persona_vetada_perfil('$PF')" 2>/dev/null)" != "t" ]] && ok "OFF: persona_vetada_perfil siempre false" || rojo "OFF: helper true"
sys "update crm.inversionistas set no_contactar=false, no_contactar_en=null, no_contactar_por=null where id='$IP'"
run_as "$G" "select crm.levantar_no_contactar('$LO','fin r$RUN')" >/dev/null

echo "== Limpieza =="
sys "update crm.tareas set estado='cancelada', cancelada_por='sistema' where estado='pendiente' and (lead_id in ('$LS','$LP','$LO') or perfil_id in ('$PF','$PF2'))" >/dev/null
sys "update crm.leads set activo=false where id in ('$LS','$LP','$LO')" >/dev/null
flag false
echo; if [[ "$ROJO" -eq 0 ]]; then echo "ORÁCULO D-3: TODO VERDE (RUN=$RUN)"; else echo "ORÁCULO D-3: $ROJO ROJOS (RUN=$RUN)"; exit 1; fi
