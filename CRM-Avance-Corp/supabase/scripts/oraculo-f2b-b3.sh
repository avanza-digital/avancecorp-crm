#!/usr/bin/env bash
# ORÁCULO F2.b sub-lote b3 — «el cliente creado sin lead es una persona» — SOLO en el BANCO.
# Simula los pasos del edge (createUser = insert en auth.users; INSERT del perfil) y ejercita la
# SAGA por sus pasos, la capacidad de alta, el enlace, el responsable, el preflight de eliminación,
# la protección del documento y la paridad con la bandera apagada.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-b3.sh   (lee $S/banco-pooler.txt). Presupone E1 + b3.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SU='f3000000-0000-0000-0000-000000000003'
VI='f3000000-0000-0000-0000-000000000005'   # vendedor INACTIVO (responsable no válido)
DA="7${RUN}5"; DB="7${RUN}6"; DC="7${RUN}7"; DD="7${RUN}8"; DE="7${RUN}9"; ROJO=0
AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
run_sys() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; $1; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
flag() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null; }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]); print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
alta() { run_as "$1" "select crm.alta_cliente_identidad_fn('$2', '$3'::jsonb)"; }
alta_sys() { run_sys "select crm.alta_cliente_identidad_fn('$1', '$2'::jsonb)"; }
sim_auth()  { psql "$PG" -q -c "insert into auth.users (id, email, raw_app_meta_data) values ('$1', '$2', jsonb_build_object('claim_id','$3')) on conflict (id) do nothing;" 2>/dev/null; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','B3 CLIENTE $2 r$RUN','cliente','DNI','$2','$3',$4,true); commit;" 2>&1 | grep -E "ERROR" ; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select to_regprocedure('crm.alta_cliente_identidad_fn(text,jsonb)') is not null")" == "t" ]] || { echo "falta b3" >&2; exit 2; }
# VI: miembro CRM INACTIVO (asesor que no puede ser responsable).
psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$VI') on conflict (id) do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$VI','F3 VENDEDOR INACTIVO','comercial','DNI','70000095') on conflict (id) do update set activo=true; insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por) values ('$VI','vendedor','$SU',false,'$SU') on conflict (perfil_id) do update set activo=false; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag true

echo "== Capacidad de alta (= autorizacion.mjs) =="
[[ "$(q "select (private.puede_alta_cliente())->>'ok'")" == "false" ]] && ok "sin sesión: puede_alta_cliente = false (el importador entra como service_role y no pasa por aquí)" || rojo "helper sin sesión: $(q "select private.puede_alta_cliente()")"
R="$(run_as "$G" "select private.puede_alta_cliente()" | tail -1)"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" via)" == "crm" && -z "$(j "$R" asesor_id)" ]] && ok "gerencia CRM: ok vía crm, sin autoasignarse" || rojo "gerencia: $R"
R="$(run_as "$V" "select private.puede_alta_cliente()" | tail -1)"; [[ "$(j "$R" ok)" == "True" && "$(j "$R" asesor_id)" == "$V" ]] && ok "vendedor: ok y se autoasigna como asesor" || rojo "vendedor: $R"
R="$(run_as "$VI" "select private.puede_alta_cliente()" | tail -1)"; [[ "$(j "$R" ok)" == "False" ]] && ok "miembro CRM inactivo (revocado): no puede" || rojo "inactivo pudo: $R"

