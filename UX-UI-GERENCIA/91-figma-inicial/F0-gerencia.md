# F0 de Gerencia — tablero, inventario y tareas

**Estado: preparación de F0 terminada; contraste con Gerencia pendiente.** No se presenta F0 como validada.

[Abrir F0 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=2-6) · [Componentes](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=15-2) · [Tareas](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=15-5)

Serial: AVC-UX-GERENCIA-FIGMA-20260905-R1 · 5 de septiembre de 2026.

## Entrega y alcance

Se creó el archivo «Gerencia · UX de reportes · Avance Corp» mediante el MCP remoto autenticado de Figma, en Borradores de El equipo de Avance Corp. Está abierto en la ventana habitual de Chrome, perfil Avance Corp.

- 00 · Auditoría y tareas: 14 capturas originales con notas editables, en una fila y con 200 px entre capturas. Cada hallazgo enlaza con su tarea; 28 enlaces verificados.
- 01 · Componentes del CRM: catálogo de nueve familias existentes, fuentes de código, estados, brechas y valores visuales.
- 06 · Validación y decisiones: siete tareas, línea de base conocida, guion de observación y criterios de cierre.

Esta entrega organiza evidencia y documentación nativa de Figma. Las pantallas de la auditoría son imágenes de la demo; no son pantallas reconstruidas ni un prototipo interactivo de Ranking. Los componentes nativos y las pantallas del piloto se preparan en F1. No se cambió código de la aplicación, backend, permisos ni fórmulas; no hubo publicación.

## Prioridades para F1

1. Conservar la consulta al repetir Ranking → Capital total → Conversiones → abrir y cerrar detalle → Atrás. La demo conserva el mes pero restablece Conversión general.
2. Mantener título, período y navegación utilizables a 390 × 844. En la demo el título de Ranking tiene ancho visible de 0 px.
3. Explicar el criterio de orden junto al dato. El código de clasificarRankingCapitalTotal confirma cumplimiento descendente, luego capital y nombre; hacer explícita esta lectura conserva la regla.
4. Reutilizar el panel de detalle, su cierre y devolución del foco, y completar los estados de carga, vacío, parcial, cero y error.

## Verificación realizada

| Comprobación | Resultado |
| --- | --- |
| Cuenta, equipo y edición por MCP | Confirmados; archivo creado y editado mediante herramientas reales. |
| Subida y colocación | 14 de 14 cargas correctas y dirigidas al nodo previsto. |
| Integridad | SHA-256 de las fuentes sin cambios; imageHash coincide con cada carga. |
| Dimensiones | 11 imágenes de 1440 × 960 y 3 de 390 × 844, sin estirar ni recortar. |
| Orden y separación | 14 fichas, 13 espacios de 200 px, misma fila. |
| Contenido y enlaces | Notas dentro de sus marcos y enlaces a tareas comprobados. |
| Revisión visual | Se inspeccionaron los 14 renders del tablero y las páginas de documentación. |
| Prueba con Gerencia | Pendiente; no hay tiempos, tasas de éxito ni porcentajes de mejora. |

No se repitieron pruebas automáticas de la aplicación porque esta entrega sólo incorpora documentación y contenido de Figma. La verificación del tablero no acredita accesibilidad o usabilidad de la aplicación.

## Inventario de componentes y patrones

### C1. Cabecera y acciones

[Ver ficha en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=17-3) · **Reutilizar estructura y adaptar distribución en F1**

Título, navegación y acciones globales. A 390 px el título de Ranking queda con ancho 0; Nuevo lead ocupa ~131 px. Reservar espacio al título y al período. Mantener las acciones y sus permisos existentes.

Fuente: `components/app/topbar.tsx · Topbar`.

### C2. Período y origen de consulta

[Ver ficha en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=17-7) · **Reutilizar controles y contrato de período**

Mes o rango según reporte; Desde/Hasta y Aplicar cuando corresponde. Período compartido y origen ya existen. La pestaña de Ranking tiene estado local: definir su persistencia al regresar. Capacidad actual y Altas nuevas de seis meses conservan su propio horizonte.

Fuente: `screens/hoy/gerencia.tsx · CabeceraGerencia / usePeriodoGerencia; components/gerencia/periodo-context.tsx`.

