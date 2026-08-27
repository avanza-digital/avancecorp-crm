#!/bin/bash
# Banco local de F2.3a (Distribucion sin cierres anulados).
#
# La promesa de esta migracion es doble y el banco la comprueba en ese orden:
#   1. Se monta el mundo, se siembra el fixture y se corre la funcion VIEJA
#      para GUARDAR la huella de forma de su payload.
#   2. Se aplica F2.3a y se exige: misma huella de forma (el front la valida a
#      cierre hermetico) y `convertidos` sin el cierre anulado.
#
# Uso: run-test-f2-distribucion-local.sh <dir-f1-vivos> <dir-f2-vivos>
set -euo pipefail
VIVOS1="${1:?dir f1-vivos}"
VIVOS2="${2:?dir f2-vivos}"
MIGDIR="$(cd "$(dirname "$0")/../migrations" && pwd)"
AQUI="$(cd "$(dirname "$0")" && pwd)"
DB=crm_f23_banco
H=127.0.0.1; PT=5432; U=postgres
MD5_CORE_PROD="b7c4a63e509b58c39b6767d568332081"

montar() {
  psql -h $H -p $PT -U $U -X -q -c "drop database if exists $DB" -c "create database $DB"
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB <<'SQL' >/dev/null
create schema crm; create schema private; create schema banco;
create table banco.forma_vieja (forma text);
-- Huella de FORMA de un payload: todas las claves de todos sus objetos, a
-- cualquier profundidad, ordenadas. `$.**` en modo lax tambien devuelve
-- arrays y escalares, asi que se filtra a objetos antes de pedir sus claves.
create function banco.forma(p jsonb) returns text
language sql immutable as $ff$
  select string_agg(distinct k, ',' order by k)
  from jsonb_path_query(p, 'lax $.**') o,
       lateral jsonb_object_keys(o) k
  where jsonb_typeof(o) = 'object'
$ff$;
-- Stubs con la FORMA de las tablas reales que este motor lee. Las columnas
-- salieron de hacer compilar el texto VIVO: si falta una, no compila.
create table public.perfiles (id uuid primary key, nombre_completo text, activo boolean default true);
create table crm.equipo (perfil_id uuid primary key, rol_crm text, supervisor_id uuid,
  activo boolean default true, capacidad_leads_objetivo int);
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
-- Devuelve un rango REAL del payload: con un id inventado, la agrupacion por
-- rangos sale a 0 y su asercion pasaria en vacio.
create function private.rango_capital_pen(n numeric) returns text
  language sql immutable as 'select ''pen_0_1000''::text';
create function private.umbral_estancamiento(e text) returns interval
  language sql immutable as 'select interval ''7 days''';
create function private.cierre_anulado(l uuid) returns boolean
  language sql stable set search_path=''
  as 'select exists (select 1 from private.anulados_stub a where a.lead_id = l)';
SQL
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS1/private__cierre_externo_anulado.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS1/private__etiqueta_mes_es.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS1/private__conversion_mensual_por_vendedor.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS2/private__peso_referido_conversion.sql" >/dev/null
  # el motor VIVO de Distribucion, byte a byte
  psql -h $H -p $PT -U $U -X -q -d $DB -f "$VIVOS2/private__metricas_distribucion_leads_core.sql" >/dev/null
  local md5_local
  md5_local=$(psql -h $H -p $PT -U $U -X -t -A -d $DB -c "select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='metricas_distribucion_leads_core'")
  if [ "$md5_local" != "$MD5_CORE_PROD" ]; then
    echo "❌ ancla rota: motor local $md5_local ≠ prod $MD5_CORE_PROD"; exit 1
  fi
  # La CADENA REAL de privilegios de produccion, reproducida: el wrapper publico
  # (DEFINER, owner del rol puente) llama a `..._autorizada` (DEFINER, owner
  # postgres), y ESA es la identidad con la que corre el motor (que no es
  # DEFINER). Sin reproducirla, el candado del preflight no se prueba.
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB <<'SQL2' >/dev/null
do $r$ begin
  if not exists (select 1 from pg_roles where rolname='crm_metricas_bridge')
    then create role crm_metricas_bridge; end if;
end $r$;
create function private.metricas_distribucion_leads_autorizada(p_desde date, p_hasta date)
  returns jsonb language sql stable security definer set search_path=''
  as 'select private.metricas_distribucion_leads_core(p_desde, p_hasta, now())';
grant execute on function private.metricas_distribucion_leads_autorizada(date,date)
  to crm_metricas_bridge;
create function crm.metricas_distribucion_leads_v2_fn(p_desde date, p_hasta date)
  returns jsonb language sql stable security definer set search_path=''
  as 'select private.metricas_distribucion_leads_autorizada(p_desde, p_hasta)';
alter function crm.metricas_distribucion_leads_v2_fn(date,date) owner to crm_metricas_bridge;
SQL2
  # la tabla-base de F1
  sed "s/raise exception '[^']*re-capturar[^']*';/null;/" \
    "$MIGDIR/20260826233000_crm_f1_conversion_episodios.sql" \
    | psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 --single-transaction -d $DB -f - >/dev/null
}

