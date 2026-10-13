#!/usr/bin/env bash
# MUTANTES del ensayo — por cada defensa, un mutante que la neutraliza.
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe la regla a propósito y se exige que el oráculo
# (`pruebas.sql`) lo GRITE: si un mutante sobrevive —el ensayo sigue verde con la defensa quitada—, esa defensa NO está
# probada y este guion falla.
#
# Hay cuatro clases:
#   · de CUERPO: la migración real con UN fragmento cambiado en `private.metricas_reuniones_implementacion` (o en el núcleo
#     `private.citas_episodios`). Se instala DESPUÉS de la migración (cuyo postflight sella el cuerpo bueno) y antes del
#     oráculo, en la misma transacción, que termina en rollback. Cada fragmento tiene que aparecer EXACTAMENTE las veces que
#     se declara: si la migración cambia, el mutante se niega a mutar otra cosa sin que nadie se entere. El mutante de
#     cuerpo RE-SELLA la huella analítica para el cuerpo mutado (imita una migración alternativa completa): así muere por
#     su comportamiento, no por el sello. El sello lo prueba aparte el mutante de la MIGRACIÓN.
#   · de la MIGRACIÓN: una copia de la migración sin el bloque de re-sellado y sin su propio control del re-sellado. La
#     migración entra; el oráculo tiene que detectar que la exención y el sello ya no corresponden al cuerpo vivo.
#   · de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha (INVOKER, search_path, VOLATILE, permisos).
#   · EQUIVALENTES: un fragmento cambiado que, en ejecución, NO puede cambiar lo que hace la función. Aquí la expectativa se
#     invierte: el ensayo tiene que seguir VERDE, y eso documenta que la defensa es redundante, no que esté sin probar.
#
# Un mutante solo cuenta como MUERTO si el ensayo sale ROJO y además nombra los fallos que le corresponden (el caso y su
# motivo). Un rojo por otra causa —un error de montaje— no prueba la defensa que ese mutante rompe. Algunos mutantes exigen
# además que un fallo NO aparezca (p. ej. «solo el divisor del resumen»: el resumen tiene que seguir bien y los cortes mal).
#
# (Lo que se rompe ANTES de la migración —la deriva de catálogo o de registro que su preflight tiene que rechazar— va en
# `derivas.sh`.)
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/metricas-reuniones-realizacion/mutantes.sh
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

F='private.metricas_reuniones_implementacion(date,date)'
NUCLEO='private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'

corre() { # corre <archivo.sql> → deja la salida completa en <archivo>.salida.txt
  local codigo
  # shellcheck disable=SC2086  # EJECUTAR_SQL es un comando con sus argumentos
  $EJECUTAR_SQL "$1" > "${1%.sql}.salida.txt" 2>&1
  codigo=$?
  # 9 = el ejecutor del laboratorio comparó la base antes y después y CAMBIÓ.
  # Un ensayo no escribe: se para todo y se avisa, no se sigue mutando.
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($1). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}

veredicto() { grep -Eo 'ENSAYO (VERDE|ROJO)[^:]*' "$1" | head -n 1; }

fallos=0
equivalentes=0
n=0
NO_DEBE=()   # fallos que el mutante en curso NO puede nombrar (se vacía en cada mutante)

echo "0. El ensayo sin mutar debe estar VERDE"
node "$DIR/armar-ensayo.mjs" > "$TMP/base.sql" || exit 1
corre "$TMP/base.sql"
v="$(veredicto "$TMP/base.salida.txt")"
if [[ "$v" == *"VERDE"* ]]; then
  echo "  ✓ base → $v"
else
  echo "  ✗ base → ${v:-sin veredicto} (arreglar el ensayo antes de mutar)"
  fallos=$((fallos + 1))
fi

nombra() { # nombra <salida> <prefijo> → ¿alguna línea empieza por «FALLO <prefijo>»? (comparación literal)
  awk -v p="FALLO $2" 'index($0, p) == 1 { ok = 1 } END { exit ok ? 0 : 1 }' "$1"
}

