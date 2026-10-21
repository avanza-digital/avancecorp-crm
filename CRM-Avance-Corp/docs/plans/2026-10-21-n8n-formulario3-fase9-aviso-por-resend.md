# Formulario 3 — fase 9 (plan): el aviso sale por Resend, no por Gmail

21/10/2026. Estado: **PLAN revisado por Codex, sin código.** Decisión de Miguel del 21/10 («opción B») tras descartar el reintento en «Leer leads filtrados» (opción A: cada intento contra Google tardó ~133 s en rendirse y la vuelta tiene 180 s; no cabe) y el no hacer nada (opción C). Codex (LEVEL 2, una pasada sobre el plan) devolvió CHANGES_REQUESTED; sus hallazgos están incorporados abajo y la decisión sobre cada uno, al final. Falta la aprobación de Miguel; el código entra en otro PR, con su propia pasada de Codex.

## Por qué

El 20/10, de 16:10 a 16:25 Lima, el VPS de n8n no llegó a Google. «Leer leads filtrados» falló tres veces con `connect ETIMEDOUT` (ejecuciones 1683, 1685 y 1687, ~136 s cada una) y el flujo de avisos se disparó las tres veces (1684, 1686 y 1688) **y las tres se cancelaron a los 120 s**: el nodo Gmail tampoco llegaba a Google. La tabla «avisos enviados» no tiene ninguna fila de ese día. Nadie se enteró hasta el día siguiente; el resumen diario de las 19:00 habría avisado por latido viejo solo si el corte coincidía con esa hora, y también por Gmail.

La causa común: el importador y su aviso dependen del mismo proveedor. La fase 9 saca el aviso de Google: lo envía **Resend** por su API HTTP (`api.resend.com`) con una clave de solo envío. La auditoría del 15/10 ya lo recomendaba (punto 3, permisos de las credenciales).

**Lo que no arregla:** si es Google Workspace lo que cae del todo, el buzón de destino tampoco recibe (`miavance.com` tiene su MX en Google). El 20/10 no fue eso: fue el camino VPS → Google. Resend entrega desde su propia red (región sa-east-1).

## Hechos comprobados el 21/10

- **Resend:** dominio `miavance.com` **verificado**, envío habilitado, región sa-east-1. Ya lo usan el portal y las edges del CRM con el remitente `Avance Corp <info@miavance.com>`. Claves existentes: «Supabase Integration», «portal-avance-corp» y «Onboarding»; ninguna para n8n. La API acepta `from` con nombre visible (`Nombre <correo>`), `to` como texto o lista y `text` como cuerpo plano.
- **Cuota del plan actual:** 100 correos al día y 3 000 al mes, compartidos con el portal y el CRM. Hoy: 48/100 y 897/3 000. Un fallo persistente del importador gasta a lo sumo 24 avisos al día (uno por hora), más uno si falla el resumen.
- **n8n:** no hay nodo nativo de Resend instalado. Existe el nodo comunitario verificado `n8n-nodes-resend` (no instalado). Se usa el nodo **HTTP Request 4.5**, el mismo que «Importar en CRM»: sin dependencia nueva en el VPS y con cada parámetro fijado por el gate.
- **Versión publicada frente a borrador (documentación de n8n, «Save and publish workflows»):** «Production executions will use this published version, not your latest edits» y «Production executions always point to the currently published version». La prueba manual desde el editor corre el borrador (`execute_workflow` del MCP: `manual` prueba la versión actual, `production` ejecuta la publicada). Un flujo de avisos se dispara como ejecución de producción (modo `error`), no manual. Es documentación, no una prueba en esta instancia: por eso el paso 0 de la publicación lo comprueba en un banco antes de tocar el flujo real (Codex, P1-b).
- **Flujo de avisos `4jfthNhVJLiZUeIo`:** una sola versión en el historial, `505bcd5e-ace3-47c7-a2ac-a0f5939c406a`, publicada el 15/10 (fase 7), con el mismo contenido que `cargarAvisos()` del repo. Cadena: Error de importación → Preparar aviso (Code) → Limitar avisos a uno por hora (Data Table `rowNotExists` por `clave`) → **Enviar aviso a Miguel (Gmail 2.2, credencial `FNfEzbpTEsdutlzd`)** → Registrar aviso enviado (upsert en la misma tabla). Rama de prueba manual: Probar aviso por correo → Preparar prueba de aviso → Preparar aviso. Ajustes vivos, leídos hoy con `get_workflow_details` (`detailLevel: 'execution'`, que el clasificador sí dejó pasar y que devuelve `settings`, `active`, `versionId` y `activeVersionId`): `executionOrder v1`, `timezone America/Lima`, `executionTimeout 120`, `saveDataSuccessExecution none`, `saveDataErrorExecution all`, `saveManualExecutions true`, más `availableInMCP true`, que pone la instancia y el repo no fija.
- **El resumen diario `Chn5g93IgxNlkF3K` apunta a este flujo de avisos** (`errorWorkflow: 4jfthNhVJLiZUeIo` en sus ajustes vivos, leídos hoy); el importador también.
- **`update_workflow` del MCP** no tiene operación para cambiar el tipo de un nodo: hay `removeNode`, `addNode`, `addConnection`, `setNodeSettings` y `setNodeGroups`. `addNode` lleva `parameters`, `credentials`, `position` y `disabled`, pero **no** los ajustes de reintento ni `onError`: esos van en `setNodeSettings` aparte (Codex). Las operaciones de grupos no son atómicas: si una se salta, la respuesta lo dice en `skippedOperations` o `removedGroups`. Ninguna operación de esta fase toca el nodo Code, así que el problema del escape `\u` de la fase 8 no aplica.
- **Resend acepta la cabecera `Idempotency-Key`** (hasta 256 caracteres, se recuerda 24 h): mismo cuerpo → devuelve la respuesta original sin reenviar; cuerpo distinto → 409. Un 2xx significa que Resend aceptó el correo, no que lo entregó: la entrega se mira en Resend (`list-emails` / `get-email`, estado `delivered`).

