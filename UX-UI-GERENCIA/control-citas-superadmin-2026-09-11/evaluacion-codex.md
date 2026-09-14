# Evaluación del review de Control de Citas

Una revisión independiente de Claude por `scripts/claude-review`, en modo SECONDARY_REVIEWER, sin herramientas ni escrituras. Dictamen recibido: **CHANGES_REQUESTED**, evaluado por Codex. El primer intento restringido no completó la invocación; se repitió con permiso y produjo el informe adjunto.

## Cambios aceptados y comprobados

- P1: cargar otra versión ya no descarta silenciosamente la edición. El diálogo ofrece conservarla o descartar explícitamente. Pruebas de componente y E2E del flujo conflicto → recarga → conservar/descartar.
- P2: el mes inválido abre las reglas, muestra error asociado y recibe el foco. Prueba con entrada de texto para representar un navegador sin selector mensual.
- P2: el botón de guardar conserva foco mediante `aria-disabled`, con guard funcional; no pierde el foco al terminar.
- P3: el ejemplo tiene `role=group`; las metas en formulario e historial usan coma decimal.
- P3: la base de depósitos, aún no acordada, pasó a `null` y a una opción explícita por confirmar. Hay siete decisiones pendientes inicialmente. El 70% sí queda propuesto con el valor solicitado.
- P3: `23505` también conduce al flujo de conflicto. Una respuesta de guardado no verificable provoca actualización del servidor. Se añadió una defensa adicional: si ese refetch falla, el editor permanece montado y conserva la edición.
- P3: se bloquea TRUNCATE por trigger y se documenta que el CHECK sólo se ejecuta bajo el propietario mediante la RPC.

## Recomendaciones evaluadas sin cambiar la regla

- FK del autor: se conserva NO ACTION intencionalmente. La regla vigente del repositorio es desactivar con `activo=false`, no borrar perfiles. El banco prueba que desactivar revoca acceso y conserva el historial y que borrar un autor referenciado se rechaza. Esto es una retención explícita, no una afirmación de que hard-delete esté soportado. Una futura purga de identidad requeriría acordar cómo conservar autoría.
- No se altera el auditor compartido: el trigger sigue el patrón existente de `private.log_audit_crm`. No se modifican objetos previos de `public`.
- No se activa ni conecta una regla a las métricas: el alcance comunicado es preparar y guardar borradores mientras se acuerdan definiciones.

## Límites de evidencia

El reviewer recibió SQL, modelos, API, editor y pantalla con líneas; no recibió todos los archivos de navegación ni los tests completos. Codex comprobó la navegación con pruebas por rol y E2E del CRM con backend loopback simulado. Los helpers `public.es_superadmin()` y `private.log_audit_crm()` se leyeron directamente, sin datos de usuarios, en producción. El banco SQL usa sus definiciones y fixtures mínimos, no un clon completo del proyecto.

No se realizó una segunda consulta para obtener conformidad. Los hallazgos aceptados se resolvieron y verificaron por Codex. La instalación en una rama, matriz RLS completa, advisors y tipos generados del catálogo instalado permanecen pendientes antes de producción.
