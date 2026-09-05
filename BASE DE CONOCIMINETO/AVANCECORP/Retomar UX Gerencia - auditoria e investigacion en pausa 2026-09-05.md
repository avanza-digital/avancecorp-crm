---
tags: [crm, ux, gerencia, auditoria, investigacion, retomar]
fecha: 2026-09-05
estado: pausado-por-miguel
---

# Retomar UX de Gerencia — auditoría e investigación en pausa

Relacionado con [[Plan de mejora UX de Gerencia - revision 2026-09-05]], [[Plan de mejoras UX-UI del CRM]] y [[Fundamentos UX del CRM]].

## Encargo y pausa

Miguel pidió analizar nuevamente al usuario de Gerencia, investigar en internet buenas prácticas de UX para sistemas de reportes y entregar un plan basado en esa revisión. Después pidió parar y continuar en una hora. La auditoría y el plan final siguen pendientes; no continuar automáticamente ni interpretar la pausa como aprobación de implementación.

## Entorno y autorización

- El navegador integrado no arrancó: el runtime instalado 26.901.41600 intenta cargar un servicio de la versión ausente 26.901.31953.
- Se explicó la restricción de Product Design para usar Playwright directamente y Miguel respondió «sí». Su uso para recorrer pantallas en consulta y tomar capturas está autorizado; no volver a pedirlo.
- Un intento con la cuenta documentada de QA no permitió entrar a producción. No se diagnosticó la causa, no se insistió y se vació el campo contraseña. No guardar credenciales en esta nota.
- Se inspecciona **la aplicación local con Gerencia demo**, a 1440 × 960, en `http://127.0.0.1:5189/`. Datos sintéticos: no certifican resultados, filtros ni disponibilidad productiva.
- Vite se inició con `VITE_ENABLE_DEMO=true`, sin editar configuración. Sesión de terminal de esta conversación: `34222`. Comprobar si sigue vivo al retomar; no detener servidores ajenos.
- Playwright tiene la pestaña local en índice 3. Al pausar está en `#/reuniones` (Citas). Volver a listar pestañas y tomar un snapshot antes de actuar: las referencias DOM antiguas pueden caducar.
- No se modificó código de aplicación ni se publicó nada durante esta auditoría.

## Evidencia capturada e inspeccionada

Carpeta: `output/ux-gerencia-2026-09-05/`. Las capturas son del viewport; el contenido del CRM tiene scroll interno, por lo que `fullPage` no abarca todos los paneles inferiores.

1. `01-resumen-escritorio.png`: conversión, capital y citas se repiten en cabecera y tarjetas. Trece destinos de análisis y operación conviven bajo «Principal». Período, condición demo y desglose de moneda visibles. Existe enlace explícito a Ranking. Los compromisos quedan más abajo.
2. `02-ranking-escritorio.png`: tabla comparable con base, cierres, conversión, exclusiones y mes. No hay filtro visible de equipo/analista ni acceso por fila al detalle en esa vista. Barras verdes/ámbar dependen de la posición, lo que puede sugerir severidad. Fórmula extensa en letra pequeña.
3. `03-ranking-capital.png`: la pestaña «Capital total» muestra primero 127 % de avance y al final 108,74 %, aunque el último tiene mayor capital. Proponer hacer visible el criterio de orden; comprobar la regla canónica antes de cambiarlo. Hay desglose PEN/USD y TC. El bloque inferior «Altas nuevas» usa un horizonte de seis meses bajo una vista mensual.
4. `04-conversiones.png`: explicaciones detalladas de población, fechas y atribución; el selector de analista y «Ver detalle» quedan varios bloques abajo. El DOM muestra lenguaje técnico («núcleo», «lectura viva», «fotos mensuales») e identificadores de operaciones. Hay redundancia de indicadores. No tratar las diferencias entre cifras demo como errores productivos.
5. `05-detalle-analista.png`: drawer con nombre, equipo y período. Se verificó que abre con foco en cerrar, Escape lo cierra y el foco vuelve a «Ver detalle». El fondo bloqueado limita comparar simultáneamente con otro analista. Mucho contenido explicativo; se conserva su significado al simplificarlo.
6. `06-ranking-al-volver.png`: **pérdida de contexto reproducida**: Ranking/Capital total → Conversiones → abrir/cerrar detalle → Atrás devuelve Ranking/Conversión general. El mes se conserva. La primera captura estaba en transición; se reemplazó por una captura estable y se inspeccionó esa versión.

