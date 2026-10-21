---
tags: [crm, conversion, etapas, reglas, propuesta]
actualizado: 2026-10-13
estado: propuesta-corregida-integrada-al-cierre-actual
---

# Conversión — recorrido obligatorio por hechos

## Requisito confirmado por Miguel

El lead no podrá convertirse a cliente sin haber cumplido todas las etapas. Miguel aclaró que deben contar **hechos registrados: contacto, cita y asistencia**; mover una tarjeta de columna no acredita el cumplimiento.

Esta es una propuesta de funcionamiento y diseño. No se han cambiado reglas, funciones ni datos de producción. El punto de partida es [[Etapas del CRM - mapa de funcionamiento (2026-10-12)]].

**Decisión confirmada el 13/10:** Miguel eligió la opción 1 para reaperturas: exigir contacto, cita y asistencia nuevos desde la reapertura. Los hechos de ciclos anteriores se conservan en el historial, pero no acreditan los requisitos del nuevo ciclo. Esta respuesta resuelve ese caso comercial; no constituye aprobación de activar la regla completa.

**Segunda decisión confirmada el 13/10:** Miguel eligió la opción 1 para llegada directa a oficina: permitir contacto presencial, cita inmediata y asistencia registrados durante esa atención, sin exigir una cita agendada previamente.

**Requisito adicional confirmado:** el analista debe percibir el flujo de trabajo y saber qué hacer. Miguel pidió una guía visible y acciones para resolver lo pendiente, no limitarse a rechazar la conversión. La propuesta de interfaz siguiente desarrolla ese requisito y sigue pendiente de aprobación e implementación.

## Plan visual para aprobación

El 13/10 Miguel pidió llevar el plan a Figma, muy sencillo de leer y **todo vertical**. Se creó el [plan editable en FigJam](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM): regla, recorrido de seis pasos, guía visible, casos especiales y decisiones comerciales. Se sincronizaron ambas respuestas: reapertura con ciclo nuevo y atención inmediata en oficina aprobadas. Crear el tablero no constituye aprobación de la regla completa ni de su activación.

Miguel pidió sustituir el texto por diagramas y ver la interfaz del analista. El tablero ahora presenta un [diagrama vertical de decisiones y acciones](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=11-117). El contenedor vigente es `11:117`; el anterior `3:29` se conserva oculto como archivo. Se revisó una captura del diagrama y se comprobó que sus elementos quedan dentro del contenedor.

Los primeros cuatro bocetos de interfaz se conservan **ocultos y sustituidos**: Miguel indicó que no estaban adaptados a su CRM y recordó que ya existe un flujo para cerrar acciones y pasar a la siguiente. La aprobación anterior del concepto no valida esos bocetos.

