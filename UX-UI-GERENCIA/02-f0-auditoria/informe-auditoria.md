# F0 / UX0 — Auditoría actual y línea base del CRM

Estado: **auditoría experta realizada; F0 continúa abierta por validación humana y prioridad de uso**. Autorización vigente: «ok comencemos la F0». Corresponde a UX0 de UI-UX (2), no al G-F0 histórico. No autoriza reanudar implementación ni publicar.

## Resultado principal

La base funcional sirve: comparación mensual, navegación, detalle de Ranking y adaptación de Cartera a lista móvil. La prioridad es hacer visibles resultado, objetivo y evolución sin perder el significado de cada cifra. Se registran **9 hallazgos priorizados**, tres recorridos de consulta y 14 capturas actuales.

Cinco superficies provisionales: Resumen, Conversiones, Ranking, Cartera de clientes/contratos y Nuevo lead. Se eligieron por el trabajo activo, el rechazo visual de Conversiones y la muestra del plan, **no porque se haya demostrado que son las cinco más usadas**. La pregunta de frecuencia y tareas a Miguel sigue pendiente.

## Alcance y evidencia

- Chrome del perfil habitual, modo Gerencia demo, servidor local existente en 127.0.0.1:5173. No se usó la pestaña de producción.
- Capturas de esta ejecución: escritorio 1440 × 960 y móvil 390 × 844. Los datos comerciales son sintéticos.
- 14 estados capturados, guardados e inspeccionados. Las capturas transitorias de Nuevo lead y Cartera se sustituyeron por las estables; Resumen móvil se recapturó desde scroll 0.
- Cartera móvil muestra el área de filtros y primera ficha tras desplazarse, no un primer pliegue comparable con Resumen. No se deduce un recorte defectuoso del CRM a partir de ese desplazamiento.
- El viewport móvil es emulación de ancho. No se probó un teléfono físico ni su teclado virtual.
- Las fechas 01–05 setiembre de 2026 son el ejemplo actual; el mes de Ranking es setiembre de 2026. La demo mantiene Aplicar/origen deshabilitados; esto impide validar filtros reales y no se registra como fallo del producto.
- CodeGraph se consultó primero; cuando devolvió segmentos incompletos o símbolos de otro módulo, se leyó de forma puntual la fuente faltante. No se reindexó ni se usó Graphify.
- Referencia de trabajo: rama main, HEAD 77c9200 con cambios locales anteriores/concurrentes. Las capturas corresponden al árbol de trabajo, no a un artefacto limpio de ese commit.

## Decisiones de prioridad

P1 = afecta lectura comercial, entrada de un dato esencial o continuidad con teclado; debe resolverse en el bloque correspondiente antes de aprobarlo. P2 = afecta densidad, claridad o consistencia y se incorpora a su fase. La prioridad no es una predicción de frecuencia. No se observó un bloqueo total de los tres recorridos de consulta; no se probaron escrituras ni condiciones de red.

### UX0-01 · P1 · Resumen · escritorio/móvil

**Observación:** La jerarquía desplaza los gráficos debajo de los KPI y de bloques de explicación. En móvil, el título de evolución empieza aproximadamente en y=1785 desde scroll 0.

**Consecuencia:** La lectura rápida exige desplazarse y reconstruir mentalmente resultado, objetivo y evolución.

**Propuesta:** Diseñar el primer bloque comercial con indicadores y comparación visual; resumir período y filtros; agrupar atención y explicaciones sin perder contexto.

**Se prepara en:** UX1 → UX2 / bloque A. **Cierre:** A 1440 × 960 y 390 × 844 se identifican resultado, período y objetivo; un gráfico útil aparece antes de los detalles extensos. Prueba de comprensión con Gerencia pendiente.

**Evidencia:** pasos 1, 11. Observado en capturas actuales y geometría DOM.

### UX0-02 · P1 · Conversiones · escritorio/móvil

**Observación:** El bloque principal y varias secciones de texto anteceden a la lectura visual; Resultados por analista está en y≈1965 en escritorio y y≈3764 en móvil.

