#!/bin/bash
# Aplica F2.2 (Ranking del equipo sobre la tabla-base) a PRODUCCIÓN.
#
# A DIFERENCIA DE F0/F1, AQUÍ LOS NÚMEROS CAMBIAN A PROPÓSITO (decisión D4 de
# Miguel): la pantalla dejaba de contar por una columna muerta y pasa al ledger.
# Por eso este guion NO aborta si la foto cambia — la IMPRIME antes y después
# para que el cambio quede registrado y se pueda comunicar al equipo.
#
# QUÉ SÍ ABORTA: preflight de md5 (que lo vivo sea lo anclado en F0 y la
# tabla-base la de F1) y postflight estructural, ambos DENTRO de la migración:
# si fallan, la transacción entera se revierte y no queda nada aplicado.
#
# VERIFICACIÓN: la función tiene puerta de rol interna (gerencia), así que la
# foto se toma suplantando —solo lectura, dentro de la transacción— a una
# gerencia activa cualquiera vía `request.jwt.claims`. No escribe nada.
#
# VUELTA ATRÁS: scripts/rollback-f2-2-ranking.sql (texto vivo verbatim).
set -euo pipefail
REF="dctqcbznekcyxhjujuci"
DIR="/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase"
MIG="$DIR/migrations/20260827033000_crm_f2_2_ranking_nucleo.sql"
VERSION="20260827033000"
NOMBRE="crm_f2_2_ranking_nucleo"
TOKEN=$(security find-generic-password -s 'Supabase CLI' -w)

echo "— huella del fichero que se va a aplicar —"
shasum -a 256 "$MIG"

api() {
  python3 - "$1" <<'PY'
import json, sys, urllib.request, os
sql = open(sys.argv[1]).read() if os.path.isfile(sys.argv[1]) else sys.argv[1]
req = urllib.request.Request(
    'https://api.supabase.com/v1/projects/' + os.environ['REF'] + '/database/query',
    data=json.dumps({'query': sql}).encode(),
    headers={'Authorization': 'Bearer ' + os.environ['TOKEN'], 'Content-Type': 'application/json',
             'User-Agent': 'avancecorp-deploy/1.0'})
try:
    print(urllib.request.urlopen(req, timeout=300).read().decode()[:4000])
except urllib.error.HTTPError as e:
    print('HTTP', e.code, e.read().decode()[:2000]); sys.exit(1)
PY
}
export TOKEN REF

FOTO="
with cfg as (
  select set_config('request.jwt.claims',
    (select json_build_object('sub', e.perfil_id)::text
       from crm.equipo e join public.perfiles p on p.id = e.perfil_id
      where e.activo and p.activo and e.rol_crm = 'gerencia'
      order by e.perfil_id limit 1), true) as v
), m as (
  select crm.metricas_conversiones_equipo_fn(
    date_trunc('month', now() at time zone 'America/Lima')::date,
    (now() at time zone 'America/Lima')::date) as p
  from cfg
)
select jsonb_pretty(jsonb_build_object(
  'alcance', p->'alcance',
  'nucleo', p->'nucleo',
  'sondas', p->'sondas',
  'responsables_con_clientes', (
    select count(*) from jsonb_array_elements(p->'responsables') x
     where (x.value->>'clientes')::int > 0),
  'total_clientes', (
    select coalesce(sum((x.value->>'clientes')::int), 0)
    from jsonb_array_elements(p->'responsables') x),
  'primeros_tres', (
    select jsonb_agg(x.value order by x.ord)
    from (select value, ord from jsonb_array_elements(p->'responsables')
            with ordinality e(value, ord) order by ord limit 3) x(value, ord)),
  'claves_raiz', (select jsonb_agg(k order by k) from jsonb_object_keys(p) k)
)) as foto from m;"

echo "— 0/4 · FOTO ANTES (mes en curso, como la ve gerencia) —"
api "$FOTO"

echo "— 1/4 · aplicando F2.1 (una transacción; si el preflight falla, no queda nada) —"
api "$MIG"

echo "— 2/4 · FOTO DESPUÉS · aquí se ve exactamente qué números cambiaron —"
api "$FOTO"

echo "— 3/4 · registrándola en schema_migrations —"
python3 - "$MIG" "$VERSION" "$NOMBRE" <<'PY' > /tmp/registro-f22.sql
import sys
sql = open(sys.argv[1]).read().replace("'", "''")
print("insert into supabase_migrations.schema_migrations (version, name, statements) "
      "values ('" + sys.argv[2] + "', '" + sys.argv[3] + "', array['" + sql + "']) "
      "on conflict (version) do nothing;")
PY
api /tmp/registro-f22.sql
rm -f /tmp/registro-f22.sql

echo "— 4/4 · verificación en vivo + vigía —"
api "select
  (select case when strpos(p.prosrc,'conversion_episodios')>0 then 1 else 0 end
     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='crm' and p.proname='metricas_conversiones_equipo_fn') as consume_base_debe_ser_1,
  (select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='crm' and p.proname='metricas_conversiones_equipo_fn') as definer_debe_ser_t,
  (select count(*) from supabase_migrations.schema_migrations where version='$VERSION') as registrada_debe_ser_1;"

echo "✅ F2.2 LISTA. Motores paralelos restantes: 2.3a distribución · 2.4 vendedores/cartera/series · 2.5 reuniones."
echo "⚠️  COMUNICAR AL EQUIPO: el ranking ya no da 0 clientes a todos; se ordena por resultados reales."
