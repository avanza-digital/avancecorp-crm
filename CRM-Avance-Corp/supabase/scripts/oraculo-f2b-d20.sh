#!/usr/bin/env bash
# ORÁCULO F2.b [D-20] — el cliente que vuelve deja tarea a su analista — SOLO en el BANCO.
# Lo que tiene que probar: (1) apagada, el importador hace exactamente lo de siempre; (2) encendida, un cliente CON
# lead vivo sigue recibiendo el reingreso en su lead y NO se le duplica el trabajo con una tarea; (3) encendida, un
# cliente SIN lead vivo deja nota en su ficha y TAREA para el analista de su cartera; (4) reenviar la misma fila no
# duplica nada; (5) un cliente sin analista activo deja la nota igual y lo dice; (6) un cliente inactivo no escribe.
# Ojo con los documentos: la siembra F3 usa 7RUN1, aquí van con prefijo 5.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d20.sh. Sin D-20 = corrida MUTANTE (S2..S5, S8 y S9 en rojo).
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR"; }
flag() { local i; for i in 1 2 3 4 5; do psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null 2>&1; [[ "$(psql "$PG" -qtA -c "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'" 2>/dev/null)" == "$( [[ "$1" == "true" ]] && echo t || echo f )" ]] && return 0; sleep 3; done; rojo "bandera: no se pudo poner en $1"; }
estado() { [[ "$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")" == "$1" ]] || { echo "  ⚠️ la bandera se había movido (otra sesión): se repone"; flag "$( [[ "$1" == "t" ]] && echo true || echo false )"; }; }
uuid() { q "select gen_random_uuid()"; }
# El importador exige que NO haya sesión de usuario (service_role). psql como postgres cumple: auth.uid() es null.
importar() { psql "$PG" -qtA -c "select crm.importar_lead_fn('$1'::jsonb)" 2>&1; }
fila() { python3 -c "
import json,sys
print(json.dumps({'fila':int(sys.argv[1]),'nombre_completo':sys.argv[2],'telefono':sys.argv[3],'dni':sys.argv[4],
 'origen':'landing','monto_estimado':'5000','moneda':'PEN','categoria_interes':'nuevo','distrito':'Miraflores',
 'nota':sys.argv[5]}))" "$1" "$2" "$3" "$4" "$5"; }
cliente() { # $1 perfil $2 dni $3 asesor(o vacio)
  psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true);
    insert into auth.users (id) values ('$1') on conflict do nothing;
    insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo)
    values ('$1','D20 CLIENTE $2 r$RUN','cliente','DNI','$2','c$2@x.pe', $( [[ -n "$3" ]] && echo "'$3'" || echo null ), true); commit;" 2>&1 | grep -E "ERROR"
  local inv; inv="$(q "select private.inversionista_resolver('DNI','$2',true,'ensayo-d20')")"
  sys "update crm.inversionistas set perfil_id='$1' where id='$inv'"
  echo "$inv"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
INST="$(q "select (to_regprocedure('private.registrar_solicitud_cliente_fn(uuid,text,jsonb)') is not null)::int")"
[[ "$INST" == "1" ]] && echo "  D-20 instalada (todo debe salir VERDE)" || echo "  ⚠️ D-20 NO instalada: corrida MUTANTE (S2..S5 en rojo)"

echo "== (1) Apagada: el importador hace lo de siempre =="
flag false; estado f
D1="5${RUN}1"; P1="$(uuid)"; cliente "$P1" "$D1" "$V" >/dev/null
R="$(importar "$(fila 11 "D20 UNO" "9${RUN}11" "$D1" "apagada")")"
if echo "$R" | grep -q '"resultado" *: *"importado"'; then ok "[S1] APAGADA: la fila de un cliente entra como lead nuevo, exactamente como hoy"; else rojo "S1: $(echo "$R" | head -c 200)"; fi
[[ "$(q "select count(*) from crm.tareas t where t.perfil_id='$P1'")" == "0" ]] && ok "[S1] y apagada no se crea ninguna tarea de cliente" || rojo "S1: se creó tarea con la bandera apagada"

echo "== (2) Encendida, cliente CON lead vivo: reingreso en el lead, sin tarea duplicada =="
flag true; estado t
R="$(importar "$(fila 12 "D20 UNO" "9${RUN}12" "$D1" "vuelve con lead")")"
if echo "$R" | grep -q '"resultado" *: *"ya_cliente"'; then ok "[S2] ENCENDIDA: el CRM la reconoce y responde «ya es cliente» (no duplica su ficha)"; else rojo "S2: $(echo "$R" | head -c 220)"; fi
# Buscar la CLAVE no vale: aparece también con valor null (Codex). Se exige la escritura de verdad.
echo "$R" | grep -q '"reingreso": *{' && [[ "$(q "select count(*) from crm.actividades a where a.lead_id='$(q "select id from crm.leads where dni='$D1' and activo and etapa not in ('convertido','descartado') limit 1")' and a.metadata->>'evento'='reingreso'")" == "1" ]] && ok "[S2] el reingreso queda anotado en su lead vivo (comprobado en la tabla, no en la clave)" || rojo "S2: el reingreso no quedó escrito · $(echo "$R" | head -c 200)"
[[ "$(q "select count(*) from crm.tareas t where t.perfil_id='$P1' and t.estado='pendiente'")" == "0" ]] && ok "[S2] y NO se le crea tarea aparte: el lead vivo ya es el trabajo" || rojo "S2: se duplicó el trabajo (lead + tarea)"

echo "== (3) Encendida, cliente SIN lead vivo: nota en la ficha y TAREA a su analista =="
D2="5${RUN}2"; P2="$(uuid)"; cliente "$P2" "$D2" "$V" >/dev/null
R="$(importar "$(fila 13 "D20 DOS" "9${RUN}13" "$D2" "quiero informacion")")"
if echo "$R" | grep -q '"resultado" *: *"ya_cliente"'; then ok "[S3] ENCENDIDA: cliente sin lead reconocido como «ya es cliente»"; else rojo "S3: $(echo "$R" | head -c 220)"; fi
[[ "$(q "select count(*) from crm.actividades_cliente a where a.cliente_id='$P2' and a.tipo='nota' and a.detalle like 'Pidió información por la web%'")" == "1" ]] && ok "[S3] queda la NOTA en la ficha del cliente, con lo que pidió" || rojo "S3: no quedó la nota en la ficha"
TAREA="$(q "select id from crm.tareas t where t.perfil_id='$P2' and t.estado='pendiente' limit 1")"
[[ -n "$TAREA" ]] && ok "[S3] y se crea la TAREA de llamada pendiente" || rojo "S3: no se creó la tarea"
[[ "$(q "select vendedor_id from crm.tareas where id='$TAREA'")" == "$V" ]] && ok "[S3] la tarea queda a nombre del ANALISTA de su cartera" || rojo "S3: la tarea no quedó en el analista del cliente ($(q "select vendedor_id from crm.tareas where id='$TAREA'"))"
[[ "$(q "select count(*) from crm.leads l where l.activo and l.dni='$D2'")" == "0" ]] && ok "[S3] y no se le crea un lead nuevo: su ficha no se duplica" || rojo "S3: se creó un lead pese a ser cliente"

echo "== (4) Reenviar la MISMA fila no duplica nada =="
R="$(importar "$(fila 13 "D20 DOS" "9${RUN}13" "$D2" "quiero informacion")")"
echo "$R" | grep -q '"repetido" *: *true' && ok "[S4] el reenvío se reconoce como repetido" || rojo "S4: no marcó repetido · $(echo "$R" | head -c 200)"
[[ "$(q "select count(*) from crm.actividades_cliente a where a.cliente_id='$P2' and a.tipo='nota'")" == "1" && "$(q "select count(*) from crm.tareas t where t.perfil_id='$P2'")" == "1" ]] && ok "[S4] sigue habiendo UNA nota y UNA tarea" || rojo "S4: se duplicó (notas=$(q "select count(*) from crm.actividades_cliente where cliente_id='$P2'") tareas=$(q "select count(*) from crm.tareas where perfil_id='$P2'"))"

echo "== (5) Cliente sin analista en su ficha: la nota cae en el responsable de su identidad =="
D3="5${RUN}3"; P3="$(uuid)"; INV3="$(cliente "$P3" "$D3" "")"
sys "insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por) values ('$INV3','$V', now(), 'ensayo d20', '$G')"
R="$(importar "$(fila 14 "D20 TRES" "9${RUN}14" "$D3" "sin asesor en la ficha")")"
[[ "$(q "select count(*) from crm.actividades_cliente a where a.cliente_id='$P3' and a.tipo='nota'")" == "1" ]] && ok "[S5] sin analista en la ficha, la NOTA queda igual, a nombre del responsable vivo de su identidad" || rojo "S5: no quedó la nota · $(echo "$R" | head -c 200)"
[[ "$(q "select vendedor_id from crm.actividades_cliente where cliente_id='$P3' limit 1")" == "$V" ]] && ok "[S5] y queda atribuida a ese responsable" || rojo "S5: la nota no quedó en el responsable"
echo "$R" | grep -q '"sin_tarea" *: *true' && ok "[S5] la respuesta avisa de que no se pudo crear la tarea (la agenda exige analista en la ficha)" || rojo "S5: no avisó de la tarea imposible · $(echo "$R" | head -c 220)"

echo "== (5b) Cliente sin analista NI responsable: no se inventa a quién atribuirlo, y se dice =="
D5="5${RUN}5"; P5="$(uuid)"; cliente "$P5" "$D5" "" >/dev/null
R="$(importar "$(fila 16 "D20 CINCO" "9${RUN}16" "$D5" "huerfano")")"
echo "$R" | grep -q '"sin_ficha" *: *true' && ok "[S5b] sin nadie a cargo, la respuesta lo dice en vez de fallar en silencio" || rojo "S5b: no avisó · $(echo "$R" | head -c 220)"
[[ "$(q "select count(*) from crm.actividades_cliente a where a.cliente_id='$P5'")" == "0" ]] && ok "[S5b] y no se inventa un responsable para la nota" || rojo "S5b: escribió una nota sin responsable real"

echo "== (6) Cliente inactivo: no se escribe nada =="
D4="5${RUN}4"; P4="$(uuid)"; cliente "$P4" "$D4" "$V" >/dev/null
sys "update public.perfiles set activo=false where id='$P4'"
R="$(importar "$(fila 15 "D20 CUATRO" "9${RUN}15" "$D4" "inactivo")")"
[[ "$(q "select count(*) from crm.actividades_cliente a where a.cliente_id='$P4'")" == "0" && "$(q "select count(*) from crm.tareas t where t.perfil_id='$P4'")" == "0" ]] && ok "[S6] con el cliente inactivo no se anota nada ni se crea tarea" || rojo "S6: escribió sobre un cliente inactivo"

echo "== (7) El ayudante no está expuesto a la API =="
[[ "$(q "select (has_function_privilege('authenticated','private.registrar_solicitud_cliente_fn(uuid,text,jsonb)','EXECUTE') or has_function_privilege('anon','private.registrar_solicitud_cliente_fn(uuid,text,jsonb)','EXECUTE') or has_function_privilege('service_role','private.registrar_solicitud_cliente_fn(uuid,text,jsonb)','EXECUTE'))::int")" == "0" ]] && ok "[S7] el ayudante no es llamable por authenticated, anon ni service_role" || rojo "S7: el ayudante quedó expuesto"

echo "== (8) Cliente que se CONVIRTIÓ desde un lead: su lead está cerrado, así que también deja tarea =="
# El caso que destapó el auditor: `leads_de_personas` devuelve también los leads convertidos, así que sin el arreglo
# la solicitud iba a anotarse en un lead cerrado que nadie mira, y sin tarea. En producción los 17 clientes con lead
# lo tienen así.
flag false; estado f
D8="5${RUN}8"; P8="$(uuid)"; L8="$(uuid)"
sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$L8','D20 OCHO r$RUN','9${RUN}18','$D8',1000,'landing','nuevo','$V','$V')"
INV8="$(cliente "$P8" "$D8" "$V")"
psql "$PG" -qtA -c "begin; set local role authenticated; select set_config('request.jwt.claims','{\"sub\":\"$G\",\"role\":\"authenticated\"}',true); select crm.convertir_lead('$L8','$P8'); commit;" >/dev/null 2>&1
[[ "$(q "select etapa from crm.leads where id='$L8'")" == "convertido" ]] && ok "[S8] fixture: el cliente tiene su lead CONVERTIDO (cerrado)" || rojo "S8 fixture: el lead no quedó convertido ($(q "select etapa from crm.leads where id='$L8'"))"
flag true; estado t
R="$(importar "$(fila 18 "D20 OCHO" "9${RUN}19" "$D8" "vuelve tras convertirse")")"
[[ "$(q "select count(*) from crm.actividades_cliente a where a.cliente_id='$P8' and a.tipo='nota'")" == "1" ]] && ok "[S8] la solicitud deja NOTA en su ficha de cliente, no en el lead cerrado" || rojo "S8: no quedó nota en la ficha · $(echo "$R" | head -c 200)"
[[ "$(q "select count(*) from crm.tareas t where t.perfil_id='$P8' and t.estado='pendiente'")" == "1" ]] && ok "[S8] y su analista recibe la TAREA (antes del arreglo, no la recibía nadie)" || rojo "S8: no se creó la tarea para el cliente convertido"
[[ "$(q "select count(*) from crm.actividades a where a.lead_id='$L8' and a.metadata->>'evento'='reingreso'")" == "0" ]] && ok "[S8] y no se escribe en el lead cerrado" || rojo "S8: escribió el reingreso en un lead cerrado"

echo "== (9) La defensa del veto es del propio ayudante, no del orden de los triggers =="
D9="5${RUN}9"; P9="$(uuid)"; INV9="$(cliente "$P9" "$D9" "$V")"
sys "update crm.inversionistas set no_contactar=true, no_contactar_en=now(), no_contactar_por='$G' where id='$INV9'"
R="$(psql "$PG" -qtA -c "select private.registrar_solicitud_cliente_fn('$P9','hoja','{\"nombre\":\"D20 NUEVE\"}'::jsonb)" 2>&1)"
echo "$R" | grep -q '"vetado" *: *true' && ok "[S9] llamado directamente con una persona vetada, el ayudante se niega él mismo" || rojo "S9: el ayudante no comprobó el veto · $(echo "$R" | head -c 200)"
[[ "$(q "select count(*) from crm.actividades_cliente where cliente_id='$P9'")" == "0" && "$(q "select count(*) from crm.tareas where perfil_id='$P9'")" == "0" ]] && ok "[S9] y no escribe ni nota ni tarea a una persona con «No insistir»" || rojo "S9: escribió sobre una persona vetada"

echo "== Limpieza =="
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true);
  update crm.leads set activo=false where nombre_completo like 'D20 % r$RUN' or telefono like '9${RUN}%';
  delete from crm.tareas where perfil_id in ('$P1','$P2','$P3','$P4','$P5','$P8','$P9');
  delete from crm.actividades_cliente where cliente_id in ('$P1','$P2','$P3','$P4','$P5','$P8','$P9');
  commit;" >/dev/null 2>&1
# El banco es COMPARTIDO: un cliente de prueba sin analista descuadra los conteos de la suite de otra sesión.
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true);
  update public.perfiles set activo=false where nombre_completo like 'D20 CLIENTE % r$RUN' or nombre_completo like 'D20 ANALISTA% r$RUN'; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b D-20: VERDE — el cliente que vuelve nunca se pierde: con lead vivo va al lead, sin lead deja nota y tarea a su analista, y reenviar no duplica."; else echo "ORÁCULO F2.b D-20: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
