---
tags: [crm, rentabilidad, publicacion]
fecha: 2026-09-18
estado: publicado
---

# El botón controla toda la exigencia de tasa

Miguel pidió: «ok el boton tiene que controlar todo por favor», después de
[[Modo observacion mantiene solicitud de tasa - diagnostico 2026-09-18]].

Implementación en CRM, portal y ocho funciones SQL. En observación
no se solicita ni consume aprobación y las solicitudes pendientes dejan de
bloquear conversión/alta. Al reactivar vuelve enforcement. Se conserva el
historial y se enlazan aprobaciones compatibles para que sigan sirviendo si
se reactiva después de convertir y antes de contratar. Conflictos o documentos
distintos no se enlazan y no bloquean observación.

Siguen vigentes identidad, permisos, origen del contrato, tasa positiva con
dos decimales, tope técnico y PDF. Renovación/upgrade conserva la base heredada
aunque supere el tope actual, hasta el máximo absoluto de 50 %. La consulta
productiva de solo lectura encontró dos contratos activos/vencidos >28 %.

Las pantallas refrescan el modo cada 30 segundos y al recuperar foco. Si se
reactiva con una tasa distinta y el campo queda fijo, muestra que es inválida
y permite confirmar la tasa vigente, sin sustituirla silenciosamente.

Verificación local: 3.697 pruebas CRM, build y gate integral; ocho E2E de tasas
en escritorio/móvil; SQL con modo efectivo, pendientes, aprobación previa,
herencia y reversa exacta; tres pruebas nuevas de portal. Los dos fallos del
banco completo del portal existían antes (83/85 baseline; 86/88 candidata).
Detalle y dictámenes en `CRM-Avance-Corp/supabase/scripts/rentabilidad-modo/`.

Migración aplicada en producción el 18/09/2026 a las 16:05 Lima:
`20260918210543_crm_modo_rentabilidad_integral.sql`.
La candidata verifica la definición completa de las ocho funciones antes de
reemplazarlas. No cambia la política elegida por Gerencia ni datos de negocio.
La prueba usa Docker y datos sintéticos, con las funciones/puertas vigentes
capturadas por SELECT. No equivale al ensayo remoto con matriz RLS/advisors.

La rama remota vacía no pudo reconstruir dos migraciones históricas que exigen
datos productivos en sus postflights. Se eliminó para detener el costo. El SQL
completo pasó en producción dentro de una transacción con `ROLLBACK` antes de
aplicarse; después se comprobaron hashes, capacidad pública, una solicitud
pendiente real sin bloqueo en observación y advisors con 0 errores.

El código quedó integrado por el PR #18 en
`6b8ffe150c656706ebe7a84b07234f3968511b1e`; preflight, verify y E2E de CI
pasaron. El release CRM reproducible quedó preparado como
`crm-20260918T213021Z-6b8ffe150c65.zip`, SHA-256
`48a835f74a1f40ed8d11787475fe9f8c4173fee62217599415a539037dc61e29`.
El portal quedó en `cbff0bc66bc06d2163f83276a90cb9126d94fc7f`, con paquete
`portal-20260918T213120Z-cbff0bc66bc0.zip`, SHA-256
`2b8b3c91a4e5b046c004b985ad6eac27e79bed40e25f5c43ebfd2eb554952d3d`.

Frontend publicado en Hostinger el 18/09/2026 y verificado a las 17:54 Lima mediante
`_DEV_NO_SUBIR/deploy-hostinger-mcp.mjs`: CRM y portal devolvieron carga
correcta y `Request accepted`. Se purgó LiteSpeed/CDN en ambos dominios.

Verificación productiva: tres lecturas estables del CRM devolvieron
`build-20260918T213020308Z`; `index.html`, `assets/index-YRxtvagF.js` y
`assets/index-BOfD5cL9.css` coincidieron byte por byte con el ZIP. En el portal,
`admin/analista.html`, `analista.js?v=28`, `admin/contratos.html`,
`contratos.js?v=43`, `_helpers.js` y `service-worker.js` coincidieron byte por
byte con el paquete. El asset CRM anterior quedó en 404 y ninguno de los dos
ZIP quedó expuesto en ninguno de los dominios. La base de datos, el CRM y el
portal quedan publicados como una sola entrega.

Relacionado: [[Inicio]],
[[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]],
[[Solicitud de tasa en el lead - publicada 2026-09-09]],
[[Rentabilidades menores a 15 - publicacion autorizada 2026-09-14]].
