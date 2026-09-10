---
tags: [crm, coordinacion, derivaciones, diagnostico]
fecha: 2026-09-10
estado: solucion-local-verificada-pendiente-publicacion
---

# Derivaciones de Rosa: diagnóstico de cola vacía

Miguel reportó que Rosa, coordinadora, vio errores al derivar y dejó de ver
leads. La captura entregada identifica la cuenta; no contiene el mensaje de
error ni identifica un lead desaparecido.

## Evidencia de producción

Comprobación de solo lectura a las **10:47 del 10 de septiembre de 2026,
America/Lima**:

- Rosa conserva el perfil y el enrolamiento CRM activos, con rol `coordinador`.
  `crm.mi_acceso_fn()` reconoce correctamente su acceso.
- Hoy existen **52 movimientos** de Rosa desde la cola global hacia bandejas,
  entre **09:46:55 y 09:48:25**. Son **52 leads distintos**.
- **50** fueron a **Carmen Jaramillo** y **2** a **Jorge Marzano**. El desglose
  exacto del primer tramo fue **30 FORMULARIO → Carmen**, **20 LANDING →
  Carmen** y **2 LANDING → Jorge**. La conciliación de `crm.actividades`
  mediante `LEFT JOIN crm.leads` confirma que los **52 existen y siguen
  activos**. Ningún lead de este lote falta.
- Ejecutadas como `authenticated` con la identidad de Rosa y transacciones
  de solo lectura, `crm.leads_por_repartir()` y `crm.resumen_reparto_fn()`
  devuelven una cola de **0**. `crm.supervisores_para_reparto()` confirma las
  bandejas pendientes de Carmen **50**, Jorge **2** y Katherinne **0**.
- Hay tres leads antiguos sin dueño (20–21 de agosto), pero los tres tienen
  `no_contactar=true` y veto de persona. Su exclusión de la cola corresponde
  al filtro vigente; no deben confundirse con leads disponibles.
- Historial, distribución, reporte de ayer e ingresos del mes respondieron
  sin error bajo la identidad de Rosa. La lectura del rol y esas consultas
  no mostraron una denegación de permisos.

## Conciliación con la hoja de Drive

Miguel señaló que en Drive había entrado más data. Se exportó la pestaña
`LEADS` de **Leads AVANCE CORP — captura para CRM** sin modificarla:

- La hoja llega a la fila **1.471**: una cabecera y **1.470 filas de datos**.
- Las filas **1.420–1.471** son exactamente **52**: **22 LANDING** y
  **30 FORMULARIO**.
- Las 52 tienen actualmente la etiqueta
  `DUPLICADO: ya existe en el CRM`.
- Ninguno de sus 52 teléfonos aparece en las filas anteriores de la hoja y
  no hay duplicados dentro del propio lote.
- Se normalizaron sus teléfonos con la misma regla del importador y se
  compararon solo sus huellas MD5, sin exponer los números: las **52 huellas
  coinciden 52/52** con los 52 leads creados en el CRM entre **09:33:20 y
  09:33:23**. La composición también coincide: 22 `landing` y 30 `formulario`.

Por tanto, la observación de Miguel era correcta: **sí entraron 52 filas nuevas
desde Drive y sí llegaron al CRM**. La etiqueta `DUPLICADO` no describe la
primera inserción de este lote. La explicación compatible con la evidencia es
un reintento posterior: una primera llamada insertó las filas y otra pasada,
tras perderse o limpiarse la confirmación de la hoja, encontró esos mismos
teléfonos ya presentes. La causa exacta de esa segunda pasada requiere el log
de Apps Script; no se presenta como demostrada.

La cuenta observada en Chrome sí era la de **Rosa**. En esa cuenta, el registro
de producción confirma por separado que una sesión autenticada como Rosa
entregó los **30 FORMULARIO** a Carmen. Después, a las 11:07, Carmen ya había
entregado esos mismos **30 FORMULARIO** a ocho analistas. Por eso el número 30
aparece en ambos tramos; no son dos lotes distintos ni 60 leads.

La agenda del día fue guardada por Rosa a las **09:07:56**, antes de la entrada
del lote y antes de repartir: **FORMULARIO → Carmen** y **LANDING → Jorge**. El
primer carril se cumplió exactamente. En Landing hubo una desviación real:
**20** terminaron en la bandeja de Carmen y solo **2** en la de Jorge. La agenda
es informativa; la cola permite escoger manualmente cualquier supervisor y no
impide una selección distinta al turno guardado.

## Atribución técnica del reparto LANDING → Carmen

