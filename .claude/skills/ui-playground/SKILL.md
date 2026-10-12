---
name: ui-playground
description: "Laboratorio de animaciones de Miguel (carpeta hermana ../ui-playground, con galería Motion/GSAP y Remotion). Úsala cuando pidan crear, aprobar, renderizar o promover una animación o un componente animado para el CRM o el portal."
---

# UI Playground (laboratorio de animaciones)

Vive **FUERA de este repo**, en la carpeta hermana `../ui-playground/`
(= `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/`). Es el laboratorio donde se
crean y aprueban animaciones ANTES de tocar los proyectos reales.

- `galeria/` — componentes de UI animados (React + Vite + **Motion** + **GSAP**) → `npm run dev` → `localhost:5173`.
- `remotion/` — **Remotion**: videos programados (MP4: intros, piezas para redes) y tablero donde se diseñan y aprueban animaciones, también las de componentes → `npm run dev` → `localhost:3000`.
- Regla de herramientas (decisión de Miguel, 27/09/2026): Remotion sirve para los dos, videos y diseño de animaciones. El componente vivo que llega al CRM o al portal se implementa con Motion/GSAP.
- Flujo: crear en el laboratorio → Miguel aprueba → promover (CRM casi directo por ser React; portal portado a vanilla).

**Comandos del flujo** (en `.claude/commands/`): `/lab` (arranca los 2 servidores), `/componente <pedido>`,
`/animacion <pedido>`, `/render [id]`, `/promover <componente> al crm|portal`. Detalle en `../ui-playground/README.md`
y en la nota del vault **"UI Playground (laboratorio de animaciones)"**.