**Consecuencia:** Cuesta comparar el desempeño y decidir dónde profundizar. Miguel ya rechazó esta presentación.

**Propuesta:** Separar visualmente conversión mensual, resultados de llegadas y cierres por fecha. Jerarquizar gráficos y llevar definiciones extensas a detalle ampliable.

**Se prepara en:** UX1 → UX2 / bloque A. **Cierre:** Las tres bases se distinguen sin abrir ayuda; los gráficos conservan sus valores y unidades; mismo acceso a comparación y detalle.

**Evidencia:** pasos 2, 12. Observado. La rapidez de comprensión aún no se midió con una persona.

### UX0-03 · P1 · Conversiones · indicador Capital del mes

**Observación:** La tarjeta abreviada dice Capital del mes y muestra S/ 1.48 M; Resumen muestra capital confirmado unificado S/ 1,840,096 y su desglose PEN/USD/TC.

**Consecuencia:** La misma expresión comercial puede interpretarse como dos totales incompatibles.

**Propuesta:** Explicitar si el importe es sólo PEN o el total equivalente ya disponible; mantener visible la existencia de USD y el contexto del TC cuando corresponda. Reutilizar el dato servido y el componente de monedas.

**Se prepara en:** UX1 → UX2 / bloque A. **Cierre:** Cada tarjeta declara moneda y alcance. La lectura de 1.48 M PEN se distingue de 1,840,096 equivalentes sin recalcular ni cambiar fórmulas.

**Evidencia:** pasos 1, 2, 12. Diferencia visible confirmada en la demo; comprobar la variante real durante validación autorizada.

### UX0-04 · P1 · Nuevo lead · móvil

**Observación:** Capital estimado dispone de sólo 43 × 36 px a 390 × 844, junto al selector de moneda de 96 px.

**Consecuencia:** El campo obligatorio deja muy poco espacio para revisar un importe antes de enviarlo.

**Propuesta:** Diseñar capital y moneda con ancho suficiente y orden adaptable; conservar el campo numérico, moneda, validaciones y obligatoriedad.

**Se prepara en:** UX1 → UX3 / bloque C. **Cierre:** Importes representativos largos se pueden leer, editar y revisar en móvil; probar teclado virtual en un dispositivo real antes de cerrar.

**Evidencia:** pasos 9. Medición DOM y captura. Teclado virtual real no probado.

### UX0-05 · P2 · Nuevo lead · orden y tamaño de controles

**Observación:** Seis campos opcionales se intercalan entre Teléfono y los obligatorios Origen/Capital. Campos y botones principales miden 36 px de alto; categorías, 25 px.

**Consecuencia:** Aumenta el recorrido hasta completar lo esencial y deja controles por debajo del objetivo táctil de producto de 44 px.

**Propuesta:** Agrupar primero los cuatro datos obligatorios y mover información adicional a una sección clara. Diseñar variantes táctiles preservando todos los campos.

**Se prepara en:** UX1 → UX3 / bloque C. **Cierre:** Los cuatro requisitos se reconocen al iniciar; campos secundarios y errores siguen accesibles; áreas táctiles se revisan con la regla del plan, sin afirmar conformidad WCAG a partir de esta medida.

**Evidencia:** pasos 8, 9. Orden, etiquetas y medidas confirmados. Ahorro de tiempo pendiente de medir.

### UX0-06 · P1 · Cartera → ficha de cliente → cerrar

**Observación:** Tras buscar NADIA, abrir Ver detalle y cerrar, la búsqueda se conserva pero document.activeElement es BODY; el foco no regresa al botón de la fila.

**Consecuencia:** Quien navega con teclado pierde su punto de trabajo.

**Propuesta:** Llevar a la ficha el mismo patrón de recuperación de foco ya comprobado en Ranking.

**Se prepara en:** UX1 → UX4 / UX5. **Cierre:** Cerrar y Escape devuelven el foco al control de origen; la búsqueda y filtros permanecen. Si el control desaparece, existe un destino de foco coherente.

**Evidencia:** pasos 6, 7. Observado en DOM inmediatamente después y en una segunda comprobación; falta recorrido completo con lector de pantalla.

