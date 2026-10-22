#!/usr/bin/env bash
# DERIVAS del bloque 2.10 — la migración (y su reversa) se niegan si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una DERIVA rompe el catálogo ANTES
# (y después del 2.11 y del 2.16, que van delante): lo que se prueba aquí es el PREFLIGHT. La migración crea tres piezas y parchea por
# ancla única la puerta de conversión y los dos núcleos del contexto de la persona: sin preflight, un cambio hecho a mano en ellas (o en
# lo que las llama o decide su efecto, en las restricciones o en los trinquetes que barre), u otro objeto que las nombrara, se pisaría
# o se daría por bueno sin que nadie lo viera. Con cada deriva la migración tiene que ABORTAR en su preflight —con el mensaje que le
# corresponde, no con cualquier error— y dejar la puerta, los núcleos, las piezas (ausentes) y lo que las rodea EXACTAMENTE como estaban.
#
# El paso 0 es el control: sin deriva, la migración entra. Después, los MUTANTES DEL PREFLIGHT: MP1, sin el inventario de los
# trinquetes en el preflight, un trinquete de más aborta igual en el POSTFLIGHT (dos capas); MP1b, sin el inventario en el preflight NI
# en el postflight, el trinquete de más se cuela (la migración entra: muere); MP2, sin la búsqueda de llamadores en el preflight, otro
# llamador aborta igual en el POSTFLIGHT (dos capas); MP3, sin ninguna de las dos, el llamador se cuela.
#
# Al final, las DERIVAS DE LA REVERSA: previos → aplicar → un cambio posterior → la reversa tiene que abortar sin rastro (y el control:
# sin cambio, entra y devuelve la puerta y los núcleos de antes y borra las piezas). Y un MUTANTE DE LA REVERSA, sin su comprobación de
# la huella de la puerta: RM1, una puerta cambiada después se «revierte» igual y el cambio ajeno se cuela (el mutante muere).
#
# El cambio de dueño solo lo puede hacer un superusuario: esas derivas corren enteras con EJECUTAR_SQL_ADMIN (el mismo ejecutor como
# supabase_admin). La deriva del trabajo programado escribe en la tabla `cron.job` del laboratorio (sin la extensión) con un jobid
# explícito: `cron.schedule` gastaría la secuencia, que el rollback no devuelve.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo en transacciones que terminan en rollback:
#   EJECUTAR_SQL="<comando que ejecuta un .sql en el banco>" EJECUTAR_SQL_ADMIN="<el mismo, como supabase_admin>" \
#     DIR_ENSAYO=<carpeta> bash supabase/scripts/conversion-cliente-antiguo/derivas.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${EJECUTAR_SQL_ADMIN:?EJECUTAR_SQL_ADMIN: el mismo ejecutor del laboratorio como supabase_admin (para las derivas «cambio de dueño»)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"

DIR=supabase/scripts/conversion-cliente-antiguo
MIG="$(ls supabase/migrations/*_crm_conversion_cliente_antiguo_misma_ficha.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_conversion_cliente_antiguo_misma_ficha.sql"; exit 1; }
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1

P='crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)'
E='private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'
L='private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)'
A='private.conversion_absorber_cliente_antiguo(uuid,uuid,text,uuid,uuid)'
H='private.lead_historia_de_persona(uuid,uuid)'

ejecuta() { # ejecuta <ejecutor> <archivo.sql> → <archivo>.salida.txt (stdin cerrado: el ejecutor usa `docker exec -i`)
  local codigo
  # shellcheck disable=SC2086  # el ejecutor es un comando con sus argumentos
  $1 "$2" > "${2%.sql}.salida.txt" 2>&1 < /dev/null
  codigo=$?
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($2). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}
veredicto() { grep -Eo '(DERIVA|REVERSA CON DERIVA) (VERDE|ROJO)' "$1" | head -n 1 | grep -Eo '(VERDE|ROJO)$'; }
aborto() { grep -m 1 -E '^la (migración|reversa) (ABORTÓ|NO abortó)' "$1" | cut -c1-230; }

fallos=0
n=0

echo "0. Control: sin deriva, la migración entra (tras el 2.11 y el 2.16)"
: > "$TMP/d0.deriva.sql"
node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d0.deriva.sql" > "$TMP/d0.sql" || exit 1
ejecuta "$EJECUTAR_SQL" "$TMP/d0.sql"
if [[ "$(veredicto "$TMP/d0.salida.txt")" == "VERDE" ]] && grep -q '^la migración NO abortó' "$TMP/d0.salida.txt"; then
  echo "  ✓ control → $(aborto "$TMP/d0.salida.txt")"
else
  echo "  ✗ control → la migración no entró sin deriva: $(grep -m 1 -E 'ERROR|^la migración' "$TMP/d0.salida.txt" | cut -c1-230)"
  fallos=$((fallos + 1))