## Qué cambia

Un solo nodo. «Enviar aviso a Miguel» pasa de Gmail a HTTP Request contra Resend, con el mismo nombre y el mismo sitio en la cadena. El asunto y el texto los sigue armando «Preparar aviso», que no se toca. El límite de uno por hora, el recibo solo tras envío confirmado, el Error Trigger y la rama de prueba quedan igual.

Nodo nuevo (canon, en `definirAvisos()` de `scripts/n8n/formulario3.alertas.mjs`). Toda expresión lleva el prefijo `=` literal:

| Campo | Valor |
|---|---|
| type · typeVersion | `n8n-nodes-base.httpRequest` · 4.5 |
| method · url | POST · `https://api.resend.com/emails` |
| authentication | `genericCredentialType` · `httpBearerAuth` · credencial «Resend — avisos Formulario 3» (id fijado en el gate cuando exista) |
| headers | `Idempotency-Key` = `={{ 'aviso-formulario3/' + $json.clave }}` |
| body (json, por campos) | `from` = `Avance Corp — Automatizaciones <info@miavance.com>` · `to` = `miguel@miavance.com` (`DESTINATARIO`) · `subject` = `={{ $json.asunto }}` · `text` = `={{ $json.mensaje }}` |
| options.timeout | 20 000 ms; sin `options.response` (ni `neverError`): cualquier respuesta que no sea 2xx hace fallar el nodo |
| retryOnFail · maxTries · waitBetweenTries | true · 3 · 5 000 (70 s nominales de intentos y esperas, dentro de los 120 s del flujo) |
| onError · continueOnFail | sin definir ninguno (el flujo se detiene): si Resend no confirma, no hay recibo, y **el siguiente error de la misma hora vuelve a intentar** (el `rowNotExists` solo frena cuando hay recibo) |

Por qué cada pieza:

