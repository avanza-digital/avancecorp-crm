# Plan de implementación y cierre de la PWA de Gerencia

El objetivo es que Gerencia pueda revisar la operación, identificar los pendientes importantes y llegar al caso correspondiente desde el teléfono. El alcance visual es Gerencia por debajo de 768 px, tanto en navegador como en PWA instalada.

La distribución solicitada por Miguel es **Resumen · Citas · Gestión Diaria · Más**. Metas y cumplimiento queda en Más. **Las cuatro mejoras están implementadas e integradas en el workspace local al 6 de octubre de 2026**. La publicación, el contraste con backend y la validación de PWA instalada en dispositivos físicos siguen pendientes; el detalle de resultados está debajo.

## Base publicada

| Pieza | Estado de partida |
| --- | --- |
| Menú lateral de Gerencia organizado | Publicado |
| Resumen compacto y número de citas por equipo con enlace | Publicado por PR 199 |
| Barra inferior y panel Más con los 18 destinos autorizados | Publicado por PR 201; la tercera posición publicada todavía es Metas |
| Señales de gestión | Ya existen prioridad, filtros, búsqueda, enlaces, errores y estados vacíos |
| Solicitudes de tasa | Tienen contador y bandeja propios; el Resumen ya permite abrirlos |
| Avisos de tasa al teléfono | Implementados y publicados; verificar la recepción y apertura en los dispositivos de la prueba final |
| Conexión y actualización de versión | Ya existen avisos y revalidación; falta comprobar su convivencia completa con la navegación móvil |
| PWA instalada en dispositivos físicos | Pendiente de comprobación del conjunto |

Referencia de navegación publicada: commit `1d4134e6476f007ac14cbb38df42b84e22fe862f`, build `build-20261006T031013454Z`. Las actas de esa entrega conservan su distribución histórica; este plan registra el cambio posterior solicitado por Miguel.

## Resultado local al 6 de octubre de 2026

| Entrega | Resultado implementado |
| --- | --- |
| 1 Pendientes en Resumen | Hasta tres avisos activos, críticas primero; total del proveedor de la campana; Ver todos; carga, vacío, fallo parcial y desconexión explícitos |
| 2 Bandeja móvil | Tarjetas compactas, filtros plegables y activos visibles; consulta en memoria por cuenta/rol; regreso con scroll y foco, incluida la desaparición del aviso |
| 3 Pantallas prioritarias | Gestión Diaria con ordenación compacta; Citas conserva filtros, vista y página; Ranking y Metas compactan fuentes e indicadores; Facturación contiene la tabla y conserva nombres; Cartera muestra consulta y conteo |
| 4 PWA | Desconexión visible, revalidación existente, actualización voluntaria aplazable, ajuste de teclado/viewport y convivencia con Más y diálogos |

La integración conserva los cambios locales ajenos `ResumenGestionesHoy` y `CitasClientes`. No hubo commit, PR ni publicación de esta entrega. La copia aislada verificada parte del commit de PR 201 mencionado arriba; la vista local utiliza datos demo.

Validación:

- Lint, tipos, compilación, bundle y límite de duplicación: **PASS**.
- Cobertura unitaria completa: **6.129 pruebas PASS** antes de los ajustes finales. Después: **249 pruebas específicas PASS** en la copia aislada; **251 PASS** y tipos PASS en el workspace integrado.
- Suite Docker completa: **354 PASS, 5 con reintento, 26 omitidas y 1 fallo persistente**. Se corrigió el aviso de mes cerrado que quedaba oculto al plegar Fuentes.
- Revalidación final Docker, un worker y cero reintentos: **15 PASS**. Incluye ese caso corregido, los cinco casos intermitentes y los nueve recorridos nuevos de PWA. No se ha repetido la suite completa después de la corrección.
- Review secundario mediante el wrapper: **CHANGES_REQUESTED**; Codex evaluó sus observaciones, corrigió las aceptadas y ejecutó las verificaciones. Resolución en el acta local.
- Backend real: **NOT RUN**, falta `SUPABASE_URL`. PWA instalada, teclado/áreas seguras y recepción de push en Android/iPhone físicos: **NOT RUN**, no disponibles en la sesión.

Evidencia: `output/pwa-gerencia-cuatro/ENTREGA.md`, `verificacion.json`, `review-resolucion.md`, logs, capturas, patch y copias de integración. Vista local: <http://127.0.0.1:5184/navegacion-movil.html>. Las secciones siguientes conservan los requisitos y criterios de cierre de cada entrega; las comprobaciones físicas y de publicación aún no están cerradas.

