# PLAN — CRM AVANCE CORP (P-054)

> **Fecha:** 2026-07-09 · **Autor:** Claude (reconocimiento multi-agente, 12 agentes) · **Estado:** PENDIENTE DE APROBACIÓN DE MIGUEL
> **Fuente analizada (READ-ONLY):** CRM VITANOVA de Clínica Álvarez — `AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/` (repo `avanzadigitald/cliente-clinica-alvarez`, último commit 2026-07-08)
> **Destino:** CRM de Avance Corp S.A.C. en **React Native (Expo)**, sobre el proyecto Supabase del portal (`dctqcbznekcyxhjujuci`)
> **Anexos:** los 10 informes técnicos completos del reconocimiento están en `docs/recon/` (citan archivo:línea de todo lo afirmado aquí).

---

## 0. Resumen ejecutivo

1. **VITANOVA SÍ es una buena base — pero solo la mitad de ella.** El esqueleto de **backend** (RLS jerárquica con helpers en esquema `private`, hook JWT, triggers de negocio, crons idempotentes, edge functions con validación server-side, disciplina de migraciones) está probado en producción y transfiere casi entero como patrón. La capa de **datos del frontend** (store singleton que descarga toda la cartera al boot, re-fetch total tras cada mutación, realtime sin filtros, reportes 100 % en cliente) **NO sobrevive** el traslado a React Native con la meta de ~5,000 clientes y red móvil: se reemplaza por TanStack React Query + paginación server-side + RPCs de agregación. La capa de **UI** (Radix/shadcn/Tailwind-CSS) no corre en RN: transfiere como *especificación* (tokens, medidas, variantes, jerarquía visual), no como código.
2. **Decisión arquitectónica (punto 4): MISMO proyecto Supabase**, con frontera dura: todas las tablas nuevas en un **esquema Postgres `crm`** dedicado, jerarquía comercial en `crm.equipo` (sin tocar el CHECK de `perfiles.rol`), vendedores sin acceso jamás a columnas bancarias, y toda migración vía branch de Supabase + suite de tests RLS antes de merge. Panel de 3 lentes independientes: unánime 3/3. Sustento completo en §5.
3. **Stack (mandato de Miguel: React Native):** Expo SDK 57 **universal** (Android/iOS + web vía react-native-web), expo-router, NativeWind v5 + react-native-reusables (el "shadcn de RN" — mismo ADN que VITANOVA), TanStack React Query, victory-native (charts), FlashList, expo-notifications, supabase-js con AsyncStorage, EAS Build/Update. Es casi el mismo stack que el equipo YA opera en producción con la app Belysh (`avanzadigitald/cliente-belysh-app`, owner EAS `avancecorp`).
4. **Correcciones a las premisas del encargo** (verificadas contra la BD real en vivo):
   - `clientes_preregistro` **no existe** (ni tabla ni referencias en el repo). No hay embrión de pipeline en el portal: todo lo pre-contrato FALTA.
   - La escala actual es 148 perfiles / 138 contratos / 1,410 cuotas; ~5,000 clientes es la **meta**, no el presente. El CRM debe nacer paginado, pero sin sobre-ingeniería de infraestructura.
   - `MD_AVANCE_CRM_F1.md` **no se encontró** en disco, Drive, Notion ni historiales git (búsqueda exhaustiva). La reconciliación (§6) se hace contra la definición de F1 que da el propio encargo (jerarquía de 4 niveles) + los documentos internos que sí existen (`REUSO-crm-vitanova-vite.md`, spec fábrica de CRMs 2026-06-20). **Miguel: si el archivo existe en otro lado, pásalo y reconcilio de nuevo antes de P-055.**

---

## 1. Qué es VITANOVA (inventario, síntesis)

Detalle completo con citas archivo:línea en `docs/recon/01` a `07`.

### 1.1 Stack real vs. el stack de Avance — la decisión más cara, dicha explícitamente

| | Portal Avance (producción) | CRM VITANOVA (fuente) | CRM Avance (destino) |
|---|---|---|---|
| Frontend | HTML/CSS/JS **vanilla**, sin build, multipágina, PWA | **SPA React 19 + Vite 8 + TS + Tailwind v4 + shadcn/Radix** | **React Native (Expo SDK 57), app universal** |
| Backend | Supabase (9 tablas, 37 policies, 9 edge functions, pg_cron) | Supabase (18 tablas, ~38 policies, 43 migraciones, 4+1 edge functions, 5 crons) | El MISMO Supabase del portal + esquema `crm` |
| Deploy | Hostinger vía MCP (`miavance.com`) | Hostinger estático (`dist/`) | **EAS Build/Update + stores**; build web opcional a Hostinger |

Los **tres stacks de frontend son distintos**. VITANOVA no comparte stack ni con el portal ni con el destino RN. Implicación honesta: del frontend de VITANOVA se reutiliza la **arquitectura y la lógica TypeScript pura** (~4,000 líneas de lib/ transferibles con adaptación), y la UI se **reconstruye** en RN usando VITANOVA como spec visual y de interacción. Del backend se reutiliza casi todo el patrón. El costo oculto más grande del cambio de plataforma: el pipeline de distribución (EAS, firma, stores, OTA) que ni el portal ni VITANOVA tienen.

### 1.2 Estructura y convenciones (fuente)