echo "== Saga completa: reclamar → auth → perfil → enlazar (Gerencia) =="
R="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"a$RUN@x.pe\",\"nombre_completo\":\"B3 A\"}")"
CL="$(j "$R" claim_id)"; TK="$(j "$R" token)"; VER="$(j "$R" version)"; INV="$(j "$R" inversionista_id)"
[[ -n "$CL" && -n "$TK" && "$(j "$R" estado)" == "reclamado" && "$VER" == "1" ]] && ok "reclamar: claim, token y estado reclamado (v1)" || rojo "reclamar: $R"
[[ "$(q "select count(*) from crm.inversionista_identificadores where documento_normalizado='$DA' and verificado")" == "1" ]] && ok "identidad creada (documento verificado, fuente alta_cliente)" || rojo "sin identidad"
[[ "$(q "select count(*) from crm.multiempresa_idempotencia where clave='auth_persona:$INV'")" == "1" && "$(q "select count(*) from crm.multiempresa_idempotencia where clave like '%$DA%'")" == "0" ]] && ok "claim por IDENTIDAD, sin documento en la clave" || rojo "clave del claim"
R2="$(alta "$V" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"a$RUN@x.pe\",\"nombre_completo\":\"B3 A\"}")"; echo "$R2" | grep -q "P0409" && ok "otra sesión (vendedor) con el mismo documento y lease vivo → P0409 «alta en curso»" || rojo "segunda sesión reclamó: $R2"
R3="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"a$RUN@x.pe\",\"nombre_completo\":\"B3 A\"}")"; echo "$R3" | grep -q "P0409" && ok "misma sesión SIN token con lease vivo → P0409 (no expulsa a la ejecución activa)" || rojo "misma sesión sin token reanudó: $R3"
R3="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"a$RUN@x.pe\",\"nombre_completo\":\"B3 A\",\"token\":\"$TK\"}")"; [[ "$(j "$R3" reanudar)" == "True" && "$(j "$R3" version)" == "2" && "$(j "$R3" token)" != "$TK" ]] && ok "misma ejecución CON token: reanuda, rota el token, v2" || rojo "reanudación con token: $R3"
TK="$(j "$R3" token)"; VER="$(j "$R3" version)"
R4="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"otro$RUN@x.pe\",\"nombre_completo\":\"B3 A\",\"token\":\"$TK\"}")"; [[ "$(j "$R4" reanudar)" == "True" && "$(j "$R4" estado)" == "reclamado" ]] && ok "en 'reclamado', un payload DISTINTO con token REINICIA la huella (nada externo aún; auditor b3 A2)" || rojo "payload distinto en reclamado: $R4"
TK="$(j "$R4" token)"; VER="$(j "$R4" version)"
R4="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"a$RUN@x.pe\",\"nombre_completo\":\"B3 A\",\"token\":\"$TK\"}")"; TK="$(j "$R4" token)"; VER="$(j "$R4" version)"
AU="$(uuid)"; AUX="$(uuid)"; sim_auth "$AUX" "x$RUN@x.pe" "otro-claim"
R5="$(alta "$G" registrar_auth "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"auth_user_id\":\"$AUX\",\"version\":$VER}")"; echo "$R5" | grep -q "marca de este claim" && ok "Auth SIN la marca de este claim → rechazado en servidor (P0409)" || rojo "Auth ajeno aceptado: $R5"
sim_auth "$AU" "a$RUN@x.pe" "$CL"
R5="$(alta "$G" registrar_auth "{\"claim_id\":\"$CL\",\"token\":\"malo\",\"auth_user_id\":\"$AU\",\"version\":$VER}")"; echo "$R5" | grep -q "42501" && ok "token inválido → 42501" || rojo "token malo aceptado: $R5"
R5="$(alta "$G" registrar_auth "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"auth_user_id\":\"$AU\",\"version\":1}")"; echo "$R5" | grep -q "40001" && ok "versión obsoleta → 40001 (CAS)" || rojo "CAS no detectó: $R5"
R5="$(alta "$G" registrar_auth "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"auth_user_id\":\"$AU\",\"version\":$VER}")"; [[ "$(j "$R5" estado)" == "auth_creado" ]] && ok "registrar_auth → auth_creado" || rojo "registrar_auth: $R5"; VER="$(j "$R5" version)"
R4b="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"otro2$RUN@x.pe\",\"nombre_completo\":\"B3 A\",\"token\":\"$TK\"}")"; echo "$R4b" | grep -q "datos distintos" && ok "tras auth_creado, un payload DISTINTO → P0409 (el Auth ya lleva los datos)" || rojo "payload distinto tras auth aceptado: $R4b"
AU2="$(uuid)"; sim_auth "$AU2" "a2$RUN@x.pe" "$CL"; R5b="$(alta "$G" registrar_auth "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"auth_user_id\":\"$AU2\",\"version\":$VER}")"; echo "$R5b" | grep -q "transición inválida" && [[ "$(q "select resultado->>'auth_user_id' from crm.multiempresa_idempotencia where clave='auth_persona:$INV'")" == "$AU" ]] && ok "repetir auth_creado con OTRO Auth → rechazado, el claim conserva su Auth (auditor b3 A1)" || rojo "repetición reescribió el Auth: $R5b"
sim_perfil "$AU" "$DA" "a$RUN@x.pe" "'$V'"
R6="$(alta "$G" perfil_creado "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"perfil_id\":\"$AU\",\"version\":$VER}")"; [[ "$(j "$R6" estado)" == "perfil_creado" ]] && ok "perfil_creado" || rojo "perfil_creado: $R6"; VER="$(j "$R6" version)"
R7x="$(alta "$G" enlazar "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"version\":$VER,\"perfil_id\":\"$AU2\"}")"; echo "$R7x" | grep -q "es el del claim" && ok "enlazar con un perfil_id distinto al del claim → P0409" || rojo "enlazar aceptó perfil ajeno: $R7x"
R7="$(alta "$G" enlazar "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"version\":$VER}")"; [[ "$(j "$R7" estado)" == "enlazado" && "$(j "$R7" tramo_abierto)" == "True" ]] && ok "enlazar → enlazado, con tramo de responsable" || rojo "enlazar: $R7"
[[ "$(q "select perfil_id='$AU' and responsable_relacion_id='$V' from crm.inversionistas where id='$INV'")" == "t" ]] && ok "identidad.perfil_id = perfil nuevo; responsable = asesor (V, activo)" || rojo "enlace/responsable incorrectos"
[[ "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$INV' and hasta is null and motivo='alta_cliente' and responsable_id='$V'")" == "1" ]] && ok "un tramo abierto motivo alta_cliente" || rojo "tramo"
R8="$(alta "$G" enlazar "{\"claim_id\":\"$CL\",\"token\":\"$TK\",\"version\":$(j "$R7" version)}")"; [[ "$(j "$R8" estado)" == "enlazado" ]] && ok "enlazar repetido: idempotente" || rojo "enlazar repetido: $R8"
R9="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DA\",\"correo\":\"a$RUN@x.pe\",\"nombre_completo\":\"B3 A\"}")"; [[ "$(j "$R9" estado)" == "enlazado" && "$(j "$R9" perfil_id)" == "$AU" ]] && ok "reclamar de nuevo → la SAGA responde 'enlazado' con perfil_id (respuesta perdida recuperada, sin Auth)" || rojo "re-alta: $R9"