juzgar_salida() { # juzgar_salida <salida> <marca de instalación> <fallo que debe nombrar>...
  local salida="$1" marca="$2" v nombrados debe faltan="" sobran=""
  shift 2
  v="$(veredicto "$salida")"
  nombrados="$(grep -Eo '^FALLO [^:]+' "$salida" | sort -u | tr '\n' ';' | sed 's/;$//; s/;/ · /g')"
  for debe in "$@"; do
    nombra "$salida" "$debe" || faltan="$faltan «FALLO ${debe}»"
  done
  for debe in "${NO_DEBE[@]+"${NO_DEBE[@]}"}"; do
    nombra "$salida" "$debe" && sobran="$sobran «FALLO ${debe}»"
  done
  NO_DEBE=()
  # La marca separa «el mutante no se pudo instalar» (no se juzga: cuenta como superviviente) de «el oráculo lo detectó».
  if ! grep -q "$marca" "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$v" != *"ROJO"* ]]; then
    echo "  ✗ MUTANTE SUPERVIVIENTE: ${v:-sin veredicto}"
    fallos=$((fallos + 1))
  elif [[ -n "$faltan" ]]; then
    # Rojo, pero por otra cosa: la defensa que este mutante rompe sigue sin prueba.
    echo "  ✗ ROJO SIN NOMBRAR SU FALLO (falta$faltan): $v: $nombrados"
    fallos=$((fallos + 1))
  elif [[ -n "$sobran" ]]; then
    echo "  ✗ ROJO PERO NOMBRA UN FALLO QUE NO DEBÍA (sobra$sobran): $v: $nombrados"
    fallos=$((fallos + 1))
  else
    echo "  ✓ muere por su fallo ($v): $nombrados"
  fi
}

juzgar() { # juzgar <fallo que debe nombrar>... → arma, corre y juzga $TMP/m$n.mutante.sql
  if [[ "$#" -eq 0 ]]; then
    echo "  ✗ el mutante no declara por qué fallo tiene que morir"
    fallos=$((fallos + 1))
    NO_DEBE=()
    return
  fi
  node "$DIR/armar-ensayo.mjs" --mutante "$TMP/m$n.mutante.sql" > "$TMP/m$n.sql" || exit 1
  corre "$TMP/m$n.sql"
  juzgar_salida "$TMP/m$n.salida.txt" 'MUTANTE_INSTALADO' "$@"
}

FRAGS=()
frag() { # frag <firma> <fragmento vigente> <fragmento mutado> [veces]
  FRAGS+=("$1" "$2" "$3" "${4:-1}")
}

# Construye el SQL del mutante de cuerpo con los fragmentos acumulados en FRAGS, y re-sella la huella analítica para el
# cuerpo mutado (la exención y el sello quedan coherentes con lo mutado: el mutante muere por su comportamiento).
construye() { # construye <archivo de salida> [sin-resellar]
  python3 - "$1" "${2:-resellar}" "${FRAGS[@]}" <<'PY'
import sys
salida, resellar, *resto = sys.argv[1:]
assert len(resto) % 4 == 0, 'fragmentos mal formados'
sql = []
for i in range(0, len(resto), 4):
    firma, vigente, mutado, veces = resto[i:i + 4]
    for t in ('$vigente$', '$mutado$', '$mutar$'):
        assert t not in vigente and t not in mutado, 'la etiqueta %s aparece en un fragmento' % t
    sql.append("""do $mutar$
declare
  v_def text;
  v_veces integer;
begin
  v_def := pg_get_functiondef('%s'::regprocedure);
  v_veces := (length(v_def) - length(replace(v_def, $vigente$%s$vigente$, ''))) / length($vigente$%s$vigente$);
  if v_veces <> %s then
    raise exception 'MUTANTE NO APLICABLE: el fragmento aparece %% veces en %s (debían ser %s)', v_veces;
  end if;
  execute replace(v_def, $vigente$%s$vigente$, $mutado$%s$mutado$);
end;
$mutar$;
""" % (firma, vigente, vigente, veces, firma, veces, vigente, mutado))
if resellar == 'resellar':
    sql.append(r"""do $resellar$
begin
  update private.analitica_leads_citas_exenciones e
     set huella = (select md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
                     from pg_proc p where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure)
   where e.objeto = 'private.metricas_reuniones_implementacion(date,date)';
  update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;
end;
$resellar$;
""")
open(salida, 'w', encoding='utf-8').write('\n'.join(sql))
PY
}