- **Bearer Auth, no la clave en parámetros.** La clave vive solo en la credencial de n8n; al repo va el id de la credencial, como con el importador (`YNRHr2PjhfLXnKff`) y Sheets (`vPzsYCzKnotpycYi`). Ni el acta ni el encargo llevan volcados sin sanear de peticiones o errores.
- **Idempotency-Key = la clave horaria.** Con tres intentos dentro de una misma ejecución, Resend entrega una sola vez. Entre ejecuciones de la misma hora, el Data Table frena cuando ya hay recibo; si dos ejecuciones consultan antes de que ninguna escriba el recibo (hoy prácticamente imposible: el aviso corre uno o dos segundos y el importador arranca cada cinco minutos), quien deduplica es Resend: la segunda recibe la respuesta original si el cuerpo es igual, o un 409 si el `Ejecución: N` del texto cambia → el nodo falla → sin recibo. Resultado en todos los casos: un correo por hora. Hoy, con Gmail, esa carrera sí mandaría dos.
- **Remitente `info@miavance.com`.** Es el que ya envía por Resend desde mayo (reputación hecha); el nombre visible es el de hoy. Si Miguel prefiere otro buzón del dominio (`avisos@`, por ejemplo), es una constante. **Ojo:** cambia la dirección respecto a Gmail; un filtro de Gmail por remitente habría que ajustarlo.
- **HTTP Request y no el nodo comunitario.** Cero dependencias nuevas en el VPS; el gate compara cada parámetro.

Fuera de alcance, a propósito:

- **El resumen diario** (`Chn5g93IgxNlkF3K`) sigue por Gmail. Si Gmail falla a las 19:00, el resumen falla y su error dispara este aviso (su `errorWorkflow` apunta aquí, comprobado en vivo), que ya saldrá por Resend: el hueco queda cubierto. Pasarlo a Resend es otra fase si se quiere un solo canal.
- **La credencial Gmail** (`FNfEzbpTEsdutlzd`) se queda: la usa el resumen.
- **El importador** no se toca. Ni Retry on Fail en «Leer leads filtrados» (descartado arriba) ni nada más.

## Código

1. `scripts/n8n/formulario3.alertas.mjs`: `definirAvisos()` con el nodo nuevo; constantes `URL_RESEND`, `REMITENTE_AVISOS` y `CREDENCIAL_RESEND`. `cargarAvisos()` sigue siendo el canon del flujo de avisos. `formulario3.fase3.alertas.mjs` (la copia aislada de la fase 3) deriva de `definirAvisos()` y sigue generando; es la plantilla del banco del paso 0.
2. `scripts/n8n/formulario3.fase9.mjs`:
   - `VERSION_AVISOS_FASE7 = '505bcd5e-ace3-47c7-a2ac-a0f5939c406a'` y `NODO_GMAIL_FASE7`, el nodo exacto que se retira, congelado.
   - `operacionesFase9(actual)`: exige `id === WORKFLOW_AVISOS`, `versionId === VERSION_AVISOS_FASE7`, `activeVersionId === VERSION_AVISOS_FASE7` (el borrador es la versión publicada: nadie lo editó por fuera), nodos, conexiones, grupos y ajustes iguales al canon de fase 7 (el de hoy, con el nodo Gmail congelado) y la fase sin aplicar. Devuelve **seis** operaciones, en orden: `removeNode` «Enviar aviso a Miguel» → `addNode` (el nuevo, mismo nombre, con credencial y posición) → `setNodeSettings` (retryOnFail, maxTries, waitBetweenTries) → `addConnection` Limitar → Enviar → `addConnection` Enviar → Registrar → `setNodeGroups` (`GRUPOS_AVISOS`, porque quitar el nodo invalida el grupo «Aviso por correo»).
   - `verificarFase9(actual, { versionEsperada, publicado })`: todo obligatorio, sin «cuando la lectura lo trae»:
     - `actual.id === WORKFLOW_AVISOS` y `actual.versionId === versionEsperada` (la versión que devolvió `update_workflow`, o la más reciente del historial leída justo después);
     - con `publicado`, `active === true` y `activeVersionId === versionEsperada`;
     - cada nodo igual al canon en forma comparable (type, typeVersion, parameters, credentials, disabled, onError, continueOnFail, retryOnFail, maxTries, waitBetweenTries, executeOnce, alwaysOutputData; se ignoran id, position y webhookId) y el mismo conjunto de nodos, ni uno más;
     - conexiones iguales a `CONEXIONES_AVISOS`; `nodeGroups` iguales a `GRUPOS_AVISOS` (nombre, descripción y nodos); sin `pinData`;
     - ningún nodo Gmail ni credencial de Google en el flujo; la credencial Resend con el id fijado; en el nodo de envío, `onError`, `continueOnFail` y `options.response` sin definir;
     - `settings` presentes y con los seis ajustes canónicos exactos (`executionOrder`, `timezone`, `executionTimeout`, `saveDataSuccessExecution`, `saveDataErrorExecution`, `saveManualExecutions`); la única clave extra admitida es `availableInMCP`. Si la lectura no trae `settings`, FAIL.
   - El estado vivo que reciben las dos funciones se arma con dos lecturas del mismo momento: `get_workflow_details` (`detailLevel: 'execution'`: id, active, versionId, activeVersionId, settings) y `get_workflow_version` (nodes, connections, nodeGroups). Nunca con una lectura de otra sesión ni completando con el canon.