- Monorepo de cliente: `crm-vitanova-vite/` (app) + `crm-vitanova/` (supabase/, integraciones/, qa/, docs/).
- App: `src/screens/` (11 pantallas, 1 archivo = 1 pantalla) + `src/components/<dominio>/` (providers de feature como modales globales por contexto) + `src/components/ui/` (27 shadcn) + `src/lib/` (capa de datos sin UI). Kebab-case en archivos, **español snake_case en BD y dominio** (ya cumple la convención de Avance).
- Sin router: navegación por estado + ternarios (NO copiar; en RN va expo-router).
- Docs con metodología plan→spec fechados (`docs/plans/`, `docs/specs/`) — misma convención que Avance ya usa en `docs/superpowers/`.

### 1.3 Autenticación y resolución de rol (fuente)

- Login `signInWithPassword`, sin registro público; usuarios los crea el gerente vía edge function con cuota server-side y contraseña temporal.
- **AuthGate**: máquina de fases `init|anon|booting|ready|error` con timeout de 15 s, dedupe de boots por token, re-boot en `TOKEN_REFRESHED` (quirk a corregir en móvil: comparar `user.id`, no `access_token`).
- Rol resuelto por **fila en tabla** (`usuarios.rol`), leída una vez en boot, con fallback de privilegio mínimo (sin fila ⇒ rol más bajo). El hook `custom_access_token_hook` inyecta además claims al JWT.
- **Doble capa declarada** (`roles.ts:2`): *"NO es seguridad (eso vive en RLS) — es la UX."* Matriz `CAPS: Record<Rol, Caps>` con 10 capacidades + `can(rol, accion)` + `dashboardVariant(rol)`. Nav data-driven filtrado por `can()` + route-guard que expulsa.
- **Modo auditoría**: staff ve lo ajeno en solo-lectura (banner "auditor", sin composer/acciones); solo el dueño escribe. Es por-registro, no por-rol — la semilla del rol directorio, pero no lo cubre.

### 1.4 Jerarquía y scoping de datos (fuente) — el corazón reutilizable

RLS en TODAS las tablas. Cuatro mecanismos ortogonales (transcripciones completas en `docs/recon/03`):

1. **`private.asesor_ids_visibles(uid)`** — SECURITY DEFINER, STABLE: gerente ⇒ toda la clínica; supervisor ⇒ su **subárbol recursivo** por `usuarios.supervisor_id` (CTE `with recursive`); asesor ⇒ solo él. **El CTE soporta N niveles sin cambio alguno: los 4 niveles de Avance caben sin rediseñar el patrón.**
2. Policies que consumen el set: `using (asesor_id in (select private.asesor_ids_visibles((select auth.uid()))))` — evaluado una vez por query (initplan), no por fila.
3. Esquema **`private`** no expuesto por PostgREST para helpers y funciones-trigger; hardening sistemático tras cada bloque (fijar `search_path`, `revoke execute`).
4. Escrituras privilegiadas SOLO por edge function/RPC SECURITY DEFINER que revalida rol por dentro (alta de usuarios sin policy INSERT; `crear_lead_entrante` grant solo `service_role`; huecos de policy cerrados por trigger, p. ej. `bloquear_reasignacion_asesor`).

Además: soft-delete estricto en prospectos/cotizaciones (sin policy DELETE — imposible hard-delete desde el cliente), tabla de leads "parkeados" al supervisor de turno con round-robin, cupos de usuarios con trigger anti-TOCTOU, y suite `scripts/test-rls.mjs` (logins reales por rol con anon key, verifica visibilidad exacta y aislamiento entre subárboles) + `qa/aislamiento-tenant.sql` (impersonación por claims + iteración dinámica de tablas + rollback).

### 1.5 Sistema de diseño (fuente)

- Tailwind v4 CSS-first: tokens semánticos en `@theme` (background/card/primary/muted/destructive/border + familia sidebar + radios + chart-1..5), marca swappeable por CSS var, dark mode, sombra de card en 2 capas, chips tintados `color-mix`, micro-interacciones con `ease-out-expo` (entrada 400 ms, cascada 60 ms de KPIs, press-glow), `prefers-reduced-motion`.
- Tipografía real: **Figtree** (no Plus Jakarta Sans — pariente geométrica cercana; la jerarquía transfiere casi 1:1). Escala: KPI `2xl extrabold tabular-nums`, títulos `lg extrabold tracking-tight`, montos `font-mono extrabold`.
- 27 componentes shadcn (spec de API y medidas: button 6 variantes × 8 tamaños, card con slots, sheet lateral 520px para la ficha) + componentes propios (sparkline, stat-strip, animated-value).
- **Desktop-first sin modo móvil real** (sidebar fija de 256 px que nunca colapsa; 84 usos de `sm:`, 6 de `md:`). Para vendedores en campo, el layout de Avance se diseña **mobile-first desde cero** (tab bar inferior + stack), usando VITANOVA solo como jerarquía de información.
- **Verde por todos lados** (success, ganado `#18a06b`, teal `#14b8a6`, WhatsApp `#22c55e`, emerald del SLA ok) — prohibido en el destino: el mapa semántico de color se redefine completo (§7).

### 1.6 Módulos funcionales (fuente)