fi

deriva() { # deriva <nombre> <sentencia(s) SQL> <texto del preflight que debe abortar> [admin]
  local salida ejecutor="$EJECUTAR_SQL"
  n=$((n + 1))
  salida="$TMP/d$n.salida.txt"
  [[ "${4:-}" == "admin" ]] && ejecutor="$EJECUTAR_SQL_ADMIN"
  echo "$n. Deriva: $1"
  printf '%s\n' "$2" > "$TMP/d$n.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d$n.deriva.sql" --espera "$3" > "$TMP/d$n.sql" || exit 1
  ejecuta "$ejecutor" "$TMP/d$n.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"; fallos=$((fallos + 1))
  elif [[ "$(veredicto "$salida")" == "VERDE" ]]; then
    echo "  ✓ el preflight se negó y no dejó rastro → $(aborto "$salida")"
  else
    echo "  ✗ LA MIGRACIÓN NO SE NEGÓ COMO DEBÍA → $(aborto "$salida")"; fallos=$((fallos + 1))
  fi
}
cambia_cuerpo() { # cambia_cuerpo <firma> <texto que aparece en un COMENTARIO del cuerpo> → SQL que recrea la función con ese texto + «.»
  printf "do \$d\$ begin execute replace(pg_get_functiondef('%s'::regprocedure), \$t\$%s\$t\$, \$t\$%s.\$t\$); end \$d\$;" "$1" "$2" "$2"
}
otro_set() { # otro_set <firma> → SQL que le añade un SET (cambia su definición)
  printf "alter function %s set statement_timeout = '30s';" "$1"
}

APLICADA='esta migración ya está aplicada'
PIEZA_NOMBRADA='otro posible llamador de las piezas nuevas antes de que existan'
P_CUERPO='crm.preparar_persona_lead_inversion_fn no es la auditada'
P_FICHA='la ficha de crm.preparar_persona_lead_inversion_fn no es la auditada'
P_COMENTARIO='crm.preparar_persona_lead_inversion_fn ya tiene comentario'
E_CUERPO='private.inversion_persona_contexto_para no es la auditada'
E_FICHA='la ficha de private.inversion_persona_contexto_para no es la auditada'
E_COMENTARIO='el comentario de private.inversion_persona_contexto_para no es el auditado'
L_CUERPO='private.inversion_contexto_lectura_para no es la auditada'
L_FICHA='la ficha de private.inversion_contexto_lectura_para no es la auditada'
L_COMENTARIO='el comentario de private.inversion_contexto_lectura_para no es el auditado'
DEPENDENCIAS='cambió algo que llama a las tres funciones o decide su efecto'
LLAMADORES='otro posible llamador de la puerta o de los núcleos'
RESTRICCION='cambió o falta una restricción de la que depende la regla'
INDICE='cambió o falta un índice único del que depende la regla'
RLS='el puente persona-lead o el libro de operaciones ya no es como se auditó'
TRINQUETES='los private.assert_*() que barre la migración no son los auditados'
PREMISAS='cambió o falta una premisa del cierre o del perfil'

# Ya aplicada: la migración entera; una pieza con su nombre; una función (o un cron.job) que ya nombra una pieza antes de existir.
deriva "la migración ya estaba aplicada (reaplicar se niega)" "-- @@MIGRACION@@" "$APLICADA"
deriva "ya existía una función con el nombre de la pieza de historia (otra firma)" \
  "create function private.lead_historia_de_persona(p uuid) returns boolean language sql stable set search_path = '' as \$f\$ select false \$f\$;" "$APLICADA"
deriva "otra función ya nombraba la pieza de absorción antes de existir" \
  "create function private.ensayo_2_10_prematuro() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin return private.conversion_absorber_cliente_antiguo(null, null, null, null, null); end \$f\$;" \
  "$PIEZA_NOMBRADA"
deriva "un trabajo programado (cron.job.command) ya nombraba la pieza de historia" \
  "insert into cron.job (jobid, jobname, schedule, command) values (9210001, 'ensayo-2-10-prematuro', '0 3 * * *', 'select private.lead_historia_de_persona(null, null)');" \
  "$PIEZA_NOMBRADA"
