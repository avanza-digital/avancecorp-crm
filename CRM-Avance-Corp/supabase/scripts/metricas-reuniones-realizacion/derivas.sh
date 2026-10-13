#!/usr/bin/env bash
# DERIVAS PREVIAS — la migración se niega si el catálogo o el registro analítico ya no son los auditados.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una deriva rompe el
# catálogo o el registro ANTES: lo que se prueba aquí es el PREFLIGHT de la migración. `create or replace` conserva dueño y
# ACL y reemplaza el cuerpo que encuentre; el re-sellado actualiza la huella de la exención «de lo que haya». Sin preflight,
# un cambio hecho a mano en `private.metricas_reuniones_implementacion`, en el núcleo `private.citas_episodios`, en la
# exención o en el sello se borraría o se daría por bueno sin que nadie lo viera. Con cada deriva la migración tiene que
# ABORTAR en su preflight —con el mensaje que le corresponde, no con cualquier error— y dejar la función, su ACL, su
# comentario, la exención y el sello EXACTAMENTE como estaban.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Sin él, un envoltorio roto daría
# «abortó» siempre. Después van los MUTANTES DE LA MIGRACIÓN: una copia sin la comparación del sello previo tiene que
# dejarse colar la deriva «sello distinto» (y sobrescribirlo); una copia sin la comparación de las fuentes tiene que dejarse
# colar el núcleo alterado; y una copia con la foto de los `assert_*` truncada a 160 caracteres (la de la ronda 1) tiene que
# dejarse colar un gate cuyo primer error cambia solo después del carácter 160 (deriva D14, que la migración íntegra rechaza
# en su POSTFLIGHT). Así se sabe que son esas comparaciones, y no otra cosa, las que protegen. Al final, la REVERSA con la
# misma deriva D14: tiene que abortar en su postflight, y una reversa con la foto truncada tiene que dejarla pasar.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo ocurre en transacciones que terminan en
# rollback:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/metricas-reuniones-realizacion/derivas.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin ella van a una carpeta temporal que se
# borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/metricas-reuniones-realizacion
MIG="$(ls supabase/migrations/*_crm_realizacion_cuenta_anticipada.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_realizacion_cuenta_anticipada.sql"; exit 1; }
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
  # La marca separa «la deriva no se pudo instalar» (no se juzga) de «la migración se negó». El veredicto VERDE lo da el
  # propio ensayo: abortó con el texto esperado (del preflight, o del postflight en D14) Y la foto (cuerpo, ACL, comentario,
  # exención y sello) es idéntica a la de antes de intentar la migración.
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

F='private.metricas_reuniones_implementacion(date,date)'
OBJ="'private.metricas_reuniones_implementacion(date,date)'"
CUERPO='el cuerpo de private.metricas_reuniones_implementacion no es el auditado'
DEFINICION='la definición de private.metricas_reuniones_implementacion no es la auditada'
FICHA='la ficha de private.metricas_reuniones_implementacion no es la auditada'
COMENTARIO='el comentario de private.metricas_reuniones_implementacion cambió'
FUENTES='cambió una fuente de la que depende este cambio'
EXENCION='la exención analítica de private.metricas_reuniones_implementacion no es la auditada'
SELLO='el sello previo de la lista de exenciones no coincide'
YA='o esta migración ya está aplicada'
RESELLA="update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;"

# D1 — el CUERPO ya no es el auditado (md5 de `prosrc` distinto, aunque sea por un punto en un mensaje).
deriva "la función tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('$F'::regprocedure), 'Periodo invalido', 'Periodo invalido.'); end \$d\$;" \
  "$CUERPO"

# D2, D3 y D4 — el cuerpo es el mismo pero la DEFINICIÓN no: un `SET` añadido, INVOKER o VOLATILE (md5 de `pg_get_functiondef` distinto).
deriva "la función traía otro SET además del search_path" \
  "alter function $F set lock_timeout = '5s';" \
  "$DEFINICION"
deriva "la función había pasado a security invoker" \
  "alter function $F security invoker;" \
  "$DEFINICION"
deriva "la función había pasado a VOLATILE" \
  "alter function $F volatile;" \
  "$DEFINICION"

# D5 — la ACL no es la auditada (no entra en el md5): authenticated con EXECUTE. `create or replace` lo conservaría.
deriva "authenticated ya tenía EXECUTE sobre la implementación" \
  "grant execute on function $F to authenticated;" \
  "$FICHA"

