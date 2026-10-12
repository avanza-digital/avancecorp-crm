# Gerencia — Resumen compacto móvil y citas por equipo

Estado: publicado y verificado el 2026-10-05 (Lima), autorizado por Miguel («ok deploy»). PR #199 integrado. Main local y `avancecorp/main` alineados en `b286b2bfce9a24004e887ee0cb127ecf5dab5a23`; artefacto construido desde copia limpia de ese commit. La vista local de revisión sigue siendo demo y lo indica expresamente.

Decisión de Miguel: aplicar la primera mejora de la PWA a Gerencia; sustituir «próxima cita del equipo» por el total de citas de hoy por equipo, con clic hacia Citas. En teléfono (<768 px), Resumen compacto; en escritorio permanece la vista completa. Se puede abrir y cerrar el resumen completo desde móvil.

- Capital confirmado y meta del mes vigente desde la foto mensual ya usada por Metas, conservando sus guardas de revisión/corte. PEN y USD solo se consolidan con TC real y rótulo de procedencia; sin TC se separa USD y no se calcula cumplimiento. Dato ausente/error no equivale a cero.
- Citas: mismo lector `citas_gerencia_consulta_fn`, normalización y filtro que el módulo existente. Se cuentan citas de leads de hoy en Lima, todos los estados; incluye equipos sin citas y grupo sin supervisor cuando corresponda. Citas de clientes continúan en Agenda.
- Enlaces por día/equipo; al editar el alcance se conserva mes, semana y equipo en la URL. Recargar mantiene ese contexto. El enlace no concede permisos: la RPC conserva su ámbito.
- Solicitudes: pendientes que el servidor permite resolver (`puede_resolver`); abre la bandeja existente y conserva los enlaces de notificaciones. No se añadió un flujo de aprobación.
- Revalida la foto financiera mientras está visible y al volver a la PWA; Citas y solicitudes usan sus lectores periódicos. Sin conexión se advierte que los datos pueden estar desactualizados. Cambio de día en Lima al reanudar, sin sobrescribir históricos elegidos a mano.

Verificación del release: `npm run check` PASS en copia limpia (379 archivos / 6.120 pruebas, duplicación 0,43%); E2E Docker completo PASS (342 aprobadas, 26 omitidas, 0 fallos, 12,9 min). GitHub `preflight`, `app-check` y `verify` PASS. El código de aplicación del merge de Main es idéntico al commit probado `85d8d13f`. Revisión independiente: hallazgos aceptados y corregidos por PRIMARY, con regresiones verificadas. Los trabajos locales ajenos y las copias «archivo 2» se conservaron.

Publicación: build `build-20261006T003148355Z`; ZIP `crm-20261006T003149Z-b286b2bfce9a.zip`; SHA-256 `90b29455d9e6b2fc8eded87f0cb5a02286e18ddf2dc42c8b07eccef5a63f429d`. Preflight de ascendencia PASS contra el release anterior `8fca20bf`. Hostinger aceptó el despliegue y el postflight confirmó el nuevo build y 135/135 archivos exactos (portada, versión, JS/CSS/PWA, fuentes y SVG); PNG excluidos por transformación conocida del CDN. El ZIP no está expuesto por HTTP. Se conserva el ZIP anterior `crm-20261005T214347Z-8fca20bf1215.zip`.

Smoke con sesión real de Gerencia en producción PASS: Resumen a 390 px, capital coherente con escritorio, total de 28 citas y desglose por equipo. El enlace de un equipo con 9 citas abrió exactamente las 9 del día/equipo; recargar mantuvo ambos filtros. Navegación de lectura, sin crear ni modificar datos de negocio. `gate:realidad`: NOT RUN por ausencia de `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` en el entorno de shell; no se aplicó SQL ni Edge. Evidencia y captura: `CRM-Avance-Corp/output/resumen-movil-local/deploy/`.

Código principal: `app/src/screens/hoy/resumen-gerencia-movil.tsx`, integración en `gerencia.tsx`, lector compartido `use-datos-citas-gerencia.ts`, contexto de Citas en `lib/router.ts` y `lib/enlace-citas.ts`. Evidencia local ignorada por Git: `CRM-Avance-Corp/output/resumen-movil-local/verificacion.json`, logs, revisión y captura.

Relacionadas: [[Gerencia - analisis del menu y limites de medicion (2026-10-05)]], [[Auditoria del Resumen de Gerencia - metricas (2026-09-24)]], [[Citas Gerencia - Supervisión por equipo 2026-09-27]].
