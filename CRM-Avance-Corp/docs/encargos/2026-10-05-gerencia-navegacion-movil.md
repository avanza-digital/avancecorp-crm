# Gerencia: navegación móvil del CRM

## Objetivo y alcance aprobado

Miguel aprobó la vista local de la barra **Resumen · Citas · Metas · Más** y pidió completar su adaptación y el plan de implementación. Esta entrega adapta la navegación compartida de los 18 módulos que Gerencia ya tiene autorizados.

Se activa para el rol `gerencia` con un ancho menor de 768 px, tanto en navegador como en la PWA. A partir de 768 px se conserva el menú lateral. Los demás roles conservan su navegación actual. Los datos, filtros, permisos y operaciones de cada módulo siguen usando sus fuentes y reglas existentes.

Estado: **adaptación implementada y verificada en local**. No se ha creado un commit, PR ni publicación de esta navegación. Base de validación: `b286b2bfce9a24004e887ee0cb127ecf5dab5a23`.

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
2. **Preparar el cambio aislado.** Revisar el diff de los quince archivos de implementación/soporte y esta documentación. Crear el commit y PR contra `avancecorp/main` (`avanza-digital/avancecorp-crm`), excluyendo trabajos ajenos del workspace. El comparador local no se incorpora al artefacto productivo.
3. **Integrar Main.** Incorporar cambios remotos sin sobrescribirlos; resolver conflictos y repetir los checks afectados. Antes de publicar, comprobar que Main local y `avancecorp/main` apuntan al mismo commit. No usar `origin/main`, ramas de release adicionales ni force push.
4. **Construir el artefacto.** Ejecutar el preflight de publicación del proyecto y construir desde ese commit verificado, con demo deshabilitada. Registrar commit, build ID y hash del paquete; publicar mediante el procedimiento vigente del CRM cuando Miguel indique publicar.
5. **Comprobar la entrega.** Verificar el build servido, la actualización del service worker y las rutas de Gerencia. Smoke en navegador móvil y PWA instalada: Resumen → cita de un equipo → Metas → Más → módulo secundario; Atrás/Adelante, teclado al buscar, giro de pantalla, área segura y cierre de sesión. Comprobar también tablet y un rol distinto.
6. **Cerrar el acta.** Registrar PR, commit, build, resultados y limitaciones en el vault. Ante una regresión, revertir el commit en Main, verificar igualdad con `avancecorp/main` y reconstruir/publicar siguiendo el mismo procedimiento.

La publicación y la prueba en dispositivos físicos permanecen pendientes de esa fase; la vista local permite revisar desde ahora la adaptación implementada.
