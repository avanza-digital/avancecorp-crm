#!/usr/bin/env bash
# DERIVAS PREVIAS — la migración se niega si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una deriva rompe el
# catálogo ANTES: lo que se prueba aquí es el PREFLIGHT de la migración. `create or replace` conserva dueño y ACL, y
# reemplaza el cuerpo que encuentre: sin preflight, un cambio hecho a mano en `public.crear_contrato` (o en lo que decide la
# excepción o el autogenerado) se borraría o se daría por bueno sin que nadie lo viera. Con cada deriva la migración tiene
# que ABORTAR en su preflight —con el mensaje que le corresponde, no con cualquier error— y dejar la función, su ACL y su
# comentario EXACTAMENTE como estaban.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Sin él, un envoltorio roto daría
# «abortó» siempre. Al final van dos MUTANTES DEL PREFLIGHT: una copia de la migración sin la comparación de `is_grantable`
# tiene que dejarse colar la deriva «WITH GRANT OPTION», y una copia sin la comparación de la FICHA de los helpers tiene que
# dejarse colar «private.rol_crm IMMUTABLE» (la migración entra): así se sabe que es esa comparación, y no otra cosa, la
# que protege.
#
# Ronda 2 (C-1/C-2 de Codex, A-3/A-4 del auditor): D13–D18 cambian la FICHA de un helper sin tocar su cuerpo (IMMUTABLE,
# otro search_path, GRANT OPTION, otro dueño, INVOKER, PARALLEL SAFE); D19 quita un `assert_*`; D20 deja la base sin un
# par vendedor–cliente apto para la sonda; D21 deja a TODOS los clientes sin documento, con lo que cada llamada de la sonda
# muere ANTES de la guarda (P0409 de la identidad unificada). D20 y D21 abortan en el POSTFLIGHT (la guarda ya instalada se
# deshace con el resto): el veredicto es el mismo, «la migración se negó y la foto es idéntica».
#
# Ronda 3 (R2-1 de Codex): la sonda recorre hasta 5 candidatos. D21 pasa a ser «NINGÚN candidato concluyente» (aborta con la
# lista de los candidatos probados y su causa); D22 es la única deriva que tiene que dejar ENTRAR a la migración: solo el
# PRIMER candidato de la ordenación pierde el documento, la sonda lo descarta, concluye con el segundo y el NOTICE lo dice.
# Y un tercer MUTANTE (del postflight): una copia de la migración cuya sonda no itera (`limit 1`) tiene que ABORTAR con D22.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo ocurre en transacciones que terminan en
# rollback:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/numero-contrato-servidor/derivas.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin ella van a una carpeta temporal que se
# borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/numero-contrato-servidor
MIG="$(ls supabase/migrations/*_crm_numero_contrato_servidor.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_numero_contrato_servidor.sql"; exit 1; }
if [[ -n "${DIR_ENSAYO:-}" ]]; then
  TMP="$DIR_ENSAYO"
  mkdir -p "$TMP" || exit 1
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
fi

corre() { # corre <archivo.sql> → deja la salida completa en <archivo>.salida.txt
  local codigo
  # shellcheck disable=SC2086  # EJECUTAR_SQL es un comando con sus argumentos
  $EJECUTAR_SQL "$1" > "${1%.sql}.salida.txt" 2>&1
  codigo=$?
  # 9 = el ejecutor del laboratorio comparó la base antes y después y CAMBIÓ.
  # Un ensayo no escribe: se para todo y se avisa.
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($1). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}

veredicto() { grep -Eo 'DERIVA (VERDE|ROJO)' "$1" | head -n 1; }
aborto() { grep -m 1 -E '^la migración (ABORTÓ|NO abortó)' "$1" | cut -c1-230; }

fallos=0
n=0

echo "0. Control: sin deriva, la migración entra por el mismo envoltorio"
: > "$TMP/d0.deriva.sql"
node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d0.deriva.sql" > "$TMP/d0.sql" || exit 1
corre "$TMP/d0.sql"
if [[ "$(veredicto "$TMP/d0.salida.txt")" == "DERIVA VERDE" ]] && grep -q '^la migración NO abortó' "$TMP/d0.salida.txt"; then
  echo "  ✓ control → $(aborto "$TMP/d0.salida.txt")"
