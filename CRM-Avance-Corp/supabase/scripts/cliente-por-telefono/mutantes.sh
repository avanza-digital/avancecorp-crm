#!/usr/bin/env bash
# MUTANTES del ensayo del bloque 2.7 — por cada defensa, un mutante que la neutraliza.
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe la regla a propósito y se exige que el oráculo (`pruebas.sql`)
# lo GRITE: si un mutante sobrevive —el ensayo sigue verde con la defensa quitada—, esa defensa NO está probada y este guion
# falla.
#
# Hay dos clases:
#   · de CUERPO: la migración real con UN fragmento cambiado en el núcleo `private.alta_reactivar_retirado` (la regla 1b). Se
#     instala DESPUÉS de la migración (cuyo postflight sella el cuerpo bueno) y antes del oráculo, en la misma transacción, que
#     termina en rollback. Cada fragmento tiene que aparecer EXACTAMENTE las veces que se declara: si la migración cambia, el
#     mutante se niega a mutar otra cosa sin que nadie se entere.
#   · de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha (INVOKER, search_path, permisos) o el verificador.
#
# Un mutante solo cuenta como MUERTO si el ensayo sale ROJO y además nombra los fallos que le corresponden (el caso y su motivo).
# Un rojo por otra causa —un error de montaje— no prueba la defensa que ese mutante rompe.
#
# (Lo que se rompe ANTES de la migración —la deriva de catálogo que su preflight tiene que rechazar— va en `derivas.sh`.)
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" DIR_ENSAYO=<carpeta> \
#     bash supabase/scripts/cliente-por-telefono/mutantes.sh
# DIR_ENSAYO es obligatoria: ahí quedan los SQL generados y sus salidas (este guion no escribe en carpetas temporales).
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"

DIR=supabase/scripts/cliente-por-telefono
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

# Construye el SQL del mutante de cuerpo con los fragmentos acumulados en FRAGS (uno tras otro, cada uno sobre el cuerpo vivo).
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
# La regla entera (teléfono → DNI, ronda 2), con la línea en blanco y el inicio del bloque del candidato que la siguen.
REGLA_Y_RAMA="$(cat <<'EOF'
  -- 1b. EL CLIENTE YA CONVERTIDO TAMBIÉN SE RECONOCE POR TELÉFONO Y POR DNI (bloque 2.7; D-22, D-25 y D-27 de Miguel,
  --     08/10/2026; hallazgo H-28). Solo en un alta NUEVA: un reintento con rastro previo sigue fijado a la ficha de su rastro
  --     (R2-1…R4-1). Si el teléfono tecleado —o, si con él no casa ninguno, el DNI tecleado (D-27)— es el de un lead CONVERTIDO
  --     (activo o retirado), el alta no crea, no reactiva y no escribe nada: enlazado a una persona ⇒ el mismo juicio de
  --     identidad que da el DNI («ya es cliente» con su asesor, o «no contactar» si la persona está vetada; el respaldo de D-21 si
  --     el juicio no dice nada); sin persona ⇒ «ya es cliente» a nombre del dueño de esa ficha (formato del verificador, sin via).
  --     El teléfono manda sobre el DNI (también con OTRO DNI tecleado, D-25) y los dos van antes que cualquier retirado no
  --     convertido que case por teléfono o DNI (el candidato de abajo ya no llega a mirarse).
  if not v_reintento then
    select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
      into v_convertido
    from crm.leads l
    left join public.perfiles pv on pv.id = l.vendedor_id
    left join public.perfiles ps on ps.id = l.asignado_supervisor_id
    where l.etapa = 'convertido'
      and l.telefono = p_telefono
    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
    limit 1;
    if not found and p_dni is not null then
      select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
        into v_convertido
      from crm.leads l
      left join public.perfiles pv on pv.id = l.vendedor_id
      left join public.perfiles ps on ps.id = l.asignado_supervisor_id
      where l.etapa = 'convertido'
        and l.dni = p_dni
      order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
      limit 1;
    end if;
    if found then
      if v_convertido.inversionista_id is not null then
        v_fresco := private.juicio_persona(private.inversionista_canonica(v_convertido.inversionista_id), null);
        return coalesce(v_fresco, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
      end if;
      return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_convertido.tenedor, 'sin asesor asignado'));
    end if;
  end if;

  <<rama>>