# La puerta: otro cuerpo; otro SET; INVOKER; su ACL; su dueño; un comentario.
deriva "la puerta tenía otro cuerpo" "$(cambia_cuerpo "$P" '-- La identidad no se corrige al invertir. Esa operación tiene su propia puerta.')" "$P_CUERPO"
deriva "la puerta traía otro SET" "$(otro_set "$P")" "$P_CUERPO"
deriva "la puerta había pasado a security invoker" "alter function $P security invoker;" "$P_CUERPO"
deriva "anon ya tenía EXECUTE sobre la puerta" "grant execute on function $P to anon;" "$P_FICHA"
deriva "authenticated había perdido EXECUTE sobre la puerta" "revoke execute on function $P from authenticated;" "$P_FICHA"
deriva "la puerta había cambiado de dueño (lo hace un superusuario)" "alter function $P owner to supabase_admin;" "$P_FICHA" admin
deriva "la puerta ya tenía un comentario" "comment on function $P is 'comentario ajeno';" "$P_COMENTARIO"
# El núcleo de escritura: otro cuerpo; otro SET; su ACL; su dueño; su comentario.
deriva "el núcleo de escritura tenía otro cuerpo" "$(cambia_cuerpo "$E" '-- NOWAIT mantiene el orden de la corrección/fusión y evita esperar una reasignación que ya tomó el lead.')" "$E_CUERPO"
deriva "el núcleo de escritura traía otro SET" "$(otro_set "$E")" "$E_CUERPO"
deriva "authenticated ya tenía EXECUTE sobre el núcleo de escritura" "grant execute on function $E to authenticated;" "$E_FICHA"
deriva "el núcleo de escritura había cambiado de dueño (lo hace un superusuario)" "alter function $E owner to supabase_admin;" "$E_FICHA" admin
deriva "el núcleo de escritura traía otro comentario" "comment on function $E is 'comentario ajeno';" "$E_COMENTARIO"
# El núcleo de lectura: otro cuerpo; otro SET; su ACL; su comentario.
deriva "el núcleo de lectura tenía otro cuerpo" "$(cambia_cuerpo "$L" '-- NOWAIT mantiene el orden de la corrección/fusión y evita esperar una reasignación que ya tomó el lead.')" "$L_CUERPO"
deriva "el núcleo de lectura traía otro SET" "$(otro_set "$L")" "$L_CUERPO"
deriva "service_role ya tenía EXECUTE sobre el núcleo de lectura" "grant execute on function $L to service_role;" "$L_FICHA"
deriva "el núcleo de lectura traía otro comentario" "comment on function $L is 'comentario ajeno';" "$L_COMENTARIO"
# Lo que llama a las tres o decide su efecto (las 43 de la lista): otro cuerpo, otro SET, un GRANT.
deriva "private.inversionista_resolver traía otro SET" "$(otro_set 'private.inversionista_resolver(text,text,boolean,text)')" "$DEPENDENCIAS"
deriva "private.leads_de_personas traía otro SET" "$(otro_set 'private.leads_de_personas(uuid[])')" "$DEPENDENCIAS"
deriva "private.leads_de_identidades traía otro SET" "$(otro_set 'private.leads_de_identidades(uuid[])')" "$DEPENDENCIAS"
deriva "la pieza del 2.8 tenía otro cuerpo" "$(cambia_cuerpo 'private.juicio_cliente_convertido(text,text,text,uuid)' '-- 2. Si ningún teléfono casa, el DNI (D-27), con la misma prioridad')" "$DEPENDENCIAS"
deriva "el puente de identidad traía otro SET" "$(otro_set 'private.trg_leads_zz_puente_identidad()')" "$DEPENDENCIAS"
deriva "el enlace de identidad traía otro SET" "$(otro_set 'private.trg_leads_zz_enlaza_identidad()')" "$DEPENDENCIAS"
deriva "private.leads_protege_inversionista_id traía otro SET" "$(otro_set 'private.leads_protege_inversionista_id()')" "$DEPENDENCIAS"
deriva "private.inversion_persona_contexto (envoltorio) traía otro SET" "$(otro_set 'private.inversion_persona_contexto(uuid,uuid)')" "$DEPENDENCIAS"
deriva "private.inversion_contexto_lectura (envoltorio) traía otro SET" "$(otro_set 'private.inversion_contexto_lectura(uuid,uuid)')" "$DEPENDENCIAS"
deriva "private.inversion_preparar_nucleo traía otro SET" "$(otro_set 'private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)')" "$DEPENDENCIAS"
deriva "crm.confirmar_inversion_revisada_fn traía otro SET" "$(otro_set 'crm.confirmar_inversion_revisada_fn(uuid,integer)')" "$DEPENDENCIAS"
deriva "crm.contexto_conversion_inversion_fn traía otro SET" "$(otro_set 'crm.contexto_conversion_inversion_fn(uuid,uuid)')" "$DEPENDENCIAS"
deriva "la puerta de enlace de Gerencia traía otro SET" "$(otro_set 'crm.enlazar_lead_inversionista_fn(uuid,uuid,text)')" "$DEPENDENCIAS"
deriva "private.trg_gestion_lead_serializada traía otro SET" "$(otro_set 'private.trg_gestion_lead_serializada()')" "$DEPENDENCIAS"
deriva "private.identidad_bloquear_documento traía otro SET (el candado del documento)" "$(otro_set 'private.identidad_bloquear_documento(text,text)')" "$DEPENDENCIAS"
deriva "private.juicio_persona traía otro SET" "$(otro_set 'private.juicio_persona(uuid,uuid)')" "$DEPENDENCIAS"
deriva "private.inversionista_operaciones_append_only traía otro SET" "$(otro_set 'private.inversionista_operaciones_append_only()')" "$DEPENDENCIAS"
deriva "anon ya tenía EXECUTE sobre private.rol_crm" "grant execute on function private.rol_crm(uuid) to anon;" "$DEPENDENCIAS"
deriva "crm.corregir_solicitud_inversion_fn traía otro SET" "$(otro_set 'crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)')" "$DEPENDENCIAS"
deriva "crm.buscar_cliente_existente_fn traía otro SET" "$(otro_set 'crm.buscar_cliente_existente_fn(text,text,text,uuid)')" "$DEPENDENCIAS"
# Ronda 2 (P3-4 del auditor): lo que decide el RETIRO del antiguo y el CIERRE que se completa (D-83).
deriva "private.leads_before_update tenía otro cuerpo (decide si el antiguo se puede retirar)" "$(cambia_cuerpo 'private.leads_before_update()' '-- Columnas inmutables: restaurar siempre desde OLD.')" "$DEPENDENCIAS"
deriva "authenticated ya tenía EXECUTE sobre private.leads_before_update" "grant execute on function private.leads_before_update() to authenticated;" "$DEPENDENCIAS"
deriva "private.trg_leads_tenencia_desde traía otro SET (la tenencia del retirado)" "$(otro_set 'private.trg_leads_tenencia_desde()')" "$DEPENDENCIAS"
deriva "private.documento_es_de_identidad traía otro SET (decide si el cierre se completa)" "$(otro_set 'private.documento_es_de_identidad(uuid,text,text)')" "$DEPENDENCIAS"
deriva "private.trg_cierres_externos_inmutables traía otro SET (protege el asesor de origen del cierre)" "$(otro_set 'private.trg_cierres_externos_inmutables()')" "$DEPENDENCIAS"
deriva "private.f4_fuente_inmutable traía otro SET" "$(otro_set 'private.f4_fuente_inmutable()')" "$DEPENDENCIAS"
# Reselle C1 (13/10): la ficha de Cartera que lee quien convierte (D-88) se fija por la huella de producción del 13/10 (9d981c6c…, con las dos claves del analista de venta).
deriva "la ficha de Cartera (crm.inversionista_ficha_fn) traía otro SET" "$(otro_set 'crm.inversionista_ficha_fn(uuid,integer,integer)')" "$DEPENDENCIAS"
deriva "la ficha de Cartera (crm.inversionista_ficha_fn) tenía otro cuerpo" "$(cambia_cuerpo 'crm.inversionista_ficha_fn(uuid,integer,integer)' '-- Fase 6 de Facturación (10/10/2026): quién VENDIÓ')" "$DEPENDENCIAS"
# Ronda 4 (auditor r2): el disparador de crm.inversionistas que reacciona al enlazar el perfil (D-87), y las PREMISAS de D-83/D-85 y D-86/D-87.
deriva "private.inversionista_fusion_destino_activo traía otro SET (reacciona al enlazar el perfil)" "$(otro_set 'private.inversionista_fusion_destino_activo()')" "$DEPENDENCIAS"
deriva "el índice de un cierre inicial por lead era otro" \
  "drop index crm.cierres_externos_inicial_por_lead_uidx; create unique index cierres_externos_inicial_por_lead_uidx on crm.cierres_externos (lead_id, es_cierre_inicial);" "$PREMISAS"