else
  echo "  ✗ control → la migración no entró sin deriva: $(grep -m 1 -E 'ERROR|^la migración' "$TMP/d0.salida.txt" | cut -c1-230)"
  fallos=$((fallos + 1))
fi

deriva() { # deriva <nombre> <sentencia(s) SQL> <texto del preflight que debe abortar>
  local salida
  n=$((n + 1))
  salida="$TMP/d$n.salida.txt"
  echo "$n. Deriva: $1"
  printf '%s\n' "$2" > "$TMP/d$n.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d$n.deriva.sql" --espera "$3" > "$TMP/d$n.sql" || exit 1
  corre "$TMP/d$n.sql"
  # La marca separa «la deriva no se pudo instalar» (no se juzga) de «la migración se negó». El veredicto VERDE lo da el
  # propio ensayo: abortó con el texto esperado del preflight Y la foto (cuerpo, ACL y comentario) es idéntica a la de antes
  # de intentar la migración.
  if ! grep -q 'DERIVA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$salida")" == "DERIVA VERDE" ]]; then
    echo "  ✓ la migración se negó y no dejó rastro → $(aborto "$salida")"
  else
    echo "  ✗ LA MIGRACIÓN NO SE NEGÓ COMO DEBÍA → $(aborto "$salida")"
    fallos=$((fallos + 1))
  fi
}

CUERPO='public.crear_contrato cambió desde que se auditó'
FICHA='la ficha de public.crear_contrato no es la auditada'
COMENTARIO='el comentario de public.crear_contrato cambió'
HELPERS='cambió public.es_admin, private.es_gerencia_crm_activa, private.rol_crm, private.puede_registrar_ventas o private.siguiente_numero_contrato'

# D1 — el CUERPO ya no es el auditado (md5 de `prosrc` distinto, aunque sea por un punto en un mensaje).
deriva "public.crear_contrato tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('public.crear_contrato(jsonb,jsonb)'::regprocedure), 'Faltan los datos del contrato', 'Faltan los datos del contrato.'); end \$d\$;" \
  "$CUERPO"

# D2 y D3 — el cuerpo es el mismo pero la DEFINICIÓN no: un `SET` añadido, o INVOKER (md5 de `pg_get_functiondef` distinto).
deriva "public.crear_contrato traía otro SET además del search_path" \
  "alter function public.crear_contrato(jsonb,jsonb) set lock_timeout = '5s';" \
  "$CUERPO"
deriva "public.crear_contrato había pasado a security invoker" \
  "alter function public.crear_contrato(jsonb,jsonb) security invoker;" \
  "$CUERPO"

# D4, D5 y D6 — la ACL no es la auditada (no entra en el md5 del cuerpo): anon con EXECUTE, EXECUTE con opción de concesión,
# service_role sin EXECUTE. `create or replace` los conservaría.
deriva "anon ya tenía EXECUTE" \
  "grant execute on function public.crear_contrato(jsonb,jsonb) to anon;" \
  "$FICHA"
GRANT_OPTION="grant execute on function public.crear_contrato(jsonb,jsonb) to authenticated with grant option;"
deriva "authenticated tenía EXECUTE WITH GRANT OPTION" \
  "$GRANT_OPTION" \
  "$FICHA"
deriva "service_role había perdido EXECUTE" \
  "revoke execute on function public.crear_contrato(jsonb,jsonb) from service_role;" \
  "$FICHA"

# D7 — el comentario ya no es el auditado: el nuevo se escribiría encima sin saberlo.
deriva "public.crear_contrato traía otro comentario" \
  "comment on function public.crear_contrato(jsonb,jsonb) is 'comentario ajeno';" \
  "$COMENTARIO"

# D8–D11 — lo que decide la excepción o el autogenerado ya no es lo auditado (cuerpo de los helpers).
deriva "private.es_gerencia_crm_activa tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.es_gerencia_crm_activa()'::regprocedure), '= ''gerencia''', 'is not null'); end \$d\$;" \
  "$HELPERS"