mutante() { # mutante <nombre> <fallo que debe nombrar>...   (usa los fragmentos de FRAGS)
  n=$((n + 1))
  echo "$n. Mutante: $1"
  if ! construye "$TMP/m$n.mutante.sql"; then
    echo "  ✗ no se pudo construir el mutante"
    fallos=$((fallos + 1))
    FRAGS=()
    NO_DEBE=()
    return
  fi
  FRAGS=()
  juzgar "${@:2}"
}

# El mutante de SQL libre (catálogo o núcleo). Tiene que morir NOMBRANDO su fallo.
mutante_sql() { # mutante_sql <nombre> <sentencia SQL> <fallo que debe nombrar>...
  n=$((n + 1))
  echo "$n. Mutante: $1"
  printf '%s\n' "$2" > "$TMP/m$n.mutante.sql"
  juzgar "${@:3}"
}

# Un EQUIVALENTE no se puede matar. Se exige que el ensayo siga VERDE; si deja de serlo, el mutante ya no es equivalente
# y hay que mirarlo.
equivalente() { # equivalente <nombre> <por qué>   (usa los fragmentos de FRAGS)
  local archivo salida v
  n=$((n + 1))
  echo "$n. Equivalente: $1"
  construye "$TMP/m$n.mutante.sql" || { echo "  ✗ no se pudo construir"; fallos=$((fallos + 1)); FRAGS=(); return; }
  FRAGS=()
  archivo="$TMP/m$n.sql"; salida="$TMP/m$n.salida.txt"
  node "$DIR/armar-ensayo.mjs" --mutante "$TMP/m$n.mutante.sql" > "$archivo" || exit 1
  corre "$archivo"
  v="$(veredicto "$salida")"
  if ! grep -q 'MUTANTE_INSTALADO' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$v" == *"VERDE"* ]]; then
    echo "  ≈ EQUIVALENTE CONFIRMADO ($v): $2"
    equivalentes=$((equivalentes + 1))
  else
    echo "  ✗ YA NO ES EQUIVALENTE ($v): $(grep -Eo '^FALLO [^:]+' "$salida" | sort -u | tr '\n' ';')"
    fallos=$((fallos + 1))
  fi
}

# ── Fragmentos vigentes de la función (los que deja la migración, tal como los devuelve pg_get_functiondef) ──────────
LINEA_NUEVA=$'      (ce.debio_ocurrir or ce.realizada) as metrica_debio_ocurrir,'
LINEA_VIEJA=$'      ce.debio_ocurrir as metrica_debio_ocurrir,'
# El conteo de «debieron ocurrir» del RESUMEN (la secuencia «select count(*)::int as pactadas,» solo está en la CTE resumen;
# los cortes empiezan por «select modalidad,», «select origen,» y «select vendedor_id,»).
RESUMEN_DEBIERON=$'select count(*)::int as pactadas,\n      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,'

# M1 — el CAMBIO REVERTIDO: vuelve `ce.debio_ocurrir` a secas. Es el defecto medido por el ROJO.
frag "$F" "$LINEA_NUEVA" "$LINEA_VIEJA"
mutante "el cambio revertido (la realizada anticipada vuelve a quedar fuera del divisor)" \
  "1-resumen-divisor" "1-responsable-A" "1-modalidad-virtual" "1-origen-web" "2-analista-sola-anticipada" "5-mes-ventana" "9-contrato-app"

