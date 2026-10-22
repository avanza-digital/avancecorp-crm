#!/usr/bin/env bash
# MUTANTES del ensayo — por cada defensa, un mutante que la neutraliza.
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe la regla a
# propósito y se exige que el oráculo (`pruebas.sql`) lo GRITE: si un mutante
# sobrevive —el ensayo sigue verde con la defensa quitada—, esa defensa NO está
# probada y este guion falla.
#
# Hay dos clases. El mutante de CUERPO es el candado de la migración con UN
# fragmento cambiado. El de CATÁLOGO deja el cuerpo intacto y rompe su ficha
# (permisos, atributos, trigger): la regla puede estar bien escrita y no
# proteger nada. Los dos se instalan DESPUÉS de la migración real (cuyo
# postflight sella el cuerpo y la ficha buenos) y antes del oráculo, todo en la
# misma transacción, que termina en rollback.
#
# Un mutante solo cuenta como MUERTO si el ensayo sale ROJO y además nombra los
# fallos que le corresponden (el caso y su motivo). Un rojo por otra causa —un
# fallo incidental de la frontera, un error de montaje— no prueba la defensa
# que ese mutante rompe.
#
# (Lo que se rompe ANTES de la migración —la deriva de catálogo que su preflight
# tiene que rechazar— va en `derivas.sh`.)
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/no-asistio-espera-hora/mutantes.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin
# ella van a una carpeta temporal que se borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/no-asistio-espera-hora
MIG=supabase/migrations/20261022170100_crm_no_asistio_espera_hora.sql
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
  nombrados="$(grep -Eo '^FALLO [^:]+' "$salida" | tr '\n' ';' | sed 's/;$//; s/;/ · /g')"
  for debe in "$@"; do
    nombra "$salida" "$debe" || faltan="$faltan «FALLO $debe»"
  done
  # La marca separa «el mutante no se pudo instalar» (no se juzga: cuenta como
  # superviviente) de «el oráculo lo detectó» (muerto).
  if ! grep -q 'MUTANTE_INSTALADO' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR: $(grep -m 1 'ERROR' "$salida" | cut -c1-160)"
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

mutante() { # mutante <nombre> <fragmento vigente> <fragmento mutado> <fallo que debe nombrar>...
  n=$((n + 1))
  echo "$n. Mutante: $1"
  # El fragmento tiene que aparecer UNA sola vez en el candado: si la migración
  # cambia, el mutante se niega a mutar otra cosa sin que nadie se entere.
  if ! python3 - "$MIG" "$TMP/m$n.mutante.sql" "$2" "$3" <<'PY'
import sys
mig, salida, vigente, mutado = sys.argv[1:5]
s = open(mig, encoding='utf-8').read()
ini = s.index('create or replace function private.trg_tareas_before_update()')
fin = s.index('\n$$;', ini) + len('\n$$;')
candado = s[ini:fin]
assert candado.count(vigente) == 1, 'el candado cambió: revisar el mutante (%r)' % vigente
open(salida, 'w', encoding='utf-8').write(candado.replace(vigente, mutado) + '\n')
PY
  then
    echo "  ✗ no se pudo construir el mutante"
    fallos=$((fallos + 1))
    return
  fi
  juzgar "${@:4}"
}

# El mutante de catálogo no reemplaza el cuerpo: es una sentencia que cambia la
# ficha del candado. Tiene que morir NOMBRANDO el fallo que le corresponde; si
# el ensayo se pone rojo por otra cosa, esa defensa sigue sin estar probada.
mutante_de_catalogo() { # mutante_de_catalogo <nombre> <sentencia SQL> <fallo que debe nombrar>...
  n=$((n + 1))
  echo "$n. Mutante de catálogo: $1"
  printf '%s\n' "$2" > "$TMP/m$n.mutante.sql"
  juzgar "${@:3}"
}

