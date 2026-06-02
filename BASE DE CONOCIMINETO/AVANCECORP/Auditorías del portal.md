---
tags: [auditoria, seguridad, historial]
actualizado: 2026-06-01
---

# Auditorías del portal

Línea de tiempo de las auditorías de seguridad/calidad. **Detalle e informes:** carpeta `AUDITORIA DE PORTAL/` y `public_html/CLAUDE.md` (§ÚLTIMA ACTUALIZACIÓN).

- **2026-05-24** — Auditoría pre-lanzamiento: fix [[Bug de fechas UTC]], [[Interés compuesto]], Excel de pagos endurecido, CSP corregida (Report-Only), límites de Storage, RLS de `perfiles` endurecida contra escalada admin→superadmin.
- **2026-05-26** — Auditoría general (10 agentes): **veredicto sólido, sin hallazgos críticos**. Escalada lateral cerrada (un admin ya no puede degradar a un superadmin).
- **2026-05-28** — Auditoría multi-agente (informe en `_dev_artifacts/INFORME_AUDITORIA_2026-05-28.md`): **Fase 0** = 7 arreglos rápidos (CSP a enforcing, botones táctiles 44px, más fixes UTC, try/catch). **Detectó el riesgo crítico:** [[Clave temporal = DNI]].
- **2026-06-01** — Implementación de la auditoría externa (`AUDITORIA DE PORTAL/`): correcciones de BD (triggers, índices, policies), `.htaccess` bloquea `config.json`, rediseño del selector multi-contrato, deprecación de `novedades.leido`.

## Pendiente crítico
🔴 **Clave inicial = DNI** sigue abierto → [[Clave temporal = DNI]].

## Notas relacionadas
[[Arquitectura del portal]] · [[Inicio]]
