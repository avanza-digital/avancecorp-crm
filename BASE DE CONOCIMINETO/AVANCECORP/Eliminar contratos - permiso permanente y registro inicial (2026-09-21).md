# Eliminar contratos — permiso permanente y registro inicial

Decisión explícita de Miguel, 21/09/2026: Admin/Superadmin debe conservar la
capacidad de eliminar contratos con copia de auditoría. **No retirar ni desactivar
esta capacidad en futuras limpiezas, cambios de pantalla o refactorizaciones.**
Mantener pruebas que cubran el alta unificada, además del contrato legado.

El caso `2026-01-001457` demostró que el permiso existía, pero el servidor rechazaba
el registro y la solicitud que genera automáticamente el alta unificada. La
corrección anterior del 16/09 estaba instalada aunque su nota seguía «preparado».

Nueva corrección: archiva el registro inicial y la solicitud en la copia v3;
conserva la solicitud cancelada y sus revisiones/correcciones, y conserva los PDF.
El historial posterior, los meses cerrados y los límites previos de renovación
mantienen sus protecciones. El contrato 001457 tiene autorización expresa de
eliminación bajo `ADMINISTRADOR AVANCE CORP`.

**PUBLICADO Y VERIFICADO:** SQL registrado como `20260921185355`. El contrato
001457 fue eliminado a las 13:54:14 Lima; auditoría
`7ead0c0e-8ad3-4e2d-9a4c-b0f87de16389`. Contrato, 13 cuotas, registro y solicitud
archivados con huellas idénticas; PDF y corrección de solicitud conservados.
35 pruebas SQL/concurrencia y 48 Edge/Storage PASS. Sin nuevos advisors.
No requirió nueva publicación frontend; no se creó rama remota de pago.
Acta: `CRM-Avance-Corp/supabase/scripts/contratos-eliminar/REGISTRO-INICIAL-20260921.md`.

Relacionadas: [[Inicio]] · [[Eliminar contrato vinculado sin historial - preparado 2026-09-16]] · [[Eliminar contratos con pagos por administrador - preparado 2026-09-15]].
