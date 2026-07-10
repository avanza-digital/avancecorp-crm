# Inventario STACK + ESTRUCTURA — CRM VITANOVA (Clínica Álvarez)

Informe crudo para síntesis. Dos repos READ-ONLY inspeccionados:
- Frontend actual (en producción): `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/crm-vitanova-vite`
- Repo raíz backend/ops: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/crm-vitanova`

---

## 1. Frontend `crm-vitanova-vite` — stack exacto

Fuente: `crm-vitanova-vite/package.json:17-61`.

**Framework y build**
- React `^19.2.6` + react-dom `^19.2.6` (SPA, un solo `index.html`).
- TypeScript `~6.0.2`, build `"build": "tsc -b && vite build"` (`package.json:8`).
- Vite `^8.0.12` + `@vitejs/plugin-react ^6.0.1`.
- `vite.config.ts:8`: `base: './'` con comentario textual: `// Deploy estático a Hostinger → base relativa './'.` — o sea, el `dist/` se sube como estático a Hostinger.
- Alias `@` → `./src` (`vite.config.ts:11`, `tsconfig.json:8`).
- tsconfig por referencias (`tsconfig.json` → `tsconfig.app.json` + `tsconfig.node.json`); `tsconfig.app.json`: target es2023, `moduleResolution: "bundler"`, `verbatimModuleSyntax`, `noEmit`, `jsx: react-jsx`, excluye tests del build (`tsconfig.app.json:26`).
- ESLint 10 flat config (`eslint.config.js:8-22`): `@eslint/js` recommended + `typescript-eslint` + `react-hooks` + `react-refresh`.

**UI (todo DOM/web — clave para la decisión RN)**
- Tailwind CSS `^4.3.1` vía plugin `@tailwindcss/vite` (config CSS-first, sin tailwind.config: tokens en `src/index.css` con `@theme inline`, `index.css:111`).
- shadcn/ui estilo `new-york` (`components.json:3`), `radix-ui ^1.6.0` (paquete unificado), `class-variance-authority`, `clsx`, `tailwind-merge`, `cmdk`, `tw-animate-css`, `next-themes` (declarado; el theming real es propio en `src/lib/theme.tsx`).
- 26 componentes shadcn en `src/components/ui/` (accordion…tooltip, incluye `chart.tsx`, `sonner.tsx`, `calendar.tsx`).
- Iconos: `lucide-react ^1.20.0` (`components.json:20` → `"iconLibrary": "lucide"`).
- Charts: `recharts ^3.8.0` (pantallas pesadas se cargan lazy por eso, `App.tsx:15`).
- Drag&drop kanban: `@dnd-kit/core|modifiers|utilities`.
- Fechas: `date-fns ^4.4.0` + `react-day-picker ^10`.
- PDF cliente: `jspdf ^4.2.1` + `jspdf-autotable ^5.0.8` (`src/lib/pdf-cotizacion.ts`, `pdf-font.ts`).
- CSV: `papaparse ^5.5.4` (`src/lib/import-prospectos.ts`).
- Toasts: `sonner ^2.0.7`.
- Errores: `react-error-boundary ^6.1.2`.
- Datos: `@supabase/supabase-js ^2.108.2`.
- Tipografía: **Figtree** desde Google Fonts CDN (`index.html:9`); `--font-sans: 'Figtree', …` (`index.css:112`). El destino Avance pide Plus Jakarta Sans.

**Testing**
- Unit: Vitest `^4.1.9` + coverage v8, `environment: 'node'`, solo lógica pura (`vitest.config.ts:10-18`, coverage incluye `src/lib/format.ts` y `src/lib/reportes.ts`). Tests: `src/lib/format.test.ts`, `leads-reparto.test.ts`, `reportes.test.ts`.
- E2E: Playwright `^1.61.1`, `playwright.config.ts:23-28`: 3 proyectos por ROL (gerente/supervisor/asesor) con `storageState` por rol (login 1 vez), smoke READ-ONLY contra el sitio vivo `https://coral-lark-647471.hostingersite.com` (`playwright.config.ts:10`) u override `E2E_BASE_URL`. Specs en `e2e/` (`auth.setup.ts`, `<rol>.smoke.spec.ts`). Credenciales por `.env` (`.env.example:10-15`).

**Config/secretos**
- `src/lib/config.ts:18-25`: `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` desde `import.meta.env`, throw si faltan; `.env` no versionado, `.env.example` como plantilla. Flags de negocio en el mismo objeto (`WHATSAPP_LIVE`, `META_CONVERSION`, marca/sede hardcodeadas `config.ts:30-32`).