deriva "el documento del cierre admitía NULL" "alter table crm.cierres_externos alter column documento drop not null;" "$PREMISAS"
deriva "el tipo de documento del cierre admitía NULL" "alter table crm.cierres_externos alter column documento_tipo drop not null;" "$PREMISAS"
deriva "el CHECK del formato del documento del cierre era otro (y sin validar)" \
  "alter table crm.cierres_externos drop constraint cierres_externos_documento_formato, add constraint cierres_externos_documento_formato check (documento ~ '^[A-Z0-9]{1,12}\$') not valid;" "$PREMISAS"
deriva "crm.inversiones.inversionista_id admitía NULL" "alter table crm.inversiones alter column inversionista_id drop not null;" "$PREMISAS"
deriva "el disparador de inmutables del cierre estaba deshabilitado" "alter table crm.cierres_externos disable trigger trg_cierres_externos_00_inmutables;" "$PREMISAS"
deriva "faltaba el índice único del perfil de la persona" "drop index crm.inversionistas_perfil_uidx;" "$PREMISAS"
deriva "la clave foránea del perfil de la persona era otra" \
  "alter table crm.inversionistas drop constraint inversionistas_perfil_id_fkey, add constraint inversionistas_perfil_id_fkey foreign key (perfil_id) references public.perfiles(id) on delete set null not valid;" "$PREMISAS"
