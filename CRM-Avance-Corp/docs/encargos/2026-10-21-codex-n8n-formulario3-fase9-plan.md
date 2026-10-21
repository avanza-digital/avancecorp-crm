ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión LEVEL 2 — n8n «Avance Corp — Avisos de Formulario 3», fase 9, PLAN: el aviso sale por Resend, no por Gmail (21/10/2026)

Eres el revisor secundario (solo análisis, sin herramientas, sin base ni red). Todo lo que necesitas está transcrito abajo.
Es un PLAN: todavía no hay código. Tu trabajo es REFUTARLO antes de que se escriba: busca cómo el aviso deja de llegar (hoy
llega por Gmail), cómo la transición deja el flujo a medias o sin aviso, cómo el gate acepta un flujo distinto del revisado,
cómo se filtra la clave de Resend, qué supuesto sobre n8n o sobre Resend es falso y qué prueba falta. Sin hallazgo sin
evidencia (cita la sección del plan, o archivo y línea o fragmento). Distingue hipótesis de hechos. Responde en español con:
VERDICT (APPROVE / APPROVE_WITH_NOTES / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 (cada uno con evidencia y propuesta),
RIESGOS / TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Preguntas concretas que el PRIMARY quiere refutadas

1. Editar el borrador del flujo de avisos SIN despublicar: ¿hay algún caso en que la versión publicada deje de atender
   errores mientras el borrador cambia, o en que la prueba manual desde el editor corra la versión publicada en vez del
   borrador?
2. `removeNode` + `addNode` con el mismo nombre + dos `addConnection` + `setNodeGroups`: ¿qué puede quedar mal (orden,
   conexiones huérfanas, grupo, posición, `onError`)? ¿Hay un camino mejor con las operaciones disponibles?
3. `Idempotency-Key` igual a la clave horaria, con un cuerpo que incluye `Ejecución: N`: ¿algún caso en que un aviso
   legítimo se pierda o se duplique? Interacción con «Limitar avisos a uno por hora» (`rowNotExists`), con `retryOnFail`
   3 × 5 000 ms y con el timeout de 20 000 ms frente a los 120 s del flujo.
4. Cuerpo por campos (`from`, `to`, `subject`, `text` con expresiones `={{ $json.x }}`): ¿pierde saltos de línea, codifica
   mal el guion largo o la «ñ», o convierte `to` en algo que Resend rechace?
5. El gate: ¿qué deriva real del flujo vivo NO detectaría la forma comparable descrita? ¿Qué debe exigir de `settings` si la
   lectura por `get_workflow_version` no los trae?
6. Alcance: ¿es un error dejar el resumen diario en Gmail y la credencial Gmail viva? ¿Falta algo en los pasos de Miguel o
   en la publicación?
7. Prueba real: ¿basta la rama manual «Probar aviso por correo» o hace falta provocar un Error Trigger real o montar un banco?

## Hechos verificados por el PRIMARY el 21/10 (no son hipótesis)

- Flujo de avisos vivo `4jfthNhVJLiZUeIo`: el historial tiene UNA versión, `505bcd5e-ace3-47c7-a2ac-a0f5939c406a` (15/10,
  «Fase 7»), publicada. Sus nodos, conexiones y grupo coinciden con `definirAvisos()`, `CONEXIONES_AVISOS` y `GRUPOS_AVISOS`
  del repo (transcritos abajo); el nodo Gmail vivo lleva además un `webhookId` y cada nodo su `id`, que el repo no fija.
  `get_workflow_version` devuelve nodes, connections y nodeGroups; NO devuelve settings ni active/activeVersionId (eso lo da
  `get_workflow_details`, que el clasificador de permisos de la sesión bloquea; en la fase 8 se usó una lectura hecha al
  inicio de la sesión).
- 20/10 (UTC 21:10, 21:15 y 21:20): tres ejecuciones del importador con `connect ETIMEDOUT` en «Leer leads filtrados»,
  ~136 s cada una (dos intentos de conexión de ~65 s). Sus avisos 1684, 1686 y 1688 quedaron `canceled` a los 120 s
  (executionTimeout del flujo de avisos). La tabla «avisos enviados» no tiene ninguna fila de ese día.
- Resend: dominio miavance.com verificado (sa-east-1, envío habilitado). Uso hoy: 48/100 diarios y 897/3 000 mensuales,
  compartidos con el portal y las edges del CRM (remitente actual de esas edges: `Avance Corp <info@miavance.com>`). Límite
  de 10 peticiones por segundo. Cabecera `Idempotency-Key`: hasta 256 caracteres, se recuerda 24 h; mismo cuerpo → misma
  respuesta sin reenviar; cuerpo distinto → 409. MX de miavance.com → SMTP.GOOGLE.com (el buzón de destino es Google).
- n8n: instancia self-hosted. HTTP Request disponible en typeVersion 4.5; así lo usa «Importar en CRM»
  (`authentication:'genericCredentialType'`, `genericAuthType:'httpTemplatedCustomAuth'`, `onError:'continueErrorOutput'`,
  `retryOnFail:true`, `maxTries:3`, `waitBetweenTries:1000`). Parámetros relevantes del nodo 4.5: `method`, `url`,
  `authentication` ('none' | 'predefinedCredentialType' | 'genericCredentialType'), `genericAuthType` (incluye
  'httpBearerAuth' y 'httpHeaderAuth'), `sendHeaders` + `specifyHeaders:'keypair'` + `headerParameters.parameters[{name,value}]`,
  `sendBody` + `contentType:'json'` + `specifyBody:'keypair'` + `bodyParameters.parameters[{name,value}]`, `options.timeout`
  en ms. El nodo falla si el status no es 2xx salvo `options.response.response.neverError`. La credencial va en
  `credentials.httpBearerAuth:{id,name}`. No hay nodo nativo de Resend instalado; existe el comunitario verificado
  `n8n-nodes-resend` (no instalado).
- `update_workflow` del MCP: operaciones atómicas (si una falla no se guarda nada), salvo las de grupos, que se saltan y se
  reportan; un grupo que otras operaciones dejan inválido se elimina y se reporta. Tipos: updateNodeParameters,
  setNodeParameter, addNode, removeNode, renameNode, addConnection, removeConnection, setNodeCredential, setNodePosition,
  setNodeDisabled, setNodeSettings (retryOnFail, maxTries 2–5, waitBetweenTries 0–5 000, onError, executeOnce,
  alwaysOutputData), setWorkflowSettings, setNodeGroups, addNodeGroup, removeNodeGroup, updateNodeGroup. No existe «cambiar
  el tipo de un nodo». `publish_workflow` acepta `versionId` y sirve de vuelta atrás sin tocar el borrador. En la fase 8 el
  transporte del MCP corrompió los escapes `\u` del código JS de un nodo Code; aquí no se envía código.
- Repo: `node --test 'scripts/n8n/*.test.mjs'` → 63/63 PASS en avancecorp/main (15e43d98). Patrón de fases:
  `operacionesFaseN` (transición desde la versión exacta anterior) + `verificarFaseN` (gate) + test + acta.

## El plan (docs/plans/2026-10-21-n8n-formulario3-fase9-aviso-por-resend.md)

# Formulario 3 — fase 9 (plan): el aviso sale por Resend, no por Gmail

21/10/2026. Estado: **PLAN, sin código.** Lo refuta Codex (LEVEL 2: una pasada sobre el plan, otra sobre el código), lo aprueba Miguel y el código entra en otro PR. Decisión de Miguel del 21/10 («opción B») tras descartar el reintento en «Leer leads filtrados» (opción A: cada intento contra Google tardó ~133 s en rendirse y la vuelta tiene 180 s; no cabe) y el no hacer nada (opción C).

## Por qué

El 20/10, de 16:10 a 16:25 Lima, el VPS de n8n no llegó a Google. «Leer leads filtrados» falló tres veces con `connect ETIMEDOUT` (ejecuciones 1683, 1685 y 1687, ~136 s cada una) y el flujo de avisos se disparó las tres veces (1684, 1686 y 1688) **y las tres se cancelaron a los 120 s**: el nodo Gmail tampoco llegaba a Google. La tabla «avisos enviados» no tiene ninguna fila de ese día. Nadie se enteró hasta el día siguiente; el resumen diario de las 19:00 habría avisado por latido viejo solo si el corte coincidía con esa hora, y también por Gmail.

La causa común: el importador y su aviso dependen del mismo proveedor. La fase 9 saca el aviso de Google: lo envía **Resend** por su API HTTP (`api.resend.com`) con una clave de solo envío. La auditoría del 15/10 ya lo recomendaba (punto 3, permisos de las credenciales).

**Lo que no arregla:** si es Google Workspace lo que cae del todo, el buzón de destino tampoco recibe (`miavance.com` tiene su MX en Google). El 20/10 no fue eso: fue el camino VPS → Google. Resend entrega desde su propia red (región sa-east-1).

## Hechos comprobados el 21/10

- **Resend:** dominio `miavance.com` **verificado**, envío habilitado, región sa-east-1. Ya lo usan el portal y las edges del CRM con el remitente `Avance Corp <info@miavance.com>`. Claves existentes: «Supabase Integration», «portal-avance-corp» y «Onboarding»; ninguna para n8n.
- **Cuota del plan actual:** 100 correos al día y 3 000 al mes, compartidos con el portal y el CRM. Hoy: 48/100 y 897/3 000. Un fallo persistente del importador gasta a lo sumo 24 avisos al día (uno por hora), más uno si falla el resumen.
- **n8n:** no hay nodo nativo de Resend instalado. Existe el nodo comunitario verificado `n8n-nodes-resend` (no instalado). Se usa el nodo **HTTP Request 4.5**, el mismo que «Importar en CRM»: sin dependencia nueva en el VPS y con cada parámetro fijado por el gate.
- **Flujo de avisos `4jfthNhVJLiZUeIo`:** una sola versión en el historial, `505bcd5e-ace3-47c7-a2ac-a0f5939c406a`, publicada el 15/10 (fase 7), con el mismo contenido que `cargarAvisos()` del repo. Cadena: Error de importación → Preparar aviso (Code) → Limitar avisos a uno por hora (Data Table `rowNotExists` por `clave`) → **Enviar aviso a Miguel (Gmail 2.2, credencial `FNfEzbpTEsdutlzd`)** → Registrar aviso enviado (upsert en la misma tabla). Rama de prueba manual: Probar aviso por correo → Preparar prueba de aviso → Preparar aviso. Ajustes: `executionTimeout` 120, zona America/Lima, solo se guardan ejecuciones con error.
- **`update_workflow` del MCP** no tiene operación para cambiar el tipo de un nodo: hay `removeNode`, `addNode`, `addConnection` y `setNodeGroups`. Ninguna de las operaciones de esta fase toca el nodo Code, así que el problema del escape `\u` de la fase 8 no aplica.
- **Resend acepta la cabecera `Idempotency-Key`** (hasta 256 caracteres, se recuerda 24 h): mismo cuerpo → devuelve la respuesta original sin reenviar; cuerpo distinto → 409.

## Qué cambia

Un solo nodo. «Enviar aviso a Miguel» pasa de Gmail a HTTP Request contra Resend, con el mismo nombre y el mismo sitio en la cadena. El asunto y el texto los sigue armando «Preparar aviso», que no se toca. El límite de uno por hora, el recibo solo tras envío confirmado, el Error Trigger y la rama de prueba quedan igual.

Nodo nuevo (canon, en `definirAvisos()` de `scripts/n8n/formulario3.alertas.mjs`):

| Campo | Valor |
|---|---|
| type · typeVersion | `n8n-nodes-base.httpRequest` · 4.5 |
| method · url | POST · `https://api.resend.com/emails` |
| authentication | `genericCredentialType` · `httpBearerAuth` · credencial «Resend — avisos Formulario 3» (id fijado en el gate cuando exista) |
| headers | `Idempotency-Key` = `{{ 'aviso-formulario3/' + $json.clave }}` |
| body (json, por campos) | `from` = `Avance Corp — Automatizaciones <info@miavance.com>` · `to` = `miguel@miavance.com` (`DESTINATARIO`) · `subject` = `{{ $json.asunto }}` · `text` = `{{ $json.mensaje }}` |
| options.timeout | 20 000 ms |
| retryOnFail · maxTries · waitBetweenTries | true · 3 · 5 000 (peor caso 70 s, dentro de los 120 s del flujo) |
| onError | sin definir (detiene el flujo): si Resend no confirma, no hay recibo y a la hora siguiente vuelve a intentar |

Por qué cada pieza:

- **Bearer Auth, no la clave en parámetros.** La clave vive solo en la credencial de n8n; al repo va el id de la credencial, como con el importador (`YNRHr2PjhfLXnKff`) y Sheets (`vPzsYCzKnotpycYi`).
- **Idempotency-Key = la clave horaria.** Con tres intentos dentro de una misma ejecución, Resend entrega una sola vez. Entre ejecuciones de la misma hora, el Data Table ya frena antes de llegar al nodo. Caso raro: envío confirmado y recibo no escrito → la siguiente ejecución de esa hora llega a Resend con otro `Ejecución: N` en el texto → 409 → el nodo falla → sin recibo; a la hora siguiente avisa normal. Es el comportamiento buscado (uno por hora), no un fallo.
- **Remitente `info@miavance.com`.** Es el que ya envía por Resend desde mayo (reputación hecha); el nombre visible es el de hoy. Si Miguel prefiere otro buzón del dominio (`avisos@`, por ejemplo), es una constante. **Ojo:** cambia la dirección respecto a Gmail; un filtro de Gmail por remitente habría que ajustarlo.
- **HTTP Request y no el nodo comunitario.** Cero dependencias nuevas en el VPS; el gate compara cada parámetro.

Fuera de alcance, a propósito:

- **El resumen diario** (`Chn5g93IgxNlkF3K`) sigue por Gmail. Si Gmail falla a las 19:00, el resumen falla y su error dispara este aviso, que ya saldrá por Resend: el hueco queda cubierto. Pasarlo a Resend es otra fase si se quiere un solo canal.
- **La credencial Gmail** (`FNfEzbpTEsdutlzd`) se queda: la usa el resumen.
- **El importador** no se toca. Ni Retry on Fail en «Leer leads filtrados» (descartado arriba) ni nada más.

## Código

1. `scripts/n8n/formulario3.alertas.mjs`: `definirAvisos()` con el nodo nuevo; constantes `URL_RESEND`, `REMITENTE_AVISOS` y `CREDENCIAL_RESEND`. `cargarAvisos()` sigue siendo el canon del flujo de avisos. `formulario3.fase3.alertas.mjs` (la copia aislada de la fase 3) deriva de `definirAvisos()` y sigue generando.
2. `scripts/n8n/formulario3.fase9.mjs`:
   - `VERSION_AVISOS_FASE7 = '505bcd5e-ace3-47c7-a2ac-a0f5939c406a'` y `NODO_GMAIL_FASE7`, el nodo exacto que se retira, congelado.
   - `operacionesFase9(actual)`: exige `id === WORKFLOW_AVISOS`, `versionId === VERSION_AVISOS_FASE7`, `activeVersionId === VERSION_AVISOS_FASE7` (el borrador es la versión publicada: nadie lo editó por fuera), nodos, conexiones y grupos iguales al canon de fase 7 (el de hoy, con el nodo Gmail congelado) y la fase sin aplicar. Devuelve cinco operaciones, en orden: `removeNode` «Enviar aviso a Miguel» → `addNode` (el nuevo, mismo nombre) → `addConnection` Limitar → Enviar → `addConnection` Enviar → Registrar → `setNodeGroups` (`GRUPOS_AVISOS`, porque quitar el nodo invalida el grupo «Aviso por correo»).
   - `verificarFase9(actual, { publicado })`: cada nodo del flujo vivo igual al canon en forma comparable (type, typeVersion, parameters, credentials, disabled, onError, retryOnFail, maxTries, waitBetweenTries, executeOnce, alwaysOutputData; se ignoran id, position y webhookId), el mismo conjunto de nodos (ni uno más), conexiones iguales a `CONEXIONES_AVISOS`, ningún nodo Gmail ni credencial de Google en el flujo, la credencial Resend con el id fijado, los ajustes iguales a `cargarAvisos().settings` cuando la lectura los trae, y con `publicado`, `active` y `activeVersionId === versionId`.
3. Pruebas (`formulario3.fase9.test.mjs`, y `formulario3.alertas.test.mjs` puesto al día):
   - El canon: POST a la URL de Resend, Bearer con el id fijado, los cuatro campos del cuerpo (`to` igual a `DESTINATARIO`, `subject` y `text` leyendo `$json.asunto` y `$json.mensaje` sin transformar), la cabecera de idempotencia desde `$json.clave`, 3 × 5 000, timeout 20 000, `onError` sin definir.
   - Evaluar las expresiones del nodo con una salida real de `prepararAlerta` y comprobar que el `text` enviado es el mensaje byte a byte (saltos de línea incluidos) y que no contiene el error crudo del servidor.
   - Ningún nodo de `cargarAvisos()` es Gmail ni lleva credencial de Google.
   - `operacionesFase9` sobre la definición exacta de fase 7 (fixture congelado, transcrito de la versión viva `505bcd5e`) devuelve las cinco operaciones; aplicadas en un simulador (quitar nodo y sus conexiones, añadir, conectar, grupos) dan un flujo que pasa `verificarFase9` y coincide con `cargarAvisos()`.
   - Rechazos de la transición: otro flujo; versión distinta de `505bcd5e`; borrador distinto de la versión publicada; nodo Gmail con cualquier deriva (destinatario, credencial); fase ya aplicada.
   - Rechazos del gate: el nodo Gmail sigue; un nodo de más; otro remitente; otro destinatario; otra credencial; `onError` continúa; sin reintento; falta la conexión a «Registrar aviso enviado»; `publicado` con `activeVersionId` distinto.
   - Las pruebas existentes de avisos siguen pasando (la que dice «después de Gmail» pasa a decir «después del envío»; `sendTo` pasa a ser el campo `to`).
4. Mutantes: unos diez sobre el gate y la transición (quitar la comprobación de credencial, dejar pasar un nodo extra, ignorar `onError`, aceptar otro destinatario, aceptar otra versión, saltarse el `setNodeGroups`…), todos muertos antes del PR.
5. Acta `docs/N8N-FORMULARIO3-FASE9.md`, nota del vault, y en la nota de auditoría del 15/10 marcar el punto 3 como atendido para el aviso (el resumen sigue en Gmail).

## Pasos de Miguel, antes del código

1. Resend → API Keys → crear `n8n-avisos-formulario3`, permiso **Sending access**, dominio **miavance.com**. Copiar la clave (se ve una sola vez).
2. n8n → Credentials → **Bearer Auth** → nombre «Resend — avisos Formulario 3» → pegar la clave → guardar. La clave no pasa por el repo ni por el chat.
3. Avisar: leo el id con `list_credentials` (el MCP nunca devuelve el secreto) y lo fijo en el código.
4. Confirmar el remitente (`info@miavance.com` por defecto) o decir otro buzón del dominio.

## Publicación (tras fusionar el PR de código; la autoriza Miguel)

**Sin despublicar.** La versión publicada es inmutable y sigue atendiendo errores mientras se edita el borrador, así que no hay ventana sin aviso (en la fase 8 fueron 23 minutos por el escape `\u`; aquí no se toca código).

1. Leer el flujo vivo (historial, versión y estado publicado) y pasar `operacionesFase9`.
2. `update_workflow` con las cinco operaciones, versión «Fase 9: aviso por Resend».
3. Leer la versión nueva → `verificarFase9` (borrador) PASS.
4. Miguel ejecuta en el editor «Probar aviso por correo» (el editor corre el borrador): llega `[PRUEBA] Avance Corp — Revisar importación Formulario 3` desde Resend. Se confirma en Resend (`list-emails`, estado delivered) y en la bandeja (cabecera `From` con el nombre y el guion largo bien codificados). Deja una fila `…|prueba|…` en la tabla, como en la fase 7.
5. `publish_workflow` (versión nueva) → `verificarFase9(…, { publicado: true })` PASS.
6. Vuelta atrás: `publish_workflow` con la versión `505bcd5e…` devuelve Gmail en segundos.
7. **NOT RUN:** Error Trigger real. La prueba manual recorre exactamente los mismos nodos desde «Preparar aviso»; el primer aviso real lo confirma. No se monta banco: la fase 7 lo usó para probar nodos nuevos del importador, aquí el importador no cambia.

## Riesgos

- **Cuota compartida.** Un fallo persistente añade hasta 25 correos al día a los del portal y el CRM; hoy sobran 52. Si la cuenta se acerca al tope, los avisos compiten con los correos a clientes. Queda anotado en el acta; si el uso crece, plan Pro o cuenta aparte.
- **Caída global de Google Workspace.** El buzón no recibe por ningún proveedor. Queda la ejecución con error en n8n y el resumen del día siguiente.
- **Clave revocada o restringida.** El nodo devuelve 401/403, la ejecución del aviso queda con error y sin recibo; se ve en n8n. No hay «aviso del aviso», igual que hoy con Gmail.
- **Guion largo en el nombre del remitente.** Lo codifica Resend; lo confirma el paso 4. Si saliera mal, se pasa a guion corto (una constante).

## Evidencia: scripts/n8n/formulario3.alertas.mjs (avancecorp/main, definición canónica del flujo de avisos; coincide con lo vivo)

```js
// Avisos sin datos de leads ni mensajes crudos del servidor.
import { pathToFileURL } from 'node:url'
import { codigoSDK, WORKFLOW_ID, NOMBRE } from './formulario3.workflow.mjs'

export const WORKFLOW_AVISOS = '4jfthNhVJLiZUeIo'
export const TABLA_AVISOS = 'TcpMCmhVw3oT9GjD'
export const DESTINATARIO = 'miguel@miavance.com'
export const NOMBRE_AVISOS = 'Avance Corp — Avisos de Formulario 3'

// Fase 7: también avisa por el resumen diario. Del error solo pasa al correo la
// lista de filas que arma cerrarVuelta (números y etiquetas fijas); cualquier
// otro mensaje queda fuera.
export function prepararAlerta(evento, ahoraMs) {
  const flujos = {
    BjI5m1PKVWhO0NDb: { asunto: 'Avance Corp — Revisar importación Formulario 3', texto: 'La importación de Formulario 3 terminó con un error.' },
    Chn5g93IgxNlkF3K: { asunto: 'Avance Corp — Revisar resumen diario de Formulario 3', texto: 'El resumen diario de Formulario 3 terminó con un error.' },
  }
  const flujo = evento?.workflow?.id
  if (typeof flujo !== 'string' || !Object.hasOwn(flujos, flujo)) return null
  if (!Number.isFinite(ahoraMs) || ahoraMs < 0) throw new Error('Falta la hora del aviso')
  const prueba = evento.prueba === true
  const id = String(evento.execution?.id ?? '')
  const ejecucion = /^\d+$/.test(id) ? id : 'consultar historial'
  const url = 'https://n8n-t27j.srv1906432.hstgr.cloud/workflow/' + flujo
  const crudo = typeof evento.execution?.error?.message === 'string' ? evento.execution.error.message : ''
  const filas = /^((?:Revisar filas de la hoja: \d+ \((?:rechazada|cliente sin registrar)\)(?:, \d+ \((?:rechazada|cliente sin registrar)\))*\.)?(?: ?Pendientes para reintentar: \d+(?:, \d+)*\.)?)(?: \[line \d+(?:, for item \d+)?\])?$/.exec(crudo)
  const detalle = filas && filas[1] ? filas[1] + '\n' : ''
  return {
    clave: flujo + '|' + (prueba ? 'prueba|' : 'error|') + Math.floor(ahoraMs / 3600000),
    workflow: flujo,
    asunto: (prueba ? '[PRUEBA] ' : '') + flujos[flujo].asunto,
    mensaje: prueba
      ? 'Este es un aviso de prueba de Formulario 3. El canal de correo funciona.\n\nFlujo: ' + url
      : flujos[flujo].texto + '\n' + detalle + 'Ejecución: ' + ejecucion + '\n\nRevisa la ejecución en n8n para identificar los pendientes y corregir el problema:\n' + url + '\n\nSe envía como máximo un aviso por hora mientras persistan los errores.',
  }
}

export function definirAvisos() {
  const codigo = prepararAlerta.toString() + '\nreturn $input.all().map((item,i)=>({json:prepararAlerta(item.json,Date.now()),pairedItem:{item:i}})).filter(item=>item.json!==null);'
  const sample = prepararAlerta({ workflow: { id: WORKFLOW_ID }, execution: { id: '24' } }, 1792010000000)
  return [
    { name: 'Error de importación', type: 'n8n-nodes-base.errorTrigger', typeVersion: 1, parameters: {}, position: [0,0], output: [{workflow:{id:WORKFLOW_ID,name:NOMBRE},execution:{id:'24',error:{message:'Error de prueba'}}}] },
    { name: 'Probar aviso por correo', type: 'n8n-nodes-base.manualTrigger', typeVersion: 1, parameters: {}, position: [0,300], output: [{}] },
    { name: 'Preparar prueba de aviso', type: 'n8n-nodes-base.set', typeVersion: 3.5, parameters: { mode:'raw',jsonOutput:JSON.stringify({prueba:true,workflow:{id:WORKFLOW_ID},execution:{id:'0'}}) }, position: [280,300],output:[{prueba:true,workflow:{id:WORKFLOW_ID},execution:{id:'0'}}] },
    { name: 'Preparar aviso', type: 'n8n-nodes-base.code', typeVersion: 2, parameters: {mode:'runOnceForAllItems',language:'javaScript',jsCode:codigo}, position:[580,100],output:[sample] },
    { name: 'Limitar avisos a uno por hora', type:'n8n-nodes-base.dataTable',typeVersion:1.1,parameters:{resource:'row',operation:'rowNotExists',dataTableId:{__rl:true,mode:'list',value:TABLA_AVISOS,cachedResultName:'Formulario 3 — avisos enviados'},matchType:'allConditions',filters:{conditions:[{keyName:'clave',condition:'eq',keyValue:'={{ $json.clave }}'}]}},position:[860,100],output:[sample] },
    { name:'Enviar aviso a Miguel',type:'n8n-nodes-base.gmail',typeVersion:2.2,parameters:{resource:'message',operation:'send',authentication:'oAuth2',sendTo:DESTINATARIO,subject:'={{ $json.asunto }}',emailType:'text',message:'={{ $json.mensaje }}',options:{appendAttribution:false,senderName:'Avance Corp — Automatizaciones'}},credentials:{gmailOAuth2:{id:'FNfEzbpTEsdutlzd',name:'Gmail account'}},position:[1140,100],output:[{id:'mensaje-de-prueba',threadId:'hilo-de-prueba',labelIds:['SENT']}] },
    { name:'Registrar aviso enviado',type:'n8n-nodes-base.dataTable',typeVersion:1.1,parameters:{resource:'row',operation:'upsert',dataTableId:{__rl:true,mode:'list',value:TABLA_AVISOS,cachedResultName:'Formulario 3 — avisos enviados'},matchType:'allConditions',filters:{conditions:[{keyName:'clave',condition:'eq',keyValue:'={{ $("Preparar aviso").first().json.clave }}'}]},columns:{mappingMode:'defineBelow',value:{clave:'={{ $("Preparar aviso").first().json.clave }}',workflow:'={{ $("Preparar aviso").first().json.workflow }}',enviado_en:'={{ $now.toISO() }}'}},options:{dryRun:false}},position:[1420,100],output:[{id:1,clave:sample.clave,workflow:WORKFLOW_ID}] },
  ]
}

export const CONEXIONES_AVISOS = [
  { source:'Error de importación',target:'Preparar aviso',sourceIndex:0,targetIndex:0 },
  { source:'Probar aviso por correo',target:'Preparar prueba de aviso',sourceIndex:0,targetIndex:0 },
  { source:'Preparar prueba de aviso',target:'Preparar aviso',sourceIndex:0,targetIndex:0 },
  { source:'Preparar aviso',target:'Limitar avisos a uno por hora',sourceIndex:0,targetIndex:0 },
  { source:'Limitar avisos a uno por hora',target:'Enviar aviso a Miguel',sourceIndex:0,targetIndex:0 },
  { source:'Enviar aviso a Miguel',target:'Registrar aviso enviado',sourceIndex:0,targetIndex:0 },
]
export const GRUPOS_AVISOS = [{name:'Aviso por correo',description:'Prepara el aviso, limita repeticiones a una por hora y registra el envío confirmado.',nodeNames:['Preparar aviso','Limitar avisos a uno por hora','Enviar aviso a Miguel','Registrar aviso enviado']}]

export function cargarAvisos() {
  const nodes=definirAvisos()
  return { workflowId:WORKFLOW_AVISOS,name:NOMBRE_AVISOS,nodes,connections:CONEXIONES_AVISOS,nodeGroups:GRUPOS_AVISOS,settings:{executionOrder:'v1',timezone:'America/Lima',executionTimeout:120,saveDataSuccessExecution:'none',saveDataErrorExecution:'all',saveManualExecutions:true},code:codigoSDK(nodes,WORKFLOW_AVISOS,NOMBRE_AVISOS,CONEXIONES_AVISOS,GRUPOS_AVISOS) }
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) process.stdout.write(JSON.stringify(cargarAvisos()))
```

## Evidencia: scripts/n8n/formulario3.alertas.test.mjs

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { prepararAlerta, cargarAvisos, TABLA_AVISOS, DESTINATARIO } from './formulario3.alertas.mjs'
const evento={workflow:{id:'BjI5m1PKVWhO0NDb'},execution:{id:'25',error:{message:'SECRETO-no-se-debe-enviar'},data:{telefono:'999000111'}}}

test('el aviso usa el destinatario autorizado y excluye mensajes crudos, secretos y datos personales',()=>{
  const aviso=prepararAlerta(evento,3600000)
  assert.equal(DESTINATARIO,'miguel@miavance.com')
  assert.ok(!JSON.stringify(aviso).includes('SECRETO'))
  assert.ok(!JSON.stringify(aviso).includes('999000111'))
  assert.match(aviso.mensaje,/Ejecución: 25/)
  assert.equal(prepararAlerta({workflow:{id:'otro-flujo'}},3600000),null)
})

test('la clave agrupa errores de la misma hora y separa las pruebas del aviso real',()=>{
  const a=prepararAlerta(evento,3600000)
  assert.equal(a.clave,prepararAlerta({...evento,execution:{id:'26'}},7199999).clave)
  assert.notEqual(a.clave,prepararAlerta(evento,7200000).clave)
  assert.notEqual(a.clave,prepararAlerta({...evento,prueba:true},3600000).clave)
  assert.match(prepararAlerta({...evento,prueba:true},3600000).asunto,/^\[PRUEBA\]/)
})

test('el recibo del aviso se escribe después de Gmail y ambas tablas apuntan al registro de avisos',()=>{
  const d=cargarAvisos()
  assert.ok(d.nodes.filter(n=>n.parameters.dataTableId).every(n=>n.parameters.dataTableId.value===TABLA_AVISOS))
  assert.equal(d.nodes.find(n=>n.name==='Enviar aviso a Miguel').parameters.sendTo,DESTINATARIO)
  assert.deepEqual(d.connections.filter(e=>e.target==='Registrar aviso enviado').map(e=>e.source),['Enviar aviso a Miguel'])
  assert.equal(d.nodes.find(n=>n.name==='Enviar aviso a Miguel').onError,undefined)
})

test('datos inesperados del error no fabrican enlaces ni contenido en el correo',()=>{
  const a=prepararAlerta({...evento,execution:{id:'https://malicioso.example',url:'https://malicioso.example'}},3600000)
  assert.ok(!a.mensaje.includes('malicioso'))
  assert.throws(()=>prepararAlerta(evento,NaN))
})

test('fase 7: el correo copia solo la lista de filas y reconoce el resumen diario', () => {
  const aviso = (id, message) => prepararAlerta({ workflow: { id }, execution: { id: '30', error: { message } } }, 3600000)
  const lista = 'Revisar filas de la hoja: 153 (rechazada), 160 (cliente sin registrar). Pendientes para reintentar: 161.'
  assert.match(aviso('BjI5m1PKVWhO0NDb', lista).mensaje, /terminó con un error\.\nRevisar filas de la hoja: 153 \(rechazada\), 160 \(cliente sin registrar\)\. Pendientes para reintentar: 161\.\nEjecución: 30/)
  assert.match(aviso('BjI5m1PKVWhO0NDb', lista + ' [line 245]').mensaje, /Pendientes para reintentar: 161\.\nEjecución/)
  assert.match(aviso('BjI5m1PKVWhO0NDb', 'Pendientes para reintentar: 4, 5.').mensaje, /Pendientes para reintentar: 4, 5\.\n/)
  for (const otro of ['Revisar filas de la hoja: 153 (Persona Privada).', 'SECRETO 999000111', lista + ' extra', '']) {
    assert.match(aviso('BjI5m1PKVWhO0NDb', otro).mensaje, /terminó con un error\.\nEjecución: 30/)
  }
  const resumen = aviso('Chn5g93IgxNlkF3K', 'Recibo sin fecha')
  assert.match(resumen.asunto, /resumen diario/)
  assert.match(resumen.mensaje, /workflow\/Chn5g93IgxNlkF3K/)
  assert.ok(!resumen.mensaje.includes('Recibo sin fecha'))
  assert.notEqual(resumen.clave, aviso('BjI5m1PKVWhO0NDb', '').clave)
  assert.equal(aviso('toString', ''), null)
  assert.equal(aviso('__proto__', ''), null)
})
```

## Evidencia: patrón de transición y gate de la fase 8 (scripts/n8n/formulario3.fase8.mjs, líneas 66–87)

```js
export function operacionesFase8(actual) {
  if (actual.id !== WORKFLOW_ID || actual.active || actual.activeVersionId) throw new Error('Preparar sin publicar y sin ejecuciones concurrentes')
  if (actual.versionId !== VERSION_FASE7) throw new Error('El borrador no es la versión de fase 7 verificada')
  const { preparar8 } = codigosFase8()
  if (actual.nodes.find(n => n.name === 'Preparar leads')?.parameters?.jsCode === preparar8) throw new Error('La fase 8 ya está aplicada')
  verificarFase7({ ...actual, active: false, activeVersionId: null })
  return [{ type: 'updateNodeParameters', nodeName: 'Preparar leads', parameters: { jsCode: preparar8 } }]
}

// Gate posterior a la escritura: el código de fase 8 aplicado y, con él devuelto
// a fase 7, todo lo demás tal como lo revisó verificarFase7. Con { publicado: true }
// exige además que la versión activa sea la inspeccionada.
export function verificarFase8(actual, tabla = TABLA_LATIDO, { publicado = false } = {}) {
  if (publicado && (actual.active !== true || !actual.versionId || actual.activeVersionId !== actual.versionId)) throw new Error('La versión publicada no es la inspeccionada')
  const { preparar7, preparar8 } = codigosFase8()
  const copia = JSON.parse(JSON.stringify(actual))
  const preparar = copia.nodes.find(n => n.name === 'Preparar leads')
  if (preparar?.parameters?.jsCode !== preparar8) throw new Error('Código de fase 8 no aplicado')
  preparar.parameters.jsCode = preparar7
  verificarFase7(copia, tabla)
  return true
}
```

## Protocolo

Reglas globales de colaboración (resumen): el reviewer es asesor; NO FINDING WITHOUT EVIDENCE; formato VERDICT / SUMMARY /
FINDINGS P0–P3 / RIESGOS y TEST GAPS / NEXT ACTIONS / CONFIDENCE; el PRIMARY acepta o rechaza con evidencia y corre los
checks reales del proyecto. La cadena termina en el PRIMARY: no hay recursión. No cites ni pidas secretos: la clave de
Resend no está en ningún archivo y no debe estarlo.
