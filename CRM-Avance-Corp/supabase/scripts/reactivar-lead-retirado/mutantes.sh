#!/usr/bin/env bash
# MUTANTES del ensayo — por cada defensa, un mutante que la neutraliza.
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe la regla a propósito y se exige que el oráculo
# (`pruebas.sql`) lo GRITE: si un mutante sobrevive —el ensayo sigue verde con la defensa quitada—, esa defensa NO está
# probada y este guion falla.
#
# Hay dos clases:
#   · de CUERPO: la migración real con UN fragmento cambiado en `crm.crear_lead_si_disponible` (la rama), en el núcleo
#     `private.alta_reactivar_retirado` o en su pieza `private.alta_reactivar_bloqueo_conservado`. Se instala DESPUÉS de la
#     migración (cuyo postflight sella los cuerpos buenos) y antes del oráculo, en la misma transacción, que termina en
#     rollback. Cada fragmento tiene que aparecer EXACTAMENTE las veces que se declara: si la migración cambia, el mutante se
#     niega a mutar otra cosa sin que nadie se entere.
#   · de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha (INVOKER, search_path, permisos) o el verificador.
#
# Un mutante solo cuenta como MUERTO si el ensayo sale ROJO y además nombra los fallos que le corresponden (el caso y su
# motivo). Un rojo por otra causa —un error de montaje— no prueba la defensa que ese mutante rompe.
#
# (Lo que se rompe ANTES de la migración —la deriva de catálogo que su preflight tiene que rechazar— va en `derivas.sh`.)
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/reactivar-lead-retirado/mutantes.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin ella van a una carpeta temporal que se
# borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/reactivar-lead-retirado
if [[ -n "${DIR_ENSAYO:-}" ]]; then
  TMP="$DIR_ENSAYO"
  mkdir -p "$TMP" || exit 1
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
fi

F='crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'
N='private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'
H='private.alta_reactivar_bloqueo_conservado(uuid)'

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
n=0

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

juzgar() { # juzgar <fallo que debe nombrar>... → arma, corre y juzga $TMP/m$n.mutante.sql
  local archivo="$TMP/m$n.sql" salida="$TMP/m$n.salida.txt" v nombrados debe faltan=""
  if [[ "$#" -eq 0 ]]; then
    echo "  ✗ el mutante no declara por qué fallo tiene que morir"
    fallos=$((fallos + 1))
    return
  fi
  node "$DIR/armar-ensayo.mjs" --mutante "$TMP/m$n.mutante.sql" > "$archivo" || exit 1
  corre "$archivo"
  v="$(veredicto "$salida")"
  nombrados="$(grep -Eo '^FALLO [^:]+' "$salida" | sort -u | tr '\n' ';' | sed 's/;$//; s/;/ · /g')"
  for debe in "$@"; do
    nombra "$salida" "$debe" || faltan="$faltan «FALLO ${debe}»"
  done
  # La marca separa «el mutante no se pudo instalar» (no se juzga: cuenta como superviviente) de «el oráculo lo detectó».
  if ! grep -q 'MUTANTE_INSTALADO' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$v" != *"ROJO"* ]]; then
    echo "  ✗ MUTANTE SUPERVIVIENTE: ${v:-sin veredicto}"
    fallos=$((fallos + 1))
  elif [[ -n "$faltan" ]]; then
    # Rojo, pero por otra cosa: la defensa que este mutante rompe sigue sin prueba.
    echo "  ✗ ROJO SIN NOMBRAR SU FALLO (falta$faltan): $v: $nombrados"
    fallos=$((fallos + 1))
  else
    echo "  ✓ muere por su fallo ($v): $nombrados"
  fi
}

FRAGS=()
frag() { # frag <firma> <fragmento vigente> <fragmento mutado> [veces]
  FRAGS+=("$1" "$2" "$3" "${4:-1}")
}

# Construye el SQL del mutante de cuerpo con los fragmentos acumulados en FRAGS.
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
    return
  fi
  FRAGS=()
  juzgar "${@:2}"
}

