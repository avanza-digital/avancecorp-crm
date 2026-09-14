---
fecha: 2026-09-10
estado: analizado-pendiente-seleccion-del-usuario
tags: [crm, citas, gerencia, metricas, proyeccion, excel]
---

# Citas Gerencia — análisis del Excel de proyección por analista

## Alcance solicitado

Miguel quiere incorporar otras métricas al módulo de Citas, usando un Excel como referencia. Pidió avanzar paso a paso: analizar primero; después él indicará qué quiere trasladar al sistema. **Este análisis no aprueba cambios en el módulo ni sustituye sus reglas vigentes.**

Fuente: `CRM-Avance-Corp/PROYECCION DE VENTAS 2026 X ANALISTA (1).xlsx`. La copia del mismo nombre en Descargas tiene contenido idéntico. SHA-256: `45c7f0d17129654e3d2f85686779137b26db67a779f7c4af39248268874655e5`.

## Estructura y lógica comprobadas

Una hoja, `medicion`, con ocho analistas en las filas 6–13. El bloque principal es A2:Q16. No contiene registros individuales de leads, citas, asistencias o depósitos. Los encabezados históricos dicen «Mes Anterior», sin identificar un mes o fechas. El año 2026 está en el nombre del archivo.

| Bloque | Celdas | Contenido |
| --- | --- | --- |
| Histórico ingresado | B6:D13 | Cantidad de leads, número de depósitos y monto captado |
| Objetivos ingresados | F6:H13 | Citas 125%, entrevistas 70%, depósitos 70%, iguales para los ocho analistas |
| Promedio por depósito | J6:J12 | Monto histórico / depósitos históricos; J13 está vacío |
| Citas proyectadas | K6:K13 | Leads históricos × 125% |
| Entrevistas proyectadas | M6:M13 | Citas proyectadas × 70% |
| Depósitos proyectados | O6:O13 | Entrevistas proyectadas × 70% |
| Ventas proyectadas | Q6:Q13 | Depósitos proyectados × promedio histórico por depósito del analista |

El comentario de K5 confirma «TOTAL LEADS * 125%». Aunque el encabezado dice «RESULTADO DE TU TRABAJO», K/M/O/Q contienen **proyecciones**, no resultados reales cargados. Los dos 70% son supuestos introducidos manualmente; no tasas calculadas del histórico.

Los totales guardados son 921 leads históricos, 4.793.984 de monto histórico, 1.151,25 citas, 805,875 entrevistas, 564,1125 depósitos y 26.207.113,50854779 de monto proyectado. La suma independiente de C6:C13 da 108 depósitos históricos; C16 no los totaliza. No asumir moneda: las columnas monetarias principales no la identifican; solo la celda auxiliar I16 tiene formato de soles.

## Diferencias que requieren decisión de negocio

1. **Base del 125%.** El Excel calcula 1,25 citas por lead: 100 leads → 125 citas. La regla vigente de Citas es 3 citas por lead = 100%; 125% = 3,75 citas por lead. No son el mismo indicador y no se debe cambiar uno por el otro sin decisión del usuario.
2. **Población de leads.** El Excel no define si «Cantidad Leads» son todos los asignados, nuevos, trabajados o los que tienen cita. El promedio vigente de Citas usa leads distintos con al menos una cita dentro de la consulta. Es necesario acordar población, período y atribución al analista antes de comparar metas y resultados.
3. **Entrevistas.** El Excel no define si equivalen a citas realizadas, personas que asistieron o un evento comercial distinto. No dar por establecida esa equivalencia.
4. **Depósitos.** El Excel no define si cuenta operaciones o personas. En el indicador vigente de recuperación, conversión a cliente acredita depósito y la unidad es un lead distinto. Varias citas o entrevistas de la misma persona no pueden producir varias conversiones contadas como clientes distintos. Si se sustituyera 1,25 por 3,75 manteniendo 70% × 70%, saldrían 183,75 depósitos por cada 100 leads; eso no sería válido como cantidad de clientes únicos convertidos.
5. **Dinero.** Contar una conversión no acredita por sí solo su importe. La proyección necesita una fuente histórica y moneda definidas; no usar capital estimado de la cita como monto real depositado. Tampoco equiparar automáticamente captación con ingreso contable por el encabezado «Ventas».
6. **Recuperación de inasistencias.** El archivo agregado no permite reconstruir quién no asistió, quién reprogramó, quién asistió después y quién se convirtió a cliente. El seguimiento individual existente debe conservarse con sus relaciones y cronología.
7. **Períodos.** No hay fechas, detalle semanal ni serie de meses en este archivo. La relación con el filtro de mes y cuatro semanas comerciales del CRM requiere una decisión explícita sobre el histórico base y el período proyectado.

