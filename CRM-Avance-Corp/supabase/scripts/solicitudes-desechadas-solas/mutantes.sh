#!/usr/bin/env bash
# MUTANTES del ensayo — por cada defensa, un mutante que la neutraliza.
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe la regla a propósito y se exige que el oráculo (`pruebas.sql`) lo
# GRITE: si un mutante sobrevive —el ensayo sigue verde con la defensa quitada—, esa defensa NO está probada y este guion falla.
#
# Clases:
#   · de CUERPO: un fragmento cambiado en una pieza nueva (`private.solicitud_desechar`, `private.solicitudes_desechar_por_contrato`,
#     `private.solicitudes_desechar_ciclo`, `private.solicitud_cancelacion_vista`) o en una puerta re-emitida. Se instala DESPUÉS
#     de la migración (cuyo postflight ya selló lo bueno) y antes del oráculo, en la misma transacción, que termina en rollback.
#     Cada fragmento tiene que aparecer EXACTAMENTE las veces que se declara: si la migración cambia, el mutante se niega a mutar
#     otra cosa.
#   · de CATÁLOGO: el cuerpo queda intacto y se rompe la ficha (DEFINER, lock_timeout, permisos, comentario, job, auditor, CHECK).
#   · EQUIVALENTES: un fragmento cambiado que, en este ensayo, NO puede cambiar nada. El ensayo tiene que seguir VERDE.
#
# Un mutante solo cuenta como MUERTO si el ensayo sale ROJO y además nombra los fallos que le corresponden.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" DIR_ENSAYO=<carpeta> bash supabase/scripts/solicitudes-desechadas-solas/mutantes.sh
# DIR_ENSAYO=<carpeta> es obligatoria: ahí quedan los SQL generados y sus salidas (son la evidencia). Este guion no borra nada.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde quedan los SQL generados y sus salidas (la evidencia; no se borra nada)}"

DIR=supabase/scripts/solicitudes-desechadas-solas
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1

DESECHAR='private.solicitud_desechar(uuid,text,jsonb)'
POR_CONTRATO='private.solicitudes_desechar_por_contrato(uuid)'
CICLO='private.solicitudes_desechar_ciclo(timestamptz,integer,integer)'
VISTA='private.solicitud_cancelacion_vista(uuid)'
ALTA='crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'
CONSULTA='crm.solicitud_inversion_fn(uuid)'

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

veredicto() { grep -Eo 'ENSAYO (VERDE|ROJO)[^:]*' "$1" | head -n 1; }

fallos=0
equivalentes=0
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

juzgar_salida() { # juzgar_salida <salida> <marca de instalación> <fallo que debe nombrar>...
  local salida="$1" marca="$2" v nombrados debe faltan=""
  shift 2
  v="$(veredicto "$salida")"
  nombrados="$(grep -Eo '^FALLO [^:]+' "$salida" | sort -u | tr '\n' ';' | sed 's/;$//; s/;/ · /g')"
  for debe in "$@"; do
    nombra "$salida" "$debe" || faltan="$faltan «FALLO ${debe}»"
  done
  if ! grep -q "$marca" "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$v" != *"ROJO"* ]]; then
    echo "  ✗ MUTANTE SUPERVIVIENTE: ${v:-sin veredicto}"
    fallos=$((fallos + 1))
  elif [[ -n "$faltan" ]]; then
    echo "  ✗ ROJO SIN NOMBRAR SU FALLO (falta$faltan): $v: $nombrados"
    fallos=$((fallos + 1))
  else
    echo "  ✓ muere por su fallo ($v): $nombrados"
  fi
}

