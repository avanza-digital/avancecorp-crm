# CLAUDE.md — Memoria del Proyecto

> **Léeme primero en cada sesión.** Soy la memoria permanente de este proyecto: decisiones, patrones, lecciones y reglas. Documento lo que el **código realmente hace**, no lo que dicen documentos externos. Si encuentras una diferencia entre este archivo y el código, gana el código — y actualízame.

---

## 1. IDENTIDAD DEL PROYECTO

- **Nombre:** Portal Digital de Inversiones — Avance Corp S.A.C.
- **Empresa:** Avance Corp S.A.C. · RUC 20611392088 · San Isidro, Lima, Perú
- **Holding:** MasCapital
- **Dominio:** miavance.com
- **Supabase project ref:** `dctqcbznekcyxhjujuci`
- **Propietario técnico:** Miguel Briceño (analista comercial, **no desarrollador**)
- **Correo de envío:** info@miavance.com (verificado en Resend)
- **Raíz del proyecto / deploy:** `public_html/` → se sube **manualmente** a Hostinger.

---

## 2. STACK TÉCNICO

- **Frontend:** HTML5 + CSS3 + **JavaScript vanilla (ES Modules)**. Sin framework, sin build step.
- **Tipografía:** Plus Jakarta Sans (definida en `dashboard-v4.css`).
- **Backend:** Supabase Pro — PostgreSQL + Auth + Storage + Edge Functions (Deno).
- **SDK:** `@supabase/supabase-js@2` desde `https://esm.sh` (NO jsdelivr — generaba 404s por su header `Link:`, ver `js/supabase.js`).
- **Emails:** Resend (dominio miavance.com verificado).
- **Push:** Web Push con VAPID (claves en Supabase Secrets).
- **Tiempo real:** Supabase Realtime (`postgres_changes`) — badge de comunicados en vivo (sube al llegar uno nuevo, baja al marcar leído en otra pestaña/dispositivo). Tablas `novedades` y `novedades_leidas` en la publicación `supabase_realtime`; la RLS filtra los eventos por usuario.
- **Gráficos:** SVG vanilla custom (`premium-chart.js`, `premium-donut.js`). *(Chart.js mencionado históricamente; el código actual usa SVG propio.)*
- **Mercados:** TradingView Widgets (ticker-tape).
- **Hosting:** Hostinger Business · **SSL:** Let's Encrypt.
- **PWA:** `manifest.json` + `service-worker.js` + prompts de instalación.
- **Excel:** SheetJS (XLSX) cargado **lazy** desde CDN solo al importar/exportar pagos.

---

## 3. ESTRUCTURA DE ARCHIVOS

### Páginas HTML — cliente (`public_html/`)
- `index.html` — login / welcome / recuperar contraseña.
- `reset-password.html` — crear nueva contraseña tras recuperación.
- `dashboard.html` — dashboard del cliente (resumen, contratos, rendimientos).
- `inversion.html` — detalle de un contrato + cronograma.
- `documentos.html` — repositorio de documentos del cliente (descarga).
- `mercados.html` — mercados en vivo (TradingView).
- `beneficios.html` — programa de beneficios / aliados (carrusel).
- `perfil.html` — datos personales, cambio de clave, push, instalar app.
- `novedades.html` — comunicados dirigidos al cliente.

### Páginas HTML — admin (`public_html/admin/`)
- `dashboard.html` — métricas + contratos por vencer + actividad.
- `clientes.html` — CRUD clientes, búsqueda, paginación, activar/desactivar, **eliminar (superadmin)**.
- `asesores.html` — CRUD de asesores.
- `contratos.html` — contratos + generación automática de cronograma.
- `pagos.html` — registro/seguimiento de pagos por contrato, import/export Excel.
- `documentos.html` — carga de PDFs a Storage.
- `novedades.html` — envío de comunicados (individual/masivo).

