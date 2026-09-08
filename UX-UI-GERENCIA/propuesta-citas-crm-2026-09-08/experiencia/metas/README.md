# Tres propuestas con meta de citas por lead

Actualización visual solicitada por Miguel el 8 de septiembre de 2026. Mantiene las tres composiciones horizontales anteriores e incorpora **3 citas por lead = 100%** y **3.75 citas por lead de promedio = 125%**. Son imágenes estáticas; no se cambió el prototipo ni la configuración de metas del CRM.

## Abrir las propuestas actualizadas

1. [Matriz con meta](matriz-con-meta.png).
2. [Comparación con meta](comparacion-con-meta.png).
3. [Meta y ficha del lead](meta-y-ficha.png).

Conservan mes, cuatro semanas comerciales, supervisor, analista, búsqueda y filtros detallados; el flujo **4 → 3 → 1 → 1**, **25% de conversión a depósito** y **S/35.000**. La nueva meta se identifica como cumplimiento de citas, con una base distinta de la conversión a depósito.

## Cálculo y alcance

- Promedio = citas del conjunto filtrado / leads distintos con cita en ese conjunto.
- Cumplimiento de la meta = promedio / 3 × 100. Los cálculos usan valores sin redondear; el porcentaje visible se redondea a un decimal.
- Objetivo = 3 × 1.25 = 3.75 citas por lead. Ejemplo: 15 citas / 4 leads = 3.75 = 125%.
- Leads con 3+ citas = personas distintas con al menos tres citas en el conjunto. No equivale a que el promedio del asesor llegue a tres.
- La base conserva el contrato de la propuesta: citas del período filtrado, de todos los estados seleccionados, y leads que sí tienen cita. No incluye leads sin cita ni interpreta citas como asistencias.
- La referencia de 3 se mantiene al filtrar; no se inventa un prorrateo entre semanas. Antes de integrar la política de metas reales debe definirse su vigencia y cómo se relaciona con un filtro parcial del mes.
- Si no hay base, mostrar «Sin base» o «—», no un cero inventado.
- Un lead individual tiene citas enteras: 3 citas son 100%; 4 son 133.3% y superan el umbral de 125%. El promedio por asesor sí puede ser 3.75 exactamente.
- La meta de cantidad y el resultado comercial son independientes. Andrea ya depositó con dos citas; la ficha no propone agendarle otra automáticamente para completar un contador.

## Valores del mismo ejemplo, comprobados desde los fixtures

| Asesor | Citas | Leads con cita | Promedio | Cumplimiento | Leads con 3+ citas |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ana Torres | 7 | 4 | 1.75 | 58.3% | 1 de 4 |
| Bruno Castro | 6 | 4 | 1.50 | 50.0% | 0 de 4 |
| Diego Salas | 7 | 4 | 1.75 | 58.3% | 1 de 4 |
| Lucía Mendoza | 7 | 5 | 1.40 | 46.7% | 0 de 5 |
| Mateo Paredes | 7 | 5 | 1.40 | 46.7% | 1 de 5 |
| Valeria León | 6 | 4 | 1.50 | 50.0% | 0 de 4 |
| Total de la consulta | 40 | 26 | 1.54 | 51.3% | 3 de 26 |

Se importaron `consultarCitas`, `consultaInicial` y `citasPorLead` del prototipo para verificar estos números. Los resultados sin redondear están en [valores-verificados.json](valores-verificados.json). Los tres leads con al menos tres citas son Ricardo Benavides (4), Andrés Villanueva (3) y Mariana Fuentes (3). Andrea Peralta tiene 2 citas, 66.7% de su meta individual; Ana como asesora tiene 58.3%.

## Criterios para implementar la dirección elegida

Las barras deben compartir escala con origen 0, marca de 100% dentro de la pista y objetivo de 125%. Una pista que termina en 125% debe llenarse al 46.7% de su ancho para representar un cumplimiento de 58.3%; las posiciones no se copian a ojo desde la imagen. No truncar el valor numérico si supera 125%.

Las imágenes se inspeccionaron y conservan las cifras numéricas esenciales. Tienen detalles ilustrativos pendientes: la longitud de algunas barras/marcas no reproduce exactamente la escala solicitada; la segunda conserva 10:05 como fecha del depósito, que corresponde a la confirmación; hay destinos y exportaciones incidentales del dibujo que no amplían el alcance del módulo. El instante de depósito correcto es 4 sep. 10:00 y su confirmación es 10:05. En la ficha de un lead individual se recomienda una escala de citas enteras, sin representar una cita fraccionaria como evento posible. Los valores y definiciones verificados de este documento prevalecen al implementar.

## Verificación de esta entrega

PASS: cálculo directo desde los datos ficticios, comparación de bases, inspección de las tres imágenes, archivos y enlaces locales y `git diff --check`. No se alteró ninguna fuente de datos.

NOT RUN: lint, typecheck, tests de la aplicación y build; no se cambió código de producto. La entrega no demuestra interacción, escalas calculadas por código, accesibilidad ni integración de metas reales. La comparación funcional se hará al implementar la dirección elegida.
