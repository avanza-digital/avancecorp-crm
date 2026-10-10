#!/usr/bin/env bash
# DERIVAS PREVIAS — la migración se niega si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una deriva rompe el
# catálogo ANTES: lo que se prueba aquí es el PREFLIGHT de la migración. `create or replace` conserva dueño y ACL, y
# reemplaza el cuerpo que encuentre: sin preflight, un cambio hecho a mano en una puerta (o en lo que decide la excepción)
# se borraría sin que nadie lo viera. Con cada deriva la migración tiene que ABORTAR en su preflight —con el mensaje que le
# corresponde, no con cualquier error— y dejar las puertas, el detector, las ACL y los comentarios EXACTAMENTE como estaban.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Sin él, un envoltorio roto daría
# «abortó» siempre. Al final va un MUTANTE DEL PREFLIGHT: una copia de la migración sin la comparación de `is_grantable`
# tiene que dejarse colar la deriva «WITH GRANT OPTION» (la migración entra): así se sabe que es esa comparación, y no otra
# cosa, la que protege.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo ocurre en transacciones que terminan en
# rollback:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/anular-venta-mes-sellado/derivas.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin ella van a una carpeta temporal que se
# borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/anular-venta-mes-sellado
MIG=supabase/migrations/20261009210000_crm_anular_venta_mes_sellado.sql
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
  # propio ensayo: abortó con el texto esperado del preflight Y la foto (cuerpos, ACL, comentarios y detector) es idéntica a
  # la de antes de intentar la migración.
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

# D1 y D2 — el CUERPO de una puerta ya no es el auditado (md5 de `prosrc` distinto).
deriva "crm.anular_cierre_avance tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('crm.anular_cierre_avance(uuid,text)'::regprocedure), 'Solo gerencia anula cierres', 'Solo gerencia anula cierres.'); end \$d\$;" \
  "crm.anular_cierre_avance cambió desde que se auditó"
deriva "crm.anular_cierre_externo tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('crm.anular_cierre_externo(uuid,text)'::regprocedure), 'Solo gerencia anula cierres externos', 'Solo gerencia anula cierres externos.'); end \$d\$;" \
  "crm.anular_cierre_externo cambió desde que se auditó"

# D3 y D4 — el cuerpo es el mismo pero la DEFINICIÓN no (un `SET` añadido con ALTER FUNCTION): md5 de `pg_get_functiondef` distinto.
deriva "crm.anular_cierre_avance traía otro SET además del search_path" \
  "alter function crm.anular_cierre_avance(uuid,text) set lock_timeout = '5s';" \
  "crm.anular_cierre_avance cambió desde que se auditó"
deriva "crm.anular_cierre_externo traía otro SET además del search_path" \
  "alter function crm.anular_cierre_externo(uuid,text) set statement_timeout = '5s';" \
  "crm.anular_cierre_externo cambió desde que se auditó"

# D5 — un EXECUTE concedido de antes (la ACL no entra en el md5 del cuerpo): `create or replace` lo conservaría.
deriva "service_role ya tenía EXECUTE sobre crm.anular_cierre_externo" \
  "grant execute on function crm.anular_cierre_externo(uuid,text) to service_role;" \
  "no es la auditada"
deriva "anon ya tenía EXECUTE sobre crm.anular_cierre_avance" \
  "grant execute on function crm.anular_cierre_avance(uuid,text) to anon;" \
  "no es la auditada"

# D6 — el comentario de una puerta ya no es el auditado: el nuevo se escribiría encima sin saberlo.
deriva "una puerta traía otro comentario" \
  "comment on function crm.anular_cierre_avance(uuid,text) is 'comentario ajeno';" \
  "el comentario de una puerta cambió"

# D7 y D8 — lo que decide la excepción ya no es lo auditado (cuerpo).
deriva "private.es_gerencia_crm_activa tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.es_gerencia_crm_activa()'::regprocedure), '= ''gerencia''', 'is not null'); end \$d\$;" \
  "cambió public.es_admin, private.es_gerencia_crm_activa o private.rol_crm"