### CSS (`public_html/css/`)
- `main.css` — sistema de diseño global (tokens, reset, paleta navy+gold).
- `dashboard.css` — layout del portal (nav, header, content).
- `dashboard-v4.css` — cards, charts, donut, hero, grillas (tokens `--v4-*`).
- `animations.css` — keyframes (ticker, shimmer, pulses).
- `admin.css` — elementos densos del panel admin.
- `mobile.css` — responsive (`max-width: 768px` / `480px`).

### JS principales (`public_html/js/`)
- `supabase.js` — cliente Supabase (storage adaptable, `resilientFetch` con retry).
- `auth.js` — login, logout, verificarSesion/verificarAdmin, roles, SW, bfcache.
- `login.js` — UI del login (welcome→login→recover→sent), validación inline.
- `dashboard.js` · `inversion.js` · `documentos.js` · `perfil.js` · `novedades.js` · `mercados.js` · `beneficios.js` — orquestadores de cada pantalla cliente.
- `reset-password.js` — flujo de reset (valida enlace, updateUser, signOut).
- `mobile-menu.js` — drawer mobile (cliente+admin), `initMobileMenu()`.
- `inactivity.js` — timer de inactividad (4 min cliente / 5 min admin).
- `no-zoom.js` — bloquea pinch/ctrl-wheel/double-tap zoom.
- `novedades-utils.js` — utilidades compartidas de comunicados (no leídas, marcar leída) **+ tiempo real** (`suscribirseNovedades`, `iniciarBadgeNoLeidasRealtime`: suscribe a `novedades`/`novedades_leidas` y repinta el badge en vivo, debounce 250 ms).

### JS admin (`public_html/js/admin/`)
- `_helpers.js` — **utilidades compartidas del panel** (ver §6).
- `dashboard.js` · `clientes.js` · `asesores.js` · `contratos.js` · `pagos.js` · `documentos.js` · `novedades.js` — cada pantalla admin.

### Componentes (`public_html/js/components/`)
- `premium-chart.js` — gráfico SVG de evolución del capital.
- `premium-donut.js` — donut animado de avance (%).
- `crono-timeline.js` — timeline vertical del cronograma.
- `ticker.js` — banda TradingView.
- `push-manager.js` — suscripciones push (VAPID, guarda en BD).
- `install-prompt.js` · `install-fab.js` · `ios-install-hint.js` — instalación PWA (Android/Chrome, universal, hint iOS).

### Utils (`public_html/js/utils/`)
- `scroll-lock.js` — body scroll lock iOS-safe (position:fixed, refcount).

### Edge Functions (`_supabase_functions/functions/`)
- `crear-cliente` · `crear-admin` · `resetear-password` · `enviar-comunicado` · `enviar-push` · `eliminar-cliente` (ver §8).

### Assets (`public_html/img/`)
- Iconos PWA (192/512, maskable), `apple-touch-icon`, `favicon-32`, `avance-logo-full`, `avance-icon`.
- `img/aliados/` — logos: belysh, mascapital, ntc-agency, phoenix, qorilazo.

### Otros (raíz)
- `manifest.json` — PWA (display standalone).
- `service-worker.js` — network-first HTML · stale-while-revalidate CSS/JS · cache-first IMG.
- `.htaccess` — HTTPS forzado, headers de cache/seguridad (HSTS, CSP), gzip.

---

## 4. ESQUEMA DE BASE DE DATOS (9 tablas, schema `public`)