11 pantallas: dashboard por variante de rol (cola "Tu siguiente acción hoy" + agenda + meta del mes), pipeline kanban (5 etapas + 2 terminales, `validTransition`), cartera/tabla, bandeja de reparto de leads (parkeados → asignación 1-clic, supervisor solo a su equipo), inbox WhatsApp 3 paneles (modo auditoría), cotizaciones (borrador→enviada→vista→aceptada/rechazada/vencida + PDF), calendario Mes/Semana/Día (3 fuentes fusionadas: citas + overlays de vencimientos y SLA, reprogramación drag con undo), inteligencia (BI de conversión por canal/asesor/servicio + insights accionables auto-generados), centro de reportes (14 bloques, export PDF/CSV), configuración solo-gerente (6 CRUDs), login.

Patrones estrella (documentados con líneas en `docs/recon/05` §5): cola accionable con predicado único y dedupe por prioridad de bucket; SLA de 1ª respuesta sellado por trigger + cron; cadencias 3-3-7-7 como DATOS dirigidas por eventos; "¿Lograste contacto?" (cada toque del vendedor se vuelve dato sin fricción); scoring 100 % en BD ("el cliente NUNCA recalcula"); import CSV con dry-run y dedup.

### 1.7 Edge functions e integraciones (fuente)

4 en repo + 1 desplegada sin fuente (drift — anti-patrón a prohibir): `admin-crear-usuario` (gerente-gated, anti-escalación, cuota, rollback), `admin-provisionar-clinica` (multi-tenant — se descarta), `whatsapp-enviar` (patrón **dual-cliente**: JWT del usuario vía RLS decide autorización + service_role solo para secretos en **Vault**; tabla config con RLS `using(false)`), `whatsapp-webhook` (firma HMAC tiempo-constante, idempotencia por `mensaje_externo_id`, alta automática con round-robin). WhatsApp Cloud API está **a medio hacer incluso en VITANOVA**: no envía plantillas ni chequea la ventana de 24 h — y para Avance las plantillas `utility` son el caso principal (mensajes iniciados por la empresa).

### 1.8 Deuda técnica del origen (lo que NO se copia — verificado en código)

Detalle en `docs/recon/07`: store monolito de 2,385 líneas que **carga todo al boot sin paginación** (con el cap de 1,000 filas de PostgREST además **trunca en silencio**); full re-fetch tras cada mutación (10 sitios); realtime tabla-completa sin filtro; mutación in-place + memoización por referencia (el update optimista está **muerto** — la tarjeta no se mueve hasta el roundtrip); soft-delete filtrado por consumidor y no en la query (eliminados cuentan en KPIs); reportes con `.limit(5000/10000)` que truncan sin aviso; HTML generado en la capa de datos; colores/emojis en el dominio; 30 `catch {}` vacíos con un `logError` excelente que casi nadie llama; import con reintento fila-a-fila (500 requests); delete+insert no atómico en cadencias; navegación por view-string; config hardcodeada (marca, sede, "Junio 2026"); cero tests del store; hard-delete de citas. **Además:** el repo fuente tiene 13 commits sin push y 4 archivos modificados sin commit (higiene, no bloquea).

---

## 2. Stack React Native del destino (mandato: "todo con React Native")

Detalle y justificaciones en `docs/recon/09`. Regla rectora: **repetir el stack que el equipo ya opera en producción** (app Belysh) y sumar solo lo imprescindible.

| Capa | Elección | Nota |
|---|---|---|
| Framework | **Expo SDK 57** (RN 0.86, React 19.2) — app **universal**: Android + iOS + web (react-native-web) | Vendedores en campo = móvil; gerencia/directorio = escritorio vía build web. Una sola base de código. Belysh ya compila target web |
| Navegación | **expo-router** (typed routes) | Grupos de rutas por rol: `(auth)/ (vendedor)/ (supervision)/ (directorio)/` — mapea la jerarquía |
| Datos | **@tanstack/react-query** + supabase-js `^2.110` (AsyncStorage, `detectSessionInUrl:false`, PKCE, AppState→auto-refresh) | Reemplaza el store boot-carga-todo: queries paginadas (`.range()`), invalidación selectiva, mutaciones optimistas inmutables |
| Estilos | **NativeWind v5** (Tailwind v4, tokens `@theme`) | El MISMO sistema de tokens que VITANOVA usa en web — máxima transferencia del spec. Plan B sin impacto: NativeWind 4.2 + Tailwind 3 |
| Componentes | **react-native-reusables** (+ @rn-primitives) | El shadcn de RN: mismo ADN (cva + clsx + tailwind-merge), código copiado = ownership del tema navy. Tamagui descartado (sistema propio, curva alta); gluestack v3 = plan B |
| Charts | **victory-native XL** (+ react-native-skia) | Donut con total central, sparklines y barras de VITANOVA son specs directas. En web: CanvasKit WASM |
| Listas | **@shopify/flash-list v2** | Para la cartera (~5,000): virtualización + paginación server-side |
| Push | **expo-notifications** + edge function → Expo Push Service | Se integra con el patrón `notificar-pagos` ya en producción |
| PDF | **expo-print** (comprobantes ad-hoc) + **edge function server-side** (documentos formales) | PDFs con validez uniforme se generan en el servidor |
| Fuentes | **@expo-google-fonts/plus-jakarta-sans** + expo-font | Empaquetada en el binario (funciona offline en campo) |
| Íconos / toasts / fechas | lucide-react-native · sonner-native · date-fns + datetimepicker RN | Mismos nombres de íconos que VITANOVA (cambio de import) |
| Build | **EAS Build + EAS Update** (OTA) | Copiar `eas.json` de Belysh (canales preview/production, autoIncrement) |
| Testing | jest-expo + @testing-library/react-native; QA por rol con **Maestro** (o Playwright sobre build web) | El harness "matriz rol×capacidad, read-only, exit code" de VITANOVA se replica |

