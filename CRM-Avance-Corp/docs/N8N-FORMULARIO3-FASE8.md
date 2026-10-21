# Formulario 3 — fase 8: la fila a medio escribir no se rechaza en su primera vuelta

21/10/2026. Estado: **PUBLICADA Y VERIFICADA en producción** (14:32 Lima), desde `15e43d98` (PR #353 fusionada en `main`). Miguel autorizó publicar en n8n. Parte de `cargarDefinicionOperativaF7()` y se verifica con `verificarFase8` (`scripts/n8n/formulario3.fase8.mjs`).

## Qué pasó (ejecución 1883, 21/10, hora Lima)

- 08:30:11 arranca la vuelta programada. La hoja devuelve 280 filas; las 277–281 llegan con **solo la fecha** (`Fecha` entre la 01:22 y las 07:27 del 21/10) y las demás nueve columnas vacías. La hoja termina en la columna J: no había datos más a la derecha.
- 08:30:29 el flujo las rechaza («Falta el nombre completo; Faltan ambos teléfonos; Capital no reconocido…; Moneda no reconocida…»), registra cinco recibos `rechazado` y «Resumen de importación» lanza `Revisar filas de la hoja: 277 (rechazada), 278 (rechazada), 279 (rechazada), 280 (rechazada), 281 (rechazada).` → correo de aviso. En la misma vuelta las filas 261–276, completas, entraron al CRM (15 importadas, 1 duplicado).
- 08:32:45 última modificación de la hoja (metadatos de Drive).
- 08:35:18 la vuelta siguiente lee las cinco filas completas; sus huellas son otras, no están en la tabla de recibos y **las cinco se importan** («IMPORTADO ✓»). Hasta las 12:40 el latido sigue y no hay más errores.

**Lectura:** la hoja se escribe por tandas (las filas 261–276 traen leads de las 09:51 a las 23:39 del 20/10 y todas se escribieron hacia las 08:30 del 21/10; dentro de cada tanda las fechas van de más nueva a más vieja). La vuelta 1883 leyó la tanda a medias. **Nada se perdió**; el aviso fue una falsa alarma y quedaron cinco recibos `rechazado` sin lead detrás, que se quedan: ninguna huella volverá a coincidir y borrarlos no cambia nada.

## Qué cambia

Una fila cuyo único contenido es la fecha, legible y a menos de **48 h** de la hora de la vuelta (`inicio_ms` de «Control del envío», la misma que ordena el lote), está **en escritura**: se omite en esa vuelta **sin recibo**, igual que hoy se omite la fila vacía del todo, y se juzga en la siguiente. Si pasado el margen sigue con solo la fecha, se rechaza y avisa como hasta ahora: una fila vacía de verdad sigue avisando, solo que hasta dos días después. **El margen sale de las tandas medidas en la hoja** (24 tramos descendentes en las 280 filas): el lead más viejo de una tanda está a lo sumo **22,5 h** del más nuevo, también los fines de semana, así que 48 h es más del doble. Si algún día una tanda trae un lead de más de 48 h con solo la fecha, el resultado es el de la fase 7 (rechazo prematuro, un correo) y la fila entra igual cuando se complete. Esa garantía de aviso supone que la fecha no se renueva: es la del lead, el escritor no la toca (Codex, P3).

Lo que **no** está en escritura y sigue la regla de la fase 7 (`prepararFilaSegura`): cualquier otro dato en la fila (con nombre y sin teléfonos se rechaza en la primera vuelta), una celda de tipo raro (va a revisión por la celda), una fecha ilegible —también el número de serie de Sheets, que no se adivina— o la fecha vacía (fila vacía: se omite como siempre). Un `row_number` inválido sigue frenando todo.

**La cabecera se valida sobre las filas que no están en escritura** (Codex, P2). n8n omite las celdas vacías, así que la fila a medio escribir llega solo con `row_number` y `Fecha`; `validarColumnas` exige que la unión de claves de la lectura tenga todas las columnas, y una lectura hecha solo de filas así frenaba la vuelta con «Faltan columnas» en vez de omitirlas. Con una sola fila completa en la lectura (siempre, en una hoja acumulativa) la protección de cabecera es exactamente la de la fase 7.

Solo cambia el código del nodo «Preparar leads»: el preludio de la fase 7 queda byte a byte y se añaden `MARGEN_ESCRITURA_MS`, `filaEnEscritura` y `prepararFilaVuelta`. Los demás nodos, ajustes, credenciales y el latido no se tocan.

## Evidencia

- `node --test 'scripts/n8n/*.test.mjs'` → **63/63 PASS** (57 de fases 1–7 + 6 nuevos), en un worktree limpio de `avancecorp/main` (`8406775f`). Las pruebas ejecutan el código del nodo como lo hace n8n (`runOnceForAllItems`) con la fila tal como la devolvió la hoja en la vuelta 1883 (`{row_number, Fecha}`, sin las demás claves) y comprueban que la fase 7 la rechazaba y la fase 8 la omite; que con la vuelta dos días después se rechaza; que una lectura hecha solo de filas así se omite entera (la fase 7 frenaba con «Faltan columnas»); `pairedItem`; cabecera cambiada; falta de `inicio_ms`.
- **Mutantes:** 13 sobre las defensas nuevas, todos MUERTOS (margen exclusivo; sin valor absoluto para una fecha futura; otro dato no descalifica; celda rara se omite; identidad inválida no fatal; sin exigir la versión de fase 7; gate publicado sin exigir la versión activa; gate sin exigir el código de fase 8; sin exigir la hora de la vuelta; hora del reloj en vez del control; sin aviso de «ya aplicada»; margen distinto al documentado; cabecera validada también sobre las filas en escritura).
- `npm run check:scripts` → PASS (no cubre `scripts/n8n/`, que corre con `node --test`).
- **Codex (LEVEL 2, una pasada): CHANGES_REQUESTED.** Encargo y respuesta en `docs/encargos/2026-10-21-codex-n8n-formulario3-fase8*.md`.
  - **P2 aceptado y corregido:** la lectura real trae la fila a medio escribir sin las demás claves y una lectura hecha solo de ellas frenaba con «Faltan columnas» antes de aplicar la regla nueva (el fixture de la primera versión traía todas las claves vacías y no lo veía). Ahora la cabecera se valida sobre las filas que no están en escritura; prueba con la forma real y mutante nuevo.
  - **P3 aceptado como documentación:** el aviso a las 48 h supone una fecha estable; el escritor no la renueva (es la fecha del lead). No se registra la primera observación: pediría otro estado de recibo y cambiar el filtro de «Omitir filas confirmadas».
  - **Riesgo anotado:** una tanda con un lead de más de 48 h con solo la fecha volvería al rechazo prematuro de la fase 7 (medido: 22,5 h como máximo en 24 tandas). Lo demás que Codex comprobó —`Date.parse` del ISO con `-05:00`, nombres disponibles en el nodo, `$("Control del envío")` como en «Resumen de importación», sin bypass de transición ni gate— sin hallazgos.
- **NOT RUN:** banco en n8n. La fase 7 lo usó para probar nodos y conexiones nuevos; aquí solo cambia código JS que las pruebas ejecutan igual que n8n. La comprobación real es la primera vuelta tras publicar, programada y manual (Codex lo pide en NEXT ACTIONS).

## Publicación (hecha el 21/10, 13:54–14:35 Lima)

1. **13:54** Sin vuelta en curso (última lectura 13:50:11, 279 filas), despublicado el importador `BjI5m1PKVWhO0NDb`.
2. `operacionesFase8` aceptó la fase 7 exacta (`b6c88f1b`) sobre la definición viva: una sola operación `updateNodeParameters` sobre «Preparar leads». **Por el MCP el texto no entra byte a byte:** el envío convirtió `\u0300-\u036f` de `normalizarRespuesta` en los caracteres (versión `157f04c1`, 11 650 caracteres contra 11 660: equivalente, no idéntica) y el reenvío con doble barra dejó dos barras (versión `141bbe6e`, 11 662). El truco de la fase 7 («escribir `\u0300`») ya no sirve: el transporte convierte el escape suelto y respeta el doblado. `verificarFase8` rechazó las dos.
3. **14:17** Para cerrar el hueco, republicada la fase 7 con `publish_workflow` y `versionId b6c88f1b` (23 min sin vueltas; la hoja no cambió, nada que importar).
4. **14:30** El texto exacto entró por el editor del nodo: `codigosFase8().preparar8` a un archivo, `pbcopy`, Miguel pegó en «Preparar leads» (Cmd+A, Cmd+V) y guardó sin publicar → versión autoguardada `92181803`. Leída con `get_workflow_version` (el clasificador de Claude Code bloquea `get_workflow_details`; los ajustes son los leídos al inicio de la sesión, que el cambio no toca): `jsCode` idéntico al repo (11 660) y `verificarFase8(borrador)` PASS.
5. **14:32** Publicada `92181803`; `verificarFase8(..., { publicado: true })` PASS.
6. **Primera vuelta real (14:35):** latido `leido_en` 14:35:11 Lima con `filas_leidas` 279; 0 ejecuciones con error desde la publicación; la tabla de recibos sigue en 285 filas (la hoja no cambió: nada que importar y nada que omitir). La vuelta de las 14:30, ya con la fase 7 republicada, también leyó 279 filas sin error.

**Volver atrás:** `publish_workflow` con `versionId b6c88f1b` (no toca el borrador) y pasar `verificarFase7(..., { publicado: true })`. Los leads y los recibos no se tocan.

**Cambios futuros del importador:** se parte de `cargarDefinicionOperativaF8()` y se verifican con `verificarFase8`; la fase 7 queda como base histórica. El código de un nodo se pega en su editor desde el archivo generado por el repo y se lee de vuelta por `get_workflow_version`; el MCP queda para despublicar, publicar y leer historial y tablas.

## Hallazgo aparte, sin tocar en esta fase

El 20/10 a las 16:10, 16:15 y 16:20 Lima hubo tres ejecuciones con error `connect ETIMEDOUT 172.217.112.4:443` en «Leer leads filtrados» (la API de Google Sheets no respondió; el propio error sugiere `Retry on Fail`). El nodo no tiene reintento. Activarlo cambia los ajustes del nodo y pide actualizar `nodoComparable`/los gates de fase 6: decisión aparte, con su propio plan.
