# P-0XX — publicación detenida por el merge de esquema

Estado al 25/09/2026: los cambios P-0XX están commiteados localmente y
probados en la rama `p0xx-cuentas-unificadas-20260925`; **producción y
miavance.com siguen con la versión anterior**. El Merge Request que abrí se
cerró sin fusionar porque su vista previa descargada no incluía el backfill
`DO $backfill$` de S1 y sí eliminaba una columna, una tabla y funciones ajenas
al trabajo, además de recrear `pg_net`. Rebase no corrigió esa diferencia.

La rama tiene las cuatro migraciones y las tres Edge Functions nuevas. El
portal quedó en el commit local `717e4c199f2991e73b4dc00b9e08f0c1acdb040e`
y el CRM en `f1a947b2` + `a06321ec`. Hay un ZIP del portal y uno de
reversión en `_DEV_NO_SUBIR/releases/`, sin subir. El script de datos separado
`CRM-Avance-Corp/supabase/scripts/p0xx/backfill-data-only-after-schema.sql`
se probó de forma idempotente en la rama; por sí solo no vuelve seguro el MR.

Para terminar hace falta acordar explícitamente otra vía productiva que ejecute
las migraciones completas S1, S3, S4 y S2, incluyendo los datos, sin usar el
diff destructivo. Luego se despliegan las tres Edge y el ZIP de Hostinger.
Ningún DDL/DML se ejecutó en producción por este trabajo. La guía técnica y
los gates están en `CRM-Avance-Corp/supabase/scripts/p0xx/RELEASE.md`.

Se conserva la conciliación manual de los ~23 contratos activos proyectados
sin vínculo y los tres conflictos del mismo CCI. Esos contratos no se podrán
pagar hasta registrar y vincular una cuenta inequívoca. No atribuirles una
cuenta por aproximación.

Relacionado: [[P-0XX - cuentas compartidas CRM portal - S1 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S2 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S3 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S4 en rama (2026-09-25)]].