deriva "private.rol_crm tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.rol_crm(uuid)'::regprocedure), '''gerencia'',''coordinador'',''directorio''', '''gerencia'',''coordinador'''); end \$d\$;" \
  "$HELPERS"
deriva "private.puede_registrar_ventas tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.puede_registrar_ventas()'::regprocedure), 'SIN scope de cartera', 'SIN scope de cartera.'); end \$d\$;" \
  "$HELPERS"
deriva "private.siguiente_numero_contrato tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.siguiente_numero_contrato(integer)'::regprocedure), 'Año de contrato inválido', 'Año de contrato invalido'); end \$d\$;" \
  "$HELPERS"

# D12 — la migración YA está aplicada: reaplicarla se niega (la guarda ya está; el cuerpo vigente no es el auditado).
deriva "la migración ya estaba aplicada (reaplicar se niega)" \
  "-- @@MIGRACION@@" \
  "o esta migración ya está aplicada"

# ── Ronda 2 (C-1 de Codex / A-3 del auditor): derivas que conservan el md5(prosrc) de un helper y aun así cambian lo que
#    la regla garantiza. Antes de la ronda 2 las tres primeras se colaban (medido contra la migración de la ronda 1). ──────

# D13 — `private.rol_crm(uuid)` IMMUTABLE: mismo md5(prosrc), pero una decisión de autorización que el planificador podría
# evaluar una vez y conservar.
HELPER_IMMUTABLE="alter function private.rol_crm(uuid) immutable;"
deriva "private.rol_crm(uuid) había pasado a IMMUTABLE" \
  "$HELPER_IMMUTABLE" \
  "la ficha de private.rol_crm(uuid) no es la auditada"

# D14 — otro `search_path` en un helper (proconfig distinto; el cuerpo no cambia).
deriva "private.puede_registrar_ventas() tenía otro search_path" \
  "alter function private.puede_registrar_ventas() set search_path = public;" \
  "la ficha de private.puede_registrar_ventas() no es la auditada"

# D15 — EXECUTE con OPCIÓN DE CONCESIÓN sobre un helper de `private`: misma lista de concesionarios, otra ACL.
deriva "authenticated tenía EXECUTE WITH GRANT OPTION sobre private.rol_crm(uuid)" \
  "grant execute on function private.rol_crm(uuid) to authenticated with grant option;" \
  "la ficha de private.rol_crm(uuid) no es la auditada"

# D16 — otro PROPIETARIO en un helper. `postgres` no es superusuario en el laboratorio: solo puede ceder el dueño a un rol del
# que es miembro (service_role) y que tenga CREATE sobre el esquema, así que la deriva concede ese CREATE antes (todo dentro
# del rollback). Sobre `public.es_admin` NO es ensayable aquí (`postgres` no es dueño de `public`): se hace sobre un helper
# de `private`; la comparación de dueño es la misma para los cinco.
deriva "private.siguiente_numero_contrato(integer) tenía otro propietario" \
  "grant create on schema private to service_role; alter function private.siguiente_numero_contrato(integer) owner to service_role;" \
  "la ficha de private.siguiente_numero_contrato(integer) no es la auditada"

# D17 — `public.es_admin()` SECURITY INVOKER (el caso del auditor): mismo cuerpo, otra ficha.
deriva "public.es_admin() había pasado a security invoker" \
  "alter function public.es_admin() security invoker;" \
  "la ficha de public.es_admin() no es la auditada"

# D18 — otro modo PARALELO en un helper.
deriva "private.es_gerencia_crm_activa() había pasado a PARALLEL SAFE" \
  "alter function private.es_gerencia_crm_activa() parallel safe;" \
  "la ficha de private.es_gerencia_crm_activa() no es la auditada"

# ── Ronda 2 (C-2 de Codex / A-4 del auditor): el postflight falla cerrado ────────────────────────────────────────────────

# D19 — falta uno de los dos `assert_*` que rodean a la función: antes «no existe» coincidía antes y después y la migración
# seguía; ahora se niega en el preflight.
deriva "private.assert_f7_piezas_cerradas() no existía" \
  "drop function private.assert_f7_piezas_cerradas();" \
  "falta private.assert_analista_vigencia() o private.assert_f7_piezas_cerradas()"

