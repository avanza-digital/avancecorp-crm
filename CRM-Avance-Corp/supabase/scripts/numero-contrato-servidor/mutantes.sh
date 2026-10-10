#!/usr/bin/env bash
# MUTANTES del ensayo — por cada defensa, un mutante que la neutraliza.
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe la regla a propósito y se exige que el oráculo
# (`pruebas.sql`) lo GRITE: si un mutante sobrevive —el ensayo sigue verde con la defensa quitada—, esa defensa NO está
# probada y este guion falla.
#
# Hay tres clases:
#   · de CUERPO: la migración real con UN fragmento cambiado en `public.crear_contrato`. Se instala DESPUÉS de la migración
#     (cuyo postflight sella el cuerpo bueno) y antes del oráculo, en la misma transacción, que termina en rollback. Cada
#     fragmento tiene que aparecer EXACTAMENTE las veces que se declara: si la migración cambia, el mutante se niega a mutar
#     otra cosa sin que nadie se entere.
#   · de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha (INVOKER, search_path, permisos).
#   · EQUIVALENTES: un fragmento cambiado que, en ejecución, NO puede cambiar lo que hace la función. Aquí la expectativa se
#     invierte: el ensayo tiene que seguir VERDE, y eso documenta que la defensa es redundante, no que esté sin probar.
#
# Un mutante solo cuenta como MUERTO si el ensayo sale ROJO y además nombra los fallos que le corresponden (el caso y su
# motivo). Un rojo por otra causa —un error de montaje— no prueba la defensa que ese mutante rompe. Algunos mutantes exigen
# además que un fallo NO aparezca (p. ej. «guarda solo en la puerta crm»: la puerta tiene que seguir rechazando).
#
# (Lo que se rompe ANTES de la migración —la deriva de catálogo que su preflight tiene que rechazar— va en `derivas.sh`.)
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/numero-contrato-servidor/mutantes.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin ella van a una carpeta temporal que se
# borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/numero-contrato-servidor
if [[ -n "${DIR_ENSAYO:-}" ]]; then
  TMP="$DIR_ENSAYO"
  mkdir -p "$TMP" || exit 1
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
fi

F='public.crear_contrato(jsonb,jsonb)'
CC='crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'

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

