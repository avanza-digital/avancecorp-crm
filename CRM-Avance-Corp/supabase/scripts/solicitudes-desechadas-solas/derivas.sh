#!/usr/bin/env bash
# DERIVAS PREVIAS — la migración se niega si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una deriva rompe el catálogo
# ANTES: lo que se prueba aquí es el PREFLIGHT. `create or replace` conserva dueño y ACL y reemplaza el cuerpo que encuentre, y
# el parche por ancla escribe sobre el texto vivo: sin preflight, un cambio hecho a mano en una puerta, en una guarda de la que
# depende la regla o en la forma de las tablas se daría por bueno sin que nadie lo viera. Con cada deriva la migración tiene que
# ABORTAR —con el mensaje que le corresponde, no con cualquier error— y dejar las puertas, las piezas, las columnas, la tabla y
# el job EXACTAMENTE como estaban.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Al final van los MUTANTES DE LA MIGRACIÓN:
# una copia sin la comparación de la ficha tiene que dejarse colar un EXECUTE «con opción de concesión» (D23); una copia sin
# la comparación del comentario, un comentario ajeno. Así se sabe que son esas comparaciones las que protegen. Para M1 no sirve
# el EXECUTE de anon (D4) ni, desde la ronda 3, el de service_role (D22): esos los para ADEMÁS el postflight
# (`has_function_privilege`), y una defensa duplicada no se puede probar con un solo mutante (ronda 1: M1 «no se coló» por eso,
# no por la ficha). La opción de concesión (`is_grantable`) solo la ve la ficha: `has_function_privilege` no la distingue.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo ocurre en transacciones con rollback:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" DIR_ENSAYO=<carpeta> bash supabase/scripts/solicitudes-desechadas-solas/derivas.sh
# DIR_ENSAYO=<carpeta> es obligatoria: ahí quedan los SQL generados y sus salidas (son la evidencia). Este guion no borra nada.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde quedan los SQL generados y sus salidas (la evidencia; no se borra nada)}"

DIR=supabase/scripts/solicitudes-desechadas-solas
MIG="$(ls supabase/migrations/*_crm_solicitudes_desechadas_solas.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_solicitudes_desechadas_solas.sql"; exit 1; }
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1

corre() { # corre <archivo.sql> → deja la salida completa en <archivo>.salida.txt
  local codigo
  # shellcheck disable=SC2086  # EJECUTAR_SQL es un comando con sus argumentos
  $EJECUTAR_SQL "$1" > "${1%.sql}.salida.txt" 2>&1
  codigo=$?
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($1). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}

veredicto() { grep -Eo 'DERIVA (VERDE|ROJO)' "$1" | head -n 1; }
aborto() { grep -m 1 -E '^la migración (ABORTÓ|NO abortó)' "$1" | cut -c1-230; }

fallos=0
n=0
m=0

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

