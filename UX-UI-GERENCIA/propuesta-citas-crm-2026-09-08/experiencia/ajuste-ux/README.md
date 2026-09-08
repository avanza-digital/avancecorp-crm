# Citas: tres propuestas con menos ruido visual

Revisión del 8 de septiembre de 2026, solicitada por Miguel después de ver las tres propuestas con meta. Conserva las composiciones y los datos necesarios; modifica su jerarquía y la cantidad de elementos que compiten por atención. Son imágenes estáticas pendientes de elección, no cambios en el módulo ejecutable.

**Actualización:** Miguel eligió la **3, Detalle a demanda**. Ya está [implementada y verificada en el prototipo local](../implementacion-3/README.md). Las imágenes y verificaciones siguientes documentan la exploración anterior a esa elección.

## Abrir las versiones revisadas

En el mismo orden en que se mostraron en la conversación:

1. [Matriz esencial](matriz-esencial.png).
2. [Comparación en paralelo](comparacion-paralela.png).
3. [Detalle a demanda](detalle-a-demanda.png).

Las [versiones anteriores con metas](../metas/README.md) se conservan para comparar.

## Documento aplicado

Se leyó íntegramente el original [UI-UX.pdf](../../../../UI-UX.pdf), de siete páginas, y se inspeccionaron las páginas renderizadas 2, 3 y 5. Antes de esta revisión se habían usado las notas del vault; no se había releído el PDF original para esas tres imágenes.

- Página 2: agrupar lo relacionado por proximidad y separar con espacio; decidir la pregunta principal de la pantalla.
- Página 3: establecer prioridades y bajar el peso visual de lo secundario; no destacar todos los datos simultáneamente.
- Página 5: conservar los datos profesionales, agrupándolos y revelando el detalle por contexto.

El foco sigue siendo «qué pasó con quienes no asistieron». La actividad y las metas de los analistas forman la segunda lectura.

## Cambios de jerarquía

- Un recorrido horizontal sin tarjetas ni fondos de flechas. Mantiene las cuatro etapas, el porcentaje con su denominador y el monto.
- Se elimina la franja grande de metas y los indicadores repetidos. La referencia común aparece junto a la tabla: **Meta 3 = 100% · Objetivo 3.75 = 125%**. El promedio y cumplimiento del equipo figuran una sola vez, en el total.
- Se elimina el bloque de próximas acciones que repetía las mismas personas de la tabla. «Sin nueva cita» continúa visible en su fila.
- Se retiran columnas de estado que repetían la nueva cita, la asistencia o el depósito; también los iconos, textos explicativos y contenedores redundantes.
- Los datos comparables se alinean en tablas con reglas suaves. El ámbar identifica la excepción «Sin nueva cita»; un porcentaje menor de 100% no se presenta automáticamente como fallo.
- La primera versión usa cifras sin barras. La segunda mantiene una comparación con barras discretas y dos áreas en paralelo. La tercera muestra la ficha abierta al seleccionar a Andrea, con un recorrido breve y una acción principal.

## Dónde queda cada dato

| Información | Lectura inicial | Acceso al detalle propuesto |
| --- | --- | --- |
| Mes, semana comercial, supervisor, analista y búsqueda | Fila compacta de filtros | «Más filtros» conserva estado, modalidad, origen, resultado, seguimiento, moneda y monto |
| Ausencia → reprogramación → asistencia → depósito | Recorrido horizontal y cuatro personas del flujo | Seleccionar una etapa filtra la lista; abrir una persona muestra su historial |
| Conversión y monto confirmado del flujo | Al extremo del recorrido, con la base «1 de 4 leads» | Movimiento vinculado en la ficha |
| Citas, leads con cita, promedio y cumplimiento por analista | Tabla de los seis analistas y total | Ayuda de cálculo y consulta del analista |
| Leads con tres o más citas | Columna propia, con numerador y denominador | Personas que alcanzaron ese umbral |
| Leads con dos o más citas y realizadas | Columnas opcionales | Menú «Columnas»; no se eliminan del modelo |
| Fecha de ausencia, registro de reprogramación, cita nueva, asistencia y depósito | Fechas principales en la tabla según el espacio de cada composición | Ficha con fechas y horas completas; en la tercera imagen aparece abierta |
| Exportación y ayudas secundarias | Menú secundario | Conservar el alcance de exportación del módulo al implementar |

El menú de columnas y estas interacciones describen la propuesta; las imágenes no implementan controles. Al construir, deben funcionar con los componentes reales del CRM y conservar los filtros activos. No se agregan destinos de navegación por aparecer incidentalmente en un dibujo.

## Bases y cálculos conservados

Se reutilizan las [definiciones de metas](../metas/README.md) y los [valores calculados desde los fixtures](../metas/valores-verificados.json). No se cambió ningún dato:

- **4 no asistieron → 3 reprogramaron → 1 asistió → 1 depositó**. Leads únicos y etapas sucesivamente contenidas en la anterior.
- **25% = 1/4** de los leads iniciales; **S/35,000** confirmados después de la asistencia. No se incluyen depósitos ajenos a esa cadena.
- Equipo: **40 citas / 26 leads con cita = 1.54 citas por lead**, **51.3%** de cumplimiento, **3 de 26** leads con tres o más citas. El porcentaje se calcula antes de redondear el promedio.
- Meta: **3 citas por lead = 100%**; objetivo del promedio: **3.75 = 125%**. No se prorratea automáticamente al seleccionar una semana.
- Andrea: **2 citas = 66.7%**; su depósito ya está completado. No se propone otra cita solo para completar la meta. Depósito el **4 sep. a las 10:00**, confirmación a las **10:05**.
- Origen: citas de septiembre. Seguimiento al **7 sep. 2026, 13:00 Lima**. Las cuatro semanas comerciales siguen siendo 1–7, 8–14, 15–21 y 22–fin; se seleccionan en el desplegable.
- Los filtros de consulta recalculan los indicadores. Seleccionar una etapa cambia solo el detalle y conserva la base del recorrido y la tabla general de analistas.

## Verificación y límites

PASS: inspección visual de las tres imágenes completas; cotejo de las cifras con los valores verificados; fórmulas del promedio, cumplimiento y objetivo; existencia de los archivos y enlaces relativos; `git diff --check` del alcance entregado.

La geometría de las barras de la segunda imagen es ilustrativa y no reproduce exactamente todos los porcentajes. Al implementar, la escala y los rellenos se calculan: pista 0–125%, marca de 100% al 80% de su ancho y relleno de 46.7% del ancho para un cumplimiento de 58.3%. Las versiones primera y tercera prescinden de barras. La navegación, las fuentes y los estados interactivos se tomarán de los componentes existentes, no de detalles incidentales del raster.

NOT RUN: lint, typecheck, tests, build y pruebas de interacción/accesibilidad del producto; no hubo cambios de código. Las imágenes no prueban comportamiento, contraste medido, teclado ni adaptación móvil. La implementación y su verificación quedan pendientes de elegir una dirección.
