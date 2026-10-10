#!/usr/bin/env bash
# MUTANTES del ensayo — por cada defensa, un mutante que la neutraliza.
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe la regla a
# propósito y se exige que el oráculo (`pruebas.sql`) lo GRITE: si un mutante
# sobrevive —el ensayo sigue verde con la defensa quitada—, esa defensa NO está
# probada y este guion falla.
#
# Hay cuatro clases:
#   · de CUERPO: la migración real con UN fragmento cambiado en una puerta o en el detector. Se instala DESPUÉS de la
#     migración (cuyo postflight sella los cuerpos buenos) y antes del oráculo, en la misma transacción, que termina en
#     rollback. Cada fragmento tiene que aparecer EXACTAMENTE las veces que se declara: si la migración cambia, el mutante
#     se niega a mutar otra cosa sin que nadie se entere.
#   · de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha (permisos, atributos).
#   · de AISLAMIENTO: la guarda 0A000 del detector se quita y se corre el ensayo de `aislamiento.sql` (transacción
#     REPEATABLE READ): sin la guarda, la puerta acepta.
#   · EQUIVALENTES: un fragmento cambiado que, en ejecución SECUENCIAL, NO puede cambiar lo que hace la puerta (la puerta ya
#     exige «Solo Gerencia» con sesión de usuario ANTES de preguntar por la excepción). Aquí la expectativa se invierte: el
#     ensayo tiene que seguir VERDE, y eso documenta que la defensa es redundante en secuencia, no que esté sin probar. Bajo
#     concurrencia (revocar Gerencia mientras la puerta espera el cerrojo) la segunda comprobación sí defiende: esa prueba
#     necesita dos conexiones y queda para la fase 4.
#
# Un mutante solo cuenta como MUERTO si el ensayo sale ROJO y además nombra los fallos que le corresponden (el caso y su
# motivo). Un rojo por otra causa —un error de montaje— no prueba la defensa que ese mutante rompe.
#
# (Lo que se rompe ANTES de la migración —la deriva de catálogo que su preflight tiene que rechazar— va en `derivas.sh`.)
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/anular-venta-mes-sellado/mutantes.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin ella van a una carpeta temporal que se
# borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/anular-venta-mes-sellado
if [[ -n "${DIR_ENSAYO:-}" ]]; then
  TMP="$DIR_ENSAYO"
  mkdir -p "$TMP" || exit 1
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
fi

AV='crm.anular_cierre_avance(uuid,text)'
EX='crm.anular_cierre_externo(uuid,text)'
DET='private.mes_sellado_de_venta(uuid)'

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
ARMADO_EXTRA=""   # modificador para armar-ensayo.mjs (vacío = oráculo; "--aislamiento" = ensayo de aislamiento)

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
echo "0b. El ensayo de aislamiento sin mutar debe estar VERDE (las puertas responden 0A000 en repeatable read)"
node "$DIR/armar-ensayo.mjs" --aislamiento > "$TMP/base-aislamiento.sql" || exit 1
corre "$TMP/base-aislamiento.sql"
v="$(veredicto "$TMP/base-aislamiento.salida.txt")"
if [[ "$v" == *"VERDE"* ]]; then
  echo "  ✓ base aislamiento → $v"
else
  echo "  ✗ base aislamiento → ${v:-sin veredicto} (arreglar el ensayo antes de mutar)"
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
  # shellcheck disable=SC2086  # ARMADO_EXTRA es un modificador opcional
  node "$DIR/armar-ensayo.mjs" $ARMADO_EXTRA --mutante "$TMP/m$n.mutante.sql" > "$archivo" || exit 1
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

# El mutante de aislamiento: mismo armado de fragmentos, pero el ensayo que lo juzga es el de REPEATABLE READ.
mutante_aislamiento() { # mutante_aislamiento <nombre> <fallo que debe nombrar>...
  ARMADO_EXTRA="--aislamiento"
  mutante "$@"
  ARMADO_EXTRA=""
}

