# Plan de mejora UX · usuario Gerencia · 6 de septiembre de 2026

Base de análisis: el commit publicado del CRM (`96f2038`, el último de `main`), construido en una copia aislada con datos de demostración; recorrido de las 14 pantallas del menú de Gerencia más la pantalla Pendientes (campana), con inventario automático de todo lo que se puede pulsar en cada una (`08-produccion-2026-09-06/gerencia-completo/inventario.json`). Marco de evaluación: `UI-UX.pdf` (8 pilares, tokens §3, fases §4, temas que faltan §5, guardrails §6, checklist §7, métricas §8, orden de impacto §9).

Pendiente de contraste: recorrido sobre `crm.miavance.com` con la sesión real de Gerencia desde el Chrome de Miguel (la extensión no estaba conectada). La estructura, los enlaces y los clics son los del código publicado; los datos de las capturas son de ejemplo.

---

## 0. Plan consolidado con las indicaciones de Miguel (06/09 noche) — VIGENTE

**Indicaciones que rigen todo el trabajo**
1. Solo el usuario **Gerencia**.
2. El problema a resolver es de **experiencia**: los datos se ven pero no se puede seguir el flujo de la información. Regla: **toda cifra y todo nombre conduce** (número → lista filtrada → ficha → acción).
3. **No se cambia el diseño**: colores de producción (navy, azul, teal, verde, ámbar, rojo, gris), IBM Plex Sans en Gerencia, hero, tarjetas, gráficas. Nada se simplifica.
4. Lo que se toque debe quedar **más profesional e innovador** que hoy, con la misma identidad: cristal, degradados, mini gráficas, áreas suaves (P1 es la vara).
5. Señal de que algo abre: **flecha ↗ gris** junto al dato; el dato conserva su color; el azul solo aparece al pasar el ratón o con foco.
6. Todo se diseña y revisa en los **dos archivos nuevos de Figma**; referencias externas (Mobbin) solo como apoyo puntual.
7. Método: el playbook `UI-UX.pdf` (medir → jerarquía → componentes → estados → validar).
8. Sin tocar fórmulas, permisos ni servidor. Única excepción posible, en solo lectura: la lista de «cierres del mes» por fecha de conversión.

**Fases**

| Fase | Qué se entrega | Cómo se comprueba | Duración estimada |
|---|---|---|---|
| **F0 · Base** | Línea base de clics (hecha: T1 ≥ 6, T2 ≈ 7, T3 sin respuesta) · checklist §7 con Miguel · recorrido con su sesión real en Chrome. | Tres tareas medidas y una observación registrada. | 1 día |
| **F1 · Diseño en Figma al nivel de P1** — ✅ construida 06/09 noche | P2 Leads filtrada con miga · P3 Ficha de analista · P4 Equipo (Ranking + Rendimiento) · P5 Conversiones · P6 período y menú · P7 Citas. Acabado de producción elevado: IBM Plex Sans, paleta completa, degradados teal→verde, cristal en cabeceras, mini áreas, avatares, estado «al pasar» en una fila por pantalla. Página 02 del archivo de mockups. | Miguel revisa cada pantalla (15 min) y aprueba o corrige. | hecha |
| **F2 · Código: Resumen + Leads** | Componente «cifra con puerta» (↗ + realce al pasar) · Leads acepta filtros por URL y los muestra como miga · enlaces desde Resumen (cierres, citas vencidas, analistas, semanas, compromisos) · franja de citas vencidas · elevación visual del hero (tendencia), mini áreas en KPI, áreas en la gráfica, con el CSS y el ECharts existentes. | T1 pasa de ≥ 6 clics a 1. Antes/después en local. | 1–2 semanas |
| **F3 · Ficha de analista + Equipo** | Drawer alcanzable desde cualquier nombre, con sus leads y acciones · Equipo une Ranking y Rendimiento con pestañas. | T2 pasa de ≈ 7 clics a 2. | 1–2 semanas |
| **F4 · Conversiones + Citas + período común** | Embudo enlazado, origen enlazado, sin hero repetido, fórmulas tras «¿Cómo se calcula?» · Citas con listas de vencidas y no concretadas · barra de período que viaja y vive en la URL. | T3 pasa de «sin respuesta» a 1 clic. El rango se conserva entre pantallas. | 1–2 semanas |
| **F5 · Estados y Cartera** | Bloqueos honestos (qué pasó, a quién pedir) · paneles sin datos colapsados · Cartera con una acción por fila y menú. | Ninguna pantalla dice «revisa tu conexión» ante un permiso. | 3 días |
| **F6 · Validar y publicar** | Repetir las tres tareas · accesibilidad como puerta (contraste, teclado, foco) · móvil de Gerencia · publicación por partes con preflight. | Clics ≤ objetivo; sin regresiones; Miguel da el OK de publicación. | 3 días |