## Observaciones de calidad

- B12, leads de Tomislav, está vacío pese a tener depósitos y monto histórico. Las multiplicaciones lo tratan como cero y anulan toda su proyección: falta de dato y cero real deben distinguirse.
- Daniela tiene B13:D13 en cero y J13 sin fórmula. No hay promedio por depósito calculable con cero depósitos; no presentar ausencia de histórico como una tasa o ticket comprobado.
- J16 usa `AVERAGE(J6:J14)`: promedio simple de los siete promedios disponibles, 45.529,03527077497. Si se desea el promedio por depósito de todo el equipo, corresponde monto total / número total de depósitos: 4.793.984 / 108 = 44.388,74074074074. El promedio simple no interviene en Q16, que suma proyecciones calculadas individualmente.
- Las cantidades proyectadas conservan decimales aunque se muestran sin decimales. Son valores esperados; para convertirlos en metas operativas enteras se debe acordar una regla de redondeo y recalcular dependencias. Sumar cifras redondeadas visibles puede diferir del total calculado con precisión completa.
- I16 suma I6:I15, un rango vacío, y muestra cero sin encabezado propio. G23 reconstruye el monto histórico de la primera analista (`J6*C6`) sin etiqueta y no alimenta las proyecciones.

## Verificación y conservación

Se inspeccionaron el XML original, valores guardados, fórmulas incluidas las compartidas, comentario de K5 y una representación visual de la hoja. Las 48 celdas con fórmulas se contrastaron con cálculos independientes; no hubo diferencias numéricas ni errores de Excel guardados. Esto verifica la aritmética, no la validez comercial de los supuestos.

Recalcular dentro de Microsoft Excel: **NOT RUN**. La importación usada para inspeccionar conserva valores, pero no expone las fórmulas hijas compartidas; su lógica se comprobó en el XML original. No se modificó ni exportó el libro. Su SHA-256 final coincide con el inicial. No se modificaron código, datos del CRM ni publicación.

## Punto de continuación

El análisis inicial quedó pendiente de la elección de indicadores de Miguel. Las aclaraciones siguientes actualizan ese punto de continuación; todavía deben definirse las bases, unidades y períodos antes de implementar.

## Aclaraciones de Miguel — 2026-09-11

- La meta solicitada es **1,25 citas por lead**, equivalente a 125 citas por cada 100 leads. Su mensaje «1,25 es la meta por lead» corrige la cifra anterior «1,12%». Esta es la nueva meta de negocio solicitada; no se ha aplicado aún al código que usaba tres citas por lead.
- La meta de citas debe quedar en la **configuración interna**, sin mostrarse en el módulo como un objetivo visible.
- La base incluye **todos los leads asignados al analista durante el mes**, incluso los que todavía no tienen cita, y **excluye los leads que el propio analista registra manualmente**. Miguel confirmó: «sii todos cuentan, menos los que ellos registran manualmente». Todavía debe confirmarse si la exclusión se aplica también a las citas, entrevistas y conversiones que aportan al cumplimiento; no se ha identificado aún el dato técnico que acredita el registro manual por el analista.
- Quiere visualizar el avance real de la gestión hacia los objetivos de **70% de entrevistas y 70% de depósitos** del Excel.
- Pidió expresamente completar las preguntas y entender su intención antes de desarrollar. No se autoriza interpretar respuestas pendientes como confirmadas.
- Sigue pendiente acordar: participación de la actividad de leads registrados manualmente en el cumplimiento; definición y repetición de entrevistas; si el avance se compara con cantidades proyectadas o tasas sobre actividad real; base de personas únicas para depósitos; atribución temporal y por analista; alcance, edición y vigencia de las metas.
- Se conserva la definición ya acordada de depósito acreditado por conversión a cliente. No se ha cambiado el módulo, importado el Excel ni publicado estas nuevas metas.

## Panel de configuración solicitado — 2026-09-11

Miguel pidió después un panel de control en su usuario de Superadmin. Se implementó localmente para configurar y guardar **borradores**, con las decisiones no respondidas en «Por definir». El candidato SQL sigue pendiente de autorización e instalación. No se han activado las nuevas metas ni cambiado los cálculos vigentes. Estado, acceso, evidencia y siguiente paso: [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]].

Relacionado: [[Citas Gerencia - cierre de sesion y punto de retoma 2026-09-09]], [[Citas Gerencia - publicacion y verificacion 2026-09-09]], [[Citas Gerencia - deposito acreditado por conversion a cliente 2026-09-08]], [[Citas Gerencia - tablero horizontal y flujo por persona 2026-09-08]].