# El mutante de SQL libre (catálogo o cuerpo reescrito entero). Tiene que morir NOMBRANDO su fallo.
mutante_sql() { # mutante_sql <nombre> <sentencia SQL> <fallo que debe nombrar>...
  n=$((n + 1))
  echo "$n. Mutante: $1"
  printf '%s\n' "$2" > "$TMP/m$n.mutante.sql"
  juzgar "${@:3}"
}

# Un EQUIVALENTE (secuencial) no se puede matar con una conexión: la puerta ya hace el filtro antes. Se exige que el ensayo
# siga VERDE; si deja de serlo, el mutante ya no es equivalente y hay que mirarlo.
equivalente() { # equivalente <nombre>   (usa los fragmentos de FRAGS)
  local archivo salida v
  n=$((n + 1))
  echo "$n. Equivalente secuencial: $1"
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
    echo "  ≈ EQUIVALENTE SECUENCIAL CONFIRMADO ($v): la puerta ya filtra con «Solo gerencia» antes de llegar aquí; la conjunción se conserva como defensa bajo concurrencia (prueba de dos conexiones: fase 4)"
    equivalentes=$((equivalentes + 1))
  else
    echo "  ✗ YA NO ES EQUIVALENTE ($v): $(grep -Eo '^FALLO [^:]+' "$salida" | sort -u | tr '\n' ';')"
    fallos=$((fallos + 1))
  fi
}

# Fragmentos vigentes de cada puerta y del detector (los de la migración, tal como los devuelve pg_get_functiondef).
G_AV='from private.mes_sellado_de_venta(p_lead_id) d;'
G_EX='from private.mes_sellado_de_venta(v_cierre.lead_id) d;'
G_NULA='from (select null::date as p_mes, false as p_sellado, false as p_desconocido) d;'
EXENTO='if public.es_admin() and private.es_gerencia_crm_activa() then'
DECIDE='if v_desconocido or v_sellado then'

# M1 — guarda quitada de las dos puertas: el servidor vuelve a dejar anular en un mes sellado. Caen los rechazos de las dos
# puertas, por ACEPTAR, y el exento deja de dejar rastro (sin guarda nadie entra por la excepción).
frag "$AV" "$G_AV" "$G_NULA"
frag "$EX" "$G_EX" "$G_NULA"
mutante "la guarda quitada de las dos puertas" \
  "1 (avance): el servidor ACEPTÓ" \
  "2 (externo): el servidor ACEPTÓ" \
  "3-fuera-de-plazo (avance): el servidor ACEPTÓ" \
  "3-D3-desconocido (externo): el servidor ACEPTÓ" \
  "5-ger_admin-avance (avance): exento: anuló SIN rastro" \
  "5n-gerencia-historica (avance): el servidor ACEPTÓ" \
  "6-despues (avance): el servidor ACEPTÓ"

# M2 — la guarda solo en UNA de las dos puertas (cada una con su fallo, y no el de la otra).
frag "$AV" "$G_AV" "$G_NULA"
mutante "la guarda solo en crm.anular_cierre_externo (avance sin guarda)" \
  "1 (avance): el servidor ACEPTÓ" \
  "5n-gerencia-historica (avance): el servidor ACEPTÓ"
frag "$EX" "$G_EX" "$G_NULA"
mutante "la guarda solo en crm.anular_cierre_avance (externo sin guarda)" \
  "2 (externo): el servidor ACEPTÓ" \
  "5n-gerencia-historica (externo): el servidor ACEPTÓ"

# M3 — el detector sin el cerrojo del mes: una anulación concurrente con el sellado de ESE mes leería «abierto». Con una
# sola conexión no se ve la carrera; se ve que el cerrojo YA NO QUEDA TOMADO tras anular (presencia en pg_locks).
frag "$DET" $'perform pg_catalog.pg_advisory_xact_lock(\n    pg_catalog.hashtext(\'crm.periodos_cerrados\'),\n    (p_mes - date \'2000-01-01\')::integer);' 'perform 1;'
mutante "el detector sin el cerrojo del mes" \
  "6-antes (avance): la anulación no tomó el cerrojo del mes" \
  "4d-avance (avance): la anulación no tomó el cerrojo del mes"