# El mutante de SQL libre (catálogo). Tiene que morir NOMBRANDO su fallo.
mutante_sql() { # mutante_sql <nombre> <sentencia SQL> <fallo que debe nombrar>...
  n=$((n + 1))
  echo "$n. Mutante: $1"
  printf '%s\n' "$2" > "$TMP/m$n.mutante.sql"
  juzgar "${@:3}"
}

# ── Fragmentos vigentes (los de la migración, tal como los devuelve pg_get_functiondef) ───────────────────────────────
RAMA=$'  v_reactivacion := private.alta_reactivar_retirado(\n    v_id, v_actor, v_telefono, v_dni, v_vendedor, v_supervisor, v_disponibilidad,\n    pg_catalog.jsonb_build_object(\n      \'telefono\', v_telefono, \'nombre_completo\', v_nombre, \'telefono_alternativo\', v_alt, \'correo\', v_correo,\n      \'distrito\', v_distrito, \'origen\', p_origen, \'etapa\', p_etapa, \'monto_estimado\', p_monto_estimado,\n      \'moneda\', p_moneda, \'categoria_interes\', v_categoria, \'vendedor_id\', v_vendedor, \'nota\', v_nota));\n  if v_reactivacion is not null then\n    return v_reactivacion;\n  end if;\n'
GATE=$'  if p_actor is null or p_actor is distinct from (select auth.uid()) then\n    raise exception using errcode = \'42501\', message = \'Acceso CRM revocado\';\n  end if;\n'
HUELLA=$'(v_tecleado - array[\'dni\', \'genero\', \'fecha_nacimiento\'])'
REPLAY=$'  select a.* into v_act from crm.actividades a where a.id = p_id;\n  if found then\n    if v_act.metadata ->> \'evento\' is distinct from \'reactivacion_alta\'\n       or v_act.creado_por is distinct from p_actor\n       or v_act.metadata ->> \'tecleado_md5\' is distinct from v_tecleado_md5 then\n      raise exception using errcode = \'22023\', message = \'El identificador de esta alta ya fue usado con datos distintos\';\n    end if;\n    if exists (select 1 from crm.leads l where l.id = v_act.lead_id and l.activo) then\n      v_respuesta := pg_catalog.jsonb_build_object(\'estado\', \'reutilizado\', \'lead_id\', v_act.lead_id);\n      if coalesce((v_act.metadata ->> \'otro_retirado\')::boolean, false) then\n        v_respuesta := v_respuesta || pg_catalog.jsonb_build_object(\'aviso\', \'otro_lead_retirado_con_ese_dni\');\n      end if;\n      return v_respuesta;\n    end if;\n'
REPLAY_ACTOR=$'       or v_act.creado_por is distinct from p_actor\n'
REPLAY_PAYLOAD=$'       or v_act.metadata ->> \'tecleado_md5\' is distinct from v_tecleado_md5 then'
REPLAY_ACTIVA=$'    if exists (select 1 from crm.leads l where l.id = v_act.lead_id and l.activo) then'
REPLAY_AVISO=$'      if coalesce((v_act.metadata ->> \'otro_retirado\')::boolean, false) then\n        v_respuesta := v_respuesta || pg_catalog.jsonb_build_object(\'aviso\', \'otro_lead_retirado_con_ese_dni\');\n      end if;\n'
VEREDICTO=$'  if coalesce(p_disponibilidad ->> \'estado\', \'\') not in (\'libre\', \'enfriamiento\') then'
CANDIDATO_TEL=$'        and l.no_contactar = false\n        and l.telefono = p_telefono\n'
# (con la línea de la etapa: la consulta del «otro retirado» tiene las mismas dos líneas pero con inversionista_id entre medias)
CANDIDATO_DNI=$'          and l.etapa <> \'convertido\'\n          and l.no_contactar = false\n          and l.dni = p_dni\n'
# Ronda 3:
REINTENTO_FIJADO=$'    if v_reintento then\n'
CHECK_SOLO_CAPITAL=$'        if coalesce(v_restriccion, \'\') <> \'leads_monto_estimado_valido\' then\n          raise;\n        end if;\n'
# Ronda 4 (las dos guardas de R3-1: el veredicto de la ficha del primer rastro y el «nunca nulo» del veredicto fresco):
R3_1_VEREDICTO=$'  if v_reintento then\n    select l.* into v_lead from crm.leads l where l.id = v_act.lead_id;\n'
R3_1_NUNCA_NULO=$'  if v_fresco is null and v_reintento then\n'
ENLAZADO_DNI=$'    if p_dni is not null then\n      select l.inversionista_id into v_inv_dni\n      from crm.leads l\n      where l.activo = false\n        and l.inversionista_id is not null\n        and l.dni = p_dni\n        and l.id <> v_cand.id\n      order by l.actualizado_en desc, l.id\n      limit 1;\n      if found then\n        v_fresco := private.juicio_persona(private.inversionista_canonica(v_inv_dni), null);\n        return coalesce(v_fresco, pg_catalog.jsonb_build_object(\'estado\', \'ya_es_cliente\', \'asesor\', \'sin asesor asignado\', \'via\', \'identidad\'));\n      end if;\n    end if;\n'
# Ronda 5: el paso 3a toma la fila del activo que casa por lo tecleado y, fuera del reintento, devuelve nulo (como siempre).
ACTIVOS_TECLEADO_WHERE=$'    where l.activo = true\n      and (l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni))\n'
ACTIVOS_TECLEADO_WHERE_SIN_DESCARTADOS=$'    where l.activo = true\n      and l.etapa not in (\'convertido\', \'descartado\')\n      and (l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni))\n'
ACTIVOS_TECLEADO_SI=$'    if found then\n      if not v_reintento then\n        return null;\n      end if;\n'
# Ronda 5 (R4-1): la guarda del reintento en el paso 3a (quitarla reproduce el núcleo de la ronda 4: nulo también en un reintento).
R4_1_NUNCA_NULO=$'      if not v_reintento then\n        return null;\n      end if;\n'
CONSERVADO_RETURN=$'      return v_conservado;'
CONSERVADO_BLOQUE=$'    v_conservado := private.alta_reactivar_bloqueo_conservado(v_cand.id);\n    if v_conservado is not null then\n      return v_conservado;\n    end if;\n'
DUENO=$'             vendedor_id = p_vendedor,\n             asignado_supervisor_id = p_supervisor,\n'
FOR_UPDATE=$'    select l.* into v_lead from crm.leads l where l.id = v_cand.id for update;'
SET_ACTIVO=$'         set activo = true,\n'
ETAPA=$'             etapa = case when l.etapa = \'descartado\' then \'nuevo\' else l.etapa end,'
CAPITAL=$'             monto_estimado = coalesce(l.monto_estimado, (v_tecleado ->> \'monto_estimado\')::numeric)'
CONVERTIDO_FILTRO=$'and l.etapa <> \'convertido\'\n'
CONVERTIDO_RECHEQUEO=$' or v_lead.etapa = \'convertido\''
SOLO_INDICES_VIVOS=$'        if coalesce(v_restriccion, \'\') not in (\'uq_leads_telefono_vivo\', \'uq_leads_dni_vivo\') then\n          raise;\n        end if;\n'
RASTRO=$'    insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por, creado_en)\n    values (\n      v_rastro_id,\n      v_lead.id,\n      \'nota\',\n      \'Ficha retirada reactivada al registrar de nuevo a la persona\'\n        || coalesce(\': \' || nullif(pg_catalog.btrim(v_tecleado ->> \'nota\'), \'\'), \'\'),\n      pg_catalog.jsonb_build_object(\n        \'evento\', \'reactivacion_alta\',\n        \'via\', \'alta_manual\',\n        \'alta_id\', p_id,\n        \'propietario_anterior\', v_propietario_anterior,\n        \'etapa_anterior\', v_etapa_anterior,\n        \'activo_anterior\', false,\n        \'ciclo_anterior\', v_ciclo_anterior,\n        \'etapa\', v_lead.etapa,\n        \'ciclo\', v_lead.ciclo_actual,\n        \'veredicto\', p_disponibilidad ->> \'estado\',\n        \'otro_retirado\', v_otro,\n        \'tecleado\', pg_catalog.jsonb_build_object(\n          \'monto_estimado\', v_tecleado -> \'monto_estimado\',\n          \'moneda\', v_tecleado -> \'moneda\',\n          \'origen\', v_tecleado -> \'origen\',\n          \'tipo_documento\', v_tipo_documento),\n        \'tecleado_md5\', v_tecleado_md5),\n      p_actor,\n      pg_catalog.statement_timestamp()\n    );\n'
# La pieza del veredicto por lo conservado:
PIEZA_VETOS=$'  if v_v ->> \'estado\' in (\'no_contactar\', \'ya_es_cliente\', \'tomado\', \'en_bolsa\') then'
PIEZA_ACTIVOS=$'  where l.activo = true\n    and (l.telefono = v_c.telefono or (v_c.dni is not null and l.dni = v_c.dni))\n'

