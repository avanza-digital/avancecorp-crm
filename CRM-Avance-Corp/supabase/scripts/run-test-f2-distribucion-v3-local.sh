#!/bin/bash
# Banco local de F2.3b (Distribucion v3: porcentajes servidos + nucleo + sondas).
#
# La promesa de F2.3b es triple y el banco la comprueba en este orden:
#   1. PARIDAD: v3 sin sus claves nuevas ES v2 byte a byte (no cambia nada vivo).
#   2. VALORES: punteria/nucleo/sondas contra un calculo A MANO del fixture.
#   3. GATE: vendedora y anonimo fuera; gerencia dentro; v1/v2 intactas.
# Y despues: 6 mutantes (cada defensa con su asesino) + ensayo del ROLLBACK.
#
# El mundo se monta como el de F2.3a (mismos stubs, mismos vivos byte a byte),
# se aplica F1 y F2.3a para llegar al MISMO estado que produccion tiene hoy
# (anclado por md5), y solo entonces se aplica F2.3b SIN neutralizar su
# preflight: los candados se prueban de verdad.
#
# Uso: run-test-f2-distribucion-v3-local.sh <dir-f1-vivos> <dir-f2-vivos> <dir-f23b-vivos>
set -euo pipefail
VIVOS1="${1:?dir f1-vivos}"
VIVOS2="${2:?dir f2-vivos}"
VIVOS3="${3:?dir f23b-vivos}"
MIGDIR="$(cd "$(dirname "$0")/../migrations" && pwd)"
AQUI="$(cd "$(dirname "$0")" && pwd)"
DB=crm_f23b_banco
H=127.0.0.1; PT=5432; U=postgres
MIG="$MIGDIR/20260827090000_crm_f2_3b_distribucion_v3.sql"
# Anclas de PRODUCCION (27/08, post-F2.3a): el banco tiene que llegar a ellas.
MD5_CORE_PROD="f8748197c550484ae59b6257397a5013"        # core post-2.3a
MD5_V2CORE_PROD="7408cb964af34dfb091108c5a7062cc4"      # v2_core vivo
MD5_AUTORIZADA_PROD="a45b00eb7beca4cf80dea2c138d65848"  # despachador vivo
MD5_SANITIZAR_PROD="3bb8707046c61864c2b028b47231c544"   # sanitizador vivo
MD5_V2FN_PROD="4f9186ab5d73f9f4e9114f271aa78a15"        # puerta v2 viva
MD5_NUCLEO_PROD="7d2940a0f3368bacf3a5e719c76bfff5"      # nucleo post-F1

md5_de() { # $1 esquema, $2 funcion
  psql -h $H -p $PT -U $U -X -t -A -d $DB -c "
    select md5(pg_get_functiondef(p.oid)) from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='$1' and p.proname='$2'"
}

exigir_ancla() { # $1 esquema, $2 funcion, $3 md5 esperado
  local real; real=$(md5_de "$1" "$2")
  if [ "$real" != "$3" ]; then
    echo "❌ ancla rota: $1.$2 local $real ≠ prod $3"; exit 1
  fi
}