### C3. Pestañas de Ranking

[Ver ficha en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=17-21) · **Extraer patrón visual para el piloto F1**

Conversión general / Capital total / Resultados de los leads del mes. Conservar los tres significados. La pestaña vuelve al valor inicial al remontar. Capital se ordena por cumplimiento, luego monto y nombre; hacer explícito el orden sin modificarlo.

Fuente: `screens/hoy/ranking-vendedores.tsx · RankingVendedoresPanel`.

### C4. Tabla y fila móvil de analista

[Ver ficha en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=17-25) · **Reutilizar anatomía; preparar acceso al detalle**

Nombre, equipo, base, cierres y porcentaje permanecen visibles en la lista móvil. Distinguir puesto, cumplimiento y alerta. No sumar un filtro global si el conjunto disponible es parcial. Comparaciones deben usar datos completos y equivalentes.

Fuente: `screens/hoy/ranking-vendedores.tsx · RankingVendedoresPanel`.

### C5. Indicador y desglose de moneda

[Ver ficha en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=19-3) · **Reutilizar contenedor y formateo**

KpiCard recibe label, value y sub; no dibuja tendencias sin series reales. Mostrar medida, base, período y estado del dato. Conservar PEN/USD, TC y cumplimiento >100 %. En Resumen y Citas, revisar duplicación en F2.

Fuente: `components/common/kpi-card.tsx · KpiCard; components/common/desglose-monedas.tsx; components/ui/card.tsx`.

### C6. Panel lateral de detalle

[Ver ficha en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=19-7) · **Reutilizar apertura y cierre; preparar regreso en F1**

Detalle identificado por analista y período. Escape cierra y devuelve el foco al origen en la prueba demo. Mantener bloqueo del fondo y foco; completar teclado, scroll y estado de la consulta al volver.

Fuente: `components/ui/sheet.tsx; screens/hoy/inteligencia-comercial.tsx`.

### C7. Estados de datos y recuperación

[Ver ficha en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=21-3) · **Inventariados; cobertura visual de estados pendiente de F1/F5**

PanelCargando, PanelError, PanelVacio y PanelSinConexion ya existen. Ranking distingue exclusiones y no disponibles. Diferenciar cero real, ausencia, parcial, carga y error. Mostrar reintento cuando existe; no representar indisponibilidad como cero.

Fuente: `components/common/estado-panel.tsx; components/app/error-boundary.tsx; screens/hoy/ranking-vendedores.tsx`.

### C8. Botones y acciones

[Ver ficha en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=21-7) · **Reutilizar variantes vigentes**

default, accent, destructive, outline, secondary, ghost y link. Tamaños default (36 px), xs (24), sm (32), lg (40) e icon (36). Estados hover, focus-visible y disabled existentes. Revisar área táctil según ubicación; no cambiar tamaños globales por F0.

Fuente: `components/ui/button.tsx · Button / buttonVariants`.

### C9. Señal de atención y capacidad

[Ver ficha en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=34-3) · **Patrón existente para F2 y F4**

Cantidad y responsable juntos; estado Sin pendientes urgentes cuando no hay avisos. Orden por cupos explicado y capacidad actual separada del período. La severidad crítica tiene texto para lector de pantalla. Acercar evidencia y casos existentes sin convertir el aviso en una recomendación automática ni ampliar permisos. Edición y guardado requieren validación propia.

Fuente: `screens/hoy/distribucion-leads-gerencia.tsx · AtencionHoy / TarjetaAnalista / EquipoPorPersona`.

## Estilos y bibliotecas

Se inspeccionó la biblioteca existente del equipo: contiene la plantilla inicial de aprendizaje, cero componentes, cero variables y estilos de ejemplo Fuschia/Iris. El archivo nuevo muestra bibliotecas genéricas, pero no se identificó una biblioteca publicada que represente al CRM. No se importó una biblioteca ajena al producto.

Gerencia utiliza IBM Plex Sans y una paleta propia en `components/gerencia/gerencia.css`; la base general usa Plus Jakarta Sans y los valores de `index.css`. Se documentaron seis muestras de color, geometría y diferencias. La referencia para F1 es el producto existente; F0 no homologa globalmente paletas ni cambia sus significados.