La [propuesta corregida del analista](https://www.figma.com/design/clrnxxPbacujdC3S5tMWkn?node-id=13-16) reconstruye de forma editable el cierre actual de una cita, a partir del código: «Se realizó / No asistió», resultado comercial, capital con moneda, nota y «Siguiente acción propuesta», con «Saltar esta vez» y «Cerrar tarea». Los mensajes posteriores de estado de conversión están identificados como incorporación propuesta. Es una reconstrucción desde código con datos ficticios, no una captura de producción ni una implementación.

El plan de cinco fases está en el [mismo FigJam](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=17-117) y en el [mismo archivo de pantallas](https://www.figma.com/design/clrnxxPbacujdC3S5tMWkn?node-id=9-596), debajo del ejemplo, todo vertical. El diagrama `11:117` se corrigió para partir del cierre existente y distinguirlo de la evaluación nueva de conversión.

Miguel indicó «el flujo está genial» y pidió el plan de desarrollo de frontend y backend. Se considera validado el concepto del flujo; las pantallas, la regularización de antiguos y la activación siguen siendo propuestas. No se ha autorizado ni ejecutado un despliegue.

## Cómo se presentaría al analista

**Punto de partida obligatorio:** reutilizar el cierre y el motor de próxima acción que ya existen. El analista registra el resultado, revisa la siguiente acción propuesta y guarda. La regla nueva lee los hechos de ese guardado; no introduce un segundo circuito de cierre ni solicita volver a registrar contacto, cita o asistencia.

La ficha y el feedback de guardado mostrarían el estado de conversión y un acceso al pendiente concreto. Deben integrarse con los bloques existentes de agenda/SLA. El motor `sugerirSiguiente` sigue proponiendo el próximo trabajo y `camposDeSugerencia` mantiene alineados los campos visibles con lo enviado. El evaluador nuevo decide si los hechos permiten convertir; no sustituye ese motor ni crea otra tarea por su cuenta.

Ejemplo para una cita ya atendida cuyo resultado falta registrar:

> **Falta registrar el resultado de la cita.**
>
> **[Registrar resultado]** abre esa cita en el formulario actual de cierre, con su resultado comercial y siguiente acción.

La entrada **«Convertir a cliente» permanece visible y consultable**. Si faltan hechos, muestra el recorrido y sus acciones; no inicia el alta financiera ni se limita a un botón deshabilitado sin explicación. Cuando se acrediten los cinco pasos y el usuario tenga acceso, se ofrece **«Iniciar conversión»**. Los controles de identidad e inversión se completan dentro del flujo existente; la inversión confirmada se exige para finalizar la conversión, no como condición imposible de cumplir antes de abrir su formulario.

Un fallo de consulta se mostraría como «No se pudo verificar» con reintento, sin dar por cumplido lo desconocido. Se mantienen los controles existentes de permisos y restricciones de contacto; la guía solo ofrece acciones que el analista puede ejecutar.

| Situación del lead | Acción visible | Qué ocurre después |
|---|---|---|
| Sin gestión | Contactar y registrar resultado | Abre los medios de contacto y el registro correspondiente. Abrir WhatsApp o pulsar llamar no acredita una conversación. |
| Gestión sin respuesta | Contactar de nuevo / programar seguimiento | Conserva Gestionado; Contactado sigue pendiente hasta una conversación registrada. |
| Contacto confirmado | Agendar cita | Abre el formulario del mismo lead. Tras guardar una cita válida, muestra su fecha. |
| Cita futura pendiente | Ver cita / reprogramar | Muestra fecha y estado; no solicita inventar asistencia anticipada. |
| Cita ocurrida sin resultado | Registrar resultado | Abre esa cita. Una asistencia válida completa Entrevista; cancelación o inasistencia ofrece reprogramar. |
| Recorrido completo | Iniciar conversión | Abre el flujo existente de identidad e inversión y conserva sus validaciones. |
| Llegada directa a oficina | Atender en oficina | Adaptar el registro de cita inmediata y reutilizar su cierre para registrar la asistencia real, resultado comercial, capital cuando corresponda y siguiente acción. |

Después del guardado confirmado se actualiza la evidencia y se refresca el estado de conversión. Si ya existe una siguiente tarea, se muestra esa tarea y se evita duplicarla. Una llamada contestada puede completar Gestión y Contacto juntas.

Hay dos conceptos distintos: **próxima acción para este lead** (agenda/motor actual) y **siguiente lead de la cola de Mi día** (`onGuardado`). La consulta nueva no debe condicionar el cierre de un resultado legítimo ni impedir avanzar en la cola por un fallo de lectura del estado de conversión. Un guardado sin confirmar conserva los datos y su reintento; no muestra éxito ni avanza.

Se conserva «Saltar esta vez»: permite cerrar sin agendar otra acción y deja visible «sin próxima acción». No autoriza saltar requisitos de conversión. «No contestó» y «No asistió» deben poder guardarse normalmente; no acreditan conversación o asistencia. Se conservan las restricciones de contacto, las cadencias, los permisos y el deshacer existente.

Al reabrir: «Nuevo proceso iniciado», requisitos del ciclo nuevo y acción para contactar; el historial anterior sigue consultable. Si se deshace evidencia o cambia el estado mientras el formulario está abierto, se explica qué requisito volvió a quedar pendiente, se enlaza a la acción necesaria y se conservan los datos ingresados. La confirmación final vuelve a validar los hechos.

## Qué acredita cada paso

| Paso | Evidencia propuesta |
|---|---|
| Nuevo | Registro del lead o comienzo documentado del ciclo. No exige arrastrarlo hacia atrás. |
| Gestionado | Una actividad de gestión válida, no deshecha. |
| Contactado | Conversación registrada: llamada contestada, WhatsApp recibido o atención presencial por una acción definida para ello. |
| Cita agendada | Registro de una cita del lead, vinculada con la entrevista que acredita el cierre del recorrido. |
| Entrevista realizada | Asistencia registrada y cita correspondiente cerrada como realizada. La etapa visible por sí sola no acredita asistencia. |

Una llamada contestada puede acreditar Gestión y Contacto en el mismo acto. No habría una espera mínima en cada columna ni obligación de registrar primero una llamada fallida. El contacto debe ser previo a la cita/entrevista o parte de un gesto compuesto explícito permitido; la entrevista aislada no inventa gestiones anteriores.

Las evidencias deben pertenecer al mismo lead y al proceso comercial que se decida validar. No se puede reunir una cita cancelada con una actividad de reunión ajena para completar el recorrido. Los vínculos entre actividad, tarea y ciclo sirven para acreditarlo; los eventos de una misma operación pueden compartir hora.

La asistencia debe seguir vigente: tarea completada y actividad correspondiente no deshecha. Ya existe una relación de tarea con ciclo en `crm.tarea_sla_contexto`, y la actividad de asistencia incluye `metadata.tarea_id`. Se aprovechará esa relación antes de añadir campos nuevos. La cobertura de contactos independientes y registros antiguos debe comprobarse por separado; no se resolverá una frontera ambigua entre ciclos únicamente comparando horas.

## Casos y tratamiento propuesto

| Caso | Propuesta |
|---|---|
| Mover manualmente por todas las columnas | No completa requisitos. Se muestran los hechos pendientes. |
| Cita cancelada o inasistencia | No acredita entrevista. Una nueva cita realizada sí puede completar el recorrido. |
| Reprogramación | Se sigue la cadena de la cita y se acredita la que efectivamente se realizó. |
| Retroceso manual | No borra hechos válidos ya registrados; la elegibilidad se vuelve a calcular con ellos. |
| Deshacer una actividad | Deja de servir como evidencia. Si existe otra evidencia válida, se usa; si era la única, el requisito queda pendiente. |
| Reasignación | El nuevo analista conserva la evidencia válida del proceso. La lista indica quién la registró. Esto es distinto de «Gestionado» por tenencia, que puede volver a Nuevo para el nuevo titular. |
| Referido o base cargada | El origen no dispensa requisitos. Reactivar a Contactado tampoco equivale por sí solo a una conversación acreditada. |
| Reapertura tras descarte | **Confirmado por Miguel, opción 1:** exigir contacto, cita y asistencia nuevos desde la reapertura. Los hechos anteriores quedan en el historial y no completan el nuevo ciclo. |
| Llegada directa a oficina / cita inmediata | **Confirmado por Miguel, opción 1:** permitir contacto presencial, cita inmediata y asistencia reales registrados durante la atención. Acción explícita «Atender en oficina» con hechos vinculados; no exige cita previa ni inventar una llamada o fecha anterior. |
| Lead antiguo ya avanzado | Reconstruir únicamente lo acreditable. Mostrar faltantes/ambigüedades; una etapa avanzada no basta. Acordar regularización antes de activar el bloqueo. |
| Borrador de conversión pendiente | Revalidar al retomar y confirmar. Haber iniciado el formulario antes de activar la regla no concede una excepción automática. |
| Conversión ya confirmada | Conservar su lectura y el reintento de su misma confirmación. La regla controla conversiones nuevas. |
| Renovación, upgrade u otra inversión de un cliente existente | No es una primera conversión de lead. Identificar el caso en el servidor; no permitir que el cliente elija una categoría para evitar la regla. |

La misma exigencia se propone para todas las empresas y roles que convierten. Una excepción por cargo, origen o falta de historial necesitaría una decisión comercial explícita; no se presume aprobada.

## Cómo se implementaría

1. **Una evaluación central del servidor** obtiene requisitos, evidencia, faltantes y versión de la regla. Respeta el ámbito del usuario y evita mantener casillas independientes que se puedan desincronizar del historial.
2. **Validación temprana** al entrar o retomar la conversión y antes de crear el acceso del cliente. Debe cubrir la ruta con identidad guardada, que entra directamente al formulario compartido, y la operación del servidor que crea el acceso. Así se detiene un proceso que ya es inelegible antes de esos pasos.
3. **Validación final en la misma operación de confirmación**, leyendo el estado vigente y coordinándose con cancelar/deshacer/reasignar. Un formulario abierto no conserva un permiso de conversión si perdió la evidencia.
4. **Protección de la transición a Convertido** con el mismo evaluador, cubriendo las rutas alternativas. La vinculación persona/lead se decide en el servidor; no se confía en que el navegador declare si es conversión inicial.
5. **Trazabilidad al convertir:** conservar referencias de evidencia, ciclo y versión de regla utilizadas. Los reintentos de una operación ya confirmada recuperan su resultado antes de aplicar requisitos para una conversión nueva.

Crear el acceso usa un servicio externo y no es atómico con confirmar la inversión. Una invalidación ocurrida después de ese alta debe impedir la conversión y continuar por la recuperación existente del borrador. No se promete deshacer el acceso mediante una reversión de SQL ni borrar cuentas automáticamente.

Puntos actuales a integrar, bajo `CRM-Avance-Corp/`:

- `app/src/components/gestion-diaria/registrar-resultado.tsx`: una lógica de resultado de llamada, presentada en diálogo o dentro de la tarjeta «Ahora» de Mi día. Guarda resultado y próxima acción; avanza la cola después de confirmar persistencia.
- `app/src/components/app/cerrar-tarea.tsx`: cierre existente, resultado comercial/capital de la cita, siguiente acción editable y «Saltar esta vez». Las llamadas de lead usan `RegistrarResultado`; las tareas de clientes conservan su flujo propio.
- `app/src/lib/motor-siguiente.ts` y `app/src/lib/campos-siguiente.ts`: sugerencia de trabajo y correspondencia con los campos guardados. Reutilizar, sin motor paralelo.
- `app/src/lib/store.tsx:674` (`ejecutarCierreTarea`): despacha reuniones de lead a `cerrar_reunion_v3`, otras tareas de lead a `cerrar_tarea_v2` y tareas de cliente a su cierre propio. Las llamadas tipificadas usan `registrar_llamada_v4`.
- `app/src/components/app/lead-drawer.tsx`: entrada de conversión y presentación de requisitos.
- `app/src/components/app/inversion-desde-lead.tsx`: identidad y retoma del proceso.
- `app/src/components/app/inversion-nueva.tsx`: acceso y confirmación de inversión.
- `app/src/data/inversion-solicitud-api.ts`: operaciones del formulario compartido.
- `crm.preparar_persona_lead_inversion_fn`, preparación de solicitud/acceso y `crm.confirmar_inversion_revisada_fn`: evaluación temprana y final.
- `private.conversion_lead_con_inversion`: defensa actual de la transición; integrar sin debilitar la exigencia de inversión confirmada.
- `crm.actividades`, `crm.tareas`, `crm.tarea_sla_contexto` y ciclos del lead: evidencias existentes; confirmar precisión y cobertura durante el diseño SQL.

La implementación deberá inventariar además las entradas de alta directa y rutas antiguas que puedan representar la primera conversión de esa persona, para que el resultado no dependa de por dónde se abra el formulario. No se propone bloquear indiscriminadamente operaciones de clientes existentes.

También se revisarán las altas de leads y los caminos privilegiados o de sistema. Las inserciones autenticadas ya tienen protecciones contra nacer Convertido en `private.leads_before_insert` y `private.trg_leads_disponibilidad_atomica`; la necesidad de inventariar todas las rutas no demuestra una evasión actual de esas protecciones.

## Plan de desarrollo de frontend y backend

> **Actualización 18/10:** el plan vigente tiene ocho fases, hasta el ZIP, y fue revisado por Codex con una revisión independiente de Claude. Ver [[Conversion - plan por fases y objetivo goal (2026-10-18)]] y el [mismo FigJam actualizado](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=17-117). No requiere n8n para el recorrido. Las cinco fases siguientes se conservan como historial; no se implementó ni activó el cambio.

Este desglose responde a la petición posterior de Miguel. Los nombres de piezas nuevas son propuestas, no funciones existentes.

### Fase 1 — Integración con el cierre existente

- Fijar el comportamiento actual desde Mi día, ficha y agenda: resultado, próxima acción, guardado confirmado y continuación. Conservar las dos presentaciones de `RegistrarResultado` y el cierre de reunión de `CerrarTareaDialog`.
- Mapear los hechos producidos por `registrar_llamada_v4`, `cerrar_reunion_v3` y `cerrar_tarea_v2`, incluidos los efectos en tareas, historial y etapa.
- Documentar que la próxima tarea del lead y el siguiente lead de la cola son operaciones distintas. Mantener reintentos, no contacto y prevención de tareas duplicadas.
- **Entrega:** mapa de cierres y puntos de integración. **Criterio:** ninguna entrada exige un segundo cierre ni adelanta la cola antes del guardado confirmado.

### Fase 2 — Evidencias y evaluación central

- Inventariar las rutas de primera conversión y el registro/deshacer de gestiones, contacto, cita y asistencia. Separar conversión inicial de operaciones de clientes existentes.
- Comprobar vínculos entre actividad, tarea, lead y ciclo. Reutilizar `crm.tarea_sla_contexto` para citas; resolver la pertenencia de contactos independientes al ciclo sin inferirla solo por la hora. No confundir ciclo comercial con tenencia del analista.
- Implementar un evaluador privado compartido y una consulta autorizada, por ejemplo `crm.evaluar_recorrido_lead_fn`. Devuelve pasos cumplidos, evidencias, faltantes y referencias para abrir la acción existente que resuelve el faltante. No propone una cadencia ni agenda una nueva tarea. Las autorizaciones y condiciones existentes siguen siendo requisitos adicionales.
- El progreso se calcula desde los hechos vigentes. No añadir cinco casillas editables ni usar la etapa visible como prueba. Deshacer/cancelar invalida la evidencia correspondiente; otra evidencia válida puede mantener el requisito cumplido.
- Ejecutar un censo de solo lectura: acreditables, incompletos e historia ambigua. No reconstruir hechos que no estén documentados.

Contrato orientativo de la consulta:

```json
{
  "version_regla": 1,
  "ciclo_n": 2,
  "cumplidos": 4,
  "total": 5,
  "recorrido_completo": false,
  "pasos": [
    { "codigo": "asistencia", "estado": "pendiente", "evidencias": [] }
  ],
  "accion_para_resolver": {
    "codigo": "registrar_resultado_cita",
    "tarea_id": "id-de-la-cita-autorizada"
  }
}
```

Ejemplo abreviado: la respuesta real incluye los cinco pasos y solo evidencia accesible al usuario. Un error de consulta se representa como «No se pudo verificar», no como cumplimiento ni como falta de hechos. `recorrido_completo` no sustituye permisos, identidad ni condiciones de inversión.

**Entrega:** evaluación común. **Criterio:** el mismo hecho se acredita una vez y un cambio de columna no completa requisitos.

### Fase 3 — Guía dentro del frontend actual

- Integrar un resumen de elegibilidad y una consulta compartida en la ficha y el feedback existente. Mostrar faltante, evidencia y acceso a su acción, evitando un checklist obligatorio paralelo al cierre actual.
- Integrar la guía con los bloques actuales de próxima acción y SLA para evitar instrucciones duplicadas o contradictorias. Priorizar las acciones permitidas para ese usuario.
- Enlazar los botones a `RegistrarResultado`, agenda y `CerrarTareaDialog`; abrir el lead y la cita correctos. Mostrar fecha/reprogramar para una cita futura. Cancelación o inasistencia ofrecen una nueva cita.
- En el Pipeline, mostrar un resumen breve; obtener los resúmenes por lote o en la consulta de la lista para evitar una petición por tarjeta.
- Tras guardar, deshacer, cancelar, reprogramar o reabrir, volver a consultar el estado y actualizar ficha y tarjeta. Contemplar cambios de otro usuario y revalidar al recuperar foco o retomar la conversión según los mecanismos existentes.
- Si se pulsa «Convertir a cliente» con faltantes, llevar al recorrido y a su acción; preservar los datos del formulario si el estado cambia.
- Adaptar «Atender en oficina» al registro y cierre actuales de citas: vincular contacto presencial y cita inmediata; cerrar la atención efectivamente realizada con resultado comercial, capital cuando corresponde y siguiente acción. Resolver en backend la operación explícita/idempotente necesaria para permitir el caso sin fabricar una llamada o fecha previa. Abrir el formulario no acredita asistencia.
- Respetar el límite entre guardado y consulta: un fallo de elegibilidad no impide guardar un resultado real; un guardado sin confirmar no habilita avanzar ni anuncia éxito. No crear una próxima tarea si el flujo ya la guardó.

**Entrega:** mensajes y accesos integrados. **Criterio:** el analista resuelve el pendiente con su formulario actual, sin repetir datos ni duplicar tareas.

### Fase 4 — Protección de la conversión existente

- Usar el mismo evaluador al iniciar/retomar, antes de crear acceso y dentro de la confirmación final de inversión; cubrir también la ruta con identidad ya guardada.
- Integrarlo con `crm.preparar_persona_lead_inversion_fn`, las operaciones de preparación/acceso, `crm.confirmar_inversion_revisada_fn` y la guarda `private.conversion_lead_con_inversion` después de verificar sus cuerpos y llamadas vigentes.
- Confirmar solo con hechos válidos del mismo lead y ciclo, manteniendo permisos y condiciones financieras actuales. No aceptar un booleano de elegibilidad enviado por el navegador.
- Coordinar la confirmación con los comandos que invalidan evidencias; revisar el orden de bloqueos de toda la cadena antes de diseñar SQL. Revalidar y guardar las referencias utilizadas en la misma transacción final.
- Conservar idempotencia: una operación ya confirmada devuelve su resultado. La inversión se confirma dentro del flujo; no se exige inversión confirmada para abrirlo. Mantener la recuperación existente si el servicio externo de acceso ya fue ejecutado.
- En reapertura, exigir hechos nuevos del ciclo nuevo. Reasignar o mover una tarjeta no borra la evidencia válida del ciclo vigente.

**Entrega:** protección de todas las entradas de primera conversión. **Criterio:** evidencia vigente del ciclo actual, con identidad e inversión dentro del flujo existente.

### Fase 5 — Pruebas, revisión y activación

- Backend: saltos de columnas, llamadas sin respuesta, citas futuras, asistencia real, cancelación/deshacer, coherencia de cita/asistencia, reapertura, reasignación, oficina, roles/ámbito, rutas alternativas, borradores y reintentos.
- Concurrencia: confirmar frente a deshacer/cancelar y doble envío de la atención presencial. Verificar que ninguna ruta cree una primera conversión sin cumplir la regla.
- Frontend: cada pendiente abre la acción correcta, guardado actualiza progreso, fallos de consulta ofrecen reintento, cambios de estado preservan datos y la conversión completa sigue funcionando. Probar conjuntamente cierre + próxima tarea + avance de etapa + avance de cola; cubrir «Saltar esta vez», «No contestó» y «No asistió» sin convertirlos en errores de cierre.
- Aplicar los checks del proyecto, pruebas SQL/RLS en base aislada y E2E del CRM en Docker local. Revisión secundaria del código final por el riesgo de datos y conversión; la revisión previa de propuesta no valida una futura implementación.
- Entregar primero la evaluación y guía para contrastar el censo; activar el bloqueo tras definir el tratamiento de antiguos y validar los ensayos. La configuración de activación pertenece al servidor y no sustituye las protecciones financieras existentes.

**Entrega:** pruebas SQL y E2E en Docker, más revisión del cambio. **Criterio:** el recorrido actual sigue funcionando y se ha definido el tratamiento de antiguos antes del bloqueo.

Orden: **integrar el cierre existente → acreditar sus hechos → incorporar guía → proteger conversión → probar y activar**. Cada fase deja una demostración y criterios de aceptación.

## Preparación antes de activarla

1. Aprobar el flujo visible para el analista. Reapertura e ingreso presencial inmediato ya resueltos: hechos nuevos por ciclo y atención inmediata permitida.
2. Hacer un censo de solo lectura de leads todavía no convertidos: cumplen, faltan hechos o tienen historia ambigua. Definir tratamiento de antiguos y borradores sin fabricar evidencias.
3. Diseñar y ensayar la regla en una base aislada: saltos manuales, eventos simultáneos, citas relacionadas, cancelación, deshacer, reasignación, reapertura, base, empresas, rutas alternas y reintentos.
4. Comprobar especialmente la competencia entre confirmar y deshacer/cancelar. Inventariar primero los bloqueos existentes, incluidos los de funciones anidadas, y mantener un orden consistente que respeten los escritores de evidencia. No fijar un orden nuevo basándose solo en el cuerpo externo de confirmación.
5. Probar la interfaz en Docker y activar el bloqueo cuando la regla comercial, el impacto y los ensayos estén revisados. Toda migración será nueva y seguirá el flujo del proyecto.

## Estado de verificación

- Requisito de evidencia: **CONFIRMADO por Miguel**.
- Reapertura: **CONFIRMADO por Miguel**, opción 1, hechos nuevos desde la reapertura.
- Atención inmediata: **CONFIRMADO por Miguel**, opción 1, contacto presencial, cita inmediata y asistencia durante la atención.
- Guía perceptible para el analista: **REQUISITO CONFIRMADO**; diseño de acciones, estados y mensajes propuesto en el tablero y esta nota.
- Concepto del flujo: previamente validado. **Corrección posterior de Miguel:** los bocetos no estaban adaptados al CRM; se debe aprovechar el cierre de acciones y el paso a la siguiente existentes. Pantallas anteriores archivadas; propuesta corregida pendiente de revisión.
- Plan solicitado de frontend/backend: cinco fases sincronizadas en FigJam y Figma Design, con contrato orientativo, componentes/comandos actuales y criterios de aceptación. Código de producto sin cambios por esta tarea.
- Verificación de la corrección: **PASS** en capturas del diagrama `11:117`, fases `17:117` y cierre editable `13:16`. Se corrigieron las alturas de filas del formulario; sin textos desbordados en la inspección final, sin imágenes aplanadas y con Plus Jakarta Sans. **PASS** en cinco fases, JSON orientativo, rutas documentadas y formato de la nota. Esta revisión visual no equivale a aprobación del usuario ni a una prueba del CRM.
- Evidencia de código: inspeccionadas la entrada del formulario, la confirmación SQL de referencia y la relación asistencia → tarea → ciclo. Se complementó la inspección de la nota de mapa con consultas de solo lectura de definiciones vivas de autorización de persona y protecciones de alta del lead.
- Tests de la regla nueva: **NOT RUN**, todavía no hay implementación. Las 222 pruebas de la nota anterior verifican el comportamiento actual, no esta propuesta.
- Revisión secundaria: recibida mediante `scripts/claude-review`, **CHANGES_REQUESTED**, confianza media. Se incorporaron las precisiones de diseño siguientes; no se presenta como aprobación de una implementación ni de su activación.

## Evaluación de la revisión secundaria

- **Aceptado:** cubrir la retoma de borradores y la operación de acceso, exigir coherencia entre tarea y asistencia, diseñar una acción explícita para cita inmediata si Miguel la permite, y probar confirmación concurrente con deshacer/cancelar.
- **Parcial:** hace falta asegurar pertenencia al ciclo, pero las citas ya tienen `crm.tarea_sla_contexto.ciclo_n`. La actividad de asistencia guarda la tarea en `20260907025220_crm_sla_comandos_recibos.sql:525`; el vínculo al ciclo lo crea `private.trg_sla_tarea_contexto` en `20260907024903_crm_sla_nucleo_operativo_escritura.sql:411`. No se acepta la conclusión general de que las citas carecen de ciclo.
- **Parcial:** la concurrencia merece diseño y pruebas. `crm.confirmar_inversion_revisada_fn` toma la solicitud en `20260919161807_crm_conversion_inversion_unificada.sql:1232`, pero previamente llama a autorización. El cuerpo vivo de `private.inversion_persona_autorizada_para` toma bloqueos de jerarquía, documentos y persona. La evidencia no demuestra por sí sola un interbloqueo actual ni permite imponer un orden nuevo sin revisar la cadena completa.
- **Parcial:** se mantiene el inventario de inserciones y rutas privilegiadas. Se descarta atribuir la protección de alta terminal solo al frontend: también existen las dos guardas SQL verificadas arriba. No se ha demostrado un bypass autenticado.

Las referencias SQL anteriores son relativas a `CRM-Avance-Corp/supabase/migrations/`. La consulta de producción fue exclusivamente de catálogo; no incluyó cambios ni datos personales.

Relacionadas: [[Etapas del CRM - mapa de funcionamiento (2026-10-12)]] · [[Pipeline - columna Gestionado (2026-10-01)]] · [[Gestion Diaria - resultado separado del descarte (2026-09-21)]] · [[Base para gestion del analista - F0 y decisiones (2026-10-01)]] · [[Inicio]].