# M1 — sin la regla: el candado vuelve a dejar pasar «No asistió» antes de la
# hora. Deben caer los nueve rechazos, y por ACEPTAR: 1, 2, 3, 5-antes y 6.
mutante "la regla no rechaza nada" \
  "and old.vence_en > clock_timestamp() then" \
  "and false then" \
  "1 (cerrar_reunion_v3): el servidor ACEPTÓ" \
  "1 (cerrar_reunion_v2): el servidor ACEPTÓ" \
  "1 (cerrar_reunion): el servidor ACEPTÓ" \
  "2 (cerrar_tarea_v2): el servidor ACEPTÓ" \
  "2 (cerrar_tarea): el servidor ACEPTÓ" \
  "3 (postventa_tarea_fn): el servidor ACEPTÓ" \
  "5-antes (cerrar_reunion_v3): el servidor ACEPTÓ" \
  "6-supervisor (cerrar_reunion_v3): el servidor ACEPTÓ" \
  "6-gerencia (cerrar_reunion_v3): el servidor ACEPTÓ"

# M2 — la comparación al revés: rechazaría las inasistencias de verdad y
# dejaría pasar las imposibles. Deben caer los rechazos y además los positivos
# con la hora pasada (4a, 5-despues, 3-despues, 6-*-pasada).
mutante "la comparación con la hora está invertida" \
  "and old.vence_en > clock_timestamp() then" \
  "and old.vence_en < clock_timestamp() then" \
  "1 (cerrar_reunion_v3): el servidor ACEPTÓ" \
  "4a (cerrar_reunion_v3): «No asistió» debía entrar y se rechazó (22023|" \
  "5-despues (cerrar_reunion_v3): «No asistió» debía entrar y se rechazó (22023|"

# M3 — la frontera adelantada: se podría marcar «No asistió» desde un minuto
# antes de la hora. Deben caer 3 y 5-antes (las citas a una hora siguen
# rechazadas: solo la frontera con reloj real lo ve).
mutante "la frontera se adelanta un minuto" \
  "and old.vence_en > clock_timestamp() then" \
  "and old.vence_en > clock_timestamp() + interval '1 minute' then" \
  "5-antes (cerrar_reunion_v3): el servidor ACEPTÓ" \
  "3 (postventa_tarea_fn): el servidor ACEPTÓ"

# M4 — la frontera retrasada: tras la hora habría que esperar un minuto más.
# Deben caer 5-despues, 3-despues y 5-misma-cita (el mismo envío repetido con
# la hora ya cumplida sigue sin entrar).
mutante "la frontera se retrasa un minuto" \
  "and old.vence_en > clock_timestamp() then" \
  "and old.vence_en + interval '1 minute' > clock_timestamp() then" \
  "5-despues (cerrar_reunion_v3): «No asistió» debía entrar y se rechazó (22023|" \
  "3-despues (postventa_tarea_fn): «No asistió» debía entrar y se rechazó (22023|" \
  "5-misma-cita (cerrar_reunion_v3): el mismo envío" \
  "5-misma-cita (postventa_tarea_fn): el mismo envío"

# M5 — el reloj de la transacción en vez del real: si la transacción esperó un
# candado mientras llegaba la hora, seguiría rechazando. El ensayo entero es
# UNA transacción, así que debe caer lo que ocurre después de la hora
# (5-despues, 3-despues, 5-misma-cita).
mutante "el reloj es el de la transacción (now) y no el real" \
  "and old.vence_en > clock_timestamp() then" \
  "and old.vence_en > now() then" \
  "5-despues (cerrar_reunion_v3): «No asistió» debía entrar y se rechazó (22023|" \
  "3-despues (postventa_tarea_fn): «No asistió» debía entrar y se rechazó (22023|" \
  "5-misma-cita (cerrar_reunion_v3): el mismo envío"