# M1 — la rama quitada del alta: vuelve el comportamiento de hoy (un SEGUNDO lead sobre el retirado).
frag "$F" "$RAMA" ""
mutante "la rama quitada del alta (vuelve el segundo lead)" \
  "1-reactiva: el alta no reutilizó la ficha retirada: estado=creado → creó un SEGUNDO lead" \
  "2-enfriamiento-vigente: el alta no reutilizó la ficha retirada: estado=enfriamiento" \
  "9-documento-ce: el alta no reutilizó la ficha retirada: estado=creado → creó un SEGUNDO lead" \
  "6-idempotencia:"

# M2 — la rama no excluye los leads ACTIVOS del mismo contacto (ni por lo tecleado ni por lo conservado: el «if found» del paso
#      3a nunca se cumple y el bloque conservado se quita; el flujo sigue): reactiva el retirado aunque un descartado activo esté
#      en espera (3b) y aunque el veto de la persona esté asociado al DNI conservado (3h). (Los activos OPERATIVOS por dato
#      conservado los cazan además los índices vivos en la carrera tardía, por eso C-1a/C-1b no bastan para este mutante;
#      «devolver null» es el mutante M12.)
frag "$N" "$ACTIVOS_TECLEADO_SI" $'    if false then\n      if not v_reintento then\n        return null;\n      end if;\n'
frag "$N" "$CONSERVADO_BLOQUE" ""
mutante "la rama no excluye leads activos del mismo contacto (tecleado ni conservado)" \
  "3b-enfriamiento-activo: estado reutilizado, se esperaba enfriamiento" \
  "3h-veto-por-dni-conservado: estado reutilizado, se esperaba no_contactar"