EOF
)"
RAMA='  <<rama>>'
# La regla SIN la guarda del reintento (teléfono → DNI → juicio), sangría de 4 espacios, para moverla de sitio (M4 y M9).
REGLA_MOVIDA="$(cat <<'EOF'
    select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
      into v_convertido
    from crm.leads l
    left join public.perfiles pv on pv.id = l.vendedor_id
    left join public.perfiles ps on ps.id = l.asignado_supervisor_id
    where l.etapa = 'convertido'
      and l.telefono = p_telefono
    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
    limit 1;
    if not found and p_dni is not null then
      select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
        into v_convertido
      from crm.leads l
      left join public.perfiles pv on pv.id = l.vendedor_id
      left join public.perfiles ps on ps.id = l.asignado_supervisor_id
      where l.etapa = 'convertido'
        and l.dni = p_dni
      order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
      limit 1;
    end if;
    if found then
      if v_convertido.inversionista_id is not null then
        v_fresco := private.juicio_persona(private.inversionista_canonica(v_convertido.inversionista_id), null);
        return coalesce(v_fresco, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
      end if;
      return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_convertido.tenedor, 'sin asesor asignado'));
    end if;
EOF
)"$'\n'
# El sub-bloque de la búsqueda por DNI (D-27), tal cual, y su versión movida al «sin candidato» del 2.4 (MD4).
DNI_BLOQUE="$(cat <<'EOF'
    if not found and p_dni is not null then
      select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
        into v_convertido
      from crm.leads l
      left join public.perfiles pv on pv.id = l.vendedor_id
      left join public.perfiles ps on ps.id = l.asignado_supervisor_id
      where l.etapa = 'convertido'
        and l.dni = p_dni
      order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
      limit 1;
    end if;
EOF
)"$'\n'
DNI_MOVIDA="$(cat <<'EOF'
        if p_dni is not null then
          select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
            into v_convertido
          from crm.leads l
          left join public.perfiles pv on pv.id = l.vendedor_id
          left join public.perfiles ps on ps.id = l.asignado_supervisor_id
          where l.etapa = 'convertido'
            and l.dni = p_dni
          order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
          limit 1;
          if found then
            if v_convertido.inversionista_id is not null then
              v_fresco := private.juicio_persona(private.inversionista_canonica(v_convertido.inversionista_id), null);
              return coalesce(v_fresco, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
            end if;
            return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_convertido.tenedor, 'sin asesor asignado'));
          end if;
        end if;
EOF
)"$'\n'
WHERE_REGLA=$'    where l.etapa = \'convertido\'\n      and l.telefono = p_telefono\n'
WHERE_DNI=$'      where l.etapa = \'convertido\'\n        and l.dni = p_dni\n'
GUARDA_DNI=$'    limit 1;\n    if not found and p_dni is not null then\n      select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor\n'
# Las dos cláusulas de prioridad (ronda 3): la del teléfono y la del DNI, cada una con la línea que la precede (únicas).
ORDEN_TEL=$'      and l.telefono = p_telefono\n    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id\n'
ORDEN_DNI=$'        and l.dni = p_dni\n      order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id\n'
GUARDA_REINTENTO=$'  if not v_reintento then\n    select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor\n'
SI_ENCONTRADO=$'    if found then\n      if v_convertido.inversionista_id is not null then\n'
CON_PERSONA=$'      if v_convertido.inversionista_id is not null then\n'
SIN_PERSONA=$'      return pg_catalog.jsonb_build_object(\'estado\', \'ya_es_cliente\', \'asesor\', coalesce(v_convertido.tenedor, \'sin asesor asignado\'));\n'
# El final del candidato por teléfono/DNI del 2.4 (alta nueva): sin candidato, nulo.
CANDIDATO_NO_HALLADO=$'      if not found then\n        return null;\n      end if;\n    end if;\n'
PASO1=$'  -- 1. Solo con «libre» o «enfriamiento» (D-15: la espera de un RETIRADO no bloquea). Cualquier otro veredicto manda.\n'

