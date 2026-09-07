# Hoy del Analista: Seguimiento en su módulo

Decisión de Miguel del 07/09/2026: retirar el bloque «Seguimiento comercial» de **Hoy del Analista**. Continúa [[Seguimiento - modulo propio y vista por rol 2026-09-07]] y [[Seguimiento - textos claros de plazos y Agenda 2026-09-07]].

Hoy conserva la agenda diaria, los indicadores y el cumplimiento de metas. El analista accede a la cola desde el menú **Seguimiento**, que ya estaba habilitado para su rol. La pantalla Hoy deja de montar y consultar esa cola; no se añade otra tarjeta de acceso dentro de Hoy.

El módulo Seguimiento conserva la cartera propia del analista, los filtros, la paginación y la apertura de fichas. La agenda y los plazos de cada ficha continúan usando el núcleo vigente. No requiere cambios de backend, reglas, permisos ni nuevos cálculos.

La prueba E2E existente del analista se actualiza para abrir la cola desde su módulo, conservando la comprobación de paginación, filtros, adaptación móvil y apertura de ficha.

Validación local: 39 pruebas existentes de Hoy del Analista y la prueba E2E actualizada correctas. La captura de Hoy con datos sintéticos confirma que la agenda, los indicadores y las metas conservan su disposición; el bloque de Seguimiento ya no aparece. La prueba confirma cero consultas a la cola desde Hoy y mantiene filtros, paginación, adaptación móvil y apertura de ficha desde Seguimiento.

Estado: validado; pendiente de publicación.
