# Eliminar contrato vinculado sin historial — preparado 16/09/2026

Miguel mostró el bloqueo de «Eliminar contrato» y autorizó continuar los cambios
de otra sesión. La versión publicada excluía cualquier `crm.inversiones`, aunque
el enlace ahora nace automáticamente con contratos nuevos. Eso impedía el caso
mostrado. La consulta de solo lectura confirmó una inversión sin historial propio.

Corrección preparada y validada: Admin/Superadmin puede eliminar también ese
contrato, archivando inversión y titulares con contrato/pagos. Se conservan PDF,
auditoría inmutable, meses cerrados, eventos/solicitudes/ajustes/orígenes y las
restricciones de reapertura de renovación (Superadmin). No se borró dato real.

PASS: 3632 pruebas frontend, 194 E2E (26 omisiones existentes), dos recorridos
vinculados móvil/escritorio, 48 Edge, 21 SQL locales/remotos, cuatro carreras y
23 comprobaciones Auth/Edge/Storage. Reversa comprobada; sin nuevos advisors.
Rama temporal eliminada; coste estimado US$0,006882. Primera revisión BLOCK por
evidencia/guarda FK, puntos resueltos con tests; segunda respuesta inválida, sin
afirmar aprobación del revisor. Evaluación del PRIMARY documentada.

**NO PUBLICADO:** falta aprobación del SQL exacto
`20260916160000_crm_eliminacion_auditada_inversion_sin_historial.sql`, promoción
literal de esa única migración, Edge y `$release-crm`. No fusionar historial del
banco reconstruido. La función productiva sigue en su versión anterior.

Acta: `CRM-Avance-Corp/supabase/scripts/contratos-eliminar/VINCULADA-20260916.md`.
El trabajo de gestión integral multiempresa de otra sesión se conserva aparte.

Relacionadas: [[Inicio]] · [[Eliminar contratos con pagos por administrador - preparado 2026-09-15]] · [[Matriz RLS global - reparacion y candado F8 2026-09-16]].