## Decisiones de la adaptación

- La barra tendrá Resumen, Citas, Gestión Diaria y Más. Metas seguirá accesible dentro de Más y desde el indicador de meta del Resumen.
- El bloque nuevo del Resumen se llamará **Pendientes de gestión** y mostrará hasta tres avisos activos. Se colocará después de Citas por equipo y antes de Abrir el resumen completo.
- Las solicitudes de tasa conservarán su contador y bandeja. El total de la campana y del bloque de gestión contará avisos activos del mismo origen, sin sumar solicitudes ni confundir un aviso agrupado con el número de personas afectadas.
- La prioridad visual será Críticas antes de Atención. Dentro del mismo nivel se conservará el orden de la fuente. El resumen y la bandeja móvil utilizarán la misma selección y orden; la lista original no se modificará en el proceso.
- Cada tarjeta mostrará motivo, prioridad, responsable cuando esté disponible y un acceso al destino existente. Un caso de empresa no recibirá un equipo o responsable inventado.
- El modelo común no contiene una fecha de creación para todas las alertas. La hora de actualización se rotulará como tal. Solo se mostrará antigüedad cuando la fuente aporte una fecha adecuada; este alcance no requiere añadir un campo de base de datos para ello.
- Abrir una tarjeta llevará al caso. Las acciones disponibles seguirán siendo las autorizadas por el flujo existente; no se añadirá un botón genérico de resolver o posponer para Gerencia.
- El alcance previsto usa las fuentes, rutas y permisos existentes. No requiere migraciones ni nuevas dependencias. Cualquier ampliación de información que necesitara backend tendría su propio alcance.

## Entrega 0 Gestión Diaria en la barra

Cambiar el tercer acceso inferior, conservar el icono y nombre del catálogo compartido y trasladar Metas y cumplimiento a Más. El selector activo debe señalar Gestión Diaria al entrar en ese módulo y Más al entrar en Metas.

Actualizar el comparador local y las pruebas existentes. Verificar el texto completo a 360 px, los 18 destinos, Atrás, apertura y cierre de Más, cambio a tablet y navegación de los demás roles. Esta entrega puede publicarse de forma independiente del desarrollo de Pendientes.

Resultado local de este ajuste: `npm run check` PASS, 379 archivos y 6.120 pruebas; E2E de navegación en Docker PASS, 9 pruebas y 0 reintentos; comprobación visual a 360 × 800 PASS. La suite Docker completa y el smoke de dispositivos físicos no se han repetido para este ajuste. Evidencia: `output/gestion-diaria-acceso-local/verificacion.json`, logs y `gestion-diaria-360.png`. Vista local: <http://127.0.0.1:5184/navegacion-movil.html>. No se ha creado un nuevo PR ni deploy de esta corrección.

## Entrega 1 Pendientes visibles desde Resumen

Preparar una vista local dentro del CRM con casos de cero, uno y más de tres avisos; combinación de prioridades; nombres largos; carga y fallo parcial. Mantener identificados los datos de ejemplo.

Conectar **Pendientes de gestión** a `useAlertasCRM`, utilizando los datos que ya consume la campana. Mostrar como máximo tres tarjetas compactas y **Ver todos**, con el total de avisos activos. El bloque debe permitir identificar el motivo y abrir el destino sin depender de un icono sin texto.

Reutilizar un selector de presentación para activos y prioridades. Conservar reconocimientos y posposiciones donde el proveedor los entregue. Las consultas, sus intervalos y la lectura de permisos continuarán en sus proveedores actuales; el bloque no iniciará un sondeo duplicado.

Aceptar esta entrega cuando el total del bloque y la campana coincidan para una misma respuesta, las tres tarjetas correspondan al inicio de la bandeja móvil y los accesos mantengan el contexto del caso.

## Entrega 2 Bandeja móvil y navegación de regreso

Adaptar Señales de gestión para Gerencia móvil con cabecera breve, última actualización, prioridades visibles y tarjetas fáciles de tocar. La campana abrirá la ruta existente de Pendientes; la barra inferior seguirá disponible.

Los filtros de tipo y búsqueda se agruparán bajo **Filtrar**, con indicación de filtros activos y acción para limpiar. Se conservará la búsqueda sin distinción de tildes, el total sin filtrar y la separación entre activas, reconocidas y pospuestas. Abrir o cerrar los filtros conservará la consulta aplicada.

