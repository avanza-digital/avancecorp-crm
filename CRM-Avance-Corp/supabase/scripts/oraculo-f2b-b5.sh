#!/usr/bin/env bash
# ORÁCULO F2.b sub-lote b5 (E3) — fusión, corrección documental, enlace de lead suelto y reasignación — SOLO en el BANCO.
# Dos sesiones psql reales para los intercalados; `run_as` cambia el ROL SQL (authenticated) y las claims: prueba
# también los grants. Presupone E1 + E2 + b5 y la siembra siembra-banco-f3.sql (actores V/S/G, leads L1..L5).
# Uso: S=/ruta/scratchpad ./oraculo-f2b-b5.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
L1="f31ead00-0000-0000-0000-${RUN}000001"; L2="f31ead00-0000-0000-0000-${RUN}000002"; L3="f31ead00-0000-0000-0000-${RUN}000003"
L4="f31ead00-0000-0000-0000-${RUN}000004"; L5="f31ead00-0000-0000-0000-${RUN}000005"
DA="5${RUN}1"; DB="5${RUN}2"; DC="5${RUN}3"; DD="5${RUN}4"; DE="5${RUN}5"; DF="5${RUN}6"; DG="5${RUN}7"; DH="5${RUN}8"; DX="5${RUN}9"; DA2="8${RUN}1"; DE2="8${RUN}5"
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
jj()   { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d
for k in sys.argv[2].split('.'):
    v=v.get(k) if isinstance(v,dict) else None
print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
alta() { run_as "$1" "select crm.alta_cliente_identidad_fn('$2', '$3'::jsonb)"; }
sim_auth()  { psql "$PG" -q -c "insert into auth.users (id, email, raw_app_meta_data) values ('$1', '$2', jsonb_build_object('claim_id','$3')) on conflict (id) do nothing;" 2>/dev/null; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','B5 CLIENTE $2 r$RUN','cliente','DNI','$2','$3','$V',true); commit;" 2>&1 | grep -E "ERROR"; }
coop() { run_as "$V" "select crm.convertir_lead_externo('$1','qorilazo',1000,'PEN','DNI','$2','B5 PERSONA','TRX-B5-${RUN}-$3')"; }
lead_dni() { psql "$PG" -q -c "begin; insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','B5 LEAD $3 r$RUN','9${RUN}$3',$2,1000,'landing','nuevo',null,'$V'); commit;" 2>&1 | grep -E "ERROR"; }
prev()  { run_as "$G" "select crm.fusion_previsualizar_fn('$1','$2')"; }
fus()   { run_as "$G" "select crm.fusionar_inversionistas_fn('$1','$2','$3','$4')"; }
corr()  { run_as "$G" "select crm.corregir_documento_inversionista_fn('$1','$2','$3','$4'${5:+,'$5'})"; }
enl()   { run_as "$G" "select crm.enlazar_lead_inversionista_fn('$1','$2','$3')"; }
reas()  { run_as "$1" "select crm.reasignar_responsable_relacion_fn('$2','$3','$4')"; }
inv_de() { q "select private.inversionista_por_documento('DNI','$1')"; }
huella_episodios() { q "select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from private.conversion_episodios(date_trunc('month', now()), date_trunc('month', now()) + interval '1 month', current_date, true, null, 1) t"; }
huella_sellados() { q "select (select count(*)||':'||md5(coalesce(string_agg(t::text,'|' order by t::text),'')) from crm.periodos_cerrados t)||' '||(select count(*)||':'||md5(coalesce(string_agg(t::text,'|' order by t::text),'')) from crm.cierre_mes_vendedor t)"; }
# saga completa de alta directa (b3): devuelve "inversionista_id perfil_id"
alta_completa() { # $1 doc, $2 correo, $3 nombre
  local R CL TK VER INV AU
  R="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$1\",\"correo\":\"$2\",\"nombre_completo\":\"$3\"}")"
  CL="$(j "$R" claim_id)"; TK="$(j "$R" token)"; VER="$(j "$R" version)"; INV="$(j "$R" inversionista_id)"
  [[ -n "$CL" ]] || { echo "ERROR reclamar: $R" >&2; return 1; }
  AU="$(uuid)"; sim_auth "$AU" "$2" "$CL"
  R="$(alta "$G" registrar_auth "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"auth_user_id\":\"$AU\",\"version\":$VER}")"; VER="$(j "$R" version)"
  sim_perfil "$AU" "$1" "$2"
  R="$(alta "$G" enlazar "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"version\":$VER}")"
  [[ "$(j "$R" estado)" == "enlazado" ]] || { echo "ERROR enlazar: $R" >&2; return 1; }
  echo "$INV $AU"
}

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select to_regprocedure('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)') is not null")" == "t" ]] || { echo "falta b5" >&2; exit 2; }
flag true; flag_inv true

