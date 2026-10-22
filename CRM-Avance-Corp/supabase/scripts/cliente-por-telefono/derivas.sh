#!/usr/bin/env bash
# DERIVAS PREVIAS del bloque 2.7 — la migración se niega si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una deriva rompe el catálogo
# ANTES: lo que se prueba aquí es el PREFLIGHT de la migración. `create or replace` conserva dueño y ACL y reemplaza el cuerpo que
# encuentre: sin preflight, un cambio hecho a mano en el núcleo `private.alta_reactivar_retirado` (o en el alta, el verificador o
# una pieza de la que depende la regla) se borraría o se daría por bueno sin que nadie lo viera. Con cada deriva la migración
# tiene que ABORTAR en su preflight —con el mensaje que le corresponde, no con cualquier error— y dejar el núcleo y el alta
# (definición, ACL y comentario) EXACTAMENTE como estaban.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Sin él, un envoltorio roto daría «abortó»
# siempre. Al final va un MUTANTE DEL PREFLIGHT: una copia de la migración sin la comparación de `is_grantable` tiene que dejarse
# colar la deriva «WITH GRANT OPTION» (la migración entra): así se sabe que es esa comparación, y no otra cosa, la que protege.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo ocurre en transacciones que terminan en
# rollback:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" EJECUTAR_SQL_ADMIN="<el mismo, como supabase_admin>" \
#     DIR_ENSAYO=<carpeta> bash supabase/scripts/cliente-por-telefono/derivas.sh
# (Ronda 3: al final, las derivas de la REVERSA —SET, GRANT a authenticated o a service_role, cambio de dueño, comentario— y el
#  mutante de la reversa sin la comprobación de ficha y ACL.)
# DIR_ENSAYO es obligatoria: ahí quedan los SQL generados y sus salidas (este guion no escribe en carpetas temporales).
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"

DIR=supabase/scripts/cliente-por-telefono
MIG="$(ls supabase/migrations/*_crm_cliente_por_telefono.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_cliente_por_telefono.sql"; exit 1; }
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1

F='crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'
N='private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'

corre() { # corre <archivo.sql> → deja la salida completa en <archivo>.salida.txt
  local codigo
  # shellcheck disable=SC2086  # EJECUTAR_SQL es un comando con sus argumentos
  $EJECUTAR_SQL "$1" > "${1%.sql}.salida.txt" 2>&1
  codigo=$?
  # 9 = el ejecutor del laboratorio comparó la base antes y después y CAMBIÓ. Un ensayo no escribe: se para todo y se avisa.
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
  # La marca separa «la deriva no se pudo instalar» (no se juzga) de «la migración se negó». El veredicto VERDE lo da el propio
  # ensayo: abortó con el texto esperado del preflight Y la foto (núcleo y alta: definición, ACL, comentario) es idéntica.
  if ! grep -q 'DERIVA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$salida")" == "DERIVA VERDE" ]]; then
    echo "  ✓ el preflight se negó y no dejó rastro → $(aborto "$salida")"
  else
    echo "  ✗ LA MIGRACIÓN NO SE NEGÓ COMO DEBÍA → $(aborto "$salida")"
    fallos=$((fallos + 1))
  fi
}

NUCLEO_CUERPO='el núcleo private.alta_reactivar_retirado cambió desde que se auditó'
NUCLEO_FICHA='la ficha del núcleo no es la auditada'
NUCLEO_COMENTARIO='el comentario del núcleo cambió'
ALTA_CUERPO='crm.crear_lead_si_disponible cambió desde que se auditó'
ALTA_FICHA='la ficha de crm.crear_lead_si_disponible no es la auditada'
VERIFICADOR='no es el fijado por la carga de bases'
PIEZA='cambió una pieza de la que depende la regla'
APLICADA='ya está aplicada'

# D1–D3 — el NÚCLEO del 2.4 ya no es el auditado: otro cuerpo; el mismo cuerpo con otro SET; INVOKER (md5 de la definición).
deriva "el núcleo tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('$N'::regprocedure), 'Acceso CRM revocado', 'Acceso CRM revocado.'); end \$d\$;" \
  "$NUCLEO_CUERPO"