deriva "el disparador de leads_before_update estaba deshabilitado (ronda 6)" "alter table crm.leads disable trigger trg_leads_before_update;" "$PREMISAS"
deriva "el disparador de tenencia estaba deshabilitado (ronda 6)" "alter table crm.leads disable trigger trg_leads_zzz_tenencia_desde;" "$PREMISAS"
deriva "había un disparador de más en crm.inversionistas" \
  "create trigger zz_ensayo_2_10 before update on crm.inversionistas for each row execute function private.set_actualizado_en_crm();" "$PREMISAS"
# Otro LLAMADOR de la puerta o de los núcleos (el cambio lo alcanzaría): por su cuerpo, en minúsculas y en MAYÚSCULAS; por pg_depend
# (vista, función SQL BEGIN ATOMIC); un trabajo programado; un comentario.
LLAMADOR_PLPGSQL="create function private.ensayo_2_10_llamador() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin return crm.preparar_persona_lead_inversion_fn(null, null, null, null); end \$f\$;"
deriva "otra función PL/pgSQL llama a la puerta" "$LLAMADOR_PLPGSQL" "$LLAMADORES"
deriva "otra función la llama en MAYÚSCULAS (CRM.PREPARAR_PERSONA_LEAD_INVERSION_FN)" \
  "create function private.ensayo_2_10_llamador_mayusculas() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin return CRM.PREPARAR_PERSONA_LEAD_INVERSION_FN(null, null, null, null); end \$f\$;" \
  "$LLAMADORES"
deriva "una vista usa el núcleo de lectura" "create view private.ensayo_2_10_vista as select private.inversion_contexto_lectura_para(null, null, null, null) as r;" "$LLAMADORES"
deriva "una función SQL BEGIN ATOMIC usa el núcleo de escritura" \
  "create function private.ensayo_2_10_atomica() returns jsonb language sql volatile begin atomic select private.inversion_persona_contexto_para(null, null, null, null); end;" \
  "$LLAMADORES"
deriva "un trabajo programado (cron.job.command) nombra a la puerta" \
  "insert into cron.job (jobid, jobname, schedule, command) values (9210002, 'ensayo-2-10-llamador', '0 3 * * *', 'select crm.preparar_persona_lead_inversion_fn(null, null, null, null)');" \
  "$LLAMADORES"
deriva "otra función nombra al núcleo de escritura en un comentario (posible llamador: bloquea de forma conservadora)" \
  "create function private.ensayo_2_10_comenta() returns void language sql set search_path = '' as \$f\$ select null::void -- ver inversion_persona_contexto_para
\$f\$;" \
  "$LLAMADORES"
# Las premisas de la regla: los CHECK, los índices únicos y la RLS.
deriva "el CHECK leads_dni_check era otro (y sin validar)" \
  "alter table crm.leads drop constraint leads_dni_check, add constraint leads_dni_check check (dni is null or dni ~ '^[0-9]{8,9}\$') not valid;" \
  "$RESTRICCION"
deriva "el CHECK del rol del puente admitía otro rol" \
  "alter table crm.inversionista_leads drop constraint inversionista_leads_rol_check, add constraint inversionista_leads_rol_check check (rol in ('canonico', 'historico', 'otro'));" \
  "$RESTRICCION"
deriva "el CHECK del tipo del libro de operaciones era otro" \
  "alter table crm.inversionista_operaciones drop constraint inversionista_operaciones_tipo_check, add constraint inversionista_operaciones_tipo_check check (tipo in ('correccion', 'enlace', 'otro'));" \
  "$RESTRICCION"
deriva "faltaba el puente único por persona canónica" "drop index crm.inversionista_leads_canonico_uidx;" "$INDICE"
deriva "la RLS del puente estaba apagada" "alter table crm.inversionista_leads disable row level security;" "$RLS"
deriva "authenticated tenía SELECT sobre el libro de operaciones" "grant select on crm.inversionista_operaciones to authenticated;" "$RLS"
# Los trinquetes que barre: uno con otro cuerpo; uno de más.
deriva "un trinquete tenía otro cuerpo" "$(cambia_cuerpo 'private.assert_tareas_pendientes_base()' 'La policy de lectura de tareas, tal cual se auditó el 19/09/2026')" "$TRINQUETES"
deriva "había un trinquete de más" "create function private.assert_ensayo_2_10() returns text language sql stable set search_path = '' as \$f\$ select 'ok'::text \$f\$;" "$TRINQUETES"