# D20 — la base no tiene un par vendedor–cliente apto para la sonda (se desactivan las fichas de vendedor con los triggers
# apagados, dentro del rollback): antes la sonda quedaba «omitida» y la migración seguía; ahora se niega en el POSTFLIGHT con
# el mensaje que dice cómo preparar el actor, y la guarda recién instalada se deshace con el resto.
deriva "no había un vendedor activo con un cliente activo en su cartera (la sonda no tiene actor)" \
  "set local session_replication_role = replica; update crm.equipo set activo = false where rol_crm = 'vendedor' and activo; set local session_replication_role = origin;" \
  "la sonda «ABC» no se pudo ejecutar"

# D21 — NINGÚN candidato es concluyente: con la identidad unificada encendida (`crm.multiempresa_flags.resolver_en_puertas`,
# encendida en el laboratorio), TODOS los clientes sin documento hacen que `private.asegurar_identidad_perfil` lance P0409 antes
# de la guarda en cada uno de los candidatos que la sonda prueba (hasta 5). En la ronda 1 la sonda quedaba «no concluyente» y la
# migración seguía; en la ronda 2 se negaba con la causa del único par; ahora (ronda 3) se niega en el POSTFLIGHT con la LISTA de
# los candidatos probados, cada uno con su causa, y dice qué preparar.
deriva "ningún candidato concluyente: los clientes no tenían documento (cada candidato muere antes de la guarda con P0409)" \
  "set local session_replication_role = replica; update public.perfiles set dni = null where rol = 'cliente'; set local session_replication_role = origin;" \
  "no fue concluyente con ninguno de los"
listados=$(grep -c '· candidato [0-9]*: vendedor .* → no concluyente: P0409' "$TMP/d$n.salida.txt")
if [[ "$listados" -ge 2 ]]; then
  echo "  ✓ el mensaje enumera $listados candidatos probados, cada uno con su causa (P0409), y dice qué preparar"
else
  echo "  ✗ EL MENSAJE NO ENUMERA LOS CANDIDATOS PROBADOS ($listados listados; se esperaban al menos 2)"
  fallos=$((fallos + 1))
fi

# D22 — (ronda 3, R2-1 de Codex) solo el PRIMER candidato de la ordenación (order by e.perfil_id, c.id) no es concluyente: su
# cliente pierde el documento (con los triggers apagados, dentro del rollback) y la llamada muere antes de la guarda con P0409;
# el segundo candidato queda intacto. La sonda tiene que descartar al primero, concluir con el segundo y la migración ENTRA; su
# NOTICE dice qué candidato concluyó (2 de 2 probados) y cuál se descartó y por qué. Antes de la ronda 3 (sonda con `limit 1`)
# esta deriva hacía abortar la migración aunque hubiera otros 15 pares aptos (medido contra la migración de la ronda 2).
PRIMER_CLIENTE_SIN_DOCUMENTO="set local session_replication_role = replica; update public.perfiles set dni = null where id = (select c.id from crm.equipo e join public.perfiles p on p.id = e.perfil_id join public.perfiles c on c.asesor_perfil_id = e.perfil_id and c.rol = 'cliente' and c.activo where e.rol_crm = 'vendedor' and e.activo and p.activo and p.rol = 'comercial' and private.rol_crm(e.perfil_id) = 'vendedor' order by e.perfil_id, c.id limit 1); set local session_replication_role = origin;"
NOTICE_CANDIDATO_2='RECHAZADO con 22023 y el mensaje fijado (concluyó el candidato 2 de 2 probado(s)'
n=$((n + 1))
echo "$n. Deriva (ENTRA): el primer candidato de la sonda no es concluyente (su cliente sin documento) y el segundo sí"
printf '%s\n' "$PRIMER_CLIENTE_SIN_DOCUMENTO" > "$TMP/d$n.deriva.sql"
node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d$n.deriva.sql" > "$TMP/d$n.sql" || exit 1
corre "$TMP/d$n.sql"
if ! grep -q 'DERIVA_INSTALADA' "$TMP/d$n.salida.txt"; then
  echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/d$n.salida.txt" | cut -c1-200)"
  fallos=$((fallos + 1))
