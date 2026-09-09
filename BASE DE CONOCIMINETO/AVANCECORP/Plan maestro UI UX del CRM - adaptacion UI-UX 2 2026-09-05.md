---
fecha: 2026-09-05
estado: reinicio-visual-desde-crm-actual-2026-09-06
tags: [crm, ux, ui, figma, plan]
---
# Plan maestro UI y UX del CRM — adaptación de UI-UX (2)

## Objetivo y decisión vigente

**Decisión vigente: reiniciar la propuesta visual desde el CRM actual.** Miguel indicó que su CRM actual le gusta y que el intento local no le resulta atractivo; pidió comenzar de nuevo. Se conserva el objetivo de avanzar hoy, 6 de septiembre de 2026, pero la siguiente entrega es una nueva composición de Resumen en Figma antes de extender la implementación. El trabajo sigue siendo de diseño y frontend, con backend, permisos y fórmulas intactos.

La referencia principal vuelve a ser la identidad y las pantallas del CRM actual que Miguel aprecia. [Propuesta UI-UX (3), `209:733`](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=209-733) y las propuestas anteriores quedan como antecedentes, no como aprobación de la nueva dirección. El intento local se conserva en [intento-no-aprobado](../../UX-UI-GERENCIA/07-implementacion/bloque-a-2026-09-06/intento-no-aprobado/README.md); archivarlo no restaura automáticamente el frontend activo.

Secuencia inmediata: **comparar capturas del CRM actual y del intento → identificar qué conservar y qué mejorar → mostrar una nueva composición de Resumen en Figma → revisar la dirección con Miguel → retomar Resumen escritorio/móvil, estados, Conversiones y piloto de Ranking.** Se reutilizan auditoría, contratos, componentes y recorridos que sigan siendo válidos. Las fases UX0–UX6 y los bloques A–D se conservan; las fechas de abajo son objetivos, no constancias de aprobación ni de trabajo terminado.

El historial está separado en [[Decisiones UI UX Gerencia - 2026-09-06]] ([DECISIONES.md](../../UX-UI-GERENCIA/01-plan/DECISIONES.md)). Organización y evidencias: [UX-UI-GERENCIA](../../UX-UI-GERENCIA/README.md). Reutilización: [[Inventario de reutilizacion frontend - F0 UI UX 2 2026-09-06]] y [[UX1 y UX2 Gerencia - componentes y revision visual 2026-09-06]].

Fuente principal: `CRM-Avance-Corp/UI-UX (2).pdf`, siete páginas, «Modelo de diseño y experiencia de usuario para productos de trabajo», agosto de 2026. Se leyó completo y se revisó su representación visual. Se adapta junto a [[Fundamentos UX del CRM]], [[Plan de mejoras UX-UI del CRM]] y [[Plan de mejora UX de Gerencia - revision 2026-09-05]].

El PDF define un método de trabajo, no una plantilla visual que deba copiarse. Sus metas orientativas de tiempo, clics y cumplimiento no son resultados medidos del CRM. La semana sugerida para auditoría se ajustará a la disponibilidad de usuarios y a la evidencia existente.

## Qué se conserva

| Elemento | Fuente actual y decisión |
| --- | --- |
| Marca | Logo original Avance Corp, nombre y sidebar navy. Activo original ya guardado en Figma; sin recrear el logotipo. |
| Lenguaje visual | Navy institucional `#111e3d`, azul de acción `#2563eb`, superficies claras, bordes y sombras actuales. Revisar la nueva composición sobre capturas del CRM actual; `209:733` se conserva como antecedente. No deducir éxito o alerta únicamente de un color sin una regla vigente. |
| Tipografía | Plus Jakarta Sans en la estructura general; IBM Plex Sans en reportes de Gerencia. Registrar ambos usos y su jerarquía antes de proponer una unificación. |
| Navegación | Menú, nombres de módulos, búsqueda, ayuda, avisos y acciones conocidas. Reorganizar sólo con evidencia de tarea y sin eliminar destinos. |
| Componentes de código | Button, Card, Input, Dialog/Sheet, pestañas, tablas/listas, estados y gráficos ECharts existentes. Reutilizar su comportamiento; añadir variantes sólo ante una necesidad concreta. |
| Biblioteca Figma | Nueve familias: Acción, Cabecera, Período, Pestaña, Fila de Ranking, Indicador, Detalle lateral, Estado del dato y Atención. Base verificada: 72 variables, ocho estilos de texto y dos estilos de efectos. |
| Datos y operación | Definiciones, fórmulas, monedas/TC, períodos, exclusiones, orden, permisos y operaciones vigentes. El diseño no convierte resultados parciales en totales ni asigna un mismo período a indicadores distintos. |
| Avances locales | Conservación de filtros, pestaña, responsable, regreso y foco; detalles; explicación ampliable; estados de datos; revisión previa de capacidad/metas. Se revisan, no se reconstruyen por defecto. |

