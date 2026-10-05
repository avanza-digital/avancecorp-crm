#!/usr/bin/env bash
# B8 · concurrencia de la carga de bases (20261004184501) con DOS sesiones reales (una transacción no puede probarla).
# Solo banco LOCAL de Docker (127.0.0.1, secreto JWT de desarrollo del CLI, sin SSL). ESCRIBE y CONFIRMA datos de prueba
# (bases «B8 conc …», teléfonos 9<run>8nnn, DNI 5<run>nnn): limpiar después con supabase/scripts/banco/limpiar-entre-corridas.sql
# (o la corrida del gate, que la ejecuta). La identidad unificada (resolver_en_puertas) se enciende como en producción y se
# deja como estaba.
# Escenarios: (1) dos lotes de la MISMA base con un teléfono en común (r1: el segundo NO espera: 55P03 al instante y reintenta);
# (2) dos lotes de bases distintas con dos teléfonos en orden cruzado; (3) lote y alta manual del mismo teléfono (lote primero);
# (4) alta manual primero y luego el lote; (5) dos armados desde el CRM con leads solapados en orden cruzado; (6) 5 rondas de
# lotes cruzados con DNI lanzados a la vez; armar bloquea FOR UPDATE SKIP LOCKED y evalúa SOLO lo bloqueado (r2): (7) reactivar
# y armar el mismo lead, en los dos órdenes; (8) vetar y armar; (9) sacar el lead del ámbito y armar; (10) abrir seguimiento
# (intento B6) y armar — con el lead tomado por el otro, el armado NO espera: «ocupado», y el reintento da el motivo real —;
# (11) armar y cargar un lote a la vez; (12) un lead que ENTRA al ámbito después de bloquear y se reactiva antes del INSERT no
# entra (la sesión del armado instrumenta, solo en su transacción deshecha, el ayudante del ámbito con pausas); (13) un lead
# bloqueado por otra transacción → «ocupado» sin esperar.
# Exige: ningún duplicado (un lead por teléfono y DNI), ningún interbloqueo (40P01) ni error, y los veredictos esperados.
# Uso: bash supabase/scripts/base-gestion/b8-concurrencia.sh --puerto 58122
set -uo pipefail
PUERTO=""
while [ $# -gt 0 ]; do case "$1" in --puerto) PUERTO="$2"; shift 2 ;; *) echo "uso: $0 --puerto <puerto>"; exit 2 ;; esac; done
[ -n "$PUERTO" ] || { echo "uso: $0 --puerto <puerto>"; exit 2; }
export PGPASSWORD="${PGPASSWORD:-postgres}"
Q() { psql -X -h 127.0.0.1 -p "$PUERTO" -U postgres -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
SALIDA=$(mktemp -d)
trap 'rm -rf "$SALIDA"' EXIT

local_ok=$(Q -c "select (md5(coalesce(current_setting('app.settings.jwt_secret', true), '')) = '2a60121f68a3f2b1fb7de7040cb89646' and (select not s.ssl from pg_stat_ssl s where s.pid = pg_backend_pid()) and to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is not null)::int")
[ "$local_ok" = "1" ] || { echo "ABORTADO: no es un banco LOCAL de Docker con B8 aplicada"; exit 2; }

RUN=$((RANDOM % 9000 + 1000))
P() { printf '9%s8%03d' "$RUN" "$1"; }          # teléfono de 9 dígitos
D() { printf '5%s%03d' "$RUN" "$1"; }           # DNI de 8 dígitos
S1=$(Q -c "select id from auth.users where email = 'sup1.crm@demo.avancecorp.pe'")
S2=$(Q -c "select id from auth.users where email = 'sup2.crm@demo.avancecorp.pe'")
G=$(Q -c "select id from auth.users where email = 'gerencia.crm@demo.avancecorp.pe'")
V1=$(Q -c "select id from auth.users where email = 'vend1.crm@demo.avancecorp.pe'")
[ -n "$S1" ] && [ -n "$S2" ] && [ -n "$G" ] && [ -n "$V1" ] || { echo "ABORTADO: faltan actores de seed:demo"; exit 2; }
BANDERA_ANTES=$(Q -c "select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'")
Q -c "update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas'" >/dev/null
restaurar() { Q -c "update crm.multiempresa_flags set activo = '${BANDERA_ANTES:-f}'::boolean where nombre = 'resolver_en_puertas'" >/dev/null; }
trap 'restaurar; rm -rf "$SALIDA"' EXIT  # la bandera vuelve a como estaba aunque el arnés aborte

# Sesión impersonada: como(<uuid>) imprime el preámbulo de una transacción con ese usuario como authenticated.
como() { printf "begin;\nselect set_config('request.jwt.claim.sub', '%s', true), set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true);\nset local role authenticated;\n" "$1" "$1"; }
fila() { printf '{"fila": %s, "nombre": "B8 conc %s", "telefono": "%s"%s}' "$1" "$1" "$2" "${3:+, \"dni\": \"$3\"}"; }

# Bases de la corrida (confirmadas): X de S1, Y de S2 (la crea Gerencia, E11).
BX=$( { como "$S1"; echo "select crm.crear_base(gen_random_uuid(), 'B8 conc X $RUN', 'archivo', null, 'x.csv')->>'base_id';"; echo "commit;"; } | Q | tail -1)
BY=$( { como "$G"; echo "select crm.crear_base(gen_random_uuid(), 'B8 conc Y $RUN', 'archivo', '$S2', 'y.csv')->>'base_id';"; echo "commit;"; } | Q | tail -1)
[ -n "$BX" ] && [ -n "$BY" ] || { echo "ABORTADO: no se crearon las bases"; restaurar; exit 1; }

lote() { # lote <actor> <base> <json> <espera_antes> <espera_despues> <archivo>
  ( sleep "$4"; { como "$1"; echo "select 'T0 ' || clock_timestamp();"; echo "select 'R ' || (crm.cargar_base_lote(gen_random_uuid(), '$2', '$3'::jsonb))::text;";
      echo "select 'T1 ' || clock_timestamp();"; echo "select pg_sleep($5);"; echo "commit;"; } | Q > "$6" 2>&1; echo "rc=$?" >> "$6" ) &
}
alta() { # alta <actor> <telefono> <espera_antes> <espera_despues> <archivo>
  ( sleep "$3"; { como "$1"; echo "select 'T0 ' || clock_timestamp();"; echo "select 'R ' || crm.crear_lead_si_disponible('B8 conc alta', '$2', 'oficina', 1000, 'PEN')::text;";
      echo "select 'T1 ' || clock_timestamp();"; echo "select pg_sleep($4);"; echo "commit;"; } | Q > "$5" 2>&1; echo "rc=$?" >> "$5" ) &
}
armar() { # armar <actor> <nombre> <ids csv> <espera_antes> <espera_despues> <archivo>
  ( sleep "$4"; { como "$1"; echo "select 'T0 ' || clock_timestamp();"; echo "select 'R ' || (crm.armar_base_crm(gen_random_uuid(), '$2', null, '{$3}'::uuid[]) - 'excluidos_detalle')::text;";
      echo "select 'T1 ' || clock_timestamp();"; echo "select pg_sleep($5);"; echo "commit;"; } | Q > "$6" 2>&1; echo "rc=$?" >> "$6" ) &
}
cat > "$SALIDA/ver.py" <<'PY'
import sys, json
modo = sys.argv[1]
linea = [l[2:] for l in open(sys.argv[2]) if l.startswith('R ')]
d = json.loads(linea[0]) if linea else {}
if modo == 'filas':
    print(','.join('%s:%s%s' % (x['fila'], x['veredicto'], '/' + x['motivo'] if 'motivo' in x else '') for x in d.get('filas', [])))
elif modo == 'estado':
    print(d.get('estado'))
else:
    print('%s|%s' % (d.get('incluidos'), json.dumps(d.get('excluidos_por_motivo'))))
PY
veredictos() { python3 "$SALIDA/ver.py" filas "$1"; }
ahora() { python3 -c 'import time; print(time.time())'; }
corre() { # corre <actor|postgres:actor> <sql que devuelve algo | STMT:sentencia> <espera_antes> <espera_despues> <archivo>: «R …» y «MS <duración>»
  ( sleep "$3"; t0=$(ahora)
    { case "$1" in
        postgres:*) printf "begin;\nselect set_config('request.jwt.claim.sub', '%s', true), set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true);\n" "${1#postgres:}" "${1#postgres:}" ;;
        *) como "$1" ;;
      esac
      case "$2" in STMT:*) echo "${2#STMT:};"; echo "select 'R ok';" ;; *) echo "select 'R ' || ($2)::text;" ;; esac
      echo "select pg_sleep($4);"; echo "commit;"; } | Q > "$5" 2>&1
    echo "rc=$?" >> "$5"; echo "MS $(python3 -c "print(int(($(ahora) - $t0) * 1000))")" >> "$5" ) &
}
ms() { grep '^MS ' "$1" | sed 's/^MS //'; }
detalle() { grep -o 'DETAIL: .*' "$1" | sed 's/^DETAIL: *//'; }
estado() { python3 "$SALIDA/ver.py" estado "$1"; }
armado() { python3 "$SALIDA/ver.py" armado "$1"; }
espera_ms() { python3 - "$1" <<'PY'
import sys,datetime,re
t=[l.split(' ',1)[1].strip() for l in open(sys.argv[1]) if l.startswith('T0 ') or l.startswith('T1 ')]
def f(s):
    s = re.sub(r'([+-]\d\d)$', r'\1:00', s)
    s = re.sub(r'\.(\d+)', lambda m: '.' + (m.group(1) + '000000')[:6], s)
    return datetime.datetime.fromisoformat(s)
print(int((f(t[1])-f(t[0])).total_seconds()*1000) if len(t)==2 else -1)
PY
}
FALLOS=0
chequea() { if [ "$2" = "$3" ]; then echo "PASS $1 · $3"; else echo "FAIL $1 · esperado $2 · obtenido $3"; FALLOS=$((FALLOS + 1)); fi; }