deriva() { # deriva <nombre> <sentencia(s) SQL> <texto con el que la migración debe abortar>
  local salida
  n=$((n + 1))
  salida="$TMP/d$n.salida.txt"
  echo "$n. Deriva: $1"
  printf '%s\n' "$2" > "$TMP/d$n.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d$n.deriva.sql" --espera "$3" > "$TMP/d$n.sql" || exit 1
  corre "$TMP/d$n.sql"
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

# mutante_migracion <nombre> <python que transforma la migración> <archivo de la deriva que DEBE colarse>
mutante_migracion() {
  local salida mig_mut
  m=$((m + 1))
  salida="$TMP/mm$m.salida.txt"
  mig_mut="$TMP/mm$m.migracion.sql"
  echo "M$m. Mutante de la migración: $1"
  if ! python3 -c "$2" "$MIG" "$mig_mut"; then
    echo "  ✗ no se pudo construir el mutante de la migración"
    fallos=$((fallos + 1))
    return
  fi
  node "$DIR/armar-ensayo.mjs" --migracion "$mig_mut" --deriva "$3" > "$TMP/mm$m.sql" || exit 1
  corre "$TMP/mm$m.sql"
  if [[ "$(veredicto "$salida")" == "DERIVA VERDE" ]] && grep -q '^la migración NO abortó' "$salida"; then
    echo "  ✓ sin esa comparación la deriva SE CUELA (la migración entró): es esa comparación la que protege"
  else
    echo "  ✗ la deriva no se coló pese a quitar la comparación → $(grep -m 1 -E 'ERROR|^la migración' "$salida" | cut -c1-230)"
    fallos=$((fallos + 1))
  fi
}

ALTA='crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'
CONSULTA='crm.solicitud_inversion_fn(uuid)'
CANCELAR='crm.cancelar_solicitud_inversion_fn(uuid,integer)'
CONFIRMAR='crm.confirmar_inversion_revisada_fn(uuid,integer)'
RESULTADO='private.inversion_solicitud_resultado(uuid,jsonb)'
NO_AUDITADA_ALTA="$ALTA no es la auditada"
NO_AUDITADA_CONSULTA="$CONSULTA no es la auditada"
reemplaza() { # reemplaza <firma> <fragmento> <sustituto> → SQL que re-emite la función con el fragmento cambiado
  printf "do \$d\$ begin execute replace(pg_get_functiondef('%s'::regprocedure), \$v\$%s\$v\$, \$m\$%s\$m\$); end \$d\$;" "$1" "$2" "$3"
}

# D1–D4 — el ALTA v2 no es la auditada: otro cuerpo, un SET añadido, un comentario ajeno, la ACL (no entra en el md5).
deriva "el alta v2 tenía otro cuerpo" "$(reemplaza "$ALTA" "'Sesión no válida'" "'Sesion no valida'")" "$NO_AUDITADA_ALTA"
deriva "el alta v2 traía otro SET además del search_path" "alter function $ALTA set lock_timeout = '5s';" "$NO_AUDITADA_ALTA"
deriva "el alta v2 tenía otro comentario" "comment on function $ALTA is 'otro comentario';" "el comentario de $ALTA no es el auditado"
deriva "anon ya tenía EXECUTE sobre el alta v2" "grant execute on function $ALTA to anon;" "la ficha de $ALTA no es la auditada"
# D5–D7 — la CONSULTA no es la auditada.
deriva "la consulta tenía otro cuerpo" "$(reemplaza "$CONSULTA" "'Solicitud no encontrada'" "'Solicitud no hallada'")" "$NO_AUDITADA_CONSULTA"
deriva "la consulta tenía otro comentario" "comment on function $CONSULTA is 'otro comentario';" "el comentario de $CONSULTA no es el auditado"
deriva "authenticated había perdido el EXECUTE sobre la consulta" "revoke execute on function $CONSULTA from authenticated;" "la ficha de $CONSULTA no es la auditada"
# D8–D10 — lo que la regla da por sabido cambió: la cancelación de la pantalla, la confirmación (clave de idempotencia), el resultado público.
deriva "la cancelación de la pantalla tenía otro cuerpo" "$(reemplaza "$CANCELAR" "'La solicitud cambió; vuelve a cargarla'" "'La solicitud cambio; vuelve a cargarla'")" "$CANCELAR no es la auditada"
deriva "la confirmación ya no mandaba el id de la solicitud como clave de idempotencia" "$(reemplaza "$CONFIRMAR" "'clave_idempotencia',v_s.id" "'clave_idempotencia',gen_random_uuid()")" "$CONFIRMAR no es la auditada"
deriva "el resultado público tenía otro cuerpo" "$(reemplaza "$RESULTADO" "'identidad_fusionada'" "'identidad_fusionada_'")" "$RESULTADO no es la auditada"
# D11–D15 — la forma de las tablas.
deriva "crm.inversion_solicitudes ya tenía la columna cancelacion_motivo" "alter table crm.inversion_solicitudes add column cancelacion_motivo text;" "las columnas de crm.inversion_solicitudes no son las auditadas"
deriva "el CHECK de estado admitía otro estado" "alter table crm.inversion_solicitudes drop constraint inversion_solicitudes_estado_check; alter table crm.inversion_solicitudes add constraint inversion_solicitudes_estado_check check (estado in ('preparada','confirmada','cancelada','archivada'));" "el CHECK de estado de crm.inversion_solicitudes cambió"
deriva "el auditor de la solicitud enmascaraba otras columnas" "drop trigger trg_audit_inversion_solicitudes on crm.inversion_solicitudes; create trigger trg_audit_inversion_solicitudes after insert or update or delete on crm.inversion_solicitudes for each row execute function private.log_audit_sin_secretos('datos');" "el auditor de crm.inversion_solicitudes no es el de hoy"
deriva "el disparador de postventa estaba apagado" "alter table crm.inversion_solicitudes disable trigger trg_solicitudes_zz_postventa;" "el disparador trg_solicitudes_zz_postventa no es el auditado o está deshabilitado"
deriva "private.contrato_altas_idempotentes había perdido su PK" "alter table private.contrato_altas_idempotentes drop constraint contrato_altas_idempotentes_pkey;" "private.contrato_altas_idempotentes no tiene la forma auditada"
# D16–D17 — el UNIQUE del número y la bandera de la empresa.
deriva "public.contratos había perdido el UNIQUE del número" "alter table public.contratos drop constraint contratos_numero_contrato_key;" "ya no tiene el UNIQUE contratos_numero_contrato_key"
deriva "crm.empresas.crea_contrato_avance admitía nulos" "alter table crm.empresas alter column crea_contrato_avance drop not null;" "crm.empresas no tiene crea_contrato_avance boolean NOT NULL"
# D18–D21 — algo de lo nuevo ya existía.
deriva "ya existía una private.solicitud_desechar ajena" "create function private.solicitud_desechar(p integer) returns integer language sql immutable as \$f\$ select p \$f\$;" "ya existe una función private.solicitud_desechar"
deriva "ya existía crm.solicitudes_desechadas_corridas" "create table crm.solicitudes_desechadas_corridas (id integer);" "ya existe crm.solicitudes_desechadas_corridas"
deriva "ya existía el job crm-solicitudes-desechar" "select cron.schedule('crm-solicitudes-desechar', '1 1 * * *', 'select 1');" "ya existe un job crm-solicitudes-desechar"
deriva "la migración ya estaba aplicada (reaplicar se niega)" "-- @@MIGRACION@@" "o esta migración ya está aplicada"
# D22 — la ficha por service_role (desde la ronda 3 también lo vigila el postflight: P3 del auditor r1).
deriva "service_role ya tenía EXECUTE sobre el alta v2" "grant execute on function $ALTA to service_role;" "la ficha de $ALTA no es la auditada"
# D23 — la ficha por la opción de concesión: solo la comparación de la ficha la ve (has_function_privilege no la distingue). Es la deriva de M1.
deriva "authenticated ya tenía EXECUTE con opción de concesión sobre el alta v2 (solo la ficha lo ve)" "grant execute on function $ALTA to authenticated with grant option;" "la ficha de $ALTA no es la auditada"
# D24–D27 (ronda 4; Codex r1, P2-4 y P2-6): el auditor deshabilitado, la guarda de postventa y la continuidad sustituidas, sin reloj.
deriva "el auditor de la solicitud estaba deshabilitado (la definición sigue igual)" "alter table crm.inversion_solicitudes disable trigger trg_audit_inversion_solicitudes;" "el auditor de crm.inversion_solicitudes no es el de hoy o está deshabilitado"
deriva "la guarda de postventa había sido sustituida por una que permite todo" "$(reemplaza 'private.postventa_reinversion_guard()' 'if not found then return new; end if;' 'return new;')" "private.postventa_reinversion_guard() o private.continuidad_coopac_fuente(uuid,uuid,text,text) no es la auditada"
deriva "la continuidad de postventa había sido sustituida (ya no valida el origen)" "$(reemplaza 'private.continuidad_coopac_fuente(uuid,uuid,text,text)' 'perform private.postventa_fuente(p_fuente,p_persona,p_empresa);' 'null;')" "private.postventa_reinversion_guard() o private.continuidad_coopac_fuente(uuid,uuid,text,text) no es la auditada"
# D27–D28 (ronda 5; Codex r2, P3): la ficha de las funciones ajenas de postventa (md5(prosrc) no la fija) y la marca puesta donde no hace falta.
deriva "la guarda de postventa con otro search_path (mismo cuerpo: la huella no lo ve; la ficha sí)" "alter function private.postventa_reinversion_guard() set search_path = 'public';" "la ficha (dueño, DEFINER, configuración) de private.postventa_reinversion_guard() o de private.continuidad_coopac_fuente(uuid,uuid,text,text) no es la auditada"
deriva "la marca crm.laboratorio_sin_cron puesta con pg_cron presente (una marca donde no hace falta es sospechosa)" "select set_config('crm.laboratorio_sin_cron', '1', true);" "la marca crm.laboratorio_sin_cron está puesta y pg_cron está presente"
# «Sin pg_cron» se simula quitando el stub del reloj (tabla y funciones de cron) dentro de la transacción; el stub es de
# supabase_admin, así que estas dos corridas van con EJECUTAR_SQL_ADMIN (lab_sql.py --usuario supabase_admin). Sin esa variable
# se saltan y se dicen (no cuentan como fallo: el laboratorio no tiene otro modo de simular la ausencia de pg_cron).
SIN_CRON='drop function cron.schedule(text,text,text); drop function cron.schedule(text,text); drop function cron.unschedule(text); drop table cron.job;'
corre_admin() { # corre_admin <archivo.sql> → como corre, pero como supabase_admin (dueño del stub del reloj)
  local codigo
  # shellcheck disable=SC2086
  $EJECUTAR_SQL_ADMIN "$1" > "${1%.sql}.salida.txt" 2>&1
  codigo=$?
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($1). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}
if [[ -n "${EJECUTAR_SQL_ADMIN:-}" ]]; then
  n=$((n + 1))
  echo "$n. Deriva: sin pg_cron (tabla y funciones de cron ausentes) y sin la marca de laboratorio [como supabase_admin]"
  printf '%s\n' "$SIN_CRON" > "$TMP/d$n.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d$n.deriva.sql" --espera "sin pg_cron (cron.job o cron.schedule) la tarea nocturna crm-solicitudes-desechar no se puede programar" > "$TMP/d$n.sql" || exit 1
  corre_admin "$TMP/d$n.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/d$n.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/d$n.salida.txt" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$TMP/d$n.salida.txt")" == "DERIVA VERDE" ]]; then
    echo "  ✓ el preflight se negó y no dejó rastro → $(aborto "$TMP/d$n.salida.txt")"
  else
    echo "  ✗ LA MIGRACIÓN NO SE NEGÓ COMO DEBÍA → $(aborto "$TMP/d$n.salida.txt")"
    fallos=$((fallos + 1))
  fi
  # Control: sin pg_cron pero CON la marca de laboratorio (la pone el armador con --sin-cron), la migración entra avisando.
  n=$((n + 1))
  echo "$n. Control: sin pg_cron pero con la marca crm.laboratorio_sin_cron (solo el armador la pone), la migración entra [como supabase_admin]"
  printf '%s\n' "$SIN_CRON" > "$TMP/d$n.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d$n.deriva.sql" --sin-cron > "$TMP/d$n.sql" || exit 1
  corre_admin "$TMP/d$n.sql"
  if [[ "$(veredicto "$TMP/d$n.salida.txt")" == "DERIVA VERDE" ]] && grep -q '^la migración NO abortó' "$TMP/d$n.salida.txt" && grep -q 'LABORATORIO SIN RELOJ' "$TMP/d$n.salida.txt"; then
    echo "  ✓ con la marca entra (y avisa LABORATORIO SIN RELOJ) → $(aborto "$TMP/d$n.salida.txt")"
  else
    echo "  ✗ con la marca tenía que entrar avisando → $(grep -m 1 -E 'ERROR|^la migración' "$TMP/d$n.salida.txt" | cut -c1-230)"
    fallos=$((fallos + 1))
  fi