La auditoría completa de las 52 filas y los logs HTTP del intervalo reducen las
explicaciones posibles:

- Las **52 actualizaciones** se ejecutaron con `auth.uid()` de Rosa. En los 20
  Landing solo cambiaron `asignado_supervisor_id` y `actualizado_en`: el
  supervisor pasó de vacío a Carmen. `origen` no cambió en ninguna de las 52
  actualizaciones ni en otra actualización posterior del lote.
- Los **52 POST** a `/rest/v1/rpc/repartir_lead` salieron de **Chrome en
  Windows**, llevaron `auth_user` de Rosa y respondieron **HTTP 200**. Hubo
  además un `OPTIONS` normal del navegador. No hubo respuesta HTTP fallida en
  la ventana de 09:46:30–09:49:00.
- Supabase conserva una sola sesión de Rosa creada antes del incidente, también
  Chrome en Windows. La sesión de Chrome en macOS se creó a las 12:36, durante
  la revisión posterior. Esto no identifica a la persona que operaba Windows;
  una sesión autenticada prueba la cuenta, no quién estaba frente al equipo.
  La tabla de auditoría de Auth no conserva eventos globales del periodo, por lo
  que no permite reconstruir ingresos ya eliminados.
- No existe cron de reparto. El único escritor usado por esta pantalla recibe
  un `p_supervisor` concreto y copia exactamente ese UUID en el lead. No mira el
  origen ni la agenda para escoger destino.
- Los 30 Formulario eran las posiciones globales 1–30 de la cola por ser los más
  recientes. Aun así, la secuencia empezó por los 22 Landing, lo que es
  compatible con activar el filtro exacto de origen `landing`. Los primeros 20
  Landing visibles se enviaron a Carmen en orden de pantalla; hubo una mediana
  de **0,672 segundos** entre respuestas y 42 de los 51 intervalos fueron
  menores a un segundo. Tras una pausa de seis segundos, los dos Landing
  restantes fueron a Jorge. La inferencia más fuerte es que los 20 selectores de
  la primera página ya estaban elegidos en Carmen antes de pulsar sus botones
  rápidamente. Los logs no registran el evento de selección y por ello no
  permiten atribuir el gesto a una persona concreta.

El sistema, por tanto, **no convirtió Formulario en Landing ni escogió Carmen
automáticamente**. Las 20 órdenes LANDING → Carmen llegaron desde la sesión de
Rosa en Windows. Si Rosa no las hizo personalmente, la evidencia restante es
compatible con otra persona usando esa misma sesión o equipo; no hay evidencia
de un segundo dispositivo simultáneo conservado por Supabase.

Una consulta inicial confirmó **52/52 activos**: 30 Formulario ya estaban con
analistas, 20 Landing permanecían en la bandeja de Carmen y 2 Landing en la de
Jorge. Mientras avanzaba el diagnóstico, Carmen entregó los 20 Landing a ocho
analistas entre **13:06:30 y 13:10:40**. El estado más reciente quedó en **50
con analistas + 2 en la bandeja de Jorge**, siempre 52 activos. El recorrido
completo queda:

```text
09:07  Rosa guarda turno: Formulario → Carmen; Landing → Jorge
09:33  Drive → CRM: 52
09:46–09:47  Sesión de Rosa → 20 Landing a Carmen y 2 Landing a Jorge
09:47–09:48  Sesión de Rosa → 30 Formulario a Carmen
11:03–11:07  Carmen → analistas: los mismos 30 Formulario
13:06–13:10  Carmen → analistas: los 20 Landing que recibió
Estado observado: 50 con analistas + 2 en bandeja de Jorge = 52
```

El total actual de 1.469 registros activos en `crm.leads` es contexto, **no una
prueba de ausencia de borrados históricos**. La conclusión de integridad se
limita al lote conciliado de 52 leads.

## Interpretación y límite del sistema desplegado durante el incidente

Los leads derivados dejan de estar en **Cola de nuevos** porque ya tienen
supervisor; cuando el supervisor los entrega también dejan su bandeja y pasan
a los analistas. En la versión desplegada durante el incidente, sus movimientos
solo se podían localizar en **Repartir leads → Historial**. El flujo de pantalla
elimina una fila local solo después de que la RPC de reparto confirma éxito. El
servidor actualiza la asignación, sin borrar ni desactivar el lead.

Hay un defecto concreto de concurrencia en el cliente. `useReparto` guarda un
único `enviandoId`. Si se inicia el envío de A y enseguida el de B, el estado
pasa a B y el botón de A vuelve a quedar habilitado aunque su petición siga en
curso. Un segundo clic sobre A puede producir esta secuencia:

