---
tags: [auditoria, seguridad, historial]
actualizado: 2026-06-07
---

# Auditorías del portal

Línea de tiempo de las auditorías de seguridad/calidad. **Detalle e informes:** carpeta `AUDITORIA DE PORTAL/` y `public_html/CLAUDE.md` (§ÚLTIMA ACTUALIZACIÓN).

- **2026-05-24** — Auditoría pre-lanzamiento: fix [[Bug de fechas UTC]], [[Interés compuesto]], Excel de pagos endurecido, CSP corregida (Report-Only), límites de Storage, RLS de `perfiles` endurecida contra escalada admin→superadmin.
- **2026-05-26** — Auditoría general (10 agentes): **veredicto sólido, sin hallazgos críticos**. Escalada lateral cerrada (un admin ya no puede degradar a un superadmin).
- **2026-05-28** — Auditoría multi-agente (informe en `_dev_artifacts/INFORME_AUDITORIA_2026-05-28.md`): **Fase 0** = 7 arreglos rápidos (CSP a enforcing, botones táctiles 44px, más fixes UTC, try/catch). Marcó la [[Clave temporal = DNI]] como riesgo — **descartado por Miguel** (ver esa nota).
- **2026-06-01** — Implementación de la auditoría externa (`AUDITORIA DE PORTAL/`): correcciones de BD (triggers, índices, policies), `.htaccess` bloquea `config.json`, rediseño del selector multi-contrato, deprecación de `novedades.leido`.
- **2026-06-03** — Auditoría de prelanzamiento del [[Rol Analista]] + integraciones (45 agentes, verificación adversarial + backend en vivo): **veredicto lanzar-con-reservas**. 0 críticas, **1 alta** (XSS analista→admin por `escapeHtml` ciego a comillas), 4 medias. Detalle → [[Auditoría prelanzamiento 2026-06-03]].
- **2026-06-07** — Auditoría **móvil** completa (todas las páginas y roles, 4 agentes paralelos + verificación): base sólida, **0 críticos**. Corregidos 2 bugs funcionales (cronograma de pagos colgado, descarga de docs admin en iOS) + paquete completo de touch-targets 44px, tooltips touch del directorio, CSV iOS, coordinación de los 3 overlays inferiores, y validaciones del analista. Detalle → [[Auditoría móvil 2026-06-07]].
- **2026-06-13** — Auditoría **exhaustiva** multi-agente (62 agentes, 7 dimensiones + verificación adversarial + SQL en vivo): **veredicto lanzar-con-reservas**, 17 hallazgos confirmados. RLS y matemática compuesta verificadas sanas. **Resueltos en la sesión:** 🔴 tabla de respaldo con PII (RLS off → `DROP`), 🟠 pagos sin auditar desde 2026-06-01 (nuevo trigger `UPDATE`-only), borrado de datos de prueba (AUM −S/100k), backfill de asesores (clientes sin asesor 8→0, ranking del directorio reconcilia). **Pendientes (código):** redondeo `.toFixed`, `proteger_campos_inmutables`, ciclo de vida de contratos, HIBP, drift `diagnostico-push`. Detalle → [[Auditoría exhaustiva 2026-06-13]].
- **2026-07-10** — Auditoría del **CRM** (app React, fuera de DB): dos análisis independientes unificados. Compila y pasa 51/51 tests, 0 vulnerabilidades, pero **no listo para datos reales**: 0 críticas; bloqueantes = carrera de sesión en logout (`auth.tsx:231`) + red de tests real (cobertura real ~17%, auth/pantallas 0%) + frontera de datos sin tipar. Riesgo de proceso: el CI y ~45% del código nuevo siguen **sin commit**. **Implementado el mismo día** (6 commits): los 3 bloqueantes cerrados (XState, 120+6 tests, frontera tipada+Valibot), dedup de dominio (1 clon restante), a11y Radix, Sentry opcional, Lefthook/CI e2e — y 2 hallazgos de seguridad nuevos del espejo RLS corregidos. Falta `git push`. Detalle → [[Deuda técnica CRM fuera de DB 2026-07-10]] · lado DB → [[Auditoría CRM 2026-07-10]].

## Notas relacionadas
[[Arquitectura del portal]] · [[Inicio]]
