---
tags: [crm, supervisor, hoy, comercial, ux, propuesta]
fecha: 2026-10-18
estado: propuestas-pendientes-de-afinar
---

# Hoy supervisor - dos propuestas de indicadores comerciales (2026-10-18)

Miguel pidió analizar Hoy del supervisor porque no entiende la vista y necesita
indicadores comerciales de todo el equipo. Solicitó usar 21st y preparar dos
propuestas con criterio propio para luego afinarlas. No autorizó aún una opción
ni pidió publicar.

Se inspeccionó Hoy real y Detalle en Chrome, el código local y notas relacionadas.
Diagnóstico: alertas y cola dominan la portada; capital confirmado, meta y conversión
quedan relegados. Equipo hoy destaca capital en proceso, no ventas logradas.

Dos maquetas interactivas con personas/cifras ficticias:

1. **Resultados del equipo (recomendación inicial):** capital confirmado/meta,
   operaciones, conversión, actividad diaria y comparación por analista.
2. **Dirección de la jornada:** resultado mensual visible y bloques de contacto,
   citas por resultado y oportunidades abiertas, más tabla de actividad.

Entrega: `CRM-Avance-Corp/docs/diseno/hoy-supervisor-2026-10-18/index.html`.
Análisis, fuentes y disponibilidad: `ANALISIS.md` en la misma carpeta. Capturas
de escritorio/móvil y `VERIFICACION.md` conservan la evidencia.

21st aportó Charts & KPI Cards y Leads Data Table como referencia visual; solo
búsqueda y previews, sin descargar código ni gastar cuota. No se envió data real.

Conversión oficial y metas existen en contratos, incluidos responsables y
objetivos individuales. La futura integración debe validar cobertura, ámbito y
permisos reales. Citas por fecha prevista/estado y oportunidades por etapa requieren
conciliar sus agregados. No mezclar capital confirmado con potencial, operaciones
con personas, actividad de hoy con mes o pendientes acumulados. La conversión
viene del núcleo; la tasa de contacto usa contestadas/útiles. Las metas mantienen
la misma base de capital y foto mensual. No inventar tasas ni porcentajes.

Claude: CHANGES_REQUESTED/MEDIUM; PRIMARY corrigió estados de citas y ausencia de
datos y contrastó las hipótesis sobre metas con código. No hubo segundo dictamen.
Sintaxis, aritmética, navegación y móvil PASS. Gates del CRM NOT RUN por alcance
de prototipo aislado. Producto, SQL y publicación sin cambios.

Siguiente: afinar con Miguel la propuesta, indicadores y distribución; después
especificar la integración y sus gates. Los diseños no están aprobados.

[[Hoy del supervisor - puesto de mando en una pantalla, plan (2026-09-27)]] ·
[[Gestion Diaria - supervisor horizontal aprobado (2026-09-23)]] ·
[[Gestion Diaria - supervisor con consulta por fecha (2026-09-24)]] · [[Inicio]]