- **`perfiles`** — usuarios. `id, nombre_completo, dni, telefono, correo, rol('cliente'|'admin'|'superadmin'), activo, asesor_id, creado_por, pwa_instalada_at, banco, numero_cuenta, tipo_cuenta, cci, creado_en, actualizado_en`. *(No hay FK a `auth.users` — comparten UUID por convención.)*
- **`asesores`** — vendedores asignables a clientes (NO son usuarios de login). `id, nombre_completo, correo, telefono, whatsapp, cargo, activo, …`.
- **`contratos`** — `id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, estado, notas_internas, creado_por, …`.
- **`cronograma_pagos`** — cuotas de cada contrato. `id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado, fecha_pago_real, monto_pagado, tipo, registrado_por, …`.
- **`documentos`** — `id, contrato_id, nombre, tipo, storage_path, subido_por, creado_en`.
- **`novedades`** — comunicados. `id, titulo, mensaje, destinatario_id (null = broadcast), leido, enviado_por, imagen_url, creado_en`.
- **`novedades_leidas`** — acuses de lectura. `id, novedad_id, usuario_id, leido_en`.
- **`suscripciones_push`** — `id, cliente_id, endpoint, p256dh, auth, dispositivo, user_agent, activo, …`.
- **`audit_log`** — auditoría. `id, tabla, operacion, fila_id, usuario_id, ts, data_antes, data_despues`.

**Cascadas al borrar un cliente:** `contratos.cliente_id` = RESTRICT (bloquea), `novedades.destinatario_id` = NO ACTION, `novedades_leidas` + `suscripciones_push` = CASCADE, `audit_log` = SET NULL.

> ⚠️ **No existe** la tabla `sesiones_log`. El registro de auditoría es `audit_log`; la inactividad se maneja en cliente (`inactivity.js`).

### RPCs (funciones Postgres en uso)
- `dashboard_admin_metricas()` → jsonb — métricas del dashboard admin.
- `admin_pagos_resumen()` · `admin_pagos_metricas()` → jsonb — resumen/métricas de pagos.
- `pagos_admin_resumen_contratos(p_tab, p_busqueda, p_moneda, p_offset, p_limit)` → record — **paginación server-side** de pagos por contrato.
- `pagos_admin_metricas_globales()` → jsonb — métricas globales de pagos.
- Helpers de RLS (usados dentro de las políticas): `es_admin()` · `es_superadmin()` → boolean · `mi_rol()` → text.
- **Triggers:** `set_actualizado_en()` (autocompleta `actualizado_en`) · `log_audit_change()` (escribe en `audit_log`).
- **Extensión `pg_trgm`** habilitada → índices GIN trigram para el buscador (ILIKE eficiente en nombre/dni/correo/n° contrato).

### RLS (Row Level Security)
- **RLS activo en las 9 tablas.** Modelo: el **cliente** solo ve/edita lo suyo (su perfil; sus `contratos`/`cronograma_pagos`/`documentos` por `cliente_id`/`contrato_id`; `novedades` dirigidas a él o broadcast; sus `suscripciones_push` y acuses). **admin/superadmin** gestionan vía `es_admin()`/`es_superadmin()`. `audit_log` es **solo lectura** (admin).
- **Escalada de roles cerrada (auditoría 2026-05-24):** crear o cambiar un `rol` ≠ `'cliente'` en `perfiles` exige `es_superadmin()` (un admin ya **no** puede auto-promoverse). Policies `perfiles_update` y `admin_crea_perfiles` endurecidas.
- **Mutaciones privilegiadas** (crear/eliminar usuarios, resetear contraseña, enviar comunicados/push) NO pasan por RLS de cliente: van por **Edge Functions con `service_role`** (que omite RLS y revalida rol en código).

### Storage (buckets)
- **`documentos`** — privado. Acceso siempre por `createSignedUrl(path, 3600)` (1 h). Path: `{contrato_id}/{timestamp}_{nombre}`. **Límite 10 MB, solo `application/pdf`** (auditoría 2026-05-24).
- **`comunicados`** — público. Imágenes adjuntas a `novedades` (`imagen_url`). **Límite 5 MB, solo `image/*`** (auditoría 2026-05-24).

