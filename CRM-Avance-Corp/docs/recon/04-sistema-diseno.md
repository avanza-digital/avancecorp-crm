# Sistema de diseño CRM VITANOVA (crm-vitanova-vite) — informe técnico para reutilización en CRM Avance Corp (React Native / Expo)

Repo analizado (READ-ONLY): `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/crm-vitanova-vite`
Stack de diseño: **Tailwind CSS v4** (sin tailwind.config; tokens en CSS `@theme inline`), **shadcn/ui estilo "new-york"** sobre **radix-ui v1.6**, **lucide-react**, **Recharts 3.8**, **sonner**, **CVA + tailwind-merge**. React 19 + Vite 8 (`package.json:17-43`).

---

## 1. Tokens (src/index.css — leído completo, 357 líneas)

### 1.1 Marca intercambiable en runtime
`src/index.css:7-9`:
```css
:root {
  --brand: #9c1a84;        /* magenta médico (default) */
  --brand-press: #7d1569;
```
`--primary`, `--ring`, `--sidebar-primary`, `--sidebar-ring` apuntan todos a `var(--brand)` (`src/index.css:29,44,57,62`). El swap en runtime lo hace `src/lib/theme.tsx:5-8`:
```ts
const BRAND: Record<Brand, [string, string]> = {
  magenta: ['#9c1a84', '#7d1569'],
  azul: ['#2557e0', '#1c46bd'],
}
```
`ThemeProvider` (`src/lib/theme.tsx:17-36`) persiste en localStorage (`vn-mode`, `vn-brand`, con try/catch tolerante a modo privado, líneas 14-15) y escribe `--brand`/`--brand-press` en `document.documentElement.style` + togglea la clase `.dark`.

### 1.2 Tokens semánticos — tema claro (`src/index.css:19-63`), transcripción literal de los clave
```css
--radius: 0.65rem;
--background: oklch(0.985 0.004 330);  /* marfil cálido, casi blanco */
--foreground: oklch(0.21 0.02 285);
--card: oklch(1 0 0);                  /* cards blanco puro sobre fondo marfil */
--primary: var(--brand);
--primary-foreground: oklch(0.985 0 0);
--secondary / --muted / --accent: oklch(0.967 0.001 286);
--muted-foreground: oklch(0.552 0.014 285);
--destructive: oklch(0.577 0.245 27.325);
--border / --input: oklch(0.92 0.004 286);
--ring: var(--brand);
--success: oklch(0.6 0.13 160);   /* ¡VERDE! */
--warning: oklch(0.75 0.15 75);
--chart-1: #9c1a84; --chart-2: #0d9488; --chart-3: #2f6bff; --chart-4: #ea9d2c; --chart-5: #7c3aed;
```
+ familia paralela completa `--sidebar-*` (`src/index.css:55-62`): sidebar con su propio background/foreground/primary/accent/border/ring.

### 1.3 Dark mode (`src/index.css:65-109`)
Clase `.dark` (variante custom Tailwind v4: `@custom-variant dark (&:is(.dark *))`, `src/index.css:4`). Redefine todos los tokens: fondo `oklch(0.16 0.006 285)`, card `oklch(0.21 0.007 285)`, bordes con alpha `oklch(1 0 0 / 12%)`, y **paleta de charts aclarada para dark**: `#c95a9b #2dd4bf #7aa6ff #f0b454 #a78bfa` (`src/index.css:95-99`). Toggle en topbar (`src/components/app/topbar.tsx:56-63`) junto al toggle de marca (Palette, líneas 50-55).

### 1.4 Mapeo Tailwind v4 (`src/index.css:111-152`)
Bloque `@theme inline` mapea cada `--color-*` a la var semántica y define escala de radios derivada:
```css
--font-sans: 'Figtree', system-ui, -apple-system, 'Segoe UI', sans-serif;
--radius-sm: calc(var(--radius) - 4px);   /* ≈ 6.4px */
--radius-md: calc(var(--radius) - 2px);   /* ≈ 8.4px */
--radius-lg: var(--radius);               /* 10.4px */
--radius-xl: calc(var(--radius) + 4px);   /* ≈ 14.4px */
```
En la práctica las superficies usan `rounded-xl` (cards, `ui/card.tsx:10`) y `rounded-2xl` (kanban, chips de KPI).