deriva "el núcleo traía otro SET además de search_path y lock_timeout" \
  "alter function $N set statement_timeout = '30s';" \
  "$NUCLEO_CUERPO"
deriva "el núcleo había pasado a security invoker" \
  "alter function $N security invoker;" \
  "$NUCLEO_CUERPO"

# D4–D5 — la ACL del núcleo no es la auditada (no entra en el md5): authenticated o service_role con EXECUTE.
deriva "authenticated ya tenía EXECUTE sobre el núcleo" \
  "grant execute on function $N to authenticated;" \
  "$NUCLEO_FICHA"
deriva "service_role ya tenía EXECUTE sobre el núcleo" \
  "grant execute on function $N to service_role;" \
  "$NUCLEO_FICHA"

# D6 — el comentario del núcleo ya no es el del 2.4: el nuevo se escribiría encima sin saberlo (y la reversa no podría reponerlo).
deriva "el núcleo traía otro comentario" \
  "comment on function $N is 'comentario ajeno';" \
  "$NUCLEO_COMENTARIO"

# D7–D10 — el ALTA ya no es la que deja el 2.4: otro cuerpo; otro SET; anon con EXECUTE; authenticated WITH GRANT OPTION.
deriva "crm.crear_lead_si_disponible tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('$F'::regprocedure), 'El nombre es obligatorio', 'El nombre es obligatorio.'); end \$d\$;" \
  "$ALTA_CUERPO"
deriva "crm.crear_lead_si_disponible traía otro SET" \
  "alter function $F set statement_timeout = '30s';" \
  "$ALTA_CUERPO"
deriva "anon ya tenía EXECUTE sobre el alta" \
  "grant execute on function $F to anon;" \
  "$ALTA_FICHA"
GRANT_OPTION="grant execute on function $F to authenticated with grant option;"
deriva "authenticated tenía EXECUTE WITH GRANT OPTION sobre el alta" \
  "$GRANT_OPTION" \
  "$ALTA_FICHA"

# D11–D12 — el VERIFICADOR ya no es el que fija la carga de bases: otro cuerpo (3 argumentos) u otra configuración (2 argumentos;
# entra en la huella compuesta aunque el cuerpo sea el mismo).
deriva "el verificador (3 argumentos) tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.verificar_disponibilidad_lead_impl(text,text,uuid)'::regprocedure), 'Un solo lead TOTAL por persona', 'Un solo lead TOTAL por persona.'); end \$d\$;" \
  "$VERIFICADOR"
deriva "el verificador (2 argumentos) traía un SET lock_timeout" \
  "alter function private.verificar_disponibilidad_lead_impl(text,text) set lock_timeout = '5s';" \
  "$VERIFICADOR"

# D13–D14 — una PIEZA de la que depende la regla cambió: el juicio de identidad; la pieza del dato conservado del 2.4.
deriva "private.juicio_persona tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.juicio_persona(uuid,uuid)'::regprocedure), 'sin asesor asignado', 'sin asesor asignado.'); end \$d\$;" \
  "$PIEZA"
deriva "private.alta_reactivar_bloqueo_conservado tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.alta_reactivar_bloqueo_conservado(uuid)'::regprocedure), 'sin asesor asignado', 'sin asesor asignado.'); end \$d\$;" \
  "$PIEZA"

# D15 — la migración YA está aplicada: reaplicarla se niega (el núcleo ya lleva la regla).
deriva "la migración ya estaba aplicada (reaplicar se niega)" \
  "-- @@MIGRACION@@" \
  "$APLICADA"

# ── MUTANTE DEL PREFLIGHT: sin la comparación de is_grantable, la deriva WITH GRANT OPTION tiene que COLARSE ──────────────
echo "M. Mutante del preflight: una copia de la migración SIN comparar is_grantable tiene que dejar entrar la deriva WITH GRANT OPTION"
if python3 - "$MIG" "$TMP/mig-sin-grantable.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
cambios = [
    # (el núcleo y el alta en el preflight; el núcleo en el postflight)
    ("(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)",
     "(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type order by a.grantee::regrole::text)", 3),
    ("is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']",
     "is distinct from array['authenticated:EXECUTE', 'postgres:EXECUTE']", 1),
    ("is distinct from array['postgres:EXECUTE:false']",
     "is distinct from array['postgres:EXECUTE']", 2),
]
for vigente, mutado, veces in cambios:
    n = sql.count(vigente)
    if n != veces:
        sys.exit('MUTANTE DEL PREFLIGHT NO APLICABLE: el fragmento aparece %d veces (debía ser %d): %s' % (n, veces, vigente[:80]))
    sql = sql.replace(vigente, mutado)