## 2. Organización de `src/` (convención de módulos)

```
src/
├── main.tsx            ← bootstrap: ThemeProvider > TooltipProvider > ErrorBoundary raíz > App + Toaster
├── App.tsx             ← AuthGate + providers de features + Workspace (enrutado por estado)
├── index.css           ← design tokens (oklch, CSS vars), tema light/dark, fuente
├── screens/            ← 1 archivo = 1 pantalla (11): dashboard, leads-nuevos, calendario,
│                          prospectos, pipeline, inteligencia, cotizaciones, inbox, reportes,
│                          configuracion, login
├── components/
│   ├── app/            ← esqueleto: shell.tsx, sidebar.tsx, topbar.tsx, auth-gate.tsx, error-fallback.tsx
│   ├── ui/             ← 26 primitivas shadcn (web)
│   ├── common/         ← reutilizables (sparkline, stat-strip, detail-window, animated-value, cot-badge)
│   └── <dominio>/      ← bi/ calendario/ config/ cotizador/ ficha/ gestion/ prospecto/ reportes/
│                          (los providers de feature viven aquí: ficha-provider, cotizador-provider,
│                           gestion-provider, nuevo-prospecto-provider — modales globales por contexto)
├── lib/                ← capa de datos y dominio SIN UI (TS puro casi todo):
│   ├── store.ts        ← 2.385 líneas; singleton cache+pub/sub, useSyncExternalStore (store.ts:11)
│   ├── types.ts        ← 1.078 líneas de tipos de dominio
│   ├── reportes.ts     ← 524 líneas de agregaciones puras (testeadas)
│   ├── roles.ts, supabase.ts, config.ts, format.ts, search.ts, log-error.ts,
│   │   leads-reparto.ts, import-prospectos.ts, pdf-cotizacion.ts, pdf-font.ts, theme.tsx, utils.ts
└── test/setup.ts
```
- Naming de archivos: kebab-case; dominio/BD en **español snake_case** (`clinica_id`, `contacto_inicial`, `cotizacion_enviada` — `store.ts:39-54`, `85-94` adaptador snake⇄short). Coincide con la convención pedida para Avance.
- `Shell` = flex sidebar + main con topbar + `overflow-auto p-6` (`components/app/shell.tsx:8-17`).

## 3. Enrutado: NO hay router — estado + switch

- `App.tsx:59`: `const [view, setView] = useState('dash')` en `Workspace`; render por cadena de ternarios `App.tsx:86-96`. Sin react-router, sin URLs por pantalla (no hay deep-linking).
- Code-splitting manual: cada screen con `lazy(() => import('@/screens/…'))` (`App.tsx:16-25`) + `Suspense` con spinner (`App.tsx:46-56`).
- **Route-guard por rol via efecto** (`App.tsx:66-69`), transcripción:
```ts
useEffect(() => {
  if (view === 'config' && snap.booted && !can(rol, 'verConfiguracion')) setView('dash')
  if (view === 'leads' && snap.booted && !can(rol, 'repartirLeads')) setView('dash')
}, [view, rol, snap.booted])
```
- Títulos/subtítulos centralizados en mapa `TITLES` (`App.tsx:27-38`).
- Boundaries en 2 niveles: raíz (`main.tsx:22-27`) y por pantalla con `resetKeys={[view]}` (`App.tsx:77-81`); handlers globales `window.error`/`unhandledrejection` → `logError` (`main.tsx:14-15`).

## 4. Estado/datos: store singleton portado de vanilla

- `src/lib/store.ts` (cabecera 1-10): porta FIELMENTE `store.js` (VNStore: cache + pub/sub + ~31 métodos + adaptadores) y `data-live.js`. Cliente Supabase ÚNICO en `src/lib/supabase.ts:7` (`createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY)`, sesión en localStorage por defecto).
- Patrón de consumo: `const snap = useStore()` (hook sobre `useSyncExternalStore`) + `store.metodo()` imperativo.
- Cache en memoria: `me, lineas: Map, usuarios: Map, prospectos: Prospecto[], convs, plantillas, notifs…` (`store.ts:113-120`) — **descarga la cartera completa al boot**; con ~5.000 clientes de Avance esto NO escala tal cual (paginación server-side FALTA).
- Constantes de dominio en el store: `ETAPAS` (5 etapas pipeline salud: nuevo→contacto_inicial→consulta_agendada→cotizacion_enviada→cirugia_agendada, `store.ts:39-45`), `TERMINALES`, `MOTIVOS` de pérdida, `ACT` (tipos de actividad→icono/color del timeline, `store.ts:66-78`), paletas.
- Notificaciones UI: `notify()` wrap de sonner con try/catch "nunca romper por un toast" (`store.ts:105-110`).