Deep links `wa.me`/`tel:` vía `expo-linking` (la lógica `waLink()` +51 se copia literal; `window.open` → `Linking.openURL`). El patrón "abrir WhatsApp → al volver preguntar ¿Lograste contacto?" es INCLUSO más natural en móvil (AppState 'active').

---

## 3. Matriz de clasificación (punto 3 del encargo)

Cada pieza en exactamente una categoría. **Regla aplicada:** si es UI web (Radix/Tailwind-CSS/DOM) y el destino es RN, no puede ser TRANSFIERE.

### TRANSFIERE 1:1 (se copia sin cambios)

| Pieza | Fuente |
|---|---|
| CTE recursivo de jerarquía por `supervisor_id` (esqueleto de `asesor_ids_visibles`) | `migrations/20260614052437:79-137` |
| Patrón "RLS = seguridad, CAPS = UX" y la función `can()` con degradación a privilegio mínimo | `src/lib/roles.ts` |
| `validTransition` (adelante contiguo o retroceso; terminales protegidas) | `store.ts:357-364` |
| `waLink()` + normalización teléfono Perú (+51, 9 dígitos) = espejo del SQL `normalizar_telefono()` | `store.ts:668-673`, `format.ts` |
| Helpers de formato: `telE164`, `humanizarDuracion`, `iniciales`, `fmtFecha/fmtFechaHora` (testeados) | `src/lib/format.ts` |
| `colorFor(id)` hash determinista → color estable por vendedor/producto | `store.ts:97-102` |
| `search.ts` (puente buscador→pantalla, TS puro) y `leads-reparto.ts` (orden por urgencia, testeado) | `src/lib/` |
| Convención `ActionResult {ok, error, code}` + adaptadores fila-BD→shape-UI | `store.ts` |
| Disciplina de migraciones: timestamped + `MIGRACIONES.md` + bloque funcional→hardening→fix adversarial + `ALTER POLICY` en caliente | `supabase/migrations/` |
| Esqueleto del test de aislamiento SQL (impersonación por claims + iteración dinámica de tablas RLS + rollback) | `qa/aislamiento-tenant.sql` |
| Comparación HMAC en tiempo constante (webhooks de terceros) | `whatsapp-webhook/index.ts:10-20` |
| Idempotencia por sello en fila + índices únicos parciales de dedup vivo | migraciones varias |
| Librerías JS puras: date-fns, papaparse, cva, clsx, tailwind-merge | `package.json` |
| Metodología docs: `docs/plans/` + `docs/specs/` fechados | ambos repos ya la usan |

### ADAPTA (misma idea, distinto dominio o distinta plataforma — con el cambio descrito)

