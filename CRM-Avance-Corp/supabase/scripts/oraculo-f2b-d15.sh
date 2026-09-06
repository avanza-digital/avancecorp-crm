#!/usr/bin/env bash
# ORÁCULO F2.b [D-15] — el botón «Reabrir» pasa por la puerta crm.reabrir_lead_fn — SOLO en el BANCO.
# Presupone b1..b5, D-10, D-13 y la siembra siembra-banco-f3.sql (actores V/S/G, leads L1..L5 sin DNI).
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d15.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
# Sin D-15 instalada = corrida MUTANTE: todo lo que llama a la puerta sale ROJO (y el UPDATE directo con ON sigue cerrado por D-13).
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
AJENO='f3aaaaaa-0000-0000-0000-000000000099'
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
ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }
reabrir() { run_as "${2:-$V}" "select crm.reabrir_lead_fn('$1')"; }
directo() { run_as "${2:-$V}" "update crm.leads set etapa='nuevo', motivo_descarte=null where id='$1'"; }
# lead vivo con dueño (por defecto V), con o sin DNI, nacido con la bandera como esté (el que llama decide)
lead_de() { sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D15 $3 r$RUN','9${RUN}$2',${4:-null},1000,'landing','nuevo','${5:-$V}','${5:-$V}')"; }
descartar() { run_as "${2:-$V}" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$1'" >/dev/null; }
foto() { q "select etapa||'|'||coalesce(motivo_descarte,'-')||'|'||coalesce(descartado_en::text,'-')||'|'||coalesce(descartado_por::text,'-')||'|'||coalesce(inversionista_id::text,'-')||'|'||(select count(*)||':'||coalesce((select a2.detalle from crm.actividades a2 where a2.lead_id=l.id and a2.tipo='cambio_etapa' order by a2.creado_en desc, a2.id desc limit 1),'-')||':'||coalesce(string_agg(distinct a.creado_por::text, ','),'-')||':'||coalesce(string_agg(distinct (a.metadata->>'automatico'), ','),'-') from crm.actividades a where a.lead_id=l.id and a.tipo='cambio_etapa') from crm.leads l where l.id='$1'"; }
resolver() { q "select private.inversionista_resolver('DNI','$1',true,'ensayo-d15')"; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$1') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','D15 CLIENTE $2 r$RUN','cliente','DNI','$2','$3','$V',true); commit;" 2>&1 | grep -E "ERROR"; }
pay()  { echo "{\"correo\":\"$1\",\"nombre_completo\":\"D15 $2\",\"telefono\":\"9${RUN}0$3\",\"domicilio\":\"Av. Prueba 123, Lima\"}"; }
reservar() { run_as "$1" "select crm.reservar_conversion_lead('$2','DNI','$3','$4'::jsonb)"; }
retener_as() { LOCKF="$S/d15-lock-$RUN-$RANDOM.out"; ( psql "$PG" -qAt -v ON_ERROR_STOP=1 > "$LOCKF" 2>&1 <<EOF
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true);
$2;
\echo LOCK-OK
select pg_sleep($3);
commit;
EOF
echo "exit=$?" >> "$LOCKF" ) & BG=$!; local i; for i in $(seq 1 100); do grep -q "LOCK-OK" "$LOCKF" 2>/dev/null && return 0; grep -q "ERROR" "$LOCKF" 2>/dev/null && { rojo "retener_as: $(head -c 200 "$LOCKF")"; return 1; }; sleep 0.1; done; rojo "retener_as: sin LOCK-OK en 10 s"; return 1; }
retener() { LOCKF="$S/d15-lock-$RUN-$RANDOM.out"; ( psql "$PG" -qAt -v ON_ERROR_STOP=1 > "$LOCKF" 2>&1 <<EOF
begin;
$1;
\echo LOCK-OK
select pg_sleep($2);
commit;
EOF
echo "exit=$?" >> "$LOCKF" ) & BG=$!; local i; for i in $(seq 1 100); do grep -q "LOCK-OK" "$LOCKF" 2>/dev/null && return 0; grep -q "ERROR" "$LOCKF" 2>/dev/null && { rojo "retener: $(head -c 200 "$LOCKF")"; return 1; }; sleep 0.1; done; rojo "retener: sin LOCK-OK en 10 s"; return 1; }
soltado() { wait $BG 2>/dev/null; grep -q "exit=0" "$LOCKF" && return 0; rojo "la sesión secundaria que retenía el candado falló: $(grep -v LOCK-OK "$LOCKF" | head -c 200)"; return 1; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
if [[ "$(q "select to_regprocedure('crm.reabrir_lead_fn(uuid)') is not null and to_regprocedure('crm.editar_lead_fn(uuid,jsonb)') is not null")" == "t" ]]; then echo "  D-15 instalada (todo debe salir VERDE)"; else echo "  ⚠️ D-15 NO instalada: corrida MUTANTE (todo lo de las puertas sale ROJO)"; fi
[[ "$(q "select to_regprocedure('private.juicio_reapertura(uuid,text,text)') is not null")" == "t" ]] && ok "premisa: D-13 instalada" || rojo "falta D-13"
flag false

echo "== (1) Bandera APAGADA: la puerta es el UPDATE de hoy =="
LA="$(uuid)"; lead_de "$LA" 11 A; descartar "$LA"
LB="$(uuid)"; lead_de "$LB" 12 B; descartar "$LB"
[[ "$(q "select etapa||' '||coalesce(descartado_por::text,'-') from crm.leads where id='$LA'")" == "descartado $V" ]] && ok "fixture: LA y LB descartados por V (sello estampado)" || rojo "fixture LA: $(q "select etapa, descartado_por from crm.leads where id='$LA'")"
R="$(reabrir "$LA")"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" etapa)" == "nuevo" && "$(j "$R" enlazado)" == "False" && "$(j "$R" reabierto_por)" == "$V" ]] && ok "[O1] reabrir_lead_fn(LA) por V → ok, etapa nuevo, sin enlace, reabierto_por = V" || rojo "O1: $(echo "$R" | head -c 220)"
R="$(directo "$LB")"; FA="$(foto "$LA")"; FB="$(foto "$LB")"
[[ -n "$FA" && "$FA" == "$FB" ]] && ok "[O2] PARIDAD: la foto de LA (puerta) es idéntica a la de LB (UPDATE directo): $FA" || rojo "O2 paridad: puerta=$FA · directo=$FB · $(echo "$R" | head -c 120)"
[[ "$FA" == nuevo\|-\|-\|-\|-\|2:* ]] && echo "$FA" | grep -q "descartado → nuevo" && echo "$FA" | grep -q "$V" && ok "[O2] etapa nuevo, motivo/sello limpios, 2 actividades cambio_etapa (la última «descartado → nuevo», atribuida a V, no automática)" || rojo "O2 foto: $FA"
R="$(reabrir "$LA")"; echo "$R" | grep -q "P0409" && echo "$R" | grep -q "Solo se puede reabrir un lead descartado" && ok "[O3] reabrir un lead ya abierto → P0409 «solo se puede reabrir un lead descartado»" || rojo "O3: $(echo "$R" | head -c 200)"
LC="$(uuid)"; lead_de "$LC" 13 C null "$SUP"; descartar "$LC" "$SUP"
R="$(reabrir "$LC" "$V")"; echo "$R" | grep -q "P0002" && [[ "$(q "select etapa from crm.leads where id='$LC'")" == "descartado" ]] && ok "[O4] V no reabre un lead del supervisor (fuera de su ámbito) → P0002, sigue descartado" || rojo "O4 ajeno: $(echo "$R" | head -c 200)"
R="$(reabrir "$LC" "$SUP")"; [[ "$(j "$R" etapa)" == "nuevo" ]] && ok "[O4] el supervisor reabre el suyo → nuevo" || rojo "O4 sup: $(echo "$R" | head -c 200)"
LD="$(uuid)"; lead_de "$LD" 14 D; descartar "$LD"
R="$(reabrir "$LD" "$SUP")"; [[ "$(j "$R" etapa)" == "nuevo" && "$(j "$R" reabierto_por)" == "$SUP" ]] && ok "[O4] el supervisor reabre un lead de su analista (ámbito jerárquico) → nuevo" || rojo "O4 jerarquía: $(echo "$R" | head -c 200)"
LE="$(uuid)"; lead_de "$LE" 15 E; descartar "$LE"
R="$(reabrir "$LE" "$G")"; [[ "$(j "$R" etapa)" == "nuevo" ]] && ok "[O4] Gerencia reabre cualquiera → nuevo" || rojo "O4 gerencia: $(echo "$R" | head -c 200)"
R="$(reabrir "$LE" "$AJENO")"; echo "$R" | grep -q "42501" && ok "[O5] una sesión sin rol CRM → 42501" || rojo "O5: $(echo "$R" | head -c 200)"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role anon; select crm.reabrir_lead_fn('$LE'); rollback;" 2>&1)"; echo "$R" | grep -q "42501" && ok "[O5] anon sin EXECUTE → 42501" || rojo "O5 anon: $(echo "$R" | head -c 200)"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role service_role; select crm.reabrir_lead_fn('$LE'); rollback;" 2>&1)"; echo "$R" | grep -q "42501" && ok "[O5] service_role sin EXECUTE → 42501 (la puerta es del front, con sesión)" || rojo "O5 service_role: $(echo "$R" | head -c 200)"
R="$(reabrir "$(uuid)")"; echo "$R" | grep -q "P0002" && ok "[O6] lead inexistente → P0002 (mismo texto que un lead ajeno: no revela existencia)" || rojo "O6: $(echo "$R" | head -c 200)"
R="$(run_as "$V" "select crm.reabrir_lead_fn(null)")"; echo "$R" | grep -q "22023" && ok "[O6] lead nulo → 22023" || rojo "O6 null: $(echo "$R" | head -c 200)"
LF="$(uuid)"; lead_de "$LF" 16 F; descartar "$LF"; LF2="$(uuid)"; lead_de "$LF2" 16 F2
R="$(reabrir "$LF")"; echo "$R" | grep -q "uq_leads_telefono_vivo" && [[ "$(q "select etapa from crm.leads where id='$LF'")" == "descartado" ]] && ok "[O7] otro lead VIVO con el mismo teléfono → 23505 uq_leads_telefono_vivo (el front lo traduce como hoy), sigue descartado" || rojo "O7: $(echo "$R" | head -c 200)"
R="$(directo "$LF")"; echo "$R" | grep -q "uq_leads_telefono_vivo" && ok "[O7] paridad: el UPDATE directo da el mismo 23505" || rojo "O7 directo: $(echo "$R" | head -c 200)"
LG="$(uuid)"; lead_de "$LG" 17 G; sys "update crm.leads set no_contactar=true where id='$LG'"; descartar "$LG"; LG2="$(uuid)"; lead_de "$LG2" 19 G2; sys "update crm.leads set no_contactar=true where id='$LG2'"; descartar "$LG2"
R="$(reabrir "$LG")"; R2="$(directo "$LG2")"; FG="$(foto "$LG")"; FG2="$(foto "$LG2")"; [[ "$(j "$R" etapa)" == "nuevo" && "$FG" == "$FG2" ]] && ok "[O8] OFF: un lead con «No insistir» propio reabre igual por la puerta que por UPDATE directo (persona_vetada es inerte apagada; con ON lo cierra T4b)" || rojo "O8: $(echo "$R" | head -c 160) · puerta=$FG · directo=$FG2"
LH="$(uuid)"; lead_de "$LH" 18 H; descartar "$LH"
retener "select 1 from crm.leads where id='$LH' for update" 8 && { T0="$(ms)"; R="$(reabrir "$LH")"; T1="$(ms)"; echo "$R" | grep -q "55P03" && (( T1 - T0 >= 4500 )) && ok "[O9] fila retenida por otra sesión → 55P03 tras el lock_timeout de 5 s ($((T1-T0)) ms)" || rojo "O9: $(echo "$R" | head -c 160) · $((T1-T0)) ms"; soltado; }
R="$(reabrir "$LH")"; [[ "$(j "$R" etapa)" == "nuevo" ]] && ok "[O9] soltada la fila, reabre" || rojo "O9 después: $(echo "$R" | head -c 160)"