# M3b — el cerrojo sobre el mes EQUIVOCADO (el de `convertido_en` y no el de la venta): no protege contra el sellado del mes que importa.
frag "$DET" $'(p_mes - date \'2000-01-01\')::integer);' $'(pg_catalog.date_trunc(\'month\', v_convertido_en at time zone \'America/Lima\')::date - date \'2000-01-01\')::integer);'
mutante "el cerrojo sobre el mes de convertido_en en vez del mes de la venta" \
  "5-ger_admin-fecha-comercial (avance): la anulación no tomó el cerrojo del mes"

# M4 — el detector que se apoya en registrar_ajuste_si_mes_cerrado: devuelve nada en varios casos de mes sellado.
mutante_sql "el detector usa registrar_ajuste_si_mes_cerrado (deja pasar lo que no habría generado ajuste)" \
"create or replace function private.mes_sellado_de_venta(p_lead_id uuid, out p_mes date, out p_sellado boolean, out p_desconocido boolean)
returns record language plpgsql volatile security invoker set search_path = ''
as \$m\$
declare
  v_a uuid;
begin
  p_mes := null; p_sellado := false; p_desconocido := false;
  v_a := private.registrar_ajuste_si_mes_cerrado(p_lead_id, 'mutante', (select auth.uid()));
  if v_a is null then return; end if;
  select a.periodo_origen into p_mes from crm.ajustes_mes_cerrado a where a.id = v_a;
  p_sellado := true;
end;
\$m\$;" \
  "3-fuera-de-plazo (avance): el servidor ACEPTÓ" \
  "3-origen-que-no-pesa (avance): el servidor ACEPTÓ" \
  "3-sin-acreditacion (avance): el servidor ACEPTÓ" \
  "3-sin-episodio (avance): el servidor ACEPTÓ" \
  "3-sin-episodio-externo (externo): el servidor ACEPTÓ"

# M5 — la regla aplicada a los cierres NO iniciales (renovación, upgrade, reinversión): D-14 dice que no cambian.
frag "$EX" $'if v_cierre.es_cierre_inicial then\n    select d.p_mes' $'if true then\n    select d.p_mes'
mutante "la regla también se aplica a los cierres externos no iniciales" \
  "4b-no-inicial (externo): debía poder anular y se rechazó"

# M6 — la excepción por el rol equivocado. Solo Gerencia (sin exigir admin): la `gerencia` histórica (comercial+gerencia)
# pasaría. Solo admin (sin exigir Gerencia): equivalente SECUENCIAL, porque la puerta ya exigió Gerencia (ver abajo).
frag "$AV" "$EXENTO" 'if private.es_gerencia_crm_activa() then'
frag "$EX" "$EXENTO" 'if private.es_gerencia_crm_activa() then'
mutante "la excepción solo exige Gerencia (sin admin del Portal)" \
  "5n-gerencia-historica (avance): el servidor ACEPTÓ" \
  "5n-gerencia-historica (externo): el servidor ACEPTÓ"
frag "$AV" "$EXENTO" 'if public.es_admin() then'
frag "$EX" "$EXENTO" 'if public.es_admin() then'
equivalente "la excepción solo exige admin (sin Gerencia): la puerta ya exigió Gerencia"

# M7 — la excepción sin exigir sesión de usuario: la puerta ya rechazó con 42501 si `auth.uid()` es nulo.
frag "$AV" "$EXENTO" 'if (select auth.uid()) is null or (public.es_admin() and private.es_gerencia_crm_activa()) then'
frag "$EX" "$EXENTO" 'if (select auth.uid()) is null or (public.es_admin() and private.es_gerencia_crm_activa()) then'
equivalente "la excepción no exige sesión de usuario: la puerta ya rechazó sin sesión"