**Reglas de trabajo**: cada fase se muestra en local antes/después y Miguel aprueba; commits pequeños sobre `main`; publicar solo con su OK y tras el preflight; el Figma se actualiza con cada avance. Metas se integra en Resumen y Configuración al final de F4, si Miguel lo confirma.

**Decisiones pendientes de Miguel**: (a) Metas: integrar o conservar como pantalla; (b) Base para gestión: fuera del menú de Gerencia o con bloqueo honesto; (c) si «cierres del mes» necesita una lectura de servidor, autorizarla aparte.

---

## 1. Diagnóstico en una frase

Gerencia tiene un tablero que **enseña** bien pero no **conduce**: de las 14 pantallas, solo 2 (Leads y Pipeline) permiten llegar a un lead, y ninguna cifra de dirección (Resumen, Conversiones, Ranking, Citas, Rendimiento, Metas) abre la lista de casos que la compone. El gerente ve «3 citas vencidas» o «Ana Torres 31.50 %» y tiene que reconstruir a mano, en otra pantalla, quiénes son.

## 2. Radiografía del rol (lo que hay hoy)

| Pantalla | Pregunta que debería responder | Clics propios* | Abren un lead | Veredicto |
|---|---|---|---|---|
| Resumen | ¿Cómo vamos? | 1 (Ver ranking) | 0 | Lee bien, no conduce. Repite la conversión en hero y KPI. |
| Conversiones | ¿De dónde salen los cierres? | 5 | 0 | 10 bloques, hero repetido, 4 KPI repetidas, texto técnico. El detalle del analista existe pero tras un select. |
| Ranking | ¿Quién rinde y por qué? | 6 (pestañas) | 0 | Filas no pulsables. Color por puesto sin regla. |
| Citas | ¿La agenda se cumple? | 0 | 0 | Hero repetido, 6 KPI en 7 colores. «3 vencidas sin resultado» sin lista. |
| Metas | ¿Vamos a llegar? | 1 (Administrar) | 0 | Casi vacía; duplica Resumen › Avance de metas y Configuración › Metas. |
| Rendimiento («Equipo») | ¿Quién tiene capacidad? | 5 (lápiz límite) | 0 | Dos tableros pegados con dos bases distintas (36 y 84). «8 leads sin atender, Diego Vega 3» sin enlace. |
| Pipeline | Operar | 39 | 15 | Funciona. |
| Leads | Operar / consultar | 20 | 20 | Filas abren ficha. Filtros solo etapa y analista; no viven en la URL. |
| Agenda | Operar | 15 | 0 (vía expandir) | Agrupada por persona, expandible: buen patrón. |
| Cartera | Operar | 13 | 0 | 4 botones por fila. |
| Repartir leads | Operar | 9 | 0 | En demo: «No tienes permiso… revisa tu conexión». |
| Base para gestión | Operar | 1 | 0 | Igual: permiso + red en el mismo mensaje. |
| Gestión de equipo | ¿Cómo va cada supervisor? | 5 | 0 | «Ver equipo» expande en línea: buen patrón. Asignar funciona. |
| Configuración | Administrar | 8 (Abrir) | 0 | La pantalla más navegable del rol. |
| Pendientes (campana) | ¿Qué requiere mi decisión? | — | 0 | Estado vacío honesto: bien redactado. |

\* Sin contar los globales (Nuevo lead, Ayuda, campana, Aplicar).

**La misma cifra en cinco sitios.** La conversión del mes (23.06 %) aparece en Resumen (dos veces), Conversiones, Metas y Rendimiento. La conversión por analista aparece en Resumen, Conversiones, Ranking, Rendimiento y Citas, con cinco formas visuales distintas y ninguna pulsable.