echo "== Fixtures: PA (alta con perfil, veto), IX (resolver + lead VIVO LX + tarea), IB (coop L1 + cierre + inversión), IC (coop L2), PB (alta) =="
read -r PA PA_PERFIL <<<"$(alta_completa "$DA" "a$RUN@x.pe" "B5 A")"; [[ -n "$PA" ]] && ok "PA creada por la saga de alta (perfil $PA_PERFIL)" || rojo "PA no se creó"
R="$(coop "$L1" "$DB" 1)"; IB="$(inv_de "$DB")"; [[ -n "$IB" && "$(q "select etapa||' '||coalesce(inversionista_id::text,'') from crm.leads where id='$L1'")" == "convertido $IB" ]] && ok "IB creada por conversión coop de L1 (cierre + inversión con inversiones_escritura)" || rojo "IB: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
INV1="$(q "select id from crm.inversiones where inversionista_id='$IB' limit 1")"; CE1="$(q "select id from crm.cierres_externos where lead_id='$L1'")"
[[ -n "$INV1" && "$(q "select count(*) from crm.inversion_titulares where inversion_id='$INV1' and inversionista_id='$IB' and rol='principal'")" == "1" ]] && ok "IB es titular principal de su inversión" || rojo "sin inversión/titular para IB"
R="$(coop "$L2" "$DC" 2)"; IC="$(inv_de "$DC")"; [[ -n "$IC" ]] && ok "IC creada por conversión coop de L2" || rojo "IC: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
read -r PB PB_PERFIL <<<"$(alta_completa "$DD" "d$RUN@x.pe" "B5 D")"; [[ -n "$PB" ]] && ok "PB creada (segundo perfil)" || rojo "PB no se creó"
# IX: identidad creada por la primitiva (fixture) + lead LX con ese DNI insertado sin sesión → se enlaza al nacer (b1), vivo, con tarea pendiente
IX="$(q "select private.inversionista_resolver('DNI','$DX',true,'ensayo-b5')")"; LX="$(uuid)"; lead_dni "$LX" "'$DX'" 60 >/dev/null
[[ -n "$IX" && "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LX'")" == "nuevo $IX" ]] && ok "IX con lead VIVO LX enlazado al nacer" || rojo "IX/LX: $(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LX'")"
R="$(run_as "$V" "insert into crm.tareas (lead_id, vendedor_id, tipo, titulo, vence_en, creado_por) values ('$LX','$V','tarea','B5 seguimiento r$RUN', now() + interval '1 day', '$V')")"; echo "$R" | grep -q ERROR && rojo "tarea: $R" || ok "tarea pendiente en LX"
# veto por persona en PA (sin lead): fixture bajo válvula; predecesora Z fusionada en PA; PA cotitular en INV1 (de IB: se reapunta a IX)
sys "update crm.inversionistas set no_contactar=true, no_contactar_en=now(), no_contactar_por='$G' where id='$PA'"
Z="$(uuid)"; sys "insert into crm.inversionistas (id, estado, inversionista_canonico_id, fusionado_en) values ('$Z','fusionado','$PA',now())"
sys "insert into crm.inversion_titulares (inversion_id, inversionista_id, rol) values ('$INV1','$PA','cotitular')"
# INV3/CE3 «de PA» por fixture (matriz inversiones/cierres/titulares con C=IX ya cotitular): IE cede su inversión a PA
R="$(coop "$L3" "$DE" 3)"; IE="$(inv_de "$DE")"; INV3="$(q "select id from crm.inversiones where inversionista_id='$IE' limit 1")"; CE3="$(q "select id from crm.cierres_externos where lead_id='$L3'")"
sys "update crm.inversiones set inversionista_id='$PA' where id='$INV3'; update crm.inversion_titulares set inversionista_id='$PA' where inversion_id='$INV3' and rol='principal'; update crm.cierres_externos set inversionista_id='$PA' where id='$CE3'; insert into crm.inversion_titulares (inversion_id, inversionista_id, rol) values ('$INV3','$IX','cotitular')"
[[ "$(q "select count(*) from crm.inversion_titulares where inversion_id='$INV3'")" == "2" ]] && ok "INV3 (fixture): PA principal, IX cotitular; CE3 de PA" || rojo "fixture INV3"

echo "== Previsualización: bloqueos y advertencias =="
R="$(prev "$IC" "$IB")"; [[ "$(j "$R" viable)" == "False" ]] && echo "$R" | grep -q "dos leads" && ok "IC→IB: dos leads → no viable (bloqueo con diagnóstico)" || rojo "dos leads: $R"
R="$(prev "$PB" "$PA")"; [[ "$(j "$R" viable)" == "False" ]] && echo "$R" | grep -q "dos perfiles" && ok "PB→PA: dos perfiles → no viable" || rojo "dos perfiles: $R"
R="$(prev "$PA" "$PA")"; [[ "$(j "$R" viable)" == "False" ]] && ok "misma identidad → no viable" || rojo "misma: $R"
R="$(prev "$Z" "$IX")"; echo "$R" | grep -q "ya está fusionada" && ok "perdedora ya fusionada → «usa su canónica»" || rojo "fusionada: $R"
R="$(run_as "$V" "select crm.fusion_previsualizar_fn('$PA','$IX')")"; echo "$R" | grep -q "42501" && ok "vendedor previsualiza → 42501 (rol SQL authenticated + claims)" || rojo "vendedor previsualizó: $R"
R="$(prev "$PA" "$IX")"; H="$(j "$R" hash)"; [[ "$(j "$R" viable)" == "True" && -n "$H" ]] && ok "PA→IX viable con huella" || rojo "PA→IX: $R"
echo "$R" | grep -q "Vetos distintos" && echo "$R" | grep -q "hereda\|Responsables" && echo "$R" | grep -q "titularidades o cierres" && echo "$R" | grep -q "aplanan" && ok "advertencias: veto OR, responsable, inversiones/cierres, predecesoras" || rojo "advertencias: $R"
echo "$R" | grep -q "$DA" && rojo "la foto lleva el documento en claro" || ok "la foto no lleva el documento en claro"

echo "== Fusión: huella caducada; motivo con documento; intercalados; fusión OK y matriz =="
R="$(fus "$PA" "$IX" "motivo con $DA dentro" "$H")"; echo "$R" | grep -q "22023" && ok "motivo con el documento → 22023" || rojo "motivo: $R"
R="$(reas "$G" "$IX" "$SUP" "ensayo b5: cambio de responsable antes de fusionar")"; [[ "$(j "$R" estado)" == "reasignado" ]] && ok "reasignar IX → supervisor (tramo nuevo)" || rojo "reasignar: $R"
R="$(fus "$PA" "$IX" "fusión de prueba r$RUN" "$H")"; echo "$R" | grep -q "caducó" && ok "fusión con huella vieja (tramo cambió) → P0409 «caducó»" || rojo "huella vieja pasó: $R"
R="$(prev "$PA" "$IX")"; H="$(j "$R" hash)"
run_as "$V" "insert into crm.tareas (lead_id, vendedor_id, tipo, titulo, vence_en, creado_por) values ('$LX','$V','tarea','B5 tarea tardía r$RUN', now() + interval '2 day', '$V')" >/dev/null
R="$(fus "$PA" "$IX" "fusión r$RUN" "$H")"; echo "$R" | grep -q "caducó" && ok "[E3-4] una tarea agendada tras previsualizar cambia la huella → P0409 «caducó»" || rojo "E3-4: $R"
R="$(prev "$PA" "$IX")"; H="$(j "$R" hash)"; [[ "$(jj "$R" impacto.tareas_pendientes)" == "2" ]] && ok "la foto y el impacto cuentan las 2 tareas pendientes" || rojo "tareas en impacto: $(jj "$R" impacto.tareas_pendientes)"
# [E3-9] otra sesión retiene el lead LX (como derivar): la fusión no espera dentro del ciclo → 40001
psql "$PG" -qtA -c "begin; select id from crm.leads where id='$LX' for update; select pg_sleep(4); commit;" > "$S/b5_nowait_a.out" 2>&1 &
NW_PID=$!; sleep 1
R="$(fus "$PA" "$IX" "fusión r$RUN" "$H")"; echo "$R" | grep -q "40001" && ok "[E3-9] lead retenido por otra sesión → la fusión responde 40001 (NOWAIT), sin esperar en el ciclo tareas↔lead" || rojo "E3-9: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
wait $NW_PID
H_EP0="$(huella_episodios)"; H_SE0="$(huella_sellados)"
# intercalado 1: fusión (sin commit 3 s) ‖ convertir_lead(L5, perfil de PA) → espera y termina en 40001 (PA fusionada), L5 intacto
psql "$PG" -qtA -v ON_ERROR_STOP=1 -c "begin; set local role authenticated; select set_config('request.jwt.claims','{\"sub\":\"$G\",\"role\":\"authenticated\"}',true); select crm.fusionar_inversionistas_fn('$PA','$IX','fusión r$RUN (intercalada)','$H'); select pg_sleep(3); commit;" > "$S/b5_race_a.out" 2>&1 &
PA_PID=$!; sleep 1
R="$(run_as "$V" "select crm.convertir_lead('$L5','$PA_PERFIL')")"; echo "$R" > "$S/b5_race_b.out"
wait $PA_PID
grep -q '"ok" *: *true' "$S/b5_race_a.out" && ok "fusión PA→IX confirmada en la sesión A" || rojo "fusión A: $(head -c 300 "$S/b5_race_a.out")"
echo "$R" | grep -q "40001" && [[ "$(q "select etapa from crm.leads where id='$L5'")" == "nuevo" ]] && ok "convertir_lead con el perfil de la perdedora, en paralelo → esperó, 40001 (fusionada), L5 intacto, sin deadlock" || rojo "intercalado convertir: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
[[ "$(q "select estado||' '||inversionista_canonico_id from crm.inversionistas where id='$PA'")" == "fusionado $IX" ]] && ok "PA fusionada, nunca borrada" || rojo "PA: $(q "select estado from crm.inversionistas where id='$PA'")"
[[ "$(inv_de "$DA")" == "$IX" && "$(q "select private.inversionista_resolver('DNI','$DA',true,'ensayo')")" == "$IX" ]] && ok "resolver y por_documento del DNI de PA devuelven IX directamente (reemisión)" || rojo "resolver tras fusión: $(inv_de "$DA")"
[[ "$(q "select count(*) from crm.inversionista_identificadores where inversionista_id='$PA' and estado='vigente'")" == "0" && "$(q "select count(*) from crm.inversionista_identificadores where inversionista_id='$IX' and estado='vigente' and fuente='fusion'")" == "1" ]] && ok "identificadores: P históricos, reemitidos en C con fuente=fusion" || rojo "identificadores"
[[ "$(q "select perfil_id from crm.inversionistas where id='$IX'")" == "$PA_PERFIL" ]] && ok "C heredó el perfil de P" || rojo "perfil no heredado"
[[ "$(q "select no_contactar from crm.inversionistas where id='$IX'")" == "t" && "$(q "select no_contactar from crm.leads where id='$LX'")" == "t" ]] && ok "veto OR: C y su lead LX vetados" || rojo "veto OR"
[[ "$(q "select count(*) from crm.tareas where lead_id='$LX' and estado='pendiente'")" == "0" && "$(q "select count(*) from crm.tareas where lead_id='$LX' and estado='cancelada' and cancelada_por='sistema'")" == "2" ]] && ok "tareas pendientes del lead canceladas como sistema" || rojo "tareas: $(q "select estado||'/'||coalesce(cancelada_por,'-') from crm.tareas where lead_id='$LX'")"
[[ "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$IX' and hasta is null")" == "1" && "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$PA' and hasta is null")" == "0" ]] && ok "un solo tramo abierto (C); el de P cerrado" || rojo "tramos"
[[ "$(q "select inversionista_canonico_id from crm.inversionistas where id='$Z'")" == "$IX" ]] && ok "predecesora Z aplanada a IX" || rojo "Z no aplanada"
[[ "$(q "select private.inversionista_canonica('$Z')")" == "$IX" ]] && ok "inversionista_canonica(Z) = IX" || rojo "canonica(Z)"
[[ "$(q "select inversionista_id from crm.cierres_externos where id='$CE3'")" == "$IX" && "$(q "select inversionista_id from crm.inversiones where id='$INV3'")" == "$IX" ]] && ok "CE3 e INV3 reapuntados a C" || rojo "cierre/inversión no reapuntados"
[[ "$(q "select string_agg(inversionista_id::text||':'||rol, ',' order by rol) from crm.inversion_titulares where inversion_id='$INV3'")" == "$IX:principal" ]] && ok "INV3: la fila principal de P se eliminó (duplicado del par) y la cotitular de C pasó a principal" || rojo "titulares INV3: $(q "select string_agg(inversionista_id::text||':'||rol, ',') from crm.inversion_titulares where inversion_id='$INV3'")"
[[ "$(q "select string_agg(inversionista_id::text||':'||rol, ',' order by rol) from crm.inversion_titulares where inversion_id='$INV1'")" == "$IX:cotitular,$IB:principal" ]] && ok "INV1: la cotitular de P se reapuntó a C (IB sigue principal)" || rojo "titulares INV1: $(q "select string_agg(inversionista_id::text||':'||rol, ',') from crm.inversion_titulares where inversion_id='$INV1'")"
[[ "$(q "select count(*) from crm.inversionista_fusiones where canonico_id='$IX' and fusionado_id='$PA' and impacto ? 'hash'")" == "1" ]] && ok "libro de fusiones con impacto" || rojo "libro"
q "select impacto::text from crm.inversionista_fusiones where fusionado_id='$PA'" | grep -q "$DA" && rojo "impacto lleva el documento" || ok "impacto sin documento en claro"
[[ "$(q "select count(*) from crm.actividades where lead_id='$LX' and tipo='nota' and metadata->>'evento'='fusion'")" == "1" ]] && ok "actividad de fusión en el lead" || rojo "sin actividad"
q "select coalesce(string_agg(coalesce(data_antes::text,'')||coalesce(data_despues::text,''), ' '), '') from public.audit_log where tabla in ('inversionista_identificadores','inversionista_fusiones','inversionistas') and ts > now() - interval '2 minutes'" | grep -q "$DA" && rojo "audit_log de identidad lleva el documento en claro" || ok "audit_log de las tablas de identidad sin documento en claro"
R="$(fus "$PA" "$IX" "otra vez" "$H")"; echo "$R" | grep -q "P0409" && ok "fusionar de nuevo → P0409 (P ya fusionada / huella)" || rojo "refusión pasó"
# proyección canónica [E3-12]: reintento idempotente de una conversión hecha a P (L5 ← perfil de PA) tras la fusión
# (L5 quedó intacto: la conversión no se consumó; la proyección se ejercita sobre la conversión coop de L1 a IB fusionando IB→IX no es posible (dos leads)).
R="$(prev "$IC" "$IE")"; [[ "$(j "$R" viable)" == "False" ]] && ok "IC→IE: dos leads (bloqueo esperado)" || rojo "IC→IE viable?"
[[ "$(huella_episodios)" == "$H_EP0" ]] && ok "huella de conversion_episodios (mes abierto) idéntica tras la fusión" || rojo "conversion_episodios cambió"
[[ "$(huella_sellados)" == "$H_SE0" ]] && ok "periodos_cerrados y cierre_mes_vendedor intactos" || rojo "sellados cambiaron"

echo "== Corrección de documento =="
LE="$(uuid)"; lead_dni "$LE" "'$DF'" 61 >/dev/null; R="$(coop "$LE" "$DF" 6)"; IF="$(inv_de "$DF")"; [[ -n "$IF" && "$(q "select dni||' '||inversionista_id from crm.leads where id='$LE'")" == "$DF $IF" ]] && ok "IF: lead LE con DNI $DF convertido en coop (lead enlazado con DNI)" || rojo "IF: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
run_as "$G" "select crm.marcar_no_contactar('$LE','ensayo b5')" >/dev/null
R="$(corr "$IF" "DNI" "$DA" "cambio a un documento ajeno")"; echo "$R" | grep -q "otra persona" && ok "corregir a un documento de OTRA persona → P0409 «fusiona»" || rojo "ajeno: $R"
R="$(corr "$IF" "DNI" "$DE2" "motivo con $DF")"; echo "$R" | grep -q "22023" && ok "motivo con el documento → 22023" || rojo "motivo corr: $R"
R="$(corr "$IC" "DNI" "$DE2" "corrección con reserva viva")"; echo "$R" | grep -q "P0409\|ok" && ok "IC (sin claim) acepta o rechaza con diagnóstico" || rojo "IC corr: $R"
DF2="8${RUN}6"; R="$(corr "$IF" "DNI" "$DF2" "DNI mal tecleado en la cooperativa")"; [[ "$(j "$R" estado)" == "corregido" && "$(j "$R" lead)" == "dni" ]] && ok "DNI→DNI: corregido; lead realineado (lead VETADO incluido, excepción estrecha del trigger)" || rojo "corr DNI: $(echo "$R"|grep -E 'ERROR|MESSAGE|\{'|head -1|cut -c1-200)"
[[ "$(q "select dni from crm.leads where id='$LE'")" == "$DF2" && "$(inv_de "$DF2")" == "$IF" && "$(inv_de "$DF")" == "" ]] && ok "lead con el DNI nuevo; el viejo ya no resuelve; el nuevo resuelve a IF" || rojo "estado tras corrección"
[[ "$(q "select count(*) from crm.inversionista_operaciones where inversionista_id='$IF' and tipo='correccion' and detalle->>'lead'='dni'")" == "1" ]] && ok "libro de operaciones (corrección)" || rojo "sin fila de corrección"
R="$(run_as "$V" "select crm.convertir_lead('$LE','$PB_PERFIL')")"; echo "$R" | grep -q "ya esta cerrado\|corrección o fusión" && ok "convertir el lead de IF a un perfil de OTRA persona → rechazado" || rojo "E3-11: $R"
IDF="$(q "select id from crm.inversionista_identificadores where inversionista_id='$IF' and tipo_documento='DNI' and estado='vigente'")"
R="$(corr "$IF" "CE" "00${RUN}55" "es extranjero: carné de extranjería" "$IDF")"; [[ "$(j "$R" estado)" == "corregido" && "$(j "$R" lead)" == "nulo" && "$(q "select dni is null from crm.leads where id='$LE'")" == "t" ]] && ok "DNI→CE: lead.dni queda nulo (crm.leads solo representa DNI)" || rojo "corr CE: $(echo "$R"|grep -E 'ERROR|MESSAGE|\{'|head -1|cut -c1-200)"
R="$(corr "$IF" "CE" "00${RUN}55" "repetir")"; [[ "$(j "$R" estado)" == "sin_cambios" ]] && ok "misma corrección repetida → sin_cambios" || rojo "repetida: $R"
# [E3-15] IX tiene DOS DNI vigentes (DX propio y DA reemitido): corregir DX→DA indicando cuál sale reutiliza DA y realinea LX
IDX="$(q "select id from crm.inversionista_identificadores where inversionista_id='$IX' and documento_normalizado='$DX' and estado='vigente'")"
R="$(corr "$IX" "DNI" "$DA" "el DNI correcto es el del Portal" "$IDX")"; [[ "$(j "$R" estado)" == "corregido" && "$(j "$R" reutilizado)" == "True" && "$(j "$R" lead)" == "dni" && "$(q "select dni from crm.leads where id='$LX'")" == "$DA" && "$(q "select count(*) from crm.inversionista_identificadores where inversionista_id='$IX' and estado='vigente'")" == "1" ]] && ok "[E3-15] destino ya vigente propio: sale el anterior, se reutiliza el destino, el lead se realinea; queda UN vigente" || rojo "E3-15: $(echo "$R"|grep -E 'ERROR|MESSAGE|\{'|head -1|cut -c1-220)"
# perfil realineado: IX (canónica) tiene el perfil de PA (dni DA) y el identificador DA reemitido
IDA="$(q "select id from crm.inversionista_identificadores where inversionista_id='$IX' and documento_normalizado='$DA' and estado='vigente'")"
R="$(corr "$IX" "DNI" "$DA2" "DNI del Portal mal tecleado" "$IDA")"; [[ "$(j "$R" estado)" == "corregido" && "$(j "$R" perfil)" == "actualizado" && "$(q "select dni from public.perfiles where id='$PA_PERFIL'")" == "$DA2" ]] && ok "perfil del Portal realineado (dni=$DA2)" || rojo "perfil: $(echo "$R"|grep -E 'ERROR|MESSAGE|\{'|head -1|cut -c1-200)"
PG2="$(uuid)"; sim_auth "$PG2" "g$RUN@x.pe" "sin-claim"; flag false; sim_perfil "$PG2" "$DG" "g$RUN@x.pe"; flag true
R="$(corr "$IB" "DNI" "$DG" "cambio al DNI de otro cliente del Portal")"; echo "$R" | grep -qi "otro cliente del Portal" && ok "documento de OTRO cliente del Portal (sin identidad) → P0409" || rojo "portal: $R"
LF="$(uuid)"; lead_dni "$LF" "'$DH'" 62 >/dev/null
R="$(corr "$IB" "DNI" "$DH" "cambio al DNI de otro lead vivo")"; echo "$R" | grep -q "Otro lead vivo" && ok "DNI de OTRO lead vivo → P0409" || rojo "lead vivo: $R"
R="$(corr "$IB" "DNI" "8${RUN}7" "sin indicar cuál")"; echo "$R" | grep -q "corregido\|indica cuál" && ok "IB con un solo DNI vigente: corrige sin p_identificador_anterior (o pide cuál si hay dos)" || rojo "auto: $R"

echo "== Enlace de lead suelto (clase E) =="
read -r PH PH_PERFIL <<<"$(alta_completa "$DH" "h$RUN@x.pe" "B5 H")"; [[ -n "$PH" ]] && ok "PH creada por alta con el DNI $DH (el lead LF con ese DNI ya existía suelto)" || rojo "PH"
R="$(enl "$LF" "$IE" "enlace a otra persona")"; echo "$R" | grep -q "otra persona" && ok "enlazar LF a IE (DNI de otra persona reconocida) → P0409" || rojo "ajeno enl: $R"
R="$(enl "$L4" "$PH" "lead sin DNI")"; echo "$R" | grep -q "no tiene DNI" && ok "lead sin DNI → P0409 (regla #8)" || rojo "sin dni: $R"
R="$(enl "$LF" "$IB" "persona con lead")"; echo "$R" | grep -q "otra persona\|ya tiene su lead" && ok "enlazar a una persona con lead o DNI ajeno → P0409" || rojo "con lead: $R"
R="$(run_as "$V" "select crm.reservar_conversion_lead('$LF')")"; [[ "$(j "$R" ok)" == "True" ]] || rojo "reserva 1-arg: $R"
R="$(enl "$LF" "$PH" "con reserva viva sin persona")"; echo "$R" | grep -q "reserva de conversión viva" && ok "[E3-7] reserva viva de 1 argumento (sin identidad) sobre el lead → enlace P0409" || rojo "E3-7 enl: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
psql "$PG" -q -c "update crm.conversion_reservas set expira_en = now() - interval '1 minute', vence_absoluto_en = now() - interval '1 minute' where lead_id='$LF'" >/dev/null
R="$(enl "$LF" "$PH" "revisión clase E r$RUN")"; [[ "$(j "$R" ok)" == "True" && "$(q "select inversionista_id from crm.leads where id='$LF'")" == "$PH" && "$(q "select count(*) from crm.inversionista_leads where lead_id='$LF' and inversionista_id='$PH' and rol='canonico'")" == "1" ]] && ok "enlace OK: lead + puente canónico" || rojo "enlace: $(echo "$R"|grep -E 'ERROR|MESSAGE|\{'|head -1|cut -c1-200)"
R="$(enl "$LF" "$PH" "otra vez")"; echo "$R" | grep -q "ya está enlazado" && ok "enlazar de nuevo → P0409" || rojo "re-enlace: $R"
[[ "$(q "select count(*) from crm.inversionista_operaciones where tipo='enlace' and lead_id='$LF' and inversionista_id='$PH'")" == "1" ]] && ok "[E3-16] libro de operaciones: fila de enlace con motivo" || rojo "sin fila de enlace"
# [E3-10] lead suelto con DNI A cuyo cierre coop (hecho con la bandera APAGADA) lleva documento B → enlazar por A → P0409
DI="5${RUN}0"; DJ="6${RUN}1"; LI="$(uuid)"; lead_dni "$LI" "'$DI'" 64 >/dev/null; flag false; R="$(coop "$LI" "$DJ" 9)"; flag true
[[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LI'")" == "convertido -" ]] && ok "fixture E3-10: lead LI (DNI $DI) convertido en coop con documento $DJ, sin identidad" || rojo "fixture E3-10: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
II="$(q "select private.inversionista_resolver('DNI','$DI',true,'ensayo-b5')")"
R="$(enl "$LI" "$II" "enlace con cierre de otro documento")"; echo "$R" | grep -q "documento del cierre" && ok "[E3-10] el cierre lleva otro documento → enlace P0409 (reconciliación documental primero)" || rojo "E3-10: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
# [E3-16] lead INACTIVO con DNI de una persona reconocida → enlace sin actividad, con fila en el libro
DK="6${RUN}2"; LK="$(uuid)"; lead_dni "$LK" "'$DK'" 65 >/dev/null; IK="$(q "select private.inversionista_resolver('DNI','$DK',true,'ensayo-b5')")"
psql "$PG" -q -c "update crm.leads set activo=false where id='$LK'" >/dev/null
R="$(enl "$LK" "$IK" "lead inactivo de la clase E")"; [[ "$(j "$R" ok)" == "True" && "$(q "select count(*) from crm.inversionista_operaciones where tipo='enlace' and lead_id='$LK'")" == "1" && "$(q "select count(*) from crm.actividades where lead_id='$LK' and metadata->>'evento'='enlace_identidad'")" == "0" ]] && ok "[E3-16] lead inactivo: enlazado, sin nota de actividad, con motivo en el libro" || rojo "E3-16: $(echo "$R"|grep -E 'ERROR|MESSAGE|\{'|head -1|cut -c1-200)"

echo "== Reasignación =="
R="$(reas "$V" "$IB" "$SUP" "vendedor intenta")"; echo "$R" | grep -q "42501" && ok "vendedor reasigna → 42501" || rojo "vendedor reasignó: $R"
R="$(reas "$G" "$IB" "$(uuid)" "a nadie")"; echo "$R" | grep -q "22023" && ok "responsable inexistente → 22023" || rojo "inexistente: $R"
R="$(reas "$G" "$IB" "$SUP" "primer cambio r$RUN")"; R="$(reas "$G" "$IB" "$SUP" "mismo")"; [[ "$(j "$R" estado)" == "sin_cambios" ]] && ok "mismo responsable → sin_cambios" || rojo "mismo: $R"
R="$(reas "$G" "$IB" "$V" "vuelve al vendedor r$RUN")"; [[ "$(j "$R" estado)" == "reasignado" && "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$IB' and hasta is null")" == "1" && "$(q "select responsable_relacion_id from crm.inversionistas where id='$IB'")" == "$V" && "$(q "select vendedor_id from crm.leads where id='$L1'")" == "$V" ]] && ok "reasignado: un tramo abierto, responsable_relacion_id nuevo, leads.vendedor_id intacto" || rojo "reasignación: $R"
[[ "$(q "select bool_and(hasta >= desde) from crm.inversionista_responsables where inversionista_id='$IB' and hasta is not null")" == "t" ]] && ok "tramos cerrados con hasta >= desde (clock_timestamp)" || rojo "tramo inválido"

echo "== Paridad con bandera APAGADA =="
flag false
for f in "crm.fusion_previsualizar_fn('$PA','$IX')" "crm.fusionar_inversionistas_fn('$PA','$IX','x','y')" "crm.corregir_documento_inversionista_fn('$IB','DNI','$DA','x')" "crm.enlazar_lead_inversionista_fn('$L4','$IB','x')" "crm.reasignar_responsable_relacion_fn('$IB','$V','x')"; do
  R="$(run_as "$G" "select $f")"; echo "$R" | grep -qi "apagada" && ok "OFF: ${f%%(*} → P0409 apagada" || rojo "OFF: $f: $(echo "$R"|head -1|cut -c1-120)"
done
R="$(run_as "$G" "update crm.leads set dni='$DE2' where id='$LE'")"; echo "$R" | grep -q "P0481" && ok "OFF: Gerencia cambia el DNI de un lead vetado sin válvula → P0481 como hoy (la excepción del trigger no aplica)" || rojo "OFF trigger: $R"
R="$(run_as "$G" "select set_config('crm.op_privilegiada','on',true); update crm.leads set dni='$DE2' where id='$LE'")"; echo "$R" | grep -q "P0481" && ok "OFF + válvula encendida: la excepción del trigger exige la bandera → P0481 como hoy" || rojo "OFF+válvula: $R"
LZ="$(uuid)"; lead_dni "$LZ" "null" 63 >/dev/null; R="$(coop "$LZ" "6${RUN}5" Z)"; [[ "$(q "select etapa from crm.leads where id='$LZ'")" == "convertido" && "$(q "select count(*) from crm.inversionista_identificadores where documento_normalizado='6${RUN}5'")" == "0" ]] && ok "OFF: conversión coop como hoy (sin identidad)" || rojo "OFF coop: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-120)"
R="$(run_as "$V" "select crm.convertir_lead('$L5','$PB_PERFIL')")"; [[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$L5'")" == "convertido -" ]] && ok "OFF: conversión Avance como hoy (sin identidad)" || rojo "OFF avance: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-120)"
flag true; flag_inv false

psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false; flag_inv false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b b5: VERDE — fusión (matriz completa, huella, intercalado sin deadlock), corrección (perfil/lead, terceros, veto), enlace de clase E, reasignación; paridad apagada."; exit 0
else echo "ORÁCULO F2.b b5: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