## Lo observado en esta revisión

Se registraron cinco vistas locales en modo Gerencia demo. Son una muestra técnica para preparar el plan, **no evidencia de cuáles son las cinco pantallas más usadas** ni una prueba con usuarios. Se consultó la prioridad a Miguel; mientras no responda, la primera propuesta visual se concentra en Gerencia por el trabajo activo y sus observaciones expresas.

| Paso y evidencia | Qué funciona | Mejora propuesta |
| --- | --- | --- |
| 1. Resumen | Marca y contexto identificables; indicadores con período y base. | Las gráficas quedan debajo de indicadores y dos bloques de texto. Dar prioridad a comparaciones visuales y compactar explicaciones; igualar jerarquía y alturas. |
| 2. Conversiones | Datos y bases ya disponibles; comparación y detalle existentes. | El hero y el texto dominan. Separar claramente conversión mensual, resultados de las llegadas y cierres por fecha. Miguel pidió corregir su presentación; el desarrollo local del bloque está autorizado. |
| 3. Cartera | Búsqueda, filtros y agrupación cliente/contrato aprovechables. | Hasta cuatro acciones por fila compiten por espacio. Probar una principal según tarea y un menú secundario; conservar nombres largos y acceso a todas las operaciones autorizadas. |
| 4. Nuevo lead | Campos etiquetados, foco inicial y pie de acciones presentes. | Varios datos opcionales aparecen antes de Origen y Capital obligatorios. Priorizar datos necesarios y agrupar información adicional sin perder campos ni validaciones. |
| 5. Ranking | Orden, base, pestañas y comparación explícitos. | Ajustar densidad y posición de Comparar; conservar la mejora de regreso y los valores originales. No confundir posición con cumplimiento. |

Las capturas se guardan en `output/ux-gerencia-desarrollo-2026-09-05/evidencia/uiux2-01…05-*-actual.png` y en Figma. Resumen fue capturado a 1440 × 960; el resto a 1440 × 767. Se preserva la proporción de cada captura. No se atribuyen a la interfaz defectos causados por una captura recortada: la primera captura incompleta del formulario fue sustituida por una con el pie visible.

Faltan observación de tareas reales, muestra móvil de los nuevos flujos operativos, estados de red/guardado y revisión de los demás roles. Los hallazgos de esta tabla son visuales y de organización; no certifican accesibilidad ni comportamiento integral.

## Fases del plan principal

Los identificadores **UX0–UX6** corresponden al PDF. Se mantienen distintos de **G-F0–G-F5**, que identifican el trabajo previo de Gerencia, para evitar dar por terminada una fase sólo porque coincide su número.

