#!/usr/bin/env bash
# MUTANTES del ensayo — por cada defensa, un mutante que la neutraliza.
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe la regla a propósito y se exige que el oráculo
# (`pruebas.sql`) lo GRITE: si un mutante sobrevive —el ensayo sigue verde con la defensa quitada—, esa defensa NO está
# probada y este guion falla.
#
# Clases:
#   · de CUERPO: un fragmento cambiado en una pieza nueva (la genérica `private.filtrar_desglose_sujetos_con_bajas_crm` o la de
#     reuniones `private.desglose_responsables_reuniones_crm`), en una puerta (`crm.metricas_reuniones_fn`,
#     `crm.metricas_agenda_fn`) o en una implementación. Se instala DESPUÉS de la migración (cuyo postflight ya selló lo
#     bueno) y antes del oráculo, en la misma transacción, que termina en rollback. Cada fragmento tiene que aparecer
#     EXACTAMENTE las veces que se declara: si la migración cambia, el mutante se niega a mutar otra cosa.
#   · de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha (DEFINER, search_path, VOLATILE, permisos).
#   · EQUIVALENTES: un fragmento cambiado que, en ejecución, NO puede cambiar nada. El ensayo tiene que seguir VERDE.
#
# Un mutante solo cuenta como MUERTO si el ensayo sale ROJO y además nombra los fallos que le corresponden; algunos exigen
# además que un fallo NO aparezca. (Lo que se rompe ANTES de la migración —la deriva que su preflight tiene que rechazar—
# va en `derivas.sh`.)
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/reuniones-desglose-con-bajas/mutantes.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin ella van a una carpeta temporal que se
# borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/reuniones-desglose-con-bajas
if [[ -n "${DIR_ENSAYO:-}" ]]; then
  TMP="$DIR_ENSAYO"
  mkdir -p "$TMP" || exit 1
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
fi

FILTRO='private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])'
PIEZA_R='private.desglose_responsables_reuniones_crm(jsonb)'
PUERTA='crm.metricas_reuniones_fn(date,date)'
AGENDA='crm.metricas_agenda_fn(date,date)'
IMPL='private.metricas_reuniones_implementacion(date,date)'
IMPL_AGENDA='private.metricas_agenda_implementacion(date,date)'

corre() { # corre <archivo.sql> → deja la salida completa en <archivo>.salida.txt
  local codigo
  # shellcheck disable=SC2086  # EJECUTAR_SQL es un comando con sus argumentos
  $EJECUTAR_SQL "$1" > "${1%.sql}.salida.txt" 2>&1
  codigo=$?
  # 9 = el ejecutor del laboratorio comparó la base antes y después y CAMBIÓ. Se para todo y se avisa.
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
  if ! grep -q "$marca" "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$v" != *"ROJO"* ]]; then
    echo "  ✗ MUTANTE SUPERVIVIENTE: ${v:-sin veredicto}"
    fallos=$((fallos + 1))
  elif [[ -n "$faltan" ]]; then
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

