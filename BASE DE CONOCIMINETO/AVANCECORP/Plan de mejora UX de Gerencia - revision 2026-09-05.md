---
tags: [crm, ux, gerencia, plan, figma]
fecha: 2026-09-05
revision: integra-figma-mcp-en-diseno-y-validacion
estado: auditoria-experta-completa-plan-propuesto-validacion-con-gerencia-pendiente
---

# Plan de mejora UX de Gerencia — revisión con Figma MCP del 5 de septiembre

Relacionado con [[Plan de mejoras UX-UI del CRM]], [[Fundamentos UX del CRM]], [[Acceso y roles del CRM]], [[Inventario de indicadores de Gerencia - Contrato de lectura]] y [[Plan de correccion de metricas de Gerencia - requerimiento vigente]].

**Serial para comenzar en otra sesión:** [[AVC-UX-GERENCIA-FIGMA-20260905-R1]]. Contiene el estado comprobado, las fuentes y el arranque de F0/F1.

## Alcance, evidencia y estado

Miguel pidió analizar de nuevo al usuario de **Gerencia**, investigar buenas prácticas de UX para reportes y mejorar su plan. Esta edición actualiza F0–F5 con la auditoría y con el uso previsto del MCP de Figma para producir diseños editables, organizar las revisiones y comprobar la implementación frente a una referencia visual. El [PDF original de Gerencia](../../output/pdf/plan-ux-gerencia-crm-avance.pdf), del 23 de agosto, queda como antecedente; esta nota es el plan vigente.

Se completó una **auditoría experta de los reportes locales**, con 14 capturas de escritorio y ancho móvil, navegación, DOM y comprobaciones puntuales de foco. Evidencia, fortalezas y límites: [informe completo con capturas](../../output/ux-gerencia-2026-09-05/informe-auditoria.md).

La aplicación se revisó en Gerencia demo: los datos son sintéticos. No se pudo acceder a las pantallas internas de producción. No se observó trabajar a usuarios reales ni se validaron escrituras comerciales. **La auditoría y la preparación documental de F0 están terminadas: el tablero real de Figma contiene las 14 capturas, un inventario de 9 familias de componentes y 7 tareas vinculadas. El contraste con Gerencia sigue pendiente; F0 no se presenta como validada.** Los diseños del piloto, el prototipo y la implementación UX están pendientes. Evidencia y archivo: [[F0 Gerencia - tablero Figma y base UX 2026-09-05]]. Los cambios de métricas o de otras sesiones tienen seguimiento propio.

Figma se incorpora al proceso de trabajo. Las prioridades siguen siendo que Gerencia entienda las cifras, identifique asuntos relevantes, compare con contexto y llegue a las operaciones que ya tiene autorizadas. La disponibilidad del conector no demuestra que una pantalla esté diseñada, implementada o validada.

## Límite de implementación confirmado: frontend

Miguel pidió confirmar que el plan no toca backend. **El alcance de F0–F5 queda limitado a diseño y frontend:** disposición, textos, navegación, estado de consulta, tablas, gráficos, accesibilidad y adaptación a dispositivos.

- No incluye cambios de base de datos, migraciones SQL, funciones del servidor, permisos, reglas de negocio ni fórmulas canónicas de los indicadores, aunque alguna fórmula se encuentre en código del frontend.
- Se reutilizan datos, filtros y operaciones que los servicios existentes ya permiten. Filtrar filas visibles no se presentará como filtrar toda la empresa ni como recalcular un indicador global. La comparación requiere datos completos y equivalentes; no se inventan agregados con información parcial o paginada.
- Las mejoras de metas y capacidad aclaran la interfaz y usan las operaciones vigentes. No añaden revisiones históricas, nuevas garantías de guardado ni idempotencia del servidor. Las pruebas de escritura se realizan sólo en escenarios controlados.
- Los reportes de F4 se limitan a presentar o exportar datos disponibles en el navegador, con alcance y vigencia explícitos. Reportes programados, envío automático, nuevas consultas agregadas y cierres históricos almacenados quedan fuera.
- Si un entregable depende de una capacidad de backend inexistente, se registra como dependencia fuera de alcance y se adapta la propuesta a lo disponible. No se modifica backend dentro de este plan.