| Pieza | Cambio |
|---|---|
| RLS jerárquica completa | Quitar `clinica_id` (single-tenant); helper `private.vendedor_ids_visibles()`; añadir 4º nivel directorio (SELECT global, cero policies de escritura) |
| Hook JWT de claims | Inyectar `rol_crm` desde `crm.equipo` (no `clinica_id`) |
| Triggers de negocio (sellado 1ª respuesta, citas→timeline, cupos anti-TOCTOU, cambio de etapa con cohorte) | Renombrar dominio; cupos recalibrados a la fuerza de ventas real |
| Crons idempotentes (SLA 15 min, cadencias, recordatorios) | Añadir cron de **vencimientos de contrato** (renovaciones) — el caso estrella de Avance |
| Edge `admin-crear-usuario` | → `crm-crear-vendedor`: fusionar con las convenciones SUPERIORES del portal (CORS allowlist, dry_run, jsr:) + cuota + anti-escalación |
| Patrón dual-cliente (RLS autoriza + service_role solo secretos Vault, config `using(false)`) | Para toda integración del CRM |
| Webhook HMAC + intake de leads (Apps Script → RPC `crear_lead_entrante` con dedup y round-robin) | Fuente de leads de Avance (Meta Lead Ads / web); round-robin a supervisor de turno |
| AuthGate (máquina de fases, timeout, dedupe) | Fix: comparar `user.id` (no access_token) para no re-bootear al volver de background |
| Matriz CAPS | 4 roles (vendedor/supervisor/gerencia/directorio) + capacidad nueva `soloLecturaTotal` (el CAPS actual no expresa "no escribe NADA") |
| Modo auditoría por-registro | Extender a por-rol: directorio = TODO solo-lectura, incluso sin asignar |
| Cola "Tu siguiente acción hoy" (buckets + dedupe + foco) | Buckets re-mapeados: lead sin responder · seguimiento · SLA · propuesta sin respuesta · **contrato por vencer** · cliente caliente |
| SLA de 1ª respuesta + horario hábil Lima | Idéntico para leads de inversión |
| Cadencias 3-3-7-7 (como datos, dirigidas por eventos) | + cadencia de **renovación pre-vencimiento** |
| "¿Lograste contacto?" (gestion-provider) | `window.open` → `Linking.openURL`; prompt al volver por AppState |
| Kanban de pipeline | Etapas de inversión (p. ej. nuevo → contactado → reunión → propuesta enviada → contrato firmado); drag HTML5 → long-press "mover a etapa" |
| Cotizador → **constructor de propuesta de inversión** | Ítems = producto (Nuevo/Renovación/Upgrade) con monto/plazo/tasa (≤15 % anual)/moneda; fuera IGV salud; ciclo borrador→enviada→aceptada→vencida transfiere |
| Ficha 360° (hub de acciones + timeline + tabs) | Sheet lateral → stack screen / bottom-sheet RN |
| Calendario 3-fuentes + overlays | Cita→reunión/llamada; overlay cotización→**vencimiento de contrato/propuesta**; dnd-kit→gestos |
| Dashboard por variante de rol + KPIs con desglose | KPIs: capital captado, contratos firmados, renovaciones, vencimientos próximos; + variante directorio |
| Motor de reportes (dataset filtrado → 14 bloques) e inteligencia (insights accionables) | Cálculo movido a **RPCs/vistas SQL server-side**; export CSV/PDF vía expo-print/edge |
| Config 6 CRUDs solo-gerencia | líneas→productos de inversión; metas de captación; usuarios con cuotas |
| Import CSV con dry-run y dedup | → **RPC server-side por lotes** (no 500 requests desde el cliente); base para migrar la cartera |
| Notificaciones (tabla + RLS por usuario + realtime) | + push Expo (el cron que inserta también dispara edge→Expo Push) |
| `log-error.ts` (scrub PII/DNI, dedup TTL, fire-and-forget) | `window/location` → equivalentes RN; **cablearlo en la capa de datos**, no solo en boundaries |
| Tokens de diseño + escala tipográfica + chips tintados + micro-interacciones | Re-materializados en NativeWind con la paleta navy/azul; `color-mix 15%` → alpha hex `26`; animaciones → Reanimated |
| 27 componentes shadcn | Como **spec de API y medidas** para react-native-reusables |
| QA harness por rol (matriz rol×capacidad, aserciones simétricas, exit code) | Playwright DOM → Maestro (o Playwright sobre build web) |
| Seed per-tenant idempotente + `seed-users.mjs` + `test-rls.mjs` | Usuarios demo de los 4 roles CRM + roles del portal |
| Soft-delete | Unificar TODO en `activo=false` (VITANOVA mezcla `eliminado` y `activo`); replicar "sin policy DELETE" |
| Anonimización Ley 29733 | Adaptar sin destruir datos contractuales (los leads no convertidos sí son anonimizables; clientes con contrato NO) |

### DESCARTA (específico de salud, o deuda técnica)

| Pieza | Razón |
|---|---|
| Todo el multi-tenant: `clinica_id`, `clinicas.plan`, `provisionar_clinica`, cuotas por plan | Avance es una sola empresa |
| Dominio clínico: líneas de servicio médicas, citas consulta/cirugía, no-show, IGV exonerado por salud, scoring quirúrgico, consentimiento de datos de salud | No aplica a inversiones |
| Store singleton **boot-carga-todo** + full re-fetch + realtime tabla-completa + mutación in-place | No escala a 5,000/móvil (§1.8) — React Query en su lugar |
| Reportes/BI 100 % en cliente con `.limit()` que trunca en silencio | → RPCs server-side |
| Navegación por view-string + ternarios | → expo-router |
| Código UI web: Radix, Tailwind-CSS runtime, Recharts, dnd-kit, jsPDF, sonner web, react-day-picker, next-themes, cmdk, tw-animate-css, aurora de fondo | DOM-only |
| Dark mode + brand switch del topbar | El destino exige tema claro único navy (se conserva la ARQUITECTURA de tokens) |
| Todo el VERDE (success, ganado, teal, emerald, WhatsApp) | Prohibido por diseño |
| Hard-delete de citas (`eliminarCita`), delete+insert no atómico (`guardarPasos`), import fila-a-fila, `catch {}` vacíos, HTML en data layer, config hardcodeada, footgun `humanizarDuracion` sin fix global | Deuda verificada |
| `APLICAR-TODO.sql`, `_migraciones-locales-previas/`, `public_html/` legacy (React+Babel CDN), `_respaldo-vanilla/`, `qa-reportes.mjs`, simulador demo WhatsApp | Legado/superado |
| CORS `'*'` y verify-token con fallback hardcodeado | El portal ya tiene el patrón correcto (allowlist + Vault) |
| Drift "función desplegada sin fuente" (`intake-lead`) | Regla nueva: toda función desplegada tiene fuente versionada |
| Web Push VAPID como canal del CRM móvil | RN usa Expo Push (el Web Push del portal sigue para el portal) |

### FALTA (Avance lo necesita y VITANOVA no lo tiene)

