# Primer acceso Avance: continuidad y revisión UX

## Objetivo

El analista debe poder completar el primer acceso Avance sin confundir apellidos con nombres, registrar el domicilio legal, confirmar el correo antes de crear la cuenta y retomar la inversión sin volver a escribir los datos ya revisados.

## Decisiones de producto

- El flujo muestra tres pasos: **Acceso → Condiciones → Revisión**. La creación del perfil forma parte de Acceso.
- El formulario de acceso pide **Apellidos** y **Nombres** por separado, luego contacto y domicilio legal. El correo y el domicilio aparecen en una revisión explícita antes de crear el acceso.
- Los campos sin enviar se guardan solo en `sessionStorage` de la pestaña, aislados por actor, persona, lead y solicitud. Las condiciones también se atan a la revisión vigente de la solicitud. Al cerrar sesión se limpian estos borradores.
- Se recuperan importes, fechas, número de contrato y selección de una cuenta **existente**. Una cuenta bancaria nueva y los documentos/nombres de co-titulares no se guardan localmente antes de enviarlos. Si el analista había añadido esos datos, al retomar se le avisa que debe ingresarlos de nuevo.
- Si el navegador impide guardar un cambio, el diálogo avisa y exige una segunda acción para cerrar sin guardar.
- Los cambios automáticos de política de tasa o carga de cuentas no crean por sí solos un borrador. El guardado empieza tras una edición humana.

La validación final de cuentas, tasa, permisos y contrato sigue en las puertas existentes del servidor; el borrador local no es una solicitud confirmada.

## Verificación local del candidato

`npm run check`: PASS. Playwright completo en Docker: **234 passed, 26 skipped**; el recorrido nuevo de acceso, pausa, recuperación y revisión pasó en 390 y 1440 píxeles. `gate:realidad` quedó **NOT RUN** en este entorno porque no hay `SUPABASE_URL` configurada; no se infiere por ello ningún estado de producción.

Relacionado: [[Acceso y roles del CRM]], [[Plan de unificacion de conversion de leads y nueva inversion (2026-09-18)]], [[CI del CRM sin E2E en GitHub (2026-09-21)]].