# M3 — la rama ignora el enfriamiento de un descartado ACTIVO (solo cuenta activos operativos, tecleados y conservados).
frag "$N" "$ACTIVOS_TECLEADO_WHERE" "$ACTIVOS_TECLEADO_WHERE_SIN_DESCARTADOS"
frag "$H" "$PIEZA_ACTIVOS" "${PIEZA_ACTIVOS}    and l.etapa not in ('convertido', 'descartado')
"
mutante "la rama ignora el enfriamiento de un descartado activo" \
  "3b-enfriamiento-activo: estado reutilizado, se esperaba enfriamiento"

# M4 — la rama reactiva convertidos (sin el filtro de etapa en el candidato fijado del reintento, los dos brazos, el aviso, la
#      recomprobación y el UPDATE).
frag "$N" "$CONVERTIDO_FILTRO" "" 5
frag "$N" "$CONVERTIDO_RECHEQUEO" ""
mutante "la rama reactiva convertidos" \
  "3d-convertido-retirado:"

# M5 — el dueño no cambia: la ficha vuelve activa a nombre del dueño anterior.
frag "$N" "$DUENO" ""
# (con el dueño anterior intacto, la gestión serializada rechaza el rastro firmado por quien registra: el alta falla; en la
#  bandeja del supervisor y en el destino de Gerencia el oráculo ve al dueño equivocado)
mutante "dueño no cambiado (sigue a nombre del anterior)" \
  "1-reactiva: el alta falló" \
  "4b-supervisor-parquea: dueño" \
  "4c-gerencia-asigna: dueño"