## 3. Línea base de fricción (Fase 0 del playbook, medida en demo)

| Tarea real de Gerencia | Hoy | Objetivo |
|---|---|---|
| T1 · ¿Quiénes son las citas vencidas sin resultado que anuncia Resumen? | Resumen → «Revisar Citas» → Citas no tiene lista → Agenda → «Todo» → expandir persona por persona → abrir tarea. ≥ 6 clics y se reconstruye a mano. | 1 clic: la cifra abre la lista. |
| T2 · ¿Qué leads cerró Ana Torres este mes? | Resumen › Mejores analistas lleva al ranking general (no a Ana) → filas no pulsables → Conversiones → select Ana → Ver detalle → solo cifras → Leads → filtro analista → etapa «Convertido» (inventario de 45 días, no cierres del mes). ≈ 7 clics y respuesta aproximada. | 2 clics: nombre → ficha de analista → «4 cierres» abre la lista. |
| T3 · ¿De qué origen vienen los cierres del mes? | Conversiones › Resultados por origen: «cifras en revisión, ocultas». Citas › «Citas que terminan en cliente» es un sustituto. Leads no filtra por origen. Sin respuesta directa. | 1 clic desde Resumen: origen → lista de cierres. |

Falta completar la Fase 0 con Miguel: checklist §7 por pantalla en una sesión de 45 minutos y una observación de 20 minutos usándolo con datos reales, sin explicación previa.

## 4. Hallazgos por pilar del documento

**Pilar 1 · Psicología y percepción.** Carga cognitiva alta por repetición (mismo dato en varias pantallas) y por texto técnico visible («aporte 1.15», «núcleo», «elegible no significa elegida», «base histórica 84 no equivale a llegadas únicas»). Modelo mental del gerente: resultado → responsable → casos → acción. El CRM organiza por tipo de dato, no por esa cadena.

**Pilar 2 · Fundamentos visuales.** Dos tipografías (IBM Plex Sans en Gerencia, Plus Jakarta Sans en el resto): el rol parece otro producto. Color sin semántica: verde/ámbar por puesto en Ranking, siete colores en seis KPI de Citas, teal decorativo en tarjetas, seis colores de etapa en Leads. Escala de espaciado con valores arbitrarios (0.69 rem, 2.35 rem, 8.3 rem).

**Pilar 3 · Arquitectura.** 14 entradas de menú en una sola lista con dirección y operación mezcladas. Cinco pantallas responden la misma pregunta («quién convierte»). Metas es una pantalla para dos tarjetas. No hay recorrido por tarea; hay recorrido por tabla.

**Pilar 4 · Interacción.** Faltan affordances: nada indica que un nombre o una cifra no se pueden pulsar, y cuando sí se puede (Mejores analistas) lleva a otra pregunta (ranking general). Progressive disclosure existe en Agenda y Gestión de equipo («Ver equipo»), y es el patrón a extender.

**Pilar 5 · Leyes.** Tesler: el sistema ya calcula; falta que también **conduzca** (proponer el siguiente paso desde la cifra). Hick: Cartera con 4 acciones por fila. Jakob: el gerente espera que una cifra subrayada o un nombre abra algo, como en cualquier tablero. Reconocimiento sobre recuerdo: para pasar de Resumen a Agenda hay que recordar el rango y volver a ponerlo.

**Pilar 6 · Componentes.** Falta el componente central del rol: la **lista filtrada por enlace** (con miga de pan del filtro aplicado). Faltan estados: la tarjeta «Resultados por origen» oculta ocupa media pantalla; el bloqueo de permisos se disfraza de error de red.

**Pilar 7 · Accesibilidad.** Foco y teclado están cuidados (revisor a11y existente). Riesgos: color como único portador de significado en Ranking y Citas; texto de 0.66 rem en mayúsculas en etiquetas.

**Pilar 8 · Validación.** No hay medición de clics ni observación registrada del rol Gerencia. La línea base de §3 es el primer dato.

## 5. Propuestas, pantalla por pantalla

Cada propuesta dice qué conserva y qué cambia. Ninguna elimina datos profesionales: agrupa, jerarquiza y revela por contexto (guardrail §6).