open(destino, 'w', encoding='utf-8').write(sql)
PY
then
  printf '%s\n' "$GRANT_OPTION" > "$TMP/mp.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-sin-grantable.sql" --deriva "$TMP/mp.deriva.sql" \
    --espera "$ALTA_FICHA" > "$TMP/mp.sql" || exit 1
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

# ══ DERIVAS DE LA REVERSA (ronda 3: Codex P1 / auditor F4) ══════════════════════════════════════════════════════════════
# Aplicar la migración → una deriva posterior sobre el núcleo → intentar la reversa: tiene que ABORTAR en su preflight con su
# mensaje y no dejar rastro (foto del núcleo y del alta —definición, dueño, ACL, comentario— idéntica). El cambio de dueño solo lo
# puede hacer un superusuario (en el laboratorio `postgres` no puede dar el núcleo a otro rol: ninguno más tiene CREATE en `private`),
# así que esa deriva se ensaya con el ejecutor del laboratorio como `supabase_admin` (EJECUTAR_SQL_ADMIN), sin conceder nada a nadie.
: "${EJECUTAR_SQL_ADMIN:?EJECUTAR_SQL_ADMIN: el mismo ejecutor del laboratorio como supabase_admin (para la deriva «cambio de dueño»)}"
veredicto_r() { grep -Eo 'REVERSA CON (DERIVA|SET) (VERDE|ROJO)' "$1" | head -n 1 | grep -Eo '(VERDE|ROJO)$'; }
aborto_r() { grep -m 1 -E '^la reversa (ABORTÓ|NO abortó)' "$1" | cut -c1-230; }
nr=0
reversa_deriva() { # reversa_deriva <nombre> <sentencia(s) SQL> <texto que debe abortar | vacío = control> [admin]
  local salida archivo ejecutor="$EJECUTAR_SQL" codigo
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
  # shellcheck disable=SC2086  # el ejecutor es un comando con sus argumentos
  $ejecutor "$archivo" > "$salida" 2>&1
  codigo=$?
  if [[ "$codigo" -eq 9 ]]; then echo "!!! La base cambió durante un ensayo ($archivo). Se detiene todo." >&2; exit 9; fi
  if ! grep -q 'SET_INSTALADO' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"; fallos=$((fallos + 1)); return
  fi
  if [[ "$(veredicto_r "$salida")" == "VERDE" ]]; then
    if [[ -n "$3" ]]; then echo "  ✓ la reversa se negó y no dejó rastro → $(aborto_r "$salida")"
    else echo "  ✓ control: sin deriva, la reversa entra y el núcleo vuelve a ser el del 2.4"; fi
  else
    echo "  ✗ LA REVERSA NO SE COMPORTÓ COMO DEBÍA → $(aborto_r "$salida")"; fallos=$((fallos + 1))
  fi
}
REV_DEF='no tiene exactamente la definición que dejó la migración'
REV_FICHA='la ficha del núcleo no es la que dejó la migración'
REV_COMENTARIO='el comentario del núcleo no es el que dejó la migración'
reversa_deriva "control (sin deriva): la reversa entra y devuelve el núcleo del 2.4" "" ""
reversa_deriva "un SET statement_timeout añadido al núcleo" "alter function $N set statement_timeout = '30s';" "$REV_DEF"
reversa_deriva "un GRANT EXECUTE a authenticated sobre el núcleo" "grant execute on function $N to authenticated;" "$REV_FICHA"
reversa_deriva "un GRANT EXECUTE a service_role sobre el núcleo" "grant execute on function $N to service_role;" "$REV_FICHA"
reversa_deriva "el núcleo cambió de dueño (lo hace un superusuario)" "alter function $N owner to supabase_admin;" "$REV_FICHA" admin
reversa_deriva "el comentario del núcleo cambió" "comment on function $N is 'comentario ajeno';" "$REV_COMENTARIO"

