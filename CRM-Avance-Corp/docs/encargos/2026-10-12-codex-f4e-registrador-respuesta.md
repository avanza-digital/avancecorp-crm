# Corrección del registrador F4-e — PR #255

Corrección del P2 del registrador preparada por Codex por pedido de Miguel.

El registrador valida ahora las huellas de pg_proc.prosrc de ambas funciones aprobadas, su lenguaje/retorno, nombres y valor por defecto de los parámetros, STABLE, SECURITY DEFINER/INVOKER, search_path y ACL de EXECUTE antes de escribir en el historial. Rechaza cuerpos vacíos, acceso adicional y permisos faltantes, incluso si la versión ya estaba registrada. No se modificó la migración versionada.

Regresiones integradas en npm run test:llamadas:local: registro válido, idempotencia y ocho alteraciones rechazadas conservando el ledger.

Verificación final: PASS 466/466 en PostgreSQL 17.10 temporal; PASS node --check y git diff --check. Revisión secundaria por scripts/claude-review intentada: exit 1 sin VERDICT; no cuenta como PASS. Gate con esquema completo, advisors y rendimiento con historial acumulado: NOT RUN en esta corrección. No se aplicó ni publicó nada.