# M8 — la excepción que además CREA AJUSTE: el exento no debe dejar deuda.
frag "$AV" 'v_excepcion := true;' 'v_excepcion := true; v_ajuste := private.registrar_ajuste_si_mes_cerrado(p_lead_id, v_motivo, v_uid);'
frag "$EX" 'v_excepcion := true;' 'v_excepcion := true; v_ajuste := private.registrar_ajuste_si_mes_cerrado(v_cierre.lead_id, v_motivo, v_uid);'
mutante "la excepción además crea ajuste" \
  "5-ger_admin-avance (avance): exento: dejó un ajuste" \
  "5-ger_admin-externo (externo): exento: dejó un ajuste"

# M9 — la excepción sin rastro: la anulación del exento no dejaría quién, cuándo ni la marca del mes en la actividad.
frag "$AV" 'when v_excepcion then' 'when false then'
frag "$EX" 'when v_excepcion then' 'when false then'
mutante "la excepción sin rastro en la actividad" \
  "5-ger_admin-avance (avance): exento: anuló SIN rastro" \
  "5-ger_admin-externo (externo): exento: anuló SIN rastro" \
  "3-D4-desconocido-exento (externo): exento: anuló SIN rastro"

# M10-M12 — SQLSTATE, mensaje y pista del rechazo: la pantalla reconoce el rechazo por su código y muestra su texto.
frag "$AV" $'errcode = \'P0409\',\n        message = pg_catalog.format(\'No se puede anular' $'errcode = \'P0001\',\n        message = pg_catalog.format(\'No se puede anular'
frag "$EX" $'errcode = \'P0409\',\n          message = pg_catalog.format(\'No se puede anular' $'errcode = \'P0001\',\n          message = pg_catalog.format(\'No se puede anular'
mutante "el rechazo sale con otro SQLSTATE (P0001)" \
  "1 (avance): rechazó, pero no con la regla: P0001|No se puede anular" \
  "2 (externo): rechazó, pero no con la regla: P0001|No se puede anular"
frag "$AV" 'No se puede anular: el mes de esta venta (%s) ya está sellado' 'Operación no permitida (%s)'
frag "$EX" 'No se puede anular: el mes de esta venta (%s) ya está sellado' 'Operación no permitida (%s)'
mutante "el rechazo sale con otro mensaje" \
  "1 (avance): rechazó, pero no con la regla: P0409|Operación no permitida" \
  "2 (externo): rechazó, pero no con la regla: P0409|Operación no permitida"
# (la pista aparece dos veces por puerta: en el rechazo por mes sellado y en el de mes desconocido)
frag "$AV" 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.' 'Otra pista.' 2
frag "$EX" 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.' 'Otra pista.' 2
mutante "el rechazo sale con otra pista (hint)" \
  "1 (avance): rechazó, pero no con la regla: P0409|No se puede anular: el mes de esta venta (2026-06) ya está sellado|Otra pista." \
  "2 (externo): rechazó, pero no con la regla: P0409|No se puede anular: el mes de esta venta (2026-06) ya está sellado|Otra pista." \
  "3-D3-desconocido (externo): rechazó, pero no con la regla: P0409|No se puede anular: no se puede determinar el mes de esta venta|Otra pista."
# M12b — el mensaje del mes DESCONOCIDO cambia (el de mes sellado se conserva).
frag "$AV" 'No se puede anular: no se puede determinar el mes de esta venta' 'No se puede anular'
frag "$EX" 'No se puede anular: no se puede determinar el mes de esta venta' 'No se puede anular'
mutante "el rechazo por mes desconocido sale con otro mensaje" \
  "3-D3-desconocido (externo): rechazó, pero no con la regla: P0409|No se puede anular|"