## 5. Auth + roles (el esqueleto que Avance quiere)

- `components/app/auth-gate.tsx`: máquina de fases `'init' | 'anon' | 'booting' | 'ready' | 'error'` (`auth-gate.tsx:8`), `BOOT_TIMEOUT_MS = 15000` (`:10`), guard anti doble-boot por `access_token` (`:54-59`), pantallas Splash y BootError con Reintentar/Cerrar sesión.
- `src/lib/roles.ts` — transcripción de la cabecera (`roles.ts:1-2`): `// roles.ts — Fuente única de capacidades por rol … NO es seguridad (eso vive en RLS) — es la UX.`
- Matriz `CAPS` (`roles.ts:19-32`): **3 roles** `gerente | supervisor | asesor` × 10 acciones (`verTodaClinica, verEquipo, filtrarPorAsesor, filtrarPorEquipo, reasignar, repartirLeads, inboxVerAjeno, verConfiguracion, editarConfiguracion, verReportes`). Helper `can(rol, accion)` con fallback a `asesor` (`roles.ts:35-38`), `dashboardVariant(rol)` (`:41-43`), `inboxPuedeResponder` (dueño del prospecto, `:45-51`).
- Jerarquía Avance objetivo es de **4 niveles** (vendedor→supervisor→gerencia→directorio/auditoría): la matriz se extiende con una fila más + acciones de auditoría/solo-lectura; el mecanismo (matriz booleana + `can()` + gating de nav + route-guard + espejo en RLS) transfiere 1:1 como patrón.
- Observabilidad: `src/lib/log-error.ts` — inserta best-effort en tabla `app_errores` (RLS por clínica, lectura solo gerente), scrub de PII/tokens con regex que incluye DNI de 8 dígitos (`log-error.ts:10`), de-dup 30 s, fire-and-forget, jamás lanza. Muy reutilizable como patrón, con cambios RN (`window`, `location`, `navigator` no existen → `ErrorUtils.setGlobalHandler` / `expo-error-recovery`).

## 6. Theming

- `src/lib/theme.tsx`: ThemeProvider propio con `mode` light/dark (clase `.dark` en `<html>`) y **brand swap-able** por CSS var: `BRAND = { magenta: ['#9c1a84','#7d1569'], azul: ['#2557e0','#1c46bd'] }` (`theme.tsx:5-8`), persiste en localStorage (`vn-mode`, `vn-brand`).
- `src/index.css:7-17`: `--brand: #9c1a84` (magenta médico) + "aurora" (blooms de fondo); tokens shadcn en oklch light (`:19-63`) y dark (`:65-109`); charts `--chart-1..5`.
- Identidad Vitanova = magenta #9c1a84 + sol #f0b454 + aurora + Figtree → **todo DESCARTA estéticamente** para Avance (navy #111e3d, acento #2563eb, blanco, tema claro único, sin verde — ojo: VITANOVA usa verdes en success/etapas `#18a06b`, `#22c55e`, `#14b8a6`, `store.ts:46-77`). Lo que sí transfiere es la **idea** de token de marca centralizado y swappeable (en RN: objeto de tokens TS, no CSS vars).

## 7. Repo raíz `crm-vitanova` (backend/ops) — qué vive ahí

`package.json` mínimo (`crm-vitanova/package.json`): solo `@supabase/supabase-js` + `playwright` dev — es repo de ops, no de app.

- **`supabase/`** — el corazón reutilizable:
  - `migrations/`: **30 migraciones** timestamped `AAAAMMDDHHMMSS_nombre.sql` espejo 1:1 del remoto (proyecto `albtrgxnvwmpsyaeqzvn`), documentadas fila por fila en `migrations/MIGRACIONES.md` (`:3-5`, `:20-53`). Cubren: cimientos multi-tenant + RLS jerárquica + hook JWT (`custom_access_token_hook` mete `clinica_id` y `rol` en el token, ver `PASOS-SETUP.md:37-41`), prospectos+scoring, WhatsApp/inbox, cotizador con correlativo por clínica, SLA por etapa con horario hábil, cadencias 3-3-7-7, `pg_cron` (jobs sla-15min, cadencias-15min, primera-respuesta-2min, recordatorio-cita), metas, cupos de usuarios con trigger anti-TOCTOU, calendario/citas, realtime, `app_errores`, anonimización Ley 29733, reparto de leads supervisor. Helpers en **esquema `private`** no expuesto por REST (`MIGRACIONES.md:26`).
  - `remote-schema.sql` (snapshot del esquema real), `SCHEMA.md` (mapa), `APLICAR-TODO.sql`, `seed.sql`, `_migraciones-locales-previas/` (archivo histórico 0001-0009).
  - `functions/`: 4 Edge Functions Deno — `admin-crear-usuario`, `admin-provisionar-clinica`, `whatsapp-enviar`, `whatsapp-webhook` (Meta Cloud API, guía en `GUIA-META-WHATSAPP.md`).
  - `scripts/`: `seed-users.mjs` (crea usuarios demo vía service_role), `test-rls.mjs`.
  - Workflow: `supabase link --project-ref …` + `supabase migration list` para Local==Remote (`MIGRACIONES.md:55-60`).