3. Pruebas (`formulario3.fase9.test.mjs`, y `formulario3.alertas.test.mjs` puesto al día):
   - El canon: POST a la URL de Resend, Bearer con el id fijado, los cuatro campos del cuerpo (`to` igual a `DESTINATARIO`, `subject` y `text` leyendo `$json.asunto` y `$json.mensaje` sin transformar), la cabecera de idempotencia desde `$json.clave`, 3 × 5 000, timeout 20 000, sin `options.response`, `onError` y `continueOnFail` sin definir, prefijo `=` en cada expresión.
   - Evaluar las expresiones del nodo con una salida real de `prepararAlerta` y comprobar que el `text` enviado es el mensaje byte a byte (saltos de línea incluidos) y que no contiene el error crudo del servidor. Esto prueba el resultado de la expresión, no el transporte de n8n: eso lo prueba el envío real del paso 0.
   - Ningún nodo de `cargarAvisos()` es Gmail ni lleva credencial de Google.
   - `operacionesFase9` sobre la definición exacta de fase 7 (fixture congelado, transcrito de la versión viva `505bcd5e` y de sus ajustes vivos) devuelve las seis operaciones; aplicadas en un simulador (quitar nodo y sus conexiones, añadir, ajustar, conectar, grupos) dan un flujo que pasa `verificarFase9` y coincide con `cargarAvisos()`.
   - Rechazos de la transición: otro flujo; versión distinta de `505bcd5e`; borrador distinto de la versión publicada; nodo Gmail con cualquier deriva (destinatario, credencial); ajustes distintos; fase ya aplicada.
   - Rechazos del gate: otro `id`; `versionId` distinta de la esperada; el nodo Gmail sigue; un nodo de más; otro remitente; otro destinatario; otra credencial; `onError` o `continueOnFail` definidos; `options.response` presente; sin reintento; falta la conexión a «Registrar aviso enviado»; grupo ausente en la **respuesta viva simulada**; `pinData` presente; `settings` ausentes; `executionTimeout` distinto; una clave de ajustes desconocida; `publicado` con `activeVersionId` distinto.
   - Las pruebas existentes de avisos siguen pasando (la que dice «después de Gmail» pasa a decir «después del envío»; `sendTo` pasa a ser el campo `to`).
4. Mutantes: unos doce sobre el gate y la transición (quitar la comprobación de credencial, dejar pasar un nodo extra, ignorar `onError`, aceptar otro destinatario, aceptar otra versión, aceptar ajustes ausentes, ignorar los grupos, saltarse el `setNodeSettings`…), todos muertos antes del PR.
5. Acta `docs/N8N-FORMULARIO3-FASE9.md` ligada al commit verificado en `avancecorp/main`, a la `versionId` publicada y a la evidencia de entrega (id de ejecución, id del correo en Resend, estado `delivered`); nota del vault; y en la nota de auditoría del 15/10 marcar el punto 3 como atendido para el aviso (el resumen sigue en Gmail).

## Pasos de Miguel, antes del código

