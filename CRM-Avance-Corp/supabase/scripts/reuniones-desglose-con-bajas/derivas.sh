#!/usr/bin/env bash
# DERIVAS PREVIAS — la migración se niega si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una deriva rompe el
# catálogo ANTES: lo que se prueba aquí es el PREFLIGHT. `create or replace` conserva dueño y ACL y reemplaza el cuerpo que
# encuentre: sin preflight, un cambio hecho a mano en una de las dos puertas (o en aquello de lo que dependen las reglas
# nuevas) se borraría o se daría por bueno sin que nadie lo viera. Con cada deriva la migración tiene que ABORTAR —con el mensaje que le
# corresponde, no con cualquier error— y dejar la puerta y la pieza nueva EXACTAMENTE como estaban.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Después van los MUTANTES DE LA
# MIGRACIÓN: una copia sin la comparación de las dependencias tiene que dejarse colar el filtro común alterado; una copia sin
# la comparación del registro analítico, la exención con otra huella; una copia sin la ficha de cada puerta, el EXECUTE a
# anon sobre ella; y una copia con la foto de los `assert_*` truncada a 160 caracteres, un gate cuyo primer error cambia
# solo después del carácter 160. Así se sabe que son esas comparaciones, y no otra cosa, las que protegen. Al final, la REVERSA con ese
# mismo gate: tiene que abortar en su postflight, y una reversa con la foto truncada tiene que dejarla pasar.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo ocurre en transacciones con rollback:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/reuniones-desglose-con-bajas/derivas.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/reuniones-desglose-con-bajas
MIG="$(ls supabase/migrations/*_crm_reuniones_desglose_con_bajas.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_reuniones_desglose_con_bajas.sql"; exit 1; }
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
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($1). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}

veredicto() { grep -Eo 'DERIVA (VERDE|ROJO)' "$1" | head -n 1; }
aborto() { grep -m 1 -E '^la migración (ABORTÓ|NO abortó)' "$1" | cut -c1-230; }
veredicto_reversa() { grep -Eo 'REVERSA CON DERIVA (VERDE|ROJO)' "$1" | head -n 1; }
aborto_reversa() { grep -m 1 -E '^la reversa (ABORTÓ|NO abortó)' "$1" | cut -c1-230; }

fallos=0
n=0          # derivas
m=0          # mutantes de la migración
r=0          # ensayos de la reversa

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

deriva() { # deriva <nombre> <sentencia(s) SQL> <texto con el que la migración debe abortar> [preflight|postflight]
  local salida donde="${4:-preflight}"
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
    echo "  ✓ el $donde se negó y no dejó rastro → $(aborto "$salida")"
  else
    echo "  ✗ LA MIGRACIÓN NO SE NEGÓ COMO DEBÍA → $(aborto "$salida")"
    fallos=$((fallos + 1))
  fi
}

PUERTA='crm.metricas_reuniones_fn(date,date)'
AGENDA='crm.metricas_agenda_fn(date,date)'
NO_AUDITADA='la puerta crm.metricas_reuniones_fn no es la auditada'
NO_AUDITADA_AGENDA='la puerta crm.metricas_agenda_fn no es la auditada'
COMENTARIO='tiene un comentario que no tenía al auditarla'
YA_EXISTE='ya existe una private.filtrar_desglose_sujetos_con_bajas_crm o una private.desglose_responsables_reuniones_crm'
DEPENDENCIA='cambió una dependencia'
ANTERIOR_22='es la anterior al bloque 2.2'
REGISTRO='el registro analítico de private.metricas_reuniones_implementacion no es el del bloque 2.2'
FORMA='ya no tienen la forma que lee la regla'
YA='o esta migración ya está aplicada'
RESELLA="update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;"
reemplaza() { # reemplaza <firma> <fragmento> <sustituto> → SQL que re-emite la función con el fragmento cambiado
  printf "do \$d\$ begin execute replace(pg_get_functiondef('%s'::regprocedure), \$v\$%s\$v\$, \$m\$%s\$m\$); end \$d\$;" "$1" "$2" "$3"
}