echo "== (1b) El cambio de bandera se serializa con la puerta (Codex v3 #4) =="
LS="$(uuid)"; lead_de "$LS" 41 SERIAL; descartar "$LS"
retener_as "$V" "select crm.reabrir_lead_fn('$LS')" 6 && { T0="$(ms)"; flag true; T1="$(ms)"; (( T1 - T0 >= 4500 )) && ok "[S1] con una reapertura en vuelo (entró apagada), ENCENDER espera a que termine ($((T1-T0)) ms)" || rojo "S1: el encendido no esperó ($((T1-T0)) ms)"; soltado; }
[[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LS'")" == "nuevo -" ]] && ok "[S1] la reapertura que entró apagada terminó apagada (nuevo, sin enlace), con la bandera encendida después" || rojo "S1 foto: $(q "select etapa, inversionista_id from crm.leads where id='$LS'")"
DS2="5${RUN}9"; IS2="$(resolver "$DS2")"; flag false; LS2="$(uuid)"; lead_de "$LS2" 42 SERIAL2 "'$DS2'"; descartar "$LS2"; flag true
retener_as "$V" "select crm.reabrir_lead_fn('$LS2')" 6 && { T0="$(ms)"; flag false; T1="$(ms)"; (( T1 - T0 >= 4500 )) && ok "[S2] con una reapertura en vuelo (entró encendida), APAGAR espera a que termine ($((T1-T0)) ms)" || rojo "S2: el apagado no esperó ($((T1-T0)) ms)"; soltado; }
[[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LS2'")" == "nuevo $IS2" ]] && ok "[S2] la reapertura que entró encendida terminó ENLAZADA a su persona (nuevo) y la bandera quedó apagada después" || rojo "S2 foto: $(q "select etapa, inversionista_id from crm.leads where id='$LS2'")"
flag false
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin isolation level repeatable read; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$V\",\"role\":\"authenticated\"}', true); select crm.reabrir_lead_fn('$LS2'); rollback;" 2>&1)"; echo "$R" | grep -q "0A000" && ok "[Codex v4 #2] REPEATABLE READ → 0A000 también APAGADA" || rojo "RR apagada: $(echo "$R" | head -c 200)"

echo "== (3) crm.editar_lead_fn: la edición de la ficha en UNA transacción (Codex bloque 4 #1) =="
editar() { run_as "${3:-$V}" "select crm.editar_lead_fn('$1', '$2'::jsonb)"; }
foto_e() { q "select nombre_completo||'|'||coalesce(correo,'-')||'|'||coalesce(nota,'-')||'|'||(dni is not null)||'|'||coalesce(distrito,'-')||'|'||monto_estimado||'|'||coalesce(inversionista_id::text,'-') from crm.leads where id='$1'"; }
flag false
LE1="$(uuid)"; lead_de "$LE1" 51 E1; LE2="$(uuid)"; lead_de "$LE2" 52 E2
# (DNIs distintos: el índice de DNI vivo no admite dos leads vivos con el mismo documento; la foto compara «tiene DNI», no el valor)
R="$(editar "$LE1" "{\"nombre_completo\":\"D15 EDITADO r$RUN\",\"correo\":\"e1$RUN@x.pe\",\"nota\":\"nota e1\",\"dni\":\"5${RUN}6\",\"distrito\":\"Lima\",\"monto_estimado\":7000}")"; R2="$(run_as "$V" "update crm.leads set nombre_completo='D15 EDITADO r$RUN', correo='e1$RUN@x.pe', nota='nota e1', dni='4${RUN}5', distrito='Lima', monto_estimado=7000 where id='$LE2'")"
[[ "$(j "$R" ok)" == "True" && "$(j "$R" dni_por_puerta)" == "False" && "$(foto_e "$LE1")" == "$(foto_e "$LE2")" && "$(q "select dni from crm.leads where id='$LE1'")" == "5${RUN}6" ]] && ok "[E1] OFF: editar_lead_fn deja la MISMA foto que el UPDATE directo del front (paridad; dni_por_puerta=false)" || rojo "E1: $(echo "$R" | head -c 160) · $(foto_e "$LE1") vs $(foto_e "$LE2") · $(echo "$R2" | head -c 120)"
[[ "$(q "select count(*) from public.audit_log where tabla like '%leads' and operacion='UPDATE' and fila_id='$LE1'")" == "$(q "select count(*) from public.audit_log where tabla like '%leads' and operacion='UPDATE' and fila_id='$LE2'")" ]] && ok "[E1] OFF: mismas filas de bitácora que el UPDATE directo (una escritura)" || rojo "E1 audit: $(q "select count(*) from public.audit_log where tabla like '%leads' and operacion='UPDATE' and fila_id='$LE1'") vs $(q "select count(*) from public.audit_log where tabla like '%leads' and operacion='UPDATE' and fila_id='$LE2'")"
R="$(editar "$LE1" "{\"nota\":\"x\",\"etapa\":\"convertido\"}")"; echo "$R" | grep -q "22023" && echo "$R" | grep -q "no editable" && ok "[E2] una clave fuera de la lista blanca (etapa) → 22023, nada escrito" || rojo "E2: $(echo "$R" | head -c 200)"
R="$(editar "$LE1" "{\"nota\":\"ajena\"}" "$AJENO")"; echo "$R" | grep -q "P0002" && [[ "$(q "select nota from crm.leads where id='$LE1'")" == "nota e1" ]] && ok "[E3] una sesión sin rol CRM no ve ningún lead (RLS) → P0002, nada escrito" || rojo "E3: $(echo "$R" | head -c 200)"
LE3="$(uuid)"; lead_de "$LE3" 53 E3 null "$SUP"; R="$(editar "$LE3" "{\"nota\":\"ajena\"}" "$V")"; echo "$R" | grep -q "P0002" && [[ "$(q "select coalesce(nota,'-') from crm.leads where id='$LE3'")" == "-" ]] && ok "[E4] lead fuera del ámbito (RLS del que edita) → P0002, nada escrito" || rojo "E4: $(echo "$R" | head -c 200)"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role anon; select crm.editar_lead_fn('$LE1','{}'::jsonb); rollback;" 2>&1)"; echo "$R" | grep -q "42501" && ok "[E5] anon sin EXECUTE → 42501" || rojo "E5: $(echo "$R" | head -c 200)"
flag true
DE="5${RUN}7"; IE="$(resolver "$DE")"; LE4="$(uuid)"; lead_de "$LE4" 54 E4
R="$(editar "$LE4" "{\"dni\":\"$DE\",\"nota\":\"con documento\"}")"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" dni_por_puerta)" == "True" && "$(q "select dni||' '||coalesce(inversionista_id::text,'-')||' '||coalesce(nota,'-') from crm.leads where id='$LE4'")" == "$DE $IE con documento" ]] && ok "[E6] ON: DNI de persona reconocida + nota → el DNI por su puerta (ENLAZADO) y la nota en la misma transacción" || rojo "E6: $(echo "$R" | head -c 200) · $(q "select dni, inversionista_id, nota from crm.leads where id='$LE4'")"
LE5="$(uuid)"; lead_de "$LE5" 55 E5; DE5="5${RUN}8"; LE6="$(uuid)"; lead_de "$LE6" 56 E6
R="$(editar "$LE5" "{\"dni\":\"$DE5\",\"telefono\":\"9${RUN}56\"}")"; echo "$R" | grep -qE "P0481|uq_leads_telefono_vivo" && [[ "$(q "select dni is null from crm.leads where id='$LE5'")" == "t" ]] && ok "[E7 Codex v4 #1] ON: el DNI pasa por su puerta pero el resto choca (teléfono de otro lead vivo: veredicto de disponibilidad o índice) → TODO se deshace: el DNI tampoco queda" || rojo "E7: $(echo "$R" | head -c 200) · dni=$(q "select dni from crm.leads where id='$LE5'")"
R="$(editar "$LE5" "{\"dni\":\"$DE\"}")"; echo "$R" | grep -q "ya es cliente o ya tiene su lead" && ok "[E8] ON: el DNI de una persona que ya tiene su lead → P0409 de la puerta (el texto del servidor)" || rojo "E8: $(echo "$R" | head -c 200)"
R="$(editar "$LE5" "{\"dni\":\"$DE5\"}")"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" dni_por_puerta)" == "True" && "$(q "select dni from crm.leads where id='$LE5'")" == "$DE5" ]] && ok "[E9] ON: solo cambia el DNI → la puerta y ningún UPDATE aparte" || rojo "E9: $(echo "$R" | head -c 200)"
R="$(editar "$LE5" "{\"dni\":\"$DE5\",\"nota\":\"mismo dni\"}")"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" dni_por_puerta)" == "False" && "$(q "select nota from crm.leads where id='$LE5'")" == "mismo dni" ]] && ok "[E10] ON: el DNI viaja sin cambiar → el UPDATE de hoy lo lleva y el trigger lo deja pasar (dni_por_puerta=false)" || rojo "E10: $(echo "$R" | head -c 200)"
R="$(editar "$LE5" "{\"dni\":null,\"nota\":\"sin dni\"}")"; [[ "$(j "$R" ok)" == "True" && "$(q "select dni is null and nota='sin dni' from crm.leads where id='$LE5'")" == "t" ]] && ok "[E11] ON: borrar el DNI (null) va por la puerta y el resto en la misma transacción" || rojo "E11: $(echo "$R" | head -c 200)"
flag false

echo "== (2) Bandera ENCENDIDA: reabrir juzga a la persona y enlaza =="
flag true
LI="$(uuid)"; lead_de "$LI" 21 I; descartar "$LI"
R="$(directo "$LI")"; echo "$R" | grep -q "solo por sus puertas" && [[ "$(q "select etapa from crm.leads where id='$LI'")" == "descartado" ]] && ok "[T0 D-13] el UPDATE directo del front (descartado→nuevo) con ON → P0409 «solo por sus puertas»: por eso existe D-15" || rojo "T0: $(echo "$R" | head -c 200)"
R="$(reabrir "$LI")"; [[ "$(j "$R" etapa)" == "nuevo" && "$(j "$R" enlazado)" == "False" ]] && ok "[T1] la puerta reabre un descartado sin DNI de persona desconocida → nuevo, sin enlace" || rojo "T1: $(echo "$R" | head -c 200)"
DJ="5${RUN}1"; flag false; LJ="$(uuid)"; lead_de "$LJ" 22 J "'$DJ'"; flag true; descartar "$LJ"; IJ="$(resolver "$DJ")"
[[ -n "$IJ" && "$(q "select inversionista_id is null from crm.leads where id='$LJ'")" == "t" ]] && ok "fixture: LJ descartado con DNI $DJ nacido apagado (sin enlace); la persona IJ existe y no tiene otro lead" || rojo "fixture LJ/IJ"
R="$(reabrir "$LJ")"; [[ "$(j "$R" etapa)" == "nuevo" && "$(j "$R" enlazado)" == "True" && "$(j "$R" inversionista_id)" == "$IJ" && "$(q "select inversionista_id from crm.leads where id='$LJ'")" == "$IJ" && "$(q "select count(*) from crm.inversionista_leads where lead_id='$LJ' and inversionista_id='$IJ' and rol='canonico'")" == "1" ]] && ok "[T2] reabrir un descartado cuyo DNI es de una persona reconocida sin otro lead → nuevo y ENLAZADO (puente canónico)" || rojo "T2: $(echo "$R" | head -c 220) · $(q "select inversionista_id from crm.leads where id='$LJ'")"
DK="5${RUN}2"; IK="$(resolver "$DK")"; flag false; LK="$(uuid)"; lead_de "$LK" 23 K "'$DK'"; descartar "$LK"; LK2="$(uuid)"; lead_de "$LK2" 24 K2 "'$DK'"; flag true
R="$(reabrir "$LK")"; echo "$R" | grep -q "ya es cliente o ya tiene su lead" && [[ "$(q "select etapa from crm.leads where id='$LK'")" == "descartado" ]] && ok "[T3] la persona ya tiene OTRO lead vivo (suelto por documento) → P0409, sigue descartado" || rojo "T3: $(echo "$R" | head -c 220)"
sys "update crm.leads set activo=false where id='$LK2'"
R="$(reabrir "$LK")"; [[ "$(j "$R" etapa)" == "nuevo" && "$(j "$R" inversionista_id)" == "$IK" ]] && ok "[T3] sin el otro lead, la misma reapertura pasa y enlaza (par mutante)" || rojo "T3 par: $(echo "$R" | head -c 300) · persona_reabrir=$(q "select private.lead_persona_reabrir('$LK')") · IK=$IK · flag=$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'") · lead=$(q "select etapa||' '||coalesce(inversionista_id::text,'-')||' '||dni from crm.leads where id='$LK'")"
DL="5${RUN}3"; IL="$(resolver "$DL")"; flag false; LL="$(uuid)"; lead_de "$LL" 25 L "'$DL'"; descartar "$LL"; flag true; sys "update crm.inversionistas set no_contactar=true, no_contactar_en=now(), no_contactar_por='$G' where id='$IL'"
R="$(reabrir "$LL")"; echo "$R" | grep -q "P0429" && [[ "$(q "select etapa from crm.leads where id='$LL'")" == "descartado" ]] && ok "[T4] la PERSONA tiene «No insistir» (suelto por documento) → P0429, sigue descartado" || rojo "T4: $(echo "$R" | head -c 200)"
LL2="$(uuid)"; lead_de "$LL2" 31 L2; sys "update crm.leads set no_contactar=true where id='$LL2'"; descartar "$LL2"
R="$(reabrir "$LL2")"; echo "$R" | grep -q "P0429" && [[ "$(q "select etapa from crm.leads where id='$LL2'")" == "descartado" ]] && ok "[T4b] ON: el propio lead con «No insistir» → P0429 (par de O8: apagada reabre, encendida no)" || rojo "T4b: $(echo "$R" | head -c 200)"
DM="5${RUN}4"; flag false; LM="$(uuid)"; lead_de "$LM" 26 M "'$DM'"; descartar "$LM"; flag true; AUM="$(uuid)"; sim_perfil "$AUM" "$DM" "m$RUN@x.pe"
R="$(reabrir "$LM")"; echo "$R" | grep -q "ya es cliente o ya tiene su lead" && [[ "$(q "select etapa from crm.leads where id='$LM'")" == "descartado" ]] && ok "[T5] el documento es de un CLIENTE del Portal → P0409 (ya es cliente), sigue descartado" || rojo "T5: $(echo "$R" | head -c 220)"
DN="5${RUN}5"; LN0="$(uuid)"; lead_de "$LN0" 27 N0; R="$(reservar "$V" "$LN0" "$DN" "$(pay "n$RUN@x.pe" N 7)")"; IN="$(j "$R" inversionista_id)"
flag false; LN="$(uuid)"; lead_de "$LN" 28 N "'$DN'"; descartar "$LN"; flag true
[[ -n "$IN" && "$(j "$R" estado)" == "reclamado" ]] && ok "fixture: reserva viva de LN0 para la persona de $DN; LN descartado con ese DNI" || rojo "fixture reserva: $(echo "$R" | head -c 200)"
R="$(reabrir "$LN")"; echo "$R" | grep -q "P0409" && [[ "$(q "select etapa from crm.leads where id='$LN'")" == "descartado" ]] && ok "[T6] la persona está EN CONVERSIÓN (reserva viva de otro lead) → P0409, sigue descartado" || rojo "T6: $(echo "$R" | head -c 220)"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin isolation level repeatable read; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$V\",\"role\":\"authenticated\"}', true); select crm.reabrir_lead_fn('$LN'); rollback;" 2>&1)"; echo "$R" | grep -q "0A000" && ok "[T7] con ON exige READ COMMITTED (repeatable read → 0A000)" || rojo "T7: $(echo "$R" | head -c 200)"
LO="$(uuid)"; lead_de "$LO" 29 O; descartar "$LO"
R="$(reabrir "$LO" "$AJENO")"; echo "$R" | grep -q "42501" && ok "[T8] ON: sesión sin rol CRM → 42501 antes de cualquier candado" || rojo "T8: $(echo "$R" | head -c 200)"
R="$(reabrir "$LO" "$SUP")"; [[ "$(j "$R" etapa)" == "nuevo" ]] && ok "[T8] ON: el supervisor reabre el lead de su analista" || rojo "T8 sup: $(echo "$R" | head -c 200)"
LP="$(uuid)"; lead_de "$LP" 30 P; descartar "$LP"; LP2="$(uuid)"; lead_de "$LP2" 30 P2
R="$(reabrir "$LP")"; echo "$R" | grep -q "uq_leads_telefono_vivo" && [[ "$(q "select etapa from crm.leads where id='$LP'")" == "descartado" ]] && ok "[T9] ON: otro lead vivo con el teléfono → 23505 (mismo índice; nada se enlazó)" || rojo "T9: $(echo "$R" | head -c 200)"

echo "== Limpieza =="
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); update crm.leads set activo=false where nombre_completo like 'D15 % r$RUN' and activo; update crm.inversionistas set no_contactar=false where id='${IL:-00000000-0000-0000-0000-000000000000}'; commit;" >/dev/null 2>&1
psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b D-15: VERDE — apagada, la puerta es el UPDATE de hoy (paridad de foto); encendida, juzga a la persona (otro lead, veto, cliente, conversión), enlaza y respeta ámbito, grants, aislamiento y candados."; else echo "ORÁCULO F2.b D-15: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