sembrar_y_fotografiar_forma() {
  # Siembra el MISMO fixture del test y guarda la huella de forma que produce
  # la funcion VIEJA. Sin esto, la comparacion de forma seria vacua.
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB \
    -f "$AQUI/fixture-f2-distribucion.sql" >/dev/null
  psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 -d $DB -c "
    insert into banco.forma_vieja (forma)
    select banco.forma(private.metricas_distribucion_leads_core(
      '2026-07-01','2026-07-31', now()));" >/dev/null
  # y el numero VIEJO, para que el informe muestre el cambio
  echo -n "   convertidos con la funcion VIEJA (el anulado contaba): "
  psql -h $H -p $PT -U $U -X -t -A -d $DB -c "
    select x.value->'pen'->'cohorte'->>'convertidos'
      from jsonb_array_elements(
        private.metricas_distribucion_leads_core('2026-07-01','2026-07-31', now())->'analistas') x
     limit 1;"
}

aplicar() {  # $1 = migracion (original o mutante)
  sed -e "s/raise exception '[^']*re-capturar[^']*';/null;/" \
      -e "s/raise exception 'el owner del wrapper[^']*';/null;/" "$1" \
    | psql -h $H -p $PT -U $U -X -q -v ON_ERROR_STOP=1 --single-transaction -d $DB -f - >/dev/null
}

echo "════ F2.3a · CASO REAL ════"
montar
sembrar_y_fotografiar_forma
aplicar "$MIGDIR/20260827050000_crm_f2_3a_distribucion_sin_anulados.sql"
psql -h $H -p $PT -U $U -X -v ON_ERROR_STOP=1 -d $DB -f "$AQUI/test-f2-distribucion.sql"

echo
echo "════ F2.3a · MUTANTES ════"
TMPD=$(mktemp -d)
declare -a N=(
  "D1 vuelve a contar los cierres anulados"
  "D2 solo UNA de las tres agrupaciones filtra anulados"
  "D3 la pierna de cierres se corta en el rango (pierde los que cierran despues)"
)
declare -a S=(
  "s/where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null/where e.tipo = 'cierre' and e.lead_id is not null/"
  "s/and (c.analista_id, c.lead_id) in/and true or (c.analista_id, c.lead_id) in/"
  "s/p.inicio, greatest(p.fin, p.ahora), null::date/p.inicio, p.fin, null::date/"
)
for i in 0 1 2; do
  MUT="$TMPD/mut$i.sql"
  sed "${S[$i]}" "$MIGDIR/20260827050000_crm_f2_3a_distribucion_sin_anulados.sql" > "$MUT"
  if cmp -s "$MIGDIR/20260827050000_crm_f2_3a_distribucion_sin_anulados.sql" "$MUT"; then
    echo "❌ ${N[$i]}: el sed no toco nada"; exit 1; fi
  montar; sembrar_y_fotografiar_forma >/dev/null
  set +e
  aplicar "$MUT" 2>/dev/null
  RCM=$?
  if [ $RCM -ne 0 ]; then set -e; echo "✅ ${N[$i]}: cazado (postflight aborto la migracion)"; continue; fi
  SAL=$(psql -h $H -p $PT -U $U -X -v ON_ERROR_STOP=1 -d $DB -f "$AQUI/test-f2-distribucion.sql" 2>&1); RC=$?
  set -e
  if [ $RC -eq 0 ]; then echo "❌ ${N[$i]}: SOBREVIVIO"; exit 1; fi
  if echo "$SAL" | grep -q "ORACULO ROTO"; then echo "✅ ${N[$i]}: cazado"
  else echo "❌ ${N[$i]}: murio por OTRA cosa:"; echo "$SAL" | tail -4; exit 1; fi
done
rm -rf "$TMPD"
echo
echo "✅ BANCO F2.3a COMPLETO: forma idéntica + anulados fuera + 3/3 mutantes muertos"
