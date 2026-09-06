#!/usr/bin/env bash
# ORÁCULO F2.b [D-4] — el importador entra por la puerta SQL: crm.importar_lead_fn responde, fila a fila, EXACTAMENTE lo que hoy
# produce el INSERT directo del edge (paridad OFF y ON), toma los candados en el orden total y solo la usa service_role — SOLO en el BANCO.
# Presupone b1..b5 + D-13 + bloque 2 y la siembra siembra-banco-f3.sql (V/S/G). Uso: S=/ruta/scratchpad ./oraculo-f2b-d4.sh
# Sin D-4 (mutante) la puerta no existe: todas las llamadas fallan (42883) y el oráculo sale ROJO.
# v3 (auditor-rls 06/09): + veredicto de duplicado sin PII, claves privilegiadas ignoradas, duplicado por DNI vivo, reingreso que
# falla (definitivo vs transitorio), persona con ficha sin lead, persona en conversión.
# v4 (Codex 06/09): persona vetada con el teléfono retenido → rechazada sin esperar; «en conversión» prueba de verdad la rama de
# la reserva (lead sin documento, ni enlace, ni puente).
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR" ; }
flag() { local i; for i in 1 2 3 4 5; do psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null 2>&1; [[ "$(psql "$PG" -qtA -c "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'" 2>/dev/null)" == "$( [[ "$1" == "true" ]] && echo t || echo f )" ]] && return 0; echo "  (bandera: reintento $i)"; sleep 3; done; echo "  ❌ bandera: no se pudo poner en $1" >&2; ROJO=$((ROJO+1)); }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2])
if isinstance(v,(dict,list)): v=json.dumps(v, sort_keys=True)
print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
jj()   { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]) or {}; v=v.get(sys.argv[3]) if isinstance(v,dict) else None; print('' if v is None else v)" "$1" "$2" "$3" 2>/dev/null; }
# la fila EXACTA que manda el edge (payload de v.insert + fila)
fila() { echo "{\"fila\":$4,\"nombre_completo\":\"D4 $3 r$RUN\",\"telefono\":\"+51$1\",\"telefono_alternativo\":null,\"telefono_alternativo_crudo\":null,\"correo\":null,\"dni\":$2,\"genero\":null,\"fecha_nacimiento\":null,\"distrito\":null,\"origen\":\"landing\",\"etapa\":\"nuevo\",\"monto_estimado\":1000,\"moneda\":\"PEN\",\"categoria_interes\":null,\"nota\":null,\"no_contactar\":false,\"consentimiento_en\":null,\"consentimiento_fuente\":null,\"vendedor_id\":null,\"asignado_supervisor_id\":null,\"activo\":true}"; }
# la PUERTA, como la llama el edge: rol service_role, sin claims de usuario
puerta() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role service_role; select crm.importar_lead_fn('$1'::jsonb); commit;" 2>&1; }
# el INSERT DIRECTO de hoy (edge con service_role): mismas columnas
directo() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role service_role; insert into crm.leads (id,nombre_completo,telefono,telefono_alternativo,telefono_alternativo_crudo,correo,dni,genero,fecha_nacimiento,distrito,origen,etapa,monto_estimado,moneda,categoria_interes,nota,no_contactar,consentimiento_en,consentimiento_fuente,vendedor_id,asignado_supervisor_id,activo) values (gen_random_uuid(),'D4 DIRECTO $3 r$RUN','+51$1',null,null,null,$2,null,null,null,'landing','nuevo',1000,'PEN',null,null,false,null,null,null,null,true) returning id; commit;" 2>&1; }
inv_de() { q "select private.inversionista_por_documento('DNI','$1')"; }
persona() { q "select private.inversionista_resolver('DNI','$1',true,'ensayo-d4')"; }
lead_de() { sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D4 $3 r$RUN','+51$2',$4,1000,'landing','nuevo',null,${5:-null})"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
if [[ "$(q "select to_regprocedure('crm.importar_lead_fn(jsonb)') is not null")" == "t" ]]; then echo "  D-4 instalada (todo debe salir VERDE)"; else echo "  ⚠️ D-4 NO instalada: corrida MUTANTE (todo lo de la puerta sale ROJO)"; fi
flag false

echo "== (1) Autorización: solo service_role, sin sesión de usuario =="
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role authenticated; select set_config('request.jwt.claims','{\"sub\":\"$G\",\"role\":\"authenticated\"}',true); select crm.importar_lead_fn('$(fila 9${RUN}71 null A 1)'::jsonb); commit;" 2>&1)"; echo "$R" | grep -q "42501" && ok "Gerencia (authenticated) → 42501 (sin EXECUTE)" || rojo "authenticated pasó: $(echo "$R" | head -c 160)"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role service_role; select set_config('request.jwt.claims','{\"sub\":\"$G\",\"role\":\"authenticated\"}',true); select crm.importar_lead_fn('$(fila 9${RUN}71 null A 1)'::jsonb); commit;" 2>&1)"; echo "$R" | grep -q "42501" && ok "service_role CON sesión de usuario → 42501 (solo el importador sin sesión)" || rojo "service_role con uid pasó: $(echo "$R" | head -c 160)"
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role anon; select crm.importar_lead_fn('{}'::jsonb); commit;" 2>&1)"; echo "$R" | grep -q "42501" && ok "anon → 42501" || rojo "anon pasó: $(echo "$R" | head -c 160)"
[[ "$(q "select count(*) from crm.leads where telefono='+519${RUN}71'")" == "0" ]] && ok "ningún rechazo de autorización dejó lead" || rojo "quedó lead tras 42501"

echo "== (2) OFF · paridad fila a fila con el INSERT directo (el contrato del importador: sin veredicto comercial) =="
R="$(puerta "$(fila 9${RUN}72 null LIBRE 2)")"; L2="$(j "$R" lead_id)"
[[ "$(j "$R" resultado)" == "importado" && -n "$L2" && "$(q "select telefono||' '||etapa||' '||coalesce(creado_por::text,'null')||' '||alta_manual||' '||activo||' '||coalesce(vendedor_id::text,'null') from crm.leads where id='$L2'")" == "+519${RUN}72 nuevo null false true null" ]] && ok "libre → importado; la fila nace como con el edge (cola global, creado_por null, alta_manual false, activo)" || rojo "[D-4] libre: $(echo "$R" | head -c 220)"
R="$(puerta "$(fila 9${RUN}72 null LIBRE 2)")"; RD="$(directo 9${RUN}72 null LIBRE)"
[[ "$(j "$R" resultado)" == "duplicado" && "$(jj "$R" veredicto estado)" == "duplicado" ]] && echo "$RD" | grep -q "23505" && ok "misma fila otra vez (lead vivo) → duplicado = INSERT directo 23505 (uq_leads_telefono_vivo)" || rojo "[D-4] duplicado: $(echo "$R" | head -c 200) | $(echo "$RD" | grep ERROR | head -1 | cut -c1-100)"
[[ "$(jj "$R" veredicto indice)" == "uq_leads_telefono_vivo" && -z "$(jj "$R" veredicto detalle)" ]] && ok "el veredicto de duplicado nombra el índice (uq_leads_telefono_vivo) y NO lleva el dato en claro (sin PII por el cable)" || rojo "[D-4] veredicto duplicado: $(j "$R" veredicto)"
sys "update crm.leads set vendedor_id='$V' where id='$L2'" >/dev/null
R="$(puerta "$(fila 9${RUN}72 null LIBRE 2)")"; [[ "$(j "$R" resultado)" == "duplicado" ]] && ok "lead vivo tomado por V → duplicado" || rojo "[D-4] duplicado tomado: $(echo "$R" | head -c 200)"
sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes', descartado_en=now(), descartado_por='$V' where id='$L2'" >/dev/null
R="$(puerta "$(fila 9${RUN}72 null LIBRE 2)")"; L2b="$(j "$R" lead_id)"
[[ "$(j "$R" resultado)" == "importado" && -n "$L2b" ]] && ok "descartado reciente → IMPORTADO (el importador no aplica el enfriamiento comercial: el que vuelve por la hoja entra, como hoy)" || rojo "[D-4] descartado: $(echo "$R" | head -c 200)"
RD="$(directo 9${RUN}72 null LIBRE)"; echo "$RD" | grep -q "23505" && ok "y el INSERT directo ahora da 23505 (el lead nuevo está vivo): misma categoría" || rojo "directo tras reingreso: $(echo "$RD" | grep ERROR | head -1 | cut -c1-120)"
# ficha de cliente de Avance con ese DNI y la bandera APAGADA: el importador NO mira la ficha (contrato de hoy) → importado
D3="6${RUN}3"; PF3="$(uuid)"
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$PF3') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$PF3','D4 CLIENTE FICHA r$RUN','cliente','DNI','$D3','d4f$RUN@x.pe','$V',true); commit;" 2>&1 | grep ERROR
[[ "$(q "select count(*) from public.perfiles where id='$PF3' and dni='$D3'")" == "1" ]] && ok "fixture: ficha de cliente PF3 con el DNI D3 (sin identidad, bandera OFF)" || rojo "fixture PF3"
R="$(puerta "$(fila 9${RUN}73 "\"$D3\"" FICHA 3)")"; L3="$(j "$R" lead_id)"
[[ "$(j "$R" resultado)" == "importado" && -n "$L3" ]] && ok "OFF · DNI de una ficha de cliente → importado (el importador de hoy tampoco lo frena; la identidad encendida sí lo reconocerá)" || rojo "[D-4] OFF ficha: $(echo "$R" | head -c 200)"
sys "update crm.leads set etapa='descartado', motivo_descarte='sin_interes', descartado_en=now(), descartado_por='$V' where id='$L3'" >/dev/null
RD="$(directo 9${RUN}73 "'$D3'" FICHA)"; echo "$RD" | grep -qv "ERROR" && [[ "$(q "select count(*) from crm.leads where telefono='+519${RUN}73' and activo")" == "2" ]] && ok "y el INSERT directo con la misma ficha también entra (paridad)" || rojo "directo ficha: $(echo "$RD" | grep ERROR | head -1 | cut -c1-120)"
# lead vivo vetado (no_contactar propio) con el mismo teléfono → duplicado (índice único), como hoy
L4="$(uuid)"; lead_de "$L4" 9${RUN}74 VETO null "'$V'"; sys "update crm.leads set no_contactar=true where id='$L4'" >/dev/null
R="$(puerta "$(fila 9${RUN}74 null VETO 4)")"; RD="$(directo 9${RUN}74 null VETO)"
[[ "$(j "$R" resultado)" == "duplicado" ]] && echo "$RD" | grep -q "23505" && ok "OFF · teléfono de un lead vivo «No insistir» → duplicado = INSERT directo 23505 (el veto propio del lead viejo no juzga al importador hoy)" || rojo "[D-4] OFF veto propio: $(echo "$R" | head -c 160) | $(echo "$RD" | grep ERROR | head -1 | cut -c1-100)"
# fila inválida: la puerta exige lo mismo que la fila al nacer
R="$(puerta "{\"nombre_completo\":\"\",\"telefono\":\"+519${RUN}75\",\"origen\":\"landing\",\"monto_estimado\":1000,\"moneda\":\"PEN\"}")"; echo "$R" | grep -q "22023" && ok "fila sin nombre → 22023" || rojo "sin nombre pasó: $(echo "$R" | head -c 120)"
R="$(puerta "$(fila 9${RUN}76 "\"123\"" DNI 6)")"; echo "$R" | grep -q "22023" && [[ "$(q "select count(*) from crm.leads where telefono='+519${RUN}76'")" == "0" ]] && ok "DNI de 3 dígitos → 22023 y no nace" || rojo "DNI inválido pasó: $(echo "$R" | head -c 120)"
R="$(puerta "$(fila 9${RUN}77 null VEND 7 | sed 's/"vendedor_id":null/"vendedor_id":"'$V'"/')")"; L7="$(j "$R" lead_id)"
[[ "$(j "$R" resultado)" == "importado" && "$(q "select vendedor_id from crm.leads where id='$L7'")" == "$V" && "$(q "select count(*) from crm.lead_asignaciones where lead_id='$L7' and finalizado_en is null and analista_id='$V'")" == "1" ]] && ok "con vendedor (hoja con destino) → importado en su cartera, con episodio abierto en el ledger" || rojo "[D-4] con vendedor: $(echo "$R" | head -c 200)"
R="$(puerta "$(fila 9${RUN}77 null VEND 7 | sed 's/"vendedor_id":null/"vendedor_id":"'$G'"/')")"; echo "$R" | grep -q "ERROR" && ! echo "$R" | grep -q '"resultado"' && [[ "$(q "select count(*) from crm.leads where telefono='+519${RUN}77'")" == "1" ]] && ok "destino que no puede recibir leads (Gerencia) → el error del trigger de tenencia sube tal cual (el edge lo clasifica como hoy)" || rojo "destino inválido: $(echo "$R" | head -c 160)"
# (v3) claves privilegiadas en el payload: la puerta solo lee las columnas del edge; nada del payload forja etapa, activo, no_contactar, alta_manual, creado_por, id, perfil_id, contrato_id ni inversionista_id
PX="$(uuid)"
R="$(puerta "$(fila 9${RUN}88 null PRIV 18 | sed 's/"etapa":"nuevo"/"etapa":"convertido"/; s/"activo":true/"activo":false/; s/"no_contactar":false/"no_contactar":true/; s/}$/,"alta_manual":true,"creado_por":"'$V'","id":"'$PX'","perfil_id":"'$PF3'","contrato_id":"'$PX'","inversionista_id":"'$PX'"}/')")"; L18="$(j "$R" lead_id)"
[[ "$(j "$R" resultado)" == "importado" && -n "$L18" && "$L18" != "$PX" && "$(q "select etapa||' '||activo||' '||no_contactar||' '||alta_manual||' '||coalesce(creado_por::text,'null')||' '||coalesce(perfil_id::text,'null')||' '||coalesce(contrato_id::text,'null')||' '||coalesce(inversionista_id::text,'null') from crm.leads where id='$L18'")" == "nuevo true false false null null null null" ]] && ok "claves privilegiadas en el payload (etapa=convertido, activo=false, no_contactar, alta_manual, creado_por, id, perfil_id, contrato_id, inversionista_id) → IGNORADAS: la fila nace nueva, activa y sin dueño" || rojo "[D-4] claves privilegiadas: $(echo "$R" | head -c 160) fila=$(q "select etapa||' '||activo||' '||no_contactar||' '||alta_manual||' '||coalesce(creado_por::text,'null') from crm.leads where id='$L18'")"
# (v3) duplicado por DNI vivo (el pase 2 del edge solo deduplica por teléfono): teléfono nuevo + DNI de un lead vivo
D19="6${RUN}9"; L19="$(uuid)"; lead_de "$L19" 9${RUN}89 DNIDUP "'$D19'" "'$V'"
R="$(puerta "$(fila 9${RUN}90 "\"$D19\"" DNIDUP2 19)")"; RD="$(directo 9${RUN}90 "'$D19'" DNIDUP2)"
[[ "$(j "$R" resultado)" == "duplicado" && "$(jj "$R" veredicto indice)" == "uq_leads_dni_vivo" ]] && echo "$RD" | grep -q "23505" && [[ "$(q "select count(*) from crm.leads where telefono='+519${RUN}90'")" == "0" ]] && ok "OFF · teléfono nuevo + DNI de un lead vivo → duplicado por uq_leads_dni_vivo = INSERT directo 23505 (el dedup que el edge no hace en memoria)" || rojo "[D-4] duplicado por DNI: $(echo "$R" | head -c 160) | $(echo "$RD" | grep ERROR | head -1 | cut -c1-100)"

echo "== (3) ON · la identidad manda: persona reconocida → ya_cliente con REINGRESO en su lead (hoy en dos pasos); vetada → rechazado =="
flag true
D8="6${RUN}8"; P8="$(persona "$D8")"; L8="$(uuid)"; lead_de "$L8" 9${RUN}78 P8 "'$D8'" "'$V'"
[[ -n "$P8" && "$(q "select inversionista_id from crm.leads where id='$L8'")" == "$P8" ]] && ok "fixture: persona P8 verificada con lead L8 enlazado (de V)" || rojo "fixture P8"
N0="$(q "select count(*) from crm.actividades where lead_id='$L8' and metadata->>'evento'='reingreso'")"
R="$(puerta "$(fila 9${RUN}79 "\"$D8\"" REING 9)")"
[[ "$(j "$R" resultado)" == "ya_cliente" && "$(j "$R" lead_id)" == "$L8" && "$(jj "$R" veredicto via)" == "identidad" && "$(jj "$R" reingreso ok)" == "True" ]] && ok "otro teléfono + DNI de P8 → ya_cliente, lead_id = L8, via identidad, reingreso registrado" || rojo "[D-4] ON ya_cliente: $(echo "$R" | head -c 260)"
[[ "$(q "select count(*) from crm.actividades where lead_id='$L8' and metadata->>'evento'='reingreso' and metadata->'datos'->>'fila'='9'")" == "$((N0+1))" && "$(q "select count(*) from crm.actividades where lead_id='$L8' and metadata->>'evento'='reingreso' and metadata::text like '%$D8%'")" == "0" ]] && ok "la nota de reingreso está en L8 con la fila 9 y SIN el documento" || rojo "nota de reingreso: $(q "select count(*) from crm.actividades where lead_id='$L8' and metadata->>'evento'='reingreso'") (antes $N0)"
[[ "$(q "select count(*) from crm.leads where telefono='+519${RUN}79'")" == "0" ]] && ok "no nació un segundo lead para P8" || rojo "segundo lead para P8"
RD="$(directo 9${RUN}79 "'$D8'" REING)"; echo "$RD" | grep -q "P0481" && echo "$RD" | grep -q "identidad" && echo "$RD" | grep -q "$L8" && ok "INSERT directo de la misma fila → P0481 ya_es_cliente vía identidad con lead_id = L8 (misma información, hoy en el error)" || rojo "directo ON: $(echo "$RD" | grep -E 'ERROR|DETAIL' | head -2 | tr '\n' ' ' | cut -c1-200)"
# persona vetada: rechazado (no_contactar) = INSERT directo P0429 (trigger 000)
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -c "begin; set local role authenticated; select set_config('request.jwt.claims','{\"sub\":\"$V\",\"role\":\"authenticated\"}',true); select crm.marcar_no_contactar('$L8','ensayo D-4 r$RUN'); commit;" 2>&1)"; [[ "$(q "select no_contactar from crm.inversionistas where id='$P8'")" == "t" ]] && ok "fixture: P8 vetada" || rojo "veto P8: $(echo "$R" | head -c 120)"
R="$(puerta "$(fila 9${RUN}80 "\"$D8\"" VETADA 10)")"; RD="$(directo 9${RUN}80 "'$D8'" VETADA)"
[[ "$(j "$R" resultado)" == "rechazado" && "$(jj "$R" veredicto estado)" == "no_contactar" && -z "$(j "$R" reingreso)" ]] && echo "$RD" | grep -q "P0429" && ok "persona vetada → puerta: rechazado (no_contactar), sin reingreso = INSERT directo: P0429" || rojo "[D-4] vetada: $(echo "$R" | head -c 160) | $(echo "$RD" | grep ERROR | head -1 | cut -c1-120)"
# (v4) persona vetada + teléfono retenido por OTRA sesión más de lock_timeout: el veto (trigger 000) va antes que el candado de contacto → rechazado enseguida, no 55P03
psql "$PG" -q -c "begin; select private.bloquear_contactos_lead(array['+519${RUN}97'], null); select pg_sleep(8); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1; T0=$(date +%s)
R="$(puerta "$(fila 9${RUN}97 "\"$D8\"" VETOLOCK 27)")"; T1=$(date +%s)
[[ "$(j "$R" resultado)" == "rechazado" && "$(jj "$R" veredicto estado)" == "no_contactar" && $((T1-T0)) -le 4 ]] && ok "ON · persona vetada con el teléfono retenido por otra sesión → rechazado no_contactar en $((T1-T0)) s, sin esperar el candado de contacto (el veto va antes, como en el INSERT directo)" || rojo "[D-4] vetada con contacto retenido: $((T1-T0)) s $(echo "$R" | head -c 160)"
wait $BG 2>/dev/null
psql "$PG" -qtA -c "begin; set local role authenticated; select set_config('request.jwt.claims','{\"sub\":\"$G\",\"role\":\"authenticated\"}',true); select crm.levantar_no_contactar('$L8','fin r$RUN'); commit;" >/dev/null 2>&1
# (v3) el reingreso FALLA: definitivo → ya_cliente con reingreso.ok=false (la hoja lo dice, sin nota a medias); transitorio → la puerta sube el error entero (la fila se reintenta)
N1="$(q "select count(*) from crm.actividades where lead_id='$L8' and metadata->>'evento'='reingreso'")"
psql "$PG" -q -v ON_ERROR_STOP=1 -c "create or replace function public.d4_ensayo_reingreso_falla() returns trigger language plpgsql as \$f\$ begin if new.lead_id = '$L8' and new.metadata->>'evento' = 'reingreso' then raise exception 'ensayo D-4: reingreso caído' using errcode = 'P0409'; end if; return new; end \$f\$; create trigger zzz_d4_ensayo before insert on crm.actividades for each row execute function public.d4_ensayo_reingreso_falla();" 2>&1 | grep ERROR
R="$(puerta "$(fila 9${RUN}92 "\"$D8\"" FALLA 22)")"
[[ "$(j "$R" resultado)" == "ya_cliente" && "$(j "$R" lead_id)" == "$L8" && "$(jj "$R" reingreso ok)" == "False" && "$(jj "$R" reingreso error)" == P0409* && "$(q "select count(*) from crm.actividades where lead_id='$L8' and metadata->>'evento'='reingreso'")" == "$N1" && "$(q "select count(*) from crm.leads where telefono='+519${RUN}92'")" == "0" ]] && ok "ON · el reingreso falla de forma DEFINITIVA (P0409) → ya_cliente con reingreso.ok=false y el error; sin nota a medias ni lead nuevo" || rojo "[D-4] reingreso definitivo: $(echo "$R" | head -c 220)"
psql "$PG" -q -v ON_ERROR_STOP=1 -c "create or replace function public.d4_ensayo_reingreso_falla() returns trigger language plpgsql as \$f\$ begin if new.lead_id = '$L8' and new.metadata->>'evento' = 'reingreso' then raise exception 'ensayo D-4: candado' using errcode = '55P03'; end if; return new; end \$f\$;" 2>&1 | grep ERROR
R="$(puerta "$(fila 9${RUN}93 "\"$D8\"" TRANS 23)")"
echo "$R" | grep -q "55P03" && ! echo "$R" | grep -q '"resultado"' && [[ "$(q "select count(*) from crm.leads where telefono='+519${RUN}93'")" == "0" ]] && ok "ON · el reingreso falla de forma TRANSITORIA (55P03) → la puerta sube el error entero (el edge lo reintenta), nada a medias" || rojo "[D-4] reingreso transitorio: $(echo "$R" | head -c 200)"
psql "$PG" -q -c "drop trigger if exists zzz_d4_ensayo on crm.actividades; drop function if exists public.d4_ensayo_reingreso_falla();" 2>&1 | grep ERROR
# DNI nuevo con ON: nace sin identidad (b1: la identidad nace al convertir/dar de alta); DNI de una persona reconocida SIN lead: nace ENLAZADO
R="$(puerta "$(fila 9${RUN}82 "\"6${RUN}2\"" NUEVA 12)")"; L12="$(j "$R" lead_id)"
[[ "$(j "$R" resultado)" == "importado" && "$(q "select inversionista_id is null from crm.leads where id='$L12'")" == "t" ]] && ok "ON · DNI nuevo → importado, sin identidad todavía (regla de b1, como hoy)" || rojo "[D-4] ON DNI nuevo: $(echo "$R" | head -c 160) enlace=$(q "select inversionista_id from crm.leads where id='$L12'")"
D13="6${RUN}6"; P13="$(persona "$D13")"; R="$(puerta "$(fila 9${RUN}86 "\"$D13\"" RECON 16)")"; L13="$(j "$R" lead_id)"
[[ -n "$P13" && "$(j "$R" resultado)" == "importado" && "$(q "select inversionista_id from crm.leads where id='$L13'")" == "$P13" ]] && ok "ON · DNI de una persona reconocida sin lead → importado y nace ENLAZADO a ella (trigger de nacimiento, como hoy)" || rojo "[D-4] ON reconocida sin lead: $(echo "$R" | head -c 160) enlace=$(q "select inversionista_id from crm.leads where id='$L13'")"
R="$(puerta "$(fila 9${RUN}87 "\"$D13\"" RECON2 17)")"; [[ "$(j "$R" resultado)" == "ya_cliente" && "$(j "$R" lead_id)" == "$L13" && "$(jj "$R" reingreso ok)" == "True" ]] && ok "ON · la misma persona otra vez → ya_cliente con reingreso en el lead que acaba de nacer" || rojo "[D-4] ON segunda vez: $(echo "$R" | head -c 200)"
# (v3) persona con FICHA de cliente y sin lead: ya_cliente sin lead_id y sin reingreso (segunda rama del trigger zz)
D20="6${RUN}7"; P20="$(persona "$D20")"; PF20="$(uuid)"
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$PF20') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$PF20','D4 CLIENTE P20 r$RUN','cliente','DNI','$D20','d4p20$RUN@x.pe','$V',true); update crm.inversionistas set perfil_id='$PF20' where id='$P20'; commit;" 2>&1 | grep ERROR
[[ -n "$P20" && "$(q "select perfil_id from crm.inversionistas where id='$P20'")" == "$PF20" && "$(q "select count(*) from private.leads_de_personas(array['$P20'::uuid])")" == "0" ]] && ok "fixture: persona P20 verificada con ficha de cliente y SIN lead" || rojo "fixture P20"
R="$(puerta "$(fila 9${RUN}94 "\"$D20\"" PERFIL 24)")"; RD="$(directo 9${RUN}94 "'$D20'" PERFIL)"
[[ "$(j "$R" resultado)" == "ya_cliente" && -z "$(j "$R" lead_id)" && -z "$(j "$R" reingreso)" && "$(jj "$R" veredicto via)" == "identidad" ]] && echo "$RD" | grep -q "P0481" && [[ "$(q "select count(*) from crm.leads where telefono='+519${RUN}94'")" == "0" ]] && ok "ON · persona con ficha de cliente y sin lead → ya_cliente SIN lead_id ni reingreso (nada donde anotar) = INSERT directo P0481; no nace lead" || rojo "[D-4] ON ficha sin lead: $(echo "$R" | head -c 220) | $(echo "$RD" | grep ERROR | head -1 | cut -c1-80)"
# (v3) persona EN CONVERSIÓN (reserva por persona viva, D-10): la fila que llega durante la conversión va al lead reservado
D21="6${RUN}1"; P21="$(persona "$D21")"; L21="$(uuid)"; lead_de "$L21" 9${RUN}95 CONV null "'$V'"   # SIN documento, ni enlace, ni puente: solo la reserva une L21 con P21
R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -c "begin; set local role authenticated; select set_config('request.jwt.claims','{\"sub\":\"$V\",\"role\":\"authenticated\"}',true); select crm.reservar_conversion_lead('$L21','DNI','$D21','{\"correo\":\"d4c$RUN@x.pe\"}'::jsonb); commit;" 2>&1)"
[[ "$(q "select count(*) from crm.conversion_reservas where lead_id='$L21' and inversionista_id='$P21' and expira_en > now()")" == "1" && "$(q "select count(*) from private.leads_de_personas(array['$P21'::uuid])")" == "0" ]] && ok "fixture: L21 (de V, sin documento) reservado para conversión POR PERSONA para P21; leads_de_personas(P21) vacío ⇒ solo la rama de la reserva puede reconocerla" || rojo "reserva L21: $(echo "$R" | head -c 200) · leads_de_personas=$(q "select count(*) from private.leads_de_personas(array['$P21'::uuid])")"
R="$(puerta "$(fila 9${RUN}96 "\"$D21\"" CONV2 26)")"
[[ "$(j "$R" resultado)" == "ya_cliente" && "$(j "$R" lead_id)" == "$L21" && "$(jj "$R" reingreso ok)" == "True" && "$(q "select count(*) from crm.actividades where lead_id='$L21' and metadata->>'evento'='reingreso' and metadata->'datos'->>'fila'='26'")" == "1" && "$(q "select count(*) from crm.leads where telefono='+519${RUN}96'")" == "0" ]] && ok "ON · persona EN CONVERSIÓN (solo la reserva la une al lead) → ya_cliente con lead_id = el lead reservado y el reingreso anotado ahí; no nace otro lead" || rojo "[D-4] ON en conversión: $(echo "$R" | head -c 220)"

