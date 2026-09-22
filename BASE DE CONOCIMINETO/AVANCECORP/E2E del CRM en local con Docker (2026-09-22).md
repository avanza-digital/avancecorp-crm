---
tags: [crm, e2e, verificacion, docker]
fecha: 2026-09-22
---

# E2E del CRM en local con Docker

Sigue a [[CI del CRM sin E2E en GitHub (2026-09-21)]]. Miguel pidió que los E2E se corran **en local con Docker** y que Claude y Codex lo sepan, para no depender de GitHub.

- Comando: `cd CRM-Avance-Corp/app && npm run test:e2e:docker` (acepta `-- <spec> --workers=2`). `check:all` ya lo usa.
- Script: `CRM-Avance-Corp/app/scripts/e2e-docker.sh`. Imagen oficial `mcr.microsoft.com/playwright:v<versión del lockfile>-noble`; los `node_modules` de Linux viven en el volumen `avancecorp-crm-e2e-node-modules` y se reinstalan solos cuando cambia `package-lock.json`. El árbol se monta en vivo.
- La regla está en `.ai/VERIFICATION.md` («E2E: SIEMPRE en local con Docker»), `AGENTS.md` (Codex) y `CLAUDE.md` (Claude): no añadir E2E a GitHub Actions; Docker apagado → `NOT RUN`, nunca PASS.
- **2 workers por defecto.** La primera corrida con ~7 workers se ahogó (timeouts y «Target crashed»: Docker tiene 6 GB compartidos con los bancos Supabase de otras sesiones). Con 2: **232 passed · 26 skipped · 0 failed en 8,8 min**.
- La integración de conversión (`playwright.conversion.config.ts`) usa su propio banco Supabase en Docker y no entra en este gate.

Relacionado: [[Inicio]].
