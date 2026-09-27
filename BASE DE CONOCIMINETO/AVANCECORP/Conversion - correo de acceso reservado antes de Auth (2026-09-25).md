---
tags: [crm, conversion, acceso-avance, incidente]
fecha: 2026-09-25
estado: recuperacion puntual ejecutada y verificada; correccion general pendiente
---

# Correo de acceso reservado antes de crear Auth

En una conversión Avance, el correo corregido en la ficha del lead no cambia el
`alta_portal.correo` de una solicitud de inversión ya preparada. La pantalla
«Corregir datos de acceso» admite la entrada, pero
`crm.corregir_solicitud_inversion_fn` devuelve `P0409` cuando hay
`auth_claim_id`, incluso si la saga sigue en `reclamado` y aún no existe usuario
Auth. El intento de corrección queda en la pestaña como «Actualización pendiente».

La consulta productiva de solo lectura para el caso reportado confirmó una única
solicitud preparada, reserva `reclamado`, sin usuario Auth asociado al claim y
con correo nuevo libre. El correo antiguo de esa solicitud pertenece a otra
cuenta Auth, por lo que completar el acceso con él tampoco resolvería el caso.
La reserva estaba activa durante el diagnóstico inicial; antes de ejecutar la
recuperación se comprobó que había vencido.

Se preparó un SQL puntual y protegido por estado, vencimiento, huella, ausencia
de usuario Auth y disponibilidad del nuevo correo:
`CRM-Avance-Corp/supabase/scripts/conversion-inversion/recuperar-correo-acceso-20260925.sql`.
Conserva el claim y su token, incrementa la versión de saga y la revisión de
datos, y usa el correo que ya figura en el lead. El SQL exacto se mostró a
Miguel y se ejecutó tras su autorización expresa. En la pestaña del CRM hay
que elegir «Descartar esta corrección y revisar la versión del servidor»;
eso recupera la revisión corregida, sin volver a enviar la corrección antigua.

**Postflight de solo lectura, 25/09:** solicitud `preparada`, revisión 1,
correo de acceso igual al de la ficha, claim conservado en estado `reclamado`,
huella de saga consistente con los nuevos datos, ningún usuario Auth para el
claim y exactamente una fila de corrección en revisión 1. Ninguna inversión
fue confirmada ni se creó acceso por herramientas. La continuación comercial
queda en el CRM, bajo revisión del correo por el usuario.

Revisión independiente de Claude: advirtió que borrar la reserva podría dejar
sin protección un handler tardío. Recomendó conservar el claim y no actuar con
lease activo. El primer dictamen fue `BLOCK` porque aún no existía SQL concreto;
dos intentos de revisar el SQL final no se completaron por fallo del wrapper y
no se atribuye aprobación. La implementación general para permitir corrección
segura antes de Auth queda separada de esta recuperación puntual.

## Continuación y aviso de celular

Después de que el usuario continuó en el CRM, una segunda consulta de solo
lectura confirmó que la cuenta Auth del claim **ya existe y usa el correo de
la ficha**, igual que la solicitud (revisión 1). La solicitud seguía preparada;
no se confirmó ninguna inversión mediante herramientas.

El aviso posterior «A tu propio perfil le falta celular» se refiere a
`public.perfiles.telefono` del `auth.uid()` que opera la pantalla, según la
definición productiva de `private.datos_legales_contrato_nucleo`. No consulta el
teléfono del analista seleccionado en la venta. El creador/responsable original
sí tenía teléfono; Miguel confirmó que la sesión del aviso era **Gerencia** y
reconoció la distinción. No atribuir ese aviso a caché ni cambiar la validación
para usar otro perfil.

Claude revisó este diagnóstico: devolvió `BLOCK` mientras aún se desconocía la
sesión y pidió identificarla antes de atribuir la causa a caché. La respuesta
posterior del usuario resolvió esa ambigüedad; no se presenta aquel dictamen
como aprobación de una implementación. La regla comercial solicitada es usar
el correo corregido en ficha o mediante «Corregir datos de acceso» antes del
primer acceso. El ajuste general de solicitudes ya reservadas sigue pendiente.

## Verificación posterior solicitada por Miguel

25/09/2026, árbol local actual, sin publicación ni cambios de código de producto:

- PASS: 72 pruebas en `lead-drawer-convertir.test.tsx`,
  `contrato-nuevo.test.tsx` e `inversion-solicitud.test.ts`.
- PASS: 17 pruebas en `inversion-nueva-venta-cruzada.test.tsx`,
  `inversionistas-api-msw.test.ts` e `inversionistas-api-error.test.ts`.
- PASS: 21 pruebas de handlers de acceso y bienvenida.
- PASS: 12 E2E locales en Docker, `acceso-avance-ux.spec.ts` y
  `contrato-crear.spec.ts` (40,7 segundos; dos workers). Cubren escritorio/móvil,
  borradores, reapertura, acceso y revisión contractual con backend simulado.
  No acreditan las guardas SQL productivas de una reserva existente.
- PASS: lint (con avisos existentes), typecheck y build.
- NOT RUN: `gate:realidad` no pudo medir porque el proceso no tenía
  `SUPABASE_URL`. Las consultas productivas focalizadas de esta nota sí se
  ejecutaron por MCP, solo lectura. No sustituyen ese gate global.
- NOT RUN: emisión de contrato y envío de correo reales. No se usaron datos
  productivos como banco de pruebas.

El primer intento E2E se detuvo antes de probar por el array vacío
`CONTAINER_ARGS` con Bash de macOS. Se repitió con el parámetro ya soportado
`CRM_E2E_CONTAINER=crm-acceso-verificacion-20260925`; la corrida posterior pasó.
No se modificó el script de pruebas.

Estos resultados verifican los recorridos cubiertos, **no** resuelven los dos
casos pendientes: propagar el correo de ficha a una solicitud ya preparada y
admitir una corrección segura cuando su acceso quedó reservado sin Auth.

Relacionado: [[Conversion de lead con Nueva inversion - preparado 2026-09-19]],
[[Conversion - correccion de credencial de acceso 2026-09-19]],
[[Identidad unificada de inversionistas - plan pendiente]].
