#!/usr/bin/env bash
# ORÁCULO F2.b [D-2] — la salida de un analista no deja personas sin responsable (offboarding atómico sobre los tramos) y el
# nuevo responsable de relación recibe capacidad operativa — SOLO en el BANCO. Presupone b1..b5 + D-13 y siembra-banco-f3.sql (V/S/G).
# Crea dos vendedores más bajo S (V2 = reemplazo, V3 = saliente) para no tocar a V, que usan los demás oráculos.
# Las personas se crean VERIFICADAS por el resolver (una identidad nacida de un lead no queda verificada) y el lead nace después,
# enlazado. uq_leads_dni_vivo solo admite un lead vivo por DNI.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d2.sh   (lee $S/banco-pooler.txt). Sin D-2 (mutante) las secciones (2), (3) y (5) deben salir ROJAS.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
V2='f3000000-0000-0000-0000-000000000004'; V3='f3000000-0000-0000-0000-000000000005'
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
v=d.get(sys.argv[2])
if isinstance(v, dict): v=json.dumps(v, sort_keys=True)
print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
jj()   { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]) or {}; v=v.get(sys.argv[3]); print('' if v is None else v)" "$1" "$2" "$3" 2>/dev/null; }
persona() { q "select private.inversionista_resolver('DNI','$1',true,'ensayo-d2')"; }
actor() { sys "insert into auth.users (id) values ('$1') on conflict (id) do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$1','$2','comercial','DNI','$3') on conflict (id) do update set activo = true; insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por) values ('$1','vendedor','$SUP',true,'$SUP') on conflict (perfil_id) do update set rol_crm='vendedor', supervisor_id='$SUP', activo=true"; }
lead_de() { sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id,asignado_supervisor_id) values ('$1','D2 $3 r$RUN','9${RUN}$2',$4,1000,'landing','nuevo',null,$5,$6)"; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$1') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','D2 CLIENTE $2 r$RUN','cliente','DNI',$3,'$4','$5',true); commit;" 2>&1 | grep -E "ERROR"; }
reasignar() { run_as "$G" "select crm.reasignar_responsable_relacion_fn('$1','$2','ensayo D-2 r$RUN')"; }
impacto() { run_as "$G" "select crm.impacto_desactivacion_usuario_fn('$1')"; }
version_de() { q "select actualizado_en from crm.equipo where perfil_id='$1'"; }
baja() { run_as "$G" "select crm.fijar_membresia_activa_fn('$1', false, $2, '$(version_de "$1")'::timestamptz, '$3')"; }
alta() { run_as "$G" "select crm.fijar_membresia_activa_fn('$1', true, null, '$(version_de "$1")'::timestamptz, '$2')"; }
tramo_abierto() { q "select responsable_id||' '||coalesce(motivo,'-')||' '||coalesce(por::text,'-') from crm.inversionista_responsables where inversionista_id='$1' and hasta is null"; }
n_abiertos() { q "select count(*) from crm.inversionista_responsables where inversionista_id='$1' and hasta is null"; }
resp_de() { q "select responsable_relacion_id from crm.inversionistas where id='$1'"; }
vendedor_de() { q "select coalesce(vendedor_id::text,'null')||' '||coalesce(asignado_supervisor_id::text,'null') from crm.leads where id='$1'"; }
tarea_lead() { run_as "$1" "insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por) values ('$2','llamada','D2 tarea lead r$RUN', now() + interval '1 day', '$1') returning id" | grep -vE '^(LOCATION|DETAIL|HINT|CONTEXT|\{)' | tail -1; }
tarea_perfil() { run_as "$1" "insert into crm.tareas (perfil_id, tipo, titulo, vence_en, creado_por) values ('$2','llamada','D2 tarea cliente r$RUN', now() + interval '1 day', '$1') returning id" | grep -vE '^(LOCATION|DETAIL|HINT|CONTEXT|\{)' | tail -1; }
JER="pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)"

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
if [[ "$(q "select (strpos(p.prosrc, 'F2.b [D-2]') > 0) from pg_proc p where p.oid = 'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)'::regprocedure")" == "t" ]]; then echo "  D-2 instalada (todo debe salir VERDE)"; else echo "  ⚠️ D-2 NO instalada: corrida MUTANTE ((2), (3) y (5) deben salir ROJAS)"; fi
actor "$V2" "D2 VENDEDOR DOS" 70000094; actor "$V3" "D2 VENDEDOR TRES" 70000095
[[ "$(q "select count(*) from crm.equipo where perfil_id in ('$V2','$V3') and activo and rol_crm='vendedor' and supervisor_id='$SUP'")" == "2" ]] && ok "V2 y V3 activos como vendedores de S" || rojo "actores V2/V3"
flag true