# D6 — el comentario ya no es el auditado: el nuevo se escribiría encima sin saberlo.
deriva "la función traía otro comentario" \
  "comment on function $F is 'comentario ajeno';" \
  "$COMENTARIO"

# D7 — el NÚCLEO del que se componen las banderas ya no es el auditado.
NUCLEO_DERIVA="do \$d\$ begin execute replace(pg_get_functiondef('private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'::regprocedure), 'coalesce(t.modalidad_reunion, ''sin_clasificar'')', 'coalesce(t.modalidad_reunion,  ''sin_clasificar'')'); end \$d\$;"
deriva "el núcleo private.citas_episodios tenía otro cuerpo" \
  "$NUCLEO_DERIVA" \
  "$FUENTES"

# D8 — la pieza que normaliza la huella (`contadores_crudos_leads_citas`) ya no es la auditada: la huella que se escribiría
# no sería comparable con la que el censo calcula.
deriva "private.contadores_crudos_leads_citas tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.contadores_crudos_leads_citas()'::regprocedure), 'order by 3, 4, 1, 2;', 'order by 3, 4, 1, 2 ;'); end \$d\$;" \
  "$FUENTES"

# D9, D10 y D11 — el registro analítico no es el revisado: huella distinta sin re-sellar, huella distinta re-sellada,
# razón distinta re-sellada. (Borrar la exención no se puede ensayar como deriva: la propia tabla lo rechaza con su candado
# «Una exencion no se borra por fuera: se retira en una migracion que re-selle la lista», medido el 07/10/2026.)
deriva "la exención tenía otra huella (sin re-sellar)" \
  "update private.analitica_leads_citas_exenciones set huella = md5('otra') where objeto = $OBJ;" \
  "$EXENCION"
HUELLA_RESELLADA="update private.analitica_leads_citas_exenciones set huella = md5('otra') where objeto = $OBJ; $RESELLA"
deriva "la exención tenía otra huella, con la lista re-sellada" \
  "$HUELLA_RESELLADA" \
  "$EXENCION"
deriva "la exención tenía otra razón, con la lista re-sellada" \
  "update private.analitica_leads_citas_exenciones set razon = razon || ' (editada)' where objeto = $OBJ; $RESELLA" \
  "$EXENCION"

# D12 — el sello no coincide con la lista (alguien relavó la lista sin re-sellar, o tocó el sello).
SELLO_DISTINTO="update private.analitica_lc_sello set sello = md5('x') where id;"
deriva "el sello no coincidía con la lista" \
  "$SELLO_DISTINTO" \
  "$SELLO"

# D13 — la migración YA está aplicada: reaplicarla se niega.
deriva "la migración ya estaba aplicada (reaplicar se niega)" \
  "-- @@MIGRACION@@" \
  "$YA"

# D14 — una deriva del POSTFLIGHT: la foto de los `private.assert_*()` compara el texto ENTERO del primer error. Se siembra
# (solo en el ensayo; se deshace con el rollback) un gate cuyo primer error es FIJO hasta pasado el carácter 160 y después
# lleva la huella que la exención analítica guarda para la función, que la migración cambia (4b28cc41… → d54d4f87…). La
# migración íntegra tiene que ABORTAR en su postflight («algún private.assert_*() da otro resultado…») y no dejar rastro.
# Con la foto truncada a 160 (la de la ronda 1) entraría: ese es el mutante de abajo. Ningún `assert_*` real se toca.
FOTO_DISTINTA='algún private.assert_*() da otro resultado que antes de la migración'
FOTO_DISTINTA_REVERSA='algún private.assert_*() da otro resultado que antes de revertir'
GATE_LARGO="$(cat <<'EOF'
-- Gate sembrado SOLO en el ensayo (se deshace con el rollback). Su primer error es fijo hasta pasado el carácter 160 y
-- después lleva la huella de la exención analítica de private.metricas_reuniones_implementacion, que la migración cambia.
create function private.assert_zz_ensayo_texto_largo() returns text
language plpgsql stable set search_path = '' as $zz$
begin
  raise exception 'ENSAYO RONDA 2 (gate sembrado solo en el ensayo; se deshace con el rollback): este texto es fijo hasta pasado el caracter 160 de la foto, para que una foto truncada a 160 caracteres lo diera por identico aunque el resto cambie. Solo a partir de aqui cambia: huella de la exencion = %',
    (select e.huella from private.analitica_leads_citas_exenciones e
      where e.objeto = 'private.metricas_reuniones_implementacion(date,date)');