juzgar() { # juzgar <fallo que debe nombrar>... → arma, corre y juzga $TMP/m$n.mutante.sql
  local archivo="$TMP/m$n.sql" salida="$TMP/m$n.salida.txt" v nombrados debe faltan="" sobran=""
  if [[ "$#" -eq 0 ]]; then
    echo "  ✗ el mutante no declara por qué fallo tiene que morir"
    fallos=$((fallos + 1))
    NO_DEBE=()
    return
  fi
  node "$DIR/armar-ensayo.mjs" --mutante "$TMP/m$n.mutante.sql" > "$archivo" || exit 1
  corre "$archivo"
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
  elif [[ -n "$sobran" ]]; then
    echo "  ✗ ROJO PERO NOMBRA UN FALLO QUE NO DEBÍA (sobra$sobran): $v: $nombrados"
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
    NO_DEBE=()
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

# Un EQUIVALENTE no se puede matar: la función ya hace el filtro antes. Se exige que el ensayo siga VERDE; si deja de
# serlo, el mutante ya no es equivalente y hay que mirarlo.
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

# ── Fragmentos vigentes de la función (los de la migración, tal como los devuelve pg_get_functiondef) ─────────────────
COND=$'if v_numero is null or v_numero !~ \'^(2024|2025|2026)-01-[0-9]{6}$\' then'
EXENTO=$'if not (public.es_admin() and private.es_gerencia_crm_activa()) then'
RAISE=$'raise exception \'Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos\'\n        using errcode = \'22023\';'
GUARDA=$'  if v_numero is null or v_numero !~ \'^(2024|2025|2026)-01-[0-9]{6}$\' then\n    if not (public.es_admin() and private.es_gerencia_crm_activa()) then\n      raise exception \'Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos\'\n        using errcode = \'22023\';\n    end if;\n  end if;\n'
AUTOGEN=$'  if v_numero is null then\n    v_numero := private.siguiente_numero_contrato(v_anio);\n  end if;\n'
DUP=$'  if exists (select 1 from public.contratos c where c.numero_contrato = v_numero) then\n    raise exception \'El N de contrato % ya existe\', v_numero;\n  end if;\n'
# En la puerta crm (crm.crear_contrato_con_cuenta): el punto donde el mutante «guarda solo en la puerta crm» la pone.
ANCLA_CC=$'  if not (select private.puede_registrar_ventas()) then\n    raise exception using errcode = \'42501\', message = \'Cliente no encontrado o fuera de tu cartera\';\n  end if;\n'
GUARDA_CC=$'  if nullif(btrim(p_contrato->>\'numero_contrato\'), \'\') is null or nullif(btrim(p_contrato->>\'numero_contrato\'), \'\') !~ \'^(2024|2025|2026)-01-[0-9]{6}$\' then\n    if not (public.es_admin() and private.es_gerencia_crm_activa()) then\n      raise exception \'Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos\' using errcode = \'22023\';\n    end if;\n  end if;\n'

# M1 — el AUTOGENERADO de vuelta para todos: la guarda solo mira los números no vacíos; sin número, inventa AC-AAAA-NNNN.
frag "$F" "$COND" $'if v_numero is not null and v_numero !~ \'^(2024|2025|2026)-01-[0-9]{6}$\' then'
mutante "el autogenerado de vuelta para todos (la guarda ignora el número vacío)" \
  "b01-sin-clave (directa · VEND1): el servidor ACEPTÓ" \
  "b02-vacio (directa · VEND1): el servidor ACEPTÓ" \
  "b03c-json-null (crm · VEND1): el servidor ACEPTÓ" \
  "5n-GERENCIA-sin-clave (directa · GERENCIA): el servidor ACEPTÓ" \
  "4b-renovacion-__SIN_CLAVE__ (crm · VEND3): el servidor ACEPTÓ"

# M2 — la guarda quitada: el servidor vuelve a aceptar cualquier número y a autogenerar; el duplicado vuelve a ganar.
frag "$F" "$GUARDA" ""
mutante "la guarda quitada (vuelve el comportamiento de hoy para todos)" \
  "b04-ABC (directa · VEND1): el servidor ACEPTÓ" \
  "b04-ABC (crm · VEND1): el servidor ACEPTÓ" \
  "b06-2027-01-000009 (directa · GERENCIA): el servidor ACEPTÓ" \
  "5n-invalido-y-duplicado (directa · VEND1): rechazó, pero no con la regla: P0001"

# M3 y M4 — la expresión sin ^ (basura delante) o sin $ (basura detrás, 7 dígitos, salto de línea final).
frag "$F" "$COND" $'if v_numero is null or v_numero !~ \'(2024|2025|2026)-01-[0-9]{6}$\' then'
mutante "la expresión sin ^" \
  "b12-prefijo (directa · VEND1): el servidor ACEPTÓ" \
  "b12b-prefijo-digito (crm · VEND1): el servidor ACEPTÓ"
frag "$F" "$COND" $'if v_numero is null or v_numero !~ \'^(2024|2025|2026)-01-[0-9]{6}\' then'
mutante "la expresión sin \$" \
  "b13-sufijo (directa · VEND1): el servidor ACEPTÓ" \
  "b08-siete-digitos (crm · VEND1): el servidor ACEPTÓ" \
  "b11-salto-final (directa · VEND1): el servidor ACEPTÓ"

# M5 — {6} por +: cualquier cantidad de dígitos.
frag "$F" "$COND" $'if v_numero is null or v_numero !~ \'^(2024|2025|2026)-01-[0-9]+$\' then'
mutante "{6} por + (5 y 7 dígitos entran)" \
  "b07-cinco-digitos (directa · VEND1): el servidor ACEPTÓ" \
  "b08-siete-digitos (directa · VEND1): el servidor ACEPTÓ"

# M6 y M7 — la lista de series: añadir 2027 o quitar 2024.
frag "$F" "$COND" $'if v_numero is null or v_numero !~ \'^(2024|2025|2026|2027)-01-[0-9]{6}$\' then'
mutante "la serie 2027 añadida" \
  "b06-2027-01-000009 (directa · VEND1): el servidor ACEPTÓ" \
  "b06-2027-01-000009 (crm · VEND1): el servidor ACEPTÓ"
frag "$F" "$COND" $'if v_numero is null or v_numero !~ \'^(2025|2026)-01-[0-9]{6}$\' then'
mutante "la serie 2024 quitada" \
  "4-2024-000000 (directa · VEND1): debía entrar y se rechazó" \
  "4-crm-2024 (crm · VEND1): debía entrar y se rechazó"

# M8 — \d en vez de [0-9]: en este Postgres \d casa dígitos no ASCII (medida 7c del oráculo).
frag "$F" "$COND" $'if v_numero is null or v_numero !~ \'^(2024|2025|2026)-01-\\d{6}$\' then'
mutante "\\d en vez de [0-9] (dígitos no ASCII entran)" \
  "b09-no-ascii (directa · VEND1): el servidor ACEPTÓ" \
  "b09b-mixto-no-ascii (crm · VEND1): el servidor ACEPTÓ"

# M9 y M10 — otro SQLSTATE; otro mensaje sin «número» ni «formato» (el banco y la pantalla los exigen).
frag "$F" "$RAISE" $'raise exception \'Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos\'\n        using errcode = \'P0001\';'
mutante "el rechazo sale con otro SQLSTATE (P0001)" \
  "b04-ABC (directa · VEND1): rechazó, pero no con la regla: P0001|Formato de número de contrato inválido" \
  "b01-sin-clave (crm · VEND1): rechazó, pero no con la regla: P0001|"
frag "$F" "$RAISE" $'raise exception \'Dato de contrato no admitido\'\n        using errcode = \'22023\';'
mutante "el rechazo sale con otro mensaje (sin «número» ni «formato»)" \
  "b04-ABC (directa · VEND1): rechazó, pero no con la regla: 22023|Dato de contrato no admitido" \
  "b01-sin-clave (crm · VEND1): rechazó, pero no con la regla: 22023|Dato de contrato no admitido"

# M11 — la guarda SOLO en la puerta crm (crm.crear_contrato_con_cuenta): la llamada directa a public.crear_contrato vuelve a
# aceptar; por la puerta crm se sigue rechazando igual (esos fallos NO pueden aparecer).
frag "$F" "$GUARDA" ""
frag "$CC" "$ANCLA_CC" "${ANCLA_CC}${GUARDA_CC}"
NO_DEBE=("b04-ABC (crm · VEND1)" "b01-sin-clave (crm · VEND1)" "5n-sin-sesion (crm · SIN SESIÓN)")
mutante "la guarda solo en la puerta crm (la llamada directa vuelve a aceptar)" \
  "b04-ABC (directa · VEND1): el servidor ACEPTÓ" \
  "b01-sin-clave (directa · VEND1): el servidor ACEPTÓ" \
  "5n-VEND1-ABC (directa · VEND1): el servidor ACEPTÓ" \
  "4b-upgrade-ABC-R1 (directa · VEND3): el servidor ACEPTÓ"

# M12 y M13 — la excepción por el rol equivocado: solo Gerencia (la gerencia histórica comercial+gerencia pasaría) o solo
# admin (un admin sin ficha o el superadmin puro pasarían).
frag "$F" "$EXENTO" 'if not private.es_gerencia_crm_activa() then'
mutante "la excepción solo exige Gerencia (sin admin del Portal)" \
  "5n-GERENCIA-sin-clave (directa · GERENCIA): el servidor ACEPTÓ" \
  "5n-GERENCIA-ABC (directa · GERENCIA): el servidor ACEPTÓ" \
  "b04-ABC (crm · GERENCIA): el servidor ACEPTÓ"
frag "$F" "$EXENTO" 'if not public.es_admin() then'
mutante "la excepción solo exige admin del Portal (sin Gerencia)" \
  "5n-ADMIN-sin-clave (directa · ADMIN): el servidor ACEPTÓ" \
  "5n-ADMIN-ABC (directa · ADMIN): el servidor ACEPTÓ" \
  "5n-SUPERADMIN-ABC (directa · SUPERADMIN): el servidor ACEPTÓ"

# M14 — la excepción sin exigir sesión de usuario: EQUIVALENTE. Sin sesión la función ya murió antes con 42501
# (`private.puede_registrar_ventas()` exige `auth.uid()`), y `es_admin()` da falso sin uid: la guarda nunca ve una sesión nula.
frag "$F" "$EXENTO" 'if (select auth.uid()) is not null and not (public.es_admin() and private.es_gerencia_crm_activa()) then'
equivalente "la excepción no exige sesión de usuario" \
  "la función ya rechaza sin sesión con 42501 (puede_registrar_ventas exige auth.uid()) antes de llegar a la guarda; el oráculo lo mide en 5n-sin-sesion (directa y crm)"

# M15 — la exención que además salta el DUPLICADO: el exento debe seguir recibiendo su error de siempre.
frag "$F" "$DUP" $'  if not (public.es_admin() and private.es_gerencia_crm_activa()) and exists (select 1 from public.contratos c where c.numero_contrato = v_numero) then\n    raise exception \'El N de contrato % ya existe\', v_numero;\n  end if;\n'
mutante "la exención además salta el duplicado" \
  "5-GER_ADMIN-duplicado (directa · GER_ADMIN):" \
  "5-GER_SUPER-duplicado (directa · GER_SUPER):"

# M16 — la guarda sobre el número CRUDO (sin recortar): «  2026-01-000012  » se rechazaría.
frag "$F" "$COND" $'if v_numero is null or (p_contrato->>\'numero_contrato\') !~ \'^(2024|2025|2026)-01-[0-9]{6}$\' then'
mutante "la guarda mira el número crudo y no el recortado" \
  "4-recortado (directa · VEND1): debía entrar y se rechazó" \
  "4-crm-recortado (crm · VEND1): debía entrar y se rechazó"

# M17 — la guarda solo para la categoría «nuevo»: una renovación o un upgrade con número fuera de forma entraría.
frag "$F" "$COND" $'if v_categoria = \'nuevo\' and (v_numero is null or v_numero !~ \'^(2024|2025|2026)-01-[0-9]{6}$\') then'
mutante "la guarda solo para la categoría nuevo (renovación y upgrade sin guarda)" \
  "4b-renovacion-ABC-R1 (directa · VEND3): el servidor ACEPTÓ" \
  "4b-upgrade-__SIN_CLAVE__ (crm · VEND3): el servidor ACEPTÓ"

# M18 — el duplicado ANTES que la forma: un número fuera de forma que además existe recibiría el error de duplicado.
frag "$F" "${GUARDA}${AUTOGEN}${DUP}" "${DUP}${GUARDA}${AUTOGEN}"
mutante "el duplicado se comprueba antes que la forma" \
  "5n-invalido-y-duplicado (directa · VEND1): rechazó, pero no con la regla: P0001"

# ── Mutantes de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha ────────────────────────────────────────────────
mutante_sql "la función pasa a security invoker" \
  "alter function public.crear_contrato(jsonb,jsonb) security invoker;" \
  "9a:"
mutante_sql "la función pierde el search_path vacío" \
  "alter function public.crear_contrato(jsonb,jsonb) set search_path = public;" \
  "9a:"
mutante_sql "anon recibe EXECUTE" \
  "grant execute on function public.crear_contrato(jsonb,jsonb) to anon;" \
  "9a:"
mutante_sql "authenticated recibe EXECUTE WITH GRANT OPTION" \
  "grant execute on function public.crear_contrato(jsonb,jsonb) to authenticated with grant option;" \
  "9a:"
mutante_sql "service_role pierde EXECUTE" \
  "revoke execute on function public.crear_contrato(jsonb,jsonb) from service_role;" \
  "9a:"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "MUTANTES: los $((n - equivalentes)) mutantes de verdad murieron, cada uno por su fallo; $equivalentes equivalente(s) confirmado(s) (la defensa es redundante: la función ya filtra antes). El oráculo prueba lo que dice probar."
  exit 0
fi
echo "MUTANTES: $fallos superviviente(s) o sin juzgar — hay defensas sin prueba."
exit 1
