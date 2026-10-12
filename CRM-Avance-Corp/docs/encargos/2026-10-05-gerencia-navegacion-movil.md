# Gerencia: navegación móvil del CRM

## Objetivo y alcance aprobado

Miguel aprobó la vista local de la barra **Resumen · Citas · Metas · Más** y pidió completar su adaptación y el plan de implementación. Esta entrega adapta la navegación compartida de los 18 módulos que Gerencia ya tiene autorizados.

Se activa para el rol `gerencia` con un ancho menor de 768 px, tanto en navegador como en la PWA. A partir de 768 px se conserva el menú lateral. Los demás roles conservan su navegación actual. Los datos, filtros, permisos y operaciones de cada módulo siguen usando sus fuentes y reglas existentes.

Estado: **publicado y verificado en https://crm.miavance.com/**, con autorización de Miguel. [PR #201](https://github.com/avanza-digital/avancecorp-crm/pull/201) integrado en `1d4134e6476f007ac14cbb38df42b84e22fe862f`; build vivo `build-20261006T031013454Z`. Los controles `app-check`, `verify`, `preflight` y `cambios` pasaron. Main local y `avancecorp/main` coincidían al construir y publicar. [Acta de publicación](../publicaciones/gerencia-navegacion-movil-2026-10-05.md).

Vista interactiva: <http://127.0.0.1:5184/navegacion-movil.html>. Utiliza datos de ejemplo identificados como demo.

## Distribución final

| Ubicación | Módulos |
| --- | --- |
| Barra inferior | Resumen, Citas, Metas y botón Más |
| Más: accesos visibles | Facturación, Ranking, Gestión Diaria, Cartera |
| Más → Análisis | Rendimiento, Conversiones, Empresas |
| Más → Operación | Leads, Pipeline, Agenda, Repartir leads, Base para gestión, Seguimiento |
| Más → Administración | Gestión de equipo, Configuración |
| Pie de Más | Identidad, rol y cierre de sesión |

La campana de pendientes sigue en la cabecera. Las subpantallas de Configuración y Base para gestión seleccionan su módulo correspondiente. Los totales de citas por equipo del Resumen conservan el enlace con equipo y período aplicados.

## Implementación local completada

1. **Integración del menú.** `Sidebar` entrega su catálogo ya filtrado a `NavegacionGerenciaMovil`; no existe una segunda lista de permisos. `App.Workspace` elige la presentación usando el ancho reactivo y el rol.
2. **Espacio para el contenido.** La barra ocupa su propia fila del layout. El contenido mantiene su scroll y termina antes de la barra, incluidos los 18 destinos. Los márgenes inferiores consideran el área segura que expone el navegador.
3. **Panel Más.** Diálogo inferior con grupos, módulo seleccionado, cierre por botón, fondo o Escape y foco contenido dentro del panel. Al navegar se cierra y lleva el foco al contenido. Al pasar a tablet con el panel abierto, lo desmonta, libera la página y recupera el foco.
4. **Pantallas bajas y accesibilidad.** La lista de Más se desplaza sin comprimir cabecera o cierre de sesión. Botones táctiles amplios, selección accesible, foco visible y animaciones que respetan movimiento reducido.
5. **Rutas e historial.** Se conserva el router del CRM. Atrás/Adelante cambia la ruta y cierra Más si cambia la vista; abrir Más no añade una ruta artificial. El cierre de sesión usa la acción existente.
6. **Pruebas compartidas.** Los helpers E2E eligen el menú que está visible, para probar tanto el lateral como la barra inferior.

Archivos de producto: `app/src/App.tsx`, `app/src/components/app/sidebar.tsx`, `app/src/components/app/navegacion-gerencia-movil.tsx` y su CSS. Soporte: `app/e2e/navegacion-gerencia-movil.spec.ts`, `_helpers.ts`, `_navegacion.ts`, siete specs existentes que cambiaban a móvil y esperaban el lateral, y el comparador local `app/navegacion-movil.html` (no es una entrada del build de producción).

No se necesita una migración, dependencia nueva ni cambio de API. Esta fase cubre la navegación común; una futura simplificación de tablas o formularios de cada módulo tendría su propio alcance.

## Verificación y criterios de aceptación