# M2 — `or` aplicado también a las CANCELADAS: una cancelada futura entraría al divisor (y la del sistema, a las exclusiones).
frag "$F" "$LINEA_NUEVA" $'      (ce.debio_ocurrir or ce.realizada or ce.cancelada_asesor or ce.cancelada_sistema) as metrica_debio_ocurrir,'
mutante "«or ce.realizada» aplicado también a las canceladas (una cancelada futura entra al divisor)" \
  "4-futuras-fuera" "4-canceladas-asesor-vencidas" "1-resumen-divisor" "1-modalidad-sin_clasificar"

# M2b — aplicado también a las REPROGRAMADAS: una reprogramada futura entraría a las exclusiones del divisor.
frag "$F" "$LINEA_NUEVA" $'      (ce.debio_ocurrir or ce.realizada or ce.reprogramada) as metrica_debio_ocurrir,'
mutante "«or ce.realizada» aplicado también a las reprogramadas (una reprogramada futura entra al divisor)" \
  "4-futuras-fuera" "1-resumen-divisor" "1-modalidad-sin_clasificar"

# M2c — aplicado también a las PENDIENTES futuras: una cita por venir entraría al divisor.
frag "$F" "$LINEA_NUEVA" $'      (ce.debio_ocurrir or ce.realizada or ce.programada_futura) as metrica_debio_ocurrir,'
mutante "«or ce.realizada» aplicado también a las pendientes futuras (una cita por venir entra al divisor)" \
  "4-futuras-fuera" "1-resumen-divisor" "1-modalidad-sin_clasificar"

# M3 — la bandera del NÚCLEO cambiada en vez de la de la métrica: la métrica da lo mismo, pero `citas_episodios.debio_ocurrir`
# pasa a ser verdadera para la anticipada y los informes de conversiones («cita real» = realizada y debió ocurrir) cambiarían.
# Se revierte la línea de la métrica (como si el cambio no se hubiera hecho ahí) y se muta el núcleo; la métrica queda igual,
# así que los fallos de la métrica NO pueden aparecer.
frag "$F" "$LINEA_NUEVA" "$LINEA_VIEJA"
construye "$TMP/nucleo.mutante.sql" || exit 1
FRAGS=()
NO_DEBE=("1-resumen-divisor" "1-responsable-A" "2-analista-sola-anticipada" "9-contrato-app")
mutante_sql "la bandera debio_ocurrir del núcleo cambiada en vez de metrica_debio_ocurrir (la métrica sale igual; los informes de conversiones cambiarían)" \
  "$(cat "$TMP/nucleo.mutante.sql")
do \$nucleo\$
declare v_def text; v_veces integer;
begin
  v_def := pg_get_functiondef('$NUCLEO'::regprocedure);
  v_veces := (length(v_def) - length(replace(v_def, 't.vence_en <= p_ahora,', ''))) / length('t.vence_en <= p_ahora,');
  if v_veces <> 1 then raise exception 'MUTANTE NO APLICABLE: el fragmento del núcleo aparece % veces (debía ser 1)', v_veces; end if;
  execute replace(v_def, 't.vence_en <= p_ahora,', '(t.vence_en <= p_ahora or t.estado = ''completada''),');
end;
\$nucleo\$;" \
  "6-nucleo-intacto"

# M4 — SOLO el divisor del resumen y no el resto: la línea de la métrica revertida y el conteo del RESUMEN ampliado a mano.
# El resumen sale bien; los cortes (analista, modalidad, origen) siguen con el divisor viejo: el fallo del resumen NO puede
# aparecer y los de los cortes SÍ.
frag "$F" "$LINEA_NUEVA" "$LINEA_VIEJA"
frag "$F" "$RESUMEN_DEBIERON" $'select count(*)::int as pactadas,\n      count(*) filter (where metrica_debio_ocurrir or metrica_realizada)::int as debieron_ocurrir,'
NO_DEBE=("1-resumen-divisor" "5-mes-ventana")
mutante "solo el divisor del resumen y no el resto (los cortes por analista, modalidad y origen se quedan con el divisor viejo)" \
  "1-responsable-A" "1-modalidad-virtual" "1-origen-web" "2-analista-sola-anticipada" "9-contrato-app"