echo "== (1) Fixture: P1 (lead L1 de V3) con tramo abierto a V3; P2 (lead L2 de V3) idem =="
# línea base: personas que ya apuntan a V3 (residuo de corridas anteriores abortadas); las aserciones cuentan a partir de ella
personas_de() { q "select count(*) from crm.inversionistas i where i.estado='activo' and (i.responsable_relacion_id='$1' or exists (select 1 from crm.inversionista_responsables r where r.inversionista_id=i.id and r.hasta is null and r.responsable_id='$1'))"; }
PRE_P="$(personas_de "$V3")"; [[ "$PRE_P" == "0" ]] || echo "  (línea base: V3 ya tenía $PRE_P persona(s) a cargo de una corrida anterior)"
D1="5${RUN}1"; P1="$(persona "$D1")"; L1="$(uuid)"; lead_de "$L1" 41 L1 "'$D1'" "'$V3'" null
D2="5${RUN}2"; P2="$(persona "$D2")"; L2="$(uuid)"; lead_de "$L2" 42 L2 "'$D2'" "'$V3'" null
[[ -n "$P1" && -n "$P2" && "$(q "select inversionista_id from crm.leads where id='$L1'")" == "$P1" && "$(q "select inversionista_id from crm.leads where id='$L2'")" == "$P2" ]] && ok "P1=$P1 y P2=$P2 (verificadas); L1 y L2 nacieron enlazados (leads de V3)" || rojo "fixture P1/P2: L1→$(q "select inversionista_id from crm.leads where id='$L1'")"
R="$(reasignar "$P1" "$V3")"; R2="$(reasignar "$P2" "$V3")"
[[ "$(j "$R" estado)" == "reasignado" && "$(tramo_abierto "$P1")" == "$V3 ensayo D-2 r$RUN $G" && "$(resp_de "$P1")" == "$V3" && "$(tramo_abierto "$P2")" == "$V3 ensayo D-2 r$RUN $G" ]] && ok "tramos abiertos de P1 y P2 → V3 (b5)" || rojo "tramos fixture: $(tramo_abierto "$P1") / $(echo "$R" | head -c 200)"
[[ "$(vendedor_de "$L1")" == "$V3 null" ]] && ok "L1 sigue en la cartera de V3 (ya era suyo: sin movimiento)" || rojo "L1: $(vendedor_de "$L1")"

echo "== (2) impacto_desactivacion_usuario_fn(V3): con ON cuenta las personas; con OFF byte a byte como hoy =="
R="$(impacto "$V3")"
[[ "$(j "$R" personas_a_cargo)" == "$((PRE_P+2))" && "$(j "$R" requiere_reemplazo)" == "True" ]] && ok "ON: personas_a_cargo = $((PRE_P+2)) y requiere_reemplazo" || rojo "[D-2 HUECO] impacto ON: $(echo "$R" | tail -1 | head -c 240)"
flag false; R="$(impacto "$V3")"; flag true
[[ -z "$(j "$R" personas_a_cargo)" && "$(j "$R" leads_abiertos)" == "2" && "$(j "$R" requiere_reemplazo)" == "True" ]] && ok "OFF: sin la clave personas_a_cargo (esquema estricto del front), leads_abiertos = 2, como hoy" || rojo "impacto OFF: $(echo "$R" | head -c 240)"
[[ "$(echo "$R" | tail -1 | grep -o '"[a-z_]*":' | sort | tr -d '\n')" == '"clientes_activos":"leads_abiertos":"leads_en_bandeja":"perfil_id":"requiere_reemplazo":"subordinados_activos":"tareas_pendientes":' ]] && ok "OFF: exactamente las 7 claves de hoy" || rojo "OFF claves: $(echo "$R" | tail -1 | grep -o '"[a-z_]*":' | sort | tr -d '\n')"