### Realtime (Supabase)
- Publicación `supabase_realtime` incluye `novedades` (INSERT → comunicado nuevo) y `novedades_leidas` (INSERT → acuse de lectura propio). El cliente se suscribe con su **JWT**, así que la **RLS SELECT filtra los eventos por usuario** (sin fuga; `postgres_changes` hace un chequeo RLS por suscriptor en cada evento). El front **solo escucha INSERT**. Lógica centralizada en `js/novedades-utils.js`. Reversible con `alter publication supabase_realtime drop table …`.

---

## 5. PALETA Y DISEÑO

**`main.css` (`:root`):**
- Navy: `--navy #1a2f5a` · `--navy-dark #111e3d` · `--navy-mid #243a6e` · `--navy-soft #2b3d6b`
- Gold: `--gold #c8922a` · `--gold-light #f0c060` · `--gold-pale #fdf3e0`
- Fondos/bordes: `--bg #f0f2f7` · `--surface #fff` · `--surface-soft #f7f8fc` · `--border #e2e6f0` · `--border-strong #c8d0e0`
- Texto: `--text-primary #111827` · `--text-secondary #5a6480` · `--text-muted #6b7280`
- Estado: `--green #0f9b6e`/`--green-bg #e8f7f2` · `--red #d63b3b`/`--red-bg #fdeaea` · `--warn #c8922a`/`--warn-bg #fdf3e0` · `--info #3b5bdb`/`--info-bg #eef2fc`
- Radios: `--radius 14px` · `--radius-sm 8px` · `--radius-pill 20px`
- Sombras: `--shadow-sm/md/lg` · Transiciones: `--t-fast .12s` · `--t .2s` · `--t-slow .4s cubic-bezier`

**`dashboard-v4.css` (`:root`, prefijo `--v4-`):**
- `--v4-navy #111e3d` · `--v4-navy-2 #1a2f5a` · `--v4-navy-deep #0c1530`
- `--v4-gold #c8922a` · `--v4-gold-light #f0c060` · `--v4-gold-text #8e6418` *(pasa WCAG AA sobre blanco)*
- `--v4-text #111e3d` · `--v4-body #5a6480` · `--v4-muted #6b7280`
- `--v4-border #e8ebf2` · `--v4-border-soft #eef0f7` · `--v4-bg #fafbfd` · `--v4-surface #fff`
- `--v4-radius-card 18px` · `--v4-radius-pill 100px` · `--v4-shadow-card` / `--v4-shadow-card-hover`

> ⚠️ `main.css` fuerza `color: navy` global en `h1–h3`. En heros navy hay que setear `color:#fff` explícito o el texto desaparece.

---

## 6. PATRONES DE CÓDIGO OBLIGATORIOS