### UX0-07 · P2 · Cartera · escritorio/móvil

**Observación:** Cuatro acciones por cliente; nombres largos abreviados en escritorio y especialmente en móvil. La adaptación a lista móvil ya funciona.

**Consecuencia:** Compiten las acciones y se dificulta identificar visualmente al cliente con poco ancho.

**Propuesta:** Conservar la lista adaptable; probar acción principal según tarea confirmada y secundarios en menú con etiquetas claras; dar más espacio al nombre o permitir leerlo completo.

**Se prepara en:** UX1 → UX3 / bloque C. **Cierre:** Se conservan todas las operaciones permitidas y se identifica al cliente sin adivinar su nombre. La acción principal se elige con frecuencia de uso, no por preferencia del auditor.

**Evidencia:** pasos 6, 10. Capturas confirmadas; frecuencia de acciones pendiente de Miguel/usuarios.

### UX0-08 · P2 · Ranking · Capital total

**Observación:** Las barras se ven llenas para resultados entre 108.74% y 127%; el porcentaje textual sí los distingue. Existe verde en esta vista frente a la regla documental sin verde.

**Consecuencia:** La longitud deja de ayudar a comparar los resultados por encima de la meta; queda una decisión visual de consistencia pendiente.

**Propuesta:** Especificar cómo mostrar sobrecumplimiento con referencia a 100% y valores originales; documentar qué colores actuales se conservan o ajustan en UX1.

**Se prepara en:** UX1 → UX2 / bloque B. **Cierre:** Orden, porcentaje, importes y metas permanecen; se entiende quién supera la meta y en qué medida; la decisión de color queda documentada.

**Evidencia:** pasos 4, 13. Observación visual y comparación con Fundamentos UX. No se considera error de la fórmula.

### UX0-09 · P2 · Cabecera móvil · Conversiones

**Observación:** El título se presenta como Conversi… a 390 px, junto a la etiqueta Demo y tres controles.

**Consecuencia:** La cabecera pierde legibilidad justo cuando el menú usa iconos.

**Propuesta:** Ajustar prioridades, ancho y variantes de cabecera aprovechando la familia existente; mantener los nombres accesibles de las acciones.

**Se prepara en:** UX1 → UX2. **Cierre:** El destino se reconoce en la cabecera de móvil, sin solapar acciones ni perder acceso. La etiqueta de entorno puede compactarse manteniendo su significado.

**Evidencia:** pasos 12. Confirmado en la captura móvil; los nombres de accesibilidad sí existen.

## Línea base de tres tareas

Son recorridos del agente sobre datos de demo, no una prueba con usuarios. Se cuentan acciones semánticas: clic, selección de opción o entrada de texto; se excluyen capturas, lecturas DOM, esperas y operaciones de preparación. No son clics humanos mínimos ni métricas de velocidad.

| Tarea | Inicio → fin | Acciones observadas | Resultado técnico | Tiempo y éxito humanos |
| --- | --- | --- | --- | --- |
| T1 | Resumen → Conversiones → comparación Carla/Bruno → Resumen | 5: 3 clics y 2 selecciones | Consulta completada; misma base mensual visible. | Pendientes |
| T2 | Resumen → Ranking → Capital total → detalle Carla → Ranking | 4 clics | Mes, pestaña y foco recuperados. | Pendientes |
| T3 | Ranking → Cartera → buscar NADIA → detalle → cerrar | 4: 3 clics y una entrada de texto | Consulta y búsqueda conservadas; foco termina en BODY. | Pendientes |

La comparación permaneció abierta y con Carla/Bruno al volver a Conversiones durante la revisión móvil; después se cerró para capturar la vista principal. No se modificaron cifras, registros ni filtros de producción. Nuevo lead se abrió y se cerró sin rellenar ni enviar.

## Checklist de las diez heurísticas