| Fase | Trabajo y entregable concreto | Base que se aprovecha | Criterio de cierre | Revisión objetivo |
| --- | --- | --- | --- | --- |
| **UX0 · Auditar y medir** | Inventario de pantallas por rol, cinco pantallas prioritarias confirmadas, checklist de Nielsen y tres tareas frecuentes medidas. Guardar capturas, problemas, severidad, pasos y evidencia. Observar al menos una persona haciendo una tarea sin dirigirla. | Auditoría experta G-F0, 14 capturas previas como historial, cinco capturas nuevas y observaciones de Miguel. | Prioridades justificadas por tarea y frecuencia; línea base registrada. Si no hay prueba humana, se identifica la limitación y no se declara validada.  Hoy, 06/09 · entrega local priorizada |
| **UX1 · Ordenar el sistema visual** | Catálogo del CRM con logo, colores, tipografías, espacios, radios, controles, anatomía, estados y correspondencia Figma/código. Matriz: conservar, ajustar, ampliar. | Nueve familias y 72 variables Figma; controles y estilos actuales. | Cada elemento propuesto tiene fuente, uso y estados aplicables. Resolver diferencias de paleta/espaciado de forma documentada, sin sustitución masiva.  Hoy, 06/09 · entrega local priorizada |
| **UX2 · Jerarquía de pantallas** | Diseños completos de las pantallas priorizadas en escritorio y móvil, mostrando qué se mira primero y dónde profundizar. Primera muestra: Resumen y Conversiones; luego extender el patrón a los módulos acordados. | G-F1–G-F3 y datos vigentes. | La vista comunica la tarea y la próxima acción; sus cifras conservan significado y evidencia. Revisión de la propuesta local con Miguel durante el desarrollo autorizado.  Hoy, 06/09 · entrega local priorizada |
| **UX3 · Tablas y formularios** | Mejorar Ranking/Cartera/Leads/Repartir/Derivaciones según prioridad; diseñar formulario y detalle más utilizados. Orden y filtros coherentes, acción principal legible, secundarios accesibles, ayuda y error junto al campo. | Tablas, adaptación a lista, búsqueda y formularios actuales. | Misma tarea completada con menos fricción; sin ocultar información profesional necesaria, cambiar requisitos ni perder operaciones.  Hoy, 06/09 · entrega local priorizada |
| **UX4 · Respuesta y estados** | Diseñar carga, vacío, error, cero comprobado, lectura parcial/antigua, sin base/TC, bloqueo por rol, guardando, confirmado y respuesta incierta. Matriz por componente y acción. | Paneles y estados existentes; revisión de metas y capacidad de G-F4. | Cada acción comunica su resultado real y el siguiente paso; un error de red no se presenta como éxito o cero.  Hoy, 06/09 · entrega local priorizada |
| **UX5 · Recorridos de trabajo** | Prototipar tareas completas: reporte → responsable → detalle → casos → regreso; consulta de metas → administración permitida → revisión → resultado → regreso; operación comercial → seguimiento → inversión/contrato, según flujo real. | Estado de consulta y enlaces locales G-F1/G-F4; destinos operativos existentes. | El usuario conserva contexto, entiende el alcance del destino y llega a su tarea sin reconstruir la consulta. Se comparan pasos con UX0.  Hoy, 06/09 · entrega local priorizada |
| **UX6 · Validación continua** | Verificación visual, teclado, foco, contraste, ampliación, dispositivos, estados y tareas repetidas. Registro antes/después de éxito, tiempo, clics y errores. | Pruebas técnicas previas como regresión; G-F5 sigue pendiente de cierre. | Sin fallos críticos de tarea o interpretación; diferencias visuales justificadas; cifras y operaciones conservadas; revisión humana registrada. Accesibilidad se comprueba en cada entrega, no sólo al final.  Hoy, 06/09 · entrega local priorizada |

UX4 y UX6 acompañan cada pasada; no se aplazan hasta terminar todas las pantallas. Se entrega por componente: fuente y uso → variante de presentación → interacción → prueba y evidencia. La revisión se hace sobre el local funcionando. Las mejoras de otros módulos conservan su prioridad dentro de B–D y se registran individualmente; una entrega de Gerencia no certifica por sí sola todo el CRM.

### Ejecución de hoy

| Pasada | Resultado revisable | Revisión objetivo |
| --- | --- | --- |
| 1 · Resumen | Comparación del CRM actual y del intento; nueva composición en Figma que conserve su identidad. Después de revisar esa dirección, adaptar escritorio y móvil. | 06/09 · nueva propuesta visual como siguiente entrega |
| 2 · Estados | Carga, consulta fallida, sin TC, parcial/antiguo, sin base y cero comprobado, sobre Indicador/Atención existentes. | 06/09 · después de la primera pasada; 15 min |
| 3 · Conversiones | Mes/rango explícitos, «Resultados de los leads del mes», comparación con bases y color único por analista. | 06/09 · tercera pasada; 15 min |
| 4 · Ranking | Piloto escritorio/móvil, selección, detalle y regreso conservando contexto. | 06/09 · tras estabilizar componentes |
| 5 · Verificación | Correcciones visuales y funcionales, pruebas de contratos, móvil, teclado y commits por alcance. | 06/09 · cierre de la entrega local |

### F0: condiciones verificables y continuidad