# D1–D6 — la PUERTA DE REUNIONES no es la auditada: otro cuerpo, un SET añadido, INVOKER, la ACL efectiva (no entra en el md5
# y `create or replace` la conservaría) o un comentario que se escribiría encima sin saberlo.
deriva "la puerta de reuniones tenía otro cuerpo" "$(reemplaza "$PUERTA" "'No autorizado'" "'No autorizado.'")" "$NO_AUDITADA"
deriva "la puerta de reuniones traía otro SET además del search_path" "alter function $PUERTA set lock_timeout = '5s';" "$NO_AUDITADA"
deriva "la puerta de reuniones había pasado a security invoker" "alter function $PUERTA security invoker;" "$NO_AUDITADA"
deriva "anon ya tenía EXECUTE sobre la puerta de reuniones" "grant execute on function $PUERTA to anon;" "$NO_AUDITADA"
deriva "authenticated había perdido el EXECUTE sobre la puerta de reuniones" "revoke execute on function $PUERTA from authenticated;" "$NO_AUDITADA"
deriva "la puerta de reuniones traía un comentario" "comment on function $PUERTA is 'comentario ajeno';" "$COMENTARIO"
# D7–D10 — lo mismo en la PUERTA DE LA AGENDA.
deriva "la puerta de la agenda tenía otro cuerpo" "$(reemplaza "$AGENDA" "'No autorizado'" "'No autorizado.'")" "$NO_AUDITADA_AGENDA"
deriva "la puerta de la agenda traía otro SET además del search_path" "alter function $AGENDA set lock_timeout = '5s';" "$NO_AUDITADA_AGENDA"
deriva "anon ya tenía EXECUTE sobre la puerta de la agenda" "grant execute on function $AGENDA to anon;" "$NO_AUDITADA_AGENDA"
deriva "la puerta de la agenda traía un comentario" "comment on function $AGENDA is 'comentario ajeno';" "$COMENTARIO"
# D11–D12 — ya existe una pieza con uno de los nombres nuevos (ajena, con otra firma).
deriva "ya existía una private.filtrar_desglose_sujetos_con_bajas_crm ajena" \
  "create function private.filtrar_desglose_sujetos_con_bajas_crm(p integer) returns integer language sql immutable as \$f\$ select p \$f\$;" \
  "$YA_EXISTE"
deriva "ya existía una private.desglose_responsables_reuniones_crm ajena" \
  "create function private.desglose_responsables_reuniones_crm(p integer) returns integer language sql immutable as \$f\$ select p \$f\$;" \
  "$YA_EXISTE"
# D13–D18 — una DEPENDENCIA ya no es la auditada: el filtro común (cuyo resultado la pieza genérica conserva tal cual),
# private.rol_crm (quién es efectivo), private.es_lector_global (el control de acceso), la implementación de reuniones (otro
# cuerpo, ni la del 2.2 ni la anterior), la de la agenda o private.vendedor_ids_visibles (el ámbito de la agenda: el subárbol
# del supervisor; auditor de permisos r1, P3-2).
FILTRO_COMUN_DERIVA="$(reemplaza 'private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])' "'Contrato interno de metricas inesperado'" "'Contrato interno de metricas inesperado.'")"
deriva "el filtro común tenía otro cuerpo" "$FILTRO_COMUN_DERIVA" "$DEPENDENCIA"
deriva "private.rol_crm tenía otro cuerpo" \
  "$(reemplaza 'private.rol_crm(uuid)' "'vendedor','supervisor','gerencia','coordinador','directorio'" "'vendedor', 'supervisor','gerencia','coordinador','directorio'")" \
  "$DEPENDENCIA"
deriva "private.es_lector_global tenía otro cuerpo" \
  "$(reemplaza 'private.es_lector_global()' "and p.rol = 'directorio'" "and p.rol = 'directorio' ")" \
  "$DEPENDENCIA"
deriva "la implementación de reuniones tenía otro cuerpo" \
  "$(reemplaza 'private.metricas_reuniones_implementacion(date,date)' "'Periodo invalido'" "'Periodo invalido.'")" \
  "$DEPENDENCIA"
