---
tags: [crm, datos, demo, qorilazo, auditoria]
fecha: 2026-10-18
estado: eliminado-verificado
---

# Qorilazo - inversion demo de 800 y retiro eliminados (2026-10-18)

**Eliminación completada el 18/10/2026 a las 18:36 Lima.** Miguel pidió borrar la inversión demo de S/ 800 de Qorilazo del analista Miguel Briceño. Al detectar un retiro vinculado cancelado, confirmó: «esa solicitud fue por error eso lo debemos eliminar».

Coincidencia única: DEMO DEMO DEMO, fecha comercial 06/10, fuente `e6891c3e-0e23-4789-8d21-5205e029e258`, inversión `50ca25d6-e0db-457d-b3ff-ea486d54ebb7`. Ya estaba anulada desde el 09/10. Se retiró también la solicitud cancelada por error `0cdb55f8-b6b8-467c-9bfd-2205f765391d`.

Una sola transacción por SQL, con el retiro copiado por su trigger normal y la inversión eliminada mediante la puerta existente `crm.eliminar_inversion_fn`. No se deshabilitaron protecciones ni se modificó la regla general: la excepción autorizada fue esta solicitud cancelada creada por error.

Copias permanentes: inversión `3986bed3-5e64-429b-a5bd-b7adfdcf9e72` en `crm.inversiones_eliminadas`; retiro `514fe27f-defb-4077-818b-cde8a4637572` en `public.audit_log`. Actor administrativo `bf1c562e-ed08-4cc3-92a8-34f1fa3e9127` (ADMINISTRADOR AVANCE CORP); el motivo identifica autorización de Miguel y ejecución de Codex.

**Verificado tras COMMIT: 0 filas operativas para el cierre, la inversión y el retiro.** Cliente y lead intactos; anulación, acreditaciones y periodos conservados. Solicitud de alta conservada cancelada; comprobante guardado como evidencia. No fue necesario publicar frontend.

Claude revisó (CHANGES_REQUESTED, sin P0/P1); Codex corrigió y comprobó los puntos aplicables antes de ejecutar. Preflight, compilación, postflight transaccional y lectura posterior PASS. Ensayo de escrituras en producción NOT RUN; tests/build de aplicación no aplican a esta operación.

Evidencia: `CRM-Avance-Corp/releases/limpieza-demo-qorilazo-800-20261018/ACTA.md`, con SQL exacto, estado previo, revisión y resultado.

[[Eliminar inversion - admin y gerencia, tres empresas (2026-10-05)]] · [[Facturacion - fase 0 decisiones de datos (2026-10-08)]] · [[Inicio]]