# M13 — comparar el mes con el RELOJ en vez de con `periodos_cerrados`: un mes terminado pero sin sellar (la ventana del 1 al
# 10) pasaría a rechazarse. Debe caer 4d (agosto: terminado, no sellado).
frag "$DET" 'p_sellado := exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_mes);' $'p_sellado := p_mes < pg_catalog.date_trunc(\'month\', pg_catalog.now() at time zone \'America/Lima\')::date;'
mutante "el mes se compara con el reloj y no con crm.periodos_cerrados" \
  "4d-avance (avance): debía poder anular y se rechazó" \
  "4d-externo (externo): debía poder anular y se rechazó"

# M14 — el detector que ignora la ACREDITACIÓN: septiembre se resolvería por convertido_en/episodio. (Con la política de
# septiembre activa, el ledger del laboratorio no saca de `lead_asignaciones` el episodio de cierre de una venta de
# septiembre en adelante: sin acreditación y sin fecha, 3-D1 degrada a «desconocido» —falla cerrado—, no a «aceptada».)
frag "$DET" $'if v_acreditacion.id is not null then\n    p_mes := v_acreditacion.periodo_comercial;' $'if false then\n    p_mes := v_acreditacion.periodo_comercial;'
mutante "el detector ignora la fecha comercial de la acreditación" \
  "3-fecha-comercial (avance): el servidor ACEPTÓ" \
  "4f-acreditacion-agosto (avance): debía poder anular y se rechazó" \
  "3-D1-sin-fecha-acreditada (externo): rechazó, pero no con la regla: P0409|No se puede anular: no se puede determinar el mes"

# M15 — el detector que ignora el EPISODIO del ledger: usaría siempre el mes de `convertido_en`.
frag "$DET" $'elsif pg_catalog.cardinality(v_meses_episodio) = 1 then\n      p_mes := v_meses_episodio[1];' $'elsif false then\n      p_mes := v_meses_episodio[1];'
mutante "el detector ignora el episodio de cierre del ledger" \
  "3-episodio-manda (avance): el servidor ACEPTÓ" \
  "4e-episodio-abierto (avance): debía poder anular y se rechazó" \
  "3-D2-sin-fecha-episodio (externo): rechazó, pero no con la regla: P0409|No se puede anular: no se puede determinar el mes"

# ── Ronda 2 (hallazgo #1) ─────────────────────────────────────────────────────

# M16 — mes DESCONOCIDO tratado como ABIERTO (fail-open): la venta sin acreditación, sin episodio y sin fecha se anularía.
frag "$AV" "$DECIDE" 'if v_sellado then'
frag "$EX" "$DECIDE" 'if v_sellado then'
mutante "el mes desconocido se trata como abierto (fail-open)" \
  "3-D3-desconocido (externo): el servidor ACEPTÓ anular una venta cuyo mes no se puede determinar" \
  "3-D4-desconocido-exento (externo): exento: anuló SIN rastro"

# M17 — con VARIOS episodios de cierre, el detector toma el mes más antiguo en vez de lanzar el error de integridad.
frag "$DET" $'if pg_catalog.cardinality(v_meses_episodio) > 1 then\n      raise exception \'Integridad: el lead % tiene % episodios de cierre en el ledger\', p_lead_id, pg_catalog.cardinality(v_meses_episodio);\n    elsif pg_catalog.cardinality(v_meses_episodio) = 1 then' $'if pg_catalog.cardinality(v_meses_episodio) >= 1 then'
mutante "con varios episodios de cierre toma el mes más antiguo en vez del error de integridad" \
  "3-M-dos-episodios (avance): rechazó, pero no como siempre: P0409|No se puede anular: el mes de esta venta (2026-06) ya está sellado" \
  "3-M-dos-episodios-externo (externo): rechazó, pero no como siempre: P0409|No se puede anular: el mes de esta venta (2026-06) ya está sellado"