| Heurística | Evidencia de esta auditoría | Estado / siguiente comprobación |
| --- | --- | --- |
| Visibilidad del estado | Períodos, demo, selección de Ranking y contexto de comparación visibles. | Parcial: carga, red lenta y respuesta incierta no ensayadas. |
| Relación con el lenguaje comercial | Conversión mensual frente a llegadas explicado; ambigüedad en Capital del mes. | UX0-03; revisar denominación y monedas. |
| Control y libertad | Ranking regresa con contexto y foco; ficha de Cartera conserva búsqueda pero pierde foco. | UX0-06. |
| Consistencia | Tablas/listas existentes aprovechables; diferencias de color, títulos y tamaño. | UX0-05 / 08 / 09. |
| Prevención de errores | Requisitos del formulario marcados y foco inicial; capital móvil demasiado estrecho. | UX0-04 / 05. Validación y guardado reales pendientes. |
| Reconocer antes que recordar | Detalle conserva responsable/mes; nombres truncados y menú sólo con iconos en móvil. | UX0-07 / 09; prueba de reconocimiento pendiente. |
| Flexibilidad y eficiencia | Tres consultas alcanzables y comparación conservada. | Línea base técnica preparada; frecuencia y tiempo humanos pendientes. |
| Claridad y economía visual | Exceso de altura anterior a gráficos y datos clave. | UX0-01 / 02 / 05. |
| Reconocer y recuperarse de errores | No se indujeron fallos de red ni se enviaron formularios. | Pendiente en matriz UX4; no inferir validación por existir código de estados. |
| Ayuda y documentación | Cómo se calcula, períodos y advertencias de bases aparecen en los reportes. | Preservar contenido y revisar su facilidad de lectura en UX2. |

## Accesibilidad focal: qué sí se comprobó

- Ranking escritorio devuelve el foco al botón de Carla después de Volver a Ranking.
- Ranking móvil abre con Enter; Shift+Tab desde el primer control llega al último dentro del diálogo; Escape cierra y restaura foco y pestaña.
- Nuevo lead recibe foco en Nombre completo y permite cerrar con Escape; no se evaluó el envío.
- Ficha de Cartera: foco en BODY después de cerrar, comprobado dos veces en el estado estable.
- Controles del formulario: 36 px de alto y categorías de 25 px; contraste y excepciones de objetivos táctiles no certificados. El objetivo de 44 px procede del plan de producto.
- No se detectó desbordamiento horizontal del documento en Resumen, Conversiones y Ranking a 390 px. Esto no acredita que todos sus gráficos internos y estados sean accesibles.
- Pendientes: lector de pantalla real, recorrido completo sólo con teclado, contraste sistemático, zoom/reflow a 200–400%, reducción de movimiento, otros roles, datos reales, red y teclado virtual.

## Observaciones que necesitan otra reproducción

Al navegar de Cartera a Resumen después de una búsqueda en móvil, el contenedor conservaba scrollTop=197.5 y ocultaba el comienzo del período. Se restableció el desplazamiento a 0 para la captura aceptada. Se registra como riesgo de continuidad a reproducir con un recorrido móvil estable, separado de los nueve hallazgos confirmados; el cambio de viewport y el foco pueden influir. No se solicita cambiar globalmente todos los comportamientos de scroll.

El título Resultados por semana de llegada en la demo debe revisarse frente a la granularidad de sus puntos al diseñar el gráfico. No se revisó en esta ejecución la serie del backend ni se declaró defectuosa la fórmula.

## Qué se conserva y qué pasa a F1

| Base anterior | Decisión en F0 | Preparación para UX1 |
| --- | --- | --- |
| Marca, logo, menú y nombres conocidos | Conservar. | Registrar anatomía y variantes de cabecera. |
| Nueve familias y 72 variables Figma | Reutilizar como inventario inicial; no certificar estados por existir. | Matriz componente ↔ código ↔ estado; documentar la diferencia de paleta observada. |
| G-F1: Ranking, contexto y regreso | Revalidación focal positiva en escritorio y móvil. | Aplicar el patrón de foco a otros diálogos cuando se apruebe su implementación. |
| G-F2: Resumen/Citas | Aprovechar datos y destinos. La jerarquía de Resumen necesita revisión. | Indicadores comerciales, gráficos, contexto compacto y atención. |
| G-F3: comparación y Conversiones | Comparación y base conservadas; UI principal requiere rediseño. | Desgloses claros de alcance/moneda y detalle ampliable. |
| G-F4: revisión previa de metas/capacidad | Conservar como antecedente; no retestado en F0. | Estados de lectura, guardado y confirmación; validación integral pendiente. |
| Cartera y Nuevo lead | Reutilizar búsqueda, lista móvil, campos, requisitos y permisos. | Tabla/lista con acciones, formulario adaptable y foco del diálogo. |

