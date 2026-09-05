---
tags: [crm, gerencia, metricas, inventario, citas, operacion]
requerimiento: REQ-GER-MET-001
punto: 1
estado: documentado
fecha: 2026-09-04
---

# Inventario de indicadores de Gerencia — Citas y operación

Parte de [[Inventario de indicadores de Gerencia - Contrato de lectura]], exclusivamente punto 1 de [[Plan de correccion de metricas de Gerencia - requerimiento vigente]]. Complementa [[Inventario de indicadores de Gerencia - Comercial]] y [[Inventario de indicadores de Gerencia - Cartera y configuracion]]. Antecedentes: [[Auditoria de metricas de Gerencia - hallazgos y plan 2026-09-04]], [[Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)]], [[Terminologia de citas en el CRM]] e [[Inicio]].

Describe la implementación **actual**, incluidos los nombres que no expresan exactamente su población. No aprueba esos nombres como semántica comercial ni propone sustituir el servidor. No se modificó código, SQL, datos, permisos, núcleos ni pantallas; no hubo commit, push ni deploy de esta labor.

## Evidencia y forma de lectura

- Baseline de aplicación: HEAD `2742bf8`. Al cerrar la lectura el repositorio pasó por trabajo ajeno a `ecbb7b9`; el árbol `CRM-Avance-Corp/app` permanece `ed23ef494093755055f1b236a37d9830fe3220f9`. Las rutas/líneas siguientes corresponden a ese mismo árbol.
- CodeGraph fue la primera herramienta de ubicación; las lecturas dirigidas complementaron los símbolos que no resolvió. Se leyeron Inicio, requerimiento, auditoría y decisiones F6.
- Las funciones productivas citadas se comprobaron con `pg_get_functiondef` en transacciones explícitas de solo lectura el 2026-09-04. Las huellas al final permiten distinguir definición viva de una migración antigua.
- Prefijo de todas las rutas de evidencia: **`CRM-Avance-Corp/`**. Las referencias indican archivo y línea del árbol de aplicación; los nombres abreviados se resuelven con la ruta de su sección.
- Cada registro se interpreta con **el contrato de su sección**: allí constan fuente, rango, ámbito, exclusiones y disponibilidad comunes; la fila identifica campo, pregunta y transformación particular. Una dimensión (día, etapa, modalidad, moneda o responsable) no cambia la unidad de la medida.
- Se cuentan indicadores visibles y datos cuantitativos descriptivos. Los campos de formulario editables, tamaños configurables de página y metadatos como ID o versión no son resultados empresariales nuevos. Los denominadores/metadatos necesarios para interpretar un indicador sí se explican.
- Rutas verificadas: `App.tsx:62`, `screens/hoy.tsx:16`, `screens/gerencia.tsx:12`, `screens/equipo.tsx:1349`. Gerencia usa **EquipoEmpresa**, no EquipoSupervisor. El ranking de las tres pestañas de EquipoSupervisor no es otro ranking activo de Gerencia. Repartir sí ofrece su propio historial; Gerencia no tiene la ruta de derivaciones de equipo del supervisor (`lib/roles.ts:76`).

## A. Citas: contrato S1

Cadena: `crm.metricas_reuniones_fn(p_desde,p_hasta)` → `private.metricas_reuniones_implementacion` → `private.citas_episodios`; `data/crm-api.ts:3789` valida `MetricasReunionesSchema` y el período solicitado → `data/crm-queries.ts:714`/`screens/hoy/gerencia.tsx:282` → `screens/hoy/reuniones-gerencia.tsx`. El alias en Resumen usa **la misma consulta**, no otro cálculo (`resumen-gerencia.tsx:167`, `:427`, `:462`).

**Unidad y reloj:** una tarea activa tipo `reunion` por `tarea_id`, cuya **fecha prevista `vence_en`** pertenece al rango inclusivo de días de Lima, implementado como [inicio, día posterior). No son leads únicos, llegadas ni fecha de creación/finalización. El corte de vencimiento usa `now()` del servidor. No se envía filtro de origen de conversión. Ámbito global de Gerencia; responsable = `tarea.vendedor_id`, supervisor/nombre del roster consultado, origen del lead actual. Una tarea con `lead_id=null` puede contar como cita, pero no entra en conversión por lead.

**Estados:** pactadas incluye todas las filas, también canceladas. Realizada = estado `completada`; no-show = `no_show`; no concretada = no-show + cancelada por asesor. Cancelada sistema = cancelada cuyo `cancelada_por` es distinto de asesor, incluido nulo. Reprogramada = **estado** `reprogramada`, no suma del contador de movimientos. Pendiente de cierre = pendiente y vencida; futura = pendiente y posterior al corte.

**Tres porcentajes distintos:**

- Realización global y por modalidad = realizadas / (debieron ocurrir − canceladas sistema vencidas − reprogramadas vencidas), ×100, redondeo servidor a un decimal. Denominador no positivo → null.
- Asistencia = realizadas / (realizadas + no-show), ×100, un decimal; denominador cero → null.
- Efectividad por analista usa el divisor de realización y **además excluye canceladas por otro asesor** cuando el autor de cancelación difiere del responsable de la tarea. No sustituirlo por el porcentaje global.

**Conversión de citas:** la implementación selecciona la última cita realizada del rango por cada lead no nulo (orden `vence_en DESC,id DESC`). Busca un cierre no anulado del núcleo cuya fecha sea igual o posterior a esa cita; el horizonte alcanza hasta el mayor entre fin del rango y ahora. Numerador = leads de ese conjunto con cierre; divisor = leads únicos reunidos. No es conversión comercial ponderada, contratos únicos ni todos los clientes de la empresa. El payload llama `contratos` a ese numerador; `clientes` contiene el mismo conteo. Modalidad de atribución = última cita realizada elegida.

**Capital de citas:** para los leads anteriores con cierre, consulta stock de `private.capital_episodios` sin recorte de fechas del capital, vinculado por cliente/perfil o cierre de cooperativa del lead. Suma sólo la moneda indicada en el lead. No equivale a capital captado en el rango de citas. Rigen las exclusiones del núcleo de capital, sin añadir anulación general de cooperativas.

**Disponibilidad:** contrato inválido o período distinto produce error, no cero. Carga inicial muestra skeleton; sin datos válidos no se fabrican KPI; pactadas=0 muestra vacío. Error con datos previos puede conservar la última fotografía y aviso (`reuniones-gerencia.tsx:49`, `:108`). `pct(null)` muestra “—” en tarjetas/tabla, pero el gráfico por origen transforma null en 0. El esquema `lib/metricas-reuniones.ts:21` valida campos conocidos y descarta campos extra; no preserva automáticamente nuevos campos explicativos. La API actual no entrega por modalidad todos los descuentos vencidos del denominador.

## Indicadores S1



| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O01 | Pactadas; «de N pactadas»; Resumen: «con cita pactada» | ¿Cuántas citas registradas tienen fecha prevista en el rango? `resumen.pactadas`, directo. | Citas/eventos, S1. Alias exacto entre cabecera, tarjeta y Resumen. `reuniones-gerencia.tsx:111,117`; `resumen-gerencia.tsx:168,462`. |
| O02 | Realizadas; Citas realizadas; Resumen: Citas | ¿Cuántas citas del rango están completadas? `resumen.realizadas`, directo. | Citas/eventos, S1. No es el avance inferido «Leads que llegaron a cita» de conversión. `reuniones-gerencia.tsx:111,118`; `resumen-gerencia.tsx:167,427,462`. |
| O03 | Asistencia | ¿Qué proporción de realizadas o no-show acabó realizada? `resumen.pct_asistencia`, porcentaje servido. | %, divisor de asistencia S1; null→—. `reuniones-gerencia.tsx:112`. |
| O04 | No concretadas | ¿Cuántas citas quedaron no-show o canceladas por asesor? `resumen.no_concretadas`. | Citas, excluye canceladas sistema; alias cabecera/tarjeta. `reuniones-gerencia.tsx:112,119`. |
| O05 | Terminan en cliente | ¿Qué proporción de los leads con cita realizada elegida tiene cierre posterior? `conversion.conversion_contrato_pct`. | % de leads únicos, horizonte de seguimiento S1; no ponderación comercial. Alias cabecera/tarjeta. `reuniones-gerencia.tsx:112,121`. |
| O06 | N próximas | ¿Cuántas citas siguen pendientes y vencen después del corte? `resumen.programadas_futuras`. | Citas dentro del rango S1, no todas las futuras de Agenda. `reuniones-gerencia.tsx:117`. |
| O07 | Porcentaje bajo Realizadas | ¿Cuántas de las citas exigibles ajustadas se realizaron? `resumen.pct_realizacion`. | % servido; divisor ajustado global S1, no pactadas ni divisor de asistencia. `reuniones-gerencia.tsx:118`. |
| O08 | N no asistieron | ¿Cuántas citas están en no-show? `resumen.no_show`. | Citas; subconjunto de No concretadas. `reuniones-gerencia.tsx:119`. |
| O09 | Reprogramadas | ¿Cuántas citas tienen estado reprogramada en el rango? `resumen.reprogramadas`. | Citas, no número de veces movidas; S1. `reuniones-gerencia.tsx:120`. |
| O10 | N sin resultado | ¿Cuántas citas vencidas siguen pendientes? `resumen.pendientes_cierre`. | Citas; no incluye futura, cancelada ni reprogramada. `reuniones-gerencia.tsx:120`. |
| O11 | N clientes | ¿Cuántos leads reunidos seleccionados presentan cierre posterior? `conversion.contratos`. | Leads únicos convertidos del conjunto S1, pese al nombre técnico contratos; no IDs de contrato o perfil únicos. `reuniones-gerencia.tsx:121`. |
| O12 | Presencial vs. virtual — Pactadas | ¿Cuántas citas se pactaron por modalidad? `modalidades[].pactadas`, barras. | Citas por modalidad, incluido sin clasificar cuando presente; S1. `reuniones-gerencia.tsx:89`. |
| O13 | Presencial vs. virtual — Realizadas; numerador N de M | ¿Cuántas se completaron por modalidad? `modalidades[].realizadas`, barras y tarjeta. | Citas por modalidad, alias del mismo campo en ambas ubicaciones. `reuniones-gerencia.tsx:89,126`. |
| O14 | Modalidad — denominador «de M» | ¿Cuántas debieron ocurrir por fecha prevista? `modalidades[].debieron_ocurrir`. | Citas vencidas brutas; NO descuenta canceladas sistema/reprogramadas. Es distinto del divisor del porcentaje adyacente. `reuniones-gerencia.tsx:126`. |
| O15 | Modalidad — porcentaje de realización | ¿Qué fracción ajustada se completó en cada modalidad? `modalidades[].pct_realizacion`. | % servido, fórmula por modalidad S1; null→—. `reuniones-gerencia.tsx:126`. |
| O16 | Modalidad — A clientes | ¿Qué proporción de leads reunidos en esa última modalidad tuvo cierre posterior? `modalidades[].conversion_contrato_pct`. | % de leads, S1 conversión; no porcentaje de tareas. `reuniones-gerencia.tsx:126`. |
| O17 | Modalidad — Capital invertido, soles | ¿Qué stock en PEN se vincula a los leads reunidos que cierran? `modalidades[].capital_pen`. | PEN, capital stock S1 sin ventana del capital; se muestra también 0. `reuniones-gerencia.tsx:126`. |
| O18 | Modalidad — Capital invertido, dólares | Misma pregunta para USD: `modalidades[].capital_usd`. | USD independiente, sin TC; sólo se dibuja si >0. `reuniones-gerencia.tsx:126`. |
| O19 | Citas que terminan en cliente — barras por origen | ¿Qué porcentaje de leads reunidos de cada origen tiene cierre posterior? `origenes[].conversion_contrato_pct`. | % de leads S1; ordenar usa null como −1 y dibujar usa null→0, diferencia frente a tarjetas. `reuniones-gerencia.tsx:94,101`. |
| O20 | Resultado final | ¿Cuántas citas realizadas quedaron en cada resultado? `resultados[].cantidad`. | Citas realizadas por `resultado`; nulo se clasifica sin_clasificar, no todas las pactadas. `reuniones-gerencia.tsx:131`. |
| O21 | Resultados por analista — Pactadas | ¿Cuántas citas del rango están atribuidas al responsable? `responsables[].pactadas`. | Citas por dueño de tarea, no dueño actual del lead. `reuniones-gerencia.tsx:72`. |
| O22 | Resultados por analista — Realizadas | ¿Cuántas citas de ese responsable se completaron? `responsables[].realizadas`. | Citas por responsable de tarea; S1. `reuniones-gerencia.tsx:72`. |
| O23 | Resultados por analista — Sin resultado | ¿Cuántas citas vencidas del responsable siguen pendientes? `responsables[].pendientes_cierre`. | Citas por responsable; S1. `reuniones-gerencia.tsx:72`. |
| O24 | Resultados por analista — Efectividad | ¿Qué fracción exigible ajustada de cada responsable se realizó? `responsables[].pct_realizacion`. | % servido con exclusión adicional por cancelador ajeno; null→—. `reuniones-gerencia.tsx:72`. |

## B. Pipeline y Leads — contratos S2/S3


**S2, resumen del servidor:** `crm.resumen_cartera_fn` → `data/crm-api.ts:3826` (esquema y ventana de 45 días) → `data/use-resumen-cartera-operativo.ts:26` → Pipeline/Leads. Gerencia global, propietario actual, sin filtro de origen ni los filtros visuales del listado. Universo de inventario: leads activos en base (no soft-delete); convertidos sólo durante **45 días desde convertido_en**, demás etapas sin esa ventana. “Abierto” excluye convertido/descartado; asignado = abierto con vendedor; parqueado = abierto sin vendedor. No se cambia esa ventana.

**Excepción temporal explícita:** `totales.convertidos` no procede de contar el inventario de 45 días: utiliza el núcleo de conversión para **cierres de leads del mes calendario actual de Lima**, no operaciones de cartera, sin anular, elegibles en su clasificación de no referidos/referidos. El contador de etapa `embudo[convertido].n` sí es inventario de 45 días. Son indicadores distintos aunque ambos digan Convertidos.

Capital S2 = suma de `monto_estimado` de los leads abiertos, por moneda, nulo→0 en servidor. `capitalPrincipal` elige la moneda principal (USD si no hay PEN; PEN en otro caso), no convierte. Error de resumen incluso durante refetch → métricas null/“—” y aviso, sin recálculo desde el listado.

**S3, listas locales:** Pipeline consume el store: `data/crm-api.ts:557` consulta `crm.leads`, orden actualizado DESC/id ASC, ventana de convertidos 45 días y `.limit(2000)`. Filas inválidas se omiten y se registran; alcanzar el tope se avisa en observabilidad, no certifica totalidad (`:268,572,582`). Las reglas de acceso/actividad provienen de RLS/ámbito y luego filtros locales. En cambio **Leads** (`screens/cartera.tsx:56`) usa `useCarteraPaginada` con cursor y filtros enviados al servidor; las tarjetas siguen leyendo S2, no la página. No se verificó el límite real PostgREST de producción: ni 2000 solicitado ni el 1000 de configuración local prueban completitud remota.

**SLA:** `crm.estado_sla_leads_fn` → `data/crm-config-api.ts:508` → `useEstadoSlaLeads` → `useEstadoSlaOperativo` → `lib/estancamiento.ts:46`. Usa foto de etapa sellada, no política actual para reconstruir el pasado. Si no hay foto válida o la etapa difiere, omite color/plazo y usa referencia operativa de espera (última actividad disponible o creación, máxima con tenencia). La ausencia de SLA no se muestra como plazo cero.


| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O25 | Pipeline — Leads activos | ¿Cuántos leads abiertos tienen analista actual? S2 `totales.asignados`. | Leads; inventario actual, no captación del rango. `screens/pipeline.tsx:320`. |
| O26 | Pipeline — Capital en proceso | ¿Qué capital estimado tienen los abiertos asignados? S2 `capital.asignado.pen/usd` → `capitalPrincipal`. | Dinero por moneda sin TC; principal y desglose de la misma medida. `pipeline.tsx:316,325`. |
| O27 | Pipeline — Propuestas | ¿Cuántos leads están hoy en propuesta enviada? S2 `embudo[propuesta_enviada].n`. | Leads asignados y sin asignar, no sólo el universo de la tarjeta Leads activos. `pipeline.tsx:318,329`. |
| O28 | Pipeline/Leads — Convertidos; chip terminal Pipeline | ¿Cuántos cierres de leads registra el núcleo este mes? S2 `totales.convertidos`, directo. | Leads cerrados del mes actual, no stock 45 días ni contador local filtrado. Alias exacto entre tarjetas/chip. `pipeline.tsx:330,529`; `cartera.tsx:96`. |
| O29 | Pipeline — Descartados, chip terminal | ¿Cuántos leads visibles están descartados actualmente? S2 `totales.descartados`. | Leads de inventario sin recorte mensual; no historial de descartes. `pipeline.tsx:540`. |
| O30 | Pipeline — Por repartir | ¿Cuántos abiertos sin vendedor hay en el store del ámbito? S3 filtro vendedor nulo y no terminal → length. | Leads locales; incluye bandejas de supervisor, no necesariamente cola global. No usa resumen de reparto. `pipeline.tsx:212`. |
| O31 | Pipeline — número por columna | ¿Cuántos leads descargados cumplen etapa y filtros del tablero? S3 `enCol.length`. | Leads locales filtrados; no garantiza el total servidor. `pipeline.tsx:226,404`. |
| O32 | Pipeline — capital por columna | ¿Qué capital estimado suman esos leads de columna? S3 `capitalPorMoneda(enCol)`. | PEN/USD separados de filas locales filtradas; no alias de capital global S2. `pipeline.tsx:404`. |
| O33 | Pipeline — tiempo, color y plazo de etapa | ¿Cuánto lleva el episodio vigente y qué plazo sellado tiene? SLA `etapa_iniciada_en,etapa_limite_en,etapa_objetivo_minutos` → `semaforoEstancamiento`. | Días/horas/minutos de reloj vivo; ámbar al límite, rojo al límite más duración. Tooltip informa versión/aproximado. Sin foto usa espera operativa y sin color; no es SLA inventado. `pipeline.tsx:143,463`; `lib/estancamiento.ts:46`; `lib/inteligencia.ts:397`. |
| O34 | Leads — Total leads; total del segmento | ¿Cuántos leads hay en el inventario visible definido por S2? `totales.vivos`. | Leads, incluye abiertos/descartados/convertidos en ventana; no sigue búsqueda ni filtros de tabla. `cartera.tsx:87,161`. |
| O35 | Leads — Activos | ¿Cuántos leads del inventario están abiertos? S2 `totales.abiertos`. | Leads con o sin vendedor; distinto de Pipeline Leads activos. `cartera.tsx:95`. |
| O36 | Leads — Capital en juego | ¿Cuánto capital estimado tienen todos los abiertos? S2 `capital.asignado + capital.parkeado` por moneda → `capitalPrincipal`. | PEN/USD independientes, incluye no asignados; no inversión confirmada. `cartera.tsx:82`. |
| O37 | Leads — segmento por etapa | ¿Cómo se distribuye el inventario entre las seis etapas? S2 `embudo[].n`. | Leads por etapa actual; convertido es stock 45 días, no cierres mensuales de la tarjeta Convertidos. `cartera.tsx:99,161`. |
| O38 | Leads — N cargados / N resultados | ¿Cuántos resultados acumuló la consulta paginada con filtros? `useCarteraPaginada.items.length`. | Filas descargadas: con hasMore se dice cargados; al agotarse, resultados. No total global S2. `cartera.tsx:56,205`. |
| O39 | Pipeline — intervalo/páginas por columna | ¿Qué parte del conjunto local filtrado se muestra? Paginador sobre `enCol`. | Leads e índices de página locales; no páginas servidor. `pipeline.tsx:488,502`. |

