# Eliminación de usuarios y contratos — 25/09/2026

Estado: **las dos migraciones están instaladas y verificadas en producción**
(25/09/2026, lectura final 15:34 Lima). Pantallas preparadas, todavía sin publicar.
Álvaro ya fue eliminado por petición expresa; la lectura final confirmó nuevamente
Auth/perfil/equipo/sesiones 0 y cuatro eventos administrativos conservados.

## Eliminación puntual ejecutada

`eliminar-alvaro-20260925.sql` se ensayó con identidad sintética y se revisó con
`scripts/claude-review`. Las observaciones sobre RLS, referencias y auditoría se
resolvieron antes de ejecutar. La comprobación completa de FK y columnas UUID sin
FK encontró cero referencias de negocio. Los cuatro eventos de administración de
la cuenta no se borraron.

Lectura independiente posterior en producción: Auth 0, perfil 0, equipo 0,
sesiones 0, nueva purga auditada 1, registros de auditoría de borrado 2 y eventos
administrativos conservados 4. No se modificó ninguna función en producción.

## Función general

Migración `20260925180145_crm_eliminacion_usuarios_sin_pendientes.sql`:

- Gerencia activa, nunca la propia cuenta ni roles Portal protegidos. Confirmación
  por nombre exacto y versiones de perfil/membresía.
- Evalúa pendientes en el servidor. La pantalla conduce a la transferencia
  existente antes de eliminar. Se cubren membresías activas e inactivas con residuos.
- Sin referencias de negocio: purga auditada de membresía y borrado de Auth/perfil.
- Con historial: perfil y membresía inactivos, nombre original conservado, sesiones
  y refresh tokens retirados, Auth bloqueado; no se reasigna autoría de actividades.
- Tabla privada de retiros sin FK a la identidad, RLS activado, sin acceso de API,
  inmutable y con auditoría. Conserva nombre/roles/actor/fecha, incluso tras borrado.
- El directorio excluye retirados, con el mismo filtro para total y paginación.
- Las asignaciones de leads, tareas, perfiles de cliente, equipo y personas toman
  locks SHARE NOWAIT sobre el responsable: una baja concurrente provoca reintento.
  El trigger corre después de los demás BEFORE para comprobar el destino definitivo.
- Con identidad OFF también se bloquea la eliminación si hay personas a cargo.
  Su transferencia usa el flujo de identidad habilitado; no se enciende ninguna
  bandera mediante esta migración. Producción tiene ese flujo habilitado.

El usuario autorizó expresamente conservar la autoría histórica. Esta petición es
la excepción al criterio general de solo soft-delete para identidades vacías.

## Verificación

Banco exclusivo: `contratos_cotitular_v3_20260925`, dentro de
`supabase_db_crm-avance-corp-local`. Datos sintéticos, ROLLBACK en cada escenario.
No se usó la base operativa del contenedor para modificar datos.

| Comprobación | Resultado |
| --- | --- |
| SQL usuarios, roles, sesión, historial, postventa, flags, rollback y concurrencia | PASS: 17 escenarios |
| SQL contratos: pagos, alta, dos cotitulares, mezcla histórica, token/actor ajenos, rollback y ACL | PASS: 16 escenarios |
| Pantalla, API MSW, demo e invalidaciones de usuarios | PASS: 47 pruebas |
| E2E Docker: eliminación, transferencia, demo Gerencia/Directorio y Superadmin | PASS: 5 recorridos |
| Portal eliminación | PASS: 4 pruebas dirigidas; suite anterior de portal 111 PASS |
| Handler y Storage de contrato PDF v2 | PASS: 48 pruebas |
| CRM lint, TypeScript, cobertura, release-config, push-tasa, build, bundle | PASS; 4.430 pruebas en el gate general |
| Gate final de duplicación | FAIL: 0,83 % supera 0,8 %; incluye archivos preexistentes ` 2.tsx`/` 2.css`, no clones de esta función |
| check:scripts, seed:preflight y RLS preflight offline | PASS |
| Edge preflight global | FAIL previo: 87/89; dos aserciones fuente ajenas en domicilio y crear-cliente/autorización |
| Rama remota: SQL de contratos y usuarios | PASS: 33 escenarios, 0 fallos |
| HTTP/PostgREST/Auth alojado con identidades ficticias | PASS: 22 solicitudes reales |
| Advisors de rama y producción | PASS de delta: ningún ERROR nuevo; avisos previstos documentados abajo |
| Lectura posterior al merge | PASS: cuerpos, ACL y triggers coinciden con la rama ensayada |

Se regeneraron tipos desde el banco con Supabase CLI y se incorporaron únicamente
las dos RPC nuevas, preservando cambios simultáneos de otros trabajos. Firmas
coincidentes. Instalación completa de la migración ensayada desde las funciones
originales; huellas previas impiden sobrescribir definiciones que hayan cambiado.
El banco omitía USAGE de esquema en su copia: el test authenticated lo concede
solo dentro de su transacción. Producción confirmó USAGE `crm/auth/public` para
authenticated, y SELECT/UPDATE/DELETE de postgres sobre las tres tablas Auth,
SELECT sobre storage.objects y BYPASSRLS. No se concedieron permisos en producción.