No afirmar una auditoría completa de accesibilidad. Se comprobó sólo el foco/cierre señalado y se recogieron riesgos visuales. Antes de aceptar capturas nuevas, esperar a que terminen las animaciones finitas, guardar y abrir la imagen exacta.

## Fuentes primarias consultadas en internet

- [Microsoft: diseño de dashboards](https://learn.microsoft.com/en-us/power-bi/create-reports/service-dashboards-design-tips): audiencia, contexto, jerarquía y visualizaciones según la tarea.
- [Tableau: dashboards efectivos](https://help.tableau.com/current/pro/desktop/en-us/dashboards_best_practices.htm): propósito, audiencia, jerarquía y diseño por dispositivo.
- [NN/g: análisis de tareas](https://www.nngroup.com/articles/task-analysis/): el recorrido del evaluador no reemplaza observar a usuarios reales.
- [NN/g: cuatro tareas en tablas](https://www.nngroup.com/articles/data-tables/): encontrar, comparar, consultar/editar y actuar; filtros visibles y referencias de filas/columnas.
- [NN/g: aplicación de filtros](https://www.nngroup.com/articles/applying-filters/): continuidad, estabilidad y momento adecuado para aplicar filtros.
- [W3C: gráficos e imágenes complejas](https://www.w3.org/WAI/tutorials/images/complex/): alternativas textuales que comuniquen información equivalente.
- [W3C: uso de color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html) y [contraste](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).
- [Government Analysis Function: gráficos](https://analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-charts/): titular informativo y subtítulo que indique medida, ámbito y período. Se leyó el resultado pertinente de búsqueda; abrir el artículo completo si hace falta ampliar la recomendación.

## Código consultado y límites

Se utilizó CodeGraph primero. Sus búsquedas amplias devolvieron bastantes coincidencias del portal; consultas más concretas y lecturas complementarias localizaron:

- `app/src/screens/hoy/gerencia.tsx`: modos de cabecera rango/mes/mixto; diferencias legítimas de períodos y alcance del origen.
- `app/src/components/gerencia/periodo-context.tsx`: conserva rango/origen durante la sesión; no equivale a un enlace de reporte reproducible.
- `app/src/components/app/sidebar.tsx` y `app/src/lib/router.ts`: navegación y rutas.
- `app/src/screens/hoy/resumen-gerencia.tsx`: repetición de indicadores y enlace a Ranking.
- `app/src/screens/hoy/ranking-vendedores.tsx`: pestañas, tablas y estados.

El árbol tiene cambios concurrentes; no atribuirlos a esta auditoría ni sobreescribirlos. Las observaciones visuales se refieren a la versión local inspeccionada.

## Siguiente trabajo

1. Completar captura/inspección de Citas, Metas y Rendimiento; revisar entrada a Configuración si aporta al flujo de reportes. No guardar cambios comerciales.
2. Comprobar consulta móvil y los filtros relevantes con los límites de demo declarados. Priorizar el recorrido de reportes sobre un inventario interminable de pantallas.
3. Sintetizar el usuario por sus tareas: vigilar resultados, explicar diferencias, comparar equipos/analistas y actuar con contexto. Frecuencia y prioridad son hipótesis hasta contrastarlas con Gerencia; no inventar entrevistas. La pregunta opcional sobre qué tarea pesa más no recibió una respuesta inequívoca; el «sí» respondió a la autorización de navegador.
4. Elaborar el plan con hallazgos, fuentes, prioridades, entregables y criterios de cierre. Primeras candidatas: contexto temporal y criterio de orden, eliminar repetición del resumen, continuidad entre reportes, comparación y detalle, lenguaje comercial, accesibilidad y salida de reportes reproducible si la tarea lo justifica.
5. Guardar el informe con capturas y actualizar el plan revisado existente. Entregar un resumen útil en español, fuentes enlazadas y evidencia visual, distinguiendo observaciones de propuestas. No presentar mejoras sugeridas como implementadas.