echo "== (3) Baja de V3 → V2: tramos cerrados y reabiertos al reemplazo en la misma transacción; leads y tareas también =="
T1="$(tarea_lead "$V3" "$L1")"; [[ -n "$T1" && ! "$T1" =~ ERROR ]] && ok "fixture: tarea pendiente T1 de L1 (V3)" || rojo "tarea T1: $T1"
IDEM="$(uuid)"; R="$(baja "$V3" null "$IDEM")"; echo "$R" | grep -q "conserva dependencias" && ok "baja de V3 SIN reemplazo → se niega (personas/leads a cargo)" || rojo "baja sin reemplazo: $(echo "$R" | head -c 200)"
IDEM="$(uuid)"; R="$(baja "$V3" "'$V2'" "$IDEM")"
[[ "$(j "$R" activo_crm)" == "False" && "$(j "$R" idempotente)" == "False" ]] && ok "baja de V3 con reemplazo V2 → ok" || rojo "baja: $(echo "$R" | head -c 240)"
[[ "$(tramo_abierto "$P1")" == "$V2 offboarding $G" && "$(n_abiertos "$P1")" == "1" ]] && ok "P1: un solo tramo abierto → V2, motivo offboarding, por Gerencia" || rojo "[D-2 HUECO] P1 tramo abierto: '$(tramo_abierto "$P1")' (n=$(n_abiertos "$P1"))"
[[ "$(tramo_abierto "$P2")" == "$V2 offboarding $G" && "$(n_abiertos "$P2")" == "1" ]] && ok "P2: idem" || rojo "[D-2 HUECO] P2 tramo abierto: '$(tramo_abierto "$P2")'"
[[ "$(q "select count(*) from crm.inversionista_responsables where inversionista_id in ('$P1','$P2') and responsable_id='$V3' and hasta is not null and motivo='ensayo D-2 r$RUN'")" == "2" ]] && ok "los tramos de V3 quedaron cerrados (hasta) conservando su motivo" || rojo "tramos de V3 no cerrados"
[[ "$(q "select count(*) from crm.inversionista_responsables r join crm.inversionista_responsables r2 on r2.inversionista_id=r.inversionista_id and r2.hasta is null where r.inversionista_id in ('$P1','$P2') and r.hasta is not null and r2.desde = r.hasta")" == "2" ]] && ok "hasta del viejo = desde del nuevo (un único v_ahora tras los locks)" || rojo "hasta/desde no coinciden"
[[ "$(resp_de "$P1")" == "$V2" && "$(resp_de "$P2")" == "$V2" ]] && ok "responsable_relacion_id = V2 en ambas" || rojo "[D-2 HUECO] responsable_relacion_id: $(resp_de "$P1") / $(resp_de "$P2")"
[[ "$(q "select count(*) from crm.inversionista_responsables where responsable_id='$V3' and hasta is null")" == "0" && "$(q "select count(*) from crm.inversionistas where estado='activo' and responsable_relacion_id='$V3'")" == "0" ]] && ok "V3 no conserva ningún tramo abierto ni persona apuntándole" || rojo "[D-2 HUECO] V3 sigue siendo responsable de alguien"
[[ "$(vendedor_de "$L1")" == "$V2 null" && "$(vendedor_de "$L2")" == "$V2 null" ]] && ok "L1 y L2 transferidos a V2 (como hoy)" || rojo "leads: $(vendedor_de "$L1") / $(vendedor_de "$L2")"
[[ "$(q "select vendedor_id from crm.tareas where id='$T1'")" == "$V2" ]] && ok "T1 transferida a V2 (como hoy)" || rojo "T1: $(q "select vendedor_id from crm.tareas where id='$T1'")"
[[ "$(q "select detalle->>'personas_transferidas' from crm.usuario_eventos where idempotencia='$IDEM'")" == "$((PRE_P+2))" ]] && ok "evento membresia_desactivada: personas_transferidas = $((PRE_P+2))" || rojo "[D-2 HUECO] evento: personas_transferidas = '$(q "select detalle->>'personas_transferidas' from crm.usuario_eventos where idempotencia='$IDEM'")'"
R="$(baja "$V3" "'$V2'" "$IDEM")"; [[ "$(j "$R" idempotente)" == "True" && "$(n_abiertos "$P1")" == "1" ]] && ok "replay con la misma idempotencia → idempotente, sin tramo nuevo" || rojo "replay: $(echo "$R" | head -c 200) n=$(n_abiertos "$P1")"
IDEM="$(uuid)"; R="$(alta "$V3" "$IDEM")"; [[ "$(j "$R" activo_crm)" == "True" && "$(tramo_abierto "$P1")" == "$V2 offboarding $G" ]] && ok "reactivar V3 → ok y los tramos se quedan en V2 (la reactivación no devuelve nada)" || rojo "reactivar: $(echo "$R" | head -c 200)"

