Corrección de los siete hallazgos de Gerencia — 7 de septiembre de 2026.

Miguel autorizó resolver los siete puntos de [[Auditoria Gerencia frontend y consumo backend 2026-09-07]] y pidió aplicar sus soluciones concretas, sin inventar reglas. Alcance exclusivamente frontend: se extienden el selector, los adaptadores y las pantallas existentes. No hay migraciones, funciones de servidor, cambios del núcleo ni reglas nuevas de elegibilidad o ponderación.

1. Ranking, Metas y Rendimiento consultan el mes calendario seleccionado, desde el día 1 hasta hoy (mes vigente) o su último día (histórico). El adaptador conserva y valida el período. Un rango previo de Resumen/Conversiones no sustituye cifras mensuales; «Todas las fuentes» usa la RPC mensual oficial, aunque haya respuestas del rango en caché.
2. Cierres de prospectos y operaciones de cartera conservan campos distintos. El índice sigue contando ambos aportes. Ranking, detalle de analista y Rendimiento ya no presentan upgrades como cierres; sus subtotales de cierres se reconcilian.
3. Resumen identifica el porcentaje principal como «Índice comercial del período» y el avance de la meta como «Cumplimiento de la meta de conversión». Los resultados por origen conservan su definición de prospectos del período que cerraron.
4. Los resultados y las citas dependientes del rango dicen «del período». Capital, meta y el ranking mensual se identifican como mensuales.
5. El filtro admite combinaciones de Landing, Formulario, Upgrade, Referido y Renovación, compartidas por las pantallas de Gerencia. Reutiliza `useMetricasConversiones` y la RPC existente por origen; agrupa los aportes ya ponderados de `cierres_por_semana` y `conversion_operaciones`, dividiendo una sola vez por la base publicada. Respuestas ausentes, períodos/divisores incompatibles o selección vacía no equivalen a cero. Los gráficos de cohortes sin un desglose para la combinación elegida permanecen ocultos.
6. En un mes cerrado no se solicitan ni reutilizan lecturas vivas por fuente. El selector informa que ese desglose no está disponible y permite volver a Todas las fuentes para ver el índice sellado. No se fabrica un desglose histórico.
7. Reintentar en Ranking vuelve a consultar las fuentes seleccionadas y la mensual. Metas también permite reintentar ambas cuando el error mensual impide consultar una fuente.

Validación: TypeScript y lint aprobados (cuatro advertencias previas de Coverflow). Suite completa: 202 archivos, 2.960 pruebas aprobadas; después se añadió y aprobó la regresión de Rendimiento con dos cierres y un upgrade (6/6 pruebas de ese archivo). Pruebas de contrato de release: 4/4. E2E de Chromium aprobado con sesión Gerencia simulada, API exclusivamente local: rango parcial → selección Landing + Formulario + Upgrade → Ranking mensual → vista móvil de 390 px → mes cerrado. Sin desbordamiento horizontal. Se validó el contrato real de las respuestas simuladas antes de servirlas.

El control de duplicación ya supera su umbral en la base anterior: 40 clones, 702 líneas duplicadas, 0,8501 % frente a 0,8 %. No se cambió el umbral ni se añadieron clones. Es deuda previa, no una nueva regla o refactor incluido en esta corrección.

Evidencia visual simulada: [Ranking de escritorio](Adjuntos/correcciones-gerencia-2026-09-07/ranking-fuentes-desktop.png) y [selector móvil](Adjuntos/correcciones-gerencia-2026-09-07/ranking-fuentes-mobile.png).

Estado: implementación y validación completadas; publicación y comprobación productiva pendientes al redactar esta nota. Los cambios remotos de seguimiento se integraron antes de preparar la publicación. Los trabajos locales pendientes de UX y rentabilidad se conservan aparte.

Relacionadas: [[Filtro por fuente de conversion comercial 2026-09-07]], [[Conversion comercial - una sola tasa visible 2026-09-06]], [[Main unico - sincronizacion y publicacion 2026-09-04]], [[Inicio]].