- **Imports + cache-busting:** imports relativos con `?v=N` **manual por módulo** (no hay versión central). Ej. `auth.js?v=15`, `_helpers.js?v=2`, `mobile-menu.js?v=7`. `supabase.js` se importa **sin** `?v=` (módulo base). **Al editar un módulo crítico, sube su `?v=N` en TODOS los HTML que lo cargan.**
- **Inicialización:** páginas cliente usan `async function inicializar()` + llamada al final; páginas admin usan **IIFE** `;(async () => { … })()`. *(No hay logs `▶ ✓ ✗`; solo `dashboard.js` define `const TAG='[dashboard]'` para `console.error/warn`.)*
- **Aislamiento por bloque:** en el dashboard cliente cada render va en su propio `try/catch` para que un fallo no tumbe la página. En admin, `recargar()` hace `Promise.all` con un `try/catch` global + `mostrarError`.
- **Helpers (`js/admin/_helpers.js`, exportados):** `formatearMoneda(monto, moneda)`, `formatearNumero`, `simbolo`, `formatearFecha` *(parsea `YYYY-MM-DD` como fecha LOCAL para evitar el bug UTC-5)*, `fechaLargaHoy`, `escapeHtml`, `iniciales`, `setText`, `capitalizar`, `diasEntre`, `normalizarTelefonoPE`, `waLink`, `mostrarError`, `mostrarExito`, `quitarSkeletons`, y el setup unificado **`setupAdminShell(opts)`** (carga perfil, puebla header, engancha logout, scroll-lock de modales, dropdown del avatar).
- **Auth:** storage **adaptable** (`localStorage` si flag `av-remember-me==='true'`, si no `sessionStorage`). `verificarSesion()`/`verificarAdmin()` **redirigen internamente** y retornan `null`/`perfil` (los callers hacen `if (!x) return`). `logout()` hace `signOut({scope:'global'})` + limpieza defensiva de claves `sb-*`. Todo redirect de auth usa **`window.location.replace()`**. `onAuthStateChange` global redirige a `/index.html` en `SIGNED_OUT`.
- **Queries:** paginación **server-side** (`range`, `PAGE_SIZE=50`) + `count:'exact'` + **`AbortController`/`abortSignal`** (cancela queries en vuelo del buscador con debounce 300ms). Conteos con `head:true`. Sanitiza búsquedas con `escaparLike()` (escapa `\ % _ , ( )`) antes de `.or(...ilike...)`. Carga **lazy + cache en `Map`** (ej. cronograma por contrato).
- **Render:** template strings + `.map().join('')` + `innerHTML`, **siempre** pasando valores por `escapeHtml()`. Binding por **event delegation con `data-action`** (listener en el contenedor + `closest('[data-action]')`); algunas pantallas re-bindean tras cada `innerHTML`.
- **Feedback:** `mostrarError()` escribe en `#errorAlert` y **NO se auto-oculta**. `mostrarExito()` escribe en `#successAlert` y **se auto-oculta a 4000 ms**. Skeletons (clase `.skeleton`) en la carga; en botones se usa `disabled` + cambio de texto ("Guardando…") restaurado en `finally`.
- **Uploads (`js/admin/documentos.js`):** `<form>` con submit (**no hay drag-drop**). Valida `type==='application/pdf'` y tamaño ≤ 10 MB; sanitiza nombre `replace(/[^a-zA-Z0-9._-]/g,'_')`; sube a bucket `documentos` en path **`{contrato_id}/{timestamp}_{nombre}`**; si el insert en tabla falla, borra el archivo huérfano (rollback). Descarga vía `createSignedUrl(path, 3600)`.
- **Edge Functions:** Deno · CORS por allowlist (miavance.com) con manejo de `OPTIONS` · valida `Authorization: Bearer` con `auth.getUser(token)` · verifica rol en `perfiles` · usa `service_role` para mutaciones privilegiadas · rollback si un paso falla · helper `json(cors, payload, status)`.
- **Mobile nav (`mobile-menu.js`):** `initMobileMenu()` (guard `window.__mobileMenuInit`), detecta scope por `location.pathname.startsWith('/admin/')`, construye overlay+panel dinámicamente, scroll-lock iOS-safe.
- **Guards idempotentes:** flags `window.__*` (`__mobileMenuInit`, `__bfcacheGuardInstalled`, `__cerrandoPorInactividad`, etc.) para no duplicar listeners.

---

## 7. ANTI-PATRONES (NO REPETIR)

- **Queries a columnas inexistentes** (ej. `asesor_nombre`, `asesor_telefono`): el asesor vive en la tabla `asesores` (`nombre_completo`, `telefono`, `whatsapp`); `perfiles.asesor_id` es la FK. Resolver el nombre por join/map, nunca asumir columnas.
- **Self-INSERT del cliente bloqueado por RLS:** el cliente NO puede auto-registrarse; la creación va por la edge function `crear-cliente` con `service_role`.
- **ID mismatch HTML↔JS** (`sidebarToggle` vs `menuToggle`): dejó el botón hamburguesa inerte. El id correcto es `#menuToggle`.
- **Editar un módulo sin subir su `?v=N`:** el navegador/SW sirve la versión vieja cacheada.
- **`innerHTML` sin `escapeHtml`:** XSS. Todo dato de usuario pasa por `escapeHtml()`.
- **Bindear `onclick` por elemento o re-bindear sin delegation:** se pierden/duplican handlers al re-renderizar. Usar `data-action` + delegation.
- **Animar acordeones con `display:none/block`:** no anima. Usar `max-height` (+ opacity).
- **Duplicar helpers en cliente:** `dashboard.js`/`documentos.js` re-definen `formatearFecha` localmente **sin** el fix UTC → riesgo de fecha corrida 1 día. Preferir importar de `_helpers.js`.

