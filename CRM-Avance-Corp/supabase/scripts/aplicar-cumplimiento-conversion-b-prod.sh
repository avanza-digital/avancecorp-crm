#!/bin/bash
# Aplica la MIGRACIÓN B (unificar la conversión de las metas) a PRODUCCIÓN.
#
# POR QUÉ EXISTE ESTE GUION: el merge de branches sigue roto del lado de Supabase
# (sus proyectos de branch no quedan registrados en la Management API → el
# workflow muere con 404 antes de aplicar nada). Miguel autorizó la aplicación
# directa para cooperativas el 2026-08-12 y para esta el 2026-08-13. Va por el
# MISMO canal que usaría el merge (Management API).
#
# QUÉ HACE, en orden:
#   1. Muestra la huella SHA-256 del fichero que se va a aplicar.
#   2. Lo manda a producción. El fichero es UNA transacción: preflight con DOS
#      anclas md5 (la propia función y `private.conversion_mensual_por_vendedor`,
#      de la que ahora depende la forma de la CTE) y postflight estructural. Si
#      algo no cuadra, NO queda nada aplicado — verificado en local que un
#      preflight fallido deja intacto el cuerpo anterior.
#   3. La registra en supabase_migrations.schema_migrations con su contenido
#      íntegro (lo que haría el CLI).
#   4. Verifica en vivo: fuente nueva declarada, la llamada presente, la fórmula
#      vieja ausente, DEFINER sigue en 167 (esta migración no crea funciones) y
#      la migración registrada.
#
# VUELTA ATRÁS, si las metas se caen: ejecutar
#   supabase/scripts/rollback-cumplimiento-conversion-B.sql
# (cuerpo verbatim anterior). El front acepta los dos literales de
# `fuentes_reales.conversion`, así que NO hace falta redesplegar el front.
set -euo pipefail
REF="dctqcbznekcyxhjujuci"
MIG="/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase/migrations/20260813212332_crm_cumplimiento_conversion_ponderada.sql"
VERSION="20260813212332"
NOMBRE="crm_cumplimiento_conversion_ponderada"
TOKEN=$(security find-generic-password -s 'Supabase CLI' -w)

echo "— huella del fichero que se va a aplicar —"
shasum -a 256 "$MIG"

api() {
  python3 - "$1" <<'PY'
import json, sys, urllib.request, os
sql = open(sys.argv[1]).read() if os.path.isfile(sys.argv[1]) else sys.argv[1]
tok = os.environ['TOKEN']
req = urllib.request.Request(
    'https://api.supabase.com/v1/projects/' + os.environ['REF'] + '/database/query',
    data=json.dumps({'query': sql}).encode(),
    headers={'Authorization': 'Bearer ' + tok, 'Content-Type': 'application/json',
             # Cloudflare rechaza el UA por defecto de urllib (error 1010)
             'User-Agent': 'avancecorp-deploy/1.0'})
try:
    print(urllib.request.urlopen(req, timeout=300).read().decode()[:1500])
except urllib.error.HTTPError as e:
    print('HTTP', e.code, e.read().decode()[:1500]); sys.exit(1)
PY
}
export TOKEN REF

echo "— 1/3 · aplicando la migración (una transacción; si falla, no queda nada) —"
api "$MIG"

echo "— 2/3 · registrándola en schema_migrations —"
python3 - "$MIG" "$VERSION" "$NOMBRE" <<'PY' > /tmp/registro-b.sql
import sys
sql = open(sys.argv[1]).read().replace("'", "''")
print("insert into supabase_migrations.schema_migrations (version, name, statements) "
      "values ('" + sys.argv[2] + "', '" + sys.argv[3] + "', array['" + sql + "']) "
      "on conflict (version) do nothing;")
PY
api /tmp/registro-b.sql
rm -f /tmp/registro-b.sql

echo "— 3/3 · verificación en vivo —"
api "select
  (select case when position('leads_recibidos_ponderado' in pg_get_functiondef('crm.cumplimiento_metas_fn(date)'::regprocedure))>0 then 1 else 0 end) as fuente_nueva_debe_ser_1,
  (select case when position('from private.conversion_mensual_por_vendedor(' in pg_get_functiondef('crm.cumplimiento_metas_fn(date)'::regprocedure))>0 then 1 else 0 end) as consume_definicion_unica_debe_ser_1,
  (select case when position('l.etapa=''descartado''' in pg_get_functiondef('crm.cumplimiento_metas_fn(date)'::regprocedure))>0 then 1 else 0 end) as formula_vieja_debe_ser_0,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private') and p.prosecdef) as definer_debe_seguir_en_167,
  (select count(*) from supabase_migrations.schema_migrations where version='$VERSION') as registrada_debe_ser_1;"

echo "✅ LISTO. Sigue: /release-crm para publicar el front con los cortes de alertas."