- **`integraciones/`**: `google-sheets-leads.gs` — Apps Script de intake de leads (hoja/ads → RPC `crear_lead_entrante` con dedup + round-robin, migración #10).
- **`qa/`**: `qa-vite.mjs` (harness Playwright READ-ONLY que verifica comportamiento **distinto por rol**: nav, gating, filtros, 0 errores de consola; doc `qa/README-qa-vite.md:104-124`), `qa-reportes.mjs`, `aislamiento-tenant.sql` (prueba SQL de aislamiento multi-tenant), `qa-out/` screenshots.
- **`docs/`**: `plans/` y `specs/` fechados `AAAA-MM-DD-tema(-design).md` (metodología plan→spec→implementación; misma convención que Avance ya usa en `docs/superpowers/plans/`), `mockups/`.
- **`public_html/`**: la versión ANTERIOR del CRM — React 18 + Babel standalone por CDN, sin build (`.jsx` transpilados en el navegador), con su propio store IIFE `window.VNStore` (`DASHBOARD-VITANOVA.md:85-99`). Hoy retirada del servidor; historia evolutiva: vanilla → React+Babel CDN → Vite (el actual). Es deuda/histórico.
- **`_respaldo-vanilla/`**: el CRM vanilla original (app.js/helpers.js/styles.css) + `LEEME-DEPLOY.txt` (deploy = arrastrar archivos al Administrador de archivos de Hostinger, sitio `coral-lark-647471.hostingersite.com`).
- **`_reuso-avanza/`**: piezas ya recicladas de Avanza (consentimiento Ley 29733, botón WhatsApp, SQL de referencia del CRM base) — precedente de que este esqueleto ya se transplantó una vez.
- `LEYENDA-SISTEMA-VITANOVA.pdf/html`: manual del sistema. `PASOS-SETUP.md`: bootstrap completo del proyecto (crear Supabase, aplicar esquema, hook JWT, seed 7 usuarios, conectar frontend, deploy Hostinger) — checklist de validación de RLS jerárquica (`PASOS-SETUP.md:77-82`).

## 8. Deploy VITANOVA (estado actual)

- `npm run build` → `dist/` (`assets/`, `index.html`, `favicon.svg`, `icons.svg`) con `base:'./'` → subida estática a Hostinger, sitio `coral-lark-647471.hostingersite.com` (subdominio temporal; previsto `crm.vitanova.pe`, `_respaldo-vanilla/LEEME-DEPLOY.txt`). Recordatorio operativo: registrar dominio en Supabase Auth → URL Configuration.
- Preview local de producción: `npm run preview` (4173); dev 5173 (`qa/README-qa-vite.md:45-58`).
- Sin CI/CD; deploy manual (en Avance ya existe precedente de deploy vía API Hostinger MCP `hosting_deployStaticWebsite`, según memoria del proyecto — pero eso aplica a WEB, no a una app Expo).

## 9. Comparación de stacks — LA decisión cara

Tres stacks en juego:

| | Portal Avance (existente) | CRM VITANOVA (esqueleto) | CRM Avance (destino) |
|---|---|---|---|
| Paradigma | Multipágina vanilla: `public_html/*.html` + `js/<página>.js` + `admin/*.html`, PWA (manifest.json, service-worker.js) | SPA React 19 + Vite 8 + TS + Tailwind 4 + shadcn/Radix | React Native (Expo), app nativa |
| Backend | Supabase (+ Edge Functions en `_supabase_functions/`) | Supabase (30 migraciones, RLS jerárquica, pg_cron, 4 Edge Functions) | Supabase (mismo patrón) |
| Deploy | Hostinger `public_html` (vía MCP API) | Hostinger estático (`dist/`) | EAS Build / stores / expo-updates — **nada de Hostinger** |
| UI | CSS artesanal, DOM | Tailwind v4 + Radix + recharts + dnd-kit (todo DOM) | RN primitives (View/Text), StyleSheet u obj. tokens, libs RN |

**Implicaciones concretas de VITANOVA(web) → Avance(RN/Expo):**
1. **NADA de la capa de vista transfiere verbatim**: los 26 `components/ui/*` (Radix/Tailwind renderizan DOM), `index.css`, `shell/sidebar/topbar`, las 11 screens JSX-DOM, `tw-animate-css`, la aurora. Todo se reconstruye con primitives RN (o NativeWind si se quiere conservar la ergonomía Tailwind — decisión aparte).
2. **La capa `lib/` transfiere casi entera** (es la mayor parte del valor: store 2.385 + types 1.078 + reportes 524 líneas de TS mayormente puro): `useSyncExternalStore` existe en RN; cambios puntuales: `localStorage` → AsyncStorage/SecureStore (cliente Supabase con `auth.storage` explícito y `detectSessionInUrl:false`), `window.addEventListener` → `ErrorUtils`, `location/navigator` en log-error, `import.meta.env.VITE_*` → `process.env.EXPO_PUBLIC_*`.
3. **Todo el backend Supabase transfiere como PATRÓN** (migraciones timestamped + doc, RLS jerárquica con helpers en `private`, hook JWT de claims, Edge Functions admin con service_role + cap por trigger, pg_cron para SLA/cadencias/recordatorios, realtime, tabla `app_errores`): es agnóstico del frontend. Se re-modela el dominio (inversiones/contratos, no clínicas/prospectos) y se agrega el 4º rol.
4. **Sustituciones de librería obligadas**: recharts→victory-native/react-native-svg u otra; dnd-kit→gesture-handler+reanimated (o quitar el kanban drag en móvil); jspdf→`expo-print` o PDF server-side en Edge Function (mejor para contratos formales de Avance); sonner→toast RN; lucide-react→`lucide-react-native`; react-day-picker→datepicker RN; Google Fonts link→`expo-font` (Plus Jakarta Sans). `date-fns` y `papaparse` son JS puro y corren en RN (el file-picker cambia a `expo-document-picker`).
5. **Enrutado**: el patrón view-string funciona en RN pero lo idiomático en Expo es expo-router/react-navigation; lo que sí se porta tal cual es el **route-guard por capacidad** y el gating del nav por `can()`.
6. **Testing**: vitest de lógica pura transfiere (o Jest, el default Expo); Playwright e2e NO (→ Maestro/Detox), pero el diseño del harness "smoke por rol, read-only, 0 errores de consola, storageState por rol" es la pieza valiosa a replicar.
7. **Deploy**: pierde sentido todo el flujo `dist/`→Hostinger; aparece un flujo nuevo (EAS, firma, stores u distribución interna, OTA updates) que ni VITANOVA ni el portal tienen — es el costo oculto más grande del cambio de plataforma junto con reconstruir la UI.
8. **Escala**: el store de VITANOVA carga toda la cartera al boot (decenas/cientos de prospectos). Con ~5.000 clientes Avance necesita paginación/consulta server-side (RPCs de agregación como ya hace `views-reportes` para gerente) — no copiar el boot "trae todo".

## 10. Choques de dominio/diseño a vigilar (para el sintetizador)

- VITANOVA usa verdes por todos lados (etapas ganadas `#18a06b`/`#14b8a6`, success oklch, WhatsApp `#22c55e`) — Avance prohíbe verde.
- VITANOVA tiene `anonimizar_prospecto` (Ley 29733, migraciones #38-40 del listado) que borra PII; Avance exige soft-delete `activo=false` sin hard-delete de clientes → adaptar la pieza de cumplimiento sin destruir datos contractuales.
- Moneda: VITANOVA es solo S/ (formato `S/ k` mencionado en `DASHBOARD-VITANOVA.md:104`); Avance es PEN/USD → FALTA multimoneda en todo (tipos, format.ts, reportes).
- Dominio salud no transfiere: etapas (consulta/cirugía), líneas de servicio con ticket_promedio, scoring de prospecto quirúrgico, no-show, cotizador médico con IGV exonerado. El CRM Avance necesita el equivalente inversiones: productos/planes, contratos AP, cronogramas de pago/intereses (hasta 15% anual, interés compuesto ya explorado en el portal), renovaciones/upgrades.
- Multi-tenant (`clinica_id`) probablemente sobra para Avance (empresa única), pero la MISMA maquinaria RLS sirve para el aislamiento jerárquico vendedor/supervisor/gerencia/directorio.