## C. Agenda — contrato S4


La Agenda no es el reporte de citas: `data/crm-api.ts:1862` lee `crm.tareas` activas **pendientes** de todos los tipos, orden vence/id y límite solicitado 2000. Filas inválidas se omiten; no hay total agregado ni prueba de completitud. `screens/agenda.tsx:902` conserva tareas cuyo lead está en el ámbito local, o de postventa con perfil no nulo; `lib/agenda-derivada.ts:87` convierte cada tarea a evento. Una tarea equivale a un evento. Vencida = `vence_en < ahora`; fechas de calendario en Lima.

Tarjetas superiores se calculan antes de filtros de búsqueda/tipo/estado/etapa y no dependen del mes/semana visibles (`agenda.tsx:81,916`). “Hoy” combina todas las vencidas con las del día, no sólo tareas fechadas hoy. Los contadores inferiores sí siguen los filtros locales. La agrupación por persona usa propietario **actual del lead** antes del vendedor de tarea, después bandeja/supervisor y sin responsable (`lib/agenda-vistas.ts:221`); puede diferir de atribución de Citas S1.

Sin historial completado en esta descarga, “Citas” significa citas pendientes, no pactadas ni realizadas. Los vacíos de un conjunto filtrado válido sí pueden ser cero; no se debe leer su length como recuento histórico completo. Error de carga depende del estado del store y no convierte el conjunto parcial en total autoritativo.


| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O40 | Agenda — Pendientes / toda la agenda | ¿Cuántas tareas pendientes descargadas entran en el ámbito? `eventos.length`. | Tareas locales S4, antes de filtros. `agenda.tsx:81,916`. |
| O41 | Agenda — Citas | ¿Cuántas tareas pendientes son de tipo reunión? `eventos.filter(tipo=reunion).length`. | Tareas/citas pendientes S4, no O01. `agenda.tsx:81`. |
| O42 | Agenda — Llamadas | ¿Cuántas tareas pendientes son llamadas? `eventos.filter(tipo=llamada).length`. | Tareas locales S4, antes de filtros. `agenda.tsx:81`. |
| O43 | Agenda — Vencidas | ¿Cuántas tareas pendientes ya pasaron su fecha prevista? `eventos.filter(vencida).length`. | Tareas locales de cualquier fecha anterior; antes de filtros. `agenda.tsx:81`. |
| O44 | Agenda — Hoy, contador de pestaña | ¿Cuántas tareas filtradas son de hoy o están vencidas? `hoyEventos.length`. | Tareas locales filtradas; puede incluir días pasados. `agenda.tsx:933,1105`. |
| O45 | Agenda — Todos, contador de pestaña | ¿Cuántas tareas cumplen los filtros activos? `filtrados.length`. | Tareas locales filtradas, no el total superior sin filtros. `agenda.tsx:918,1109`. |
| O46 | Agenda — distribución por tipo | ¿Cuántas tareas de cada tipo cumplen filtros? Reducción de `filtrados` por tipo. | Tareas por tipo del conjunto filtrado, no cierres ni eventos históricos. `agenda.tsx:962`. |
| O47 | Agenda — número por día, semana/mes y cabecera del día | ¿Cuántas tareas filtradas vencen ese día Lima? Agrupaciones `n` del día. | Tareas pendientes por fecha prevista; mismos eventos al cambiar presentación. `agenda.tsx:719,975,986,1314`. |
| O48 | Agenda — vencidas por día | ¿Cuántas tareas de ese día filtrado están vencidas? Agrupaciones `v`. | Tareas pendientes; reloj vivo local, no sólo días previos. `agenda.tsx:975,986`. |
| O49 | Agenda — N tareas por persona | ¿Cuántas tareas filtradas pertenecen a esa persona/grupo visible? `grupo.items.length`. | Tareas; agrupación S4 con dueño actual del lead. `agenda.tsx:1435`. |
| O50 | Agenda — N vencidas por persona | ¿Cuántas tareas del grupo están vencidas? `grupo.nVencidas`. | Tareas por persona, misma atribución S4. `agenda.tsx:1439`. |
| O51 | Agenda — movida ×N | ¿Cuántos movimientos de reprogramación registra esta tarea? `tarea.reprogramaciones`. | Movimientos de una tarea, no tareas en estado reprogramada de O09. `agenda.tsx:279`. |
| O52 | Agenda — Confirmada / Sin confirmar | ¿Existe fecha de confirmación registrada para esta tarea? `confirmada_en != null`. | Estado binario descriptivo, no asistencia registrada ni total confirmado. `agenda.tsx:269`. |
| O53 | Agenda — paginación por persona | ¿Qué grupos de personas del listado filtrado se muestran? Paginador de grupos. | Personas/grupos, no número de tareas. `agenda.tsx:948`. La cantidad de filtros activos en `:923` es control de interfaz, no medida de negocio. |

## D. Repartir — contratos S5/S6/S7


`screens/repartir.tsx:795,826` ofrece Distribución, Cola, Historial y Descartados. Sus filtros/relojes no son el período de Gerencia.

**S5 Distribución:** `crm.panel_distribucion_reparto(p_supervisor,p_analista,p_origen,p_solo_activos=true)` → `data/crm-api.ts:1084` → `components/app/panel-distribucion-reparto.tsx`. Selecciona roster activo de supervisores/analistas. **“Activo” aquí significa `lead.activo=true`, no excluir etapas terminales.** No hay rango de llegada. Analista = leads cuyo vendedor actual es él. Supervisor = conteo de su `asignado_supervisor_id` **sin exigir vendedor nulo** + conteos de analistas directos; el total global usa UNION de IDs. No dar por probado que sumar todos los conteos de supervisor produce IDs únicos. Filtros se envían al servidor. Error con foto previa conserva foto + advertencia; error inicial muestra error (`:57,129`).

**S6 Entregas por fecha:** `crm.reporte_derivaciones_coordinacion_fn(desde,hasta)` → `data/crm-api.ts:3932` valida esquema, período y sumas → `components/app/reporte-diario-derivaciones.tsx:171` filtra filas por supervisor/analista/origen → reduce resumen. Rango por `lead_asignaciones.asignado_en`, días Lima. Cuenta **episodios de entrega**, repetibles para el mismo lead: entrega/reasignación por supervisor de origen, excluyendo reapertura de parqueado al mismo supervisor según contrato. Nombres de personas se resuelven con perfiles; dimensiones de entrega/origen son la foto del episodio, no dueño/origen actual. Rango predeterminado ayer, selector propio de fechas; se exige a lo sumo 366 días inclusivos. Error invalida datos; no hay fallback al store. El reporte habla de gestión de reparto: no sustituye captación comercial.

**S7 Cola:** agregados `crm.resumen_reparto_fn` → `data/crm-api.ts:4092` → resumen operativo de `repartir.tsx:304`. Universo actual: activo, vendedor nulo, supervisor asignado nulo, cuatro etapas abiertas, `no_contactar=false`, no persona vetada. No recorte temporal ni Landing/Formulario obligatorio. Suma estimado con nulo→0 por moneda; espera = días enteros desde el lead más antiguo, piso y mínimo 0. Error del agregado → “—”/aviso sin sustituirlo por length local.

Lista independiente: `crm.leads_por_repartir` → `private.leads_por_repartir_implementacion` → `data/crm-api.ts:944`. Además consulta la bandera de resolver en puertas y veto de persona canónica cuando está activa. Orden FIFO por creación. Esta lectura no suministra total agregado de completitud; validación puede omitir filas. Búsqueda/origen/posible crédito y paginación se aplican localmente. El texto de lista puede diferir del agregado porque son llamadas/poblaciones de lectura independientes.

**Historial:** `crm.historial_derivaciones(p_limite,cursor)` → `data/crm-api.ts:966` → `components/app/historial-derivaciones.tsx`. Página de movimientos ordenada por cursor fecha/actividad; búsqueda sólo en página descargada, no en todo historial. No es reporte global de asignaciones ni llegadas.