1. Resend → API Keys → crear `n8n-avisos-formulario3`, permiso **Sending access**, dominio **miavance.com**. Copiar la clave (se ve una sola vez).
2. n8n → Credentials → **Bearer Auth** → nombre «Resend — avisos Formulario 3» → pegar la clave → guardar. La clave no pasa por el repo ni por el chat.
3. Avisar: leo el id con `list_credentials` (el MCP nunca devuelve el secreto) y lo fijo en el código.
4. Confirmar el remitente (`info@miavance.com` por defecto) o decir otro buzón del dominio.
5. **Durante la publicación, el editor de n8n cerrado** (los dos flujos). El editor autoguarda borradores con cualquier clic: hoy el importador tiene cuatro autoguardados de las 16:11 Lima, posteriores a la publicación de la fase 8 (el diff contra la versión publicada `92181803` no muestra ningún nodo ni conexión cambiados: son cosméticos, pero convierten el borrador en una versión distinta de la publicada).

## Publicación (tras fusionar el PR de código; la autoriza Miguel)

**Sin despublicar.** La versión publicada sigue atendiendo errores mientras se edita el borrador (documentación de n8n, arriba), así que no hay ventana sin aviso (en la fase 8 fueron 23 minutos por el escape `\u`; aquí no se toca código). Como esa garantía es documental, el paso 0 la comprueba en esta instancia antes de tocar el flujo real.

0. **Banco mínimo, aislado, como en las fases 3 y 7** (Codex, P1-b; también cierra el NOT RUN del Error Trigger real):
   - Productor P: Schedule Trigger cada minuto → Code que lanza un error. Publicado, con `errorWorkflow` = C.
   - Copia C del flujo de avisos generada desde `definirAvisos()` como hace `formulario3.fase3.alertas.mjs`: el id del importador sustituido por el de P (si no, `prepararAlerta` descarta el evento), tabla de pruebas A en vez de la de producción, asunto `[PRUEBA F9]`, **nodo Resend real** con la credencial nueva y `DESTINATARIO`. Publicada.
   - Primera ejecución de P (producción): C publicada envía por Resend desde un Error Trigger real → correo `[PRUEBA F9]` con id en Resend, fila en la tabla A.
   - Editar el **borrador** de C sin publicar: la tabla A pasa a una tabla B (y nada más). Siguiente ejecución de P: si la fila cae en A y no en B, el manejador corre la versión publicada, no el borrador. Si cae en B, la hipótesis de Codex era cierta y el flujo real se publica **despublicando antes**, como en la fase 8, aceptando una ventana corta sin aviso.
   - Despublicar P en cuanto hay resultado (dos o tres ejecuciones), archivar P y C. Las tablas de prueba quedan con filas ficticias (el MCP no borra tablas), como las de la fase 7. Los correos del banco cuentan en la cuota del día (dos o tres).
1. Leer el flujo vivo en el mismo momento (`get_workflow_details` `execution` + `get_workflow_version`) y pasar `operacionesFase9`.
2. `update_workflow` con las seis operaciones, versión «Fase 9: aviso por Resend». Guardar la `versionId` que devuelve (o leer la más reciente del historial acto seguido) como `versionEsperada`; revisar en la respuesta `skippedOperations` y `removedGroups`.
3. Releer (detalles + versión `versionEsperada`) → `verificarFase9(…, { versionEsperada })` PASS.
4. Miguel ejecuta en el editor «Probar aviso por correo» (el editor corre el borrador; el editor debe mostrar la versión `versionEsperada`): llega `[PRUEBA] Avance Corp — Revisar importación Formulario 3` desde Resend. Evidencia atribuible, no solo un verde: id de la ejecución en n8n, id del correo que devuelve el nodo, `get-email` en Resend con estado `delivered` al destinatario, cabecera `From` con el nombre y el guion largo bien codificados. Deja una fila `…|prueba|…` en la tabla, como en la fase 7: **una prueba por hora**; para repetir dentro de la misma hora hay que borrar esa fila en la tabla desde la interfaz de n8n.
5. `publish_workflow` con `versionEsperada` → releer → `verificarFase9(…, { versionEsperada, publicado: true })` PASS.
6. Vuelta atrás: `publish_workflow` con la versión `505bcd5e…` devuelve Gmail en segundos; releer y comprobar que `activeVersionId` es `505bcd5e…`.
7. Ejecuciones en curso al publicar o al volver atrás: un aviso dura uno o dos segundos; si justo entonces había una ejecución Gmail pasada del filtro, podría llegar un correo duplicado. Se acepta (a lo sumo un correo de más, una vez); no hay ventana sin atención.