echo "=== B8 concurrencia · run $RUN · banco 127.0.0.1:$PUERTO ==="
# (1) misma base, teléfono en común (r1: NOWAIT): el segundo falla AL INSTANTE con 55P03 (no gasta sus 8 s esperando); el
#     reintento, cuando A terminó, ve la repetida.
LOTE1B="[$(fila 3 "$(P 2)"), $(fila 4 "$(P 3)")]"
lote "$S1" "$BX" "[$(fila 1 "$(P 1)"), $(fila 2 "$(P 2)")]" 0 2 "$SALIDA/1a"
corre "$S1" "crm.cargar_base_lote('00000000-0000-4000-8000-000000$(printf '%04d' "$RUN")01', '$BX', '$LOTE1B'::jsonb)" 0.5 0 "$SALIDA/nowait-1b"
wait
chequea '(1) lote A' '1:cargada,2:cargada' "$(veredictos "$SALIDA/1a")"
chequea '(1) lote B mientras A carga → 55P03 «Hay otra carga en curso de esta base; reintenta»' '1' "$(grep -c 'ERROR:  Hay otra carga en curso de esta base; reintenta' "$SALIDA/nowait-1b")"
echo "     lote B falló en $(ms "$SALIDA/nowait-1b") ms (sin esperar a A)"
corre "$S1" "crm.cargar_base_lote('00000000-0000-4000-8000-000000$(printf '%04d' "$RUN")01', '$BX', '$LOTE1B'::jsonb)" 0 0 "$SALIDA/1b"
wait
chequea '(1) reintento de B (mismo id de operación): el teléfono común ya está en la base' '3:repetida/en_base,4:cargada' "$(veredictos "$SALIDA/1b")"
# (2) bases distintas, dos teléfonos en orden cruzado: candados ordenados, sin interbloqueo; el segundo ve «ya existía».
lote "$S1" "$BX" "[$(fila 11 "$(P 11)"), $(fila 12 "$(P 12)")]" 0 2 "$SALIDA/2a"
lote "$G" "$BY" "[$(fila 13 "$(P 12)"), $(fila 14 "$(P 11)")]" 0.5 0 "$SALIDA/2b"
wait
chequea '(2) lote A (base X)' '11:cargada,12:cargada' "$(veredictos "$SALIDA/2a")"
chequea '(2) lote B (base Y, orden cruzado)' '13:ya_existia/descartado,14:ya_existia/descartado' "$(veredictos "$SALIDA/2b")"
echo "     lote B esperó $(espera_ms "$SALIDA/2b") ms"
# (3) lote primero, alta manual del mismo teléfono después: el alta espera y ve «enfriamiento».
lote "$S1" "$BX" "[$(fila 21 "$(P 21)")]" 0 2 "$SALIDA/3a"
alta "$V1" "$(P 21)" 0.5 0 "$SALIDA/3b"
wait
chequea '(3) lote' '21:cargada' "$(veredictos "$SALIDA/3a")"
chequea '(3) alta manual del mismo teléfono' 'enfriamiento' "$(estado "$SALIDA/3b")"
echo "     el alta esperó $(espera_ms "$SALIDA/3b") ms"
# (4) alta manual primero, lote después: el lote espera y ve «ya existía» (con dueño).
alta "$V1" "$(P 31)" 0 2 "$SALIDA/4a"
lote "$S1" "$BX" "[$(fila 31 "$(P 31)")]" 0.5 0 "$SALIDA/4b"
wait
chequea '(4) alta manual' 'creado' "$(estado "$SALIDA/4a")"
chequea '(4) lote del mismo teléfono' '31:ya_existia/con_dueno' "$(veredictos "$SALIDA/4b")"
echo "     el lote esperó $(espera_ms "$SALIDA/4b") ms"
# (5) dos armados con leads solapados en orden cruzado (descartados elegibles de V1, confirmados antes).
IDS=$(Q -c "with n as (
  insert into crm.leads (nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
  select 'B8 conc armar ' || i, '$(printf '9%s7' "$RUN")' || lpad(i::text, 3, '0'), 'oficina', 'nuevo', '$V1', 1000, 'PEN', '$V1', true from generate_series(1, 4) i
  returning id, telefono) select string_agg(id::text, ',' order by telefono) from n")
Q -c "update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id = any ('{$IDS}'::uuid[])" >/dev/null
IFS=, read -r L1 L2 L3 L4 <<< "$IDS"
armar "$S1" "B8 conc armada A $RUN" "$L1,$L2,$L3" 0 2 "$SALIDA/5a"
armar "$S1" "B8 conc armada B $RUN" "$L3,$L2,$L4" 0.5 0 "$SALIDA/5b"
wait
chequea '(5) armado A' '3|{}' "$(armado "$SALIDA/5a")"
chequea '(5) armado B (orden cruzado; L3 y L2 los tiene tomados A) → ocupado, sin esperar' '1|{"ocupado": [1, 2]}' "$(armado "$SALIDA/5b")"
chequea '(5) … y no esperó (< 1000 ms)' 'true' "$(python3 -c "print(str($(espera_ms "$SALIDA/5b") < 1000).lower())")"
# (6) 5 rondas: dos lotes de bases distintas con teléfonos y DNI en orden cruzado, lanzados A LA VEZ.
for r in 1 2 3 4 5; do
  a=$((100 + r * 10)); b=$((a + 1))
  lote "$S1" "$BX" "[$(fila "$a" "$(P "$a")" "$(D "$a")"), $(fila "$b" "$(P "$b")" "$(D "$b")")]" 0 0 "$SALIDA/6a$r"
  lote "$G" "$BY" "[$(fila "$b" "$(P "$b")" "$(D "$b")"), $(fila "$a" "$(P "$a")" "$(D "$a")")]" 0 0 "$SALIDA/6b$r"
  wait
done
# (7–11) r1 · armar bloquea FOR UPDATE (en orden de id) los leads del ámbito ANTES de evaluar. Descartados de V1 con capital.
IDS2=$(Q -c "with n as (
  insert into crm.leads (nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
  select 'B8 conc intercalar ' || i, '$(printf '9%s6' "$RUN")' || lpad(i::text, 3, '0'), 'oficina', 'nuevo', '$V1', 1000, 'PEN', '$V1', true from generate_series(1, 7) i
  returning id, telefono) select string_agg(id::text, ',' order by telefono) from n")
Q -c "update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id = any ('{$IDS2}'::uuid[])" >/dev/null
IFS=, read -r L7 L7B L8 L9 L10 L11A L11B <<< "$IDS2"
V3=$(Q -c "select id from auth.users where email = 'vend3.crm@demo.avancecorp.pe'")
armar_sql() { echo "crm.armar_base_crm(gen_random_uuid(), 'B8 conc $1 $RUN', null, '{$2}'::uuid[]) - 'excluidos_detalle'"; }
# (7) reactivar primero (V1), armar después (S1): armar espera la fila y la ve reactivada → no_descartado, sin base.
corre "$V1" "crm.reactivar_lead_base(gen_random_uuid(), '$L7')" 0 2 "$SALIDA/7a"
corre "$S1" "$(armar_sql 7 "$L7")" 0.5 0 "$SALIDA/7b"
wait
chequea '(7) reactivar mientras se arma: armar NO espera y lo deja fuera (ocupado, sin base)' 'contactado|{"excluidos_por_motivo": {"ocupado": [1]}}|true' \
  "$(grep '^R ' "$SALIDA/7a" | sed 's/^R //' | python3 -c 'import sys,json; print(json.load(sys.stdin)["etapa"])')|$(detalle "$SALIDA/7b")|$(python3 -c "print(str($(ms "$SALIDA/7b") < 1000).lower())")"
corre "$S1" "$(armar_sql 7r "$L7")" 0 0 "$SALIDA/7r"; wait
chequea '(7) el reintento, ya reactivado: no_descartado' '{"excluidos_por_motivo": {"no_descartado": [1]}}' "$(detalle "$SALIDA/7r")"
# (7b) armar primero, reactivar después: reactivar espera y luego pasa (E14: no se bloquea).
corre "$S1" "$(armar_sql 7b "$L7B")" 0 2 "$SALIDA/7c"
corre "$V1" "crm.reactivar_lead_base(gen_random_uuid(), '$L7B')" 0.5 0 "$SALIDA/7d"
wait
chequea '(7b) armar primero: lo incluye; reactivar espera y luego pasa' '1|contactado' \
  "$(armado "$SALIDA/7c" | cut -d'|' -f1)|$(grep '^R ' "$SALIDA/7d" | sed 's/^R //' | python3 -c 'import sys,json; print(json.load(sys.stdin)["etapa"])')"
echo "     reactivar esperó $(ms "$SALIDA/7d") ms"
# (8) vetar (V1) mientras se arma.
corre "$V1" "crm.marcar_no_contactar('$L8', 'B8 conc veto')" 0 2 "$SALIDA/8a"
corre "$S1" "$(armar_sql 8 "$L8")" 0.5 0 "$SALIDA/8b"
wait
chequea '(8) vetar mientras se arma: ocupado, sin esperar' '{"excluidos_por_motivo": {"ocupado": [1]}}|true' "$(detalle "$SALIDA/8b")|$(python3 -c "print(str($(ms "$SALIDA/8b") < 1000).lower())")"
corre "$S1" "$(armar_sql 8r "$L8")" 0 0 "$SALIDA/8r"; wait
chequea '(8) el reintento: no_contactar' '{"excluidos_por_motivo": {"no_contactar": [1]}}' "$(detalle "$SALIDA/8r")"
# (9) sacar el lead del ámbito de S1 (pasa a V3, equipo de S2) mientras S1 arma.
corre "postgres:$G" "STMT:update crm.leads set vendedor_id = '$V3' where id = '$L9'" 0 2 "$SALIDA/9a"
corre "$S1" "$(armar_sql 9 "$L9")" 0.5 0 "$SALIDA/9b"
wait
chequea '(9) el lead sale del ámbito mientras se arma: ocupado, sin esperar' 'ok|{"excluidos_por_motivo": {"ocupado": [1]}}|true' \
  "$(grep '^R ' "$SALIDA/9a" | sed 's/^R //')|$(detalle "$SALIDA/9b")|$(python3 -c "print(str($(ms "$SALIDA/9b") < 1000).lower())")"
corre "$S1" "$(armar_sql 9r "$L9")" 0 0 "$SALIDA/9r"; wait
chequea '(9) el reintento, ya fuera del ámbito: no_encontrado' '{"excluidos_por_motivo": {"no_encontrado": [1]}}' "$(detalle "$SALIDA/9r")"
# (10) el analista registra un intento (seguimiento activo B6) mientras se arma.
corre "$V1" "crm.registrar_intento_base(gen_random_uuid(), '$L10', 'no_contesto', 'B8 conc intento')" 0 2 "$SALIDA/10a"
corre "$S1" "$(armar_sql 10 "$L10")" 0.5 0 "$SALIDA/10b"
wait
chequea '(10) intento B6 mientras se arma: ocupado, sin esperar' '{"excluidos_por_motivo": {"ocupado": [1]}}|true' "$(detalle "$SALIDA/10b")|$(python3 -c "print(str($(ms "$SALIDA/10b") < 1000).lower())")"
corre "$S1" "$(armar_sql 10r "$L10")" 0 0 "$SALIDA/10r"; wait
chequea '(10) el reintento: en_gestion' '{"excluidos_por_motivo": {"en_gestion": [1]}}' "$(detalle "$SALIDA/10r")"
# (11) armar y un lote a la vez: no comparten nada; el lote no espera.
corre "$S1" "$(armar_sql 11 "$L11A,$L11B")" 0 2 "$SALIDA/11a"
lote "$S1" "$BX" "[$(fila 201 "$(P 201)"), $(fila 202 "$(P 202)")]" 0.5 0 "$SALIDA/11b"
wait
chequea '(11) armar y un lote a la vez: los dos terminan' '2|201:cargada,202:cargada' "$(armado "$SALIDA/11a" | cut -d'|' -f1)|$(veredictos "$SALIDA/11b")"
echo "     el lote tardó $(espera_ms "$SALIDA/11b") ms con el armado abierto"

# (12) (a) Codex r2 P1: L12 está FUERA del ámbito de S1 (de V3) cuando el armado bloquea; B lo pasa a V2 (equipo de S1) y C lo
#      reactiva ANTES del INSERT. Para que las tres cosas pasen en ese orden, la sesión A instrumenta (en su transacción, que se
#      deshace) private.bases_carga_en_subarbol con una pausa de 1,5 s cuando mira a V3 (al bloquear) y a V2 (al clasificar).
V2=$(Q -c "select id from auth.users where email = 'vend2.crm@demo.avancecorp.pe'")
IDS3=$(Q -c "with n as (
  insert into crm.leads (nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
  select 'B8 conc (12-13) ' || i, '$(printf '9%s5' "$RUN")' || lpad(i::text, 3, '0'), 'oficina', 'nuevo', case when i = 1 then '$V3' else '$V1' end::uuid,
         1000, 'PEN', '$V1', true from generate_series(1, 4) i
  returning id, telefono) select string_agg(id::text, ',' order by telefono) from n")
Q -c "update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id = any ('{$IDS3}'::uuid[])" >/dev/null
IFS=, read -r L12 L12OK L13 L13OK <<< "$IDS3"
( t0=$(ahora)
  { echo "begin;"
    echo "create or replace function private.bases_carga_en_subarbol(p_subarbol uuid[], p_vendedor_id uuid, p_asignado_supervisor_id uuid) returns boolean language plpgsql set search_path = '' as \$f\$ begin if p_vendedor_id in ('$V3', '$V2') then perform pg_catalog.pg_sleep(1.5); end if; return (p_vendedor_id = any (p_subarbol) or (p_vendedor_id is null and p_asignado_supervisor_id = any (p_subarbol))) is true; end \$f\$;"
    echo "select set_config('request.jwt.claim.sub', '$S1', true), set_config('request.jwt.claims', '{\"sub\":\"$S1\",\"role\":\"authenticated\"}', true);"
    echo "set local role authenticated;"
    echo "select 'R ' || (crm.armar_base_crm(gen_random_uuid(), 'B8 conc 12 $RUN', null, '{$L12,$L12OK}'::uuid[]) - 'excluidos_detalle')::text;"
    echo "rollback;"; } | Q > "$SALIDA/12a" 2>&1
  echo "rc=$?" >> "$SALIDA/12a"; echo "MS $(python3 -c "print(int(($(ahora) - $t0) * 1000))")" >> "$SALIDA/12a" ) &
corre "postgres:$G" "STMT:update crm.leads set vendedor_id = '$V2' where id = '$L12'" 0.5 0 "$SALIDA/12b"
corre "$S1" "crm.reactivar_lead_base(gen_random_uuid(), '$L12')" 2.2 0 "$SALIDA/12c"
wait
chequea '(12) entra al ámbito tras el bloqueo y se reactiva antes del INSERT: NO entra (ocupado); el elegible bloqueado sí' \
  '1|{"ocupado": [1]}|ok|contactado' \
  "$(armado "$SALIDA/12a")|$(grep '^R ' "$SALIDA/12b" | sed 's/^R //')|$(grep '^R ' "$SALIDA/12c" | sed 's/^R //' | python3 -c 'import sys,json; print(json.load(sys.stdin)["etapa"])')"
echo "     el armado tardó $(ms "$SALIDA/12a") ms (pausas instrumentadas); la reactivación, $(ms "$SALIDA/12c") ms (sin esperarlo)"
# (13) (b): otra transacción tiene tomado L13: el armado no espera; L13 → ocupado; L13OK entra.
corre "postgres:$G" "STMT:select 1 from crm.leads where id = '$L13' for update" 0 2 "$SALIDA/13a"
corre "$S1" "$(armar_sql 13 "$L13,$L13OK")" 0.5 0 "$SALIDA/13b"
wait
chequea '(13) un lead tomado por otra transacción → ocupado sin esperar; el otro entra' '1|{"ocupado": [1]}|true' \
  "$(armado "$SALIDA/13b")|$(python3 -c "print(str($(ms "$SALIDA/13b") < 1000).lower())")"
echo "     el armado tardó $(ms "$SALIDA/13b") ms con L13 tomado"

# Errores ESPERADOS: el 55P03 del escenario 1 y los 22023 «sin elegibles» de los armados que excluyen (7–10 y sus reintentos).
ESPERADOS="nowait-1b 7b 8b 9b 10b 7r 8r 9r 10r"
ERRORES=0; RC_MALOS=0
for a in "$SALIDA"/*; do
  b=$(basename "$a"); case " $ESPERADOS " in *" $b "*) continue ;; esac
  [ -f "$a" ] || continue; case "$b" in *.py) continue ;; esac
  ERRORES=$((ERRORES + $(grep -cE 'ERROR|deadlock|40P01' "$a" || true)))
  RC_MALOS=$((RC_MALOS + $(grep -h '^rc=' "$a" | grep -vc '^rc=0' || true)))
done
for b in 7b 8b 9b 10b 7r 8r 9r 10r; do
  [ "$(grep -c 'ERROR:  Ningún lead de la lista es elegible: no se crea la base' "$SALIDA/$b")" = "1" ] || ERRORES=$((ERRORES + 1))
done
chequea '(1–13) ninguna sesión con error inesperado ni interbloqueo (40P01)' '0|0|0' "$ERRORES|$RC_MALOS|$(cat "$SALIDA"/* | grep -c '40P01\|deadlock' || true)"
CARGADAS6=$(for r in 1 2 3 4 5; do veredictos "$SALIDA/6a$r"; veredictos "$SALIDA/6b$r"; done | tr ',' '\n' | grep -c ':cargada$' || true)
chequea '(6) en cada ronda cada contacto se carga UNA vez (10 de 20 filas)' '10' "$CARGADAS6"
DUP=$(Q -c "select count(*) from (select telefono from crm.leads where telefono like '+519${RUN}%' group by telefono having count(*) > 1) x")
DUPD=$(Q -c "select count(*) from (select dni from crm.leads where dni like '5${RUN}%' group by dni having count(*) > 1) x")
chequea 'ningún teléfono ni DNI duplicado en crm.leads' '0|0' "$DUP|$DUPD"
VALV=$(Q -c "select count(*) from pg_db_role_setting s cross join lateral unnest(s.setconfig) c(x) where c.x ilike 'crm.op_bases_carga=%'")
chequea 'la válvula no quedó en ninguna configuración persistente' '0' "$VALV"
restaurar
echo "TOTAL concurrencia: $([ "$FALLOS" -eq 0 ] && echo 'PASS' || echo "$FALLOS FAIL") · datos de prueba CONFIRMADOS en el banco (run $RUN): limpiar con limpiar-entre-corridas.sql"
[ "$FALLOS" -eq 0 ]