elif [[ "$(veredicto "$TMP/d$n.salida.txt")" == "DERIVA VERDE" ]] && grep -q '^la migración NO abortó' "$TMP/d$n.salida.txt" \
     && grep -qF "$NOTICE_CANDIDATO_2" "$TMP/d$n.salida.txt" \
     && grep -q '· candidato 1: vendedor .* → no concluyente: P0409' "$TMP/d$n.salida.txt"; then
  echo "  ✓ la migración ENTRÓ y el NOTICE lo dice → $(grep -m 1 -o 'concluyó el candidato [0-9]* de [0-9]* probado(s)[^;]*' "$TMP/d$n.salida.txt"); descartado el candidato 1 por P0409"
else
  echo "  ✗ LA SONDA NO ITERÓ COMO DEBÍA → $(aborto "$TMP/d$n.salida.txt") · NOTICE: $(grep -m 1 -o 'sonda «ABC» para un no exento: .*' "$TMP/d$n.salida.txt" | cut -c1-200)"
  fallos=$((fallos + 1))
fi
ENTRAN=1

# ── MUTANTE DEL PREFLIGHT: sin la comparación de is_grantable, la deriva WITH GRANT OPTION tiene que COLARSE ──────────────
echo "M. Mutante del preflight: una copia de la migración SIN comparar is_grantable tiene que dejar entrar la deriva WITH GRANT OPTION"
if python3 - "$MIG" "$TMP/mig-sin-grantable.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
cambios = [
    ("(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)",
     "(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type order by a.grantee::regrole::text)"),
    ("is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false', 'service_role:EXECUTE:false'] then",
     "is distinct from array['authenticated:EXECUTE', 'postgres:EXECUTE', 'service_role:EXECUTE'] then"),
]
for vigente, mutado in cambios:
    n = sql.count(vigente)
    if n != 1:
        sys.exit('MUTANTE DEL PREFLIGHT NO APLICABLE: el fragmento aparece %d veces (debía ser 1): %s' % (n, vigente[:80]))
    sql = sql.replace(vigente, mutado)
open(destino, 'w', encoding='utf-8').write(sql)
PY
then
  printf '%s\n' "$GRANT_OPTION" > "$TMP/mp.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-sin-grantable.sql" --deriva "$TMP/mp.deriva.sql" \
    --espera "$FICHA" > "$TMP/mp.sql" || exit 1
  corre "$TMP/mp.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/mp.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/mp.salida.txt" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$TMP/mp.salida.txt")" == "DERIVA ROJO" ]] && grep -q '^la migración NO abortó' "$TMP/mp.salida.txt"; then
    echo "  ✓ el mutante muere: sin comparar is_grantable, la deriva se coló (la migración entró). Es esa comparación la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: el preflight sin is_grantable abortó igualmente → $(aborto "$TMP/mp.salida.txt")"
    fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir el mutante del preflight"
  fallos=$((fallos + 1))
fi

# ── MUTANTE DEL PREFLIGHT 2 (ronda 2): sin la comparación de la FICHA de los helpers (preflight y postflight), la deriva
#    «private.rol_crm IMMUTABLE» tiene que COLARSE: el md5(prosrc) no la ve. ─────────────────────────────────────────────
echo "M2. Mutante del preflight: una copia de la migración SIN comparar la ficha de los helpers tiene que dejar entrar la deriva IMMUTABLE"
if python3 - "$MIG" "$TMP/mig-sin-ficha-helpers.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
cambios = [
    ("raise exception 'PREFLIGHT numero_contrato_servidor: la ficha de % no es la auditada (medida «%»; auditada «%»): la excepción del admin o el autogenerado ya no son los auditados'",
     "raise notice 'PREFLIGHT numero_contrato_servidor: la ficha de % no es la auditada (medida «%»; auditada «%»): la excepción del admin o el autogenerado ya no son los auditados'"),
    ("raise exception 'POSTFLIGHT numero_contrato_servidor: la ficha de % cambió durante la migración (medida «%»)'",
     "raise notice 'POSTFLIGHT numero_contrato_servidor: la ficha de % cambió durante la migración (medida «%»)'"),
]
for vigente, mutado in cambios:
    n = sql.count(vigente)
    if n != 1:
        sys.exit('MUTANTE DEL PREFLIGHT 2 NO APLICABLE: el fragmento aparece %d veces (debía ser 1): %s' % (n, vigente[:80]))
    sql = sql.replace(vigente, mutado)