## Tareas y registro de línea de base

### T1. Detectar un asunto que requiere revisión

[Ver tarea en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=17-12)

Abre Gerencia y elige qué revisarías primero. Explica el dato que sostiene esa decisión.

**Éxito observable:** Señala un asunto, su evidencia, período y responsable sin ayuda.

**Línea de base:** No observado con Gerencia. Frecuencia e importancia por confirmar.

### T2. Explicar una cifra y su base

[Ver tarea en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=17-16)

Explica el orden de Capital total y por qué asistencia y realización muestran porcentajes distintos.

**Éxito observable:** Distingue monto, cumplimiento, numerador, población, fecha y moneda/TC.

**Línea de base:** Revisión experta: contexto fragmentado. Comprensión real no medida.

### T3. Comparar responsables

[Ver tarea en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=17-30)

Compara dos analistas para decidir qué diferencia investigar. Indica si sus bases son equivalentes.

**Éxito observable:** Utiliza misma definición y período; reconoce límites de datos parciales.

**Línea de base:** Tabla y lista existentes. Necesidad de comparación conjunta por validar.

### T4. Consultar detalle y regresar

[Ver tarea en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=17-34)

Ranking → Capital total → Conversiones → abrir y cerrar detalle de analista → Atrás.

**Éxito observable:** Regresa a Capital total y a la misma consulta; conserva mes, filtros compatibles, responsable, scroll y foco pertinente.

**Línea de base:** Demo: mes conservado, pestaña restablecida a Conversión general. Escape devuelve foco a Ver detalle.

### T5. Pasar de una señal a una acción

[Ver tarea en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=19-12)

Elige un aviso de capacidad o citas pendientes y señala qué caso revisarías y qué acción existente corresponde.

**Éxito observable:** Identifica alcance y responsable; llega al caso correcto. Las escrituras se validan en entorno controlado.

**Línea de base:** Avisos visibles; no se probó editar límites ni guardar cambios comerciales.

### T6. Consultar y administrar metas

[Ver tarea en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=19-16)

Consulta una meta vigente, entra a su administración y vuelve al origen. Explica revisión, moneda y cumplimiento.

**Éxito observable:** Distingue consulta de edición y reconoce vigencia y alcance; regreso coherente.

**Línea de base:** Demo en solo lectura. Regreso visible a Configuración; guardado no probado.

### T7. Consultar en móvil y preparar reunión

[Ver tarea en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=21-12)

Repite la consulta habitual en celular. Explica cómo la compartirías en una reunión y qué contexto necesita el destinatario.

**Éxito observable:** Título y período legibles; reconoce consulta y vigencia. El formato de salida responde a una necesidad confirmada.

**Línea de base:** Solo viewport Chromium, 390 × 844. Uso real de móvil, frecuencia y formato de reunión por confirmar.

### Registro por completar con Gerencia

| Campo | Registro |
| --- | --- |
| Participante / rol / fecha | Pendiente |
| Última consulta real y decisión | Pendiente |
| Tarea / frecuencia / prioridad | Pendiente |
| Dispositivo / período / filtros | Pendiente |
| Resultado e interpretación | Pendiente |
| Tiempo / pasos / ayuda / errores | Pendiente |
| Citas textuales y decisión de diseño | Pendiente |

No hay respuesta registrada todavía a la pregunta sobre la última consulta real. Esta observación pendiente permite preparar F1, pero impide dar F0 por validada.

## Recorrido de auditoría: 14 pasos

Evidencia original de la demo local. Las imágenes son vistas del área visible con scroll interno, no capturas de toda la longitud. Datos sintéticos; no se observaron usuarios reales ni se probaron escrituras comerciales. Cada imagen siguiente es un render del tablero real de Figma con sus notas.

### 1. Resumen de escritorio — mejorable

[Abrir paso 1 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=3-2) · Tareas: T1, T2 · Fase: F2

![Paso 1: Resumen de escritorio — mejorable](evidencia/11-render-audit-1-1.png)

### 2. Ranking de conversión — buena base para comparar

[Abrir paso 2 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=3-6) · Tareas: T2, T3 · Fase: F1 / F3