# ── MUTANTES DE LA REVERSA: las comprobaciones de ficha y ACL son las que protegen ─────────────────────────────────────────────
#    RM1 — sin la comprobación del PREFLIGHT: el GRANT a authenticated todavía hace abortar la reversa, ahora en su POSTFLIGHT (que
#          exige la ACL exacta del 2.4): defensa en dos capas, y nada queda escrito.
#    RM2 — sin la del preflight NI la del postflight: la reversa revierte dejando el GRANT (lo que señaló Codex P1). Muere = se cuela.
mutar_reversa() { # mutar_reversa <modo: preflight|ambos> <destino>
  python3 - "$DIR/reversa.sql" "$2" "$1" <<'PY'
import sys
origen, destino, modo = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
marca = "  -- Ronda 3 (Codex P1 / auditor F4): lo que la definición no incluye."
fin_pre = "  if md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from"
if sql.count(marca) != 1:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (preflight)')
i = sql.index(marca); j = sql.index(fin_pre, i)
sql = sql[:i] + sql[j:]
if modo == 'ambos':
    post = sql.index("do $postflight$")
    k = sql.index("  if not exists (select 1 from pg_proc p\n", post)
    aviso = "raise exception 'REVERSA cliente_por_telefono: el núcleo no quedó con la ficha y la ACL exactas del 2.4"
    m = sql.index(aviso, k)
    fin_post = sql.index("  end if;\n", m) + len("  end if;\n")
    if sql.count(aviso) != 1:
        sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (postflight)')
    sql = sql[:k] + sql[fin_post:]
open(destino, 'w', encoding='utf-8').write(sql)
PY
}
printf '%s\n' "grant execute on function $N to authenticated;" > "$TMP/rm.deriva.sql"
echo "RM1. Mutante de la reversa SIN la comprobación de ficha y ACL del preflight: el GRANT a authenticated aborta en el postflight"
if mutar_reversa preflight "$TMP/reversa-sin-ficha-preflight.sql"; then
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm.deriva.sql" --espera 'el núcleo no quedó con la ficha y la ACL exactas del 2.4' \
    --reversa-archivo "$TMP/reversa-sin-ficha-preflight.sql" > "$TMP/rm1.sql" || exit 1
  corre "$TMP/rm1.sql"
  if [[ "$(veredicto_r "$TMP/rm1.salida.txt")" == "VERDE" ]]; then
    echo "  ✓ sin la comprobación del preflight, la reversa aborta en su postflight sin rastro → $(aborto_r "$TMP/rm1.salida.txt")"
  else
    echo "  ✗ RM1 → $(aborto_r "$TMP/rm1.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir RM1"; fallos=$((fallos + 1))
fi
echo "RM2. Mutante de la reversa SIN ninguna de las dos comprobaciones: el GRANT a authenticated tiene que COLARSE"
if mutar_reversa ambos "$TMP/reversa-sin-ficha.sql"; then
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm.deriva.sql" --espera "$REV_FICHA" --reversa-archivo "$TMP/reversa-sin-ficha.sql" > "$TMP/rm2.sql" || exit 1
  corre "$TMP/rm2.sql"
  if [[ "$(veredicto_r "$TMP/rm2.salida.txt")" == "ROJO" ]] && grep -q -E '^la reversa NO abortó' "$TMP/rm2.salida.txt"; then
    echo "  ✓ el mutante muere: sin esas comprobaciones, la reversa revirtió dejando el GRANT. Son ellas las que protegen."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto_r "$TMP/rm2.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir RM2"; fallos=$((fallos + 1))
fi

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: las $n abortan en el preflight de la migración y no dejan rastro; el control entra; el mutante del preflight muere."
  echo "DERIVAS DE LA REVERSA: el control entra; las $((nr - 1)) derivas abortan su preflight sin rastro; RM1 aborta en el postflight y RM2 muere."
  exit 0
fi
echo "DERIVAS: $fallos sin el veredicto esperado — un preflight no protege lo que dice."
exit 1