---

## 8. EDGE FUNCTIONS

Deploy: `supabase functions deploy <nombre> --project-ref dctqcbznekcyxhjujuci` (o vía MCP de Supabase). Secrets disponibles: `RESEND_API_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` (+ `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` automáticos).

| Función | Qué hace | Secrets |
|---|---|---|
| `crear-cliente` | Crea usuario Auth + perfil (rol cliente) + email de bienvenida | RESEND_API_KEY |
| `crear-admin` | Crea usuario Auth + perfil (rol admin). **Solo superadmin** | — |
| `resetear-password` | Admin resetea la contraseña de un usuario | — |
| `eliminar-cliente` | Borra perfil + usuario Auth de un cliente. **Solo superadmin; bloquea si tiene contratos** | — |
| `enviar-comunicado` | Crea novedad + email (Resend) + aviso WhatsApp al asesor | RESEND_API_KEY |
| `enviar-push` | Envía Web Push a suscripciones activas (VAPID) | VAPID_* |

> ⚠️ `diagnostico-push` está **desplegada en Supabase** pero no tiene fuente versionada en `_supabase_functions/`. Hay copias de funciones también en `_DEV_NO_SUBIR/supabase/functions/` (mantener `_supabase_functions/` como fuente de verdad).

---

## 9. REGLAS DE TRABAJO CON MIGUEL

- Miguel **no es desarrollador** (analista comercial). Explica en **lenguaje natural**, sin jerga.
- **Cambios de BD:** muestra el **SQL primero** y espera confirmación antes de ejecutar.
- **No interrumpas** con preguntas que puedas resolver leyendo el código.
- Lo **visual** (cómo se ve en pantalla) decláralo explícito para que Miguel lo pruebe; las **capturas** son el input principal de debugging.
- **Máximo 3 intentos** automáticos; si sigue fallando, escala con explicación clara.
- Los prompts/instrucciones deben ser **copy-paste listos**, directos, sin relleno.
- **Audita y autoevalúa cada cambio** (checks concretos contra el sistema real) — el portal es público, cero errores.
- **Deploy:** los archivos van **manualmente** a Hostinger; mantener sincronizada la carpeta de subida.

---

## 10. ESTADO ACTUAL Y PENDIENTES

**Completo y funcionando:**
- Auth completo (login, roles, inactividad, reset password, storage adaptable).
- Portal cliente: dashboard (charts SVG, cronograma, novedades), inversión, documentos (descarga), mercados, beneficios, perfil (cambio de clave, push, instalar PWA), novedades.
- Panel admin: clientes (CRUD + paginación + **eliminar superadmin**), asesores, contratos (+ cronograma automático, **interés simple y compuesto**), pagos (registro + import/export Excel con validación), documentos (upload), novedades (envío), dashboard de métricas.
- **Interés compuesto** implementado (capitaliza anual, años exactos, pago único al vencimiento) — admin genera cronograma de 1 cuota + proyección año a año; cliente ve la curva compuesta. Ver [[project_interes_compuesto]].
- **Sincronización en vivo (Realtime):** el badge de comunicados sube/baja solo en todas las pantallas abiertas (comunicado nuevo / lectura en otra pestaña), sin recargar.
- Edge functions desplegadas · PWA (manifest, SW, push, prompts) · Emails Resend.