1. la primera petición entra correctamente y A sale de la cola;
2. la segunda petición llega después y el servidor responde `P0002` /
   `FUERA_DE_COLA` porque A ya tiene supervisor;
3. la pantalla muestra un toast de error y relee la cola, donde A ya no aparece.

El servidor protege la integridad con bloqueo y predicado anti-carrera, así que
ese doble intento no duplica ni borra el lead. El defecto está también en el
chunk desplegado `repartir-CNy5f3kZ.js`, no solo en el código local. Sin
embargo, los logs conservados descartan que esa carrera ocurriera durante las 52
derivaciones estudiadas: hubo exactamente 52 POST, los 52 respondieron 200 y
produjeron 52 cambios. Por eso el defecto es real y debe corregirse, pero **no
es evidencia de la causa del aviso que Rosa recuerda**. El texto original del
toast no fue capturado; pudo corresponder a otro momento o a otra carga.

La desviación de los 20 Landing es un hallazgo aparte: no desaparecieron, pero
quedaron en una bandeja distinta a la agenda. La interfaz y el servidor
desplegados ese día no aplicaban ni validaban el turno al repartir.

## Por qué Miguel no encontraba las entregas en la cuenta de Rosa antes de la corrección

La información detallada sí está expuesta por
`crm.historial_derivaciones`, pero la presentación la oculta de forma poco
intuitiva:

- **Distribución** informa el segundo tramo, supervisor → analista. No sirve
  para buscar directamente las entradas Rosa → bandeja.
- **Historial → Agenda de reparto** muestra solo el agregado correcto:
  `Formulario · Carmen · 30 derivados`.
- El listado **Historial de derivaciones** mezcla los dos tramos y muestra solo
  25 movimientos por página, de más nuevo a más antiguo.
- Como Carmen hizo después 30 entregas a analistas, esos movimientos más nuevos
  ocupan toda la página 1 y cinco lugares de la página 2. Las primeras
  entregas de Rosa aparecen recién en la **página 2**.
- El buscador declara y aplica búsqueda únicamente a la página visible. Buscar
  `ROSA` desde la página 1 devuelve vacío aunque existan movimientos en las
  siguientes páginas.

Se comprobó en la sesión activa de Rosa: en **Historial, página 2**, al buscar
`ROSA`, aparecen los movimientos de las 09:47–09:48 con `Sin asignar → Bandeja
de CARMEN JARAMILLO` y `por ROSA`. Esa vista quedó abierta para facilitar la
comprobación. Los restantes movimientos del lote continúan en páginas
posteriores. No se modificó ningún dato.

El problema de visibilidad es, por tanto, reproducible: el historial existe,
pero combina etapas, pagina antes de buscar y carece de filtros globales por
fecha, actor y tipo de traspaso. Eso hace que una entrega correcta parezca
ausente desde la cuenta de Coordinación.

## Solución implementada

La corrección local elimina las dos condiciones que hicieron posible el
incidente y mejora la evidencia visible para Coordinación:

- `private.repartir_lead_implementacion` exige un turno guardado para el día de
  Lima cuando el origen es `landing` o `formulario`. Si el destino solicitado no
  coincide con la agenda, responde `22023` con un mensaje operativo y no mueve
  el lead.
- El reparto toma un bloqueo compartido de la agenda del día; guardar o cambiar
  el turno toma el bloqueo exclusivo existente. Así una modificación concurrente
  del turno no puede dejar una asignación validada contra un plan que cambió a
  mitad de la operación.
- En **Cola de nuevos**, Landing y Formulario cargan el destino desde la agenda y
  lo muestran bloqueado. Sin turno guardado, el botón de reparto queda
  deshabilitado. La decisión sigue siendo visible, pero ya no se puede enviar por
  descuido al supervisor equivocado.
- La primera pestaña ahora es **Coordinación → supervisores**. Cuenta el movimiento
  inmediatamente cuando Rosa entrega el lead a una bandeja, aunque Carmen o Jor
  todavía no lo hayan distribuido a analistas. Muestra el total real por origen,
  el desglose por supervisor que efectivamente recibió y una alerta si existe un
  movimiento histórico fuera del turno.
- **Supervisión → analistas** queda rotulada como el segundo tramo para evitar
  interpretar sus 30 o 50 como el total entregado originalmente por Rosa.
- Cada lead conserva su propio estado de envío en curso. Terminar la petición de
  otro lead ya no vuelve a habilitar prematuramente el primero, por lo que se
  elimina la carrera de doble clic detectada.