echo "== (4) Paridad con la bandera APAGADA: la baja no toca tramos ni añade la clave al evento =="
D3="5${RUN}3"; P3="$(persona "$D3")"; L3="$(uuid)"; lead_de "$L3" 43 L3 "'$D3'" "'$V3'" null; R="$(reasignar "$P3" "$V3")"
[[ "$(tramo_abierto "$P3")" == "$V3 ensayo D-2 r$RUN $G" && "$(vendedor_de "$L3")" == "$V3 null" ]] && ok "fixture: P3 con tramo abierto a V3 y lead L3 de V3" || rojo "fixture P3: $(echo "$R" | head -c 200)"
flag false; IDEM="$(uuid)"; R="$(baja "$V3" "'$V2'" "$IDEM")"; flag true
[[ "$(j "$R" activo_crm)" == "False" && "$(tramo_abierto "$P3")" == "$V3 ensayo D-2 r$RUN $G" && "$(resp_de "$P3")" == "$V3" && "$(vendedor_de "$L3")" == "$V2 null" ]] && ok "OFF: L3 transferido pero el tramo de P3 sigue en V3 (como hoy: la identidad no existe para el offboarding)" || rojo "OFF: tramo $(tramo_abierto "$P3") lead $(vendedor_de "$L3") $(echo "$R" | head -c 160)"
[[ "$(q "select (detalle ? 'personas_transferidas') from crm.usuario_eventos where idempotencia='$IDEM'")" == "f" ]] && ok "OFF: el evento NO lleva personas_transferidas (payload de hoy)" || rojo "OFF: el evento lleva la clave nueva"
IDEM="$(uuid)"; alta "$V3" "$IDEM" >/dev/null; [[ "$(q "select activo from crm.equipo where perfil_id='$V3'")" == "t" ]] && ok "V3 reactivado para lo que sigue" || rojo "V3 no reactivado"
R="$(reasignar "$P3" "$V2")"; [[ "$(j "$R" estado)" == "reasignado" ]] && ok "P3 reasignada a V2 (limpieza del fixture OFF)" || rojo "reasignar P3: $(echo "$R" | head -c 200)"