1. Inventario, fuentes, capturas y hallazgos de las pantallas prioritarias enlazados y trazables.
2. Tres tareas con guion y registro de la línea base: resultado, tiempo, pasos y errores; los valores humanos siguen vacíos hasta observarlos.
3. Prioridad de trabajo documentada y limitaciones asignadas a la validación continua. Hoy rige provisionalmente Gerencia por la solicitud explícita de Miguel.

La auditoría documental permite continuar. La validación humana requiere las observaciones efectivamente realizadas; se proponen dos sesiones de 20 minutos (gerencia y analista) y cinco minutos para ordenar frecuencia, **hoy si están disponibles**, en paralelo al desarrollo. No hay cita concertada ni se espera una semana. Sin participantes disponibles se registra la limitación y se mantiene la ejecución autorizada; no se inventan resultados humanos.

### Regla de color y términos para el bloque A

| Rol | Color | Uso |
| --- | --- | --- |
| Familia o serie real | Azul: capital/llegadas. Verde: conversión/cierres. Naranja: citas. | Identifica qué se mide; no califica rendimiento. Analistas del mismo gráfico: un solo color. |
| Referencia | Gris/navy atenuado | Meta u otro conteo de referencia, con su nombre y base. Pactadas no se convierte automáticamente en divisor de realizadas. |
| Cumplimiento | Sólo la regla vigente del CRM | Mostrar el avance servido o ya calculado por la lógica existente; ninguna escala cromática nueva por analista. |
| Atención | Ámbar | Señales existentes: citas vencidas, falta de TC, lecturas parciales o errores que lo requieran. |

El contrato de lectura describe «Meta y cumplimiento» como objetivo configurado y grado de avance; `objetivos.ts` representa tanto `conversionObjetivo` como `capitalObjetivo` dentro de las metas. Puede usarse **Meta** como rótulo de referencia en cada tarjeta, conservando **Conversión del mes (%)** y **Capital confirmado (moneda)**, sus bases y su objetivo específico. No se cambian nombres de campos ni cálculos. Véase [[Inventario de indicadores de Gerencia - Contrato de lectura]].

Los deltas frente a agosto del frame son ejemplos inventados y se excluyen del frontend. También se excluye el 71% de citas: el contrato vigente no acredita que ambos conteos compartan divisor. No se añade backend para completar esos adornos.

## Qué significa un dashboard dinámico y comercial

La primera lectura debe responder cuatro preguntas: **cómo vamos, frente a qué objetivo, dónde está la diferencia y qué conviene revisar**. Los gráficos tienen prioridad visual; el detalle explica los resultados y permite actuar con las operaciones existentes.

| Comportamiento previsto | Beneficio comercial | Base a conservar y prueba de cierre |
| --- | --- | --- |
| Cambiar rango, origen y responsable donde el reporte lo permita | Acotar la consulta sin rehacer el recorrido. | Reutilizar filtros actuales. Cada bloque indica el período que realmente utiliza; un filtro de rango no aparenta cambiar un indicador mensual fijo. |
| Gráficos vinculados a la consulta | Ver capital frente a meta, conversión frente a objetivo, volumen y evolución. | Usar las series y cálculos servidos. Cambiar un filtro debe actualizar sólo las vistas compatibles y sus etiquetas, sin cifras anteriores presentadas como actuales. |
| Seleccionar un analista o abrir el detalle desde un indicador | Entender quién explica el resultado y consultar la evidencia. | Reutilizar Ranking, comparación y detalles existentes. Mantener responsable, mes, pestaña y origen al volver. |
| Comparar responsables con una base equivalente | Identificar diferencias útiles para supervisión. | Reutilizar la comparación de G-F3; mostrar base y aportes. No promediar porcentajes ni mezclar cierres del rango con conversión mensual. |
| Abrir pendientes y seguir el caso | Convertir la lectura del dashboard en una acción concreta. | Reutilizar señales y destinos actuales de Citas/Hoy/Agenda. Mostrar si el destino cambia el alcance de la consulta. |
| Mostrar carga, actualización, ausencia y error con claridad | Saber cuándo confiar en la lectura y cómo continuar. | Respetar el ciclo actual de consulta. No prometer tiempo real, actualización automática nueva ni capacidad offline que el CRM no tenga. |
| Revelar filtros y explicaciones cuando se necesitan | Leer con menos desplazamiento, especialmente en móvil. | Resumen compacto del contexto siempre visible; panel ampliable, etiquetas claras y regreso accesible. |

