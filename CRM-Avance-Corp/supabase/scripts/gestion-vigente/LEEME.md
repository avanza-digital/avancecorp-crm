# Gestionado en ficha y listados

`crm.gestion_vigente_fn(uuid[])` delega a `private.gestion_vigente_lectura`.
Ambas son INVOKER/estables y usan la RLS del actor. Devuelve versión 1 e items
con lead_id, vendedor_id, tenencia_desde y gestion_vigente. Máximo 100 IDs;
acepta lote vacío y repetidos, rechaza null/matrices/lotes mayores.

Gestionado significa etapa Nuevo activa, titular y tenencia actual, con alguno
de los cinco tipos de contacto desde esa tenencia. Cualquier clave deshecho_en,
incluido JSON null, excluye la actividad. Una nota no cuenta. La comparación por
rol con cartera_filtrada_fn protege la coherencia con el filtro del Pipeline.

El adaptador compara titular y sello con microsegundos. Un cambio de tenencia,
una fila ausente o un fallo de lectura deja «Gestión sin verificar». Conservar un
true anterior sería incorrecto si se deshizo el contacto en esa misma tenencia.
Gestionado se muestra automáticamente; no es una nueva etapa persistida ni un
botón para cambiar la etapa. Los contadores históricos y SLA conservan su regla.

## Pruebas

Solo en banco con seed-demo (nunca producción):

- `psql -X -v ON_ERROR_STOP=1 -f supabase/scripts/gestion-vigente/test.sql`:
  100 leads transaccionales; seis actores, cinco tipos, contacto de otro autor,
  precisión de un microsegundo, deshechos (fecha y JSON null), nota, sin contacto,
  sin titular/tenencia, inactivo/avanzado, límites, ACL y comparación con filtro.
  Termina con ROLLBACK y EXPLAIN de la lectura por lote.
- `node supabase/scripts/gestion-vigente/test-http.mjs`: variables del mismo
  seed; sesiones reales y RPC HTTP, anon/service denegados y esquema private
  no expuesto. Solo lecturas.
- Gate general: `node supabase/scripts/test-rls.mjs` con entorno del banco.
- Front: `npm run check`; Docker `gestionado-ficha.spec.ts`,
  `pipeline-gestionado.spec.ts`, `cartera-keyset.spec.ts`.

Review independiente final: PASS, sin cambios obligatorios. Se añadieron los
casos de matriz pequeña SQL/HTTP y ACL del núcleo; las fechas ISO se normalizan
a milisegundos antes de Date.parse y se conserva por separado la fracción micro.
