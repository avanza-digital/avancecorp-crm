---
tags: [crm, conversion, reasignacion, incidente, resuelto]
actualizado: 2026-09-29
---

# Conversión: conciliación de responsable tras reasignar

**CASO PUNTUAL CORREGIDO EN PRODUCCIÓN EL 29/09, 15:12 LIMA.**

Tras preparar la identidad y un borrador de inversión a cargo de Nayra, el lead
de Zoila fue reasignado a Linda. `preparar_persona_lead_inversion_fn` rechazaba
continuar porque el lead y `inversionistas.responsable_relacion_id` diferían.
El borrador también conservaba `responsable_esperado_id` de Nayra.

Miguel autorizó corregir este caso. Se usaron las puertas existentes
`reasignar_responsable_relacion_fn` y `revisar_solicitud_inversion_fn`, juntas en
una transacción con guardas de estado, huellas y postcondiciones. La cuenta
administrativa y el motivo identifican la reparación técnica mediante Codex.
Linda quedó en las tres referencias; historial y autoría se conservaron. La
solicitud sigue preparada con el mismo hash y condiciones; no se creó inversión.

PASS: siete comprobaciones SQL sintéticas con rollback, bloque exacto con
rechazo de hash cambiado y reintento idempotente, paridad de cinco funciones,
relectura productiva y acceso de Linda a la misma solicitud. Claude pidió
comparaciones explícitas ante NULL; el PRIMARY las corrigió y volvió a probar.
No hubo cambios de esquema, funciones o frontend. Navegador/E2E: NOT RUN.

**Alcance:** reparación puntual; la sincronización automática de futuras
reasignaciones no forma parte de este cambio. No atribuir un arreglo global.

[Acta y evidencia](../../CRM-Avance-Corp/docs/encargos/2026-09-29-conciliacion-conversion.md).

Relacionado: [[Conversion de lead con Nueva inversion - preparado 2026-09-19]],
[[Leads - marca y filtro de reasignados (2026-09-28)]] y [[Inicio]].