**Descartados de cola:** `crm.leads_descartados` → `private.leads_descartados_implementacion` → `data/crm-api.ts:1228`. Leads activos actualmente descartados, sin vendedor/supervisor, descartados por miembro Coordinación/Gerencia, con perfil existente y `descartado_en > statement_timestamp()-30days`, orden descendente, **LIMIT 200**. “Últimos 30d” es ventana móvil de instantes, no mes calendario. No es todo descarte comercial ni el ledger histórico de Base para gestión. El dato válido puede ser 0; error/carga se presentan por separado. Filas inválidas se omiten en adaptador.


| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O54 | Distribución — N activos | ¿Cuántos IDs de lead hay en la población global seleccionada? S5 `total_leads`. | Leads únicos globales del RPC, no sólo abiertos. `panel-distribucion-reparto.tsx:143`. |
| O55 | Distribución — leads por supervisor | ¿Qué carga retorna para cada supervisor y sus analistas? S5 `supervisores[].total_leads`. | Conteo compuesto de asignación actual S5; no una llegada atribuida al primer receptor. `panel-distribucion-reparto.tsx:221`. |
| O56 | Distribución — leads por analista | ¿Cuántos leads activos en base tiene ese analista actual? S5 `analistas[].total_leads`. | Leads por propietario actual, incluso terminales si activo=true. `panel-distribucion-reparto.tsx:264`. |
| O57 | Distribución — paginación de supervisores/analistas | ¿Cuántas filas de roster pasan los filtros y qué página se muestra? Arrays de supervisores y analistas. | Personas por tipo, no leads; paginación local de diez filas. `panel-distribucion-reparto.tsx:230,273`. |
| O58 | Entregas — Leads entregados | ¿Cuántos episodios de entrega cumplen rango y filtros? S6 suma de `dias[].entregas[].derivados`. | Entregas repetibles de leads, no leads nuevos únicos. `reporte-diario-derivaciones.tsx:183,323`. |
| O59 | Entregas — Analistas | ¿A cuántos analistas distintos se entregó según los filtros? Set de `analista_id` con entregas. | Analistas históricos con entrega en rango S6, no roster activo entero. `reporte-diario-derivaciones.tsx:183,324`. |
| O60 | Entregas — Orígenes | ¿Cuántos valores de origen aparecen en las entregas filtradas? Set de origen. | Categorías distintas del snapshot S6, no número de leads por origen. `reporte-diario-derivaciones.tsx:183,325`. |
| O61 | Entregas — Días con entregas | ¿En cuántos días del rango hubo al menos una entrega filtrada? Días con total >0. | Días calendario Lima; los días sin entrega no incrementan. `reporte-diario-derivaciones.tsx:183,326`. |
| O62 | Entregas — Leads en tabla | ¿Cuántas entregas hubo ese día al analista, origen y supervisor? S6 `entrega.derivados`. | Episodios por cuatro dimensiones; la suma filtrada alimenta el total superior. `reporte-diario-derivaciones.tsx:372,392`. La paginación es de días, no de leads. |
| O63 | Cola — Por repartir | ¿Cuántos leads elegibles tiene la cola global? S7 `cola.total`. | Leads actuales sin ambos responsables y sin veto, agregado servidor sin filtros de lista. `repartir.tsx:304`. |
| O64 | Cola — Capital en juego (PEN) | ¿Qué estimado suma la cola global en soles? S7 `cola.capital.pen`. | PEN; servidor clasifica moneda distinta de USD en PEN. Error→—. `repartir.tsx:311`. |
| O65 | Cola — Capital en juego (USD) | ¿Qué estimado suma la cola global en dólares? S7 `cola.capital.usd`. | USD separado, no TC. `repartir.tsx:317`. |
| O66 | Cola — Espera más larga | ¿Cuántos días enteros lleva el lead más antiguo elegible? S7 `cola.espera_max_dias`. | Días desde creación, no entrega/asignación. Cola vacía muestra — aunque campo servidor sea 0. `repartir.tsx:323`. |
| O67 | Cola — N en espera / X de N | ¿Cuántas filas descargadas hay y cuántas pasan filtros? Lista S7 `cola.length`/`colaFiltrada.length`. | Leads locales antes/después de filtros, sin garantía de igualdad con agregado O de cola. `repartir.tsx:352`. |
| O68 | Cola — Posible crédito | ¿Cuántos leads descargados tienen clasificacion_auto posible_credito? `contarMarcados(cola)`. | Leads locales; no lee `resumen.cola.posible_credito` aunque el servidor lo ofrezca. `repartir.tsx:424`. |
| O69 | Historial — Mostrando N movimientos | ¿Cuántas filas tiene la página descargada? `filasPagina.length`. | Movimientos de esa página; el contador no es total histórico ni cuenta solamente coincidencias de búsqueda. `historial-derivaciones.tsx:144,204`. |
| O70 | Historial — monto de cada movimiento | ¿Qué estimado/moneda retorna la fila de historial? `monto_estimado,moneda`, formato dinero. | Estimado descriptivo de la fila; fecha mostrada = `derivado_en`, no captación de capital. `historial-derivaciones.tsx:185,187`. |
| O71 | Descartados — N · últimos 30d | ¿Cuántos descartados de cola devolvió y validó la llamada? `lista.length`. | Leads elegibles de ventana móvil S7, **máximo servidor 200**, no todo historial. `repartir.tsx:688`; `crm-api.ts:1228`. |

## E. Base para gestión y carpetas — contrato S8


`screens/rescate-descartados.tsx:249` y `screens/rescate-carpeta.tsx:4` reutilizan una pantalla en modo carpeta. Servidor: `crm.rescate_descartes_meses` y `crm.rescate_descartes_mes(p_mes)` → `data/crm-api.ts:1270,1285`. Universo = episodios de `crm.lead_asignaciones` con resultado descartado y `resultado_en` no nulo; mes por fecha de ese resultado en Lima. **Unidad episodio, no lead único**. Incluye historial aunque el estado actual haya cambiado, no sólo leads activos.

Pendiente/recuperable exige hoy lead activo, etapa descartado, que `lead.descartado_en` coincida null-safe con el resultado del episodio, motivo distinto de datos_invalidos y no_contactar no verdadero. Detalle `puede_rescatar` aplica la misma elegibilidad. Si no es recuperable y existe una asignación posterior al descarte, `estado_rescate='rescatado'`; en otro caso historial. No demuestra que se haya repartido mediante el botón de esta pantalla.

Los meses provienen del agregado de episodios; `construirMeses` añade meses sin filas con total/pendientes=0 (`:96,275`). Carpetas se agrupan en frontend; los filtros son locales sobre los episodios descargados del mes. Montos/orígenes/categoría/motivo y fecha del episodio son históricos; algunos descriptores del lead/nombre de persona se unen a datos actuales. Los adaptadores omiten filas inválidas; la consulta del detalle añade joins de perfil, por lo que no debe presuponerse identidad total↔detalle sin validar integridad.

Disponibilidad actual desigual: mosaico principal muestra carga/error/vacío (`:760`); la rama de carpeta (`:484` hasta `:650`) **no usa el estado de error/carga del listado para bloquear sus contadores**, de modo que length=0 puede representar un array no disponible, no una confirmación de cero. Se documenta, no se corrige.


| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O72 | Base — total del mes; número de registros en mosaico | ¿Cuántos episodios de descarte ocurrieron ese mes? `mesMeta.total`/`mes.total`. | Episodios de descarte del mes S8, alias cabecera/mosaico; no llegadas ni leads únicos. `rescate-descartados.tsx:669,724`. |
| O73 | Base — por revisar del mes | ¿Cuántos episodios del mes siguen recuperables hoy? `mesMeta.pendientes`/`mes.pendientes`. | Episodios elegibles por estado actual, foto viva de un mes histórico. `rescate-descartados.tsx:673,727`. |
| O74 | Base — número por carpeta; Leads guardados / Registros en carpeta | ¿Cuántos episodios descargados pertenecen a la carpeta? Agrupación local → length. | Episodios aunque la etiqueta diga leads. Cabecera de carpeta repite el mismo conjunto sin filtros de tabla. `rescate-descartados.tsx:342,511,517,769`. |
| O75 | Carpeta — Recuperables; recuperables del mosaico de carpeta | ¿Cuántos episodios de la carpeta tienen puede_rescatar? Filtro booleano → length. | Episodios elegibles S8; no todos los descartes. Alias de conteo por carpeta. `rescate-descartados.tsx:521,795`. |
| O76 | Carpeta — Repartidos | ¿Cuántos episodios de carpeta están marcados estado_rescate=rescatado? Filtro → length. | Episodios con asignación posterior, no contador de asignaciones ni sólo acciones de esta interfaz. `rescate-descartados.tsx:525`. |
| O77 | Carpeta — Historial | ¿Cuántos episodios no son recuperables ni rescatados? Total − recuperables − rescatados. | Episodios locales remanentes, no todo historial de la persona. `rescate-descartados.tsx:529`. |
| O78 | Carpeta — N resultados | ¿Cuántos episodios cumplen los filtros locales de la carpeta? `filtrados.length`. | Episodios filtrados; alimenta paginación local, no total servidor nuevo. `rescate-descartados.tsx:563`. |
| O79 | Carpeta — seleccionar N de página / N de filtro / N seleccionados | ¿Cuántos episodios elegibles se pueden seleccionar o están seleccionados? Página elegible, filtro elegible y Set de IDs. | Contadores de selección de episodios; tres estados de la misma operación, no total de leads únicos ni reparto realizado. `rescate-descartados.tsx:581,582,588`. |
| O80 | Carpeta — capital del registro | ¿Qué monto estimado y moneda quedaron en el episodio de descarte? `episodio.monto_estimado,moneda`. | Dinero histórico estimado por episodio; fecha mostrada = resultado/descarte del episodio. No capital confirmado ni actual. `rescate-descartados.tsx:609,610`. |