echo "== Reanudación por lease vencido (otra sesión) y muerte tras createUser =="
R="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DB\",\"correo\":\"b$RUN@x.pe\",\"nombre_completo\":\"B3 B\"}")"; CLB="$(j "$R" claim_id)"; TKB="$(j "$R" token)"; VERB="$(j "$R" version)"; INVB="$(j "$R" inversionista_id)"
AUB="$(uuid)"; sim_auth "$AUB" "b$RUN@x.pe" "$CLB"
alta "$G" registrar_auth "{\"claim_id\":\"$CLB\",\"token\":\"$TKB\",\"auth_user_id\":\"$AUB\",\"version\":$VERB}" >/dev/null
psql "$PG" -q -c "update crm.multiempresa_idempotencia set resultado = resultado || jsonb_build_object('lease_hasta', (now() - interval '1 minute')::text) where clave='auth_persona:$INVB';"
R="$(alta "$V" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DB\",\"correo\":\"b$RUN@x.pe\",\"nombre_completo\":\"B3 B\"}")"; [[ "$(j "$R" reanudar)" == "True" && "$(j "$R" estado)" == "auth_creado" && "$(j "$R" auth_user_id)" == "$AUB" ]] && ok "lease vencido: otra sesión reanuda en auth_creado y recibe el auth_user_id (el edge verifica app_metadata.claim_id)" || rojo "reanudación por lease: $R"
TKB="$(j "$R" token)"; VERB="$(j "$R" version)"
sim_perfil "$AUB" "$DB" "b$RUN@x.pe" "'$V'"
R="$(alta "$V" enlazar "{\"claim_id\":\"$CLB\",\"token\":\"$TKB\",\"version\":$VERB}")"; [[ "$(j "$R" estado)" == "enlazado" ]] && ok "enlazar directo desde auth_creado (perfil ya insertado por el edge) → enlazado" || rojo "enlazar desde auth_creado: $R"