# M18 — la ACREDITACIÓN (y el episodio) se ignoran si falta `convertido_en`: «desconocido» decidido ANTES de mirar las fuentes
# autoritativas (el defecto de la ronda 1).
frag "$DET" $'  where l.id = p_lead_id;\n' $'  where l.id = p_lead_id;\n  if v_convertido_en is null then p_desconocido := true; return; end if;\n'
mutante "sin convertido_en el detector dice «desconocido» sin mirar la acreditación ni el episodio" \
  "3-D1-sin-fecha-acreditada (externo): rechazó, pero no con la regla: P0409|No se puede anular: no se puede determinar el mes" \
  "3-D2-sin-fecha-episodio (externo): rechazó, pero no con la regla: P0409|No se puede anular: no se puede determinar el mes"

# M19 — sin la guarda de aislamiento: en REPEATABLE READ la puerta acepta (ensayo de `aislamiento.sql`).
frag "$DET" $'if pg_catalog.current_setting(\'transaction_isolation\') <> \'read committed\' then' 'if false then'
mutante_aislamiento "el detector sin la guarda de aislamiento (acepta en repeatable read)" \
  "AISLAMIENTO (avance): la puerta ACEPTÓ anular en repeatable read" \
  "AISLAMIENTO (externo): la puerta ACEPTÓ anular en repeatable read"

# ── Ronda 3 (R2-2) ─────────────────────────────────────────────────────────────

# M20 — un mes NULO o NO CANÓNICO se trata como ABIERTO (fail-open): el día 10 (o un nulo) no casa con el sello del día 1, así
# que `exists (… pc.periodo = p_mes)` es falso y la puerta aceptaría. El detector debe responder con el error de integridad.
# (El oráculo siembra esos dos estados quitando, dentro del rollback y al final, los CHECK y el NOT NULL que los impiden.)
frag "$DET" $'if p_mes is null or p_mes <> pg_catalog.date_trunc(\'month\', p_mes::timestamp)::date then' 'if false then'
mutante "el mes nulo o no canónico se trata como abierto (fail-open)" \
  "3-N1-periodo-no-canonico (avance): el servidor ACEPTÓ la anulación" \
  "3-N2-periodo-nulo (avance): el servidor ACEPTÓ la anulación"

# ── Mutantes de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha ────────

# C1 — alguien concede EXECUTE sobre el detector: deja de ser privado.
mutante_sql "authenticated recibe EXECUTE sobre el detector" \
  "grant execute on function private.mes_sellado_de_venta(uuid) to authenticated;" \
  "9b:"

# C2 — el detector pasa a `security definer`: ya no es el patrón del núcleo INVOKER (hallazgo #3 de la ronda 1).
mutante_sql "el detector pasa a security definer" \
  "alter function private.mes_sellado_de_venta(uuid) security definer;" \
  "9b:"

# C3 — el detector pierde su `search_path` vacío.
mutante_sql "el detector pierde el search_path vacío" \
  "alter function private.mes_sellado_de_venta(uuid) set search_path = public;" \
  "9b:"

# C4 — una puerta pierde su EXECUTE para authenticated: la pantalla dejaría de poder anular.
mutante_sql "authenticated pierde EXECUTE sobre crm.anular_cierre_avance" \
  "revoke execute on function crm.anular_cierre_avance(uuid,text) from authenticated;" \
  "9a:"

# C5 — una puerta recibe EXECUTE con opción de concesión: la ACL ya no es la auditada (hallazgo #5 de la ronda 1).
mutante_sql "authenticated recibe EXECUTE WITH GRANT OPTION sobre crm.anular_cierre_externo" \
  "grant execute on function crm.anular_cierre_externo(uuid,text) to authenticated with grant option;" \
  "9a:"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "MUTANTES: los $((n - equivalentes)) mutantes de verdad murieron, cada uno por su fallo; $equivalentes equivalente(s) secuencial(es) confirmado(s) (la defensa es redundante en secuencia por la puerta). El oráculo prueba lo que dice probar."
  exit 0
fi
echo "MUTANTES: $fallos superviviente(s) o sin juzgar — hay defensas sin prueba."
exit 1
