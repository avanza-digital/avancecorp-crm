---
tags: [crm, gerencia, requerimiento, plan, metricas]
identificador: REQ-GER-MET-001
fecha_acuerdo: 2026-09-04
estado: puntos-1-a-3-completados-frontend-publicado
---

# Plan de corrección de métricas de Gerencia — requerimiento vigente

Relacionado con [[Inicio]], [[Auditoria de metricas de Gerencia - hallazgos y plan 2026-09-04]], [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]] y [[Main unico - sincronizacion y publicacion 2026-09-04]].

## Acuerdo y continuidad

Miguel aceptó la recomendación de trabajo y pidió guardar los **cinco puntos** del plan para poder continuar sin depender del chat. En esta solicitud pidió únicamente el objetivo del primer punto y la persistencia del requerimiento; **no se inició implementación ni publicación**.

Este documento es el seguimiento vigente de los cinco puntos. El informe enlazado conserva la evidencia, los hallazgos G01–G15 y las necesidades N1–N4. Sus etapas técnicas 0–5 se agrupan aquí en los cinco puntos comunicados a Miguel; la publicación permanece como una puerta posterior, no como un sexto requerimiento autorizado.

Avance posterior: se ejecutó exclusivamente el punto 1 como inventario documental de significados y fuentes. Completado y verificado el 4 de septiembre de 2026, 21:21 America/Lima, sin implementar correcciones ni publicar. Entregable: [[Inventario de indicadores de Gerencia - Contrato de lectura]]; comprobaciones: [[Inventario de indicadores de Gerencia - Evidencia y verificacion]].

Avance siguiente: el objetivo posterior autorizó la implementación local del punto 2. Completado y verificado el 4 de septiembre de 2026, 22:05 America/Lima, sin publicación. Entregable, alcance, pruebas y límites: [[Correccion de pantallas de Gerencia - punto 2 - 2026-09-04]].

Punto 3: Miguel autorizó continuar con «ok hazlo» y confirmó el SQL exacto con «sí», condicionado a probarlo aisladamente. Aplicado y verificado el 4 de septiembre, 22:50 America/Lima: se excluyeron de la lectura dos contratos de prueba (PEN 100.000 y USD 100.000), sin borrar datos; los 517 contratos reales concilian con el resumen. **Completado a las 23:23 Lima: frontend implementado y verificado localmente, sin deploy.** 2.741 pruebas y 120 E2E aprobadas (26 omisiones previas). Alcance, pruebas y reversión en [[Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04]].

**Publicación posterior concluida:** Miguel pidió guardar todo y publicar el frontend. Commit de implementación `50f33a59b92b2263296863c857e4ef3e39619450`, Main local/remoto sincronizados antes de construir y publicar; build `build-20260905T043211512Z` verificado en producción el 4 de septiembre, 23:49 Lima. Ejecución, pruebas, acceso con sesión de Gerencia y reversión en [[Publicacion frontend metricas Gerencia 2026-09-04]]. No se aplicó SQL adicional ni se cerraron los puntos 4–5.

## Objetivo general

Que Gerencia vea métricas confiables, comprensibles y coherentes con el servidor, sin confundir captación con asignaciones, avance inferido con asistencia ni datos de prueba con capital real.

## Los cinco puntos acordados

### 1. Definir qué significa cada indicador

- [x] Completado: inventario de definiciones y fuentes, verificado y enlazado arriba.
- **Objetivo:** definir y documentar qué mide cada indicador de Gerencia y de qué dato del servidor proviene, para evitar confundir llegadas, asignaciones, citas, cierres y capital, sin cambiar los núcleos.
- Entregable: inventario por pantalla e indicador con pregunta comercial, fuente y campo, unidad, fecha, ámbito, atribución, exclusiones y estado de disponibilidad/verificación.
- Criterio de cierre: cada indicador tiene una definición inequívoca y una fuente identificada; las diferencias legítimas y los datos faltantes quedan explícitos. No se cambian reglas para forzar coincidencias.

### 2. Corregir pantallas y conexiones existentes

- [x] Completado y verificado; publicado posteriormente con autorización expresa en el release `crm-20260905T043212Z-50f33a59b92b`. Evidencia de implementación en la nota del punto 2 y de publicación en la nota de despliegue enlazadas arriba.
- Objetivo: presentar el dato correcto bajo el nombre y período correctos, reutilizando las salidas y componentes existentes.
- Alcance: retirar asignaciones presentadas como captación; distinguir base automática y llegadas; no afirmar asistencia a partir de etapas inferidas; corregir fechas de Rendimiento, estados de citas, alcance de filtros y tratamiento de errores/verificación.
- Criterio de cierre: los números conservan el significado del servidor; error, ausencia de verificación y cero real no se confunden. No hay nuevas calculadoras independientes.

### 3. Corregir la lectura de Cartera

- [x] Completado: SQL confirmado por Miguel, probado aisladamente y aplicado como `20260905034917`; lectura productiva conciliada y núcleos/permisos intactos. Conexión frontend y completitud implementadas, verificadas y publicadas posteriormente en `crm-20260905T043212Z-50f33a59b92b`. Ver las notas del punto 3 y de publicación enlazadas arriba.
- Objetivo: que los indicadores reales de Cartera se apoyen en las lecturas existentes del servidor y no incluyan contratos de prueba ni dependan de listas incompletas.
- Alcance: conciliar los resúmenes existentes campo por campo antes de conectarlos; corregir la exclusión de pruebas en la fachada existente del listado; respetar saldo vigente, producción mensual, monedas y atribución.
- Criterio de cierre: exclusiones y alcance concilian entre indicadores y listado; ningún dato de prueba aporta al indicador real. No se borran contratos ni perfiles, ni se modifica el núcleo de capital.