echo "== Perfil suelto con el documento (creado con la bandera apagada) → se enlaza =="
flag false; P2="$(uuid)"; sim_auth "$P2" "c$RUN@x.pe" "sin-claim"; sim_perfil "$P2" "$DC" "c$RUN@x.pe" "'$V'"; flag true
R="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DC\",\"correo\":\"c$RUN@x.pe\",\"nombre_completo\":\"B3 C\"}")"; [[ "$(j "$R" estado)" == "ya_existia" && "$(j "$R" perfil_id)" == "$P2" ]] && ok "reclamar con documento de un perfil suelto → resultado ya_existia (perfil enlazado al vuelo, sin excepción)" || rojo "perfil suelto: $R"
[[ "$(q "select count(*) from crm.inversionistas i join crm.inversionista_identificadores d on d.inversionista_id=i.id where d.documento_normalizado='$DC' and i.perfil_id='$P2'")" == "1" ]] && ok "identidad de $DC apunta al perfil suelto" || rojo "perfil suelto sin enlazar"

echo "== Asesor inactivo → sin tramo, revision_responsable =="
R="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DD\",\"correo\":\"d$RUN@x.pe\",\"nombre_completo\":\"B3 D\"}")"; CLD="$(j "$R" claim_id)"; TKD="$(j "$R" token)"; VERD="$(j "$R" version)"; INVD="$(j "$R" inversionista_id)"
AUD="$(uuid)"; sim_auth "$AUD" "d$RUN@x.pe" "$CLD"; R="$(alta "$G" registrar_auth "{\"claim_id\":\"$CLD\",\"token\":\"$TKD\",\"auth_user_id\":\"$AUD\",\"version\":$VERD}")"; VERD="$(j "$R" version)"
sim_perfil "$AUD" "$DD" "d$RUN@x.pe" "'$VI'"
R="$(alta "$G" enlazar "{\"claim_id\":\"$CLD\",\"token\":\"$TKD\",\"version\":$VERD}")"; [[ "$(j "$R" estado)" == "enlazado" && "$(j "$R" revision_responsable)" == "True" && "$(j "$R" tramo_abierto)" == "False" ]] && ok "asesor inactivo: enlaza pero NO abre tramo y pide revisión" || rojo "asesor inactivo: $R"
[[ "$(q "select responsable_relacion_id is null from crm.inversionistas where id='$INVD'")" == "t" ]] && ok "sin responsable de relación" || rojo "responsable asignado a un inactivo"