# M6 — la regla aplicada de más: también frena «Se realizó» antes de la hora,
# que es justo lo que Miguel pidió conservar. Deben caer 4b y 4b-postventa.
mutante "también frena «Se realizó» antes de la hora" \
  "and new.estado = 'no_show'" \
  "and new.estado in ('no_show', 'completada')" \
  "4b: «Se realizó» antes de la hora no entró (22023|" \
  "4b-postventa: «Se realizó» antes de la hora no entró (22023|"

# M7 — la regla aplicada a cualquier cierre: tampoco se podría cancelar ni
# reprogramar una cita antes de su hora. Deben caer 4b, 4c y 4d.
mutante "también frena cancelar y reprogramar antes de la hora" \
  "and new.estado = 'no_show'" \
  "and new.estado <> 'pendiente'" \
  "4c: cancelar antes de la hora no entró (22023|" \
  "4d: reprogramar antes de la hora no entró (22023|"

# M8 — la regla aplicada a lo que no es reunión: cambiaría la conducta de hoy
# de llamadas, WhatsApp y tareas. Debe caer 7.
mutante "también se aplica a tareas que no son reunión" \
  "if old.tipo = 'reunion' and new.estado = 'no_show'" \
  "if new.estado = 'no_show'" \
  "7-llamada (cerrar_tarea): «No asistió» debía entrar y se rechazó (22023|" \
  "7-whatsapp (cerrar_tarea): «No asistió» debía entrar y se rechazó (22023|" \
  "7-tarea (cerrar_tarea): «No asistió» debía entrar y se rechazó (22023|"

# M9 — otro SQLSTATE: la pantalla y el banco reconocen el rechazo por su
# código. Deben caer los rechazos, y por llegar con OTRO código (no por aceptar).
mutante "el rechazo sale con otro SQLSTATE" \
  $'pase la hora pactada\'\n      using errcode = \'22023\';' \
  $'pase la hora pactada\'\n      using errcode = \'P0001\';' \
  "1 (cerrar_reunion_v3): rechazó, pero no con la regla: P0001|Aún no llega la hora de la cita" \
  "3 (postventa_tarea_fn): rechazó, pero no con la regla: P0001|Aún no llega la hora de la cita"

# M10 — otro mensaje: el texto es lo que lee el analista en la pantalla. Deben
# caer los rechazos, y por llegar con OTRO texto.
mutante "el rechazo sale con otro mensaje" \
  "Aún no llega la hora de la cita: «No asistió» se registra cuando pase la hora pactada" \
  "Operación no permitida" \
  "1 (cerrar_reunion_v3): rechazó, pero no con la regla: 22023|Operación no permitida" \
  "3 (postventa_tarea_fn): rechazó, pero no con la regla: 22023|Operación no permitida"

# ── Mutantes de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha ────────

# M11 — alguien concede EXECUTE sobre el candado: deja de ser privado. Debe
# caer 9a, y solo 9a (la regla sigue funcionando).
mutante_de_catalogo "authenticated recibe EXECUTE sobre el candado" \
  "grant execute on function private.trg_tareas_before_update() to authenticated;" \
  "9a:"

# M12 — el candado deja de ser `security definer`: correría con los permisos de
# quien hace el UPDATE. Debe caer 9a.
mutante_de_catalogo "el candado deja de ser security definer" \
  "alter function private.trg_tareas_before_update() security invoker;" \
  "9a:"

# M13 — el trigger se deshabilita: ningún UPDATE pasa ya por el candado, así que
# la regla no rechaza nada aunque su cuerpo esté intacto. Debe caer 9b (y con
# él, los rechazos).
mutante_de_catalogo "el trigger del candado se deshabilita" \
  "alter table crm.tareas disable trigger trg_tareas_00_before_update;" \
  "9b:"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "MUTANTES: los $n murieron, cada uno por su fallo. El oráculo prueba lo que dice probar."
  exit 0
fi
echo "MUTANTES: $fallos superviviente(s) o sin juzgar — hay defensas sin prueba."
exit 1