else
  echo "— Sin EJECUTAR_SQL_ADMIN: se saltan la deriva «sin pg_cron sin marca» y su control (el stub del reloj es de supabase_admin)."
fi

# ── Mutantes de la migración: sin la comparación, la deriva se cuela ──────────────────────────────────────────────────────
printf '%s\n' "grant execute on function $ALTA to authenticated with grant option;" > "$TMP/deriva-grant-option.sql"
mutante_migracion "sin comparar la ficha, el EXECUTE con opción de concesión sobre el alta v2 se cuela (la deriva D23)" '
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
a = """    if v_ficha is distinct from v_h.ficha then
      raise exception '"'"'PREFLIGHT solicitudes_desechadas_solas: la ficha de % no es la auditada (medida «%»; auditada «%»)'"'"', v_h.firma, v_ficha, v_h.ficha;
    end if;
"""
assert t.count(a) == 1, "ancla de la ficha no encontrada"
open(dst, "w", encoding="utf-8").write(t.replace(a, ""))
' "$TMP/deriva-grant-option.sql"
printf '%s\n' "comment on function $CONSULTA is 'otro comentario';" > "$TMP/deriva-comentario.sql"
mutante_migracion "sin comparar el comentario, un comentario ajeno en la consulta se cuela" '
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
a = """    if obj_description(to_regprocedure(v_h.firma), '"'"'pg_proc'"'"') is distinct from v_h.comentario then
      raise exception '"'"'PREFLIGHT solicitudes_desechadas_solas: el comentario de % no es el auditado: revisar antes de instalar'"'"', v_h.firma;
    end if;
"""
assert t.count(a) == 1, "ancla del comentario no encontrada"
open(dst, "w", encoding="utf-8").write(t.replace(a, ""))
' "$TMP/deriva-comentario.sql"