# ── MUTANTES DEL PREFLIGHT ──────────────────────────────────────────────────────────────────────────────────────────────
mutar_migracion() { # mutar_migracion <trinquetes|trinquetes-ambos|llamadores-preflight|llamadores-ambos> <destino>
  python3 -I - "$MIG" "$2" "$1" <<'PY'
import sys
origen, destino, que = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
def quitar(sql, ini, fin, veces_ini=1):
    if sql.count(ini) != veces_ini:
        sys.exit('MUTANTE DEL PREFLIGHT NO APLICABLE (%s: %d)' % (ini.strip()[:60], sql.count(ini)))
    i = sql.index(ini); j = sql.index(fin, i)
    return sql[:i] + sql[j:]
LL = "  select string_agg(x.f, ', ' order by x.f) into v_mal\n  from (select p.oid::regprocedure::text as f\n          from pg_proc p\n         where (strpos(lower(p.prosrc), 'preparar_persona_lead_inversion_fn') > 0 and p.oid <> v_puerta)"
if que in ('trinquetes', 'trinquetes-ambos'):
    sql = quitar(sql, "  -- El inventario y las DEFINICIONES de los trinquetes que se barren abajo",
                 "  -- Fotos para el postflight")
    if que == 'trinquetes-ambos':
        # Queda UNA comprobación del inventario (la del postflight): se quita entera, hasta la foto de los trinquetes.
        sql = quitar(sql, "  -- El inventario de los private.assert_*() (los 29 que no re-sella el 2.16)",
                     "  for r in\n", 1)
elif que in ('llamadores-preflight', 'llamadores-ambos'):
    sql = quitar(sql, "  -- Nadie más nombra a las tres (el cambio lo alcanzaría)",
                 "  -- Las premisas de la regla: el DNI de ocho dígitos")
    if que == 'llamadores-ambos':
        # Queda UNA búsqueda de llamadores de las tres (la del postflight): se quita entera, hasta las restricciones.
        sql = quitar(sql, LL, "  -- Las restricciones, los índices y la RLS de las que depende la regla, intactos.", 1)
else:
    sys.exit('mutante desconocido')
open(destino, 'w', encoding='utf-8').write(sql)
PY
}
mutante_preflight() { # mutante_preflight <id> <descripción> <qué quitar> <deriva SQL> <espera | vacío = debe ENTRAR>
  echo "$1. $2"
  if ! mutar_migracion "$3" "$TMP/$1.migracion.sql"; then
    echo "  ✗ no se pudo construir $1"; fallos=$((fallos + 1)); return
  fi
  printf '%s\n' "$4" > "$TMP/$1.deriva.sql"
  if [[ -n "$5" ]]; then
    node "$DIR/armar-ensayo.mjs" --migracion "$TMP/$1.migracion.sql" --deriva "$TMP/$1.deriva.sql" --espera "$5" > "$TMP/$1.sql" || exit 1
  else
    node "$DIR/armar-ensayo.mjs" --migracion "$TMP/$1.migracion.sql" --deriva "$TMP/$1.deriva.sql" --espera 'NO DEBE ABORTAR' > "$TMP/$1.sql" || exit 1
  fi
  ejecuta "$EJECUTAR_SQL" "$TMP/$1.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/$1.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/$1.salida.txt" | cut -c1-200)"; fallos=$((fallos + 1))
  elif [[ -n "$5" ]]; then
    if [[ "$(veredicto "$TMP/$1.salida.txt")" == "VERDE" ]]; then
      echo "  ✓ sin esa comprobación del preflight, la migración aborta igual en su POSTFLIGHT sin rastro → $(aborto "$TMP/$1.salida.txt")"
    else
      echo "  ✗ $1 → $(aborto "$TMP/$1.salida.txt")"; fallos=$((fallos + 1))
    fi
  elif grep -q '^la migración NO abortó' "$TMP/$1.salida.txt"; then
    echo "  ✓ el mutante muere: sin esa comprobación, la deriva se coló y la migración entró. Es ella la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/$1.salida.txt")"; fallos=$((fallos + 1))
  fi
}
TRINQUETE_DE_MAS="create function private.assert_ensayo_2_10() returns text language sql stable set search_path = '' as \$f\$ select 'ok'::text \$f\$;"
mutante_preflight MP1 "Mutante del preflight SIN el inventario de los trinquetes: un trinquete de más aborta en el POSTFLIGHT (dos capas)" trinquetes \
  "$TRINQUETE_DE_MAS" "el inventario de los private.assert_*() no es el de antes"
mutante_preflight MP1b "Mutante SIN el inventario de los trinquetes en el preflight NI en el postflight: el trinquete de más tiene que COLARSE" trinquetes-ambos \
  "$TRINQUETE_DE_MAS" ""
mutante_preflight MP2 "Mutante del preflight SIN la búsqueda de llamadores: otro llamador aborta en el POSTFLIGHT (dos capas)" llamadores-preflight \
  "$LLAMADOR_PLPGSQL" "otro objeto nombra a la puerta o a los núcleos"
mutante_preflight MP3 "Mutante SIN la búsqueda de llamadores en el preflight NI en el postflight: el llamador tiene que COLARSE" llamadores-ambos \
  "$LLAMADOR_PLPGSQL" ""