# M6 — sin FOR UPDATE sobre la fila del retirado (solo medible por el cuerpo: el ensayo corre en una conexión).
frag "$N" "$FOR_UPDATE" $'    select l.* into v_lead from crm.leads l where l.id = v_cand.id;'
mutante "sin FOR UPDATE al retirado" \
  "7-for-update:"

# M7 — sin rastro: la reactivación no deja la actividad reactivacion_alta.
frag "$N" "$RASTRO" ""
mutante "sin rastro (sin la actividad reactivacion_alta)" \
  "1-reactiva: sin actividad de rastro" \
  "4d-aviso: el rastro no avisa"

# M8 — sin idempotencia por p_id: el reintento ya no devuelve «reutilizado» (recibe el veredicto de hoy: tomado).
frag "$N" "$REPLAY" $'  select a.* into v_act from crm.actividades a where a.id = p_id;\n  if false then\n'
mutante "sin idempotencia por p_id" \
  "6-idempotencia: el reintento con el mismo p_id no devolvió «reutilizado»"
# M8b/M8c — el reintento no exige el mismo actor (solo lo distingue el caso de dos supervisores: un vendedor cambia el
#            payload al autoasignarse) / el mismo payload.
frag "$N" "$REPLAY_ACTOR" ""
mutante "el reintento no exige el mismo actor" \
  "6d-mismo-p_id-otro-supervisor:"
frag "$N" "$REPLAY_PAYLOAD" "       then"
mutante "el reintento no exige el mismo payload" \
  "6b-mismo-p_id-otro-payload:"

# M9 — los datos de la ficha pisados con lo tecleado.
frag "$N" "$SET_ACTIVO" "${SET_ACTIVO}             nombre_completo = coalesce(v_tecleado ->> 'nombre_completo', l.nombre_completo),
             correo = coalesce(v_tecleado ->> 'correo', l.correo),
"
mutante "datos de la ficha pisados con lo tecleado" \
  "5-ficha-conservada: la ficha fue pisada"

# M10 — etapa mal: siempre «nuevo» (un retirado operativo pierde su etapa).
frag "$N" "$ETAPA" $'             etapa = \'nuevo\','
mutante "etapa mal (siempre nuevo)" \
  "1-reactiva: etapa nuevo, se esperaba contactado" \
  "4b-supervisor-parquea: etapa nuevo, se esperaba propuesta_enviada"
# M10b — etapa/ciclo mal: el descartado se queda descartado (no renace en nuevo con ciclo +1).
frag "$N" "$ETAPA" $'             etapa = l.etapa,'
mutante "etapa/ciclo mal (el descartado no renace)" \
  "2-enfriamiento-vigente:" \
  "2b-cero-dias:"

# M11 — la rama intercepta cualquier veredicto (no solo libre/enfriamiento): el veto de OTRO lead que casa solo por el DNI
#       TECLEADO (3i) ya no manda.
frag "$N" "$VEREDICTO" "  if false then"
mutante "la rama no filtra el veredicto" \
  "3i-veto-por-dni-tecleado: estado reutilizado, se esperaba no_contactar"

# ── Ronda 2 ─────────────────────────────────────────────────────────────────────────────────────────────────────────
# M12 (C-1) — la coincidencia activa por un dato CONSERVADO vuelve a devolver null: el alta llega al INSERT y nace el duplicado.
frag "$N" "$CONSERVADO_RETURN" "      return null;"
mutante "C-1: la coincidencia por dato conservado vuelve a devolver null" \
  "C1a-activo-por-dni-conservado: estado creado, se esperaba en_bolsa" \
  "C1b-activo-por-telefono-conservado: estado creado, se esperaba tomado" \
  "3h-veto-por-dni-conservado:"