juzgar() { # juzgar <fallo que debe nombrar>... → arma, corre y juzga $TMP/m$n.mutante.sql
  if [[ "$#" -eq 0 ]]; then
    echo "  ✗ el mutante no declara por qué fallo tiene que morir"
    fallos=$((fallos + 1))
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

# ── Fragmentos vigentes (los que deja la migración, tal como los devuelve pg_get_functiondef) ─────────────────────────────
GUARDA_ESTADO=$'    when v_s.estado <> \'preparada\' then \'estado \' || v_s.estado\n'
GUARDA_CLAIM=$'    when v_s.auth_claim_id is not null then \'acceso Avance pendiente\'\n'
GUARDA_INVERSION=$'    when v_s.inversion_id is not null then \'con inversion\'\n'
GUARDA_CONTRATO=$'    when exists (select 1 from private.contrato_altas_idempotentes a where a.clave = v_s.id) then \'ya creo su contrato\'\n'
EXCEPCION=$'  exception when others then\n    return \'rechazada: \' || sqlstate || \' \' || sqlerrm;\n'
RECHAZADA=$'    return \'rechazada: \' || sqlstate || \' \' || sqlerrm;'
SKIP_LOCKED='for update skip locked'
MOTIVO_NUMERO=$'      when pg_catalog.btrim(v_s.datos -> \'contrato\' ->> \'numero_contrato\') is distinct from p_detalle ->> \'numero_contrato\' then \'el numero cambio bajo el candado\'\n'
MOTIVO_MOVIMIENTO=$'      when v_s.actualizado_en is distinct from (p_detalle ->> \'ultimo_movimiento\')::timestamptz then \'se movio bajo el candado\'\n'
MOTIVO_CORTE=$'      when v_s.actualizado_en > (p_detalle ->> \'corte\')::timestamptz - pg_catalog.make_interval(days => (p_detalle ->> \'dias\')::integer) then \'ya no cumple el corte\'\n'
CREADORAS=$'       and s.id <> all (v_creadoras)\n'
EMPRESA_ALTA=$'       and e.crea_contrato_avance\n       and pg_catalog.btrim(s.datos -> \'contrato\' ->> \'numero_contrato\') = v_numero\n'
NUMERO_ALTA=$'       and pg_catalog.btrim(s.datos -> \'contrato\' ->> \'numero_contrato\') = v_numero\n'
DETALLE_ALTA="v_detalle := pg_catalog.jsonb_build_object('via', 'alta', 'contrato_id', p_contrato_id, 'numero_contrato', v_numero);"
UMBRAL=$'       and s.actualizado_en <= v_umbral\n'
# Ronda 4: la exclusión de la memoria idempotente está en las DOS pasadas; cada fragmento lleva su línea siguiente para ser único.
EXCLUSION_CICLO=$'       and not exists (select 1 from private.contrato_altas_idempotentes a where a.clave = s.id)\n     order by s.creado_en, s.id\n'
EXCLUSION_CICLO_MUT=$'     order by s.creado_en, s.id\n'
EXCLUSION_PASADA2=$'       and not exists (select 1 from private.contrato_altas_idempotentes a where a.clave = s.id)\n       and s.actualizado_en <= v_umbral\n'
EXCLUSION_PASADA2_MUT=$'       and s.actualizado_en <= v_umbral\n'
PRESUPUESTO_P1=$'    if v_res = \'cancelada\' then v_nu_c := v_nu_c + 1; v_restante := v_restante - 1;\n'
PRESUPUESTO_P1_MUT=$'    if v_res = \'cancelada\' then v_nu_c := v_nu_c + 1;\n'
PRESUPUESTO_P2=$'    exit when v_restante <= 0;\n    v_res := private.solicitud_desechar(r.id, \'sin_movimiento\',\n'
PRESUPUESTO_P2_MUT=$'    v_res := private.solicitud_desechar(r.id, \'sin_movimiento\',\n'
LIMITE_ANTES=$'     order by s.actualizado_en, s.id\n  loop\n'
LIMITE_ANTES_MUT=$'     order by s.actualizado_en, s.id\n     limit p_limite\n  loop\n'
CONTRATO_NUMERO=$'    if v_num_contrato is distinct from p_detalle ->> \'numero_contrato\' then\n      return \'omitida: el contrato ya no lleva ese numero\';\n    end if;\n'
CONTRATO_EXISTE=$'    if not found then\n      return case when exists (select 1 from public.contratos c where c.id = v_contrato_id)\n                  then \'omitida: contrato ocupado por otra sesion\' else \'omitida: el contrato ya no existe\' end;\n    end if;\n'
EMPRESA_CICLO=$'      join crm.empresas e on e.id = s.empresa_id\n      join public.contratos c on c.numero_contrato = pg_catalog.btrim(s.datos -> \'contrato\' ->> \'numero_contrato\')\n     where s.estado = \'preparada\'\n       and e.crea_contrato_avance\n'
EMPRESA_CICLO_MUT=$'      join crm.empresas e on e.id = s.empresa_id\n      join public.contratos c on c.numero_contrato = pg_catalog.btrim(s.datos -> \'contrato\' ->> \'numero_contrato\')\n     where s.estado = \'preparada\'\n       and true\n'
SIN_MOV_WHERE=$'     where s.estado = \'preparada\'\n       and s.auth_claim_id is null\n       and s.inversion_id is null\n       and not exists (select 1 from private.contrato_altas_idempotentes a where a.clave = s.id)\n       and s.actualizado_en <= v_umbral\n'
SIN_MOV_WHERE_MUT=$'     where s.estado = \'preparada\'\n       and s.auth_claim_id is null\n       and s.inversion_id is null\n       and not exists (select 1 from private.contrato_altas_idempotentes a where a.clave = s.id)\n       and s.actualizado_en <= v_umbral\n       and s.empresa_id = (select e.id from crm.empresas e where e.crea_contrato_avance)\n'
INSERT_CORRIDA=$'  insert into crm.solicitudes_desechadas_corridas\n    (id, corte, dias, limite, canceladas_numero_usado, canceladas_sin_movimiento, omitidas, rechazadas, detalle, duracion_ms)\n  values\n    (v_corrida, p_corte, p_dias, p_limite, v_nu_c, v_sm_c, v_nu_o + v_sm_o, v_nu_r + v_sm_r, v_lista, v_duracion);\n'
LLAMADA_ALTA=$'  perform private.solicitudes_desechar_por_contrato(v_contrato_id);\n'
VISTA_CONSULTA='||private.solicitud_cancelacion_vista(p_solicitud)'
TEXTO_NUMERO="|| ' ya lo usa otro contrato.'"
TEXTO_DIAS="|| ' días sin confirmarse ni corregirse.'"

# ── La pieza escritora (private.solicitud_desechar) ──────────────────────────────────────────────────────────────────────
frag "$DESECHAR" "$GUARDA_CLAIM" ''
mutante "sin la guarda del acceso Avance pendiente: el alta cancela S4" 'R3-s4-intacta'
frag "$DESECHAR" "$GUARDA_INVERSION" ''
mutante "sin la guarda «con inversión»: el alta cancela S5" 'R3-s5-intacta'
frag "$DESECHAR" "$GUARDA_CONTRATO" ''
mutante "sin la guarda «ya creó su contrato»: el alta cancela S7" 'R3-s7-intacta'
frag "$DESECHAR" "$EXCEPCION" ''
mutante "sin la subtransacción: el rechazo del disparador de S8 tumba el alta" 'R1-alta-entra'
frag "$DESECHAR" "$RECHAZADA" "    return 'cancelada';"
mutante "el rechazo del disparador se informa como «cancelada»" 'R4-pieza-informa'
frag "$DESECHAR" "$GUARDA_ESTADO" ''
equivalente "sin la guarda de estado en la pieza escritora" "quien la llama ya filtra estado = preparada y el UPDATE también lo exige"
frag "$DESECHAR" "$SKIP_LOCKED" 'for update'
equivalente "sin SKIP LOCKED" "en una sola sesión nadie tiene la fila: la espera no se puede medir aquí (se documenta)"
# Ronda 3 (P2 del auditor): la relectura del MOTIVO bajo el candado, una defensa por cada rama.
frag "$DESECHAR" "$MOTIVO_NUMERO" ''
mutante "sin releer el número bajo el candado: S3 (lleva N2) se cancela como si llevara N1" 'R12-numero-releido'
frag "$DESECHAR" "$MOTIVO_CORTE" ''
mutante "sin releer el corte bajo el candado: S12 (29 días 23 h) se cancela como sin movimiento" 'R12-corte-releido'
frag "$DESECHAR" "$MOTIVO_MOVIMIENTO" ''
mutante "sin releer el último movimiento bajo el candado: S12 se cancela con un movimiento observado que no es el suyo" 'R12-movimiento-releido'
# Ronda 4 (Codex r1, P2-1): el CONTRATO del motivo, releído bajo candado.
frag "$DESECHAR" "$CONTRATO_NUMERO" ''
mutante "sin releer el número del contrato bajo candado: S3 se cancela con un detalle cuyo contrato lleva otro número" 'R13-contrato-releido'
frag "$DESECHAR" "$CONTRATO_EXISTE" ''
mutante "sin comprobar que el contrato del detalle exista: un contrato inexistente no se distingue" 'R13-contrato-inexistente'

# ── La pieza del alta (private.solicitudes_desechar_por_contrato) ────────────────────────────────────────────────────────
frag "$POR_CONTRATO" "$CREADORAS" ''
equivalente "sin excluir a la creadora en la pieza del alta" "la creadora está protegida DOS veces: cuando corre la pieza, su clave de idempotencia (= su id) ya está en private.contrato_altas_idempotentes, así que sin la exclusión S16 llega a private.solicitud_desechar y la guarda «ya creó su contrato» la omite (medido: 3 → 4 omitidas, 0 canceladas; el oráculo fija en R4 canceladas y rechazadas, no las omitidas). La exclusión se conserva: es barata y explícita (ronda 2, informe parcial H2)"
frag "$POR_CONTRATO" "$EMPRESA_ALTA" "       and true
$NUMERO_ALTA"
mutante "sin mirar la empresa: el alta cancela la de Prodelco (S6)" 'R3-s6-intacta'
frag "$POR_CONTRATO" "$NUMERO_ALTA" "       and pg_catalog.btrim(s.datos -> 'contrato' ->> 'numero_contrato') is not null
"
equivalente "sin comparar el número en el FILTRO de la pieza del alta" "desde la ronda 3 la pieza escritora relee el número bajo el candado: sin el filtro, S3 (N2) llega a la pieza y se omite («el numero cambio bajo el candado»); solo cambia el contador de omitidas, que R4 no fija. Defensa duplicada a propósito: el filtro evita candados inútiles, la relectura protege contra la carrera (hasta la ronda 2 este mutante moría por R3-s3-intacta)"
frag "$POR_CONTRATO" "$DETALLE_ALTA" "v_detalle := pg_catalog.jsonb_build_object('via', 'tarea', 'contrato_id', p_contrato_id, 'numero_contrato', v_numero);"
mutante "el detalle dice vía «tarea» en vez de «alta»" 'R2-s1-detalle'

# ── La tarea (private.solicitudes_desechar_ciclo) ────────────────────────────────────────────────────────────────────────
frag "$CICLO" "$UMBRAL" "       and s.actualizado_en <= v_umbral + interval '1 day'
"
mutante "el umbral de 30 días se mueve un día en la consulta de candidatas: S12 (29 días 23 h) llega a la pieza, que la omite por el corte (relectura de la ronda 3), y los contadores lo delatan" 'R8-contadores'
frag "$CICLO" "$EXCLUSION_CICLO" "$EXCLUSION_CICLO_MUT"
mutante "la pasada del número usado no excluye a la que ya creó su contrato (S15 llega a la pieza y se omite): los contadores lo delatan" 'R8-contadores'
# Ronda 4 (Codex r1, P2-2 y P2-3): presupuesto único por corrida y progreso.
frag "$CICLO" "$PRESUPUESTO_P1" "$PRESUPUESTO_P1_MUT"
mutante "la pasada del número usado no descuenta el presupuesto: la corrida A cancela 203 en vez de 200" 'R14-presupuesto-corrida-a'
frag "$CICLO" "$PRESUPUESTO_P2" "$PRESUPUESTO_P2_MUT"
mutante "la pasada de 30 días ignora el presupuesto: la corrida A cancela 253 en vez de 200" 'R14-presupuesto-corrida-a'
frag "$CICLO" "$LIMITE_ANTES" "$LIMITE_ANTES_MUT"
mutante "el límite se aplica ANTES de las guardas (LIMIT en la consulta de candidatas): 205 rechazadas tapan a la válida" 'R15-progreso-corrida-a'
frag "$CICLO" "$EXCLUSION_PASADA2" "$EXCLUSION_PASADA2_MUT"
mutante "la pasada de 30 días no descarta la memoria idempotente antes del recorrido: S19 llega a la pieza" 'R8-s19-ni-candidata'
frag "$CICLO" "$EMPRESA_CICLO" "$EMPRESA_CICLO_MUT"
mutante "la pasada del número usado ignora la empresa: cancela la de Prodelco (S6)" 'R8-s6-intacta'
frag "$CICLO" "$SIN_MOV_WHERE" "$SIN_MOV_WHERE_MUT"
mutante "la pasada de 30 días solo mira Avance: S11 (Prodelco) sigue preparada" 'R8-s11-sin-movimiento'
frag "$CICLO" "$INSERT_CORRIDA" ''
mutante "la tarea no deja su corrida" 'R8-corrida'

# ── Las puertas y la vista ───────────────────────────────────────────────────────────────────────────────────────────────
frag "$ALTA" "$LLAMADA_ALTA" ''
mutante "el alta v2 no llama a la pieza" 'R2-s1-cancelada' 'K2-alta-llama-a-la-pieza'
frag "$CONSULTA" "$VISTA_CONSULTA" ''
mutante "la consulta no añade la vista de la cancelación" 'R7-consulta-motivo' 'R7-consulta-sin-motivo' 'K2-consulta-con-vista'
frag "$VISTA" "$TEXTO_NUMERO" "|| ' ya lo usa otro contrato'"
mutante "el texto del número usado cambia" 'R7-consulta-motivo'
frag "$VISTA" "$TEXTO_DIAS" "|| ' dias sin confirmarse ni corregirse.'"
mutante "el texto de «sin movimiento» cambia" 'R10-texto-sin-movimiento'

# ── Catálogo ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
mutante_sql "authenticated gana EXECUTE sobre la pieza escritora" "grant execute on function $DESECHAR to authenticated;" 'K1-piezas-ficha'
mutante_sql "la tarea pasa a SECURITY DEFINER" "alter function $CICLO security definer;" 'K1-piezas-ficha'
mutante_sql "la tarea pierde su lock_timeout" "alter function $CICLO reset lock_timeout;" 'K1-piezas-ficha'
mutante_sql "la vista pasa a VOLATILE" "alter function $VISTA volatile;" 'K1-piezas-ficha'
mutante_sql "la consulta pierde el comentario del bloque" "comment on function $CONSULTA is 'otro comentario';" 'K2-consulta-con-vista'
mutante_sql "anon gana EXECUTE sobre el alta v2" "grant execute on function $ALTA to anon;" 'K2-alta-llama-a-la-pieza'
mutante_sql "el job se desprograma" "select cron.unschedule('crm-solicitudes-desechar');" 'K4-cron'
mutante_sql "el job cambia de comando" "select cron.schedule('crm-solicitudes-desechar', '17 7 * * *', 'select 1');" 'K4-cron'
mutante_sql "la tabla de corridas pierde su auditor (la regla de auditoría la lista)" "drop trigger trg_audit_solicitudes_desechadas_corridas on crm.solicitudes_desechadas_corridas;" 'K3-tabla-corridas' 'K3-trinquete-auditoria-idem'
mutante_sql "authenticated gana SELECT sobre la tabla de corridas" "grant select on crm.solicitudes_desechadas_corridas to authenticated;" 'K3-tabla-corridas'
mutante_sql "el CHECK que ata el motivo al estado desaparece" "alter table crm.inversion_solicitudes drop constraint inversion_solicitud_cancelacion_coherente;" 'K3-columnas-y-check'

echo
echo "RESUMEN: $n ensayos · $((n - fallos - equivalentes)) mutantes muertos · $equivalentes equivalentes confirmados · $fallos fallo(s)"
[[ "$fallos" -eq 0 ]] || exit 1