**Parcial / pendiente:**
- **Beneficios:** aliados en estado "Convenio en negociación" (placeholder); CTA "Hablar con mi asesor" → `/perfil.html` (no hay deep-link a WhatsApp aún).
- **WhatsApp Cloud API** diferida (hoy aviso manual/`wa.me`).
- **CSP** corregida (dominios `esm.sh`/`sheetjs`) pero en **Report-Only**: activar el bloqueo (enforcing) tras confirmar que no hay violaciones en producción.
- **Sincronización entre pestañas al marcar leído:** solo hay Realtime de INSERT; no se sincroniza un "marcar leído" salvo que llegue un comunicado nuevo (no queda número inflado de forma permanente).
- Tests Playwright existen en `_DEV_NO_SUBIR` pero no en CI.

**Bugs conocidos / resueltos:**
- Fechas UTC: `new Date("YYYY-MM-DD")` corre 1 día en Perú (UTC-5). Parcheado en `_helpers.formatearFecha` y, tras la auditoría 2026-05-24, **también en el cliente** (`dashboard.js`, `inversion.js`, `documentos.js`, `crono-timeline.js`). Ver [[project_bug_fechas_utc]].
- `dashboard.js`: el listener de la lista de documentos se migró a delegación idempotente (`bindDocsDescarga`) — ya no acumula handlers.

---

## 11. CREDENCIALES Y CONFIGURACIÓN

- **Supabase URL:** https://dctqcbznekcyxhjujuci.supabase.co
- **Dominio:** miavance.com · **Email envío:** info@miavance.com (Resend)
- **Secrets en Supabase** (solo nombres): `RESEND_API_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`.
- **Credenciales de prueba** (cliente/admin): NO van aquí — viven en el gestor de contraseñas de Miguel.
- **NUNCA** escribir API keys, service_role ni contraseñas en este archivo ni en el repo.
- ⚠️ **No subir este `CLAUDE.md` al hosting** (expone arquitectura y nombres de secrets). Es local; la carpeta de subida a Hostinger no debe incluirlo.

---

## 12. HISTORIAL DE DECISIONES IMPORTANTES

- **Vanilla JS, no React:** sin build step → deploy de archivos estáticos directo a Hostinger; Miguel (no-dev) puede mantenerlo; carga rápida y simple.
- **Supabase, no Firebase:** datos relacionales (contratos↔cronogramas↔pagos), SQL + RLS, y Auth/Storage/Edge Functions integrados en un solo proveedor.
- **PWA, no app nativa:** instalable en iOS/Android sin tiendas, push web, un solo código, despliegue inmediato.
- **Resend para emails:** dominio propio verificado, API simple, buena entregabilidad.
- **Storage adaptable (no solo localStorage):** "recuérdame" → sesión persistente; si no, `sessionStorage` efímero (más seguro en equipos compartidos).
- **Event delegation en mobile nav:** el menú se reconstruye dinámicamente; delegar evita perder handlers tras re-render.
- **Skeletons, no spinners:** sensación de velocidad y layout estable mientras cargan los datos.
- **RLS desde el día 1:** datos financieros sensibles; cada cliente solo ve lo suyo aunque el frontend falle. Mutaciones privilegiadas pasan por Edge Functions con `service_role`.
- **Realtime sobre la RLS (no broadcast manual):** el badge en vivo usa `postgres_changes`, que ya corre la RLS de cada tabla por suscriptor → no hay que reimplementar permisos ni exponer datos; un solo canal por página, conteo siempre recalculado desde la BD (idempotente).
- **CSP en Report-Only primero:** se corrigen dominios y se observan violaciones reales en producción antes de activar el bloqueo, para no romper el login por un dominio olvidado.

---

## 13. VERSIONES DE MÓDULOS (`?v=N`)

Cache-busting **manual por módulo**. Al editar un archivo, **sube su `?v=N` en TODOS los HTML/JS que lo importan**. Versiones vigentes (auditadas 2026-05-24):