La revisión independiente de la función general pidió resolver postventa,
concurrencia, schema estricto, permisos alojados y definiciones completas.
Se comprobó `postventa_cambio_persona → postventa_sincronizar` con transferencia
real en el banco; se añadió protección de asignación y prueba concurrente; se probó
la respuesta de candidato en MSW; se verificaron privilegios alojados y SET ROLE
authenticated; se versionaron cuerpos completos en la migración. La observación
de campos opcionales era una hipótesis: `personas_a_cargo` ya era `v.optional`.

El lanzador E2E tiene un fallo de Bash 3 con el array de nombre vacío. Se ejecutó
sin modificarlo, usando `CRM_E2E_CONTAINER=crm-usuarios-20260925` y
`CRM_E2E_TASK=usuarios-eliminar`. Cinco recorridos PASS; no se usó GitHub.

## Contratos y revisión

La migración `20260925172955_crm_eliminacion_contrato_cotitular_alta.sql` corrige la
clasificación del origen `alta` del cotitular. No se había retirado el permiso de
Admin: se confundía ese registro inicial con historial posterior.

La versión 4 archiva los orígenes completos y permite retirarlos únicamente dentro
de la reserva privada del contrato con actor, inversión y copia exactos. Conserva
identidades, archivos y solicitudes canceladas. El historial posterior independiente
y los cierres mensuales siguen bloqueando el borrado. La instalación no borra el
contrato de la captura ni otros contratos.

La revisión contractual no encontró defectos de privilegios; pidió evidencia y
pruebas adicionales. Se verificó que el cuerpo anterior de
`f4_proteger_origen_cotitular` conserva todas sus ramas; solo se antepone la
excepción DELETE auditada. Los dos triggers originales BEFORE UPDATE/DELETE
permanecen habilitados. Se reforzó postguard de ACL no nula, SECURITY DEFINER,
search_path y vínculos de triggers. Los tokens de otro contrato/actor, restauración
del GUC y múltiples orígenes se cubrieron con nuevas pruebas.

Se conserva la compatibilidad de snapshot 3 para registros anteriores; la RPC
produce exclusivamente versión 4 y no acepta una reserva anterior pendiente.
El hash y snapshot de cotitular comparan la fila completa: nuevas columnas en
`contrato_titulares` requieren revisar esa compatibilidad; cualquier diferencia
bloquea la eliminación. No hay cambio de firma ni de respuesta de la Edge.

Portal: se retira el bloqueo local antiguo para Admin con pagos; el servidor
central decide para Portal y CRM. `contratos.js?v=45`; conservar el CACHE_VERSION
vigente del trabajo compartido (v121 al preparar esta acta).

## Instalación de backend completada

Miguel aprobó instalar ambos SQL con «siii». Se creó la rama sin datos
`eliminacion-auditada-20260925` (`nojjwdpeziyabrpabudx`). Su replay automático solo
contenía 86 migraciones antiguas; se reconstruyó allí la estructura vigente desde
un dump sin datos, se igualaron permisos/roles y se cargaron exclusivamente
fixtures sintéticos. Antes de aplicar: 774 funciones y 123 tablas cotejadas;
358 migraciones base idénticas por versión, nombre y contenido. Tres CHECK
conservaron semántica con distinta agrupación de paréntesis al restaurar.

Se aplicaron ambos archivos exactos mediante MCP en la rama y se fijaron sus
versiones canónicas antes del merge. Las 33 pruebas SQL originales pasaron por
conexión remota, incluida una segunda conexión concurrente. Las 22 solicitudes
HTTP comprobaron Gerencia frente a anónimo/analista, eliminación vacía, autoría
histórica, sesiones retiradas, login y refresh bloqueados y permisos denegados
con el JWT anterior. La matriz general `test-rls.mjs` no se repitió en esta rama;
la evidencia alojada corresponde a los escenarios dirigidos descritos aquí.

Advisors: ningún ERROR nuevo ni hallazgo nuevo de rendimiento. Avisos previstos:
INFO de [RLS sin políticas](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
en `private.usuarios_retirados` (deny-all intencional y grants revocados) y dos WARN
de [RPC SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
para las puertas de impacto/eliminación (guardas de Gerencia activa verificadas).

Merge nativo `4d6d5d55-cec3-4302-90d7-d90254757bc1`: solo dos migraciones,
21 Edge Functions idénticas antes y después. La lectura de producción confirmó
360 migraciones, las 358 previas intactas, 779 funciones y 124 tablas; cuerpos y
ACL exactos al candidato. El merge divide el SQL en statements: sus tokens se
cotejaron conservando exactamente literales y cuerpos dollar-quoted.
Roles, políticas Storage y triggers Auth intactos. El contrato `2026-01-001471`
sigue presente: instalar la corrección no lo elimina. Rama temporal eliminada y
ausencia confirmada; las ramas de otros trabajos se conservaron.

Huellas de los archivos instalados y resumen reproducible:
`PUBLICACION-20260925.json`. Evidencia detallada de esta sesión en
`/private/tmp/eliminacion-publicacion-20260925/` (catálogos, TAP, HTTP y cotejos).

## Publicación de pantallas pendiente

La publicación CRM requiere invocación humana `$release-crm`, según
`CRM-Avance-Corp/CLAUDE.md`, sección Deploy. No se hizo commit global ni se
incluyeron modificaciones simultáneas de otros trabajos. El gate de duplicación
global deberá aclararse antes de una release. Portal también conserva su cambio
local de bloqueo/caché pendiente de publicación.
