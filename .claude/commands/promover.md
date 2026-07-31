---
description: Lleva un componente aprobado de la galería al CRM o al portal
argument-hint: <componente> al crm | al portal
---

Miguel aprobó un componente de la galería del UI Playground y quiere promoverlo: **$ARGUMENTS**

Fuente: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/galeria/src/componentes/`

Reglas por destino:

- **CRM** (`AVANCECORP-desktop/CRM-Avance-Corp/app`, React + Vite):
  - Adapta el componente a los patrones y tokens del CRM (no pegues los colores del playground a ciegas: el CRM tiene su propio tema).
  - Sigue las convenciones del repo (TypeScript estricto, a11y — considera el agente revisor-a11y) y corre sus tests/lint.
  - **NO desplegar** sin orden expresa de Miguel.

- **Portal** (`AVANCECORP-desktop/public_html`, JavaScript vanilla SIN build):
  - **LEE PRIMERO `public_html/CLAUDE.md`** (§6 patrones obligatorios, §13 versiones `?v=N`, §14 deploy).
  - El port es a CSS/JS puro, **ADITIVO y con fallback** (el portal está en uso por clientes reales).
  - Sube el `?v=N` de cada módulo tocado en TODOS sus importadores + `CACHE_VERSION` del Service Worker.
  - **NO subir a Hostinger** sin orden expresa de Miguel.

En ambos casos:
- El playground manda en el DISEÑO; el destino manda en los PATRONES de código.
- Antes de tocar nada: `git status` (varias sesiones comparten el mismo árbol — regla del proyecto).
- El componente original QUEDA en la galería como referencia (no se borra).
