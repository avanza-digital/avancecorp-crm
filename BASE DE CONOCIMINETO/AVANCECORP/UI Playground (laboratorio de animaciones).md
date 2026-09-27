# UI Playground (laboratorio de animaciones)

> Creado el 2026-07-28. Laboratorio donde se crean y aprueban animaciones y componentes
> ANTES de tocar los proyectos reales. Nada de aquí va directo a producción.

## Dónde vive

**Fuera del repo de AVANCECORP**, como carpeta hermana:
`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/`

| Carpeta     | Qué es                                                                                  | Servidor          |
| ----------- | --------------------------------------------------------------------------------------- | ----------------- |
| `galeria/`  | Componentes UI animados — React + Vite + Motion + GSAP + Lenis + Tailwind v4 + shadcn/ui | `localhost:5173`  |
| `remotion/` | Videos programados (MP4) y diseño de animaciones — Remotion                             | `localhost:3000`  |

## Regla de herramientas (decisión 2026-07-28)

- **Remotion** = **videos** (MP4: intro del logo, piezas para redes) **y** tablero donde se diseñan y aprueban animaciones, también las de componentes (decisión de Miguel, 27/09/2026). El componente vivo se implementa después con Motion/GSAP.
- **Motion** (`motion/react`) = micro-interacciones de UI: hovers, entradas, transiciones.
- **GSAP** (`useGSAP` + ScrollTrigger) = animaciones ligadas al scroll y timelines complejos. Hoy es gratis al 100% (plugins incluidos).

### Ampliación del stack (2026-07-29, pedido de Miguel)

- **Lenis** (`lenis` v1) = scroll suave; se integra con GSAP vía `gsap.ticker` (patrón en el README de Lenis; usar `lenis/react` con `autoRaf: false`).
- **Tailwind CSS v4** = utilidades; entra por `@tailwindcss/vite` (plugin en `vite.config.ts`) y `@import "tailwindcss"` al tope de `src/index.css`. Sin `tailwind.config` — en v4 todo se configura por CSS.
- **shadcn/ui** = componentes copiables; inicializado con **Base UI + preset Nova** (Lucide/Geist). Alias `@/*` → `src/*` en tsconfig y vite. Agregar piezas con `npx shadcn@latest add <componente>`; caen en `src/components/ui/`.
- Los tokens de identidad del laboratorio (`--fondo`, `--tinta`, `--acento`…) conviven en el mismo `:root` con los de shadcn (`--background`, `--primary`…); el marco visual del lab manda porque sus reglas van después del import.
- **Next.js NO se instaló**: la galería corre sobre Vite; todas estas librerías funcionan igual ahí. Si algún día se arranca un proyecto Next.js real (p. ej. landing nueva), se crea aparte.

## Flujo de trabajo

**Idea central de Miguel (2026-07-28): en el laboratorio se hace primero el DISEÑO
(Remotion es su tablero de diseño de animaciones); luego los modelos de lenguaje —
las sesiones de IA— ADAPTAN ese diseño aprobado al destino real.**

**Prioridad fijada por Miguel (mismo día, más tarde): REMOTION ES LO PRINCIPAL.**
La galería no le convenció como paso obligatorio y queda solo como archivo de
referencia. Los componentes para el CRM/apps se construyen **directo en el destino**
(el CRM es React: Motion/GSAP entran nativo), con su proceso normal de release.

1. Miguel pide un componente/animación (comandos: `/componente`, `/animacion`).
2. Se genera en el laboratorio con su demo; Miguel lo ve en el navegador (hot reload).
3. Aprobado → la IA lo **adapta/promueve** (`/promover`):
   - **CRM** (crm.miavance.com, React): casi copy-paste — mismo stack a propósito.
   - **Portal** (miavance.com, vanilla sin build): se **porta** a CSS/JS puro, aditivo con fallback, respetando el CLAUDE.md de `public_html` (`?v=N` + SW).
   - **Videos**: `/render` → MP4 en `remotion/out/`.
4. El original queda en la galería como referencia.

## Estado inicial (2026-07-28)

- Galería con 4 categorías vivas: **Botones premium** (navy-dorado con brillo, CTA verde, fantasma),
  **Cargas y skeletons** (panel dashboard con shimmer → datos en cascada), **Hero sections**
  (entrada palabra por palabra), **Scroll reveal** (GSAP ScrollTrigger).
- Remotion con la composición **LogoAvanceCorp** (intro del logo 5s, 1920×1080) ya renderizada en `out/logo-avance-corp.mp4`.
- Tokens de marca en `galeria/src/index.css`; logo en `remotion/public/avance-logo-full.png`.

## Comandos (en `.claude/commands/` del repo AVANCECORP)

- `/lab` — arranca los dos servidores y **SIEMPRE cierra con la guía de uso** (pedido expreso de Miguel; la guía vive en `.claude/commands/lab.md`).
- `/componente <pedido>` — componente nuevo en la galería, registrado en el menú, verificado con build.
- `/animacion <pedido>` — composición nueva de Remotion, verificada con un fotograma renderizado.
- `/render [id]` — exporta el MP4 final.
- `/promover <componente> al crm|portal` — lleva lo aprobado a su destino con las reglas de cada uno.

Relacionadas: [[Bienvenido]]