UX1 queda con una entrada concreta: **Indicador y moneda; Cabecera y Período; Acción; Tabla/Lista; Campo; Diálogo; Estado y detalle ampliable**. Primero se especifican variantes y estados en Figma; el código continúa pausado. Las propuestas anteriores de Resumen/Conversiones son material de diseño a revisar, no pantallas ya aprobadas o implementadas.

## Puerta de cierre de F0

- [x] Contexto del plan vigente y avances anteriores revisados.
- [x] Inventario documental de 21 rutas por rol y dependencias de visibilidad.
- [x] Cinco superficies provisionales auditadas en escritorio y móvil.
- [x] 14 capturas actuales y nueve hallazgos con evidencia, prioridad y fase.
- [x] Tres recorridos técnicos con acciones contadas y resultados registrados.
- [x] Guion y plantilla de prueba humana preparados.
- [ ] Miguel confirma las cinco pantallas más usadas y las tres tareas más frecuentes.
- [ ] Observar al menos a una persona sin dirigirla; registrar resultado, tiempo, acciones y errores.
- [ ] Ajustar prioridades y registrar decisión de cierre con esa evidencia.

F0 no está al 100%. La parte experta permite revisar y preparar la siguiente fase; la prueba humana pendiente no se reemplaza con pruebas automatizadas. No se fija un ahorro de tiempo, fecha final ni tasa de éxito sin medición.

## Evidencia visual por paso

Las imágenes siguientes son capturas del CRM local de esta ejecución. Sus textos explican el estado, lo que funciona y los límites de la observación.

### Paso 01 · Resumen · escritorio — Mejorar jerarquía

Los indicadores explicitan mes y base. El gráfico de evolución queda al final de la primera pantalla. Priorizar lectura visual y conservar las aclaraciones. UX0-01.

![Paso 1: Resumen · escritorio](evidencia/01-resumen-desktop.jpg)

### Paso 02 · Conversiones · escritorio — Prioridad alta

El bloque principal y el texto anteceden a los gráficos. Capital del mes muestra sólo S/ 1.48 M; revisar la etiqueta y el desglose sin cambiar cálculos. UX0-02 / UX0-03.

![Paso 2: Conversiones · escritorio](evidencia/02-conversiones-desktop.jpg)

### Paso 03 · Comparar Carla y Bruno — Base aprovechable

Selección de ambos analistas comprobada. Misma base mensual explícita, valores distintos y acceso a detalle. Conservar la comparación existente; no confundir conversión con cumplimiento.

![Paso 3: Comparar Carla y Bruno](evidencia/03-comparacion-desktop.jpg)

### Paso 04 · Ranking · Capital total — Base aprovechable

Orden por cumplimiento declarado. Las barras llenas no diferencian 108.74–127%; el verde se revisará frente a la regla visual documentada. Mantener importes y orden. UX0-08.

![Paso 4: Ranking · Capital total](evidencia/04-ranking-capital-desktop.jpg)

### Paso 05 · Detalle de Carla · escritorio — Recorrido comprobado

Al volver se conservan Capital total, setiembre 2026 y el foco en Carla. Reutilizar esta mejora de G-F1. No se modifica ningún dato.

![Paso 5: Detalle de Carla · escritorio](evidencia/05-ranking-detalle-desktop.jpg)

### Paso 06 · Cartera · escritorio — Ajustar acciones

Cuatro acciones por fila compiten con nombres largos. Separar la acción habitual de las secundarias. Los indicadores explicitan qué filtros afectan a cada uno. UX0-07.