- **CSS:** `main v12` · `dashboard v12` · `dashboard-v4 v19` · `animations v5` · `admin v17` · `mobile v7`
- **JS cliente (`js/`):** `auth v15` · `supabase` (sin `?v`) · `login v17` · `dashboard v23` · `inversion v19` · `documentos v14` · `perfil v10` · `novedades v14` · `mercados v15` · `beneficios v4` · `reset-password v1` · `mobile-menu v8` · `inactivity v2` · `no-zoom v2` · `novedades-utils v5`
- **JS admin (`js/admin/`):** `_helpers v2` · `dashboard v12` · `clientes v20` · `asesores v6` · `contratos v19` · `pagos v19` · `documentos v12` · `novedades v16`
- **Componentes/utils:** `premium-chart v4` · `premium-donut v2` · `crono-timeline v3` · `ticker v2` · `push-manager v9` · `install-prompt v4` · `install-fab v2` · `ios-install-hint v3` · `scroll-lock v3`
- **Service Worker:** `CACHE_VERSION = avance-v61`

> ⚠️ `dashboard.js`, `documentos.js` y `novedades.js` existen **dos veces** (cliente en `js/` y admin en `js/admin/`) — son archivos distintos con versiones independientes. No confundir. (`auth.js` es uniforme v15; la mención a `auth.js?v=7` en `mobile-menu.js:210` es un **comentario** sobre un bug viejo, no un import.)

---

## 14. DEPLOY

**Frontend (Hostinger, manual):**
1. Edita el archivo → **sube su `?v=N`** en cada HTML/JS que lo carga (ver §13).
2. Copia los archivos cambiados a la carpeta espejo de subida `~/Desktop/UPLOAD-HOSTINGER-public_html/` (réplica de `public_html/`).
3. Sube esa carpeta a `public_html` en Hostinger (File Manager / FTP).
4. **NO subir:** `_*` (dev/backups), `.gitignore`, `.DS_Store`, artifacts, **ni `CLAUDE.md`** (§11).
5. Verifica en incógnito: Network muestra el `?v=N` nuevo y el flujo tocado funciona.

**Edge Functions (Supabase):**
- Fuente de verdad: `_supabase_functions/functions/`.
- Deploy: `supabase functions deploy <nombre> --project-ref dctqcbznekcyxhjujuci` (o vía MCP de Supabase).
- Secrets: `supabase secrets set NOMBRE=valor --project-ref dctqcbznekcyxhjujuci`.

---

## ÚLTIMA ACTUALIZACIÓN

**2026-05-24 (c)** — **Tiempo real (Supabase Realtime).** Badge de comunicados en vivo en las 7 páginas cliente: sube al llegar un comunicado, baja al marcar leído en otra pestaña. Centralizado en `novedades-utils.js`; tablas `novedades` + `novedades_leidas` agregadas a la publicación `supabase_realtime` (la RLS filtra por usuario, sin fuga). Auditado en 3 fases. Ver [[project_realtime_novedades]].

**2026-05-24 (b)** — **Auditoría pre-lanzamiento + correcciones.** Fix del bug de fechas UTC en el cliente; **interés compuesto** implementado; Excel de pagos endurecido (anti-inyección de fórmulas en export, validación de montos en import); CSP corregida (queda en Report-Only); upload/borrado de documentos (magic bytes `%PDF`, orden BD→Storage); rollback de imagen en comunicados; accesibilidad (zoom WCAG, labels, focus-visible); RLS de `perfiles` endurecida contra escalada admin→superadmin; límites de bucket. Ver [[project_auditoria_prelanzamiento]].

**2026-05-24 (a)** — Creación inicial (auditoría completa del código real). Incluye RPCs/triggers, modelo RLS, buckets de Storage, tabla de versiones `?v=N` y checklist de deploy. Cambios del día: rediseño de `beneficios.html` (carrusel de aliados con franja de marca), feature **eliminar cliente** (superadmin) + edge function `eliminar-cliente`, y limpieza de la tabla `novedades`.