echo "== (5) reasignar_responsable_relacion_fn: capacidad operativa del nuevo responsable =="
T1b="$(tarea_lead "$V2" "$L1")"; [[ -n "$T1b" && ! "$T1b" =~ ERROR ]] && ok "fixture: tarea pendiente T1b de L1 (hoy de V2)" || rojo "tarea T1b: $T1b"
N_LA0="$(q "select count(*) from crm.lead_asignaciones where lead_id='$L1'")"; N_NOTA0="$(q "select count(*) from crm.actividades where lead_id='$L1' and metadata->>'evento'='reasignacion_responsable'")"
R="$(reasignar "$P1" "$V3")"
[[ "$(j "$R" estado)" == "reasignado" && "$(jj "$R" tenencia estado)" == "movida" && "$(jj "$R" tenencia leads_movidos)" == "1" && "$(jj "$R" tenencia perfil_movido)" == "False" ]] && ok "P1 → V3: reasignado, tenencia movida (1 lead, sin perfil)" || rojo "[D-2 HUECO] reasignar P1→V3: $(echo "$R" | head -c 300)"
[[ "$(tramo_abierto "$P1")" == "$V3 ensayo D-2 r$RUN $G" && "$(resp_de "$P1")" == "$V3" ]] && ok "tramo abierto → V3" || rojo "tramo: $(tramo_abierto "$P1")"
[[ "$(vendedor_de "$L1")" == "$V3 null" ]] && ok "L1 pasó a la cartera de V3 (vendedor_id, sin bandeja)" || rojo "[D-2 HUECO] L1: $(vendedor_de "$L1")"
[[ "$(q "select vendedor_id from crm.tareas where id='$T1b'")" == "$V3" && "$(q "select estado from crm.tareas where id='$T1b'")" == "pendiente" ]] && ok "T1b (pendiente) siguió al lead → V3" || rojo "[D-2 HUECO] T1b: $(q "select vendedor_id||' '||estado from crm.tareas where id='$T1b'")"
[[ "$(q "select count(*) from crm.lead_asignaciones where lead_id='$L1'")" == "$((N_LA0+1))" && "$(q "select analista_id||' '||motivo_apertura from crm.lead_asignaciones where lead_id='$L1' and finalizado_en is null")" == "$V3 reasignado" && "$(q "select motivo_cierre||' '||analista_destino_id from crm.lead_asignaciones where lead_id='$L1' and finalizado_en is not null order by finalizado_en desc limit 1")" == "transferido $V3" ]] && ok "ledger de asignaciones: episodio de V2 cerrado como transferido → V3, episodio nuevo 'reasignado' abierto en V3" || rojo "ledger L1: $(q "select string_agg(analista_id||':'||motivo_apertura||':'||coalesce(motivo_cierre,'-'), ' | ' order by asignado_en) from crm.lead_asignaciones where lead_id='$L1'")"
[[ "$(q "select count(*) from crm.actividades where lead_id='$L1' and tipo='reasignacion' and metadata->>'vendedor_nuevo'='$V3' and metadata->>'vendedor_anterior'='$V2'")" == "1" ]] && ok "actividad «reasignacion» V2 → V3 en L1" || rojo "actividad de reasignación ausente"
[[ "$(q "select count(*) from crm.actividades where lead_id='$L1' and metadata->>'evento'='reasignacion_responsable'")" == "$((N_NOTA0+1))" && "$(q "select metadata->>'nuevo' from crm.actividades where lead_id='$L1' and metadata->>'evento'='reasignacion_responsable' order by creado_en desc limit 1")" == "$V3" ]] && ok "nota de b5 «responsable reasignado» (nuevo = V3) presente, una por llamada" || rojo "nota b5: $(q "select count(*) from crm.actividades where lead_id='$L1' and metadata->>'evento'='reasignacion_responsable'") (antes $N_NOTA0)"
R="$(reasignar "$P1" "$V3")"; [[ "$(j "$R" estado)" == "sin_cambios" ]] && ok "repetir → sin_cambios" || rojo "repetir: $(echo "$R" | head -c 200)"
R="$(reasignar "$P1" "$G")"
[[ "$(j "$R" estado)" == "reasignado" && "$(jj "$R" tenencia estado)" == "sin_cambios" && "$(tramo_abierto "$P1")" == "$G ensayo D-2 r$RUN $G" && "$(vendedor_de "$L1")" == "$V3 null" ]] && ok "P1 → Gerencia: tramo a G, la cartera NO se mueve (Gerencia no tiene cartera): L1 sigue en V3" || rojo "[D-2 HUECO] P1→G: $(echo "$R" | head -c 200) L1=$(vendedor_de "$L1")"
# [auditor M7] el nuevo responsable es un SUPERVISOR: también recibe la cartera (vendedor_id = supervisor, sin bandeja)
R="$(reasignar "$P1" "$SUP")"
[[ "$(j "$R" estado)" == "reasignado" && "$(jj "$R" tenencia estado)" == "movida" && "$(vendedor_de "$L1")" == "$SUP null" && "$(q "select analista_id||' '||motivo_apertura from crm.lead_asignaciones where lead_id='$L1' and finalizado_en is null")" == "$SUP reasignado" ]] && ok "P1 → supervisor S: tramo a S y L1 a la cartera de S (ledger 'reasignado' en S)" || rojo "[D-2 HUECO] P1→S: $(echo "$R" | head -c 200) L1=$(vendedor_de "$L1")"
R="$(reasignar "$P1" "$V3")"; [[ "$(vendedor_de "$L1")" == "$V3 null" ]] && ok "P1 → V3 de vuelta: L1 a V3" || rojo "vuelta a V3: $(vendedor_de "$L1")"
# persona con PERFIL cliente y tarea de cliente pendiente
D4="5${RUN}4"; P4="$(persona "$D4")"; L4="$(uuid)"; lead_de "$L4" 44 L4 "'$D4'" "'$V3'" null; PF4="$(uuid)"
sim_perfil "$PF4" P4 "'$D4'" "d2p4$RUN@x.pe" "$V3"; sys "update crm.inversionistas set perfil_id='$PF4' where id='$P4'"
TP4="$(tarea_perfil "$V3" "$PF4")"; [[ -n "$TP4" && ! "$TP4" =~ ERROR && "$(q "select inversionista_id from crm.leads where id='$L4'")" == "$P4" ]] && ok "fixture: P4 con lead L4 (V3), perfil PF4 (asesor V3) y tarea de cliente pendiente TP4" || rojo "fixture P4/PF4: $TP4"
R="$(reasignar "$P4" "$V2")"
[[ "$(j "$R" estado)" == "reasignado" && "$(jj "$R" tenencia perfil_movido)" == "True" && "$(jj "$R" tenencia leads_movidos)" == "1" ]] && ok "P4 → V2: tenencia movida (1 lead + perfil)" || rojo "[D-2 HUECO] reasignar P4→V2: $(echo "$R" | head -c 300)"
[[ "$(q "select asesor_perfil_id from public.perfiles where id='$PF4'")" == "$V2" ]] && ok "PF4.asesor_perfil_id = V2 (la cartera del Portal sigue al responsable)" || rojo "[D-2 HUECO] asesor de PF4: $(q "select asesor_perfil_id from public.perfiles where id='$PF4'")"
[[ "$(q "select vendedor_id||' '||coalesce(asignado_supervisor_id::text,'null')||' '||estado from crm.tareas where id='$TP4'")" == "$V2 $SUP pendiente" ]] && ok "TP4 (tarea de cliente) → V2 con la bandeja de su supervisor S (trigger del perfil)" || rojo "TP4: $(q "select vendedor_id||' '||coalesce(asignado_supervisor_id::text,'null')||' '||estado from crm.tareas where id='$TP4'")"
[[ "$(q "select count(*) from crm.actividades_cliente where cliente_id='$PF4' and tipo='reasignacion'")" == "1" ]] && ok "actividad de cliente «reasignacion» dejada por el trigger del perfil" || rojo "sin actividad de cliente"
[[ "$(vendedor_de "$L4")" == "$V2 null" ]] && ok "L4 → V2" || rojo "L4: $(vendedor_de "$L4")"
R="$(reasignar "$P4" "$V2")"; [[ "$(j "$R" estado)" == "sin_cambios" ]] && ok "repetir P4 → V2: sin_cambios" || rojo "repetir P4: $(echo "$R" | head -c 200)"
# lead en BANDEJA del supervisor (sin vendedor)
D5="5${RUN}5"; P5="$(persona "$D5")"; L5="$(uuid)"; lead_de "$L5" 45 L5 "'$D5'" null "'$SUP'"
[[ -n "$P5" && "$(vendedor_de "$L5")" == "null $SUP" && "$(q "select inversionista_id from crm.leads where id='$L5'")" == "$P5" ]] && ok "fixture: P5 con lead L5 en la bandeja de S" || rojo "fixture L5: $(vendedor_de "$L5")"
R="$(reasignar "$P5" "$V2")"
[[ "$(j "$R" estado)" == "reasignado" && "$(vendedor_de "$L5")" == "$V2 null" && "$(q "select analista_id||' '||motivo_apertura||' '||coalesce(supervisor_origen_id::text,'-') from crm.lead_asignaciones where lead_id='$L5' and finalizado_en is null")" == "$V2 asignado $SUP" ]] && ok "P5 → V2: el lead sale de la bandeja de S a la cartera de V2 (ledger 'asignado' con supervisor_origen S)" || rojo "[D-2 HUECO] L5: $(vendedor_de "$L5") $(echo "$R" | head -c 200)"
# lead SUELTO con el documento de la persona (D-13: también es de la persona); un lead cerrado no se mueve
D6="5${RUN}6"; P6="$(persona "$D6")"; L6b="$(uuid)"; flag false; lead_de "$L6b" 47 L6b "'$D6'" "'$V3'" null; flag true
[[ -n "$P6" && "$(q "select inversionista_id is null and activo from crm.leads where id='$L6b'")" == "t" ]] && ok "fixture: P6 (verificada, sin leads enlazados) y L6b SUELTO vivo con su DNI (nacido con OFF, de V3)" || rojo "fixture L6b"
R="$(reasignar "$P6" "$V2")"; [[ "$(jj "$R" tenencia leads_movidos)" == "1" && "$(vendedor_de "$L6b")" == "$V2 null" ]] && ok "P6 → V2: el suelto con su documento pasa a V2" || rojo "[D-2 HUECO] P6: movidos=$(jj "$R" tenencia leads_movidos) L6b=$(vendedor_de "$L6b")"
sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes', descartado_en=now(), descartado_por='$V2' where id='$L6b'" >/dev/null
R="$(reasignar "$P6" "$V3")"; [[ "$(j "$R" estado)" == "reasignado" && "$(jj "$R" tenencia leads_movidos)" == "0" && "$(vendedor_de "$L6b")" == "$V2 null" ]] && ok "P6 → V3: el descartado L6b no se mueve (0 leads); el tramo sí" || rojo "cerrado movido: $(echo "$R" | head -c 200) L6b=$(vendedor_de "$L6b")"