Al abrir un aviso, reutilizar la navegación actual. Los avisos gerenciales que llevan período deben restaurar ese período y limpiar el origen anterior como hace la bandeja existente. Los avisos operativos sin período no deben cambiar la consulta de Gerencia.

Conservar filtros y posición al regresar desde un caso. Guardar únicamente estado de presentación en memoria de la sesión, ligado al usuario; restablecerlo al cambiar de cuenta o salir. No persistir una copia de las alertas o nombres en almacenamiento del navegador para este fin.

Aceptar esta entrega cuando Abrir caso, Atrás, recarga, limpieza de filtros y cambio entre móvil y escritorio funcionen sin perder acceso a un módulo ni mostrar datos de otro usuario.

## Entrega 3 Pantallas prioritarias para uso diario

La navegación publicada adapta el acceso a los 18 módulos. La adaptación de cada tabla, formulario y detalle se revisará por separado, con capturas y recorridos reales antes de modificarlo.

| Prioridad | Pantallas | Comprobación y ajuste cuando haga falta |
| --- | --- | --- |
| 1 | Gestión Diaria | Resumen de equipos, filtros, lectura de actividad y entrada al detalle cómodos desde el teléfono |
| 2 | Citas | Día y equipo visibles, filtros desplegables, consulta y regreso conservados; los números del Resumen llevan al mismo conjunto |
| 3 | Ranking y Metas | Indicadores legibles, período visible, detalle por persona y comparación sin depender de columnas fuera de pantalla |
| 4 | Facturación y Cartera | Totales y moneda claros, búsqueda y detalle accesibles, filtros utilizables con teclado abierto |
| 5 | Otros módulos del panel Más | Acceso, lectura básica, scroll y controles esenciales operables; registrar cualquier adaptación específica pendiente |

Utilizar tarjetas o detalles desplegables donde mejoren la lectura. Mantener una tabla con desplazamiento contenido cuando sea necesaria para comparar columnas. Cada cambio conservará el significado de cifras, monedas, períodos y filtros. Los defectos detectados se registrarán por pantalla para cerrar el alcance por entregas.

## Entrega 4 Comportamiento completo de la PWA

Comprobar y ajustar los avisos de nueva versión, mensajes temporales, diálogos y teclado para que no oculten la barra ni la acción principal. El aviso de versión actual tiene posición fija inferior; debe probarse expresamente junto con Más y con formularios abiertos.

Mantener la actualización de versión como una decisión de la persona después de guardar. Al volver de segundo plano, recuperar datos vigentes y comprobar el cambio de día en Lima sin sobrescribir un período histórico seleccionado.

Extender al bloque de Pendientes la indicación de conexión y de información desactualizada que ya utiliza el Resumen. Al recuperar la conexión, revalidar con el proveedor compartido. Este alcance no incorpora aprobaciones ni otras operaciones de negocio sin conexión.

Verificar los avisos de tasa existentes mediante Enviar prueba en dispositivos autorizados: recepción, apertura del destino correcto, sesión vencida, permiso denegado y cambio de cuenta. La pantalla bloqueada conservará el contenido genérico actual, sin nombres ni importes. No se creará otro sistema de notificaciones.

Revisar los avisos de animación GSAP registrados en el smoke anterior si se reproducen en las vistas adaptadas; priorizar cualquier caso que afecte a la lectura o navegación.

## Estados que deben quedar cubiertos

| Situación | Comportamiento esperado |
| --- | --- |
| Primera carga | Estado de carga; no anunciar cero mientras falta la respuesta |
| Actualización en curso | Conservar contenido utilizable e indicar la actualización sin mover innecesariamente el foco |
| Sin avisos generados | Explicar el alcance del resultado; no afirmar que todos cumplieron la meta |
| Solo avisos reconocidos o pospuestos | Conservar su explicación y separación; no contarlos como activos |
| Una fuente falla | Mostrar información incompleta y reintento; el total disponible no se presentará como una evaluación completa |
| Sin conexión | Advertir de posible desactualización; no anunciar éxito en una operación no confirmada |
| Filtro sin coincidencias | Permitir limpiar filtros y conservar el total global |
| Aviso desaparecido o acceso denegado | Mostrar la respuesta del flujo existente y permitir volver a la bandeja |
| Retorno desde un caso | Restaurar la consulta de la bandeja y el foco en un punto útil |
| Cambio de cuenta | Eliminar estado de presentación vinculado a la cuenta anterior |