### 5.1 Resumen · «¿Cómo vamos?»
- Conserva: hero navy (único en el rol), tarjetas, gráfica semanal, mejores analistas, franja de atención, compromisos de supervisores.
- Cambia: toda cifra y nombre lleva una flecha ↗ gris pequeña (abre la lista o la ficha); el dato conserva su color de producción, sin subrayado ni azul: «10 cierres» → lista de cierres del mes; «3 citas vencidas» → lista de esas citas; «Referido 10 leads» → leads de ese origen; nombre de analista → ficha del analista (no ranking general). La tarjeta de conversión repetida sale de la fila de KPI (ya hecho en local). «Resultados por origen» oculto se colapsa a una línea con motivo. «Avance de metas» absorbe la pantalla Metas.

### 5.2 Conversiones · «¿De dónde salen los cierres?»
- Conserva: los datos de los diez bloques y el detalle del analista.
- Cambia: sin hero (vive en Resumen). Orden por pregunta: embudo (llegadas → contacto → cita → propuesta → cierre) → por origen → por semana → operaciones elegidas. Las cuatro KPI que repiten cifras del resumen se quitan. Cada barra del embudo y de origen es enlace a la lista. El nombre del analista abre su ficha directamente (fuera el select). Las explicaciones de fórmula van a «¿Cómo se calcula?» plegable por bloque.

### 5.3 Ranking + Rendimiento → **Equipo** · «¿Quién y por qué?»
- Conserva: las tres lecturas de Ranking (conversión, capital, resultados de leads del mes), la capacidad por analista con edición de límite, la agrupación por supervisor.
- Cambia: una sola pantalla con una lista de analistas y pestañas (Conversión · Capital · Citas · Capacidad). Cada fila abre la **ficha de analista** (el drawer que ya existe en Conversiones, ampliado): cifras + lista de sus leads del período + agenda + acciones (ver leads, editar límite, ver equipo). El puesto se muestra sin color; la meta se muestra con texto («83 % de la meta»). Las dos bases (36 y 84) no conviven en la misma vista: una etiqueta de período aclara cuál se está mirando. «8 leads sin atender · Diego Vega 3» se vuelve enlace a esos 8 leads.

### 5.4 Citas · «¿La agenda se cumple?»
- Conserva: todos los conteos, presencial vs. virtual, resultado final, tabla por analista.
- Cambia: sin hero. Seis KPI en un solo acento, con la relación explícita (82 pactadas → 58 realizadas → 15 no concretadas → 17 clientes). «3 vencidas sin resultado» y «15 no concretadas» son enlaces a la lista de citas (hoy no existe: se construye sobre Agenda con filtro por estado). Cada analista de la tabla abre su ficha.

### 5.5 Metas
- Se integra: el avance vive en Resumen; la administración en Configuración › Metas (ya existe). Metas deja de ser entrada de menú o queda como atajo a Configuración. Si Miguel prefiere conservarla, gana contenido: meta vs. real por analista, con enlace a cada uno.

### 5.6 Leads (la pieza clave de todo el plan)
- Conserva: tabla, ficha al pulsar la fila, KPIs.
- Cambia: acepta filtros por enlace (analista, supervisor, origen, etapa, rango de fechas, estado de cita, «cerrado en el período») y los muestra como **miga de pan** en la cabecera: «Resumen › Citas vencidas sin resultado · 01–06 set. · 3 leads». La barra «Distribución por etapa» filtra al pulsar un tramo. Los filtros viven en la URL: un enlace compartido abre la misma lista.

### 5.7 Cartera
- Una acción primaria según el estado del cliente («Registrar primera inversión» si no tiene contratos; «Gestionar» si los tiene) y menú «…» con el resto. Nada se elimina.

### 5.8 Repartir leads y Base para gestión
- Estado honesto: si Gerencia no tiene permiso, el mensaje lo dice y ofrece a quién pedirlo, sin mencionar la red. Si no las opera nunca, salen del menú de Gerencia.

### 5.9 Gestión de equipo y Agenda
- Se conservan como están: son los dos mejores patrones del rol (expandir en línea). En Agenda, la persona expandida gana «Ver sus leads» y cada tarea abre la ficha.

### 5.10 Menú lateral
- De 14 entradas planas a tres grupos: **Dirección** (Resumen, Equipo, Conversiones, Citas) · **Operación** (Pipeline, Leads, Agenda, Cartera, Repartir leads, Gestión de equipo) · **Administración** (Configuración, con Metas dentro).

