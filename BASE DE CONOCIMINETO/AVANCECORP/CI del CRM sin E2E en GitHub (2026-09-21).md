---
tags: [crm, ci, verificacion]
fecha: 2026-09-21
---

# CI del CRM sin E2E en GitHub

Miguel pidió retirar el paso E2E de GitHub porque no le resulta suficientemente funcional. El workflow `.github/workflows/crm-app-quality.yml` deja de ejecutar Playwright y el check obligatorio `verify` depende solamente del detector de cambios y de `app-check`.

`app-check` conserva `npm run check`: lint, tipos, pruebas con cobertura, build y sus validaciones de bundle. Las PR clasificadas como solo documentación siguen omitiendo ese job. La suite Playwright permanece disponible localmente con `npm run test:e2e` para cambios que la necesiten según `.ai/VERIFICATION.md`.

Relacionado: [[Inicio]], [[Deploy a Hostinger]].