deriva "private.rol_crm tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.rol_crm(uuid)'::regprocedure), '''gerencia'',''coordinador'',''directorio''', '''gerencia'',''coordinador'''); end \$d\$;" \
  "cambió public.es_admin, private.es_gerencia_crm_activa o private.rol_crm"

# D9 — el detector YA existe (otro cuerpo, antes de la migración): no se sobrescribe.
deriva "private.mes_sellado_de_venta ya existía" \
  "create function private.mes_sellado_de_venta(p_lead_id uuid) returns date language sql as \$d\$ select null::date \$d\$;" \
  "private.mes_sellado_de_venta ya existe"

# D10 — la migración YA está aplicada: reaplicarla se niega (la guarda ya está; el cuerpo vigente no es el auditado).
deriva "la migración ya estaba aplicada (reaplicar se niega)" \
  "-- @@MIGRACION@@" \
  "o esta migración ya está aplicada"

# ── Ronda 2 (hallazgo #5): derivas que conservan el md5 del cuerpo y aun así cambian lo que la regla garantiza ──────────

# D11 — EXECUTE con OPCIÓN DE CONCESIÓN sobre una puerta: misma lista de concesionarios y privilegios, otra ACL.
GRANT_OPTION="grant execute on function crm.anular_cierre_avance(uuid,text) to authenticated with grant option;"
deriva "authenticated tenía EXECUTE WITH GRANT OPTION sobre crm.anular_cierre_avance" \
  "$GRANT_OPTION" \
  "la ficha de crm.anular_cierre_avance(uuid,text) no es la auditada"

# D12 — `public.es_admin()` IMMUTABLE: mismo md5(prosrc), pero una decisión de autorización que el planificador podría
# evaluar una vez y conservar. (Dentro de la transacción del ensayo, que se deshace: no se modifica nada de `public`.)
deriva "public.es_admin() había pasado a IMMUTABLE" \
  "alter function public.es_admin() immutable;" \
  "la ficha de public.es_admin() no es la auditada"

# D13 — `proconfig` distinto en un helper (un SET añadido).
deriva "private.es_gerencia_crm_activa() traía otro SET" \
  "alter function private.es_gerencia_crm_activa() set statement_timeout = '5s';" \
  "la ficha de private.es_gerencia_crm_activa() no es la auditada"

# D14 — otro PROPIETARIO en un helper. `postgres` no es superusuario en el laboratorio: solo puede ceder el dueño a un rol del
# que es miembro (service_role) y que tenga CREATE sobre el esquema, así que la deriva concede ese CREATE antes (todo dentro
# del rollback). Sobre `public.es_admin` no es posible (`public` no es de postgres): se hace sobre `private.rol_crm`.
deriva "private.rol_crm(uuid) tenía otro propietario" \
  "grant create on schema private to service_role; alter function private.rol_crm(uuid) owner to service_role;" \
  "la ficha de private.rol_crm(uuid) no es la auditada"

# D15 — otro modo PARALELO en un helper (el único atributo de la ficha que aún no cambiaba ninguna deriva).
deriva "private.es_gerencia_crm_activa() había pasado a PARALLEL SAFE" \
  "alter function private.es_gerencia_crm_activa() parallel safe;" \
  "la ficha de private.es_gerencia_crm_activa() no es la auditada"

# ── Ronda 3 (R2-2 y R2-3): las restricciones que hacen canónico el mes, y la versión del ledger ──────────────────────────

# D16 — el CHECK de `periodo_comercial` (primer día de mes) ya no está: el detector supondría algo que el esquema ya no garantiza.
#       Se localiza por su TEXTO (pg_get_constraintdef), como hace el preflight, no por su nombre.
deriva "crm.conversion_acreditaciones había perdido el CHECK periodo_comercial = date_trunc(month, fecha_comercial)" \
  "do \$d\$ declare v text; begin select c.conname into v from pg_constraint c where c.conrelid = 'crm.conversion_acreditaciones'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) = 'CHECK ((periodo_comercial = (date_trunc(''month''::text, (fecha_comercial)::timestamp without time zone))::date))'; if v is null then raise exception 'DERIVA NO APLICABLE: no existe el CHECK de periodo_comercial'; end if; execute format('alter table crm.conversion_acreditaciones drop constraint %I', v); end \$d\$;" \
  "crm.conversion_acreditaciones.periodo_comercial ya no es NOT NULL con CHECK"

