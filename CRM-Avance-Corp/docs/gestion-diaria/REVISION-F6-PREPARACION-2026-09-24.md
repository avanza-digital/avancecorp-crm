# F6 — Revisión de la preparación de Seguimiento

24/09/2026. Codex PRIMARY; Claude SECONDARY_REVIEWER mediante
`scripts/claude-review`, sin herramientas, MCP ni escritura. Dos consultas de
nivel 2 sobre el cambio incremental respecto de F5 `9bde971f` (árbol idéntico
a Main `8da4bcf3`). La segunda responde a una regresión real posterior. No se revisó
ni ejecutó la retirada futura.

**Dictamen inicial: PASS.** No hay cambios obligatorios ni hallazgos P0–P2. Confianza
MEDIUM-HIGH. La revisión no sustituye las pruebas ni la aprobación humana de
GitHub. Texto íntegro: [respuesta](f6-preparacion-2026-09-24/review.txt).

## Evidencia y alcance

Se adjuntaron el diff, las rutas y política de vistas, la sincronización de
App, la frontera y cola SLA existentes, las consultas compartidas y los siete
recorridos E2E nuevos. CodeGraph se consultó primero; las referencias que no
resolvió se completaron con lectura dirigida de la copia autorizada.

El gate integral terminó con **4.393 pruebas / 297 archivos PASS**, incluido
build, antes de recibir el dictamen. Los siete E2E focalizados pasaron en
Docker Chromium, un worker, sin reintentos. La regresión completa se registra
por separado en el [acta de preparación](f6-preparacion-2026-09-24/ACTA.md).

## Evaluación de recomendaciones P3 por PRIMARY

| Recomendación | Decisión y evidencia |
| --- | --- |
| Derivar la lista de roles de la política compartida | Se conserva la defensa explícita de la pantalla, coherente con su anterior distribución por rol. `App.sanearVista` continúa aplicando la política completa, incluido el gate y el rol Portal, antes de montar el módulo. Los tres roles operativos y los dos denegados están cubiertos. No se amplía la autorización. |
| Unificar todos los nombres de destino | «Ver todas las oportunidades» explica la salida del resumen parcial; «Seguimiento completo» identifica la sección; «Seguimiento comercial» conserva el nombre del componente existente y su accesibilidad. Son rótulos con funciones distintas para el mismo destino; no se cambia el contrato histórico durante esta preparación. |
| Sacar el enlace de la región de estado | Mejora opcional de verbosidad, sin impedimento de teclado ni prohibición ARIA. Se conserva el anuncio del rango y de la existencia de más oportunidades. No se declara una auditoría completa con lector de pantalla. |
| Precisar el clic lateral estando en la cola | El menú lateral selecciona el módulo y conserva su sección actual, igual que el detalle gerencial existente. «Resumen del día» es el acceso explícito de regreso. No se introduce un reinicio silencioso de la cola al pulsar el módulo activo. |

Se añadieron recorridos de supervisor y vendedor que eliminan los detalles
`equipo`/`analista`, conservan una ficha permitida y llegan a la cola. También
se verificó el clic lateral activo conservando la página 101–105. Los nueve
recorridos de cola pasaron en Docker. El enlace trivial de «hay más» no recibió
una prueba específica; no se atribuye como caso ejecutado.

## Regresión real y segunda consulta

La primera regresión completa encontró FAIL en tres controles: franja de
cortes H4 y densidad H2 a 1.512 y 1.366 px. La página excedía el viewport en
68 px: navegación de 48 px más 20 px de separación encima de un supervisor
que ya consumía su altura. Se detuvo solo el contenedor propio y se conservaron
los errores originales.

PRIMARY trasladó el acceso a «Seguimiento completo» a la fila de acciones
existente del supervisor. Conservó CSS, tamaños de texto, filas y tolerancias
de los tests. La cola y los otros roles mantienen la navegación de dos enlaces.
Los controles son de al menos 44 px. Resultado después del cambio:

- Gate integral: 4.393 pruebas / 297 archivos PASS, incluido build.
- Docker cola, equipo y cortes: 19/19 PASS, incluidos los tres fallos anteriores.
- Docker de cola con los dos recorridos adicionales: 9/9 PASS.

La segunda consulta obtuvo PASS, confianza MEDIUM; texto íntegro en
[review de densidad](f6-preparacion-2026-09-24/review-densidad.txt).
El reviewer dejó una hipótesis P2 porque no recibió el CSS de gerencia:
posible altura fija análoga. PRIMARY la descartó con `gerencia.tsx`
(`section.gd-pulso`) y `gerencia.css:1`: altura natural, sin `.gd-supervisor`
ni `100svh`. Importa supervisor.css para componentes compartidos, sin aplicar
su clase de altura al contenedor. No es un defecto confirmado ni requiere
reducir el alto de gerencia. No se pidió una tercera revisión.

Se aceptan dos observaciones P3: en un escritorio estrecho las acciones pueden
envolverse y reducir filas visibles; el resumen de supervisor tiene un único
enlace de sección, mientras la cola ofrece ambos. Las filas siguen accesibles
por scroll interno. No se atribuye una medición específica a 1.280 px con el
menú abierto ni una auditoría completa con lector de pantalla. La regresión
integral final se acredita separadamente en el acta.

## Límites conservados

- El transporte E2E está interceptado. Sus 403 y ámbitos prueban la respuesta
  de la UI; no acreditan nuevamente RLS real. No cambia SQL ni ninguna RPC.
- Abrir/cerrar una ficha conserva filtros y página. Salir de la sección o
  recargar inicia sus valores predeterminados, como la pantalla anterior.
- La fecha de gerencia conserva la memoria de F5. El resumen del supervisor
  mantiene su comportamiento al volver a montar: empieza en hoy.
- Los enlaces antiguos siguen en Seguimiento; su futura redirección y retirada
  permanecen NOT RUN. Los siete días reales todavía no han empezado.
- Una futura normalización de ruta que cambie la sección con `replaceState`
  deberá notificar la navegación; este cambio no introduce esa normalización.