# M1 — la regla quitada (el bloque 1b desaparece entero, teléfono y DNI): vuelve el comportamiento de hoy (un SEGUNDO lead).
frag "$N" "$REGLA_Y_RAMA" "$RAMA"
mutante "la regla quitada (vuelve el segundo lead del cliente)" \
  "1-activo-solo-telefono: estado=creado" \
  "2-retirado-solo-telefono: estado=creado" \
  "4a-sin-persona-solo-telefono: estado=creado" \
  "7a-precedencia-por-telefono: estado=reutilizado" \
  "11a-dni-sin-persona-activo: estado=creado"

# M2a — la búsqueda por TELÉFONO solo mira convertidos ACTIVOS: el cliente retirado (L9f-tel) vuelve a recibir un segundo lead.
#       (Con la ronda 2, 4c —teléfono + DNI del cliente sin persona retirado— lo salva la búsqueda por DNI: ya no lo nombra.)
frag "$N" "$WHERE_REGLA" $'    where l.etapa = \'convertido\'\n      and l.activo\n      and l.telefono = p_telefono\n'
mutante "la búsqueda por teléfono solo mira convertidos activos" \
  "2-retirado-solo-telefono: estado=creado" \
  "7a-precedencia-por-telefono: estado=reutilizado"

# M2b — la búsqueda por TELÉFONO solo mira convertidos RETIRADOS: el cliente activo (la sonda del Director) vuelve a recibir un
#       segundo lead.
frag "$N" "$WHERE_REGLA" $'    where l.etapa = \'convertido\'\n      and not l.activo\n      and l.telefono = p_telefono\n'
mutante "la búsqueda por teléfono solo mira convertidos retirados" \
  "1-activo-solo-telefono: estado=creado" \
  "4a-sin-persona-solo-telefono: estado=creado"

# M3 — la búsqueda por teléfono deja pasar con OTRO DNI (D-25 roto): el familiar —o cualquiera que teclee un DNI cualquiera— crea
#      el lead.
frag "$N" "$WHERE_REGLA" $'    where l.etapa = \'convertido\'\n      and l.telefono = p_telefono\n      and (p_dni is null or l.dni is null or l.dni = p_dni)\n'
mutante "la regla deja pasar con otro DNI" \
  "3-otro-dni: estado=creado"

# M4 — la regla entera (teléfono y DNI) DESPUÉS del candidato retirado (sin precedencia): solo actúa si no hay retirado no
#      convertido que casar; con el cliente retirado, la rama del 2.4 reactiva al otro retirado (`reutilizado`).
frag "$N" "$REGLA_Y_RAMA" "$RAMA"
frag "$N" "$CANDIDATO_NO_HALLADO" $'      if not found then\n'"$REGLA_MOVIDA"$'        return null;\n      end if;\n    end if;\n'
mutante "la regla va después del candidato retirado (sin precedencia)" \
  "7a-precedencia-por-telefono: estado=reutilizado" \
  "7b-precedencia-por-dni: estado=reutilizado" \
  "7c-precedencia-sobre-el-retirado-en-enfriamiento: estado=reutilizado" \
  "11h-el-dni-manda-sobre-el-candidato-retirado: estado=reutilizado"

