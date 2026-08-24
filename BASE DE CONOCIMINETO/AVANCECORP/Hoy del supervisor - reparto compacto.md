---
tags: [crm, ux, supervisor, leads, asignacion]
actualizado: 2026-08-23
estado: desplegado-produccion
---

# Hoy del supervisor - reparto compacto

Decisión de producto: la pantalla **HOY** del supervisor resume el trabajo por
repartir en un único KPI accionable. La asignación detallada permanece en el
módulo **Derivar leads**; no se duplican allí filas, selectores ni botones de
asignación.

Relacionadas: [[Distribución de leads por capital y trazabilidad CRM]] ·
[[CRM conexión a datos reales]] · [[Acceso y roles del CRM]] ·
[[Derivar leads del supervisor - paginacion compacta]].

## Comportamiento acordado

- Toda la tarjeta `Por repartir` abre `#/derivaciones` y funciona con mouse y
  teclado.
- Con pendientes muestra el conteo autorizado por el resumen del servidor, la
  espera observable del caso más rezagado cuando el detalle local está
  disponible, el texto `Repartir →` y un único acento ámbar de 3 px.
- Sin pendientes conserva el acceso con `Bandeja al día · Ver historial →` y no
  presenta el acento de alerta.
- Si falla el resumen, no se inventa un conteo: se muestra `—` y se mantiene el
  acceso a Derivaciones.
- El tamaño del KPI no cambia entre estados ni se añade una animación nueva.

## Alcance técnico

El cambio es exclusivamente de interfaz. No altera RPC, políticas, base de
datos ni la operación completa de reparto. Queda cubierto con pruebas de los
estados pendiente/vacío/sin dato, autoridad del conteo del servidor, destino del
enlace, retiro de controles duplicados y navegación por teclado. Miguel validó
visualmente la propuesta antes de autorizar su publicación.

## Validación y despliegue

Miguel aprobó visualmente la propuesta local el 2026-08-23 y pidió publicarla.
El cambio se desplegó exclusivamente en `crm.miavance.com`, sin modificar el
portal ni Supabase, mediante el release
`crm-20260823T151159Z-94fd5304e5a3` (`build-20260823T151131Z`).

El build salió de una reconstrucción aislada de producción: antes de añadir el
KPI, sus 67 archivos coincidieron byte por byte con el manifiesto vivo anterior.
Después se incorporaron únicamente `supervisor.tsx`, su prueba de integración y
el E2E de navegación por teclado. El gate terminó con 2.133 pruebas, lint,
TypeScript, cobertura, build, verificación de bundle y duplicación en verde.

En producción, tres lecturas consecutivas de `index.html`, `version.json`, JS
principal, CSS y el chunk de HOY coincidieron con sus SHA-256 locales. El bundle
servido contiene los estados compactos y ya no contiene el título de la bandeja
grande. El ZIP responde 404 en CRM y portal, `.vite/license.md` responde 404,
`.htaccess` responde 403 y los assets principales anteriores responden 404. No
fue necesaria una purga de caché. Rollback inmediato:
`crm-20260821T233421Z-4335bb5f88e3`.
