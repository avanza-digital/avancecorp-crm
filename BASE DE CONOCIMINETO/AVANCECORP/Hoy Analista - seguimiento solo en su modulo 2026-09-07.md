# Hoy del Analista: Seguimiento en su módulo

Decisión de Miguel del 07/09/2026: retirar el bloque «Seguimiento comercial» de **Hoy del Analista**. Continúa [[Seguimiento - modulo propio y vista por rol 2026-09-07]] y [[Seguimiento - textos claros de plazos y Agenda 2026-09-07]].

Hoy conserva la agenda diaria, los indicadores y el cumplimiento de metas. El analista accede a la cola desde el menú **Seguimiento**, que ya estaba habilitado para su rol. La pantalla Hoy deja de montar y consultar esa cola; no se añade otra tarjeta de acceso dentro de Hoy.

El módulo Seguimiento conserva la cartera propia del analista, los filtros, la paginación y la apertura de fichas. La agenda y los plazos de cada ficha continúan usando el núcleo vigente. No requiere cambios de backend, reglas, permisos ni nuevos cálculos.

La prueba E2E existente del analista se actualiza para abrir la cola desde su módulo, conservando la comprobación de paginación, filtros, adaptación móvil y apertura de ficha.

Validación local: 39 pruebas existentes de Hoy del Analista y la prueba E2E actualizada correctas. La captura de Hoy con datos sintéticos confirma que la agenda, los indicadores y las metas conservan su disposición; el bloque de Seguimiento ya no aparece. La prueba confirma cero consultas a la cola desde Hoy y mantiene filtros, paginación, adaptación móvil y apertura de ficha desde Seguimiento.

Estado: **PUBLICADO Y VERIFICADO** en `crm.miavance.com`.

Fuente `67400637f295b3cd5e43b2629dd37f01dc95f998`, sincronizada con Main y `avancecorp/main` antes de compilar. Build `build-20260907T143810607Z`, release `crm-20260907T143831Z-67400637f295`. ZIP de 1.923.225 bytes, SHA-256 `afe12b1a1f55f81660ac40663d46f9c81584f51b170a81b617e465eba1ba78a6`. Pasaron las 2.945 pruebas de 202 archivos, tipos, lint, compilación y verificación del paquete.

La comprobación HTTP confirmó los 78 archivos: 65 hashes exactos, 12 imágenes transformadas por Hostinger y `.htaccess` protegido con 403. Versión estable, ningún fallo y ZIP inaccesible por HTTP en CRM y portal.

En la sesión real del analista se recargó la nueva versión y se confirmó: bloque «Seguimiento comercial» ausente en Hoy; agenda, indicadores, metas y menú Seguimiento presentes. Se abrió el módulo Seguimiento y se comprobaron lista, filtro de etapa y paginación. Se dejó la sesión en Hoy, sin guardar gestiones ni modificar registros. [Evidencia resumida](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/modulo-seguimiento-20260907/hoy-analista-produccion.json).

Los cambios locales ajenos de Rentabilidad y UX se conservaron. Los commits documentales posteriores registran la comprobación sin cambiar el artefacto servido.