## Pruebas y revisión

Ejecutar pruebas del selector compartido, conteos, orden, estados incompletos, rutas con período y regreso a filtros. Ampliar las pruebas de comportamiento existentes de Alertas, Resumen móvil, campana y navegación; comprobar la regresión de escritorio y de los demás roles.

Realizar los recorridos a 360, 390 y 430 px, horizontal 667 × 375, límite 767 y 768 px y escritorio. Incluir texto largo, zoom, foco por teclado, lector de pantalla, movimiento reducido, teclado virtual y áreas seguras. Los controles táctiles principales tendrán al menos 44 × 44 px.

Usar `npm run check` y E2E local mediante Docker. Durante el ajuste, ejecutar los specs relacionados; al cerrar una entrega sustancial de navegación o Pendientes y antes de publicar, completar el gate correspondiente de `.ai/VERIFICATION.md`, incluida la suite Docker completa cuando proceda. No ejecutar E2E en GitHub. Una revisión secundaria por `scripts/claude-review` evaluará la implementación de Pendientes con evidencia y resultados; el cambio simple de posición del menú no requiere otra revisión.

Intentar el gate de realidad cuando se disponga del entorno autorizado y contrastar los estados reales de vacío o error. Si no puede ejecutarse, registrar el motivo y completar la lectura productiva y las pruebas de esos estados sin presentarlo como PASS. Los escenarios de escritura se verifican en el banco de pruebas, sin crear ni modificar operaciones reales para probar la interfaz.

## Integración publicación y cierre

Trabajar sobre una copia limpia del Main vigente, conservando los cambios locales de otras tareas. Hay modificaciones en Gestión Diaria y Hoy en el workspace compartido; los cambios de presentación se integrarán revisando esos cruces, sin incluirlos accidentalmente ni crear worktrees automáticamente.

Preparar el PR de cada entrega con alcance y pruebas. Integrar los cambios remotos, obtener los controles de GitHub exigidos y comprobar la igualdad de Main local con `avancecorp/main`. Construir desde ese commit limpio, verificar ZIP y manifiesto y pasar el preflight del CRM antes de publicar en Hostinger.

Después del deploy, comprobar portada, versión, JS/CSS, service worker, huellas del artefacto y el recorrido de Gerencia. Conservar el ZIP anterior y registrar la versión efectivamente servida. Cualquier recuperación seguirá el procedimiento vigente de publicación.

Cerrar la validación de la PWA con un Android y un iPhone físicos disponibles, sobre el sitio HTTPS autorizado: apertura instalada, regreso de segundo plano, red intermitente, actualización, teclado, giro, áreas seguras, notificación y cierre de sesión. Si falta un dispositivo o permiso, registrar exactamente lo no probado; la validación física seguirá pendiente.

La adaptación queda completa cuando las entregas implementadas tienen pruebas y evidencia, los 18 destinos son accesibles, los conteos son coherentes, los estados incompletos están explicados y la comprobación física prevista está cerrada.

## Archivos y fuentes de implementación

| Pieza | Base que se reutiliza |
| --- | --- |
| Distribución móvil | `app/src/components/app/navegacion-gerencia-movil.tsx`, catálogo de `sidebar.tsx` y `app/e2e/navegacion-gerencia-movil.spec.ts` |
| Resumen | `app/src/screens/hoy/resumen-gerencia-movil.tsx` y su CSS y pruebas |
| Pendientes | `app/src/screens/alertas.tsx`, `app/src/lib/alertas-context.ts`, `alertas-provider.tsx`, `alertas.ts` y `alertas-gerencia.ts` |
| Campana | `app/src/components/app/topbar.tsx` |
| Actualización | `app/src/components/app/version-publicada.tsx` y `app/src/lib/version-publicada.ts` |
| Avisos al teléfono | `app/src/components/app/notificaciones-tasa.tsx` y pruebas de notificaciones existentes |

Referencias: actas de Resumen compacto, navegación móvil PR 201, nota de notificaciones de tasa y `.ai/VERIFICATION.md`. La división en tres tarjetas, la compactación de filtros y la secuencia de entregas son decisiones de este plan; la existencia de los proveedores, filtros y acciones se ha comprobado en el código actual.