# D17 — `periodo_comercial` admite NULL.
deriva "crm.conversion_acreditaciones.periodo_comercial había perdido el NOT NULL" \
  "alter table crm.conversion_acreditaciones alter column periodo_comercial drop not null;" \
  "crm.conversion_acreditaciones.periodo_comercial ya no es NOT NULL con CHECK"

# D18 — el CHECK de primer día de `crm.periodos_cerrados.periodo` ya no está (su NOT NULL no se puede quitar: es la clave primaria).
deriva "crm.periodos_cerrados había perdido el CHECK periodo = date_trunc(month, periodo)" \
  "do \$d\$ declare v text; begin select c.conname into v from pg_constraint c where c.conrelid = 'crm.periodos_cerrados'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) = 'CHECK ((periodo = (date_trunc(''month''::text, (periodo)::timestamp with time zone))::date))'; if v is null then raise exception 'DERIVA NO APLICABLE: no existe el CHECK de periodo'; end if; execute format('alter table crm.periodos_cerrados drop constraint %I', v); end \$d\$;" \
  "crm.periodos_cerrados.periodo ya no es NOT NULL con CHECK"

# D19 — OTRA implementación de `private.conversion_episodios` (el ledger del que el detector saca el mes del episodio): la
#       huella del cuerpo cambia (aquí solo un comentario; cualquier otra versión también) y la migración se niega.
deriva "private.conversion_episodios tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)'::regprocedure), 'nunca se inventa un responsable.', 'nunca se inventa un responsable'); end \$d\$;" \
  "private.conversion_episodios no es la versión auditada"

# ── Ronda 4 (R3-1 y R3-2): la segunda función del ledger, y el NOT NULL de `fecha_comercial` ────────────────────────────

# D20 — OTRA implementación de `private.conversion_cierres` (en la que `conversion_episodios` delega los cierres desde
#       septiembre; de ella sale la `fecha_numerador`): la huella de `conversion_episodios` NO cambia (por eso antes de la
#       ronda 4 esta deriva se colaba) y la migración tiene que negarse por la huella de `conversion_cierres`.
deriva "private.conversion_cierres tenía otro cuerpo (conversion_episodios intacta)" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.conversion_cierres(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric,uuid[])'::regprocedure), 'Una fuente retirada no sigue fabricando cierres en un mes abierto.', 'Una fuente retirada no sigue fabricando cierres en un mes abierto'); end \$d\$;" \
  "private.conversion_cierres no es la versión auditada"

# D21 — `fecha_comercial` admite NULL: el CHECK `periodo_comercial = date_trunc('month', fecha_comercial)::date` daría UNKNOWN
#       con una fecha nula y dejaría pasar un periodo cualquiera; sin ese NOT NULL la garantía del mes canónico no existe.
deriva "crm.conversion_acreditaciones.fecha_comercial había perdido el NOT NULL" \
  "alter table crm.conversion_acreditaciones alter column fecha_comercial drop not null;" \
  "crm.conversion_acreditaciones.fecha_comercial ya no es NOT NULL"

# ── MUTANTE DEL PREFLIGHT (hallazgo #5): sin la comparación de is_grantable, la deriva D11 tiene que COLARSE ──────────────
echo "M. Mutante del preflight: una copia de la migración SIN comparar is_grantable tiene que dejar entrar la deriva WITH GRANT OPTION"
if python3 - "$MIG" "$TMP/mig-sin-grantable.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
cambios = [
    ("(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)",
     "(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type order by a.grantee::regrole::text)"),
    ("is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false'] then",
     "is distinct from array['authenticated:EXECUTE', 'postgres:EXECUTE'] then"),
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
    --espera "la ficha de crm.anular_cierre_avance(uuid,text) no es la auditada" > "$TMP/mp.sql" || exit 1
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

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: las $n abortan en el preflight y no dejan rastro; el control entra; el mutante del preflight muere."
  exit 0
fi
echo "DERIVAS: $fallos sin el veredicto esperado — el preflight no protege lo que dice."
exit 1