# ══ DERIVAS DE LA REVERSA ════════════════════════════════════════════════════════════════════════════════════════════════════
nr=0
reversa_deriva() { # reversa_deriva <nombre> <sentencia(s) SQL> <texto que debe abortar | vacío = control> [admin]
  local archivo salida ejecutor="$EJECUTAR_SQL"
  nr=$((nr + 1))
  archivo="$TMP/r$nr.sql"; salida="$TMP/r$nr.salida.txt"
  [[ "${4:-}" == "admin" ]] && ejecutor="$EJECUTAR_SQL_ADMIN"
  echo "R$nr. Reversa con deriva: $1"
  printf '%s\n' "$2" > "$TMP/r$nr.deriva.sql"
  if [[ -n "$3" ]]; then
    node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/r$nr.deriva.sql" --espera "$3" > "$archivo" || exit 1
  else
    node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/r$nr.deriva.sql" > "$archivo" || exit 1
  fi
  ejecuta "$ejecutor" "$archivo"
  if ! grep -q 'DERIVA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"; fallos=$((fallos + 1)); return
  fi
  if [[ "$(veredicto "$salida")" == "VERDE" ]]; then
    if [[ -n "$3" ]]; then echo "  ✓ la reversa se negó y no dejó rastro → $(aborto "$salida")"
    else echo "  ✓ control: sin deriva, la reversa entra y devuelve la puerta y los núcleos de antes y borra las piezas"; fi
  else
    echo "  ✗ LA REVERSA NO SE COMPORTÓ COMO DEBÍA → $(aborto "$salida")"; fallos=$((fallos + 1))
  fi
}
REV_P='crm.preparar_persona_lead_inversion_fn no es la que deja la migración'
REV_E='private.inversion_persona_contexto_para no es la que deja la migración'
REV_A='private.conversion_absorber_cliente_antiguo no es la que deja la migración'
REV_FICHA='la ficha de la puerta o de un núcleo no es la esperada'
REV_PIEZA_FICHA='la ficha de una pieza no es la esperada'
REV_COMENTARIO='el comentario de crm.preparar_persona_lead_inversion_fn no es el que deja la migración'
REV_PIEZA_COM='el comentario de private.lead_historia_de_persona no es el que deja la migración'
REV_INVENTARIO='el inventario de los private.assert_*() no es el que deja la migración'
REV_LLAMADOR='otro posible llamador de la puerta o de los núcleos'
REV_USA='otro objeto usa las piezas'
REV_DEPENDENCIAS='cambió algo que llama a las tres funciones o decide su efecto: revisar a mano'
REV_RESTRICCION='cambió o falta una restricción de la que depende la regla'
REV_INDICE='cambió o falta un índice único del que depende la regla'
REV_RLS='el puente persona-lead o el libro de operaciones ya no es como se auditó'
REV_PREMISAS='cambió o falta una premisa del cierre o del perfil'
CAMBIO_P="$(cambia_cuerpo "$P" '-- La identidad no se corrige al invertir. Esa operación tiene su propia puerta.')"
reversa_deriva "control (sin deriva): la reversa entra y devuelve la puerta y los núcleos de antes" "" ""
reversa_deriva "la puerta cambió después" "$CAMBIO_P" "$REV_P"
reversa_deriva "el núcleo de escritura cambió después (otro SET)" "$(otro_set "$E")" "$REV_E"
reversa_deriva "la pieza de absorción cambió después" "$(cambia_cuerpo "$A" '-- 1. Los candidatos: leads CONVERTIDOS sin persona (sin puntero y sin puente) cuyo DNI es el de la conversión, distintos del que se')" "$REV_A"
reversa_deriva "un GRANT EXECUTE a anon sobre la puerta" "grant execute on function $P to anon;" "$REV_FICHA"
reversa_deriva "la puerta cambió de dueño (lo hace un superusuario)" "alter function $P owner to supabase_admin;" "$REV_FICHA" admin
reversa_deriva "authenticated ganó EXECUTE sobre la pieza de historia" "grant execute on function $H to authenticated;" "$REV_PIEZA_FICHA"
reversa_deriva "el comentario de la puerta cambió" "comment on function $P is 'comentario ajeno';" "$REV_COMENTARIO"
reversa_deriva "el comentario de la pieza de historia cambió" "comment on function $H is 'comentario ajeno';" "$REV_PIEZA_COM"
reversa_deriva "había un trinquete de más (el inventario ya no es el que deja la migración)" \
  "create function private.assert_ensayo_2_10() returns text language sql stable set search_path = '' as \$f\$ select 'ok'::text \$f\$;" "$REV_INVENTARIO"