### 1.5 Sombras, chips tintados, aurora (`src/index.css:166-225`)
- **Sombra de card en 2 capas** (`src/index.css:174-175`):
  `--shadow-card: 0 2px 4px -1px rgb(120 110 130 / 0.10), 0 8px 24px -10px rgb(120 110 130 / 0.16);` (variante propia en dark, línea 175). La consume `ui/card.tsx:10` (`shadow-[var(--shadow-card)]`).
- **`.vn-chip`** (`src/index.css:176-177`) — patrón "light-variant" cosechado de MaterialM: `background: color-mix(in srgb, var(--c) 15%, transparent); color: var(--c);` (28% en dark). Se parametriza inline con `style={{'--c': 'var(--chart-2)'}}` — usado en KPI cards (`src/screens/dashboard.tsx:101`), badges de bucket (`dashboard.tsx:203`), contadores de columna kanban (`src/screens/pipeline.tsx:195`).
- **Fondo aurora `.vn-aurora`** (`src/index.css:185-225`): capa `position:fixed` detrás de todo, 3 blooms radiales con `blur(80-90px)` — bloom de marca (58vw arriba-izq), naranja cálido `rgba(240,180,84,.11)` (abajo-der), violeta `rgba(124,58,237,.07)`. Montada en `src/components/app/shell.tsx:11`. Las cards sólidas van encima para no comprometer contraste.

### 1.6 Micro-interacciones (`src/index.css:227-317`)
- Curva de marca: `--ease-out-expo: cubic-bezier(0.22, 1, 0.36, 1)` (línea 232).
- `.vn-rise`: entrada de pantalla, fade + translateY(10px→0), 400ms — corre en cada navegación vía `key={view}` (`src/App.tsx:84`).
- `.vn-pop`: aparición de badges/tiles, 350ms con overshoot desde scale 0.92; los 4 KPIs entran en cascada con `animationDelay: i*60ms` (`src/screens/dashboard.tsx:98,365`).
- `.vn-flick`: latido infinito 2s (badge de notificaciones, `topbar.tsx:69`).
- `.vn-lift`: hover de cards clicables, translateY(-3px) + sombra doble.
- Botones vía `[data-slot="button"]` + `data-variant` (líneas 283-306): lift -1px al hover, **glow del color de marca** en el primario (`0 8px 20px -8px color-mix(... var(--brand) 55%...)`), glow destructive equivalente.
- `.vn-nav-item`: items del sidebar, translateX(2px) al hover.
- **Accesibilidad**: bloque `prefers-reduced-motion: reduce` anula todos los transforms/animaciones (`src/index.css:322-340`).

### 1.7 Impresión (`src/index.css:348-357`)
`@media print` para el Centro de Reportes: oculta `aside, header, .vn-aurora, .vn-no-print`, expande overflow, `break-inside: avoid` por card, `@page { margin: 12mm }`.

---

## 2. Tipografía — DISCREPANCIA CON EL ENCARGO

**La fuente real de VITANOVA es Figtree, NO "Plus Jakarta Sans + Inter"**. Verificado: `index.html:9` carga `https://fonts.googleapis.com/css2?family=Figtree:wght@400;500;600;700;800` y `src/index.css:112` define `--font-sans: 'Figtree', ...`. `grep -r "Jakarta|Inter"` en src/ e index.html: 0 resultados. (Plus Jakarta Sans es la restricción del DESTINO Avance Corp, y geométricamente es pariente cercana de Figtree, así que la jerarquía tipográfica transfiere casi 1:1.)

Escala de uso observada:
- Título de pantalla: `text-lg font-extrabold tracking-tight` (`topbar.tsx:36`), subtítulo `text-xs text-muted-foreground`.
- Valor KPI: `text-2xl font-extrabold tracking-tight tabular-nums` (`dashboard.tsx:109`); label `text-sm font-medium text-foreground/80`; sub `text-xs text-muted-foreground`.
- Encabezado de sección de card: icono 16px + `font-bold text-[15px]` (`dashboard.tsx:84-92`, componente `SectionHead`).
- Sidebar: grupos en `text-[11px] font-bold uppercase tracking-wider` (`sidebar.tsx:51`), items `text-sm font-medium`.
- **Montos**: `font-mono ... font-extrabold tabular-nums` (kanban card `pipeline.tsx:76`, total de columna `pipeline.tsx:197`). `tabular-nums` es sistemático en toda cifra.
- Pesos cargados: 400/500/600/700/800 — el diseño abusa deliberadamente de extrabold (800) para números y títulos.