montar() {
  psql -h $H -p $PT -U $U -X -q -c "drop database if exists $DB" -c "create database $DB"
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB <<'SQL' >/dev/null
create schema crm; create schema private; create schema banco; create schema auth;
-- Roles de plataforma: la migracion revoca de ellos y el banco debe tenerlos.
do $roles$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $roles$;
-- Sesion conmutable: el gate del despachador se prueba en negativo Y positivo
-- (leccion de F2.1: un gate que solo se prueba en negativo no se prueba).
-- Ademas cae al JWT como en prod: el postflight 5.5 de la migracion prueba la
-- cadena real via set_config('request.jwt.claims', ...).
create table banco.uid_actual (uid uuid);
insert into banco.uid_actual values (null);
create function auth.uid() returns uuid language sql stable
  as $uid$ select coalesce(
    (select uid from banco.uid_actual limit 1),
    (nullif(current_setting('request.jwt.claims', true), '')::json->>'sub')::uuid
  ) $uid$;
create function private.es_lector_global() returns boolean
  language sql stable as 'select false';
-- Stubs con la FORMA de las tablas reales (identicos a los del banco F2.3a).
create table public.perfiles (id uuid primary key, nombre_completo text, activo boolean default true);
create table crm.equipo (perfil_id uuid primary key, rol_crm text, supervisor_id uuid,
  activo boolean default true, capacidad_leads_objetivo int);
create function private.rol_crm(p_perfil_id uuid) returns text
  language sql stable set search_path=''
  as 'select e.rol_crm from crm.equipo e where e.perfil_id = p_perfil_id';
create table crm.leads (id uuid primary key, activo boolean default true, etapa text,
  origen text, creado_en timestamptz, vendedor_id uuid, contrato_id uuid,
  monto_estimado numeric, moneda text, categoria_interes text, asignado_supervisor_id uuid);
create table crm.lead_asignaciones (id uuid primary key default gen_random_uuid(),
  analista_id uuid, lead_id uuid, origen text, motivo_apertura text, aproximado boolean,
  asignado_en timestamptz, resultado text, resultado_en timestamptz, finalizado_en timestamptz,
  moneda text, monto_estimado numeric, motivo_cierre text);
create table crm.actividades (lead_id uuid, tipo text, creado_en timestamptz,
  metadata jsonb, creado_por uuid);
create table crm.operaciones_cartera (id uuid primary key default gen_random_uuid(),
  cliente_id uuid, vendedor_id uuid, tipo text, fecha_operacion date, periodo date,
  moneda text, capital_renovado numeric, capital_adicional numeric,
  elegible_conversion boolean, creado_en timestamptz);
create table crm.conversion_pesos (vigente_desde date primary key, peso_referido numeric);
insert into crm.conversion_pesos values ('2026-01-01', 0.15);
create table private.anulados_stub (lead_id uuid primary key);
create function private.rango_capital_pen(n numeric) returns text
  language sql immutable as 'select ''pen_0_1000''::text';
create function private.umbral_estancamiento(e text) returns interval
  language sql immutable as 'select interval ''7 days''';
create function private.cierre_anulado(l uuid) returns boolean
  language sql stable set search_path=''
  as 'select exists (select 1 from private.anulados_stub a where a.lead_id = l)';
-- El SLA global NO es objeto de esta fase: stub con las claves que v2 lee.
create function private.metricas_sla_global_core(p_desde date, p_hasta date, p_ahora timestamptz)
  returns jsonb language sql stable set search_path=''
  as $sla$ select jsonb_build_object(
    'cohorte_ciclos', 0, 'cohorte_leads_unicos', 0, 'contactos', 0,
    'sla_evaluables', 0, 'sla_en_24h', 0, 'primer_contacto_mediana_minutos', null,
    'sin_contacto_vencidos_actuales', 0, 'reasignaciones_cohorte', 0,
    'ciclos_aproximados_cohorte', 0) $sla$;
SQL
  # Los VIVOS, byte a byte (el md5 se exige mas abajo)
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS1/private__cierre_externo_anulado.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS1/private__etiqueta_mes_es.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS1/private__conversion_mensual_por_vendedor.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS2/private__peso_referido_conversion.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS2/private__metricas_distribucion_leads_core.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS3/private__metricas_distribucion_leads_v2_core.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS3/private__sanitizar_sujetos_distribucion_crm.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS3/private__metricas_distribucion_leads_autorizada.sql" >/dev/null
  # La CADENA REAL de privilegios, reproducida
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB <<'SQL2' >/dev/null
do $r$ begin
  if not exists (select 1 from pg_roles where rolname='crm_metricas_bridge')
    then create role crm_metricas_bridge; end if;
end $r$;
grant usage on schema private to crm_metricas_bridge;
grant execute on function private.metricas_distribucion_leads_autorizada(date,date,smallint)
  to crm_metricas_bridge;
SQL2
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS2/crm__metricas_distribucion_leads_v2_fn.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB -c \
    "alter function crm.metricas_distribucion_leads_v2_fn(date,date) owner to crm_metricas_bridge;
     revoke all on function crm.metricas_distribucion_leads_v2_fn(date,date) from public;
     grant execute on function crm.metricas_distribucion_leads_v2_fn(date,date) to crm_metricas_bridge;" >/dev/null
  # F1 (tabla-base) y F2.3a (el core que hoy vive en prod), como las aplico prod
  sed "s/raise exception '[^']*re-capturar[^']*';/null;/" \
    "$MIGDIR/20260826233000_crm_f1_conversion_episodios.sql" \
    | psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 --single-transaction -d $DB -f - >/dev/null
  sed -e "s/raise exception '[^']*re-capturar[^']*';/null;/" \
      -e "s/raise exception 'el owner del wrapper[^']*';/null;/" \
      "$MIGDIR/20260827050000_crm_f2_3a_distribucion_sin_anulados.sql" \
    | psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 --single-transaction -d $DB -f - >/dev/null
  # El banco tiene que estar EXACTAMENTE donde esta produccion hoy:
  exigir_ancla private metricas_distribucion_leads_core       "$MD5_CORE_PROD"
  exigir_ancla private metricas_distribucion_leads_v2_core    "$MD5_V2CORE_PROD"
  exigir_ancla private metricas_distribucion_leads_autorizada "$MD5_AUTORIZADA_PROD"
  exigir_ancla private sanitizar_sujetos_distribucion_crm     "$MD5_SANITIZAR_PROD"
  exigir_ancla crm     metricas_distribucion_leads_v2_fn      "$MD5_V2FN_PROD"
  exigir_ancla private conversion_mensual_por_vendedor        "$MD5_NUCLEO_PROD"
  # Fixtures: el de F2.3a + el episodio USD y la gerencia de F2.3b
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB \
    -f "$AQUI/fixture-f2-distribucion.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB \
    -f "$AQUI/fixture-f2-distribucion-v3.sql" >/dev/null
}