La primera ejecución también verificará que las mismas entradas conservan las mismas cifras y reglas. Un cambio visual puede alterar accidentalmente la lectura o el flujo; «sólo frontend» no sustituye la verificación de regresión.

### Estado de Figma y continuidad

Miguel autorizó organizar las 14 capturas y observaciones en Figma y luego indicó «vamos con la f0». El [archivo de Gerencia](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=2-6) ya está creado en Borradores de El equipo de Avance Corp y su contenido fue verificado. Retomar ese archivo, sin crear un duplicado. Estado y nodos: [[F0 Gerencia - tablero Figma y base UX 2026-09-05]].

Miguel eligió usar su ventana habitual del navegador, donde tiene iniciada la sesión de Figma. No abrir otra sesión de navegador como sustituto. La conexión remota por MCP ya fue autenticada: `whoami` confirmó Miguel Briceño, El equipo de Avance Corp, plan Profesional y asiento Full. La creación, edición y subida de las 14 capturas comprobaron el acceso efectivo al archivo. Véase [[Conexion Figma MCP verificada - UX Gerencia 2026-09-05]].

Al retomar: cargar las skills correspondientes, leer los nodos guardados y consultar el archivo antes de modificarlo. La biblioteca inicial del equipo es una plantilla de aprendizaje; el inventario de F0 parte del código y de las capturas del CRM. La biblioteca nativa y el piloto editable se preparan en F1. No confundir acceso al MCP, documentación preparada, diseño implementado y validación con usuarios.

## Usuario y objetivo de experiencia

Gerencia supervisa resultados y puede operar globalmente en el ámbito comercial autorizado. Necesita pasar de una cifra a una explicación, comparar responsables y decidir si corresponde una acción. El flujo propuesto es:

**Resumen → asunto o resultado → comparación → evidencia → acción existente → resultado comprobable → regreso a la consulta.**

| Necesidad del rol | Pregunta comercial | Respuesta que debe facilitar el CRM |
| --- | --- | --- |
| Supervisar resultados | ¿Cómo vamos y qué revisar primero? | Resultado, objetivo vigente y asuntos sustentados en datos. |
| Entender | ¿Por qué cambió esta cifra o difiere de otra? | Definición, fechas, base y atribución a la vista; detalle disponible. |
| Comparar | ¿Qué equipo o analista requiere seguimiento y con qué evidencia? | Resultados comparables, denominadores y capacidad actual diferenciada. |
| Operar | ¿Qué casos revisar y qué puedo hacer? | Responsable, casos y acceso a la operación existente, con alcance y resultado claros. |
| Comunicar | ¿Puedo explicar esta consulta en una reunión? | Contexto de período, moneda, definición y vigencia; formato de salida por validar. |