La muestra actual de Figma demuestra dirección visual y navegación acotada. **Todavía no recalcula por filtros, no permite cualquier combinación de analistas ni consulta datos reales.** La propuesta local conecta las consultas y controles ya existentes; el demo conserva sus límites y se rotula como ejemplo.

## Orden de entregas del plan

1. **Bloque A — lectura comercial:** terminar el diseño de Resumen y Conversiones, con gráficos, contexto, detalle y estados en escritorio y móvil. Incorporar la corrección visual solicitada de Conversiones.
2. **Bloque B — supervisión:** revisar Ranking, Citas, Metas y Rendimiento aplicando la dirección acordada. Aprovechar navegación, detalle, comparación y revisión previa de G-F1–G-F4.
3. **Bloque C — operación:** priorizar Hoy/Agenda/Pipeline/Cartera/Leads y los formularios de mayor uso con la evidencia de UX0. Revisar listados, ficha, seguimiento y regreso.
4. **Bloque D — consistencia y cierre:** completar pantallas y estados restantes por rol, documentar componentes y ejecutar la validación de los recorridos acordados.

Cada bloque tendrá una ficha con pantalla/rol, problema observado, tarea, elementos conservados, cambios propuestos, estados, enlace Figma, dependencias y criterio de prueba. La fecha objetivo de esta ejecución local es hoy; cualquier mejora porcentual exige una línea base medida. Un hallazgo que requiera backend, permisos o una fórmula se registra aparte y no se introduce en este alcance.

## Cómo se relaciona con lo ya desarrollado

| Trabajo previo | Estado al pausar | Encaje en el plan |
| --- | --- | --- |
| G-F0: auditoría y biblioteca | Base técnica preparada; prueba humana pendiente. | UX0 y UX1. No repetir lo que conserva validez; actualizar evidencia afectada. |
| G-F1: contexto y Ranking | Cambios locales y recorridos focales comprobados. | UX2, UX3 y UX5. Mantener filtros, regreso, foco y título móvil. |
| G-F2: Resumen y Citas | Implementación local; Resumen requiere más gráficos por indicación de Miguel. | UX2 y UX4. Revisar primero la jerarquía visual. |
| G-F3: comparación y Conversiones | Comparación y explicación implementadas; UI de Conversiones rechazada. | UX2/UX3/UX5. Reutilizar lógica y preparar nueva presentación en Figma. |
| G-F4: gestión y ajustes | Revisión previa y estados implementados localmente con pruebas focales; revisión integral pendiente. | UX4 y UX5. Revisar los flujos con cambios simulados/controlados. |
| G-F5: calidad y entrega | Parcial. No hay cierre de usabilidad ni aprobación visual global. | UX6 transversal. No equivale a “100 % terminado”. |

## Dirección visual y prioridades por módulo

| Módulo | Pregunta del usuario y mejora |
| --- | --- |
| **Resumen** | «¿Cómo va el negocio y qué debo revisar?» Capital frente a meta, conversión frente a su objetivo compatible, citas pactadas/realizadas y evolución de llegadas/cierres. Gráficos con valores y acceso a detalle; alertas existentes compactas y accionables. |
| **Conversiones** | «¿Qué recibimos, qué ocurrió y qué explica la conversión?» Separar lecturas mensuales y del rango. Gráficos y comparación por analista con base visible; explicaciones por niveles. Conservar el título acordado «Resultados de los leads del mes». |
| **Ranking** | «¿Cómo comparo a dos responsables con la misma base?» Tabla densa en escritorio, lista legible en móvil, orden explícito, bases, exclusiones y detalle cercano. |
| **Citas** | «¿Qué citas se concretaron y cuáles requieren seguimiento?» Distribución y evolución cuando la fuente lo permita; pendientes por responsable; distinguir asistencia y realización. |
| **Metas / Rendimiento** | «¿Dónde falta avance y qué ajuste puedo realizar?» Objetivo frente a resultado, vigencia y carga actual diferenciados; consulta separada de administración. |
| **Hoy / Agenda / Pipeline** | «¿Qué hago ahora y qué sigue?» Prioridad y acción próxima, agrupación de avisos, búsqueda/filtros, referencias temporales y contexto al volver. Auditoría por rol antes del diseño específico. |
| **Cartera / Leads / Base para gestión** | «¿A quién gestiono y qué información necesito?» Identidad, estado y acción principal; filtros con alcance claro, filas legibles, detalle y regreso. |
| **Repartir / Derivaciones / Gestión de equipo** | «¿Qué debo asignar o supervisar?» Estados de asignación, capacidad y responsable; revisión previa en operaciones sensibles; mismos permisos y reglas. |
| **Nuevo lead / ficha / inversión o contrato** | «¿Qué datos necesito para completar esta operación?» Obligatorios primero, opcionales agrupados, validación en línea, guardado y recuperación según capacidades reales. |
| **Configuración y lectura por rol** | «¿Qué puedo consultar o cambiar?» Ubicación familiar, explicación del bloqueo cuando sea útil y retorno al origen. No se concede acceso nuevo ni se muestran datos restringidos. |