# Construye el SQL del mutante de cuerpo con los fragmentos acumulados en FRAGS (re-emite la función con el texto cambiado).
construye() { # construye <archivo de salida>
  python3 - "$1" "${FRAGS[@]}" <<'PY'
import sys
salida, *resto = sys.argv[1:]
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

mutante_sql() { # mutante_sql <nombre> <sentencia SQL> <fallo que debe nombrar>...
  n=$((n + 1))
  echo "$n. Mutante: $1"
  printf '%s\n' "$2" > "$TMP/m$n.mutante.sql"
  juzgar "${@:3}"
}

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

# ── Fragmentos vigentes (los que deja la migración, tal como los devuelve pg_get_functiondef) ─────────────────────────
# Pieza genérica (FILTRO), pieza de reuniones (PIEZA_R) y las dos puertas.
LLAMADA_REU_NUEVA='  return private.desglose_responsables_reuniones_crm(v_payload);'
LLAMADA_REU_COMUN=$'  return private.filtrar_desglose_sujetos_crm(\n    v_payload,\'responsables\',\'responsable_id\',array[\'vendedor\',\'supervisor\']\n  );'
CLAVES=$'array[\'toques\',\'reuniones_realizadas\',\'completadas\',\'no_asistio\',\'canceladas\',\n          \'tareas_creadas\',\'reuniones_agendadas\',\'reprogramaciones\',\'pendientes\']'
LLAMADA_AGE_NUEVA=$'  return private.filtrar_desglose_sujetos_con_bajas_crm(\n    v_payload,\'vendedores\',\'vendedor_id\',array[\'vendedor\',\'supervisor\'],\n    '"$CLAVES"$'\n  );'
LLAMADA_AGE_COMUN=$'  return private.filtrar_desglose_sujetos_crm(\n    v_payload,\'vendedores\',\'vendedor_id\',array[\'vendedor\',\'supervisor\']\n  );'
MARCA_BAJA=$'            || jsonb_build_array(v_elemento || jsonb_build_object(\'de_baja\', true));'
MARCA_SUSP=$'            || jsonb_build_array(v_elemento || jsonb_build_object(\'suspendido\', true));'
SIN_MARCA=$'            || jsonb_build_array(v_elemento);'
RAMA_SUSP=$'        elsif v_perfil_activo is not true then\n          v_filtrados := v_filtrados\n'"$MARCA_SUSP"$'\n'
CON_ROL=$'       where e.perfil_id = v_id\n         and e.rol_crm = any(p_roles);'
SIN_ROL=$'       where e.perfil_id = v_id;'
ACTIVIDAD=$'      if found and (\n        p_claves_actividad is null'
DEJA_EFECTIVO=$'    if private.rol_crm(v_id) = any(p_roles) then\n      v_filtrados := v_filtrados || jsonb_build_array(v_elemento);'
RETORNO=$'  return jsonb_set(p_payload,array[p_clave],v_filtrados,false);'
NADIE_FUERA=$'  if jsonb_array_length(v_desglose->\'responsables\')\n     = jsonb_array_length(p_payload->\'responsables\') then'
ANADE_OTROS=$'    (v_desglose->\'responsables\') || jsonb_build_array(v_otros),'
MARCA_OTROS=$',\n    \'otros\', true\n  )'
PCT_OTROS='then round(100.0*f.realizadas/f.divisor_realizacion,1)'
DIVISOR_OTROS="sum(x.signo*(x.fila->>'divisor_realizacion')::int) as divisor_realizacion"
SIN_ACTIVIDAD_REU=$'p_payload,\'responsables\',\'responsable_id\',array[\'vendedor\',\'supervisor\'],null'

# ── Reglas de las PUERTAS ────────────────────────────────────────────────────────────────────────────────────────────
# M1 — REUNIONES vuelve al filtro común (el cambio revertido): ni marcas ni «Otros»; el desglose no suma el total.
frag "$PUERTA" "$LLAMADA_REU_NUEVA" "$LLAMADA_REU_COMUN"
mutante "la puerta de reuniones vuelve al filtro común" \
  "R1-d1-baja-analista" "R2-d2-suspendido" "R2-d2-otros" "R5-cuadra-d1" "R5-cuadra-d2" "K1-ficha-puerta-reuniones"

# M2 — la AGENDA vuelve al filtro común: el de baja y el suspendido con actividad desaparecen.
frag "$AGENDA" "$LLAMADA_AGE_NUEVA" "$LLAMADA_AGE_COMUN"
mutante "la puerta de la agenda vuelve al filtro común" \
  "G1-gerencia-hoy" "G3-supervisor-hoy" "K1-ficha-puerta-agenda" "K3-puerta-agenda-claves"

# ── Reglas de la pieza GENÉRICA (marcas, roles y actividad) ──────────────────────────────────────────────────────────
# M3 — SIN la marca «de_baja»: el de baja aparece como si estuviera activo.
frag "$FILTRO" "$MARCA_BAJA" "$SIN_MARCA"
NO_DEBE=("R5-cuadra-d1")
mutante "el de baja aparece SIN la marca de_baja" \
  "R1-d1-baja-analista" "R4-solo-anade-d1" "G3-gerencia-hoy" "G5-gerencia-hoy"

# M4 — SIN la marca «suspendido».
frag "$FILTRO" "$MARCA_SUSP" "$SIN_MARCA"
NO_DEBE=("R5-cuadra-d2")
mutante "el suspendido aparece SIN la marca suspendido" \
  "R2-d2-suspendido" "R4-solo-anade-d2" "G3-supervisor-hoy"

# M5 — el suspendido marcado como «de baja» (la ficha está ACTIVA: la marca no casa con activo).
frag "$FILTRO" "$MARCA_SUSP" "$MARCA_BAJA"
mutante "el suspendido sale marcado «de baja»" \
  "R2-d2-suspendido" "R6-marcas-d2" "G3-supervisor-hoy" "G5-supervisor-hoy" "P1-suspendido-perfil-nulo"

# M5b — la SUSPENSIÓN antes que la baja (Codex r1, P3-1): con la ficha inactiva y el perfil inactivo o nulo, saldría
# «suspendido». Con el oráculo de la ronda 3 este mutante SOBREVIVÍA (medido); lo mata el caso P3.
BAJA_ANTES=$'        if v_ficha_activa is false then\n          v_filtrados := v_filtrados\n'"$MARCA_BAJA"$'\n        elsif v_perfil_activo is not true then\n          v_filtrados := v_filtrados\n'"$MARCA_SUSP"$'\n        end if;'
SUSPENSION_ANTES=$'        if v_perfil_activo is not true then\n          v_filtrados := v_filtrados\n'"$MARCA_SUSP"$'\n        elsif v_ficha_activa is false then\n          v_filtrados := v_filtrados\n'"$MARCA_BAJA"$'\n        end if;'
frag "$FILTRO" "$BAJA_ANTES" "$SUSPENSION_ANTES"
mutante "la suspensión gana a la baja (ficha inactiva + perfil inactivo o nulo ⇒ «suspendido»)" \
  "P3-baja-gana-a-suspension"

# M6 — SIN la rama del suspendido (la regla de la ronda 1): sus citas caen en «Otros» y la agenda lo pierde. «Otros» lo
# absorbe: el desglose sigue sumando el total (por eso NO debe nombrar el cuadre).
frag "$FILTRO" "$RAMA_SUSP" ''
NO_DEBE=("R5-cuadra-d2")
mutante "el suspendido en el Portal queda fuera (solo la ficha inactiva cuenta)" \
  "R2-d2-suspendido" "R2-d2-otros" "G3-supervisor-hoy"

# M7 — «perfil activo is false» en vez de «is not true»: el perfil con activo NULO deja de contar como suspendido.
frag "$FILTRO" '        elsif v_perfil_activo is not true then' '        elsif v_perfil_activo is false then'
NO_DEBE=("R2-d2-suspendido")
mutante "suspendido solo con perfil activo = false (no con NULL)" \
  "P1-suspendido-perfil-nulo"

# M8 — SIN mirar el rol de la ficha: el ex Gerencia de baja aparecería por su nombre en el desglose de analistas.
frag "$FILTRO" "$CON_ROL" "$SIN_ROL"
mutante "la baja no mira el rol de la ficha (entra el ex Gerencia)" \
  "R2-d2-fuera-por-nombre" "R2-d2-otros"

# M9 — SIN la condición de actividad: en la agenda entran el de baja sin nada (Q2) y el suspendido con solo rezago (R).
frag "$FILTRO" "$ACTIVIDAD" $'      if found and (\n        true'
mutante "la agenda conserva al de baja o suspendido aunque no tenga actividad" \
  "G4-sin-actividad-fuera" "G3-gerencia-hoy" "S2-sin-gerencia-hoy"

# M10 — la actividad solo con «toques»: el de baja que cerró citas y creó tareas (A), fuera.
frag "$AGENDA" "$CLAVES" "array['toques']"
mutante "la agenda solo cuenta los toques como actividad" \
  "K3-puerta-agenda-claves" "G3-gerencia-hoy" "G3-supervisor-hoy"

# M11 — la actividad SIN «pendientes»: el de baja cuya única actividad es una tarea pendiente (Q1), fuera.
frag "$AGENDA" $',\'reprogramaciones\',\'pendientes\']' $',\'reprogramaciones\']'
mutante "la agenda no cuenta las tareas pendientes como actividad" \
  "K3-puerta-agenda-claves" "G3-gerencia-hoy"

# M12 — la condición de actividad también para los ACTIVOS: la agenda perdería a los efectivos sin actividad.
frag "$FILTRO" "$DEJA_EFECTIVO" $'    if private.rol_crm(v_id) = any(p_roles) and (p_claves_actividad is null or exists (select 1 from unnest(p_claves_actividad) clave where coalesce((v_elemento->>clave)::numeric, 0) <> 0)) then\n      v_filtrados := v_filtrados || jsonb_build_array(v_elemento);'
mutante "la condición de actividad se aplica también a los activos" \
  "G2-gerencia-hoy" "S2-sin-gerencia-hoy"

# M13 — ROMPIENDO LA IGUALDAD: la pieza marca a TODOS (de_baja: false a los efectivos).
frag "$FILTRO" "$DEJA_EFECTIVO" $'    if private.rol_crm(v_id) = any(p_roles) then\n      v_filtrados := v_filtrados || jsonb_build_array(v_elemento || jsonb_build_object(\'de_baja\', false));'
mutante "la pieza añade de_baja: false a los efectivos" \
  "S1-sin-d1" "S2-sin-gerencia-hoy" "R7-contrato-app-d1" "R1-d1-activo-sin-marca"

# M14 — UNA CLAVE NUEVA en la respuesta, aunque no haya bajas.
frag "$FILTRO" "$RETORNO" $'  return jsonb_set(p_payload,array[p_clave],v_filtrados,false) || jsonb_build_object(\'con_bajas\', true);'
mutante "la pieza añade una clave a la respuesta" \
  "S1-sin-d1" "S2-sin-gerencia-hoy" "S3-vis-sin-gerencia"

# M15 — LOS MARCADOS AL FINAL en vez de en su sitio (cambia el orden de la implementación).
frag "$FILTRO" $'  v_filtrados jsonb := \'[]\'::jsonb;' $'  v_filtrados jsonb := \'[]\'::jsonb;\n  v_al_final jsonb := \'[]\'::jsonb;'
frag "$FILTRO" "$MARCA_BAJA" $'            || \'[]\'::jsonb;\n          v_al_final := v_al_final || jsonb_build_array(v_elemento || jsonb_build_object(\'de_baja\', true));'
frag "$FILTRO" "$RETORNO" $'  return jsonb_set(p_payload,array[p_clave],v_filtrados || v_al_final,false);'
mutante "los de baja van al final (no en el orden de la implementación)" \
  "R1-d1-orden" "G1-gerencia-hoy"

# M15b — SIN el nombre de reserva (P3-5 del auditor): un marcado con el nombre vacío llegaría vacío y la agenda de la app (que
# exige texto no vacío) tumbaría el panel entero.
NOMBRE_RESERVA=$'        if v_elemento ? \'nombre\'\n           and coalesce(v_elemento->>\'nombre\', \'\') !~ \'[^[:space:]]\' then\n          v_elemento := v_elemento || jsonb_build_object(\'nombre\', \'(sin nombre)\');\n        end if;\n'
frag "$FILTRO" "$NOMBRE_RESERVA" ''
mutante "un marcado con el nombre vacío o en blanco sale sin nombre de reserva" \
  "P2-marcado-sin-nombre"

# ── Reglas de la pieza de REUNIONES (la fila «Otros», D-47) ───────────────────────────────────────────────────────────
# M16 — SIN «Otros»: lo que queda fuera vuelve a no estar en el desglose.
frag "$PIEZA_R" "$NADIE_FUERA" '  if true then'
mutante "sin la fila «Otros»" \
  "R2-d2-otros" "R5-cuadra-d2" "S1-sin-d2"

# M17 — «Otros» SIEMPRE, aunque nadie quede fuera (una fila en cero).
frag "$PIEZA_R" "$NADIE_FUERA" '  if false then'
mutante "la fila «Otros» aparece aunque nadie quede fuera" \
  "R1-d1-sin-otros" "S1-sin-d1" "R3-esperado-d1"

# M18 — «Otros» al PRINCIPIO.
frag "$PIEZA_R" "$ANADE_OTROS" $'    jsonb_build_array(v_otros) || (v_desglose->\'responsables\'),'
mutante "la fila «Otros» va al principio" \
  "R2-d2-orden" "R7-contrato-app-d2"

# M19 — «Otros» SIN su marca: la pantalla la pintaría como a una persona.
frag "$PIEZA_R" "$MARCA_OTROS" $'\n  )'
mutante "la fila «Otros» sin la marca otros" \
  "R2-d2-otros" "R4-solo-anade-d2"

# M20 — «Otros» sin recalcular el porcentaje.
frag "$PIEZA_R" "$PCT_OTROS" 'then null'
mutante "la fila «Otros» sin porcentaje" \
  "R2-d2-otros" "R3-esperado-d2"

# M21 — el divisor de «Otros» sin descontar las canceladas por el sistema, por otro asesor y las reprogramadas.
frag "$PIEZA_R" "$DIVISOR_OTROS" "sum(x.signo*(x.fila->>'debieron_ocurrir')::int) as divisor_realizacion"
mutante "el divisor de «Otros» no descuenta las exclusiones" \
  "R2-d2-otros" "R7-contrato-app-d2"

# M22 — reuniones CON condición de actividad (solo con inasistencias): el supervisor de baja sin inasistencias cae a «Otros».
frag "$PIEZA_R" "$SIN_ACTIVIDAD_REU" $'p_payload,\'responsables\',\'responsable_id\',array[\'vendedor\',\'supervisor\'],array[\'no_show\']'
mutante "reuniones exige una inasistencia para conservar al de baja" \
  "R1-d1-baja-supervisor" "R1-d1-sin-otros"

# ── La VISIBILIDAD cambia (dos cerraduras en cada puerta: la puerta y su implementación) ─────────────────────────────
# M23 — Coordinación consulta reuniones (las dos cerraduras abiertas). Abrir solo la puerta es un EQUIVALENTE (abajo).
frag "$PUERTA" $'private.rol_crm(v_actor)=\'gerencia\'' $'private.rol_crm(v_actor) in (\'gerencia\',\'coordinador\')'
frag "$IMPL" $'and e.rol_crm = \'gerencia\'' $'and e.rol_crm in (\'gerencia\',\'coordinador\')'
mutante "Coordinación puede consultar reuniones (las dos cerraduras abiertas)" \
  "R8-vis-con-coordinacion-vis" "S3-vis-sin-coordinacion" "K4-intactas"

# M24 — Coordinación consulta la agenda (las dos cerraduras abiertas).
frag "$AGENDA" $'private.rol_crm(v_actor) in (\'vendedor\',\'supervisor\',\'gerencia\')' $'private.rol_crm(v_actor) in (\'vendedor\',\'supervisor\',\'gerencia\',\'coordinador\')'
frag "$IMPL_AGENDA" $'and e.rol_crm in (\'vendedor\',\'supervisor\',\'gerencia\')' $'and e.rol_crm in (\'vendedor\',\'supervisor\',\'gerencia\',\'coordinador\')'
mutante "Coordinación puede consultar la agenda (las dos cerraduras abiertas)" \
  "G6-coordinacion-hoy" "S2-sin-coordinacion-hoy" "K4-intactas"

# ── Mutantes de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha ────────────────────────────────────────────────
mutante_sql "la pieza genérica pasa a security definer" \
  "alter function $FILTRO security definer;" \
  "K2-ficha-piezas"
mutante_sql "la pieza de reuniones pierde el search_path vacío" \
  "alter function $PIEZA_R set search_path = public;" \
  "K2-ficha-piezas"
mutante_sql "la pieza genérica pasa a VOLATILE" \
  "alter function $FILTRO volatile;" \
  "K2-ficha-piezas"
mutante_sql "authenticated recibe EXECUTE sobre la pieza de reuniones" \
  "grant execute on function $PIEZA_R to authenticated;" \
  "K2-ficha-piezas"
mutante_sql "anon recibe EXECUTE sobre la puerta de reuniones" \
  "grant execute on function $PUERTA to anon;" \
  "K1-ficha-puerta-reuniones"
mutante_sql "anon recibe EXECUTE sobre la puerta de la agenda" \
  "grant execute on function $AGENDA to anon;" \
  "K1-ficha-puerta-agenda"

# ── EQUIVALENTES ─────────────────────────────────────────────────────────────────────────────────────────────────────
# Solo la puerta de reuniones abre a Coordinación: la implementación sigue exigiendo Gerencia o lector global.
frag "$PUERTA" $'private.rol_crm(v_actor)=\'gerencia\'' $'private.rol_crm(v_actor) in (\'gerencia\',\'coordinador\')'
equivalente "solo la puerta de reuniones deja pasar a Coordinación" \
  "la implementación tiene su propia cerradura (Gerencia o lector global) y responde el mismo 42501 No autorizado"

# Solo la puerta de la agenda abre a Coordinación: la implementación exige analista, supervisor o Gerencia activos.
frag "$AGENDA" $'private.rol_crm(v_actor) in (\'vendedor\',\'supervisor\',\'gerencia\')' $'private.rol_crm(v_actor) in (\'vendedor\',\'supervisor\',\'gerencia\',\'coordinador\')'
equivalente "solo la puerta de la agenda deja pasar a Coordinación" \
  "la implementación tiene su propia cerradura (miembro activo con rol operativo o lector global) y responde el mismo 42501"

# `crm.equipo.activo` es NOT NULL (lo exige el preflight): «is false» y «not» eligen las mismas fichas.
frag "$FILTRO" '        if v_ficha_activa is false then' '        if not v_ficha_activa then'
equivalente "«not v_ficha_activa» en vez de «v_ficha_activa is false»" \
  "crm.equipo.activo es NOT NULL: las dos formas eligen las mismas fichas; el ensayo sigue VERDE"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "MUTANTES: los $((n - equivalentes)) mutantes de verdad murieron, cada uno por su fallo; $equivalentes equivalente(s) confirmado(s). El oráculo prueba lo que dice probar."
  exit 0
fi
echo "MUTANTES: $fallos superviviente(s) o sin juzgar — hay defensas sin prueba."
exit 1