reversa_deriva "otra función PL/pgSQL llama a la puerta" "$LLAMADOR_PLPGSQL" "$REV_LLAMADOR"
reversa_deriva "otra función usa la pieza de historia" \
  "create function private.ensayo_2_10_usa_pieza() returns boolean language sql stable set search_path = '' as \$f\$ select private.lead_historia_de_persona(null, null) \$f\$;" "$REV_USA"
reversa_deriva "private.inversionista_resolver cambió después (una dependencia)" "$(otro_set 'private.inversionista_resolver(text,text,boolean,text)')" "$REV_DEPENDENCIAS"
reversa_deriva "private.leads_before_update cambió después (dependencia de la ronda 2)" "$(otro_set 'private.leads_before_update()')" "$REV_DEPENDENCIAS"
reversa_deriva "private.inversionista_fusion_destino_activo cambió después (dependencia de la ronda 4)" "$(otro_set 'private.inversionista_fusion_destino_activo()')" "$REV_DEPENDENCIAS"
reversa_deriva "la ficha de Cartera cambió después (dependencia resellada en C1, 13/10)" "$(otro_set 'crm.inversionista_ficha_fn(uuid,integer,integer)')" "$REV_DEPENDENCIAS"
# Ronda 6 (P2-2 de Codex r1): la reversa fija las premisas de la ronda 4 y los índices y la RLS del puente y del libro.
reversa_deriva "el índice único del perfil de la persona se quitó después" "drop index crm.inversionistas_perfil_uidx;" "$REV_PREMISAS"
reversa_deriva "el disparador de inmutables del cierre se deshabilitó después" "alter table crm.cierres_externos disable trigger trg_cierres_externos_00_inmutables;" "$REV_PREMISAS"
reversa_deriva "la clave foránea del perfil de la persona cambió después" \
  "alter table crm.inversionistas drop constraint inversionistas_perfil_id_fkey, add constraint inversionistas_perfil_id_fkey foreign key (perfil_id) references public.perfiles(id) on delete set null not valid;" "$REV_PREMISAS"
reversa_deriva "el disparador de leads_before_update se deshabilitó después" "alter table crm.leads disable trigger trg_leads_before_update;" "$REV_PREMISAS"
reversa_deriva "el puente único por persona canónica se quitó después" "drop index crm.inversionista_leads_canonico_uidx;" "$REV_INDICE"
reversa_deriva "la RLS del libro de operaciones se apagó después" "alter table crm.inversionista_operaciones disable row level security;" "$REV_RLS"
reversa_deriva "el CHECK del rol del puente cambió después" \
  "alter table crm.inversionista_leads drop constraint inversionista_leads_rol_check, add constraint inversionista_leads_rol_check check (rol in ('canonico', 'historico', 'otro'));" "$REV_RESTRICCION"

# ── MUTANTE DE LA REVERSA: sin su comprobación de la huella de la puerta ───────────────────────────────────────────────
mutar_reversa() { # mutar_reversa <destino>
  python3 -I - "$DIR/reversa.sql" "$1" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ini = "  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_puerta) is distinct from '"
fin = "  if md5(coalesce(obj_description(v_puerta, 'pg_proc'), '')) is distinct from '"
if sql.count(ini) != 2 or sql.count(fin) != 1:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (%d/%d)' % (sql.count(ini), sql.count(fin)))
i = sql.index(ini); j = sql.index(fin, i)   # la primera: la del preflight
open(destino, 'w', encoding='utf-8').write(sql[:i] + sql[j:])
PY
}
if mutar_reversa "$TMP/reversa-sin-huella-puerta.sql"; then
  echo "RM1. Mutante de la reversa SIN la huella de la puerta: una puerta cambiada después se «revierte» igual y el cambio ajeno se cuela"
  printf '%s\n' "$CAMBIO_P" > "$TMP/rm1.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm1.deriva.sql" --espera "$REV_P" \
    --reversa-archivo "$TMP/reversa-sin-huella-puerta.sql" > "$TMP/rm1.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/rm1.sql"
  if [[ "$(veredicto "$TMP/rm1.salida.txt")" == "ROJO" ]] && grep -q -E '^la reversa (NO abortó|ABORTÓ: .*(postflight|no es la de antes|aparece))' "$TMP/rm1.salida.txt"; then
    echo "  ✓ el mutante muere: sin la huella, la reversa ya no se niega por la deriva ($(aborto "$TMP/rm1.salida.txt")). Es la huella la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/rm1.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir el mutante de la reversa"; fallos=$((fallos + 1))
fi

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: el control entra; las $n derivas abortan en el preflight sin rastro; MP1 y MP2 abortan en el postflight y MP1b y MP3 mueren; las $((nr - 1)) derivas de la reversa abortan sin rastro y su control entra; RM1 muere."
  exit 0
fi
echo "DERIVAS: $fallos fallo(s) — hay defensas del preflight o de la reversa sin prueba."
exit 1