AGENDA_IMPL_DERIVA="$(reemplaza 'private.metricas_agenda_implementacion(date,date)' "'Periodo invalido: maximo 366 dias'" "'Periodo invalido: maximo 366 dias.'")"
deriva "la implementación de la agenda tenía otro cuerpo" "$AGENDA_IMPL_DERIVA" "$DEPENDENCIA"
deriva "private.vendedor_ids_visibles tenía otro cuerpo" \
  "$(reemplaza 'private.vendedor_ids_visibles(uuid)' "-- incluye históricos" "-- incluye historicos")" \
  "$DEPENDENCIA"
# D19 — la implementación de reuniones NO es la del bloque 2.2 sino la ANTERIOR (el 2.12 va encima del 2.2).
deriva "la implementación de reuniones era la anterior al bloque 2.2" \
  "$(reemplaza 'private.metricas_reuniones_implementacion(date,date)' '(ce.debio_ocurrir or ce.realizada) as metrica_debio_ocurrir' 'ce.debio_ocurrir as metrica_debio_ocurrir')" \
  "$ANTERIOR_22"
# D20–D21 — el registro analítico de la implementación no es el que dejó el 2.2: otra huella (re-sellada) o el sello distinto.
EXENCION_DERIVA="update private.analitica_leads_citas_exenciones set huella = md5('otra') where objeto = 'private.metricas_reuniones_implementacion(date,date)'; $RESELLA"
deriva "la exención de la implementación tenía otra huella, con la lista re-sellada" "$EXENCION_DERIVA" "$REGISTRO"
deriva "el sello no coincidía con la lista" "update private.analitica_lc_sello set sello = md5('x') where id;" "$REGISTRO"
# D22–D23 — la forma que lee la regla: `crm.equipo.activo` admite nulos («is false» dejaría de decir «de baja»), o la ficha ya
# no está atada a su perfil del Portal (sin la FK, la regla del suspendido leería un perfil que podría no existir).
deriva "crm.equipo.activo admitía nulos" "alter table crm.equipo alter column activo drop not null;" "$FORMA"
deriva "crm.equipo ya no tenía la FK a public.perfiles" "alter table crm.equipo drop constraint equipo_perfil_id_fkey;" "$FORMA"
# D24 — la migración YA está aplicada: reaplicarla se niega.
deriva "la migración ya estaba aplicada (reaplicar se niega)" "-- @@MIGRACION@@" "$YA"

# D25 — una deriva del POSTFLIGHT: la foto de los `private.assert_*()` compara el texto ENTERO del primer error. Se siembra
# (solo en el ensayo; se deshace con el rollback) un gate cuyo primer error es FIJO hasta pasado el carácter 160 y después
# lleva la huella del cuerpo de la puerta de reuniones, que la migración cambia (ca480bc7… → e448db0c…) y la reversa devuelve.
# La migración íntegra tiene que ABORTAR en su postflight; con la foto truncada a 160 entraría (mutante de abajo). Ningún
# `assert_*` real se toca, y el gate no nombra las piezas nuevas (la reversa se negaría antes, por otra razón).
FOTO_DISTINTA='algún private.assert_*() da otro resultado que antes de la migración'
FOTO_DISTINTA_REVERSA='algún private.assert_*() da otro resultado que antes de revertir'
GATE_LARGO="$(cat <<'SQL'
-- Gate sembrado SOLO en el ensayo (se deshace con el rollback). Su primer error es fijo hasta pasado el carácter 160 y
-- después lleva la huella del cuerpo de crm.metricas_reuniones_fn, que la migración cambia.
create function private.assert_zz_ensayo_texto_largo() returns text
language plpgsql stable set search_path = '' as $zz$
begin
  raise exception 'ENSAYO 2.12 (gate sembrado solo en el ensayo; se deshace con el rollback): este texto es fijo hasta pasado el caracter 160 de la foto, para que una foto truncada a 160 caracteres lo diera por identico aunque el resto cambie. Solo a partir de aqui cambia: cuerpo de la puerta = %',
    (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.metricas_reuniones_fn(date,date)'::regprocedure);
end
$zz$;
SQL
)"
deriva "un gate (sembrado) cuyo primer error cambia solo después del carácter 160: la foto íntegra lo ve" \
  "$GATE_LARGO" "$FOTO_DISTINTA" postflight