end
$zz$;
EOF
)"
deriva "un gate (sembrado) cuyo primer error cambia solo después del carácter 160: la foto íntegra lo ve" \
  "$GATE_LARGO" \
  "$FOTO_DISTINTA" \
  postflight

# ── MUTANTES DE LA MIGRACIÓN ──────────────────────────────────────────────────────────────────────────────────────────
# Cada comparación del preflight tiene su eco en el postflight (segunda red): para demostrar que son ESAS comparaciones las
# que protegen hay que quitar las dos; si solo se quita la del preflight, la del postflight aborta igual (medido el
# 07/10/2026 con las fuentes). El tercer mutante no quita: SUSTITUYE la foto íntegra por la truncada a 160 (en el preflight y
# en el postflight) y tiene que dejarse colar el gate de D14.
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
  echo "M$m. Mutante del preflight: $nombre"
  if python3 - "$MIG" "$TMP/mig-mutada-$m.sql" "$@" <<'PY'
import sys, re
origen, destino, *patrones = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
for patron in patrones:
    nuevo, k = re.subn(patron, '', sql, count=1, flags=re.S)
    if k != 1 or re.search(patron, nuevo, flags=re.S):
        sys.exit('MUTANTE DEL PREFLIGHT NO APLICABLE: el bloque no aparece exactamente una vez: %s' % patron[:70])
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
    echo "  ✗ no se pudo construir el mutante del preflight"
    fallos=$((fallos + 1))
  fi
}

# Sustituye, en una copia del archivo, la foto ÍNTEGRA de los assert_* por la truncada a 160 (la de la ronda 1), en sus
# DOS apariciones (preflight y postflight). Vale para la migración y para la reversa.
foto_truncada() { # foto_truncada <origen> <destino>
  python3 - "$1" "$2" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
integra = "v := 'cae: ' || sqlstate || ' ' || sqlerrm;"
truncada = r"v := 'cae: ' || left(replace(sqlerrm, E'\n', ' '), 160);"
if sql.count(integra) != 2:
    sys.exit('MUTANTE DE LA FOTO NO APLICABLE: la foto íntegra aparece %d veces en %s (debían ser 2: preflight y postflight)' % (sql.count(integra), origen))
open(destino, 'w', encoding='utf-8').write(sql.replace(integra, truncada))
PY
}

mutante_preflight "una copia de la migración SIN comparar el sello previo tiene que dejar entrar (y sobrescribir) el sello distinto" \
  "$SELLO_DISTINTO" \
  "$SELLO" \
  "  if \(select s\.sello from private\.analitica_lc_sello s where s\.id\)\n       is distinct from private\.huella_exenciones_analitica_lc\(\) then\n    raise exception 'PREFLIGHT.*?\n  end if;\n"
mutante_preflight "una copia de la migración SIN comparar las fuentes (en el preflight ni en el postflight) tiene que dejar entrar el núcleo alterado" \
  "$NUCLEO_DERIVA" \
  "$FUENTES" \
  "  -- 3\. Las fuentes de las que depende el cambio.*?revisar antes de re-emitir';\n  end if;\n" \
  "  -- Lo que no se toca, intacto\.\n  if \(select md5\(p\.prosrc\) from pg_proc p where p\.oid = to_regprocedure\('private\.citas_episodios\(timestamptz,timestamptz,timestamptz\)'\)\).*?no debía tocar \(private\.citas_episodios.*?\)';\n  end if;\n"

m=$((m + 1))
echo "M$m. Mutante de la foto: una copia de la migración con la foto de los assert_* TRUNCADA a 160 tiene que dejar entrar el gate de D14"
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

# ── LA REVERSA, con la misma deriva D14 ───────────────────────────────────────────────────────────────────────────────
# Aplicar → sembrar el gate → intentar la reversa: su foto íntegra ve que el texto del gate cambia (d54d4f87… → 4b28cc41…)
# y ABORTA en su postflight sin dejar rastro. Una reversa con la foto truncada a 160 tiene que dejarlo pasar (revierte).
r=$((r + 1))
echo "R$r. Reversa con el gate de D14 sembrado: tiene que abortar en su postflight y no dejar rastro"
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
echo "R$r. Mutante de la reversa: con la foto TRUNCADA a 160, la reversa revierte pese al gate de D14"
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
