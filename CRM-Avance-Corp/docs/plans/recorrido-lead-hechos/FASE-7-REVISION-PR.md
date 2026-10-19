# Fase 7 · revisión y correcciones del PR

PR: https://github.com/avanza-digital/avancecorp-crm/pull/331. Codex PRIMARY. Fuente inicial revisada: `db63d4720781d819105e25bd20971aae07931da1`; base `6ace3d441bd874a1e06613ee5718b1023e08c39d`. La integración y el ZIP aún estaban pendientes al congelar este informe de fuente; el acta final de entrega registra el commit integrado y su SHA-256.

## Decisiones con evidencia

| Hallazgo CodeRabbit | Decisión de Codex y verificación |
|---|---|
| [Guía no aplicable](https://github.com/avanza-digital/avancecorp-crm/pull/331#discussion_r4309847255) | Aceptado. `RecorridoFicha` oculta la guía si el servidor devuelve `aplica=false`; conserva el formulario abierto y su nota hasta cerrarlo. Dos tests de componente y un E2E adicional. |
| [Gestión sin ciclo](https://github.com/avanza-digital/avancecorp-crm/pull/331#discussion_r4309847278) | Reproducido: `registrar_intento_base_v2` de un descartado sin ciclo falló con 23514 en observación. Corregido mediante 01702–03: sello `sin_ciclo` inmutable y no acreditable, sin backfill, en los tres modos. Conserva `base_sin_ciclo`. Restaurar después un ciclo no atribuye retroactivamente el intento. La primera conversión nueva sigue rechazándose con P0409. |
| [Lock ajeno a evidencia](https://github.com/avanza-digital/avancecorp-crm/pull/331#discussion_r4309847282) | Reproducido con dos sesiones: PATCH autenticado de `confirmada_en` falló con 55P03 mientras una sesión retenía el lead. Se restringe el lock a DELETE y columnas que usa el evaluador; se mantiene la comprobación de lead en todo UPDATE. Se amplía la propuesta del bot para incluir ID/tipo/vence_en/creado_en según tabla; tareas no tiene columna metadata. El mismo ensayo pasa y cambiar `vence_en` sigue rechazando con 55P03 ante lock inverso. |

No se alteran las seis migraciones previas. Se añaden `20261019001702` y `20261019001703`, con preflight, ACL cerradas y comprobación de RLS/auditoría. No se cambia modo ni corte del banco principal. Producción sin modificaciones.

## Verificación tras corregir

| Gate | Resultado | Evidencia |
|---|---|---|
| Integral frontend | PASS · 456 archivos / 7.316 tests, lint, tipos, cobertura, build, bundle y duplicación | `evidencia/fase7-check.log` |
| Guía, formularios y foco en Docker local | PASS · 7/7 E2E, sin retries | `evidencia/fase7-e2e.log` |
| SQL nuevo | PASS · 4 grupos: gestión real en tres modos y rechazo de primera conversión; sello no reasignable a ciclo reparado | `evidencia/fase7-sql-revision.log` |
| Concurrencia de gestión/oficina | PASS · 8 escenarios | `evidencia/fase7-concurrencia.log` |
| Replay de conversión y corrección del PR; carreras financieras | PASS · 5 escenarios y ambos replay completos en copia desechable | `evidencia/fase7-conversion-replay.log` |
| Auth/PostgREST reales | PASS · 79 comprobaciones, limpieza y control original intacto | `evidencia/fase7-http.log` |
| Evaluación, oficina, conversión y cartera | PASS | `evidencia/fase7-sql-regresion.log` |
| Scripts backend | PASS | `evidencia/fase7-scripts.log` |
| Tipos regenerados | PASS · mismo contrato; CLI local omite `__InternalSupabase`, se conserva la anotación 14.5 existente | `evidencia/fase7-tipos.log` |
| Lint SQL | Candidatas sin errores. Persisten los cinco diagnósticos ajenos por cron/net ausentes en el banco | `evidencia/fase7-db-lint.log` |

La suite general Docker anterior pasó 467 pruebas y omitió 26; tras el ajuste de foco de fase 6 pasaron 41 regresiones. En fase 7 se repitió el flujo modificado con siete E2E, sin atribuir una nueva ejecución a toda la suite. Advisors hosted y Safari/VoiceOver manual siguen NOT RUN.

## Revisiones y CI

- Claude participó en arquitectura y conversión crítica; decisiones y correcciones están en REVISION-ARQUITECTURA.md y REVISION-CONVERSION.md. No se inventa una aprobación posterior.
- Codex de GitHub completó revisiones de código y seguridad de `db63d472`, sin hallazgos. CodeRabbit publicó tres observaciones, contrastadas y corregidas arriba.
- CI de ese commit: preflight, app-check, cambios y verify PASS. Supabase Preview SKIPPED; la integración busca `supabase/` en raíz y no creó una rama para este monorepo. No acredita migraciones ni advisors.
- El commit corregido debe pasar sus checks del PR antes de integrar. El ruleset de organización exige aprobación y los contextos Documentación, ERP y Base de datos, que no están entre los workflows de este CRM; no se modificaron esas protecciones.
