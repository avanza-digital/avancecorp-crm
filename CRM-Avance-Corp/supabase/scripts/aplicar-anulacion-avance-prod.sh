#!/bin/bash
# Aplica la ANULACIÓN DE CIERRES DE AVANCE a PRODUCCIÓN y la registra.
#
# POR QUÉ EXISTE: el merge de branches de Supabase sigue roto (sus proyectos de
# branch no quedan registrados en la Management API → el workflow muere con 404).
# Miguel autorizó la aplicación directa para cooperativas (2026-08-12) y para la
# migración B (2026-08-13). ESTA necesita su OK propio: una autorización no se
# hereda de la anterior.
#
# QUÉ HACE, en orden:
#   1. Muestra la huella SHA-256 del fichero.
#   2. Lo aplica. Es UNA transacción con preflight de TRES anclas md5 + un
#      conteo que exige que el delegado tenga exactamente UN consumidor. Si algo
#      no cuadra, ABORTA y no queda nada aplicado.
#   3. Lo registra en supabase_migrations.schema_migrations.
#   4. Verifica en vivo: tabla nueva, las tres funciones nuevas, la cadena de
#      neutralización dentro de la cuota, DEFINER 169 y la migración registrada.
#
# ⚠️ ANTES DE LANZARLO conviene tener presente que esto NO sirve solo: sin la
# Fase 2 (el botón de gerencia) la capacidad queda en la base sin forma de
# usarla desde la aplicación.
#
# VUELTA ATRÁS si algo se rompe:
#   psql ... -f supabase/scripts/rollback-anulacion-avance.sql
# Devuelve la cuota al cuerpo post-B y el delegado a mirar solo cooperativas.
# NO borra la tabla ni la RPC a propósito: si gerencia ya anuló algo, esa fila
# es la razón escrita que se le dio a una persona.
set -euo pipefail
REF="dctqcbznekcyxhjujuci"
MIG="/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase/migrations/20260813235119_crm_anulacion_cierre_avance.sql"
VERSION="20260813235119"
NOMBRE="crm_anulacion_cierre_avance"
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

echo "— 1/3 · aplicando (una transacción; si el preflight falla, no queda nada) —"
api "$MIG"

echo "— 2/3 · registrándola en schema_migrations —"
python3 - "$MIG" "$VERSION" "$NOMBRE" <<'PY' > /tmp/registro-anul-avance.sql
import sys
sql = open(sys.argv[1]).read().replace("'", "''")
print("insert into supabase_migrations.schema_migrations (version, name, statements) "
      "values ('" + sys.argv[2] + "', '" + sys.argv[3] + "', array['" + sql + "']) "
      "on conflict (version) do nothing;")
PY
api /tmp/registro-anul-avance.sql
rm -f /tmp/registro-anul-avance.sql

echo "— 3/3 · verificación en vivo —"
api "select
  (select count(*) from information_schema.tables where table_schema='crm' and table_name='cierres_avance_anulados') as tabla_debe_ser_1,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where (n.nspname='crm' and p.proname='anular_cierre_avance')
        or (n.nspname='private' and p.proname in ('cierre_anulado','contratos_afectados_por_anulacion','vendedor_acreditado_del_cierre'))) as funciones_deben_ser_4,
  (select case when position('cross join lateral private.contratos_afectados_por_anulacion' in pg_get_functiondef('crm.cumplimiento_metas_fn(date)'::regprocedure))>0 then 1 else 0 end) as cuota_consulta_la_regla_debe_ser_1,
  (select case when position('from neutralizados n' in pg_get_functiondef('crm.cumplimiento_metas_fn(date)'::regprocedure))>0 then 1 else 0 end) as neutralizacion_viva_debe_ser_1,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname in ('crm','private') and p.prosecdef) as definer_debe_ser_169,
  (select count(*) from supabase_migrations.schema_migrations where version='$VERSION') as registrada_debe_ser_1;"

echo "✅ LISTO. Sigue: la Fase 2 (el botón de gerencia) para que esto se pueda usar."