aplicar() { # $1 = migracion (original o mutante) — SIN sed: el preflight es real
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 --single-transaction -d $DB -f "$1" >/dev/null
}

echo "════ F2.3b · CASO REAL ════"
montar
aplicar "$MIG"
psql -h $H -p $PT -U $U -X -v ON_ERROR_STOP=1 -d $DB -f "$AQUI/test-f2-distribucion-v3.sql"

echo
echo "════ F2.3b · ROLLBACK ════"
psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB \
  -f "$AQUI/rollback-f2-3b-distribucion-v3.sql"
exigir_ancla private metricas_distribucion_leads_autorizada "$MD5_AUTORIZADA_PROD"
echo "✅ rollback deja el despachador byte a byte como el vivo pre-F2.3b"

echo
echo "════ F2.3b · MUTANTES ════"
TMPD=$(mktemp -d)
declare -a N=(
  "M1 el nucleo vuelve a contar cierres ANULADOS"
  "M2 la punteria pierde los descartados del divisor"
  "M3 la rama v2 del despachador se desvia al motor v3"
  "M4 la puerta v3 queda abierta a PUBLIC"
  "M5 el USD suma el campo equivocado"
  "M6 cada rango recibe la punteria del analista entero"
  "M7 la rama v1 queda pisada por una v2 (Codex c3: el strpos solo no lo ve)"
  "M8 el referido pondera al 100% (Codex b6: factor pisado a 1)"
  "M9 el numerador pierde las operaciones de cartera (Codex b6)"
)
declare -a S=(
  "s/e.tipo = 'cierre' and not e.anulado and not e.fue_referido/e.tipo = 'cierre' and not e.fue_referido/;s/e.tipo = 'cierre' and not e.anulado and e.fue_referido/e.tipo = 'cierre' and e.fue_referido/"
  "s|/ (coalesce(p_convertidos, 0) + coalesce(p_descartados, 0)), 6)|/ greatest(coalesce(p_convertidos, 0), 1), 6)|"
  "s/v_payload:=private.metricas_distribucion_leads_v2_core(p_desde,p_hasta,v_ahora);/v_payload:=private.metricas_distribucion_leads_v3_core(p_desde,p_hasta,v_ahora);/"
  "s/^revoke all on function crm.metricas_distribucion_leads_v3_fn.*$//"
  "s/{usd_no_segmentado,convertidos}/{usd_no_segmentado,descartados}/g"
  "s/(rango.elemento#>>'{cohorte,convertidos}')::int/(fila.elemento#>>'{pen,cohorte,convertidos}')::int/"
  "PERL:s/v_payload:=private\.metricas_distribucion_leads_core\(p_desde,p_hasta,v_ahora\);/v_payload:=private.metricas_distribucion_leads_core(p_desde,p_hasta,v_ahora);\n    v_payload:=private.metricas_distribucion_leads_v2_core(p_desde,p_hasta,v_ahora);/"
  "s/v_factor := private.peso_referido_conversion(v_mes);/v_factor := 1;/"
  "s/ + nv.operaciones)/)/g"
)
for i in 0 1 2 3 4 5 6 7 8; do
  MUT="$TMPD/mut$i.sql"
  if [[ "${S[$i]}" == PERL:* ]]; then
    perl -0pe "${S[$i]#PERL:}" "$MIG" > "$MUT"
  else
    sed "${S[$i]}" "$MIG" > "$MUT"
  fi
  if cmp -s "$MIG" "$MUT"; then
    echo "❌ ${N[$i]}: el sed no toco nada"; exit 1; fi
  montar >/dev/null
  set +e
  aplicar "$MUT" 2>/dev/null
  RCM=$?
  if [ $RCM -ne 0 ]; then set -e; echo "✅ ${N[$i]}: cazado (el postflight aborto la migracion)"; continue; fi
  SAL=$(psql -h $H -p $PT -U $U -X -v ON_ERROR_STOP=1 -d $DB -f "$AQUI/test-f2-distribucion-v3.sql" 2>&1); RC=$?
  set -e
  if [ $RC -eq 0 ]; then echo "❌ ${N[$i]}: SOBREVIVIO"; exit 1; fi
  if echo "$SAL" | grep -q "ORACULO ROTO"; then echo "✅ ${N[$i]}: cazado (oraculo)"
  else echo "❌ ${N[$i]}: murio por OTRA cosa:"; echo "$SAL" | tail -4; exit 1; fi
done
rm -rf "$TMPD"
echo
echo "✅ BANCO F2.3b COMPLETO: paridad v2 + valores a mano + gate + rollback + 9/9 mutantes muertos"