# M13 (C-2) — la huella de idempotencia sin el teléfono: otro teléfono con el mismo p_id se confirma como el mismo alta.
frag "$N" "$HUELLA" $'(v_tecleado - array[\'dni\', \'genero\', \'fecha_nacimiento\', \'telefono\'])'
mutante "C-2: huella sin teléfono" \
  "C2-mismo-p_id-otro-telefono:"

# M14 (C-5) — cualquier 23505 del UPDATE se trata como carrera de contacto: un índice ajeno se traga y el alta inserta.
frag "$N" "$SOLO_INDICES_VIVOS" ""
mutante "C-5: captura cualquier 23505" \
  "C5-23505-ajeno-se-propaga:"

# M15 (A-4 / D-21) — el retirado enlazado a persona deja de ser candidato (vuelve el filtro inversionista_id is null): con solo
#       el teléfono, el alta crea un segundo lead de una persona reconocida.
frag "$N" "$CANDIDATO_TEL" $'        and l.no_contactar = false\n        and l.inversionista_id is null\n        and l.telefono = p_telefono\n'
frag "$N" "$CANDIDATO_DNI" $'          and l.etapa <> \'convertido\'\n          and l.no_contactar = false\n          and l.inversionista_id is null\n          and l.dni = p_dni\n'
mutante "D-21: el enlazado por teléfono vuelve a crear un segundo lead" \
  "3c-enlazado-solo-telefono: estado creado, se esperaba ya_es_cliente"

# M16 (A-5) — sin el gate interno p_actor = auth.uid().
frag "$N" "$GATE" ""
mutante "A-5: sin gate interno en el núcleo" \
  "10f:"

# M17 (A-6) — el reintento confirma la ficha aunque ya no esté activa.
frag "$N" "$REPLAY_ACTIVA" "    if true then"
mutante "A-6: el reintento no exige que la ficha siga activa" \
  "A6-reintento-tras-segundo-retiro:"

# M18 (A-2) — sin el capital tecleado para el retirado de base cargada sin capital: el CHECK cae, se captura y nace un segundo lead.
frag "$N" "$CAPITAL" $'             monto_estimado = l.monto_estimado'
mutante "A-2: sin el capital tecleado (el retirado de base sin capital no sale del retiro)" \
  "A2-base-cargada-sin-capital: el alta no reutilizó"

# M19 (C-3) — el replay pierde el aviso de los dos retirados.
frag "$N" "$REPLAY_AVISO" ""
mutante "C-3: el replay pierde el aviso" \
  "4d-replay: el replay perdió el aviso"

# M20 — la pieza del veredicto por lo conservado ignora el veto («no_contactar») asociado al DNI conservado.
frag "$H" "$PIEZA_VETOS" $'  if v_v ->> \'estado\' in (\'ya_es_cliente\', \'tomado\', \'en_bolsa\') then'
mutante "la pieza conservada ignora el veto asociado al DNI conservado" \
  "3h-veto-por-dni-conservado: estado reutilizado, se esperaba no_contactar"

# ── Ronda 3 ─────────────────────────────────────────────────────────────────────────────────────────────────────────
# M21 (R2-1) — el reintento vuelve a elegir el candidato por contacto (teléfono y actualizado_en) en vez de fijarlo a la ficha del
#       primer rastro: con dos retirados del mismo teléfono reactiva la otra ficha y devuelve otro lead_id.
frag "$N" "$REINTENTO_FIJADO" $'    if false then\n'
mutante "R2-1: el reintento vuelve a elegir el candidato por contacto" \
  "R2-1-reintento-fija-la-ficha: el reintento reactivó OTRA ficha del mismo teléfono"

