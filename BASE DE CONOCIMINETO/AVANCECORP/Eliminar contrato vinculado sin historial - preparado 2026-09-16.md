# Eliminar contrato vinculado sin historial — publicado 16/09/2026

Miguel mostró el bloqueo de «Eliminar contrato» y autorizó continuar los cambios
de otra sesión. La versión publicada excluía cualquier `crm.inversiones`, aunque
el enlace ahora nace automáticamente con contratos nuevos. Eso impedía el caso
mostrado. La consulta de solo lectura confirmó una inversión sin historial propio.

Corrección publicada y validada: Admin/Superadmin puede eliminar también ese
contrato, archivando inversión y titulares con contrato/pagos. Se conservan PDF,
auditoría inmutable, meses cerrados, eventos/solicitudes/ajustes/orígenes y las
restricciones de reapertura de renovación (Superadmin). No se borró dato real.

PASS: 3632 pruebas frontend, 194 E2E (26 omisiones existentes), dos recorridos
vinculados móvil/escritorio, 48 Edge, 21 SQL locales/remotos, cuatro carreras y
23 comprobaciones Auth/Edge/Storage. Reversa comprobada; sin nuevos advisors.
Rama temporal eliminada; coste estimado US$0,006882. Primera revisión BLOCK por
evidencia/guarda FK, puntos resueltos con tests; segunda respuesta inválida, sin
afirmar aprobación del revisor. Evaluación del PRIMARY documentada.

**PUBLICADO:** Miguel confirmó «ya ets aprobado» después de la solicitud de
aprobación del SQL, integración excepcional y release. PR #1 integrada en
`a0c47ebc1d4eaa38544fe1b0e550bdceab021007`; su árbol es idéntico al commit probado
`f4cf98b`. Main local, copia limpia y `avancecorp/main` coincidían al publicar.

Solo se instaló la migración autorizada; registro remoto `20260916170027`
(16/09 12:00:27 Lima). Huella nueva `c0ae3e3167c82724b784d73b4f427868`;
las otras 652 funciones, permisos, RLS y conteos conservados. Edge v20 activa,
JWT habilitado y nueve archivos idénticos a Main. Sin nuevos advisors.

Web: `crm-20260916T165912Z-a0c47ebc1d4e.zip`, build
`build-20260916T165911818Z`, SHA-256
`58aa3548076ae892d6a564720c87f36bc26bb88aa075e9a2224da9ddb0736534`.
Hostinger aceptó publicación y purga. 92 recursos: 80 hashes exactos,
11 imágenes optimizadas y `.htaccess` protegido; 96 controles HTTP PASS.
Tres lecturas estables y acceso público cargado sin errores. La sesión de
administrador no estuvo disponible para recorrido visual autenticado; el flujo
completo ya pasó en el banco remoto autorizado. No se borró ningún contrato real.

Uso: recargar CRM; Cartera → cliente → Eliminar contrato; escribir el número
mostrado; «Eliminar y conservar auditoría». Sigue prohibida la eliminación de
una inversión con historial propio o restricciones previas de cierre/renovación.

Artefacto, manifiesto, reversa y recibo productivo conservados. Rollback frontend:
`crm-20260916T035915Z-a09ecad9aaed.zip`. La carpeta principal quedó sincronizada
sin alterar archivos ajenos; respaldo de integración guardado en stash.

Acta: `CRM-Avance-Corp/supabase/scripts/contratos-eliminar/VINCULADA-20260916.md`.
El trabajo de gestión integral multiempresa de otra sesión se conserva aparte.

Relacionadas: [[Inicio]] · [[Eliminar contratos con pagos por administrador - preparado 2026-09-15]] · [[Matriz RLS global - reparacion y candado F8 2026-09-16]].