Estos módulos definen la cobertura del plan; no significa que todos hayan sido auditados o rediseñados en esta entrega. El orden después de Gerencia se decide con frecuencia real, impacto y error, no por facilidad de dibujar la pantalla.

## Reglas de gráficos comerciales

- Cada gráfico responde una pregunta, identifica unidad/período/población y dispone de cifras consultables. Explicación extensa ampliable, contexto indispensable visible.
- Capital confirmado y meta se comparan en la misma moneda y TC. Si falta TC o la meta no es comparable, mostrar desgloses y estado; no fabricar avance.
- Conversión del rango y meta mensual sólo se comparan cuando comparten base y período. La propuesta demo identifica explícitamente la conversión mensual.
- Citas pactadas y realizadas pueden mostrarse como cantidades comparables; no apilar estados solapados como partes de un 100 % ni inventar un embudo.
- «Resultados de los leads del mes» sigue su contrato actual. Leads que cerraron, cierres por fecha y conversión ponderada son lecturas diferentes.
- No añadir ingresos, rentabilidad, crecimiento, previsiones ni tendencias históricas para las que no exista una fuente comparable verificada.

## Componentes y recursos de Figma

La búsqueda se realizó por MCP sobre bibliotecas disponibles en el archivo. Se consultaron Accordion, Table, Input y Chart; el servidor limitó la primera petición a una búsqueda y las tres restantes se ejecutaron por separado.

| Recurso localizado | Uso previsto y decisión |
| --- | --- |
| **Simple Design System: Accordion / Accordion Item** | Anatomía para detalle ampliable. Adaptar al patrón existente «Cómo se calcula» y a los estilos del CRM. |
| **Simple Design System: Table** | Inspeccionado en Figma: es un icono de 48 px con variantes de tamaño. Descartado como tabla funcional; se conserva la tabla propia del CRM. |
| **Simple Design System: Input Field / Date Input Field** | Ayuda, error y estados del campo. Base de implementación: Input del CRM. |
| **Material 3: selectores de fecha y Text field** | Referencia de interacción táctil y estados. No adoptar su tipografía, formas y paleta como identidad nueva. |
| **Simple Design System: Bar chart** | Inspeccionado en Figma: es un icono de 48 px con variantes de tamaño. Descartado como gráfico funcional. Se conservan ECharts y las fuentes vigentes del CRM. |
| **Lucide y ECharts existentes** | Conservar iconos y gráficos del proyecto; diseñar sus variantes necesarias en Figma con datos de ejemplo trazables. |

Cada candidato debe registrar origen, enlace/clave, finalidad, compatibilidad, costo/licencia si aplica, accesibilidad pendiente, adaptación y decisión. No se instalarán dependencias ni se comprarán kits durante esta preparación. La biblioteca nueva debe tener responsable de revisión, documentación de estados y correspondencia con código; los componentes anteriores se deprecian explícitamente, nunca desaparecen por sorpresa.

