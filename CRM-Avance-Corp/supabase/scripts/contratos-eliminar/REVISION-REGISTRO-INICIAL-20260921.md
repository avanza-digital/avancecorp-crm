# Revisión de registro inicial — 21/09/2026

LEVEL 3. Codex PRIMARY; Claude SECONDARY_REVIEWER/auditor-rls mediante
`scripts/claude-review`, sin herramientas. Primer intento no completado en el
entorno restringido; el reintento autorizado con red entregó **CHANGES_REQUESTED**.
No se atribuye PASS al reviewer. La respuesta llegó durante la verificación
productiva; el PRIMARY conserva la responsabilidad de la activación autorizada.

## Evaluación del PRIMARY

- **Dependencias y bloqueo del contrato:** catálogo productivo y banco coinciden:
  `contrato_eliminacion_finalizar` = `c1eba8d9b7af8dbb84a22ba91e19fc70`,
  `bloquear_fila_contrato_pdf` = `d77128a7e0ad7799336b60bf80e8217d`, ambos
  SECURITY DEFINER, owner postgres, search_path vacío. El segundo ya toma
  `FOR UPDATE` sobre `public.contratos` antes del snapshot: se descarta la
  hipótesis de inserciones hijas sin bloqueo. No hace falta duplicarlo.
- **Identidad:** `auth.uid()` tiene cuerpo idéntico en banco/producción
  (`cdef18c69c4f4cbbced2eaf81e628b49`) y prioriza `request.jwt.claim.sub`.
  El borrado productivo confirmó actor y copia exactos. El owner del helper
  local difiere (postgres frente a supabase_auth_admin), sin SECURITY DEFINER.
- **Exposición de auditoría:** producción tiene RLS ON, cero políticas y ACL
  solo postgres. `anon`, `authenticated` y `service_role` no tienen SELECT.
  `auditoria-casos.mjs` ya verifica estos permisos y la ACL de la RPC; el
  reviewer no recibió ese archivo completo. No se abre acceso por Data API.
- **Triggers y solicitudes:** inventario productivo leído antes de instalar.
  Inversiones/titulares solo añaden auditoría en DELETE; la solicitud conserva
  origen y el trigger postventa retorna sin efectos si OLD estaba confirmada.
  La CHECK confirmada permite estado cancelada + inversion_id NULL. La
  protección de etapa del lead solo interviene cuando cambia a convertido.
  No hay trigger de envío externo en esas escrituras.
- **Cancelación y lectores:** catálogo sin vistas que lean solicitudes ni
  funciones de métricas que las cuenten por estado. Sus lectores corresponden
  a preparación/confirmación/contexto/acceso/bienvenida/backfill. La solicitud
  cancelada no puede confirmar otra vez ni reclamar bienvenida; la copia guarda
  el estado confirmado anterior y conserva revisiones/correcciones. No se cambia
  el enum ni se agrega un booleano sin consumidor. Meses cerrados siguen bloqueados.
- **Pruebas pendientes del prompt:** completadas antes de activar: 31/31 SQL y
  concurrencia, 48/48 Edge. El arnés EPIPE sigue exigiendo error SQLSTATE 23503;
  no convierte un cierre inesperado en éxito. Después de recibir la revisión se
  agregaron cuatro casos de solicitud incoherente (fuente/persona/empresa/estado):
  10/10 nuevos, total 35 SQL/concurrencia.
- **Pagos:** se rechaza la recomendación de volver a bloquear pagos. Miguel ya
  autorizó expresamente el borrado con pagos y copia de auditoría el 15/09.
  La prueba correspondiente sigue PASS; el caso real tenía cero cuotas pagadas.
- **Número de registros:** se permite cero o más registros iniciales archivados,
  sin perder ninguno. Exigir exactamente uno rompería contratos sin evento,
  que deben seguir funcionando. Corrección/anulación posterior siguen rechazadas.
- **Contención JSON:** actualmente el evento solo contiene escalares; snapshot y
  OLD provienen de las mismas filas bloqueadas e inmutables. No se acepta como
  fallo actual la hipótesis de una futura columna JSON. Todo evento se copia.
- **Reaplicación:** la migración se ejecuta una vez y queda registrada; los
  pre/postflight evitan sobrescribir versiones distintas. No se altera el
  archivo ya instalado para hacerlo repetible fuera del historial de migraciones.

No queda un defecto demostrado por la revisión. Las comprobaciones productivas
confirmaron la eliminación autorizada y la conservación exacta de las evidencias.
No se abrió otra consulta para buscar un dictamen favorable.