# ── Derivas de la REVERSA (ronda 4; Codex r1, P2-5): algo cambia DESPUÉS de migrar y la reversa tiene que negarse sin rastro ──
k=0
deriva_reversa() { # deriva_reversa <nombre> <sentencia(s) SQL tras migrar> <texto con el que la reversa debe negarse>
  local salida
  k=$((k + 1))
  salida="$TMP/rd$k.salida.txt"
  echo "RD$k. Deriva de la reversa: $1"
  printf '%s\n' "$2" > "$TMP/rd$k.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rd$k.deriva.sql" --espera "$3" > "$TMP/rd$k.sql" || exit 1
  corre "$TMP/rd$k.sql"
  if ! grep -q 'DERIVA_REVERSA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(grep -Eo 'REVERSA CON DERIVA (VERDE|ROJO)' "$salida" | head -n 1)" == "REVERSA CON DERIVA VERDE" ]]; then
    echo "  ✓ la reversa se negó y no dejó rastro → $(grep -m 1 -E '^la reversa (ABORTÓ|NO abortó)' "$salida" | cut -c1-230)"
  else
    echo "  ✗ LA REVERSA NO SE NEGÓ COMO DEBÍA → $(grep -m 1 -E '^la reversa (ABORTÓ|NO abortó)' "$salida" | cut -c1-230)"
    fallos=$((fallos + 1))
  fi
}
deriva_reversa "una pieza con un SET añadido después de migrar" "alter function private.solicitud_desechar(uuid,text,jsonb) set statement_timeout = '7s';" "la pieza private.solicitud_desechar(uuid,text,jsonb) no tiene exactamente la definición que dejó la migración"
deriva_reversa "una columna añadida a la tabla de corridas después de migrar" "alter table crm.solicitudes_desechadas_corridas add column nota text;" "la tabla crm.solicitudes_desechadas_corridas no tiene la ficha que dejó la migración"
deriva_reversa "un CHECK de las columnas nuevas quitado después de migrar" "alter table crm.inversion_solicitudes drop constraint inversion_solicitud_cancelacion_motivo_valido;" "las columnas cancelacion_motivo/cancelacion_detalle no tienen la ficha que dejó la migración"
deriva_reversa "otra función lee la tabla de corridas (lector directo, no una llamada a las piezas)" "create function private.ensayo_b215_lector_corridas() returns bigint language sql as \$f\$ select count(*) from crm.solicitudes_desechadas_corridas \$f\$;" "lee la tabla de corridas o las columnas nuevas"
deriva_reversa "el job cambiado después de migrar" "select cron.unschedule('crm-solicitudes-desechar'); select cron.schedule('crm-solicitudes-desechar', '1 1 * * *', 'select 1');" "el job crm-solicitudes-desechar no tiene la configuración que dejó la migración"
# RD6–RD11 (ronda 5; Codex r2, P2): lo que la «forma» (nombre/tipo/nulabilidad) de la ronda 4 no veía y la FICHA completa sí.
deriva_reversa "un CHECK añadido a la tabla de corridas después de migrar (el de Codex: tope de canceladas)" "alter table crm.solicitudes_desechadas_corridas add constraint ensayo_b215_corrida_tope check (canceladas_numero_usado + canceladas_sin_movimiento <= limite);" "la tabla crm.solicitudes_desechadas_corridas no tiene la ficha que dejó la migración"
deriva_reversa "un índice añadido a la tabla de corridas después de migrar" "create index ensayo_b215_corridas_corte on crm.solicitudes_desechadas_corridas (corte);" "la tabla crm.solicitudes_desechadas_corridas no tiene la ficha que dejó la migración"
deriva_reversa "un valor por defecto añadido a una columna de la tabla de corridas" "alter table crm.solicitudes_desechadas_corridas alter column duracion_ms set default 0;" "la tabla crm.solicitudes_desechadas_corridas no tiene la ficha que dejó la migración"
deriva_reversa "el comentario de una columna de la tabla de corridas cambiado" "comment on column crm.solicitudes_desechadas_corridas.omitidas is 'otro comentario';" "la tabla crm.solicitudes_desechadas_corridas no tiene la ficha que dejó la migración"
deriva_reversa "una política añadida a la tabla de corridas" "create policy ensayo_b215_lectura on crm.solicitudes_desechadas_corridas for select to authenticated using (true);" "la tabla crm.solicitudes_desechadas_corridas no tiene la ficha que dejó la migración"
deriva_reversa "un valor por defecto puesto a una de las dos columnas nuevas" "alter table crm.inversion_solicitudes alter column cancelacion_motivo set default 'sin_movimiento';" "las columnas cancelacion_motivo/cancelacion_detalle no tienen la ficha que dejó la migración"

echo
echo "RESUMEN: $n derivas · $m mutantes de la migración · $k derivas de la reversa · $fallos fallo(s)"
[[ "$fallos" -eq 0 ]] || exit 1