La migración y el frontend están preparados y verificados localmente. Todavía no
se han publicado: producción conserva el comportamiento anterior hasta ejecutar
el ciclo controlado de migración y despliegue.

## Verificación y alcance

- **PASS:** acceso vivo de Rosa y lecturas de reparto con su identidad.
- **PASS:** conciliación del lote de 52 derivaciones con sus leads actuales.
- **PASS:** coincidencia exacta 52/52 entre las últimas filas de Drive y el
  lote creado a las 09:33 en el CRM, usando huellas de teléfono normalizado.
- **PASS:** agenda vigente desde las 09:07:56, previa al lote: Formulario a
  Carmen y Landing a Jorge.
- **PASS:** auditoría de los campos modificados: 52 cambios de supervisor,
  ningún cambio de origen y actor autenticado Rosa en todos.
- **PASS:** logs HTTP entre 09:46:30 y 09:49:00: 52 POST autenticados de Chrome
  en Windows, 52 respuestas 200, un OPTIONS 200 y cero fallos HTTP.
- **PASS:** el bundle desplegado conserva el estado de envío como un solo ID y
  permite la carrera de doble intento descrita; los logs descartan que se haya
  activado durante estas 52 llamadas.
- **PASS:** tests focalizados de reparto: **57/57** en
  `repartir.test.tsx` y `crm-api-reparto-msw.test.ts`, incluidos destino por
  agenda, agenda ausente, dos repartos concurrentes y desglose fuera del turno.
- **PASS:** compuerta completa de frontend: **225 archivos y 3.185 pruebas**,
  typecheck, build productivo, verificación de bundle y umbral de duplicación.
  Lint terminó sin errores y conserva cuatro advertencias preexistentes de
  accesibilidad en `coverflow-carousel.tsx`.
- **PASS:** Playwright del módulo Repartir: **30/30**, incluido el escenario de
  22 Landing con 20 enviados a Carmen y 2 a Jor, visible en Coordinación antes
  del reparto posterior a analistas.
- **PASS:** suite Playwright completa: **160 aprobadas y 26 omitidas** por la
  configuración vigente; no aparecieron regresiones en navegación ni otros roles.
- **PASS:** migración nueva aplicada en una base temporal aislada, clonada de un
  banco local. El oráculo `test-reparto.sql` terminó con `REPARTO_TX_OK` y
  confirmó rechazo atómico del destino fuera del turno, trazabilidad real y
  preservación de los vetos existentes.
- **PASS:** checks de scripts del repositorio.
- **PASS:** reproducción de la falta de visibilidad: `ROSA` no aparece en la
  primera página del historial y sí aparece en la segunda; el buscador opera
  solo sobre la página actual.
- **NOT RUN:** reproducción sobre un lead real en producción; no se alteraron
  datos para forzar el defecto de concurrencia. Tampoco quedó el texto original
  del toast.
- **NOT RUN:** log de la ejecución de Apps Script que dejó las 52 filas con
  etiqueta `DUPLICADO`; el reintento es una explicación probable, no probada.
- **NOT RUN:** nueva derivación de prueba en producción; no se alteraron leads
  para probar el diagnóstico.
- **NOT RUN:** gate RLS conectado. El preflight no pudo iniciarse porque este
  entorno no tiene `SUPABASE_URL`; no se presenta como fallo del producto.
- **NOT RUN (sin dictamen válido):** opinión independiente de Claude. Se invocó
  `scripts/claude-review` con evidencia saneada y rol `SECONDARY_REVIEWER`.
  El primer intento no completó el review; el segundo, con acceso a red
  autorizado, terminó con resultado incompleto o sin `VERDICT` válido.
  Ambos comandos devolvieron código 1. No se interpreta como aprobación ni
  como rechazo del diagnóstico. Las conclusiones se apoyan en la conciliación
  directa y conservan explícitamente el límite sobre el error reportado.
- **PENDIENTE:** publicación de la migración y del frontend. No se modificaron
  asignaciones ni datos de producción durante la implementación.

El diagnóstico original contrastó el código desplegado y las funciones vivas.
La solución local está en `app/src/screens/repartir.tsx`,
`app/src/components/app/agenda-reparto-diaria.tsx`,
`app/src/data/crm-api.ts` y la migración
`20260910201500_crm_reparto_turno_obligatorio_y_trazabilidad_real.sql`.

Relacionadas: [[Acceso y roles del CRM]],
[[Reporte diario de derivaciones para Coordinación]],
[[Distribución de leads por capital y trazabilidad CRM]].