# ── MUTANTES DE LA MIGRACIÓN ──────────────────────────────────────────────────────────────────────────────────────────
juzgar_mutante() { # juzgar_mutante <salida>: la deriva instalada tiene que haberse COLADO (la migración mutada entró)
  local salida="$1"
  if ! grep -q 'DERIVA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$salida")" == "DERIVA ROJO" ]] && grep -q '^la migración NO abortó' "$salida"; then
    echo "  ✓ el mutante muere: sin esa comparación, la deriva se coló (la migración entró). Es esa comparación la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: la migración mutada abortó igualmente → $(aborto "$salida")"
    fallos=$((fallos + 1))
  fi
}

mutante_preflight() { # mutante_preflight <nombre> <deriva SQL> <texto esperado si el preflight fuera el bueno> <patrón python a quitar>...
  local nombre="$1" sql="$2" espera="$3" archivo
  shift 3
  m=$((m + 1))
  archivo="$TMP/mp-$m.sql"
  echo "M$m. Mutante de la migración: $nombre"
  if python3 - "$MIG" "$TMP/mig-mutada-$m.sql" "$@" <<'PY'
import sys, re
origen, destino, *patrones = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
for patron in patrones:
    nuevo, k = re.subn(patron, '', sql, count=1, flags=re.S)
    if k != 1 or re.search(patron, nuevo, flags=re.S):
        sys.exit('MUTANTE DE LA MIGRACIÓN NO APLICABLE: el bloque no aparece exactamente una vez: %s' % patron[:70])
    sql = nuevo
open(destino, 'w', encoding='utf-8').write(sql)
PY
  then
    printf '%s\n' "$sql" > "$TMP/mp-$m.deriva.sql"
    node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-mutada-$m.sql" --deriva "$TMP/mp-$m.deriva.sql" \
      --espera "$espera" > "$archivo" || exit 1
    corre "$archivo"
    juzgar_mutante "${archivo%.sql}.salida.txt"
  else
    echo "  ✗ no se pudo construir el mutante de la migración"
    fallos=$((fallos + 1))
  fi
}

# Sustituye, en una copia, la foto ÍNTEGRA de los assert_* por la truncada a 160, en sus DOS apariciones.
foto_truncada() { # foto_truncada <origen> <destino>
  python3 - "$1" "$2" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
integra = "v := 'cae: ' || sqlstate || ' ' || sqlerrm;"
truncada = r"v := 'cae: ' || left(replace(sqlerrm, E'\n', ' '), 160);"
if sql.count(integra) != 2:
    sys.exit('MUTANTE DE LA FOTO NO APLICABLE: la foto íntegra aparece %d veces en %s (debían ser 2)' % (sql.count(integra), origen))
open(destino, 'w', encoding='utf-8').write(sql.replace(integra, truncada))
PY
}

# Cada comparación del preflight de dependencias tiene su eco en el postflight (segunda red): para demostrar que son ESAS
# comparaciones las que protegen hay que quitar las dos.
mutante_preflight "SIN comparar las dependencias (ni en el preflight ni en el postflight): el filtro común alterado se cuela" \
  "$FILTRO_COMUN_DERIVA" \
  "$DEPENDENCIA" \
  "  select string_agg\(e\.objeto, ', ' order by e\.objeto\) into v_distintas.*?revisar antes de aplicar', v_distintas;\n  end if;\n" \
  "  select string_agg\(e\.objeto, ', ' order by e\.objeto\) into v_distintas.*?no debía tocar: %', v_distintas;\n  end if;\n"
mutante_preflight "SIN comparar el registro analítico del 2.2: la exención con otra huella se cuela" \
  "$EXENCION_DERIVA" \
  "$REGISTRO" \
  "  if \(select e\.huella from private\.analitica_leads_citas_exenciones e where e\.objeto = v_impl\).*?revisar antes de aplicar';\n  end if;\n"
mutante_preflight "SIN la ficha de la puerta de reuniones: el EXECUTE a anon se cuela (create or replace lo conservaría)" \
  "grant execute on function $PUERTA to anon;" \
  "$NO_AUDITADA" \
  "  if v_ficha is distinct from 'ca480bc7.*?revisar antes de re-emitirla', v_ficha;\n  end if;\n"