## F. Alertas de Gerencia — contrato S9


Cadena existente, **no un núcleo nuevo**: `lib/alertas-provider.tsx:160` pide conversión del mes en curso y mismo corte del mes anterior; toma `objetivos.porVendedor` de `crm.configuracion_metas_fn` (`data/crm-api.ts:773`) y `cumplimientoMetas.porVendedor` del RPC de cumplimiento mensual. `lib/alertas-gerencia.ts:218` deriva avisos a partir de campos servidos, y `lib/alertas-provider.tsx:56` redacta la tarjeta. Campos comerciales/diccionario: [[Inventario de indicadores de Gerencia - Comercial]]. **No sigue el período seleccionado en las otras pantallas de Gerencia.**

Individual: sólo desde cortes 7/15/21/30 (último ajustado a febrero), muestra válida `resueltos>=10`, cumplimiento disponible para todas las metas y meta positiva publicada. `resueltos` es el divisor comercial servido, no “todos los recibidos” por nombre histórico. Meta 0 o fallo → sin meta aplicable, **sin inventar 15%** (`lib/objetivos.ts:180`). Aviso si meta − conversión >=5 puntos; crítico >=10. Global: ambas lecturas con sondas verificadas, divisor >=30 en cada período, caída >=3 puntos; crítico >=5. Porcentajes finitos/no negativos; no se limita conversión ponderada a 100. Brechas redondeadas a dos decimales.

Unidad de campana/listas = **avisos**, no leads/personas. Un aviso por analista y tipo; una caída global. Gerencia no usa reconocimiento de alertas del supervisor. Si no se cumple corte/muestra/meta/sonda, no se crea aviso; **ausencia de aviso no acredita evaluación completa o buen resultado**. Carga/error se exponen en el provider/pantalla; con arrays sin avisos el vacío dice no hay desviaciones, sin desglose de cuántos casos no fueron evaluables (`screens/alertas.tsx:566`). `generadoEn` de la UI toma la consulta de conversión actual, no demuestra mismo instante de todas las fuentes. Seguir el enlace al ranking no fuerza el mismo período (`alertas.tsx:463`).


| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O81 | Campana / Todas / total de alertas | ¿Cuántos avisos activos produjo la derivación de Gerencia? `alertas.length` / `activas.length`. | Avisos S9, no leads; misma colección antes de filtros locales. `lib/alertas-provider.tsx:269`; `screens/alertas.tsx:145,489`. |
| O82 | Alertas — Críticas | ¿Cuántos avisos activos superan el umbral crítico de su tipo? Filtro severidad crítica → length. | Avisos S9, antes de filtros de búsqueda/tipo. `alertas.tsx:502`. |
| O83 | Alertas — Atención | ¿Cuántos avisos activos no son críticos? Total activos − críticos. | Avisos, no cantidad de leads bajo meta. `alertas.tsx:145`. |
| O84 | Alertas — N pendientes activos | ¿Cuántos avisos coinciden con filtros visuales? `filtradas.length`. | Avisos filtrados; puede diferir de campana sin inconsistencia aritmética. `alertas.tsx:515,621`. |
| O85 | Bajo meta — porcentaje actual | ¿Qué conversión mensual servida tiene el analista avisado? `cumplimiento.porVendedor[].conversionReal` → `alerta.actual`. | % comercial, mes en curso y atribución del RPC de cumplimiento, no asistencia de citas. `lib/alertas-gerencia.ts:257`; `lib/alertas-provider.tsx:68`. |
| O86 | Bajo meta — frente a X% | ¿Qué meta publicada aplica al analista? `objetivos.porVendedor[].conversionObjetivo` → `metaConversionAplicable` → `alerta.objetivo`. | % objetivo; 0/error/null no originan aviso individual con objetivo inventado. `alertas-gerencia.ts:253`; `alertas-provider.tsx:68`. |
| O87 | Bajo meta — brecha X pp | ¿Cuántos puntos faltan para la meta? `redondearPp(objetivo-actual)` → `brechaPp`. | Puntos porcentuales, no caída relativa %. Regla S9 5/10. `alertas-gerencia.ts:260`; `alertas-provider.tsx:68`. |
| O88 | Bajo meta — sobre N recibidos (se avisa desde 10) | ¿Qué tamaño de divisor sostiene ese aviso? `cumplimiento.resueltos` → `alerta.muestra`. | Leads que aportan al divisor, no todas las llegadas. El texto recibidos es más amplio que el campo. 10 es umbral, no resultado medido. `alertas-gerencia.ts:276`; `alertas-provider.tsx:59`. |
| O89 | Caída global — porcentaje actual | ¿Qué conversión tiene el núcleo desde inicio de mes hasta hoy? `conversionActual.nucleo.conversion_pct` → `alerta.actual`. | % comercial ponderado del rango MTD S9. `alertas-gerencia.ts:307,319`; `alertas-provider.tsx:90`. |
| O90 | Caída global — porcentaje del mismo corte anterior | ¿Qué conversión arroja igual tramo del mes anterior? `conversionesAnteriores.nucleo.conversion_pct` → `alerta.objetivo`. | % histórico de rango equivalente, no meta publicada; día se limita al último del mes anterior. `alertas-gerencia.ts:168,320`; `alertas-provider.tsx:90`. |
| O91 | Caída global — caída X pp | ¿Cuántos puntos bajó respecto al mismo corte? `redondearPp(anterior-actual)`. | Puntos porcentuales, regla S9 3/5; no porcentaje de reducción relativa. `alertas-gerencia.ts:307`; `alertas-provider.tsx:90`. |
| O92 | Caída global — sobre N recibidos (se compara desde 30) | ¿Qué divisor del tramo actual sostiene la señal? `conversionActual.nucleo.divisor` → `alerta.muestra`. | Leads de base del divisor; se comprueba también mínimo 30 anterior aunque el texto sólo muestra N actual. `alertas-gerencia.ts:322`; `alertas-provider.tsx:81`. |

## G. Gestión de equipo — contrato S10


Gerencia `screens/equipo.tsx:869,1349` → **EquipoEmpresa**. `crm.metricas_vendedores_fn()` sin argumentos → `data/crm-api.ts:3882` valida contrato/mes → `data/use-metricas-vendedores-operativas.ts:26` → `lib/metricas-vendedores.ts:311` mapea IDs a roster/nombres. Clave de consulta cambia con mes Lima; los campos operativos descritos aquí son **foto actual**, no llegada del mes. Los cierres, operaciones de cartera y conversión de esta pantalla están en [[Inventario de indicadores de Gerencia - Comercial]], C64 (conversión), C65 (cierres) y C66 (operaciones), y no se duplican como métricas operativas.

Inventario del RPC = activo y convertido en ventana de 45 días; activos/capital operativos usan solamente **abiertos**. Atribución actual por vendedor. Equipos del RPC = supervisores activos con rol válido; el dato `equipos[].vendedores` cuenta miembros activos de `crm.equipo` cuyo supervisor coincide **sin filtrar rol vendedor**. Sus activos/capital incluyen propiedad del supervisor y de sus miembros activos directos. La suma del tablero es suma de equipos mapeados, no cualquier propietario posible de toda la empresa. Un equipo sin nombre/roster correspondiente puede omitirse en adaptador.

“Sin tocar” = abierto sin actividad de estos tipos: llamada_realizada, llamada_no_contestada, whatsapp_enviado, whatsapp_recibido o reunion_realizada. Una nota no lo saca de Sin tocar. “Última actividad” es otro reloj: máximo tiempo desde **cualquier actividad** del lead, fallback creación, sobre abiertos del responsable. El servidor entrega días con cuatro decimales; cliente añade deriva positiva desde `query.dataUpdatedAt` para que envejezca. El semáforo de este tiempo es <2 días normal, 2–5 atención, >5 crítico; no es el SLA de etapa.

**Capital:** estimado de abiertos en PEN/USD. La pantalla usa `totalEnSoles` existente con `useTipoCambio()`: edge `crm-tipo-cambio`, promedio válido de siete días hábiles, corte actual por defecto (`lib/tipo-cambio.ts:64,116`). Con tasa disponible convierte USD y suma equivalente PEN; sin tasa el chip muestra PEN y USD aparte, no inventa TC. Tabla usa `CeldaCapitalTabla`, número principal sólo si total disponible >0; 0 también se representa “—” (`equipo.tsx:96,124`). Desglose por moneda mantiene importes crudos.

**Disponibilidad:** error del RPC incluso refetch invalida el snapshot y muestra “—”; no recompone negocio del store. Hay una salvedad actual: al mapear un individuo visible sin fila del payload, valores operativos toman 0 por defecto (`metricas-vendedores.ts:334`). Bandeja y conteo de roster se toman del store de manera independiente y no tienen la misma cobertura autoritativa del agregado. La bandeja del tablero `d.parkeados` son abiertos locales sin vendedor, aunque el subtítulo diga “En bandejas de supervisores”; no exige supervisor no nulo. No confundir con `equipos[].parkeados`, que sí exige supervisor asignado.


| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O93 | Equipo — Equipos | ¿Cuántos equipos mapeados tiene el tablero? `tablero.filas.length`. | Equipos visibles activos de S10, no cantidad de todos los usuarios. `equipo.tsx:966`. |
| O94 | Equipo — N analistas en total | ¿Cuántos vendedores tiene el ámbito local? `ambito.vendedores.length`. | Personas/roster del store, no suma del campo equipos[].vendedores. `equipo.tsx:969`. |
| O95 | Equipo — Leads activos, total | ¿Cuántos abiertos suman los equipos mapeados? Sumatoria de `equipos[].activos` → `tablero.activos`. | Leads actuales S10; no llegada mensual ni total de propietario fuera de equipos. `equipo.tsx:955,977`. |
| O96 | Equipo — Capital en proceso, total | ¿Qué estimado suman los equipos, consolidado si hay TC? Sumatoria `capital_pen/usd` → `chipCapitalEnProceso`. | PEN equivalente o PEN + USD aparte según TC S10; campos/desglose por moneda. `equipo.tsx:954,972`. |
| O97 | Equipo — Por repartir; contador de bandeja | ¿Cuántos abiertos sin vendedor hay descargados en el ámbito? `d.parkeados.length`. | Leads locales, incluye sin supervisor; alias chip y cabecera de misma bandeja. `equipo.tsx:986,1322`. |
| O98 | Equipo — N analistas por supervisor | ¿Cuántos miembros activos directos cuenta el RPC? `equipos[].vendedores` → `f.vendedores`. | Personas sin filtro de rol en SQL, aunque etiqueta diga analistas. Alias fila/detalle. `equipo.tsx:1078,1164`. |
| O99 | Equipo — Activos del supervisor/equipo | ¿Cuántos abiertos poseen supervisor y miembros directos activos? `equipos[].activos`. | Leads por estructura actual S10; no sólo la lista de analistas dibujados. `equipo.tsx:1098,1172`. |
| O100 | Equipo — Capital del supervisor/equipo | ¿Qué estimado suman esos abiertos? `equipos[].capital_pen/usd` → celda/chip de capital. | PEN equivalente con TC o desglose disponible S10; 0 puede verse — en tabla. `equipo.tsx:1101,1171`. |
| O101 | Equipo — Por repartir del supervisor; bandeja del equipo | ¿Cuántos abiertos sin vendedor tienen asignado ese supervisor? `equipos[].parkeados`. | Leads de bandeja del supervisor, no cola global; 0→— en tabla. `equipo.tsx:1128,1197`. |
| O102 | Equipo — Última actividad del equipo | ¿Cuál es la mayor inactividad de los analistas visibles con abiertos? Máximo de días de sus filas mapeadas. | Días, excluye filas sin abiertos y no incorpora automáticamente abiertos propios del supervisor. No es suma ni antigüedad de lead. `equipo.tsx:1093`. |
| O103 | Equipo — Activos por analista | ¿Cuántos abiertos tiene el propietario individual? `vendedores[].activos`. | Leads actuales S10; fila ausente en payload puede mapear a 0. `equipo.tsx:1269`; `metricas-vendedores.ts:334`. |
| O104 | Equipo — Capital por analista | ¿Qué estimado tienen sus abiertos? `vendedores[].capital_pen/usd` → `CeldaCapitalTabla`. | Dinero estimado por moneda/consolidación S10, no capital cerrado. `equipo.tsx:1272`. |
| O105 | Equipo — Sin tocar | ¿Cuántos abiertos carecen de contacto de los cinco tipos definidos? `vendedores[].sin_tocar`. | Leads actuales S10; tener actividad de nota no equivale a contacto. 0→—. `equipo.tsx:1279`. |
| O106 | Equipo — Última actividad por analista; Al día / N d sin act. | ¿Cuál es la inactividad máxima de sus abiertos? `dias_sin_actividad_max` + deriva del cliente. | Días desde última actividad de cualquier tipo/creación. Sin abiertos muestra Sin abiertos; <1 Al día; resto piso de días/color S10. `equipo.tsx:72,1258`; `use-metricas-vendedores-operativas.ts:66`. |
| O107 | Equipo — Bandeja, antigüedad por lead | ¿Cuánto tiempo lleva creado el lead listado? `lead.creado_en` → edad con reloj local. | Días de antigüedad original, no permanencia en bandeja/SLA del dueño. `equipo.tsx:396`. |
| O108 | Equipo — Bandeja, capital por lead | ¿Qué estimado y moneda tiene el lead actual? `lead.monto_estimado,moneda`. | Dinero descriptivo local S3, no stock confirmado ni suma del equipo. `equipo.tsx:407`. |

## H. Ficha de lead transversal — contrato S11


`components/app/lead-drawer.tsx:168` busca lead por ID en el store. No hace una consulta métrica canónica nueva al abrir; si el lead no está descargado en ámbito, no existe esta ficha operativa disponible. No se confunde con ficha de cliente/contrato de la nota de Cartera.

Fuentes: leads S3; tareas S4; `crm.actividades_del_ambito_fn` → `data/crm-api.ts:1332` (límite servidor 10000, filas inválidas omitidas) → store. `lib/store.tsx:1348` filtra tareas pendientes/activas del lead; `:1365` actividades del lead. No hay total histórico agregado ni indicador de cuánto falta fuera de descarga. Timeline agrupa actividades antes de aplicar su tope; por eso entradas ocultas no es cantidad de actividades ni leads. La ficha no dibuja un KPI SLA propio: el reloj/plazo SLA está inventariado en Pipeline, no se le atribuye falsamente a esta ficha.


| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O109 | Ficha lead — Capital en juego / ganado / no concretado | ¿Qué estimado tiene este lead? `l.monto_estimado,moneda`; `rotuloCapital` cambia nombre según etapa. | Dinero estimado actual, incluso con rótulo ganado: NO consulta capital confirmado del núcleo. Nulo muestra Sin capital estimado. `lead-drawer.tsx:160,217,232`. |
| O110 | Ficha lead — N tareas pendientes / próxima acción | ¿Cuántas tareas activas pendientes del lead están descargadas? `tareasDe(id)` → pendientes.length. | Tareas locales ordenadas por vence_en, sin histórico completo. `lead-drawer.tsx:489,493,636`; `store.tsx:1348`. |
| O111 | Ficha lead — Agrupar N cambios de etapa | ¿Cuántas actividades quedaron dentro de ese grupo del timeline? `agruparTimeline` → cantidad de grupo. | Actividades del conjunto descargado, no llegadas ni citas. `lead-drawer.tsx:1349,1385`. |
| O112 | Ficha lead — Ver N entradas anteriores | ¿Cuántas entradas agrupadas se ocultaron por el tope visual? `itemsAgrupados.length - visibles.length`. | Entradas de timeline agrupado descargado; no total histórico servidor. `lead-drawer.tsx:1387,1388,1478`. |
| O113 | Ficha lead — hace N min/h/d de una actividad | ¿Cuánto tiempo pasó desde el instante de esta actividad? `actividad.creado_en` → `haceRelativo`. | Tiempo de reloj local, luego fecha absoluta si supera siete días; no SLA ni promedio de respuesta. `lead-drawer.tsx:140`. |

## I. Compromisos de supervisores en Resumen — contrato S12

Fuente `crm.alertas_reconocimientos_vigentes` → `listarReconocimientosAlertas` → `useReconocimientosAlertas` → `derivarCompromisos` → `resumenCompromisos` → `CompromisosSupervisoresPanel`. Evidencia: `app/src/data/crm-api.ts:1498`, `app/src/data/crm-queries.ts:902`, `app/src/lib/trazabilidad-reconocimientos.ts:87`, `app/src/screens/hoy/compromisos-supervisores.tsx:39`; montaje `app/src/screens/hoy/gerencia.tsx:582`.

La vista productiva fue leída sin datos: último asiento por alerta según `secuencia DESC`, entre registros de los últimos siete días; después excluye `hasta` vencido. `md5(pg_get_viewdef)=339b01e24dfab12540f42ffb062a9eb6`. Gerencia consulta el ámbito autorizado completo, no el rango de conversión ni sólo el roster activo. No se oculta un compromiso por haber salido su supervisor del roster. Consulta limitada a 1.000 filas, orden descendente de secuencia, refresco cada 60 segundos con pestaña activa. Alcanzar el tope muestra advertencia; no prueba totalidad.

El adaptador valida el arreglo completo. Carga inicial y error ocultan los conteos; no se imprime cero durante esos estados. `derivarCompromisos` descarta empates de secuencia y vencidos según reloj local; usa el mínimo de `hasta` y creación más siete días. Conserva tipos desconocidos con etiqueta genérica. **El panel no conoce la reactivación anticipada por agravamiento de una alerta**: no certificar que todas las alertas enumeradas continúan atenuadas ni que sus miembros sigan pendientes.

| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O114 | N compromisos | ¿Cuántos últimos asientos reconocidos/pospuestos siguen en la lista tras sus filtros temporales? `compromisos.length`. | Compromisos por alerta, no casos resueltos ni leads; S12. Sin filas, mensaje vacío en lugar del contador. `app/src/lib/trazabilidad-reconocimientos.ts:130`. |
| O115 | N supervisores | ¿Cuántos IDs de supervisor distintos tienen esos compromisos? `Set(compromisos.supervisorId)` excluyendo ID vacío. | Personas identificadas por `alerta_id`; no todo el roster. Si un ID no se puede extraer, su fila visible no infla este total. `app/src/lib/trazabilidad-reconocimientos.ts:132`. |
| O116 | «N leads» / «N analistas» en cada compromiso | ¿Cuántos miembros tenía la fotografía reconocida? `asiento.miembros.length`; tipo de `alerta_id` decide unidad. | Leads en por_repartir/lead_sin_responder/tarea_vencida; analistas en sin_proxima_accion; ítems en tipo desconocido. **Fotografía del reconocimiento, no cantidad viva actual**. `app/src/lib/trazabilidad-reconocimientos.ts:33,105`. |
| O117 | Hace N; se reactiva / rige como máximo hasta | ¿Cuándo se reconoció/pospuso y cuál es su vencimiento máximo? `creado_en`, `min(hasta,creado_en+7 días)` → tiempo transcurrido y fecha/hora Lima. | Relojes de un compromiso; no SLA de lead ni tiempo de resolución. Puede ceder antes por agravamiento, que no se refleja aquí. `app/src/screens/hoy/compromisos-supervisores.tsx:35,137`. |

## J. Distribución inferior de Rendimiento — contrato S13

Ruta activa: `app/src/screens/hoy/gerencia.tsx:859` monta `DistribucionLeadsGerencia` con `mostrarOperacion=false` y `mostrarPeriodo=false`. Se muestran fichas, filtros de equipos, atención, tabla de rangos y calidad. **No se montan Asistente de reparto ni panel Por repartir**. No atribuir a esta ruta todas las capacidades del componente compartido.

Localizadores (rutas relativas a `CRM-Avance-Corp/`):

| Clave | Archivo |
|---|---|
| DG | `app/src/screens/hoy/distribucion-leads-gerencia.tsx` |
| DL | `app/src/lib/distribucion-lecturas.ts` |
| MD | `app/src/lib/metricas-distribucion.ts` |
| API | `app/src/data/crm-api.ts` |
| CQ | `app/src/data/crm-queries.ts` |
| SD | `supabase/migrations/20260827050000_crm_f2_3a_distribucion_sin_anulados.sql` |
| V3 | `supabase/migrations/20260827090000_crm_f2_3b_distribucion_v3.sql` |

Cadena: `crm.metricas_distribucion_leads_v3_fn(p_desde,p_hasta)` → `MetricasDistribucionLeadsV3Schema` (incluido rango devuelto) → `useMetricasDistribucionLeadsV3` → `fichaAnalista` / `equiposDistribucion` → DG. API:3584,3593; CQ:548; DG:1549. Se heredan reglas del contrato D comercial, sin duplicar C01/C02/C61–C63.

**Cartera actual:** episodios `crm.lead_asignaciones` con `finalizado_en IS NULL`, unidos al lead. Cuenta episodios abiertos, no `COUNT(DISTINCT lead_id)` ni llegadas del mes. Montos estimados de asignación, no inversiones. **Cohorte:** episodios por `asignado_en` en el rango libre enviado, días Lima inclusivos; ese rango sigue siendo independiente del selector mensual superior. SD:101,118,181,203,233.

**Roster/atribución:** vendedores activos y vendedores/supervisores con capacidad configurada o historial, incluidos no disponibles. Propiedad del episodio; agrupación por `supervisor_id`; supervisor sin superior forma su propio equipo, resto sin vínculo queda Sin supervisor asignado. SD:209; DL:318,330. La selección de equipo recorta fichas/tabla; los avisos y calidad globales conservan el payload empresarial.

**Disponibilidad:** error o contrato inválido no inventa cifras; con datos previos pueden permanecer junto al aviso. Sin datos se muestra carga/vacío. Sondas de conversión no bloquean estas magnitudes operativas. Demo identificado. DG:1590,1611,1632,1643,1666. Las reservas estructurales de filas/campos particulares se declaran abajo.

| ID | Etiqueta actual / ubicación | Definición actual y campo / transformación | Unidad, período, disponibilidad particular y evidencia |
|---|---|---|---|
| O118 | N analistas — Todos / Equipo de… | ¿Cuántas fichas tiene ese conjunto? `analistas[] → fichaAnalista → fichas.length/fichasEquipo.length`. | Personas del roster actual S13, no sólo vendedores activos. Tarjetas-filtro si equipos>1; equipos sin fichas se omiten. DG:930,934,939,947; DL:330. |
| O119 | Cartera actual: N / Total activos de tabla | ¿Cuántos episodios abiertos tiene la persona en todas las monedas? `analistas[].capacidad.carga_activa`. | Episodios actuales; **incluye USD y sin monto**, aunque las columnas sean rangos PEN. Reserva SQL 0 sin cartera. SD:203,236,401; DG:585,677,1359. |
| O120 | N de… leads — Todos / equipo | ¿Cuánto suman las cargas de las fichas? `Σ capacidad.carga_activa → resumenEquipo.cargaActiva`. | Episodios actuales global/equipo; incluye personas sin límite y no disponibles. DL:380,387; DG:793. |
| O121 | Límite de cartera / de N leads — persona | ¿Qué cupo se configuró? `capacidad.objetivo`, de `equipo.capacidad_leads_objetivo`. | Parámetro actual individual, todas las monedas; 1–1000, null=sin límite definido, no 0. No se ejecuta su edición. SD:218,400; MD:104; DG:638,679. |
| O122 | de N leads — límite Todos / equipo | ¿Cuánto suman los límites definidos? `Σ capacidad.objetivo → resumenEquipo.limiteDefinido`. | Cupos configurados actuales del conjunto; si nadie tiene límite, null=límites por definir. DL:382,388; DG:795. |
| O123 | N cupos libres — persona | ¿Cuánto espacio no negativo le queda? `max(0,objetivo-carga_activa) → ficha.cuposLibres`. | Cupos actuales individuales, null sin límite. Si lleno, el texto se sustituye por O125. DL:232; DG:695,698. |
| O124 | N cupos libres — Todos / equipo | ¿Cuánto espacio positivo queda sumando por persona? `Σ max(0,objetivo_i-carga_i) → resumenEquipo.cuposLibres`. | Cupos actuales; no compensar sobrecarga de una persona con cupo de otra. Omite sin límite; incluye no disponibles con objetivo. Sólo texto si algún límite. DL:388,391; DG:795. |
| O125 | N% del límite / Al tope de su límite | ¿Qué porcentaje redondeado ocupa la carga? `round(carga/objetivo*100) → uso`; lleno si carga≥objetivo definido. | % individual actual; puede superar 100, sólo barra limitada. Ámbar desde 85; rojo lleno. Sin límite no hay %. DL:233,234; DG:682,698. |
| O126 | N analistas al tope | ¿Cuántos disponibles tienen límite y carga≥límite? Filtro `disponible_para_recibir && objetivo!=null && carga>=objetivo`. | Personas actuales; global en aviso, global/equipo en tarjetas. No disponibles excluidos aquí, no de O120/O122. Cero omite aviso; hasta tres nombres y resto. DL:135,160,394; DG:801,807. |
| O127 | N sin atender — persona / mayor caso del aviso | ¿Cuántos episodios abiertos carecen de contacto válido del analista desde su asignación? `operacion.sin_tocar_actual → ficha.sinAtender`. | Episodios actuales. Contacto: llamada realizada/no contestada, WhatsApp enviado/recibido o reunión realizada, por ese dueño, desde asignado_en hasta corte. No ausencia de toda actividad ni de contacto histórico de otro dueño. SQL 0 sin cartera; badge si>0. SD:137,156,241,457; DL:240; DG:731. |
| O128 | N sin atender — Todos / equipo / aviso | ¿Cuánto suman los episodios O127? `Σ operacion.sin_tocar_actual → resumenEquipo.sinAtender/sinAtenderTotal`. | Episodios actuales del conjunto; incluye no disponibles. Aviso global suma total y muestra persona de máximo, no otra métrica. Cero omite aviso. DL:163,180,393; DG:504,801,803. |
| O129 | S/… en soles — ficha | ¿Qué estimado PEN suman sus episodios abiertos? `pen.cartera_actual.capital → ficha.capitalPen`. | PEN de asignación actual, no capital confirmado; UI redondea a unidad entera y muestra cero. SD:239,408; DL:243; DG:154,746. |
| O130 | US$… en dólares — ficha | ¿Qué estimado USD suman sus episodios abiertos? `usd_no_segmentado.cartera_actual_capital → ficha.capitalUsd`. | USD separado sin TC. Aparece si `conUsd`: cartera o historia USD de cohorte/resultados; puede mostrarse 0 con historia. SD:240,442; DL:244,249; DG:747. |
| O131 | Leads activos hoy — celda rango PEN | ¿Cuántos episodios abiertos están en ese rango de monto? `pen.rangos[].cartera_actual.episodios`. | Episodios actuales por persona/rango y equipo filtrado. Siete columnas PEN excluyen sin_monto; no suman obligatoriamente O119. Reserva 0 de rango ausente, aunque schema exige catálogo completo. SD:251,259; MD:93; DG:159,178,1204,1214. |
| O132 | S/… — tooltip de celda | ¿Qué estimado suman los episodios PEN de ese segmento? `pen.rangos[].cartera_actual.capital`. | PEN actual por persona/rango, redondeado; sólo tooltip modo carga. Reserva estructural 0 para rango ausente. SD:256; DG:154,185,1212. |
| O133 | Salidas del período: N transferidos | ¿Cuántos episodios asignados en el rango tienen motivo final transferido? `operacion.transferidos → ficha.transferidos`. | Episodios de cohorte por persona; selección por asignado_en, **no fecha de transferencia**. Bloque si transferidos+parqueados>0. SD:181,186,311,321,454; DL:241; DG:749,753. |
| O134 | N parqueados — Salidas del período | ¿Cuántos episodios asignados en el rango tienen motivo final parqueado? `operacion.parqueados → ficha.parqueados`. | Episodios de cohorte por persona; no flujo por fecha de parqueo. Reserva SQL 0; visibilidad como O133. SD:181,186,322,455; DL:242; DG:749,754. |
| O135 | bandeja: N pendientes / bandeja sin pendientes | ¿Cuántos leads activos abiertos sin vendedor tiene asignados ese supervisor? `por_repartir.bandejas[].carga_total → pendientesBandeja`. | Leads actuales, todas las monedas, cuatro etapas de trabajo, por asignado_supervisor_id. Bandeja ausente→0. Sólo subtítulo de equipo con fichas; no panel de cola global. SD:327,334,367,377; DL:332,348,362; DG:939,950. |
| O136 | No recibe por ahora | ¿La ficha no está disponible para recibir según servidor? `!disponible_para_recibir`. | Estado actual: no cumple conjuntamente equipo.activo y perfiles.activo. No significa cartera llena. Ficha se conserva al final y no habilita edición de límite. SD:216,217; DG:607,618; DL:272,273,304. |
| O137 | N registros no tienen monto | ¿Cuánto suman casos sin monto válido en cartera y cohorte? `calidad.episodios_sin_monto_actuales + episodios_sin_monto_cohorte`. | Conteos de episodios globales, actual+cohorte; nulo/≤0. **No deduplica intersección**: episodio abierto del rango puede contarse dos veces. Aviso si>0, no filtro equipo. SD:521,525; DG:1509,1523. |
| O138 | N registros usan fechas estimadas | ¿Cuánto suman episodios aproximados en cartera y cohorte? `calidad.episodios_aproximados_actuales + episodios_aproximados_cohorte`. | Conteos globales de ambas poblaciones, tampoco deduplica; no antigüedad ni atraso. Aviso si>0, independiente de equipo. SD:519,520; DG:1510,1524,1525. |
| O139 | Mostrar los N analistas restantes | ¿Cuántas fichas filtradas oculta el recorte visual? `visibles.length-recortadas.length → ocultas`. | Fichas UI actuales, no truncamiento RPC ni usuarios no descargados. `recortarConMargen` evita ocultar sólo 1–2 elementos. DG:116,125,835,846,991,1000. |
| O140 | Sin pendientes urgentes / Lo que merece tu atención | ¿Hay avisos permitidos en esta variante? `avisosAtencion(datos).filter(avisoVisible).length`. | Estado compuesto global. `mostrarOperacion=false` excluye avisos de alto monto pendiente, cola Gerencia y bandejas. Vacío sólo habla de avisos restantes de capacidad/sin atender, **no de todas las urgencias ni SLA**. DL:100,184; DG:145,151,504,518. |