echo "== (6) Interlock: con una baja en curso (jerarquía exclusiva), reasignar espera y muere por lock_timeout (5 s) =="
psql "$PG" -q -c "begin; select pg_advisory_xact_lock($JER); select pg_sleep(9); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1
R="$(reasignar "$P1" "$V2")"; echo "$R" | grep -q "55P03" && ok "reasignar bajo una baja en curso → 55P03 (lock_timeout): no se cruzan" || rojo "interlock: $(echo "$R" | head -c 200)"
wait $BG 2>/dev/null

echo "== (6b) [Codex #1] los leads se toman SIN esperar: con L1 retenido por otra sesión (como derivar), reasignar → 40001 en el acto =="
T_ANTES="$(tramo_abierto "$P1")"
psql "$PG" -q -c "begin; select 1 from crm.leads where id='$L1' for update; select pg_sleep(6); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1; T0=$(date +%s)
R="$(reasignar "$P1" "$V2")"; T1=$(date +%s)
echo "$R" | grep -q "40001" && [[ $((T1-T0)) -le 3 ]] && ok "reasignar con L1 retenido → 40001 en $((T1-T0)) s (sin esperar, sin tramo nuevo)" || rojo "[D-2 HUECO #1] reasignar esperó o pasó: $((T1-T0)) s $(echo "$R" | grep -E 'ERROR|estado' | head -1 | cut -c1-140)"
wait $BG 2>/dev/null
[[ "$(tramo_abierto "$P1")" == "$T_ANTES" ]] && ok "el 40001 no dejó tramo a medias (sigue como antes)" || rojo "tramo tras 40001: $(tramo_abierto "$P1") (antes: $T_ANTES)"