Esto es un modelo de tareas basado en el rol y el producto, no una entrevista ni una medición de hábitos. F0 debe confirmar frecuencia, prioridad, uso del celular y necesidad de compartir reportes con las personas disponibles de Gerencia. [NN/g: análisis de tareas](https://www.nngroup.com/articles/task-analysis/).

## Hallazgos que cambian el plan

| Evidencia | Implicación para Gerencia | Decisión de diseño propuesta |
| --- | --- | --- |
| Resumen y Citas repiten cifras en cabecera y tarjetas (capturas 1 y 7). | Hay mucho contenido antes de identificar una revisión concreta. | Una presentación por indicador principal y un bloque visible de asuntos pertinentes. |
| «Capital total» presenta un orden que en demo coincide con cumplimiento, no con monto (3). | Puede interpretarse mal quién ocupa el primer puesto. | Hacer explícito el criterio de orden; confirmar la regla antes de cambiarla. |
| Conviven mes, rango, horizonte de seis meses y capacidad actual (1, 3, 7, 11). | Un filtro superior puede parecer aplicable a todo. | Identificar el período y alcance efectivos de cada bloque. |
| Atrás devuelve «Conversión general» después de salir de «Capital total» (6). | Se pierde el punto de comparación. | Conservar pestaña y contexto al regresar. |
| El detalle por analista está lejos del inicio y bloquea el fondo (4 y 5). | Investigar y comparar exige desplazamiento y memoria. | Acercar el acceso y probar comparación conjunta para dos responsables. |
| Rendimiento ya incluye atención, capacidad y criterio de orden (11). | Existe una base para dirigir la revisión. | Reutilizarla y conectarla con casos y acciones. |
| En 390 × 844 el título superior de Ranking tiene ancho visible de 0 píxeles (14). | La cabecera pierde su función de orientación. | Corregir cabecera y menú desde la primera entrega. |
| Metas separa consulta y administración y muestra revisión (8 y 9). | Hay un patrón comprensible que conservar. | Mejorar etiquetas, enlaces y vuelta al contexto; validar guardado por separado. |

## Plan de ejecución propuesto

Las prioridades describen impacto esperado en las tareas. Se conserva la numeración F0–F5 para mantener el seguimiento previo. El esfuerzo es relativo y preliminar; incluye diseño, implementación y comprobación, y no representa un calendario comprometido.

| Fase | Entregable de diseño y uso de Figma MCP | Trabajo en el CRM o con Gerencia | Condición de cierre | Esfuerzo relativo |
| --- | --- | --- | --- | --- |
| **F0. Preparar Figma y validar las tareas** | Verificar acceso, cuenta y destino. Crear el tablero con las 14 capturas y hallazgos; vincular cada problema con una tarea. Inspeccionar componentes y estilos disponibles para preparar la base del archivo. | Observar las tareas del final de esta nota y registrar una línea base. Confirmar frecuencia de uso, consulta en móvil y necesidad de compartir reportes. | Archivo accesible y contenido verificado; prioridades sustentadas en la auditoría y tareas contrastadas con Gerencia. Si la observación sigue pendiente, se declara y F0 no se presenta como validada. | Bajo–medio |
| **F1. Aclarar y conservar el contexto** | Diseñar la cabecera, filtros, navegación y estados usando los componentes existentes. Preparar un piloto de Ranking en escritorio y móvil, con acceso al detalle y regreso. Dejar reglas explícitas de período, orden, cifras y conservación de la consulta. | Corregir etiquetas, lenguaje, enlaces, estado de navegación y cabecera móvil. Verificar el recorrido Capital total → detalle → Atrás y conservar las cifras originales. | El prototipo explica el recorrido; el CRM conserva pestaña y filtros compatibles. Título y período legibles en móvil y significado de los indicadores comprendido en la prueba. | Medio |
| **F2. Resumen para decidir** | Diseñar Resumen y Citas con jerarquía clara: contexto, indicadores sin duplicación, asuntos existentes que requieren revisión y acceso a su evidencia. Preparar versiones de escritorio y móvil y estados sin alertas o sin datos. | Aplicar el diseño y conectar los destinos existentes. Mostrar las señales con su alcance real y comprobar los valores con los mismos datos de referencia. | Gerencia identifica qué revisar y lo justifica; cada indicador principal tiene una presentación clara y cada acceso lleva a un destino válido. | Medio |
| **F3. Comparar y entender resultados** | Diseñar Ranking, Conversiones y detalle por analista: orden visible, denominadores, explicación por niveles y comparación de dos responsables cuando haya datos equivalentes. Prototipar entrada, comparación, detalle y regreso. | Reutilizar datos y filtros vigentes. Confirmar cobertura antes de ofrecer comparaciones; preservar el contexto y comprobar tablas, gráficos y accesibilidad. | Gerencia compara con la misma definición y período, reconoce exclusiones y vuelve sin reconstruir su consulta. No se presentan filas parciales como totales globales. | Medio–alto |
| **F4. Pasar del reporte a la gestión** | Diseñar los recorridos desde señales a casos y operaciones existentes; aclarar consulta y administración de metas y capacidad. Representar guardado, error y respuesta incierta según las capacidades actuales. Diseñar una salida para reuniones sólo si F0 confirma la necesidad. | Conectar los recorridos sin ampliar permisos. Probar modificaciones en un entorno controlado. La eventual exportación usa únicamente datos disponibles y muestra alcance, período y corte. | El usuario entiende a quién afecta un cambio, comprueba el resultado y puede explicar el alcance del reporte. Ningún recorrido depende de una operación de backend nueva. | Medio–alto; dividir en entregas |
| **F5. Validar y preparar la entrega** | Comparar la versión de referencia en Figma con capturas del CRM en los mismos estados y tamaños. Registrar diferencias, decisiones y correcciones con enlaces a los diseños. | Repetir las tareas con Gerencia; comprobar teclado, foco, contraste, estados, navegación, dispositivos y conservación de cifras. Preparar una versión verificable conforme a las reglas de publicación del proyecto. | Recorridos acordados resueltos sin ayuda crítica ni errores de interpretación; diferencias visuales justificadas o corregidas y verificaciones pertinentes superadas. Publicar requiere la autorización correspondiente. | Transversal |

Orden: **F0 → F1 → F2 → F3 → F4**, con **F5 en cada entrega**. Cada fase de F1 a F4 sigue el ciclo **diseñar → revisar el recorrido → implementar en frontend → comprobar en el CRM y con Gerencia**. No se espera a diseñar todo el sistema para obtener la primera mejora comprobable. La auditoría ya permite preparar F1; una observación pendiente no impide avanzar en su diseño, pero impide afirmar que fue validado con usuarios.

## Entregables y organización en Figma

Usar como punto de partida un archivo de diseño llamado **«Gerencia · UX de reportes · Avance Corp»**, en el equipo que corresponda a Miguel. Si ya existe un archivo apropiado, inspeccionarlo y continuar allí para conservar su contexto. Esta organización es propuesta; debe adaptarse a las convenciones del archivo existente.

| Página o sección | Contenido y resultado esperado |
| --- | --- |
| **00 · Auditoría y tareas** | Las 14 capturas originales, observaciones y tareas relacionadas, con alcance demo explícito. Mantener las capturas en orden y sus notas asociadas; 200 px entre capturas y nueva fila sólo al superar 15, con 600 px entre filas. |
| **01 · Componentes del CRM** | Tipografía, colores, espaciado y componentes reutilizables identificados en el producto: cabecera, filtros, indicador, tabla/lista, señal de atención, panel y estados. Reutilizar el sistema vigente y documentar cualquier ajuste necesario. |
| **02 · F1 Contexto y navegación** | Piloto de Ranking, cabecera y filtros en escritorio y móvil, detalle y reglas de regreso. |
| **03 · F2 Resumen y Citas** | Pantallas propuestas, acceso a evidencia y variantes de estado relevantes para estas tareas. |
| **04 · F3 Comparación y Conversiones** | Ranking completo, explicaciones, detalle individual y comparación con cobertura de datos confirmada. |
| **05 · F4 Gestión y comunicación** | Recorridos hacia casos, metas y capacidad; salida para reuniones si se confirma. |
| **06 · Validación y decisiones** | Recorridos del prototipo, escenarios, referencia elegida para implementar, comparación con el CRM y resultados de las pruebas. |

Las propuestas nuevas deben tener capas, textos y componentes editables. Las capturas de la auditoría permanecen como evidencia. Para cada mejora registrar: problema observado, tarea afectada, diseño propuesto, datos y operación vigentes que utiliza, referencia visual y prueba de cierre. El nombre del archivo y sus páginas no equivalen a archivos ya creados: se añadirá su enlace real cuando exista.

## Cómo se usará el MCP y cómo se comprobará su resultado

El MCP remoto permite leer diseños y crear o modificar contenido nativo de Figma. La disponibilidad efectiva de sus herramientas, el plan y los permisos deben verificarse en la sesión de ejecución. [Figma: herramientas disponibles](https://developers.figma.com/docs/figma-mcp-server/tools-and-prompts/).

1. **Comprobar el acceso y el destino.** Verificar la identidad y el plan con `whoami`, y el permiso sobre el archivo. Conservar el archivo o equipo identificado por Miguel. Leer las skills correspondientes antes de crear archivos o editar el lienzo.
2. **Inspeccionar antes de diseñar.** Obtener estructura, componentes, estilos y capturas del archivo; contrastarlos con el sistema visual y los componentes actuales del CRM. Para localizar código se usa CodeGraph primero. No introducir otro sistema visual por comodidad de la herramienta.
3. **Construir por partes.** Preparar los componentes necesarios y componer las pantallas mediante contenido nativo, usando `use_figma` y las herramientas de archivos e imágenes que estén disponibles. Conservar los identificadores de los elementos para corregirlos sin duplicar pantallas.
4. **Revisar cada entrega.** Comprobar estructura y capturas después de cambios relevantes: legibilidad, textos cortados, superposiciones, espaciado, resolución de estilos y coherencia de componentes. Corregir los defectos antes de seguir ampliando esa pantalla.
5. **Comprobar las interacciones del prototipo.** Verificar qué enlaces, estados e interacciones permite editar el MCP conectado y probarlos en el visor. Si una interacción necesaria no está expuesta, resolverla en el editor o en un prototipo local de frontend; identificar esa dependencia y distinguir siempre los estados simulados de operaciones reales. La disponibilidad del MCP no garantiza la automatización de todo el prototipado.
6. **Implementar y contrastar.** Usar el diseño elegido como referencia al modificar el frontend existente. Comparar visualmente diseño e implementación con el mismo tamaño, datos y estado, y probar el comportamiento en el navegador. El código sugerido por una herramienta debe adaptarse al proyecto y pasar las comprobaciones correspondientes.

Figma permite preparar y revisar la experiencia. La comprobación del comportamiento real exige el CRM y el navegador; la validación de las tareas exige participación de Gerencia. Un diseño visualmente correcto no acredita accesibilidad, guardado correcto ni comprensión de las cifras.

## Primera entrega concreta

Al quedar disponible el conector, la primera entrega reúne el tablero de auditoría, la base mínima de componentes existentes y el piloto **Ranking en escritorio y móvil → detalle → regreso**. Debe incluir un enlace real al diseño, capturas verificadas, recorrido revisable y criterios precisos para su implementación. Prioriza dos fallos ya observados: pérdida de la pestaña al volver y desaparición del título en móvil. La primera implementación comprueba ambos en el CRM antes de ampliar el trabajo a Resumen y Citas.

Mientras no aparezcan las herramientas de Figma en esta conversación, se puede mantener el plan y preparar el material local. No se declara creado el archivo ni se atribuyen cambios a una cuenta sin haber verificado el acceso.

## F1: reglas para que las cifras se entiendan

- Cada lectura identifica **qué mide, período efectivo, población, moneda y estado del dato**. Las fórmulas completas siguen disponibles mediante «Cómo se calcula»; la explicación comercial breve queda junto al indicador.
- Diferenciar «conversión» de «cumplimiento de la meta», «asistencia» de «realización», y resultado del mes de carga actual. El título acordado **«Resultados de los leads del mes»** se conserva; si sus datos siguen un rango, ese alcance debe ser explícito junto al título.
- Mostrar «Ordenado por…» en Ranking según la regla confirmada. El color de un puesto no debe sugerir automáticamente una alerta o una meta cumplida.
- Al volver, conservar filtros compatibles, pestaña, responsable y posición. Si un destino usa otra base temporal, explicarlo. Un rango común no obliga a que todas las medidas signifiquen lo mismo.
- En móvil, reservar espacio para título y período y adaptar el menú y las acciones. Mantener la adaptación a lista que Ranking ya ofrece.

La estabilidad de filtros y navegación favorece la continuidad de la tarea; el momento de aplicar filtros depende de la intención y de la respuesta del sistema. [NN/g: diseño de filtros](https://www.nngroup.com/articles/applying-filters/). La distribución debe ajustarse al tamaño real de consulta. [Tableau: dashboards efectivos](https://help.tableau.com/current/pro/desktop/en-us/dashboards_best_practices.htm).

## F2: primera pantalla propuesta

1. **Contexto:** ámbito, período, filtros activos y actualización disponible. Evitar una sola fecha que parezca gobernar lecturas distintas.
2. **Resultados esenciales:** como punto de partida, conversión, capital, citas realizadas y avance frente a la meta pertinente. Definir la selección final con Gerencia. Cada cifra se presenta una vez y conserva acceso a su explicación.
3. **Asuntos que revisar:** hasta tres grupos relevantes de señales existentes, con cantidad, responsable, razón y destino. El número es un límite de presentación, no una cuota que se llene con avisos inventados.
4. **Comparación y evolución:** acceso a Ranking, equipos y evolución temporal con bases compatibles; compromisos de supervisores donde aporten al seguimiento.

«Lo que merece tu atención» de Rendimiento es un patrón disponible. Elevarlo al Resumen requiere respetar las reglas que lo alimentan y conectar los casos cuando haya un destino válido. Se conserva la severidad real; agrupar no rebaja su importancia.

Esta jerarquía aplica la recomendación de priorizar las necesidades de la audiencia y permitir profundizar en el detalle. [Microsoft: diseño de dashboards](https://learn.microsoft.com/en-us/power-bi/create-reports/service-dashboards-design-tips).

## F3: comparación y lenguaje

Conservar tablas para la comparación en escritorio, con identidad del responsable, columnas relacionadas próximas, denominadores visibles y orden inequívoco. Si la tabla supera el área visible, mantener referencias de fila y columna. Probar comparación de dos responsables antes de ampliar a un constructor de reportes.

El detalle individual puede seguir siendo un panel; comparar requiere una presentación donde las cifras relevantes puedan consultarse juntas. Acercar «Ver detalle» al resultado y transformar referencias textuales a otra pantalla en enlaces claros.

En Conversiones, organizar la lectura alrededor de preguntas como «qué recibimos», «qué se concretó» y «qué aporta a la conversión», manteniendo las diferencias entre fecha de llegada, fecha de cierre y cita registrada. Sustituir terminología de implementación por explicación comercial, sin modificar el contrato del indicador. [NN/g: tareas de las tablas](https://www.nngroup.com/articles/data-tables/).

Cada gráfico tendrá una finalidad reconocible, título informativo y subtítulo de medida, ámbito y período. Los valores de respaldo estarán disponibles cuando hagan falta para explicar o comparar. [Government Analysis Function: gráficos](https://analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-charts/).

## F4: conectar con la gestión y las reuniones

Desde un aviso, llegar a los casos y a la operación existente con responsable y filtros pertinentes. Antes de una modificación sensible, mostrar a quién afecta y qué cambiará; después, informar el resultado real. Si la respuesta es incierta, el diseño debe permitir comprobar el estado; no afirmar que un reintento es seguro sin soporte de la operación.

En metas y capacidad, conservar edición centralizada, revisión y agrupación por equipo. Precisar vigencia, dependencias y motivos de bloqueo; diferenciar la pantalla de consulta de la de administración. No ampliar permisos como consecuencia de una reorganización visual.

Para reuniones, confirmar primero si hace falta un enlace interno, una vista de presentación o un archivo. Implementar la salida que resuelva la tarea confirmada. Debe conservar período, ámbito, filtros, moneda/TC, definición y fecha de corte o consulta. **Un enlace que recuerda filtros sigue mostrando datos actualizables: no equivale a una fotografía histórica cerrada.** Una salida fija debe identificar los datos que incluye y su corte; la reproducibilidad histórica exige soporte verificable.

## Calidad en todas las fases

- Diferenciar cero comprobado, ausencia, carga, dato parcial y error. Mantener el último dato únicamente con estado y vigencia claros. No mostrar un porcentaje de avance esperado o una tendencia si la definición o la base comparable no existen.
- Aplicar la gramática de color acordada en [[Fundamentos UX del CRM]]. En las capturas hay verdes en puestos y resultados; revisar esa divergencia con los componentes vigentes, conservando un significado consistente. Acompañar estados de texto o forma. [W3C: uso del color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html).
- Medir contraste, comprobar foco visible, teclado, ampliación y lectura de tablas y gráficos. Como referencia, WCAG 2.2 AA requiere 4.5:1 para texto normal y 3:1 para texto grande, con las excepciones indicadas por la norma. No se ha certificado cumplimiento en esta auditoría. [W3C: contraste](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).
- Proporcionar información equivalente de gráficos mediante texto o tabla; un nombre accesible por sí solo no describe sus relaciones y valores. [W3C: imágenes complejas](https://www.w3.org/WAI/tutorials/images/complex/).
- Comprobar escritorio, tablet, ancho móvil y dispositivos reales relevantes. Respetar reducción de movimiento y evitar transiciones que impidan leer o conservar el contexto.

## Tareas de validación y definición de terminado

| Tarea | Resultado esperado |
| --- | --- |
| 1. Identificar un asunto que merece revisión, incluyendo un escenario sin alertas verificables. | Justifica su elección con evidencia; reconoce cuando no existe una señal suficiente. |
| 2. Explicar dos lecturas distintas, por ejemplo asistencia y realización, o conversión y cumplimiento. | Identifica fechas, población y significado sin tratar porcentajes diferentes como equivalentes. |
| 3. Comparar dos equipos o analistas. | Usa definición y período compatibles, considera denominadores y distingue carga actual. |
| 4. Abrir detalle y regresar al reporte. | Recupera pestaña, filtros compatibles, selección y punto de lectura; foco correcto. |
| 5. Llegar a los casos y ejecutar una acción existente en pruebas controladas. | Entiende alcance, comprueba resultado y reconoce un fallo o respuesta incierta. |
| 6. Localizar un ajuste permitido y comprobar su guardado en ese entorno. | Distingue consulta, edición y vigencia; entiende bloqueos. |
| 7. Si se confirma la tarea de reuniones, preparar y explicar una consulta o reporte. | Su destinatario interpreta ámbito, definición y corte; no confunde una consulta viva con un cierre histórico. |

Registrar por persona y tarea: interpretación y resultado correctos, ayuda necesaria, tiempo, pasos y errores. Medir antes y después con escenarios equivalentes. Si sólo participa una persona de Gerencia, informar los resultados individuales y el límite de la muestra. Las metas de tiempo se fijan después de obtener la línea base, sin prometer porcentajes de mejora sin medir.

El rediseño se considera terminado cuando Gerencia resuelve las tareas acordadas sin ayuda crítica ni errores de interpretación y conserva acceso a su gestión autorizada. Deben acompañarlo pruebas de estados e interacción, verificación visual, accesibilidad y comprobación productiva al publicar. **Entregar este plan o aprobar pruebas de métricas no equivale a haber implementado las mejoras UX.**
