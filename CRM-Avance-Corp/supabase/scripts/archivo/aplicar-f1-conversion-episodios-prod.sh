#!/bin/bash
# Aplica F1 (conversion_episodios) a PRODUCCIÓN con PARIDAD sobre datos reales.
#
# QUÉ ES F1: nace private.conversion_episodios (tabla-base de la conversión) y
# private.conversion_mensual_por_vendedor pasa a ser una agrupación encima.
# CERO cambio de números: paridad byte a byte probada en banco local
# (run-test-conversion-episodios-local.sh: 6 llamadas + oráculo + 4 mutantes)
# y verificada aquí sobre los datos REALES: foto del núcleo (mes actual y mes
# anterior, factor 0.15 y 1.0) ANTES y DESPUÉS — deben ser byte-idénticas.
#
# CANAL directo (Management API): el merge de branches de Supabase sigue roto.
# Miguel ordenó F1 el 2026-08-26 («desarrolla la fase 1»; D1-D7 resueltas).
#
# VUELTA ATRÁS: rollback-f1-conversion-episodios.sql (núcleo vivo verbatim
# pre-F1 + drop de conversion_episodios). Si preflight/postflight fallan, la
# transacción entera se revierte sola.
set -euo pipefail
REF="dctqcbznekcyxhjujuci"
DIR="/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase"
MIG="$DIR/migrations/20260826233000_crm_f1_conversion_episodios.sql"
VERSION="20260826233000"
NOMBRE="crm_f1_conversion_episodios"
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
    print(urllib.request.urlopen(req, timeout=300).read().decode()[:3000])
except urllib.error.HTTPError as e:
    print('HTTP', e.code, e.read().decode()[:2000]); sys.exit(1)
PY
}
export TOKEN REF

FOTO_SQL="
with lima as (
  select date_trunc('month', now() at time zone 'America/Lima')::date as m0
), args as (
  select (m0::timestamp) at time zone 'America/Lima' as ini0,
         ((m0 + interval '1 month')::timestamp) at time zone 'America/Lima' as fin0,
         (((m0 - interval '1 month')::date)::timestamp) at time zone 'America/Lima' as ini1,
         (m0::timestamp) at time zone 'America/Lima' as fin1
  from lima
)
select
  (select md5(coalesce(string_agg(t::text, E'\n' order by t::text), '<vacio>'))
     from args a, private.conversion_mensual_por_vendedor(a.ini0, a.fin0, true, null, 0.15) t) as mes_actual_f015,
  (select md5(coalesce(string_agg(t::text, E'\n' order by t::text), '<vacio>'))
     from args a, private.conversion_mensual_por_vendedor(a.ini0, a.fin0, true, null, 1.0) t)  as mes_actual_f1,
  (select md5(coalesce(string_agg(t::text, E'\n' order by t::text), '<vacio>'))
     from args a, private.conversion_mensual_por_vendedor(a.ini1, a.fin1, true, null, 0.15) t) as mes_anterior_f015;
"

echo "— 0/4 · candados de datos (Codex P1/P3): empates y orden total —"
CANDADOS=$(api "select
  (select count(*) from (
     select 1 from crm.lead_asignaciones
     group by analista_id, lead_id, asignado_en having count(*) > 1) x
  ) as empates_asignado_en_debe_ser_0,
  (select count(*) from pg_index i
     join pg_class c on c.oid = i.indrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname='crm' and c.relname='operaciones_cartera'
      and i.indisprimary) as ops_pk_debe_ser_1,
  (select count(*) from information_schema.columns
    where table_schema='crm' and table_name='operaciones_cartera'
      and column_name='creado_en' and is_nullable='NO') as ops_creado_en_notnull_debe_ser_1;")
echo "$CANDADOS"
if ! echo "$CANDADOS" | grep -q '"empates_asignado_en_debe_ser_0":0'; then
  echo "❌ HAY EMPATES EXACTOS de asignado_en en el ledger: el orden del primer"
  echo "   episodio es indeterminado (tambien en el nucleo VIVO). Resolver antes de F1."
  exit 1
fi
if ! echo "$CANDADOS" | grep -q '"ops_pk_debe_ser_1":1'; then
  echo "❌ operaciones_cartera sin PK: el desempate de cartera no tiene orden total."
  exit 1
fi

echo "— 0b/4 · FOTO ANTES (núcleo sobre datos reales) —"
ANTES=$(api "$FOTO_SQL")
echo "$ANTES"

echo "— 1/4 · aplicando F1 (una transacción; si falla, no queda nada) —"
api "$MIG"

echo "— 2/4 · FOTO DESPUÉS y comparación —"
DESPUES=$(api "$FOTO_SQL")
echo "$DESPUES"
if [ "$ANTES" != "$DESPUES" ]; then
  echo "❌ PARIDAD ROTA EN PRODUCCIÓN: ejecutar el rollback YA:"
  echo "   scripts/rollback-f1-conversion-episodios.sql"
  exit 1
fi
echo "✅ paridad byte a byte sobre datos reales"

echo "— 3/4 · registrándola en schema_migrations —"
python3 - "$MIG" "$VERSION" "$NOMBRE" <<'PY' > /tmp/registro-f1.sql
import sys
sql = open(sys.argv[1]).read().replace("'", "''")
print("insert into supabase_migrations.schema_migrations (version, name, statements) "
      "values ('" + sys.argv[2] + "', '" + sys.argv[3] + "', array['" + sql + "']) "
      "on conflict (version) do nothing;")
PY
api /tmp/registro-f1.sql
rm -f /tmp/registro-f1.sql

echo "— 4/4 · verificación en vivo + VIGÍA —"
api "select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='conversion_episodios') as episodios_existe_debe_ser_1,
  (select case when strpos(p.prosrc,'conversion_episodios')>0
               and strpos(p.prosrc,'crm.lead_asignaciones')=0 then 1 else 0 end
     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='conversion_mensual_por_vendedor') as nucleo_consume_base_debe_ser_1,
  (select count(*) from supabase_migrations.schema_migrations where version='$VERSION') as registrada_debe_ser_1;"

# VIGÍA (a) del plan: toda función de crm.* cuyo payload nombra 'conversion'
# debe consumir el núcleo o la tabla-base — strpos, jamás LIKE (el _ es comodín).
# Las 5 excepciones listadas son los MOTORES PARALELOS CONOCIDOS que F2 va a
# migrar uno a uno: la lista debe ENCOGER en cada fase, nunca crecer.
api "with sospechosas as (
  select n.nspname||'.'||p.proname as fn, p.prosrc
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname in ('crm','private')
     and strpos(p.prosrc, 'conversion') > 0
     and p.proname not in ('conversion_episodios','conversion_mensual_por_vendedor')
)
select fn,
  case when strpos(prosrc,'conversion_mensual_por_vendedor')>0
         or strpos(prosrc,'conversion_episodios')>0 then 'consume_nucleo'
       when fn in ('private.metricas_conversiones_implementacion',
                   'private.metricas_distribucion_leads_core',
                   'crm.metricas_vendedores_fn',
                   'private.metricas_reuniones_implementacion',
                   'crm.resumen_cartera_fn')
         then 'MOTOR PARALELO CONOCIDO (lo migra F2)'
       else 'REVISAR: motor desconocido' end as veredicto
from sospechosas
order by 2 desc, 1;"

echo "✅ F1 LISTA. El núcleo agrupa la tabla-base; ni un número cambió."