| Comprobación | Estado |
| --- | --- |
| `npm run check`: lint, TypeScript, tests con cobertura, configuración de release, service worker, build, bundle y duplicación | PASS: 379 archivos de tests / 6.120 pruebas |
| E2E local Docker: 18 destinos, geometría, Más, foco, Escape, Atrás, pantalla horizontal, tablet y otros roles | PASS; incluidos en la suite completa final, sin reintentos |
| Gate integral: `npm run check` + suite Docker completa | PASS: 351 E2E aprobadas, 26 omitidas, 0 fallos; 13,8 min; 2 workers y 0 reintentos |
| Vista real del frontend en Chrome: Resumen, Citas, Metas, apertura/cancelación de Nuevo lead y vuelta móvil → escritorio → móvil | PASS en demo, 390 px |
| Revisión secundaria por wrapper del proyecto | PASS; sin hallazgos bloqueantes. Incorporada la espera explícita de Más en el helper de navegación |
| PWA instalada en iPhone/Android físico | NOT RUN; pendiente del smoke de publicación |
| Gate con base real | NOT RUN: faltan credenciales de servicio en shell; no se modifican consultas ni datos en esta fase |

Las comprobaciones automáticas se ejecutan en una copia limpia del commit base con únicamente los archivos de este cambio. El workspace tiene modificaciones y duplicados de sincronización ajenos que se conservan. Evidencia local: `output/navegacion-movil-local/`.

Debe quedar acreditado que:

- Gerencia móvil ve los tres destinos principales y Más; los 18 módulos siguen alcanzables.
- Una ruta de configuración autorizada conserva su selección tras recargar; una ruta reservada a superadmin sigue redirigiendo según los permisos actuales.
- El contenido no queda bajo la barra; la lista de Más funciona a 667 × 375 y la página no desborda horizontalmente a 360/390/430 px.
- Cambiar a tablet recupera el lateral sin dejar una capa bloqueante ni perder el foco.
- Analista, Supervisor y Directorio conservan sus menús. No se abren destinos adicionales por cambiar de presentación.

## Plan para integrar y publicar

1. **Validación local — completada.** `npm run check` y toda la suite Docker pasaron. Review evaluado, mejora del helper incorporada y siete pruebas antiguas adaptadas a la nueva navegación. Capturas, logs, decisión de review y hashes guardados. Si el código cambia durante la integración, repetir los checks afectados.
2. **Cambio aislado — completado.** Quince archivos de implementación/soporte y documentación integrados por el PR #201 contra `avancecorp/main`. Se conserva también una nota de B11 que ya estaba confirmada en Main local. Los trabajos sin confirmar del workspace quedan preservados. El comparador local no forma parte del artefacto productivo.
3. **Integración de Main — completada.** GitHub fusionó el PR mediante squash en `1d4134e6476f007ac14cbb38df42b84e22fe862f`. Se comprobó la igualdad de árboles antes de alinear Main local; índice y archivos locales permanecieron intactos. Main local y remoto coinciden. El código de la app es idéntico al verificado en `7253de7e`.
4. **Construcción y publicación — completadas.** `npm run release:crm`, verificación del manifiesto y preflight PASS. Fuente limpia, demo deshabilitada, destino `crm.miavance.com`. Hostinger aceptó el ZIP `crm-20261006T031014Z-1d4134e6476f.zip`; el build servido es `build-20261006T031013454Z`.
5. **Comprobación web — completada.** 135 archivos publicados coinciden byte a byte con el manifiesto, incluidos HTML, JS/CSS, service worker y versión; 13 PNG responden HTTP 200. Gerencia real: Resumen → citas de un equipo con día y supervisor conservados → Metas → Más → Ranking, vuelta con Atrás y cambio móvil/escritorio PASS. PWA instalada en dispositivos físicos: NOT RUN; teclado, giro, área segura y cierre de sesión en esos dispositivos siguen pendientes.
6. **Acta — registrada.** [Publicación, huella y límites de validación](../publicaciones/gerencia-navegacion-movil-2026-10-05.md), con evidencia en `output/navegacion-movil-local/deploy/`. ZIP y manifiesto anteriores conservados. Cualquier recuperación sigue el preflight y procedimiento vigente de publicación.

La versión efectivamente publicada queda vinculada al commit y al manifiesto del artefacto, aunque después se confirmen estas actas. La comprobación visual se realizó con sesión real de Gerencia en Chrome a 390 × 844 y 1024 × 768; no sustituye la prueba de la PWA instalada en un dispositivo físico.