# M5a — la regla ESCRIBE una actividad (una nota sobre la ficha del cliente, firmada por quien registra): con su propio dueño la
#       nota entra y el oráculo la ve («se escribió algo»); con otro asesor la gestión serializada la rechaza y el alta falla.
frag "$N" "$SI_ENCONTRADO" $'    if found then\n      insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por, creado_en)\n      select pg_catalog.gen_random_uuid(), l.id, \'nota\', \'mutante 2.7: la regla escribe\', \'{}\'::jsonb, p_actor, pg_catalog.statement_timestamp()\n      from crm.leads l\n      where l.etapa = \'convertido\' and l.telefono = p_telefono\n      order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id\n      limit 1;\n      if v_convertido.inversionista_id is not null then\n'
mutante "la regla escribe una actividad sobre la ficha del cliente" \
  "1d-su-propio-dueno-solo-telefono:" \
  "1-activo-solo-telefono:"

# M5b — la regla REACTIVA al cliente retirado (activo = true bajo las válvulas, como haría una reactivación) antes de responder.
frag "$N" "$SI_ENCONTRADO" $'    if found then\n      perform pg_catalog.set_config(\'crm.toma_directa\', \'on\', true);\n      perform pg_catalog.set_config(\'crm.reapertura_identidad\', \'on\', true);\n      update crm.leads l set activo = true where l.etapa = \'convertido\' and l.telefono = p_telefono and not l.activo;\n      perform pg_catalog.set_config(\'crm.toma_directa\', \'off\', true);\n      perform pg_catalog.set_config(\'crm.reapertura_identidad\', \'off\', true);\n      if v_convertido.inversionista_id is not null then\n'
mutante "la regla reactiva al cliente retirado" \
  "2-retirado-solo-telefono:" \
  "4c-sin-persona-retirado-telefono-y-dni:"

# M6 — la regla se aplica también al REINTENTO del 2.4 (sin la guarda `not v_reintento`): el reintento deja de ser idéntico a hoy.
frag "$N" "$GUARDA_REINTENTO" $'  if true then\n    select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor\n'
mutante "la regla se aplica también al reintento" \
  "8a-reintento-tras-segundo-retiro:" \
  "8b-reintento-con-cliente-activo-sigue-en-22023:" \
  "11i-reintento-con-el-dni-de-un-cliente:"

# M8 — la regla no juzga a la persona (trata a todo convertido como «sin persona»): el veto de la persona no se ve y el asesor
#      deja de ser el de la persona.
frag "$N" "$CON_PERSONA" $'      if false then\n'
mutante "la regla no juzga a la persona" \
  "5b-persona-vetada-bandera-apagada:" \
  "1-activo-solo-telefono:"

# M9 — la regla ANTES del filtro del veredicto: se adelanta al veredicto de hoy (cuenta del Portal, lead activo vivo).
frag "$N" "$REGLA_Y_RAMA" "$RAMA"
frag "$N" "$PASO1" $'  if not v_reintento then\n'"$REGLA_MOVIDA"$'  end if;\n\n'"$PASO1"
mutante "la regla va antes del filtro del veredicto" \
  "6a-cuenta-del-portal:" \
  "6e-lead-activo-vivo-tomado:"

# M10 — formato: el «sin persona» con `via = identidad` (la decisión del ensayo es el formato del verificador, sin via).
frag "$N" "$SIN_PERSONA" $'      return pg_catalog.jsonb_build_object(\'estado\', \'ya_es_cliente\', \'asesor\', coalesce(v_convertido.tenedor, \'sin asesor asignado\'), \'via\', \'identidad\');\n'
mutante "el sin persona responde con via (otro formato)" \
  "4a-sin-persona-solo-telefono:"

# M11 — el «sin persona» no nombra al dueño de la ficha.
frag "$N" "$SIN_PERSONA" $'      return pg_catalog.jsonb_build_object(\'estado\', \'ya_es_cliente\', \'asesor\', \'sin asesor asignado\');\n'
mutante "el sin persona no nombra al dueño de la ficha" \
  "4a-sin-persona-solo-telefono:"