| Pieza | Nota |
|---|---|
| **Rol directorio (4º nivel)**: solo-lectura GLOBAL por rol + policies SELECT dedicadas + cero escritura | La pieza de seguridad nueva más importante |
| **Nivel supervisor en Avance** (`crm.equipo` con `supervisor_id`) | El portal no tiene campo jerárquico alguno |
| **Dominio de inversiones**: `crm.leads`, `crm.actividades`, `crm.citas`, `crm.propuestas`, `crm.metas`, `crm.notificaciones` + FKs reales a `public.perfiles`/`public.contratos` | Modelado en P-055 |
| **Conversión lead→cliente transaccional** (edge que extiende `crear-cliente` v12: auth.users + perfil + contrato + cronograma + lead convertido, atómico) | Con índice UNIQUE parcial anti-duplicados |
| **Vista `crm.clientes_basicos`** (o column grants): identidad/contacto/estado, **JAMÁS columnas bancarias** | Condición del panel de decisión |
| **Post-venta / cartera viva**: vencimientos de contrato, pipeline de renovaciones/upgrades (usa `contratos.categoria` ya en prod), alertas pre-vencimiento | VITANOVA muere en "venta cerrada"; el primer vencimiento real de Avance muerde en oct-2026 |
| **Multimoneda PEN/USD** (formatos, KPIs, consolidación con tipo de cambio) | Todo VITANOVA hardcodea "S/" |
| **Push móvil** (expo-notifications + token registry + edge de envío) | Base: patrón `notificar-pagos` |
| **Paginación y búsqueda server-side** + FlashList | Nace paginado |
| **Persistencia offline / rehidratación** (React Query persist) | Vendedores en campo |
| **Plantillas WhatsApp `utility`** + chequeo ventana 24 h | El caso principal de Avance (empresa inicia); ni VITANOVA lo tiene |
| **Recuperación de contraseña en el CRM** | El portal ya la tiene; el CRM interno necesita al menos cambio forzado de temporal |
| **Auditoría de accesos** (quién vio qué) + export WORM del audit_log + **matriz de segregación de funciones rol×tabla×operación documentada** | Preparación SBS |
| **Pipeline EAS** (build, firma, stores, OTA) y QA móvil (Maestro) | Costo nuevo de la plataforma |
| **Refresco de rol en caliente** (desactivar un vendedor lo expulsa sin esperar re-login) | Hueco de VITANOVA |

---

## 4. Modelo de roles propuesto (cómo encajan portal y CRM)

Verificado contra la BD en vivo (`docs/recon/08`): `perfiles.rol` CHECK = `cliente|analista|admin|superadmin|directorio`; la fuerza comercial actual son los 18 **analistas** (con cartera vía `asesor_perfil_id` y auto-asignación al crear cliente).

**Propuesta: NO tocar el CHECK de `perfiles.rol`.** La jerarquía comercial vive en una tabla nueva:

```
crm.equipo (
  perfil_id     uuid PK → public.perfiles(id),
  rol_crm       text CHECK (vendedor|supervisor|gerencia),
  supervisor_id uuid → crm.equipo(perfil_id),   -- auto-FK, subárbol recursivo
  activo        boolean default true, ...
)
```

- **vendedor** ≈ el analista de hoy (mismo humano, enrolado en `crm.equipo`); **gerencia** ≈ admin; **directorio** ya existe en `perfiles.rol` y cierra la cúspide con su patrón RPC-only probado (el más seguro del portal). **supervisor** es el único nivel nuevo.
- Ventajas: ninguna policy ni el enrutamiento de `public_html/js/auth.js` del portal se ven afectados; la matriz de accesos CRM queda separada y documentable ante la SBS; la alternativa (ampliar el CHECK) queda registrada como plan B en `docs/recon/10`.
- `private.vendedor_ids_visibles(uid)` (CTE recursivo sobre `crm.equipo.supervisor_id`): gerencia ⇒ todos; supervisor ⇒ subárbol; vendedor ⇒ él; **directorio ⇒ rama SELECT global, excluido de toda escritura**.

## 5. Decisión arquitectónica (punto 4): MISMO proyecto Supabase

**Recomendación: el CRM vive en `dctqcbznekcyxhjujuci`, en un esquema `crm` dedicado. Panel de 3 lentes independientes (integridad de datos · seguridad/SBS · operación): unánime 3/3.** Posturas completas con argumentos, riesgos y condiciones en `docs/recon/10-decision-supabase-posturas.md`.

**Por qué:**
1. **Postgres no tiene FKs entre proyectos.** `crm.leads.perfil_id → public.perfiles(id)` y `crm.propuestas.contrato_id → public.contratos(id)` solo existen como constraints reales en el mismo proyecto; separados serían UUIDs copiados con huérfanos silenciosos.
2. **La conversión lead→cliente es intrínsecamente transaccional** — en un proyecto es UNA función atómica (extendiendo `crear-cliente` v12 ya en prod); en dos proyectos es una saga sin 2PC condenada a estados intermedios inconsistentes.
3. **Identidad única**: `perfiles.dni UNIQUE` resuelve por constraint el caso crítico (un vendedor capta como lead a alguien que YA es cliente); con dos proyectos solo se detectaría con jobs de sincronización.
4. **Para la SBS, un solo linaje de datos es MÁS defendible**: un `audit_log` único (el trigger genérico `log_audit_change` se cuelga tal cual sobre `crm.*`), un solo timeline de PITR, una sola matriz de accesos. Dos proyectos = dos logs sin correlación y la pregunta del auditor "¿cuál es la fuente de verdad?". La segregación de funciones que pide la SBS es **lógica** (roles, RLS, privilegios), no separación física.
5. **La escala no lo justifica**: 148 perfiles hoy, meta 5,000 — muy por debajo de los límites del plan Pro; separar duplicaría compute, PITR, secrets y monitoreo, y añadiría el sincronizador como el componente más frágil del sistema, operado por un equipo de facto de una persona.