echo "== (4) Orden de candados: documento → persona → contactos; la puerta espera detrás del candado de contacto =="
psql "$PG" -q -c "begin; select private.bloquear_contactos_lead(array['+519${RUN}83'], null); select pg_sleep(4); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1; T0=$(date +%s)
R="$(puerta "$(fila 9${RUN}83 null LOCK 13)")"; T1=$(date +%s)
[[ "$(j "$R" resultado)" == "importado" && $((T1-T0)) -ge 2 ]] && ok "con el teléfono retenido por otra sesión, la puerta esperó $((T1-T0)) s y luego importó (el candado de contacto lo toma el trigger 00 del INSERT, como en el front y en el INSERT directo)" || rojo "candado de contacto: $((T1-T0)) s $(echo "$R" | head -c 160)"
wait $BG 2>/dev/null
psql "$PG" -q -c "begin; select private.identidad_bloquear_documento('DNI','6${RUN}4'); select pg_sleep(4); commit;" >/dev/null 2>&1 &
BG=$!; sleep 1; T0=$(date +%s)
R="$(puerta "$(fila 9${RUN}84 "\"6${RUN}4\"" DOC 14)")"; T1=$(date +%s)
[[ "$(j "$R" resultado)" == "importado" && $((T1-T0)) -ge 2 ]] && ok "ON · con el DOCUMENTO retenido (como la reserva de conversión), la puerta esperó $((T1-T0)) s (documento antes que contactos)" || rojo "candado documental: $((T1-T0)) s $(echo "$R" | head -c 160)"
wait $BG 2>/dev/null
flag false
R="$(puerta "$(fila 9${RUN}85 "\"6${RUN}5\"" OFFLOCK 15)")"; [[ "$(j "$R" resultado)" == "importado" && "$(q "select inversionista_id is null from crm.leads where id='$(j "$R" lead_id)'")" == "t" ]] && ok "OFF · DNI nuevo → importado SIN identidad (los candados de identidad no toman nada; paridad con hoy)" || rojo "OFF libre: $(echo "$R" | head -c 160)"

echo "== Limpieza =="
sys "update crm.leads set activo=false where telefono like '+519${RUN}%' and nombre_completo like 'D4 %'" >/dev/null
sys "update public.perfiles set activo=false where id in ('$PF3','${PF20:-$PF3}')" >/dev/null
psql "$PG" -q -c "drop trigger if exists zzz_d4_ensayo on crm.actividades; drop function if exists public.d4_ensayo_reingreso_falla();" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" -eq 0 ]]; then echo "ORÁCULO D-4: TODO VERDE (RUN=$RUN)"; else echo "ORÁCULO D-4: $ROJO ROJOS (RUN=$RUN)"; exit 1; fi