## Riesgos

- **Cuota compartida.** Un fallo persistente añade hasta 25 correos al día a los del portal y el CRM; hoy sobran 52. Si la cuenta se acerca al tope, los avisos compiten con los correos a clientes. Queda anotado en el acta; si el uso crece, plan Pro o cuenta aparte.
- **Caída global de Google Workspace.** El buzón no recibe por ningún proveedor. Queda la ejecución con error en n8n y el resumen del día siguiente.
- **Clave revocada o restringida.** El nodo devuelve 401/403, la ejecución del aviso queda con error y sin recibo; se ve en n8n. No hay «aviso del aviso», igual que hoy con Gmail. Lo mismo con un 429 o un 5xx de Resend: tres intentos y, si no, error sin recibo.
- **Aceptado no es entregado.** El 2xx de Resend es aceptación; un rebote posterior se ve en Resend, no en n8n. Para un aviso interno al propio dominio es asumible.
- **Guion largo en el nombre del remitente.** Lo codifica Resend; lo confirma el paso 0. Si saliera mal, se pasa a guion corto (una constante).

## Revisión de Codex (21/10, LEVEL 2, sobre el plan)

Encargo y respuesta en `docs/encargos/2026-10-21-codex-n8n-formulario3-fase9-plan*.md`. Jev (`agrupar-hallazgos`) no encontró repetidos entre los diez puntos.

| Hallazgo | Decisión |
|---|---|
| P1 · el gate admitía ajustes ausentes | **Aceptado.** `settings` obligatorios y exactos; la lectura sale de `get_workflow_details` (`execution`), que hoy sí respondió con ajustes y estado de publicación. Sin ajustes, FAIL. |
| P1 · continuidad del Error Trigger no acreditada | **Aceptado.** Se cita la documentación de n8n y se comprueba en el banco del paso 0 antes de tocar el flujo real; si el banco contradice la documentación, se despublica antes de editar. |
| P2 · identidad de lo inspeccionado | **Aceptado.** `verificarFase9` exige `id` y `versionEsperada`; se publica esa misma versión; la prueba manual se correlaciona con la ejecución y el id del correo en Resend; editor cerrado durante la ventana. |
| P2 · carreras y duplicado al cambiar de proveedor | **Aceptado en parte.** La frase corregida («el siguiente error de la misma hora vuelve a intentar»). La carrera entre dos ejecuciones la resuelve Resend mejor que hoy (idempotencia); el duplicado durante la publicación o la vuelta atrás es a lo sumo un correo, una vez, y se acepta documentado. No se añade un mecanismo de exclusión: no hay cómo probarlo por unidad y el coste supera al riesgo. |
| P3 · grupos perdidos sin que falle el gate | **Aceptado.** El gate compara `nodeGroups`; mutante sobre la respuesta viva simulada; se revisan `skippedOperations` y `removedGroups`. |
| `addNode` sin ajustes de reintento | **Aceptado.** Sexta operación `setNodeSettings`. |
| `pinData` y `continueOnFail` | **Aceptado.** Entran en la forma comparable; el gate exige ausencia. |
| Prefijo `=` en todas las expresiones | **Aceptado.** Explícito en el canon y en la prueba. |
| Casos 401/403/429/5xx/409 sin recibo | **Aceptado en lo que se puede probar.** El gate fija `options.response` ausente y `onError`/`continueOnFail` sin definir, que es lo que hace que un no-2xx detenga el flujo sin recibo; la respuesta real de n8n ante esos códigos no se prueba por unidad y queda como riesgo documentado. |
| Prueba manual repetida en la misma hora | **Aceptado.** Una por hora; evidencia atribuible por ids. |
| `errorWorkflow` del resumen y trazabilidad del acta | **Aceptado.** Comprobado en vivo hoy; el acta liga commit, versión y entrega; la vuelta atrás verifica la versión activa. |
