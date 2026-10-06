# Gerencia — Resumen compacto móvil y citas por equipo

Estado: implementado y verificado en local el 2026-10-05. Publicación autorizada por Miguel («ok deploy»); pendiente de completar el release y su verificación. La pestaña local de revisión usa sesión demo y lo indica expresamente.

Decisión de Miguel: aplicar la primera mejora de la PWA a Gerencia; sustituir «próxima cita del equipo» por el total de citas de hoy por equipo, con clic hacia Citas. En teléfono (<768 px), Resumen compacto; en escritorio permanece la vista completa. Se puede abrir y cerrar el resumen completo desde móvil.

- Capital confirmado y meta del mes vigente desde la foto mensual ya usada por Metas, conservando sus guardas de revisión/corte. PEN y USD solo se consolidan con TC real y rótulo de procedencia; sin TC se separa USD y no se calcula cumplimiento. Dato ausente/error no equivale a cero.
- Citas: mismo lector `citas_gerencia_consulta_fn`, normalización y filtro que el módulo existente. Se cuentan citas de leads de hoy en Lima, todos los estados; incluye equipos sin citas y grupo sin supervisor cuando corresponda. Citas de clientes continúan en Agenda.
- Enlaces por día/equipo; al editar el alcance se conserva mes, semana y equipo en la URL. Recargar mantiene ese contexto. El enlace no concede permisos: la RPC conserva su ámbito.
- Solicitudes: pendientes que el servidor permite resolver (`puede_resolver`); abre la bandeja existente y conserva los enlaces de notificaciones. No se añadió un flujo de aprobación.
- Revalida la foto financiera mientras está visible y al volver a la PWA; Citas y solicitudes usan sus lectores periódicos. Sin conexión se advierte que los datos pueden estar desactualizados. Cambio de día en Lima al reanudar, sin sobrescribir históricos elegidos a mano.

Verificación: 6.120 pruebas unitarias, 10 E2E en Docker, lint/typecheck/build/bundle PASS; revisión Claude con dos P2 aceptados/corregidos y regresiones verificadas. El gate integral falla únicamente por copias preexistentes «archivo 2» que elevan duplicación a 1,07%; diagnóstico excluyéndolas: 0,43% PASS. Se conservaron esas copias y el resto del trabajo local ajeno. Lectores reales probados con transporte simulado; no se afirma validación con cuenta real de Gerencia en producción.

Código principal: `app/src/screens/hoy/resumen-gerencia-movil.tsx`, integración en `gerencia.tsx`, lector compartido `use-datos-citas-gerencia.ts`, contexto de Citas en `lib/router.ts` y `lib/enlace-citas.ts`. Evidencia local ignorada por Git: `CRM-Avance-Corp/output/resumen-movil-local/verificacion.json`, logs, revisión y captura.

Relacionadas: [[Gerencia - analisis del menu y limites de medicion (2026-10-05)]], [[Auditoria del Resumen de Gerencia - metricas (2026-09-24)]], [[Citas Gerencia - Supervisión por equipo 2026-09-27]].