---

## 3. Paleta de dominio: etapas del embudo y series

### 3.1 Colores por etapa (`src/lib/store.ts:39-49`) — transcripción literal
```ts
export const ETAPAS = [
  { k: 'nuevo',              label: 'Nuevo',              color: '#8b95a7' },  // gris azulado
  { k: 'contacto_inicial',   label: 'Contactado',         color: '#3b82f6' },  // azul
  { k: 'consulta_agendada',  label: 'Consulta agendada',  color: '#9c1a84' },  // magenta marca
  { k: 'cotizacion_enviada', label: 'Cotización enviada', color: '#ef9f2e' },  // ámbar
  { k: 'cirugia_agendada',   label: 'Venta cerrada',      color: '#14b8a6' },  // teal
] as const
export const TERMINALES = [
  { k: 'cerrado_ganado',  label: 'Ganado',  color: '#18a06b' },  // VERDE
  { k: 'cerrado_perdido', label: 'Perdido', color: '#e5484d' },  // rojo
] as const
```
Naming ya en **español snake_case** (coincide con la restricción destino).

### 3.2 Paletas de series
- `PALETTE` (`store.ts:80`): `['#9c1a84','#ef9f2e','#18a06b','#3b82f6','#7c3aed','#14b8a6','#e5484d','#8b95a7']` — consumida por `colorFor(id)` (`store.ts:97-102`), **hash determinista de id → color estable por asesor/línea** (función TS pura, portable tal cual).
- `PALETTE_DASH` (`store.ts:82`): `['#9c1a84','#ea9d2c','#0d9488','#2f6bff','#7c3aed','#c95a9b','#0891b2','#65a30d']`.
- Colores por tipo de actividad del timeline `ACT` (`store.ts:66-78`): whatsapp `#22c55e`/`#16a34a` (verdes), llamada `#3b82f6`, cita `#9c1a84`, etc.
- Tonos de SLA (`pipeline.tsx:24-31`): ok=emerald-500/600, warn=amber-500/600, vencido=destructive — verde otra vez.