echo "== Dos altas SIMULTÁNEAS del mismo documento nuevo → una reclama, la otra P0409 =="
alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DE\",\"correo\":\"e$RUN@x.pe\",\"nombre_completo\":\"B3 E\"}" > "$S/b3_r1.out" & p1=$!
alta "$V" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"$DE\",\"correo\":\"e$RUN@x.pe\",\"nombre_completo\":\"B3 E\"}" > "$S/b3_r2.out" & p2=$!
wait $p1; wait $p2; n=$(cat "$S/b3_r1.out" "$S/b3_r2.out" | grep -c '"estado": *"reclamado"'); m=$(cat "$S/b3_r1.out" "$S/b3_r2.out" | grep -c "P0409")
[[ "$n" == "1" && "$m" == "1" ]] && ok "exactamente una reclamó; la otra P0409; sin deadlock" || rojo "carrera: reclamados=$n p0409=$m"
[[ "$(q "select count(distinct inversionista_id) from crm.inversionista_identificadores where documento_normalizado='$DE'")" == "1" ]] && ok "una sola identidad para $DE" || rojo "identidades duplicadas"

echo "== Preflight de eliminación y documento protegido =="
R="$(run_sys "select crm.cliente_eliminable_fn('$AU')" | tail -1)"; [[ "$(j "$R" eliminable)" == "False" && "$(j "$R" motivo)" == "identidad" ]] && ok "cliente_eliminable_fn(enlazado) → no eliminable (identidad)" || rojo "eliminable: $R"
R="$(run_as "$G" "select crm.cliente_eliminable_fn('$AU')")"; echo "$R" | grep -q "42501" && ok "authenticated no consulta el preflight (42501)" || rojo "authenticated consultó"
R="$(run_as "$G" "select crm.actualizar_cliente_gerencia_con_domicilio('$AU', '{\"dni\":\"6${RUN}9\",\"domicilio\":\"Av. Prueba 123, Lima\"}'::jsonb)")"; echo "$R" | grep -q "P0409" && ok "cambiar el DNI de un cliente enlazado (Gerencia) → P0409 (corrección de documento, b5)" || rojo "cambio de DNI aceptado: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$G" "select crm.actualizar_cliente_gerencia_con_domicilio('$AU', '{\"telefono\":\"+51999999999\",\"domicilio\":\"Av. Prueba 123, Lima\"}'::jsonb)")"; [[ -z "$(echo "$R"|grep -E 'P0409|ERROR')" ]] && ok "otros campos del cliente enlazado se editan como hoy" || rojo "edición normal bloqueada: $(echo "$R"|tail -1|cut -c1-120)"

echo "== Paridad con bandera APAGADA =="
flag false
R="$(alta "$G" reclamar "{\"tipo_documento\":\"DNI\",\"documento\":\"6${RUN}1\",\"correo\":\"z@x.pe\",\"nombre_completo\":\"Z\"}")"; echo "$R" | grep -q "P0409" && echo "$R" | grep -qi "apagada" && ok "OFF: alta_cliente_identidad_fn inerte (P0409 apagada)" || rojo "OFF: RPC actuó: $R"
R="$(run_sys "select crm.cliente_eliminable_fn('$AU')" | tail -1)"; [[ "$(j "$R" eliminable)" == "True" ]] && ok "OFF: cliente_eliminable_fn no mira la identidad (como hoy: contratos y FK)" || rojo "OFF: preflight miró identidad: $R"
R="$(run_as "$G" "select crm.actualizar_cliente_gerencia_con_domicilio('$AU', '{\"dni\":\"6${RUN}8\",\"domicilio\":\"Av. Prueba 123, Lima\"}'::jsonb)")"; [[ -z "$(echo "$R"|grep -E 'P0409')" ]] && ok "OFF: el DNI de un cliente enlazado se edita como hoy" || rojo "OFF: DNI bloqueado"
run_as "$G" "select crm.actualizar_cliente_gerencia_con_domicilio('$AU', '{\"dni\":\"$DA\",\"domicilio\":\"Av. Prueba 123, Lima\"}'::jsonb)" >/dev/null
flag true

psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b b3: VERDE — saga reanudable por identidad, capacidad de alta, enlace y responsable, preflight y documento protegido; paridad apagada."; exit 0
else echo "ORÁCULO F2.b b3: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