echo "== (6c) [Codex N2] la baja no espera a una persona retenida (censo NOWAIT): con P2 retenida por otra sesión, baja V2 → V3 → 40001 =="
T_ANTES="$(tramo_abierto "$P2")"
psql "$PG" -q -c "begin; select 1 from crm.inversionistas where id='$P2' for update; select pg_sleep(6); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1; T0=$(date +%s)
IDEM="$(uuid)"; R="$(baja "$V2" "'$V3'" "$IDEM")"; T1=$(date +%s)
echo "$R" | grep -q "40001" && [[ $((T1-T0)) -le 3 ]] && ok "baja de V2 con una persona suya retenida → 40001 en $((T1-T0)) s" || rojo "[D-2 HUECO N2] la baja esperó o pasó: $((T1-T0)) s $(echo "$R" | grep -E 'ERROR|activo_crm' | head -1 | cut -c1-140)"
wait $BG 2>/dev/null
[[ "$(q "select activo from crm.equipo where perfil_id='$V2'")" == "t" && "$(tramo_abierto "$P2")" == "$T_ANTES" ]] && ok "V2 sigue activo y el tramo de P2 intacto (nada a medias)" || rojo "estado tras 40001: V2 activo=$(q "select activo from crm.equipo where perfil_id='$V2'") tramo=$(tramo_abierto "$P2")"