### 4. Justificar los datos que falten

- [ ] Pendiente; sólo si un requerimiento no puede resolverse con salidas existentes.
- Objetivo: explicar y acordar cada necesidad adicional antes de ampliarla, sin duplicar reglas de negocio.
- Entregable por necesidad: pregunta comercial, dato existente insuficiente, motivo técnico, alternativa sin ampliación, impacto y aprobación requerida.
- Casos ya identificados: leads únicos del lote con cita real; divisor ajustado de citas por modalidad; aporte efectivo de cada operación; cierres por semana real de cierre.
- Criterio de cierre: cada caso queda resuelto con una lectura existente, descartado o aprobado expresamente como ampliación compatible de una respuesta existente. No se crean núcleos, RPC ni funciones independientes.

### 5. Probar y conciliar

- [ ] Pendiente; pruebas durante el desarrollo y cierre integral al final.
- Objetivo: demostrar que las pantallas coinciden con el servidor cuando miden lo mismo y explican las diferencias cuando miden cosas distintas.
- Alcance: reasignaciones, llegada a Ana/cierre de Luis, manuales/referidos, citas y cancelaciones, operaciones repetidas, capital de prueba, PEN/USD, filtros, rangos parciales, meses sellados, errores, respuestas parciales y metas superiores al 100 %.
- Observación adicional del smoke productivo: revisar los importes transitorios al cambiar de mes a «Todos los meses» en Cartera. Una lectura inmediata fue negativa y la posterior quedó en los saldos positivos conciliados; distinguir transición visual de dato final, sin modificar el núcleo ni asumir la causa. Evidencia en la nota de publicación.
- Criterio de cierre: pruebas de contrato e interfaz aprobadas, discrepancias justificadas y núcleos/permisos intactos. No usar producción para semillas, mutantes ni pruebas de escritura.

## Restricciones obligatorias

1. No editar ni modificar ningún núcleo; mantener la semántica del servidor.
2. No crear funciones, RPC o calculadoras independientes ni reconstruir fórmulas de negocio por pantalla.
3. Conservar origen y fecha de llegada, atribución al primer analista, cierre a quien lo consigue, pesos vigentes, deduplicación y fotografías mensuales selladas.
4. Si falta algo, explicar técnicamente y comercialmente por qué antes de proponerlo. Ampliar una respuesta existente tampoco queda aprobado de forma automática.
5. Mostrar el SQL exacto y esperar confirmación antes de cambios de base de datos. No aplicar migraciones ajenas o pendientes mediante una publicación global.
6. No publicar hasta tener autorización. Al publicar: Main local sincronizado con `avancecorp/main`, artefacto del mismo commit verificado, sin ramas de release ni force push, verificación y reversión preparadas.
7. Preservar cambios concurrentes del usuario; revisar el estado actual del repositorio antes de continuar. Las huellas y cifras del informe son evidencia de su fecha, no una garantía de que el estado externo siga igual.

## Punto de reanudación

**Último punto terminado:** 3, lectura de Cartera; SQL y frontend en producción. El frontend del punto 2 también está publicado. El punto 1 se conserva como inventario documental de 336 registros en las 20 rutas de Gerencia; sus etiquetas son la línea base anterior a estas correcciones.

**Siguiente punto:** 4, justificar comercial y técnicamente los datos faltantes y presentar alternativas antes de ampliar nada. El punto 3 está cerrado en [[Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04]]. **No volver a aplicar la migración** ni esperar una confirmación ya recibida. «Sin analista», capital mensual filtrado y ámbitos no globales conservan sus criterios: no admiten sustitución directa por el resumen global. No modificar el núcleo de capital ni crear calculadoras independientes. La publicación autorizada ya se completó; no repetirla ni ampliar su alcance por esta continuidad.

Los puntos 4–5 siguen pendientes; las pruebas de estas correcciones y el smoke productivo no cierran todavía la conciliación integral del punto 5. No inferir autorización de SQL adicional ni funciones nuevas. Línea base histórica al comenzar el punto 2: HEAD `ecbb7b97ad79124e34f1a924227d27dd8585c737`, árbol de aplicación `ed23ef494093755055f1b236a37d9830fe3220f9`, inicialmente limpio. Los commits concurrentes de documentación y altas nuevas se preservaron; HEAD observado durante el punto 3 llegó a `ed2b7ea`. Las correcciones quedaron guardadas y publicadas desde `50f33a5`; el cierre documental posterior no cambia ese artefacto. Verificar nuevamente el estado antes de cualquier publicación futura, no asumir Main sincronizado por esta nota.

Al retomar: leer este requerimiento, la ejecución de los puntos 2 y 3, el inventario y el informe enlazado; verificar el estado actual y actualizar aquí el avance de cada punto. No repetir los puntos 1–3 salvo cambios posteriores que exijan actualizarlos. No marcar los demás completos por tener sus objetivos descritos.