### 5.11 Período común
- Una barra de período para todo Dirección, persistente al navegar y en la URL. Donde el dato solo existe por mes cerrado (Ranking, Metas), la etiqueta lo dice: «Mes calendario · setiembre».

## 6. Componentes nuevos o ajustados (los mínimos)

1. **Cifra enlazable**: valor + destino + affordance (subrayado punteado, flecha en hover, foco visible). Sustituye a la KPI muda.
2. **Lista filtrada por enlace con miga de pan** (en Leads y en Agenda): lee los filtros de la URL, los muestra, permite quitarlos uno a uno.
3. **Ficha de analista** (drawer): ya existe en Conversiones; se hace alcanzable desde cualquier nombre y gana lista de leads + acciones.
4. **Barra de período global** con etiqueta de tipo (rango / mes cerrado).
5. **«¿Cómo se calcula?»** plegable, uno por bloque; sustituye a los párrafos técnicos visibles.
6. **Estado bloqueado honesto**: qué pasó, por qué, a quién pedir.
7. **Panel colapsado por falta de datos**: una línea con motivo, no media pantalla.

### 6.1 Cómo se señala lo que abre (decisión de Miguel, 06/09 tarde)
Miguel descartó pintar las cifras de azul con subrayado y flecha («muchos elementos») y también la alternativa de solo chevrón; pidió **la disposición de la primera propuesta con los colores naturales de producción**. Regla vigente:
- El dato conserva su color y su peso (navy de Gerencia, verde, teal, ámbar donde ya los hay).
- Junto a cada cifra o nombre que abre algo va una **flecha ↗ pequeña en gris** (#7c8794). Nada se subraya; ninguna cifra se pinta de azul.
- Al pasar el ratón: la tarjeta o fila se eleva, el borde toma el azul de producción al 30 % y la flecha se vuelve azul, exactamente como ya hace la tarjeta «Mejores analistas». Con teclado, el anillo de foco que ya usa el CRM.
- El objetivo es la tarjeta o la fila completa (Fitts), no la cifra.

## 7. Colores y tipografía: se conservan los de producción

Decisión de Miguel (06/09 tarde): **mejorar la experiencia, no rediseñar**. No se propone paleta nueva ni unificar tipografías. Se inventaría lo que existe para que las propuestas lo usen tal cual:
- **Paleta de Gerencia** (`chart-theme.ts`, `gerencia.css`): navy `#16334d`, blue `#1f4e79`, cyan `#2a7ba8`, teal `#2ba8a0`, green `#2f9e63`, amber `#c9820e`, red `#d16456`, muted `#7c8794`, line `#e8e3da`, soft `#f8f6f1`, track `#f0ece4`. El verde sigue (leads que cerraron, barras de analistas).
- **Resto del CRM**: navy `#111e3d`, azul `#2563eb`, ámbar `#d97706`, rojo `#dc2626`, violeta `#7c3aed`, gris `#64748b`.
- **Tipografía**: IBM Plex Sans en los reportes de Gerencia y Plus Jakarta Sans en el resto; ambas se mantienen.
- **Lo único que se añade**: la señal de apertura descrita en 6.1.

Las observaciones sobre color por puesto o valores de espaciado arbitrarios (§4, pilar 2) quedan registradas como recomendaciones futuras, no como parte de este plan.

## 8. Fases, criterios de cierre y métricas

| Fase | Contenido | Cierre |
|---|---|---|
| **0 · Medir** (2 días, sin código) | Línea base §3 (hecha en demo) + checklist §7 con Miguel + observación de 20 min con datos reales. | Tres tareas con clics contados y tres pantallas con issues de Nielsen anotados. |
| **1 · Señal de apertura** (3 días) | Componente «cifra con puerta» (↗ gris + realce al pasar) sobre los colores y tipografías de producción, sin tocar nada más. | Toda cifra o nombre enlazable usa la misma señal; ningún color nuevo. |
| **2 · Número → lista → ficha** (2–3 semanas) | Leads con filtros por URL y miga; cifras enlazadas en Resumen y Citas; nombre de analista → ficha en todas las pantallas. | T1 = 1 clic, T2 = 2 clics, T3 = 1 clic. 14/14 pantallas con al menos una salida a leads. |
| **3 · Período común** (1 semana) | Barra global, persistencia, URL. | Cambiar de pantalla conserva el rango; un enlace compartido reproduce la vista. |
| **4 · Pantallas de dirección** (2–3 semanas) | Equipo unificado, Conversiones sin hero y por embudo, Metas integrada, menú en tres grupos. | La conversión aparece una vez por pantalla; cada pantalla responde una pregunta declarada en su subtítulo. |
| **5 · Estados y Cartera** (1 semana) | Estados honestos, paneles colapsados, Cartera con una acción. | Ninguna pantalla muestra «revisa tu conexión» ante un permiso; ninguna fila con más de una acción visible. |
| **6 · Validar** (1 semana) | Repetir las tres tareas y la observación; accesibilidad como gate (contraste, teclado, foco). Revisión móvil del rol. | Clics ≤ objetivo; sin regresiones a11y; móvil sin scroll horizontal. |

**Métricas del producto (§8 del playbook)**: clics por tarea (T1/T2/T3), pantallas con salida a leads (2 → 14), repeticiones de la cifra de conversión (5 → 1), bloques de texto técnico visibles por defecto (Conversiones 5 → 0).

## 9. Riesgos y guardrails

- **No se elimina información profesional**: se agrupa y se pliega. Las fórmulas siguen accesibles.
- **PEN y USD jamás se suman** (regla de la casa): las listas y fichas mantienen la separación.
- **No se inventan umbrales**: un color de estado solo aparece cuando existe una regla definida (meta, SLA).
- **Permisos**: las listas enlazadas solo pasan filtros; el servidor sigue limitando lo que cada rol ve.
- **Dato «cierres del mes»**: la etapa «Convertido» de Leads es inventario de 45 días, no cierres del período. La lista de cierres debe salir de la fecha de conversión. Si no existe una lectura de lista para ello, será el único punto del plan que toque servidor, en solo lectura, y se decide aparte.
- **Datos demo vs. reales**: Repartir leads y Base para gestión pueden comportarse distinto con sesión real; se verifica en el recorrido pendiente.

## 10. Figma (archivos nuevos, separados del trabajo anterior)

- **Flujos** (FigJam): https://www.figma.com/board/TAdFQI94B2DABzSLU8I9kI — mapa actual del rol, las tres tareas hoy vs. propuesto, arquitectura «número → lista → ficha → acción».
- **Mockups** (Design): https://www.figma.com/design/1OD5qEmCz7CI1IuNBm642E — 01 auditoría con capturas anotadas · 02 propuestas P1–P6 sobre el diseño de producción · 03 inventario de colores y tipografía actuales (se conservan).

Evidencias: `08-produccion-2026-09-06/gerencia-completo/` (capturas largas, inventario de interactivos, sondas).

## 11. Dirección visual: elevar, no simplificar (decisión de Miguel, 06/09 noche)

Miguel rechazó los primeros mockups por planos: sustituían el hero de cristal (degradado, brillo, rejilla, pastillas con desenfoque) y las tarjetas de producción por formas sólidas «de 2010». Regla: **el rediseño debe verse más profesional e innovador que producción, con su misma identidad.** P1 se rehizo en alta fidelidad:
- Hero: degradado real 132° (#112d46 → #1a4867 → #1f6c72), brillo radial teal y azul, rejilla de 32 px, pastillas de cristal con desenfoque de fondo y borde luminoso, tendencia de 4 semanas (sparkline) y chip de meta.
- KPI: borde superior de color, círculo decorativo, icono y **mini gráfica de área** con degradado en el color de la tarjeta.
- Gráfica semanal con **áreas degradadas** bajo las líneas y tooltip «Ver los 47 leads ↗».
- Barras de analistas y metas con el degradado teal→verde que ya define `gi-fill`; avatares con iniciales.
- Misma paleta e IBM Plex Sans; la señal de apertura sigue siendo la flecha ↗ gris.

Referencias consultadas en Mobbin (página 04 del archivo de mockups): Vapi (mini área en KPI), Zoho CRM (jerarquía de tarjeta), Twenty (tooltip «Click to see data»), Zendesk Sell (título con chevrón como puerta), Jobber (embudo con flechas), Visitors (área suave). Se toman detalles, no el estilo; ninguna iguala el hero que el CRM ya tiene.