![Paso 2: Ranking de conversión — buena base para comparar](evidencia/11-render-audit-1-2.png)

### 3. Ranking de capital — criterio de orden poco explícito

[Abrir paso 3 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=5-2) · Tareas: T2, T3 · Fase: F1 / F3

![Paso 3: Ranking de capital — criterio de orden poco explícito](evidencia/11-render-audit-1-3.png)

### 4. Conversiones — contenido útil con lectura exigente

[Abrir paso 4 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=5-6) · Tareas: T2, T3 · Fase: F3

![Paso 4: Conversiones — contenido útil con lectura exigente](evidencia/11-render-audit-1-4.png)

### 5. Detalle de analista — apertura y cierre correctos; comparación limitada

[Abrir paso 5 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=7-2) · Tareas: T3, T4 · Fase: F1 / F3

![Paso 5: Detalle de analista — apertura y cierre correctos; comparación limitada](evidencia/11-render-audit-2-1.png)

### 6. Regreso al Ranking — pérdida de contexto reproducida

[Abrir paso 6 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=7-6) · Tareas: T4 · Fase: F1

![Paso 6: Regreso al Ranking — pérdida de contexto reproducida](evidencia/11-render-audit-2-2.png)

### 7. Citas — definiciones presentes, prioridad diluida

[Abrir paso 7 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=7-10) · Tareas: T1, T2, T5 · Fase: F2

![Paso 7: Citas — definiciones presentes, prioridad diluida](evidencia/11-render-audit-2-3.png)

### 8. Metas — consulta clara con etiquetas por precisar

[Abrir paso 8 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=7-14) · Tareas: T2, T6 · Fase: F4

![Paso 8: Metas — consulta clara con etiquetas por precisar](evidencia/11-render-audit-2-4.png)

### 9. Entrada a administrar metas — estructura comprensible, edición no probada

[Abrir paso 9 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=10-2) · Tareas: T4, T6 · Fase: F1 / F4

![Paso 9: Entrada a administrar metas — estructura comprensible, edición no probada](evidencia/11-render-audit-3-1.png)

### 10. Rendimiento general — legible, con solapamiento de propósito

[Abrir paso 10 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=10-6) · Tareas: T3 · Fase: F3

![Paso 10: Rendimiento general — legible, con solapamiento de propósito](evidencia/11-render-audit-3-2.png)

### 11. Rendimiento y capacidad — patrón útil para extender

[Abrir paso 11 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=10-10) · Tareas: T1, T5 · Fase: F2 / F4

![Paso 11: Rendimiento y capacidad — patrón útil para extender](evidencia/11-render-audit-3-3.png)

### 12. Resumen al reducir el ancho — menú abierto invade la consulta

[Abrir paso 12 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=10-14) · Tareas: T1, T7 · Fase: F1

![Paso 12: Resumen al reducir el ancho — menú abierto invade la consulta](evidencia/11-render-audit-3-4.png)

### 13. Resumen móvil con menú plegado — demasiado contenido antes de la decisión

[Abrir paso 13 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=13-2) · Tareas: T1, T7 · Fase: F1 / F2

![Paso 13: Resumen móvil con menú plegado — demasiado contenido antes de la decisión](evidencia/11-render-audit-4-1.png)

### 14. Ranking móvil — adaptación útil con fallo en la cabecera

[Abrir paso 14 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=13-6) · Tareas: T3, T4, T7 · Fase: F1

![Paso 14: Ranking móvil — adaptación útil con fallo en la cabecera](evidencia/11-render-audit-4-2.png)

## Continuidad

Fuentes y trazabilidad local: `manifest.json` conserva capturas y huellas; `state.json` conserva los nodos reales; `componentes.json` y `tareas.json` contienen el inventario y guion; `verificacion-imagenes.json` documenta controles de integridad. `calls/` contiene solicitudes y resultados de MCP sin credenciales OAuth. Las URL efímeras de subida se guardaron sólo en /private/tmp.

Siguiente paso: contrastar tareas con Gerencia y comenzar el diseño editable de F1 según el plan vigente. La biblioteca del piloto, prototipo, implementación y validación del CRM permanecen pendientes.