# M5 — la MIGRACIÓN sin re-sellar la huella (y sin su propio control del re-sellado): entra, y el oráculo tiene que ver que
# la exención y el censo ya no corresponden al cuerpo vivo.
n=$((n + 1))
echo "$n. Mutante de la migración: sin re-sellar la huella analítica (y sin su control del re-sellado en el postflight)"
if python3 - "$MIG" "$TMP/mig-sin-resello.sql" <<'PY'
import sys, re
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
def quitar(patron):
    global sql
    nuevo, k = re.subn(patron, '', sql, count=1, flags=re.S)
    if k != 1 or re.search(patron, nuevo, flags=re.S):
        sys.exit('MUTANTE DE LA MIGRACIÓN NO APLICABLE: el bloque no aparece exactamente una vez: %s' % patron[:60])
    sql = nuevo
quitar(r"-- ── Re-sellado de la huella analítica.*?\$resello\$;\n")
quitar(r"  if \(select e\.huella from private\.analitica_leads_citas_exenciones e where e\.objeto = v_objeto\)\n       is distinct from 'd54d4f8773cf1106dadbcb0d793575e2' then\n.*?\n  end if;\n")
quitar(r"  if \(select s\.sello from private\.analitica_lc_sello s where s\.id\)\n       is distinct from private\.huella_exenciones_analitica_lc\(\) then\n    raise exception 'POSTFLIGHT.*?\n  end if;\n")
quitar(r"  if not exists \(select 1 from private\.contadores_crudos_leads_citas\(\) c\n                  where c\.objeto = v_objeto and c\.declarada and c\.huella_ok\) then\n    raise exception 'POSTFLIGHT.*?\n  end if;\n")
open(destino, 'w', encoding='utf-8').write(sql)
PY
then
  node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-sin-resello.sql" > "$TMP/m$n.sql" || exit 1
  corre "$TMP/m$n.sql"
  juzgar_salida "$TMP/m$n.salida.txt" 'POSTFLIGHT realizacion_cuenta_anticipada: cuerpo' "7-huella-resellada"
else
  echo "  ✗ no se pudo construir el mutante de la migración"
  fallos=$((fallos + 1))
fi

# ── Mutantes de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha ────────────────────────────────────────────────
mutante_sql "la función pasa a security invoker" \
  "alter function private.metricas_reuniones_implementacion(date,date) security invoker;" \
  "8-ficha"
mutante_sql "la función pierde el search_path vacío" \
  "alter function private.metricas_reuniones_implementacion(date,date) set search_path = public;" \
  "8-ficha"
mutante_sql "la función pasa a VOLATILE" \
  "alter function private.metricas_reuniones_implementacion(date,date) volatile;" \
  "8-ficha"
mutante_sql "authenticated recibe EXECUTE sobre la implementación" \
  "grant execute on function private.metricas_reuniones_implementacion(date,date) to authenticated;" \
  "8-ficha"

# ── EQUIVALENTE: el orden del `or` no cambia nada ────────────────────────────────────────────────────────────────────
frag "$F" "$LINEA_NUEVA" $'      (ce.realizada or ce.debio_ocurrir) as metrica_debio_ocurrir,'
equivalente "el orden de las dos banderas en el or" \
  "«(realizada or debio_ocurrir)» es la misma bandera que «(debio_ocurrir or realizada)»: el ensayo sigue VERDE con la huella re-sellada para ese cuerpo"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "MUTANTES: los $((n - equivalentes)) mutantes de verdad murieron, cada uno por su fallo; $equivalentes equivalente(s) confirmado(s). El oráculo prueba lo que dice probar."
  exit 0
fi
echo "MUTANTES: $fallos superviviente(s) o sin juzgar — hay defensas sin prueba."
exit 1