**Límites de cobertura S13:** no hay indicadores visibles de antigüedad, mediana de primer contacto, contactabilidad o SLA en esta variante. V3 retira `contactos`, campos SLA, medianas y `estancados_actual`; pie remite tiempos a SLA versionados. V3:619,660; DG:1676. Los siete rangos PEN se describen por límites inferior exclusivo/superior inclusivo (`datos.rangos`); `sin_monto` no se dibuja (SD:107,116; MD:53,58; DG:159,162). La suma de cupos individuales puede ser positiva aunque carga total supere suma de límites. Estas diferencias se documentan, no se modifican.

## Cobertura y límites del inventario

**140 registros, O01–O140**, sin duplicar los alias exactos de O01/O02 en Resumen ni C64–C66 de Gestión de equipo. La tabla siguiente facilita revisar superficies, no agrega cantidades comerciales.

| Sección | IDs | Superficies cubiertas |
|---|---|---|
| Indicadores S1 | O01–O24 | Contrato de la sección y cada ubicación citada |
| B. Pipeline y Leads — contratos S2/S3 | O25–O39 | Contrato de la sección y cada ubicación citada |
| C. Agenda — contrato S4 | O40–O53 | Contrato de la sección y cada ubicación citada |
| D. Repartir — contratos S5/S6/S7 | O54–O71 | Contrato de la sección y cada ubicación citada |
| E. Base para gestión y carpetas — contrato S8 | O72–O80 | Contrato de la sección y cada ubicación citada |
| F. Alertas de Gerencia — contrato S9 | O81–O92 | Contrato de la sección y cada ubicación citada |
| G. Gestión de equipo — contrato S10 | O93–O108 | Contrato de la sección y cada ubicación citada |
| H. Ficha de lead transversal — contrato S11 | O109–O113 | Contrato de la sección y cada ubicación citada |
| I. Compromisos de supervisores — contrato S12 | O114–O117 | Resumen, cantidades de la fotografía y relojes de compromiso |
| J. Distribución inferior de Rendimiento — contrato S13 | O118–O140 | Capacidad, cartera actual, rangos, salidas, bandeja de equipo y calidad |

No se trata como inconsistencia por sí sola que Agenda pendiente, Citas por fecha prevista y cohorte de llegadas den cantidades distintas. Sí se preservan explícitamente las diferencias de divisor, población y reloj para que el punto 2 pueda decidir cómo explicarlas sin cambiar el servidor.

### Información que hoy no permite afirmar más

1. **Citas por modalidad:** el payload entrega debieron_ocurrir bruto pero no todos los descuentos vencidos del divisor. No existe una identidad visible “N de M = porcentaje” con el M actual. Cualquier campo explicativo adicional deberá aprovechar el agregador/núcleo existente y ser aprobado; no se crea otra calculadora.
2. **Conteos locales:** Pipeline/store, Agenda, timeline, cola e historial no transportan en todas sus lecturas una prueba de totalidad ni un total global compatible. Se documenta length según su alcance. No se inventa un total con otra consulta ni se afirma cuál es el límite remoto efectivo de PostgREST.
3. **Base/carpetas:** el estado vacío de carpeta no distingue por sí solo array vacío válido de lectura fallida. Sus conteos actuales están definidos, pero no certifican disponibilidad.
4. **Alertas:** cero alertas puede significar que falta corte, meta, muestra o verificación. El payload del provider no trae un recuento separado de evaluados/no evaluables; no se registra cero desviaciones como garantía empresarial completa.
5. **Capital y dueño:** estimado local, stock contractual y conversión no son equivalentes. La atribución actual de carga no se sustituye por primera llegada, y una cancelación de conversión no se aplica por analogía al núcleo de capital.
6. **Detalle descriptivo:** importes de una fila se inventarían si se trataran como inversión confirmada sin la fuente correspondiente. Aquí se documentan como estimados. Totales de selección, índices de página y cantidad de filtros son controles, no indicadores de captación.

Estos límites son evidencia para los puntos posteriores del requerimiento, **no autorización de desarrollo**. No se declara necesaria una función independiente: antes de solicitar cualquier ampliación se debe probar qué campo falta en la salida oficial, qué lectura existente puede proporcionarlo y qué decisión comercial necesita esa explicación.

## Huellas de las definiciones vivas utilizadas

Algoritmo: `md5(pg_get_functiondef(oid))`, no `md5(prosrc)`; por eso no comparar directamente con huellas de otro método. Sólo texto de funciones leído; sin extracción de datos personales.

| Función | Huella |
|---|---|
| `private.metricas_reuniones_implementacion` | `7f4f885e2d044afdd2fd0766991517a0` |
| `crm.resumen_reparto_fn` | `af9cc1965a8384d40b4f0d440de14f4e` |
| `crm.panel_distribucion_reparto` | `3df8a05efbdcf0ea96a6ea6ad3c8ad38` |
| `crm.rescate_descartes_meses` | `c69a1f2c0853daf3bbc1d792b3d999a4` |
| `crm.rescate_descartes_mes` | `e2f267b6f13f280b9cb440449391cb72` |
| `crm.leads_por_repartir` | `b52431bc89bdc0b382e167a938e06abb` |
| `crm.resumen_cartera_fn` | `e69c9eb25ef352150404875f3b5687c5` |
| `crm.metricas_vendedores_fn` | `7462d4e1736ebe22fc2268b1cb71e105` |
| `private.citas_episodios` | `ea636888a266941e959f26c6a5727216` |
| `crm.reporte_derivaciones_coordinacion_fn` | `1c7380008403af7cfa2ade2a976f2cd4` |
| `private.leads_por_repartir_implementacion` | `efa6a62319223adb186276bdf9997b68` |
| `crm.leads_descartados` | `35918d3991006e6f17a6a1ca9350b2ef` |
| `private.leads_descartados_implementacion` | `f1ac0c4c2fbb95ef8811435cd7e3c900` |

La definición del servidor prevalece sobre un nombre de tarjeta, comentario antiguo o reconstrucción local. Referencia transversal de núcleos y matriz de rutas: [[Inventario de indicadores de Gerencia - Contrato de lectura]]. Registro de cierre común: [[Inventario de indicadores de Gerencia - Evidencia y verificacion]].