**Riesgo principal asumido** (los 3 lentes coinciden): blast radius compartido — una migración CRM mal hecha puede afectar el portal EN PRODUCCIÓN, y una policy permisiva podría exponer columnas bancarias de `perfiles` a la fuerza de ventas. Por eso las condiciones de abajo **no son opcionales**.

**Condiciones no negociables (síntesis del panel):**
1. Esquema **`crm`** para toda tabla nueva; regla escrita: **ninguna migración del CRM altera tablas/triggers/policies de `public`** (la frontera por esquema mantiene la decisión reversible — plan de carve-out documentado).
2. Vendedores **NUNCA** leen `public.perfiles` crudo: vista/RPC `crm.clientes_basicos` sin columnas bancarias (banco, numero_cuenta, cci y espejos USD). RLS es por fila, no por columna — este es el hueco que hay que cerrar por diseño.
3. Toda migración: **branch de Supabase → aplicar → suite RLS (8-9 roles) → advisors → merge**. Prohibido `apply_migration` directo a prod.
4. RLS **deny-by-default** en `crm.*`; cero policies nuevas de vendedores sobre `contratos`, `cronograma_pagos`, `documentos`, `audit_log`. Quien vende no aprueba contratos ni registra pagos (segregación demostrable: la conversión la ejecuta una edge function con rol admin/analista).
5. Trigger `log_audit_change` sobre TODAS las tablas `crm.*` desde la primera migración; audit_log inmutable (revocar UPDATE/DELETE) + export WORM periódico.
6. **PITR activado y verificado ANTES de que el CRM escriba su primera fila**; la app móvil usa exclusivamente la publishable/anon key + RLS (service_role solo en edge functions).
7. Umbral definido: si algún día el CRM degrada al portal, primero read-replica/upgrade de cómputo del MISMO proyecto — no segundo proyecto.

## 6. Reconciliación con MD_AVANCE_CRM_F1.md (punto 5)

⚠️ **El archivo no se encontró** (disco completo, Drive, Notion, historial git de los 5 repos — búsqueda por nombre y por contenido). Se reconcilia contra la definición que el propio encargo da de F1 (jerarquía vendedor → supervisor → gerencia → directorio/auditoría) y los documentos internos existentes. **Si F1 aparece, esta sección se re-valida antes de P-055.**

**Lo que F1 pide y VITANOVA YA cubre (como patrón):**
- Jerarquía de niveles con scoping de datos → el CTE recursivo + RLS jerárquica cubre N niveles sin rediseño (§1.4). Cubre 3 de los 4 niveles funcionando en producción.
- Vendedor con cartera propia, supervisor con equipo, gerencia con todo → exactamente `asesor/supervisor/gerente` de VITANOVA; además reparto de leads con bandeja parkeada, metas por vendedor/mes, ranking, reportes por equipo, modo auditoría.
- Pipeline comercial, actividades/timeline, cotizaciones→propuestas, calendario, SLA, cadencias, notificaciones, configuración gerencial: todo existe y se ADAPTA de dominio.

**Lo que F1 pide y VITANOVA NO tiene (se construye — ver FALTA §3):**
- El 4º nivel **directorio/auditoría** como rol de solo-lectura global (VITANOVA solo tiene solo-lectura por-registro). Nota: el portal de Avance ya tiene el rol `directorio` con el patrón RPC-only — se extiende al CRM.
- El dominio inversiones completo (leads de inversión, propuestas con monto/plazo/tasa/moneda, conversión a contrato, post-venta/renovaciones).

**Lo que el portal de Avance ya aporta a F1** (no partir de cero): roles y auth en producción, `crear-cliente` v12 con auto-asignación de asesor, `contratos.categoria` (nuevo/renovación/upgrade) implementada, audit_log genérico + Realtime, push/notificaciones (`notificar-pagos`), clave temporal = DNI, convención español snake_case + soft-delete + nombres en MAYÚSCULA + fechas America/Lima.

## 7. Restricciones de diseño (punto 8 — no negociables, aplicadas)