**Inventario de VERDE (prohibido en destino)**: `--success` (`index.css:46`), `#18a06b` ganado + en PALETTE, `#14b8a6` teal venta cerrada, `#22c55e/#16a34a` WhatsApp, `#65a30d` en PALETTE_DASH, emerald-500/600 en SLA ok (`pipeline.tsx:25,30`; `dashboard.tsx:41,104,153-154`). Todo estado "positivo" hay que re-mapear (propuesta natural con la paleta destino: éxito = azul acento #2563eb o navy #111e3d; ganado ≠ verde).

---

## 4. Inventario shadcn/ui — 27 componentes en `src/components/ui/`

accordion, alert-dialog, avatar, badge, button, calendar, card, chart, checkbox, command, dialog, dropdown-menu, input, label, popover, progress, scroll-area, select, separator, sheet, skeleton, sonner, switch, table, tabs, textarea, tooltip. (Conteo verificado: 27.)

Config shadcn (`components.json`): style `"new-york"`, `baseColor: "neutral"`, `cssVariables: true`, tailwind config vacío (v4 puro por CSS), `iconLibrary: "lucide"`, aliases `@/components`, `@/lib`, etc.

Detalles con valor de spec:
- **button.tsx** (`ui/button.tsx:7-39`): CVA con 6 variantes (default/destructive/outline/secondary/ghost/link) × 8 tamaños (`default` h-9 px-4, `xs` h-6, `sm` h-8, `lg` h-10, `icon` size-9, `icon-xs` size-6, `icon-sm` size-8, `icon-lg` size-10). Emite `data-slot="button"` y `data-variant` (líneas 55-57) que es lo que enganchan las micro-interacciones globales de index.css. Focus ring: `focus-visible:ring-[3px] ring-ring/50`.
- **badge.tsx** (`ui/badge.tsx:7-27`): pill `rounded-full px-2 py-0.5 text-xs`, 6 variantes.
- **card.tsx** (`ui/card.tsx:5-82`): `rounded-xl border bg-card shadow-[var(--shadow-card)]`, slots Header/Title/Description/Action/Content/Footer, con container queries (`@container/card-header`).
- **chart.tsx** (`ui/chart.tsx:13-80`): wrapper oficial shadcn de Recharts — `ChartConfig` (label/icon/color o theme por serie), `ChartContainer` con `ResponsiveContainer`, `ChartStyle` que inyecta colores por tema light/dark, `ChartTooltipContent` estilizado con tokens.
- **sonner.tsx**: `Toaster` con iconos Lucide y tokens (`--normal-bg: var(--popover)` etc.).
- **sheet.tsx**: panel lateral; la ficha del prospecto vive ahí: `SheetContent side="right" className="w-full gap-0 p-0 sm:max-w-[520px]"` (`src/components/ficha/ficha-provider.tsx:91-94`) — full-screen en móvil, 520px en ≥sm.

Componentes propios reutilizables (`src/components/common/`): `sparkline.tsx` (mini-área Recharts para KPI: gradiente vertical 0.35→0.05 del color de familia, stroke 2px redondeado, sin ejes/tooltip, `aria-hidden`, animación 600ms — `sparkline.tsx:22-42`), `animated-value.tsx` (contador animado), `stat-strip.tsx`, `detail-window.tsx`, `cot-badge.tsx`. Familia BI (`src/components/bi/`): kpi-breakdown, insights-band, resultados-semana, funnel-stages, ic-bars, response-time-panel, conversion-card, dimension-detail, cruce-detail, insight-prospectos-dialog.

---

## 5. Layout: Shell / Sidebar / Topbar

- **shell.tsx** (`src/components/app/shell.tsx:8-18`): `flex h-svh overflow-hidden` → `.vn-aurora` (z-0) + `<Sidebar>` + `<main>` (Topbar + `div.flex-1 overflow-auto p-6`). El scroll vive en el contenido, no en el body.
- **sidebar.tsx**: `aside` **fijo de `w-64` (256px), `shrink-0`, NUNCA colapsa ni se oculta en móvil** (`sidebar.tsx:45`). `bg-sidebar/95 backdrop-blur-sm border-r`. Estructura: header h-16 con logomark 32px ("CA") + nombre; grupos rotulados ("Principal", "Administración") en uppercase 11px; **NAV data-driven** (`sidebar.tsx:17-27`): array `{id, label, icon, staff?}` filtrado por permiso (`can(rol,'repartirLeads')`), con **contadores en vivo** por item (prospectos activos, inbox no leídos, leads sin asignar — `sidebar.tsx:35-38`); item activo: `bg-sidebar-primary text-sidebar-primary-foreground shadow-sm shadow-primary/25` (`sidebar.tsx:62`); footer con Avatar (iniciales sobre `bg-primary/15 text-primary`), nombre, rol y logout (`sidebar.tsx:92-101`). Solo 3 roles: `ROL_LABEL = {gerente, supervisor, asesor}` (`sidebar.tsx:13-15`).
- **topbar.tsx**: `header h-16 sticky top-0 border-b bg-background/80 backdrop-blur-sm px-6` (`topbar.tsx:34`). Izquierda: título+sub de la vista. Derecha: buscador global (**`hidden md:block`, w-64**; Enter → navega a Prospectos con el término, `topbar.tsx:24-31,40-49`), toggle de marca (Palette), toggle de tema (Sun/Moon), campana con Popover de notificaciones (badge rojo `vn-flick`, "9+", `ring-2 ring-background` — `topbar.tsx:64-94`), y CTA primario "Nuevo prospecto" siempre visible.
- **Navegación**: sin router — estado `view` en `App.tsx:59` + switch de pantallas lazy (`App.tsx:16-25,86-96`), ErrorBoundary POR PANTALLA con `resetKeys={[view]}` (`App.tsx:77-81`) y transición `.vn-rise` por `key={view}` (`App.tsx:84`).

---

## 6. Pantallas representativas y responsive

### dashboard.tsx
Contenedor `max-w-[1240px] mx-auto space-y-5` (`dashboard.tsx:344`). Grid KPI: `grid-cols-1 sm:grid-cols-2 lg:grid-cols-4` (`dashboard.tsx:360`). Fila de charts: `grid lg:grid-cols-3` con card ancha `lg:col-span-2` (`dashboard.tsx:372-375`). Donut Recharts: `innerRadius 56 / outerRadius 86, paddingAngle 2, cornerRadius 4` con total en `<Label>` central y leyenda con dots + % (`dashboard.tsx:381-412`). KPI card = chip tintado 40px (`vn-chip rounded-xl`) + Badge de tendencia + valor 2xl extrabold + Sparkline del color de familia (`dashboard.tsx:94-125`). **Dashboard por variante de rol**: `dashboardVariant(rol)` → asesor (bloque "Hoy": cola de acción priorizada + agenda + meta del mes con `Progress`), supervisor (ranking + SLA en riesgo), gerente (comparativa por equipos) (`dashboard.tsx:346-357,437-438,549-611`). Skeleton de carga espejo del layout (`dashboard.tsx:615-633`).

### pipeline.tsx (kanban)
`max-w-[1400px]`; panel `rounded-2xl bg-muted/30 p-3`; **columnas de ancho fijo `w-[280px] shrink-0` con `overflow-x-auto` horizontal** (`pipeline.tsx:171-186`) — el responsive del kanban es scroll horizontal, no re-stacking (patrón que sí funciona en RN con ScrollView horizontal). Header de columna: fondo `color-mix(in srgb, ${col.color} 9%, transparent)`, dot con halo `box-shadow: 0 0 0 3px color-mix(...22%...)`, chip contador `vn-chip`, total `font-mono extrabold` y mini barra de progreso relativa al máximo (`pipeline.tsx:189-201`). Tarjeta: `rounded-2xl bg-card/80 ring-1 ring-black/[0.04]`, hover lift, estado arrastrando `rotate-1 scale-[1.02] opacity-50` (`pipeline.tsx:51-55`); avatar del asesor coloreado con `colorFor`; botón "Cotizar" revelado con `group-hover:opacity-100` (`pipeline.tsx:86`). **Drag & drop HTML5 nativo** (`draggable` + dataTransfer, `pipeline.tsx:134-147`) — inexistente en RN. Drop-zone punteada del color de la etapa (`pipeline.tsx:216-223`).

### Responsive global (medido)
Conteo de prefijos en src/: `sm:` 84, `lg:` 42, `md:` 6, `xl:` 5. Es decir: **dos breakpoints reales (640px y 1024px), diseño desktop-first**. No hay sidebar móvil (ni Sheet ni hamburger): en un teléfono el sidebar de 256px se come la pantalla — VITANOVA se usa en escritorio de clínica. Única concesión móvil real: `isDesktop()` en `src/lib/utils.ts:11-14` (`matchMedia('(min-width: 640px) and (pointer: fine)')`) para suprimir autofocus (evita abrir el teclado), buscador oculto bajo `md`, y la ficha Sheet full-width en móvil.

---

## 7. Evaluación pieza por pieza para React Native (Expo) + restricciones destino

Premisas destino: RN/Expo; navy `#111e3d` primario, azul `#2563eb` acento, fondo blanco, **tema claro único**, **sin verde**, Plus Jakarta Sans; español snake_case (VITANOVA ya cumple el naming).

Qué NO corre en RN (hechos, no opiniones): Radix UI (portales/focus DOM), Tailwind CSS runtime (NativeWind lo sustituye pero SIN `oklch()`, `color-mix()`, `backdrop-blur`, `box-shadow` multicapa, `:hover`, `@media print`), Recharts (SVG/DOM), sonner web, drag HTML5, `document.documentElement`/localStorage, Google Fonts por `<link>`, `position: fixed`.

Qué SÍ sobrevive:
1. **La arquitectura de tokens semánticos** (background/foreground/card/muted/primary/destructive/border + familia sidebar + radios + chart-1..5) — se re-materializa como objeto de tema TS o `tailwind.config` de NativeWind, convirtiendo oklch→hex y re-pintando: primary `#111e3d`, ring/acento `#2563eb`, fondo `#ffffff` (VITANOVA ya usa card blanco puro sobre fondo casi-blanco → en destino fondo blanco plano directamente), `--success` NO puede ser verde.
2. **CVA + variantes**: `class-variance-authority` funciona con NativeWind → `buttonVariants`/`badgeVariants` se portan casi textuales como spec (6 variantes × 8 tamaños, alturas 24/32/36/40).
3. **Patrones TS puros**: `colorFor` hash→color estable, estructura `ETAPAS {k,label,color}`, NAV data-driven con permisos y contadores, dashboard por variante de rol, ThemeProvider (localStorage→AsyncStorage), `cn()` (clsx+twMerge, usado igual por NativeWind).
4. **Lucide**: existe `lucide-react-native` con los mismos nombres de icono — el mapa de iconos del NAV y KPIs se copia cambiando el import.
5. **Jerarquía visual**: chips tintados por familia de color (recalcular el 15% de `color-mix` como alpha hex `${color}26`), extrabold+tabular-nums para cifras, SectionHead (icono 16 + bold 15px), leyendas dot+label+valor+%.
6. **Micro-interacciones como spec**: ease-out-expo, entrada 400ms fade+10px por pantalla, cascada 60ms de KPIs, press-feedback — reimplementables 1:1 con Reanimated; `prefers-reduced-motion` → `AccessibilityInfo.isReduceMotionEnabled()`.

Qué muere o cambia de forma:
- **Los 27 componentes shadcn**: valen como **spec de API y medidas**, no como código. Overlays (dialog/sheet/popover/dropdown/command/tooltip) → bottom sheets (@gorhom/bottom-sheet), Modal RN, action sheets; tooltip casi desaparece en táctil. Formularios (input/select/checkbox/switch/calendar) → TextInput/pickers/switch nativos estilizados. table → FlatList con filas-card en móvil.
- **Layout shell**: sidebar 256px + topbar 64px es patrón de escritorio → en RN: **tab bar inferior (4-5 módulos) + stack headers + drawer opcional en tablet**; el NAV array alimenta ambos. La navegación por estado `view` sin router → expo-router/react-navigation (necesario para deep links y back nativo).
- **Recharts** → victory-native o react-native-gifted-charts (o Skia); el donut con total central, el sparkline (gradiente 0.35→0.05, stroke 2) y las barras de distribución son specs directas.
- **Aurora de fondo**: 3 blooms con blur 80-90px fijos — caro en RN (BlurView full-screen) y contradice el destino "fondo blanco" → descartar.
- **Dark mode + brand switch**: el destino exige tema claro único navy → se eliminan ambos toggles del topbar; conservar la ARQUITECTURA de tokens (por si el futuro pide dark) pero sin UI de cambio.
- **Sombra 2 capas** → iOS: 1 capa `shadowColor/Offset/Opacity/Radius`; Android: `elevation` (aprox. `shadowOpacity 0.08, radius 12, offset {0,4}` + elevation 3).
- **Kanban**: el scroll horizontal de columnas w-280 funciona en RN; el drag HTML5 no — reimplementar con gesture-handler+Reanimated o sustituir por acción "mover a etapa" por long-press (más honesto en táctil con ~5,000 clientes).
- **@media print** → expo-print/generación de PDF (VITANOVA ya tiene jsPDF para cotizaciones, patrón separado).

Lo que VITANOVA NO tiene y Avance necesita (FALTA): 4º nivel de rol (directorio/auditoría) en NAV/ROL_LABEL/dashboardVariant (hoy 3); moneda dual PEN/USD (`money()`/`moneyK()` hardcodean `'S/ '` — `src/lib/format.ts:11-23`); paleta de éxito/positivo sin verde; primitivas móviles (safe areas, tab bar, pull-to-refresh, teclado, offline); carga de Plus Jakarta Sans vía expo-font/@expo-google-fonts; spec de tablas financieras densas (cronogramas de pagos/contratos) que en móvil no existen en VITANOVA.

## 8. Riesgos/observaciones para el sintetizador
- La discrepancia tipográfica (encargo decía "Plus Jakarta Sans + Inter"; el repo usa **Figtree**) sugiere que quien redactó el encargo ya pensaba en la fuente destino — no buscar Inter en VITANOVA, no está.
- VITANOVA es **desktop-first sin modo móvil real**: el "responsive" transferible es la técnica (grids 1→2→4, scroll horizontal del kanban, Sheet full-width), no el layout. Para un CRM RN con vendedores en campo, el layout hay que diseñarlo mobile-first desde cero usando VITANOVA solo como jerarquía de información.
- El acoplamiento micro-interacciones↔CSS (`[data-slot]`/`[data-variant]`) es elegante en web pero no existe en RN: en RN eso se convierte en un componente Button propio que encapsula el press-feedback.
- El magenta `#9c1a84` participa en la paleta de DATOS (chart-1, etapa consulta, PALETTE) además de la marca: al re-pintar a navy hay que rehacer la paleta categórica completa, no solo `--primary` (y validar contraste de navy #111e3d como color de serie sobre blanco: funciona, es muy oscuro — mejor navy para UI y #2563eb + secundarios para series).