echo "== (7) Paridad OFF de reasignar y autorización =="
flag false; R="$(reasignar "$P1" "$V2")"; echo "$R" | grep -q "P0409" && ok "OFF: reasignar → P0409 apagada (b5)" || rojo "OFF reasignar: $(echo "$R" | head -c 160)"; flag true
R="$(run_as "$V3" "select crm.reasignar_responsable_relacion_fn('$P1','$V2','x')")"; echo "$R" | grep -q "42501" && ok "un vendedor no reasigna → 42501" || rojo "vendedor reasignó: $(echo "$R" | head -c 160)"

echo "== Limpieza (las personas de la corrida pasan a Gerencia para no dejar residuo en V2/V3) =="
sys "update crm.tareas set estado='cancelada', cancelada_por='sistema' where estado='pendiente' and (lead_id in ('$L1','$L2','$L3','$L4','$L5','$L6b') or perfil_id='$PF4')" >/dev/null
sys "update crm.leads set activo=false where id in ('$L1','$L2','$L3','$L4','$L5','$L6b')" >/dev/null
for P in "$P1" "$P2" "$P3" "$P4" "$P5" "$P6"; do reasignar "$P" "$G" >/dev/null; done
sys "update public.perfiles set activo=false where id='$PF4'" >/dev/null
[[ "$(personas_de "$V3")" == "$PRE_P" && "$(personas_de "$V2")" == "0" ]] && ok "V2 y V3 sin personas de esta corrida" || echo "  (residuo: V3=$(personas_de "$V3") V2=$(personas_de "$V2"))"
flag false
echo; if [[ "$ROJO" -eq 0 ]]; then echo "ORÁCULO D-2: TODO VERDE (RUN=$RUN)"; else echo "ORÁCULO D-2: $ROJO ROJOS (RUN=$RUN)"; exit 1; fi