mutante_preflight "SIN la ficha de la puerta de la agenda: el EXECUTE a anon se cuela (create or replace lo conservaría)" \
  "grant execute on function $AGENDA to anon;" \
  "$NO_AUDITADA_AGENDA" \
  "  if v_ficha is distinct from '104d863b.*?revisar antes de re-emitirla', v_ficha;\n  end if;\n"

m=$((m + 1))
echo "M$m. Mutante de la foto: una copia de la migración con la foto de los assert_* TRUNCADA a 160 tiene que dejar entrar el gate de D25"
if foto_truncada "$MIG" "$TMP/mig-mutada-$m.sql"; then
  printf '%s\n' "$GATE_LARGO" > "$TMP/mp-$m.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-mutada-$m.sql" --deriva "$TMP/mp-$m.deriva.sql" \
    --espera "$FOTO_DISTINTA" > "$TMP/mp-$m.sql" || exit 1
  corre "$TMP/mp-$m.sql"
  juzgar_mutante "$TMP/mp-$m.salida.txt"
else
  echo "  ✗ no se pudo construir el mutante de la foto"
  fallos=$((fallos + 1))
fi

# ── LA REVERSA, con el mismo gate de D25 ──────────────────────────────────────────────────────────────────────────────
r=$((r + 1))
echo "R$r. Reversa con el gate de D25 sembrado: tiene que abortar en su postflight y no dejar rastro"
printf '%s\n' "$GATE_LARGO" > "$TMP/r$r.deriva.sql"
node "$DIR/armar-ensayo.mjs" --reversa-con-deriva "$TMP/r$r.deriva.sql" --espera "$FOTO_DISTINTA_REVERSA" > "$TMP/r$r.sql" || exit 1
corre "$TMP/r$r.sql"
if ! grep -q 'DERIVA_INSTALADA' "$TMP/r$r.salida.txt"; then
  echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/r$r.salida.txt" | cut -c1-200)"
  fallos=$((fallos + 1))
elif [[ "$(veredicto_reversa "$TMP/r$r.salida.txt")" == "REVERSA CON DERIVA VERDE" ]]; then
  echo "  ✓ la reversa se negó en su postflight y no dejó rastro → $(aborto_reversa "$TMP/r$r.salida.txt")"
else
  echo "  ✗ LA REVERSA NO SE NEGÓ COMO DEBÍA → $(aborto_reversa "$TMP/r$r.salida.txt")"
  fallos=$((fallos + 1))
fi

r=$((r + 1))
echo "R$r. Mutante de la reversa: con la foto TRUNCADA a 160, la reversa revierte pese al gate de D25"
if foto_truncada "$DIR/reversa.sql" "$TMP/reversa-truncada.sql"; then
  printf '%s\n' "$GATE_LARGO" > "$TMP/r$r.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --reversa-con-deriva "$TMP/r$r.deriva.sql" --espera "$FOTO_DISTINTA_REVERSA" \
    --reversa-archivo "$TMP/reversa-truncada.sql" > "$TMP/r$r.sql" || exit 1
  corre "$TMP/r$r.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/r$r.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/r$r.salida.txt" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto_reversa "$TMP/r$r.salida.txt")" == "REVERSA CON DERIVA ROJO" ]] && grep -q '^la reversa NO abortó' "$TMP/r$r.salida.txt"; then
    echo "  ✓ el mutante muere: con la foto truncada, la reversa revirtió pese al gate. Es la foto íntegra la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: la reversa truncada abortó igualmente → $(aborto_reversa "$TMP/r$r.salida.txt")"
    fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir el mutante de la reversa"
  fallos=$((fallos + 1))
fi

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: las $n abortan ($((n - 1)) en el preflight, 1 en el postflight) y no dejan rastro; el control entra; los $m mutantes de la migración mueren; la reversa aborta con el gate sembrado y su mutante de la foto truncada muere."
  exit 0
fi
echo "DERIVAS: $fallos sin el veredicto esperado — el preflight, el postflight o la reversa no protegen lo que dicen."
exit 1
