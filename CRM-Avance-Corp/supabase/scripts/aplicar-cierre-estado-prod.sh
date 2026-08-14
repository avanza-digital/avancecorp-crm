#!/bin/bash
# Aplica la LECTURA DEL ESTADO DEL CIERRE a PRODUCCIÓN y la registra.
#
# QUÉ ES: `crm.cierres_estado_fn(uuid[])` — la ventana que le faltaba a la
# anulación. Desde el 2026-08-14 gerencia puede anular un cierre de Avance, pero
# `crm.cierres_avance_anulados` es deny-by-default con cero policies y cero
# grants, así que la aplicación NO PUEDE VER esa anulación: se anularía, la
# pantalla se recargaría igual que antes y el segundo intento moriría con «ese
# cierre ya estaba anulado». Esto lo cierra sin abrir la tabla.
#
# POR QUÉ DIRECTO: el merge de branches de Supabase sigue roto (sus proyectos de
# branch no quedan registrados en la Management API → el workflow muere con 404).
# ⚠️ ESTA MIGRACIÓN NECESITA SU OK PROPIO: una autorización no se hereda.
#
# QUÉ HACE, en orden:
#   1. Muestra la huella SHA-256 del fichero.
#   2. Lo aplica. Es UNA transacción con preflight (el md5 del `using` de la
#      policy `leads_select`, que esta función ESPEJA por ser DEFINER, y la
#      existencia de private.cierre_anulado) + postflight estructural. Si algo no
#      cuadra, ABORTA y no queda nada aplicado.
#   3. Lo registra en supabase_migrations.schema_migrations.
#   4. Verifica en vivo: la función existe y es DEFINER, DEFINER total 170, la
#      migración registrada, y —lo que más importa— que las tablas de anulación
#      SIGUEN cerradas: cero policies y no legibles por `authenticated`.
#
# ⚠️ ORDEN DE DESPLIEGUE: SERVIDOR PRIMERO. El front nuevo llama a esta función;
# si sale antes que ella, pide una RPC que no existe.
#
# VUELTA ATRÁS: `drop function crm.cierres_estado_fn(uuid[]);`
# No hay estado que perder — es solo lectura. Con la función caída, la ficha deja
# de marcar los cierres anulados (vuelve al comportamiento de hoy), así que el
# front viejo sigue funcionando igual.
set -euo pipefail
REF="dctqcbznekcyxhjujuci"
MIG="/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase/migrations/20260814100746_crm_cierre_estado_lectura.sql"
VERSION="20260814100746"
NOMBRE="crm_cierre_estado_lectura"
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
python3 - "$MIG" "$VERSION" "$NOMBRE" <<'PY' > /tmp/registro-cierre-estado.sql
import sys
sql = open(sys.argv[1]).read().replace("'", "''")
print("insert into supabase_migrations.schema_migrations (version, name, statements) "
      "values ('" + sys.argv[2] + "', '" + sys.argv[3] + "', array['" + sql + "']) "
      "on conflict (version) do nothing;")
PY
api /tmp/registro-cierre-estado.sql
rm -f /tmp/registro-cierre-estado.sql

echo "— 3/3 · verificación en vivo —"
api "select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='crm' and p.proname='cierres_estado_fn' and p.prosecdef) as funcion_definer_debe_ser_1,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname in ('crm','private') and p.prosecdef) as definer_debe_ser_170,
  (select count(*) from supabase_migrations.schema_migrations where version='$VERSION') as registrada_debe_ser_1,
  -- La ventana no puede convertirse en puerta: las tablas siguen cerradas.
  (select count(*) from pg_policy where polrelid='crm.cierres_avance_anulados'::regclass) as policies_debe_ser_0,
  has_table_privilege('authenticated','crm.cierres_avance_anulados','select') as legible_debe_ser_false,
  has_function_privilege('authenticated','crm.cierres_estado_fn(uuid[])','execute') as ejecutable_debe_ser_true;"

echo "✅ LISTO. Sigue: correr el gate de RLS contra una base con esto aplicado, y el release del front."