Referencias primarias: [Simple Design System de Figma](https://github.com/figma/sds), [kits de interfaz en Figma](https://help.figma.com/hc/en-us/articles/24037724065943-Start-designing-with-UI-kits). La disponibilidad de un kit no acredita su ajuste al CRM ni cumplimiento de accesibilidad.

## Límites del PDF al aplicarlo aquí

- La experiencia por rol se mejora visualmente sin cambiar permisos.
- «Deshacer», guardado optimista, reintentos automáticos y operación offline sólo se ofrecerán si la operación existente los soporta. No afirmar un guardado antes de su confirmación; ante respuesta incierta, comprobar estado antes de repetir.
- Recuperar formularios y contexto se diseña sin persistir indiscriminadamente datos personales. No se añadirá grabación de sesiones, heatmaps ni telemetría externa en esta fase.
- Se usarán 44 × 44 px como objetivo táctil del producto. No se confunde con el mínimo de WCAG 2.2 AA: [W3C 2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html); la referencia de 44 px corresponde al criterio mejorado [W3C 2.5.5](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced).
- Mantener texto normal con contraste suficiente, teclado, foco visible, zoom, información equivalente en gráficos y reducción de movimiento. No declarar conformidad completa basándose sólo en Figma.
- Exportación para reuniones, command palette y cambios amplios de arquitectura continúan condicionados a una tarea confirmada. No forman parte automática del nuevo diseño.

## Entrega en Figma y revisión

Archivo existente: [Gerencia · UX de reportes · Avance Corp](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK). La página de propuestas `108:2`, creada como «07 · UI-UX (2) · Plan y propuesta», se llama ahora **03 · Propuestas · UI-UX (2)**. La portada **00 · Inicio y estado** lleva al trabajo vigente y las páginas 90–95 conservan los antecedentes. Los identificadores y enlaces a los diseños se mantienen.

La página reúne evidencia actual con notas, elementos propios reutilizados, muestras externas evaluadas y propuesta inicial de Resumen/Conversiones en escritorio y móvil. Cada pantalla debe indicar su estado de propuesta, datos demo y recorrido disponible. La propuesta inicial permite revisar dirección y jerarquía; las pantallas restantes y todos los estados forman parte de la ejecución posterior del plan.

| Entregable preparado | Enlace directo |
| --- | --- |
| Plan resumido en el lienzo | [Leer primero](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=121-283) |
| Cinco capturas actuales y notas | [Evidencia conservada](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=109-2) |
| Biblioteca propia existente | [Componentes del CRM](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=2-2) |
| Muestras externas evaluadas | [Recursos y decisiones](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=110-2) |
| Resumen vigente | [UI-UX (3) escritorio](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=209-733) · [Móvil compacto reutilizado](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=162-718) |
| Resumen anterior, escritorio / móvil | [Escritorio](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=112-14) · [Móvil](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=113-55) |
| Conversiones, escritorio / móvil | [Escritorio](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=113-366) · [Móvil](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=113-734) |
| Recorrido de revisión | [Prototipo de escritorio](https://www.figma.com/proto/1FEvjQkwSzNDsGJ7UUvqIK?node-id=112-14&page-id=108%3A2&starting-point-node-id=112%3A14&scaling=scale-down&content-scaling=fixed) · [Prototipo móvil](https://www.figma.com/proto/1FEvjQkwSzNDsGJ7UUvqIK?node-id=113-55&page-id=108%3A2&starting-point-node-id=113%3A55&scaling=scale-down&content-scaling=fixed) |

Navegación acotada: Resumen ↔ Conversiones → comparación fija Carla/Bruno y regreso; en móvil, abrir filtros y volver. Los accesos a Citas, Ranking y Metas del pie abren referencias de diseño previas, no un recorrido operativo integrado. Búsqueda, alta, cambio de filtros, cambio de analistas y detalles de esa comparación son ilustrativos en esta muestra. Las pantallas de ejemplo no guardan cambios en el CRM.

Para revisar: identificar el resultado principal, explicar su período/base, localizar un asunto que requiere revisión, abrir evidencia y regresar. Registrar si se logra sin ayuda, interpretación, tiempo, pasos y errores. Miguel puede corregir la dirección visual sobre el local durante la ejecución de hoy.

## Definición de terminado

El plan está preparado cuando cada prioridad tiene problema, tarea, pantalla, componente, datos vigentes, propuesta y prueba de cierre. El diseño está aprobado cuando Miguel revisa las pantallas y recorridos correspondientes. La implementación está terminada cuando pasa revisión visual, interacción, estados, accesibilidad y regresión de datos en el CRM. Son tres estados distintos.

Una prueba automática no sustituye observar al usuario. Una muestra de Figma no acredita que el CRM completo esté implementado. No se promete error cero ni una mejora porcentual sin medir. Publicar conserva su autorización y verificaciones independientes; este trabajo permanece local y en Figma.

Relacionado: [[Replanteamiento UI UX con UI-UX 2 - 2026-09-05]], [[AVC-UX-GERENCIA-FIGMA-20260905-R1]].
