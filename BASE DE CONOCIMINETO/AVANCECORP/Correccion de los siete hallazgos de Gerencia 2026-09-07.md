Corrección de los siete hallazgos de Gerencia — 7 de septiembre de 2026.

Miguel autorizó resolver los siete puntos de [[Auditoria Gerencia frontend y consumo backend 2026-09-07]] y pidió aplicar sus soluciones concretas, sin inventar reglas. Alcance exclusivamente frontend: se extienden el selector, los adaptadores y las pantallas existentes. No hay migraciones, funciones de servidor, cambios del núcleo ni reglas nuevas de elegibilidad o ponderación.

1. Ranking, Metas y Rendimiento consultan el mes calendario seleccionado, desde el día 1 hasta hoy (mes vigente) o su último día (histórico). El adaptador conserva y valida el período. Un rango previo de Resumen/Conversiones no sustituye cifras mensuales; «Todas las fuentes» usa la RPC mensual oficial, aunque haya respuestas del rango en caché.
2. Cierres de prospectos y operaciones de cartera conservan campos distintos. El índice sigue contando ambos aportes. Ranking, detalle de analista y Rendimiento ya no presentan upgrades como cierres; sus subtotales de cierres se reconcilian.
3. Resumen identifica el porcentaje principal como «Índice comercial del período» y el avance de la meta como «Cumplimiento de la meta de conversión». Los resultados por origen conservan su definición de prospectos del período que cerraron.
4. Los resultados y las citas dependientes del rango dicen «del período». Capital, meta y el ranking mensual se identifican como mensuales.
5. El filtro admite combinaciones de Landing, Formulario, Upgrade, Referido y Renovación, compartidas por las pantallas de Gerencia. Reutiliza `useMetricasConversiones` y la RPC existente por origen; agrupa los aportes ya ponderados de `cierres_por_semana` y `conversion_operaciones`, dividiendo una sola vez por la base publicada. Respuestas ausentes, períodos/divisores incompatibles o selección vacía no equivalen a cero. Los gráficos de cohortes sin un desglose para la combinación elegida permanecen ocultos.
6. En un mes cerrado no se solicitan ni reutilizan lecturas vivas por fuente. El selector informa que ese desglose no está disponible y permite volver a Todas las fuentes para ver el índice sellado. No se fabrica un desglose histórico.
7. Reintentar en Ranking vuelve a consultar las fuentes seleccionadas y la mensual. Metas también permite reintentar ambas cuando el error mensual impide consultar una fuente.

Validación: TypeScript y lint aprobados (cuatro advertencias previas de Coverflow). Suite completa final: 202 archivos, 2.961 pruebas aprobadas, incluida la regresión de Rendimiento con dos cierres y un upgrade. Pruebas de contrato de release: 4/4. E2E de Chromium aprobado con sesión Gerencia simulada, API exclusivamente local: rango parcial → selección Landing + Formulario + Upgrade → Ranking mensual → vista móvil de 390 px → mes cerrado. Sin desbordamiento horizontal. Se validó el contrato real de las respuestas simuladas antes de servirlas.

El control de duplicación ya supera su umbral en la base anterior: 40 clones, 702 líneas duplicadas, 0,8501 % frente a 0,8 %. No se cambió el umbral ni se añadieron clones. Es deuda previa, no una nueva regla o refactor incluido en esta corrección.

Evidencia visual simulada: [Ranking de escritorio](Adjuntos/correcciones-gerencia-2026-09-07/ranking-fuentes-desktop.png) y [selector móvil](Adjuntos/correcciones-gerencia-2026-09-07/ranking-fuentes-mobile.png).

Publicado y verificado: release `crm-20260907T173339Z-a6eefa74bfd2`, build `build-20260907T173338443Z`, commit de aplicación `a6eefa74bfd2a444233f7ccd55a3168904990cb9`, ZIP SHA-256 `16d6562577b6f6b8ec581660500a076b8a22bf022582e3301ce2fff48d44d791`. Main local y `avancecorp/main` coincidían antes de construir y publicar el artefacto limpio. El preflight verificó que contiene el commit que ya estaba publicado, `8bb960672fb2`.

[Verificación productiva HTTP](Adjuntos/correcciones-gerencia-2026-09-07/verificacion-http.json): 78 archivos, 65 hashes exactos, 12 imágenes transformadas por Hostinger y `.htaccess` protegido con 403; cero fallos. Tres lecturas de `version.json` confirmaron el build nuevo. ZIP inaccesible en CRM y portal, inventario interno de dependencias inaccesible. Acceso con contraseña habilitado y sin errores de JavaScript en navegador nuevo. La comprobación del rol Gerencia fue el E2E simulado descrito arriba; la sesión productiva disponible había cambiado a Analista y se dejó intacta.

El conector de Hostinger de la sesión no encontró el dominio. La publicación se completó con el cliente MCP oficial ya documentado en [[Deploy a Hostinger]], usando la configuración local existente. No se publicó el portal. ZIP y manifiesto se conservaron en `CRM-Avance-Corp/releases/`; rollback anterior: `crm-20260907T165158Z-8bb960672fb2.zip`.

Los cambios remotos de seguimiento se integraron. El trabajo local pendiente de UX y rentabilidad se reintegró sin incluirlo en este artefacto; TypeScript y 118 pruebas de los archivos afectados aprobaron después de resolver los conflictos. Respaldo adicional de esos siete archivos: `/private/tmp/gerencia-siete-integracion-respaldo`, stash `6bcf0426999382e5fc0a31dc96585ec225d30e21`.

Relacionadas: [[Filtro por fuente de conversion comercial 2026-09-07]], [[Conversion comercial - una sola tasa visible 2026-09-06]], [[Main unico - sincronizacion y publicacion 2026-09-04]], [[Inicio]].
