# P-0XX — CRM y portal publicados; conciliación pendiente

Actualización: [[P-0XX - cierre de excepciones ensayado (2026-09-26)]].

El 25/09/2026 Miguel autorizó excepcionalmente publicar P-0XX sin usar el
Merge Request del dashboard, que omitía datos y borraba objetos ajenos. Se
aplicaron las cuatro migraciones S1, S3, S4 y S2; las tres Edge Functions y el
portal por Hostinger. Miguel confirmó visualmente que las cuentas creadas en
CRM aparecen en el portal.

Después invocó **`$release-crm`**. El [PR #106](https://github.com/avanza-digital/avancecorp-crm/pull/106)
quedó integrado; se publicó `crm.miavance.com` desde Main **`caf999794655`**,
build **`build-20260925T220850705Z`**. La ficha compatible guarda por
`registrar_cuenta_cliente` y acepta el origen `portal`. Fuente limpia, Main
local/remoto idéntico, ZIP/manifiesto verificados. Se preservó el trabajo ajeno
del árbol original mediante una copia Git independiente para publicar.

Verificación final: `npm run check` **4440 tests PASS**, lint, typecheck/build,
bundle y duplicación; E2E local Docker **274 PASS / 26 SKIP / 0 FAIL**; HTTP/RLS
contratos y cuentas **287/287 PASS**; portal **112/112 PASS**. En producción,
portada y **78/78 JS/CSS** coinciden con el ZIP. Acceso autenticado en Chrome
**PASS**. Doce PNG ya diferían del paquete previo y conservaron sus bytes;
se guardaron como respaldo aparte y no se declararon idénticos al manifiesto.

S1 insertó **241 cuentas** y vinculó **257 contratos**. Permanecen **23 contratos
activos sin vínculo**: 16 sin cuenta y 7 con candidatas ambiguas. Reporte nominal
privado: `_DEV_NO_SUBIR/releases/p0xx-conciliacion-actual-20260925.csv`.
Existen **3 perfiles válidos** con igual CCI y otros datos frente a CRM, y **17**
grupos cliente/moneda con varias cuentas activas; reporte en
`_DEV_NO_SUBIR/releases/p0xx-conciliacion-perfiles-20260925.md`, enmascarado.
Las listas pueden solaparse. Operaciones debe resolver con evidencia; los
contratos sin cuenta vinculada siguen bloqueados para pagos.

El portal se publicó desde el commit local `717e4c1`; su remoto original
respondió 404 y no se sustituyó por otro repositorio con historia diferente.
El código CRM sí quedó en Main remoto. Dos WARN nuevos de seguridad corresponden
a RPC SECURITY DEFINER con autorización, documentados como excepciones abiertas.
No se declara el objetivo íntegramente cerrado: quedan esas excepciones y las
discrepancias de datos. Las columnas legado, su trigger y el modo `perfil`
permanecen como deuda acordada.

Acta técnica: `CRM-Avance-Corp/supabase/scripts/p0xx/ACTA-PUBLICACION.md`.
Artefactos: `_DEV_NO_SUBIR/releases/p0xx-crm-publicado/`; recuperación exacta de
código y copias de imágenes en `p0xx-crm-recuperacion/`. La rama temporal de
Supabase sigue disponible y genera costo por hora. Un commit posterior de esta
nota no cambia la fuente efectivamente desplegada.

Relacionado: [[P-0XX - merge de esquema inseguro y salida pendiente (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S1 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S2 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S3 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S4 en rama (2026-09-25)]].