# M12 — sin el respaldo de D-21: si el juicio de la persona no dice nada (persona fusionada en otra sin leads), la regla devuelve
#       nulo y el alta llega al INSERT (nace el segundo lead).
frag "$N" $'        v_fresco := private.juicio_persona(private.inversionista_canonica(v_convertido.inversionista_id), null);\n        return coalesce(v_fresco, pg_catalog.jsonb_build_object(\'estado\', \'ya_es_cliente\', \'asesor\', \'sin asesor asignado\', \'via\', \'identidad\'));\n' \
  $'        v_fresco := private.juicio_persona(private.inversionista_canonica(v_convertido.inversionista_id), null);\n        return v_fresco;\n'
mutante "sin el respaldo de D-21 cuando el juicio no dice nada" \
  "4e-persona-fusionada-sin-juicio-respaldo: estado=creado"

# ── Ronda 2 (D-27): la búsqueda por DNI ───────────────────────────────────────────────────────────────────────────────
# MD1 — la regla del DNI quitada (vuelve el hueco medido en la ronda 1: el DNI de un cliente con otro teléfono crea otro lead).
frag "$N" "$DNI_BLOQUE" ""
mutante "la regla del DNI quitada" \
  "11a-dni-sin-persona-activo: estado=creado" \
  "11b-dni-sin-persona-retirado: estado=creado" \
  "11c-dni-con-persona-activo: estado=creado" \
  "11d-dni-con-persona-retirado: estado=creado" \
  "11h-el-dni-manda-sobre-el-candidato-retirado: estado=reutilizado"

# MD2 — la regla del DNI solo mira convertidos SIN persona (la del cliente con persona se deja al verificador, que con la bandera
#       apagada no la ve).
frag "$N" "$WHERE_DNI" $'      where l.etapa = \'convertido\'\n        and l.dni = p_dni\n        and l.inversionista_id is null\n'
mutante "la regla del DNI solo mira convertidos sin persona" \
  "11c-dni-con-persona-activo: estado=creado" \
  "11d-dni-con-persona-retirado: estado=creado"

# MD3 — la regla del DNI solo mira convertidos ACTIVOS (el cliente retirado vuelve a recibir otro lead, o se reactiva al retirado).
frag "$N" "$WHERE_DNI" $'      where l.etapa = \'convertido\'\n        and l.dni = p_dni\n        and l.activo\n'
mutante "la regla del DNI solo mira convertidos activos" \
  "11b-dni-sin-persona-retirado: estado=creado" \
  "11d-dni-con-persona-retirado: estado=creado" \
  "11h-el-dni-manda-sobre-el-candidato-retirado: estado=reutilizado"

# MD4 — la regla del DNI DESPUÉS del candidato retirado del 2.4 (solo actúa si no hay retirado que casar): el retirado del teléfono
#       se reactiva aunque el DNI sea de un cliente.
frag "$N" "$DNI_BLOQUE" ""
frag "$N" "$CANDIDATO_NO_HALLADO" $'      if not found then\n'"$DNI_MOVIDA"$'        return null;\n      end if;\n    end if;\n'
mutante "la regla del DNI va después del candidato retirado" \
  "11h-el-dni-manda-sobre-el-candidato-retirado: estado=reutilizado"

# MD5 — el DNI ANTES que el teléfono (precedencia invertida): con el teléfono de un cliente y el DNI de otro, responde por el del DNI.
frag "$N" "$WHERE_REGLA" $'    where l.etapa = \'convertido\'\n      and l.dni = p_dni\n'
frag "$N" "$GUARDA_DNI" $'    limit 1;\n    if not found then\n      select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor\n'
frag "$N" "$WHERE_DNI" $'      where l.etapa = \'convertido\'\n        and l.telefono = p_telefono\n'
mutante "el DNI va antes que el teléfono" \
  "11g-el-telefono-manda-sobre-el-dni:"

# ── Ronda 3 (Codex P2): la PRIORIDAD entre varios convertidos (enlazado → activo → más reciente), por teléfono y por DNI ────────
frag "$N" "$ORDEN_TEL" $'      and l.telefono = p_telefono\n    order by (l.inversionista_id is not null) asc, l.activo desc, l.convertido_en desc nulls last, l.id\n'
mutante "teléfono: el enlazado a persona deja de ir primero" \
  "12a-telefono-gana-el-enlazado:"