![Paso 6: Cartera · escritorio](evidencia/06-cartera-desktop.jpg)

### Paso 07 · Buscar NADIA → Ver detalle — Revisar foco

La búsqueda se conserva al cerrar. El foco vuelve a BODY, no al botón que abrió la ficha: hallazgo confirmado por DOM. Datos sintéticos de demo. UX0-06.

![Paso 7: Buscar NADIA → Ver detalle](evidencia/07-cartera-detalle-desktop.jpg)

### Paso 08 · Nuevo lead · escritorio — Reordenar campos

Hay cuatro obligatorios; seis opcionales se intercalan antes de Origen y Capital. Nombre recibe el foco y el pie de acciones permanece visible. No se envió el formulario. UX0-05.

![Paso 8: Nuevo lead · escritorio](evidencia/08-nuevo-lead-desktop.jpg)

### Paso 09 · Nuevo lead · móvil — Prioridad alta

Capital estimado mide 43 × 36 px a 390 × 844; resulta demasiado estrecho para revisar un importe. Mantener campo y moneda, darles espacio suficiente. Escape cierra. UX0-04.

![Paso 9: Nuevo lead · móvil](evidencia/09-nuevo-lead-mobile.jpg)

### Paso 10 · Cartera · móvil — Ajustar densidad

Lista adaptada a móvil, sin tabla horizontal. La captura muestra filtros y primera ficha después de desplazar. El nombre queda abreviado y persisten cuatro acciones. UX0-07.

![Paso 10: Cartera · móvil](evidencia/10-cartera-mobile.jpg)

### Paso 11 · Resumen · móvil — Prioridad alta

Captura desde scroll 0. El bloque de período y la atención preceden a los KPI; la evolución empieza en y≈1785. Compactar contexto y acercar indicadores/gráficos. UX0-01.

![Paso 11: Resumen · móvil](evidencia/11-resumen-mobile.jpg)

### Paso 12 · Conversiones · móvil — Prioridad alta

Comparación cerrada. El título se abrevia y el bloque principal se prolonga más allá del primer pliegue; Resultados por analista aparece en y≈3764. UX0-02 / UX0-09.

![Paso 12: Conversiones · móvil](evidencia/12-conversiones-mobile.jpg)

### Paso 13 · Ranking · Capital total / móvil — Base aprovechable

Pestañas y listas legibles; primera ficha desde y≈615. Mes y selección conservados al navegar. Revisar densidad y representación de cumplimiento. UX0-08.

![Paso 13: Ranking · Capital total / móvil](evidencia/13-ranking-mobile.jpg)

### Paso 14 · Detalle de Carla · móvil — Teclado focal comprobado

Enter abre. Shift+Tab recorre el límite del diálogo; Escape cierra y devuelve el foco a Carla conservando Capital total. No acredita accesibilidad completa.

![Paso 14: Detalle de Carla · móvil](evidencia/14-ranking-detalle-mobile.jpg)

## Archivos y enlaces

- [Inventario por rol](inventario-pantallas.md)
- [Línea base estructurada](linea-base.json)
- [Guion de prueba humana](prueba-usabilidad.md)
- [Hallazgos estructurados](hallazgos.json)
- [Tablero F0 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=128-3)
- [Evidencia F0 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=128-10)
- [Plan y propuesta anteriores](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=121-283)

Base metodológica: Plan maestro UI UX del CRM — adaptación de UI-UX 2; Fundamentos UX del CRM; UI-UX (2).pdf. El inventario de rutas documenta UX de acceso, no valida ni modifica la seguridad del servidor.


## Continuación del 6 de septiembre

Miguel eligió la propuesta Resumen / desktop como dirección visual y reiteró aprovechar el desarrollo y librerías actuales. Se añadió un inventario de diez áreas y se comprobó de nuevo el regreso móvil Cartera → Resumen. [Informe de continuación con tres capturas](continuacion-2026-09-06/informe-continuacion.md). El riesgo de desplazamiento heredado no se reprodujo en dos recorridos con tamaño fijo; no se declara corregido. La validación humana y las prioridades reales siguen pendientes.