open(destino, 'w', encoding='utf-8').write(sql)
PY
then
  printf '%s\n' "$HELPER_IMMUTABLE" > "$TMP/mp2.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-sin-ficha-helpers.sql" --deriva "$TMP/mp2.deriva.sql" \
    --espera "la ficha de private.rol_crm(uuid) no es la auditada" > "$TMP/mp2.sql" || exit 1
  corre "$TMP/mp2.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/mp2.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/mp2.salida.txt" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$TMP/mp2.salida.txt")" == "DERIVA ROJO" ]] && grep -q '^la migración NO abortó' "$TMP/mp2.salida.txt"; then
    echo "  ✓ el mutante muere: sin comparar la ficha de los helpers, la deriva IMMUTABLE se coló (la migración entró). Es esa comparación la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: el preflight sin la ficha de los helpers abortó igualmente → $(aborto "$TMP/mp2.salida.txt")"
    fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir el mutante del preflight 2"
  fallos=$((fallos + 1))
fi

# ── MUTANTE DEL POSTFLIGHT (ronda 3): una copia de la migración cuya sonda NO itera (`limit 5` → `limit 1`: la sonda de la
#    ronda 2) tiene que ABORTAR con la deriva D22 («primer candidato no concluyente»): 1 candidato probado, ninguno concluyente.
#    Con la migración real, D22 entra. Es la iteración la que protege. ───────────────────────────────────────────────────────
echo "M3. Mutante del postflight: una copia de la migración cuya sonda NO itera (limit 1) tiene que abortar con la deriva «primer candidato no concluyente»"
if python3 - "$MIG" "$TMP/mig-sonda-sin-iterar.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
cambios = [
    ("    order by e.perfil_id, c.id\n    limit 5\n",
     "    order by e.perfil_id, c.id\n    limit 1\n"),
]
for vigente, mutado in cambios:
    n = sql.count(vigente)
    if n != 1:
        sys.exit('MUTANTE DEL POSTFLIGHT NO APLICABLE: el fragmento aparece %d veces (debía ser 1): %s' % (n, vigente[:80]))
    sql = sql.replace(vigente, mutado)
open(destino, 'w', encoding='utf-8').write(sql)
PY
then
  printf '%s\n' "$PRIMER_CLIENTE_SIN_DOCUMENTO" > "$TMP/mp3.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-sonda-sin-iterar.sql" --deriva "$TMP/mp3.deriva.sql" \
    --espera "no fue concluyente con ninguno de los 1 candidato(s) probados" > "$TMP/mp3.sql" || exit 1
  corre "$TMP/mp3.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/mp3.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/mp3.salida.txt" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$TMP/mp3.salida.txt")" == "DERIVA VERDE" ]] && grep -q '^la migración ABORTÓ' "$TMP/mp3.salida.txt"; then
    echo "  ✓ el mutante muere: sin iterar, la deriva «primer candidato no concluyente» hace abortar la migración (1 candidato probado, ninguno concluyente); con la iteración entra. Es la iteración la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: la sonda sin iterar no abortó como la ronda 2 → $(aborto "$TMP/mp3.salida.txt")"
    fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir el mutante del postflight"
  fallos=$((fallos + 1))
fi

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: las $((n - ENTRAN)) abortan (preflight, o postflight las dos de la sonda) y no dejan rastro; la deriva $n (primer candidato no concluyente) ENTRA y su NOTICE nombra al candidato 2; el control entra; los tres mutantes (dos del preflight, uno del postflight) mueren."
  exit 0
fi
echo "DERIVAS: $fallos sin el veredicto esperado — el preflight o la sonda no protegen lo que dicen."
exit 1