frag "$N" "$ORDEN_TEL" $'      and l.telefono = p_telefono\n    order by (l.inversionista_id is not null) desc, l.activo asc, l.convertido_en desc nulls last, l.id\n'
mutante "teléfono: el retirado va antes que el activo" \
  "12b-telefono-gana-el-activo:"
frag "$N" "$ORDEN_TEL" $'      and l.telefono = p_telefono\n    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en asc nulls last, l.id\n'
mutante "teléfono: el convertido más antiguo va primero" \
  "12c-telefono-gana-el-mas-reciente:"
frag "$N" "$ORDEN_DNI" $'        and l.dni = p_dni\n      order by (l.inversionista_id is not null) asc, l.activo desc, l.convertido_en desc nulls last, l.id\n'
mutante "DNI: el enlazado a persona deja de ir primero" \
  "12d-dni-gana-el-enlazado:"
frag "$N" "$ORDEN_DNI" $'        and l.dni = p_dni\n      order by (l.inversionista_id is not null) desc, l.activo asc, l.convertido_en desc nulls last, l.id\n'
mutante "DNI: el retirado va antes que el activo" \
  "12e-dni-gana-el-activo:"
frag "$N" "$ORDEN_DNI" $'        and l.dni = p_dni\n      order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en asc nulls last, l.id\n'
mutante "DNI: el convertido más antiguo va primero" \
  "12f-dni-gana-el-mas-reciente:"

# ── Ronda 4 (revisión 2 del auditor): DESEMPATES. Un convertido SIN fecha va detrás (`nulls last`; `desc` a secas en PostgreSQL es
#    `nulls first`, así que este mutante también es «quitar el nulls last»), y quitar el criterio de la fecha muere SIEMPRE: en
#    12c/12f/12g/12h el id menor es el del que debe perder, así que el desempate por `l.id` lo haría ganar.
frag "$N" "$ORDEN_TEL" $'      and l.telefono = p_telefono\n    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls first, l.id\n'
mutante "teléfono: los convertidos sin fecha van primero (nulls first)" \
  "12g-telefono-gana-el-que-tiene-fecha:"
frag "$N" "$ORDEN_TEL" $'      and l.telefono = p_telefono\n    order by (l.inversionista_id is not null) desc, l.activo desc, l.id\n'
mutante "teléfono: sin el criterio de la fecha (desempata el id)" \
  "12c-telefono-gana-el-mas-reciente:" "12g-telefono-gana-el-que-tiene-fecha:"
frag "$N" "$ORDEN_DNI" $'        and l.dni = p_dni\n      order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls first, l.id\n'
mutante "DNI: los convertidos sin fecha van primero (nulls first)" \
  "12h-dni-gana-el-que-tiene-fecha:"
frag "$N" "$ORDEN_DNI" $'        and l.dni = p_dni\n      order by (l.inversionista_id is not null) desc, l.activo desc, l.id\n'
mutante "DNI: sin el criterio de la fecha (desempata el id)" \
  "12f-dni-gana-el-mas-reciente:" "12h-dni-gana-el-que-tiene-fecha:"

# MW (ronda 3, huella por contenido) — la regla ESCRIBE en OTRA ficha (ni la del cliente ni la del caso: un lead ajeno del banco)
#      antes de responder: ninguna comparación de fichas lo ve y el número de filas no cambia; solo la huella por contenido.
frag "$N" "$SI_ENCONTRADO" $'    if found then\n      update crm.leads l set nota = coalesce(l.nota, \'\') || \' (mutante 2.7)\' where l.id = (select x.id from crm.leads x where x.telefono not like \'+5192407%\' and x.etapa <> \'convertido\' order by x.id limit 1);\n      if v_convertido.inversionista_id is not null then\n'
mutante "la regla escribe en otra ficha (solo la ve la huella por contenido)" \
  "1-activo-solo-telefono: se escribió algo"

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