# M22 (R2-2) — cualquier 23514 del UPDATE se trata como veredicto fresco: el CHECK ajeno se traga y el alta inserta un segundo lead.
frag "$N" "$CHECK_SOLO_CAPITAL" ""
mutante "R2-2: captura cualquier 23514 del UPDATE" \
  "R2-2-check-ajeno-se-propaga: debía rechazar con 23514"

# M23 (AR2-1) — el otro retirado ENLAZADO que casa por el DNI tecleado ya no bloquea: con la bandera apagada se reactiva el no
#       enlazado y la persona recibe un lead activo mientras su ficha sigue retirada.
frag "$N" "$ENLAZADO_DNI" ""
mutante "AR2-1: el otro retirado enlazado por el DNI tecleado no bloquea" \
  "AR2-1-enlazado-por-dni-tecleado: estado reutilizado, se esperaba ya_es_cliente"

# ── Ronda 4 ─────────────────────────────────────────────────────────────────────────────────────────────────────────
# M24 (R3-1) — el reintento con rastro previo cae al veredicto fresco (las dos guardas quitadas: vuelve el núcleo de la ronda 3):
#       sobre una ficha convertida o borrada el verificador dice «libre», el núcleo devuelve nulo y el alta inserta OTRA ficha
#       con el mismo p_id.
frag "$N" "$R3_1_VEREDICTO" $'  if false then\n    select l.* into v_lead from crm.leads l where l.id = v_act.lead_id;\n'
frag "$N" "$R3_1_NUNCA_NULO" $'  if false then\n'
mutante "R3-1: el reintento con rastro previo cae al veredicto fresco (llega al INSERT)" \
  "R3-1a-convertida: estado creado, se esperaba ya_es_cliente" \
  "R3-1b-inexistente: debía rechazar con 22023"

# ── Ronda 5 ─────────────────────────────────────────────────────────────────────────────────────────────────────────
# M25 (R4-1) — el paso 3a devuelve nulo también en un reintento (la guarda quitada: vuelve el núcleo de la ronda 4): con un
#       descartado activo de 0 días en sus 24 h que casa por lo tecleado, el verificador dice «libre», el núcleo devuelve nulo y
#       el alta inserta OTRA ficha con el mismo p_id (los índices vivos no cubren descartados).
frag "$N" "$R4_1_NUNCA_NULO" $'      return null;\n'
mutante "R4-1: el paso 3a devuelve nulo en un reintento (llega al INSERT)" \
  "R4-1-activo-por-lo-tecleado: estado creado, se esperaba tomado"

# ── Mutantes de CATÁLOGO ────────────────────────────────────────────────────────────────────────────────────────────
mutante_sql "el verificador modificado" \
  "do \$m\$ begin execute replace(pg_get_functiondef('private.verificar_disponibilidad_lead_impl(text,text,uuid)'::regprocedure), 'Un solo lead TOTAL por persona', 'Un solo lead TOTAL por persona.'); end \$m\$;" \
  "10c:"
mutante_sql "el núcleo pasa a security invoker" \
  "alter function $N security invoker;" \
  "10b:"
mutante_sql "authenticated recibe EXECUTE sobre el núcleo" \
  "grant execute on function $N to authenticated;" \
  "10b:"
mutante_sql "el núcleo pierde el search_path vacío" \
  "alter function $N set search_path = public;" \
  "10b:"
mutante_sql "la pieza conservada pasa a security invoker" \
  "alter function $H security invoker;" \
  "10b2:"
mutante_sql "authenticated recibe EXECUTE sobre la pieza conservada" \
  "grant execute on function $H to authenticated;" \
  "10b2:"
mutante_sql "el alta pierde el search_path vacío" \
  "alter function $F set search_path = public;" \
  "10a:"
mutante_sql "anon recibe EXECUTE sobre el alta" \
  "grant execute on function $F to anon;" \
  "10a:"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "MUTANTES: los $n mutantes murieron, cada uno por su fallo. El oráculo prueba lo que dice probar."
  exit 0
fi
echo "MUTANTES: $fallos superviviente(s) o sin juzgar — hay defensas sin prueba."
exit 1
