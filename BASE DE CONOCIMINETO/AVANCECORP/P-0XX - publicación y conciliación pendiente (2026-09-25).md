# P-0XX — cuentas compartidas publicadas; conciliación pendiente

El 25/09/2026 Miguel autorizó excepcionalmente publicar P-0XX sin usar el
Merge Request del dashboard, que omitía datos y borraba objetos ajenos. Se
aplicaron a producción las cuatro migraciones canónicas S1, S3, S4 y S2; luego
las tres Edge Functions y el ZIP del portal por Hostinger. La persona usuaria
confirmó visualmente que las cuentas creadas en CRM aparecen en el portal.

S1 insertó 241 cuentas y vinculó 257 contratos. Permanecen 23 contratos
activos sin vínculo (16 sin cuenta, 7 con candidatas ambiguas), con reporte
nominal privado en `_DEV_NO_SUBIR/releases/p0xx-conciliacion-actual-20260925.csv`.
Hay además tres perfiles válidos con el mismo CCI que una cuenta CRM y otros
datos; no se sobreescribió ningún dato. Operaciones debe resolverlos con
evidencia. Pagos bloquea contratos sin vínculo.

El despliegue portal se hizo desde el commit local `717e4c1`; GitHub del portal
no fue accesible y el CRM local no se sincronizó con `avancecorp/main`. Los
advisors reportan dos WARN de seguridad nuevos para RPC autorizadas. El acta
técnica está en `CRM-Avance-Corp/supabase/scripts/p0xx/ACTA-PUBLICACION.md`.

Relacionado: [[P-0XX - merge de esquema inseguro y salida pendiente (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S1 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S2 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S3 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S4 en rama (2026-09-25)]].