- **Paleta**: navy `#111e3d` primario · azul `#2563eb` acento · fondo blanco puro · tema claro único (sin dark mode, sin brand switch) · **SIN verde en ningún estado** — "éxito/ganado" se re-mapea a azul acento; el semáforo SLA usa azul/ámbar/rojo. La paleta categórica de charts se rehace completa (navy para UI; series con #2563eb + secundarios; validar contraste AA).
- **Tipografía**: Plus Jakarta Sans (vía @expo-google-fonts, empaquetada), escala heredada de VITANOVA (KPI 2xl extrabold tabular-nums, montos tabulares).
- **Naming**: español, snake_case en BD, RPCs, edges y mensajes (VITANOVA y el portal ya cumplen — se mantiene).
- **Soft-delete**: `activo = false` en TODO; sin policy DELETE en tablas de clientes/leads; hard-delete solo superadmin y solo sin historial (patrón ya semi-institucionalizado en `eliminar-cliente` del portal).

## 8. Árbol de carpetas (punto 6 — creado en este P-054, sin lógica de negocio)

```
CRM-Avance-Corp/
├── README.md                        ← qué es esto y de dónde viene
├── PLAN-CRM-AVANCE-CORP.md          ← este documento
├── docs/
│   ├── recon/                       ← 10 anexos del reconocimiento (informes con citas archivo:línea)
│   ├── plans/                       ← planes fechados AAAA-MM-DD-tema.md (metodología existente)
│   └── specs/                       ← specs de diseño fechados
├── app/                             ← la app Expo universal se scaffoldea AQUÍ en P-055
│   └── LEEME.md                     ← estructura interna propuesta (expo-router por grupos de rol)
├── supabase/
│   ├── migrations/                  ← migraciones del esquema crm (timestamped + MIGRACIONES.md)
│   ├── functions/                   ← edge functions crm-* (toda función desplegada tiene fuente aquí)
│   └── scripts/                     ← test-rls.mjs (4 roles CRM + 5 del portal), seed de demo
└── qa/                              ← harness por rol (Maestro/build web) + aislamiento-jerarquia.sql
```

## 9. Fases de construcción (cada una termina con visto bueno de Miguel)

| Fase | Qué se construye | Piezas de VITANOVA que usa |
|---|---|---|
| **F0 — Cimientos BD** (branch + merge) | Esquema `crm`; `crm.equipo` (jerarquía 4 niveles); `crm.leads` + `crm.actividades` con FKs a `perfiles`; helpers `private.vendedor_ids_visibles`; RLS deny-by-default + policies jerárquicas + directorio SELECT-only; vista `crm.clientes_basicos`; audit triggers; suite `test-rls` como gate; seed demo | CTE recursivo, policies transcritas, hardening, test-rls, aislamiento SQL |
| **F1 — App esqueleto + captación** | Scaffold Expo universal (copiar config Belysh); tema navy/Plus Jakarta (NativeWind tokens); design system base (react-native-reusables re-pintado); auth (login, clave temporal, AuthGate corregido); tabs por rol; alta de lead + pipeline kanban (long-press) + cartera paginada (FlashList + React Query) | AuthGate, CAPS/can, ETAPAS/validTransition, spec de componentes, nuevo-prospecto |
| **F2 — Gestión diaria** | Dashboard por rol con cola "Tu siguiente acción hoy"; "¿Lograste contacto?" (wa.me/tel + registro); calendario de reuniones con overlays; bandeja de reparto (supervisor de turno, round-robin); notificaciones in-app + push Expo | bucketsAccionables, gestion-provider, calendario, leads-nuevos, SLA + crons |
| **F3 — Propuestas y conversión** | Constructor de propuesta de inversión (producto Nuevo/Renovación/Upgrade, monto/plazo/tasa/moneda); ciclo de estados + vencimiento; PDF server-side; **edge transaccional lead→cliente** (extiende crear-cliente); dedup contra `perfiles.dni` | cotizador, correlativo atómico, trg_cotizacion, crear-cliente v12 del portal |
| **F4 — Post-venta y dirección** | Cartera viva: vencimientos de contrato, cadencias de renovación, pipeline de upgrades; reportes/BI por RPCs server-side; metas; variante directorio (solo-lectura global); export CSV/PDF | cadencias 3-3-7-7, motor de reportes (como spec), insights, metas, RPCs directorio del portal |
| **F5 — Integraciones y salida a producción** | WhatsApp Cloud API con **plantillas utility** + ventana 24 h (lo que ni VITANOVA terminó); intake de leads externos; import masivo server-side; QA Maestro por rol; hardening final + advisors; EAS production + OTA; matriz de segregación documentada (SBS) | whatsapp-enviar/webhook (dual-cliente, HMAC, Vault), intake, import CSV, QA harness |

**Fuera de alcance de todas las fases:** tocar el código del portal (`public_html/`), modificar tablas/policies de `public`, y cualquier escritura en el repo de Clínica Álvarez.

## 10. Riesgos principales

1. **Blast radius compartido** (asumido por decisión §5) → mitigado por las 7 condiciones; la que más protege: branch + suite RLS como gate.
2. **NativeWind v5 aún en RC al kickoff** → plan B sin impacto arquitectónico (NativeWind 4.2 + Tailwind 3).
3. **Verificación de Meta Business (RUC/SUNAT) tarda 2–6 semanas** → iniciar el trámite en F2 aunque WhatsApp se integre en F5; mientras, deep links wa.me (sin API) ya funcionan desde F2.
4. **Primer vencimiento real de contratos en oct-2026** — el ciclo vencido/renovado del portal aún no tiene flujo; F4 debe llegar antes, o el CRM nace sin su caso estrella (renovaciones).
5. **iOS**: vendedores mayormente Android; cuenta Apple Developer solo si se necesita iOS en producción (EAS preview interno puede bastar al inicio).

---

## Procedencia y verificación

- Reconocimiento ejecutado el 2026-07-09 con un workflow de 12 agentes (9 inventarios + 3 posturas), 1.03 M tokens, 301 lecturas de herramienta. Informes completos en `docs/recon/`.
- El repositorio de Clínica Álvarez y el código del portal de Avance Corp se trataron como **READ-ONLY**: cero archivos modificados, creados o borrados fuera de `CRM-Avance-Corp/`.
- Datos de producción citados (conteos de filas, policies, CHECK constraints) verificados en vivo contra `dctqcbznekcyxhjujuci` con SQL de solo lectura.
