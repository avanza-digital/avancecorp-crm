---
tags: [portal, pagos, admin, figma, plan, ux]
creado: 2026-09-26
estado: LAS CUATRO FASES PUBLICADAS Y VERIFICADAS el 26/09 (commits 12d9d4f, bf32942, 97895bb, 232b2ea y 10693b1 del portal) · pendiente pasada visual de Miguel y retirar admin_pagos_resumen ~03/10
---

## Decisión (26/09, Miguel): «solo lo que toca pagar», SIN el tramo «Próximos 30 días» → F5 publicada
Primero dijo «déjalo así»; al aclarar, lo que no le gustaba era SOLO el tramo «Próximos 30 días — para
adelantar pagos» («esto no me gusta, lo demás sí»). Se construyó y publicó el resto de la maqueta como **F5**
(ver Avance). **No volver a proponer el tramo de 30 días.** Para adelantar un pago se busca el contrato.

## Avance
- **26/09 ~18:45 UTC · `admin_pagos_resumen()` RETIRADA de la base** (orden de Miguel, sin esperar la semana).
  Comprobado antes: 0 funciones/vistas/triggers/crons/pg_depend; en código solo un comentario y los tipos
  generados del CRM. Migración `20260926182748_portal_retira_admin_pagos_resumen.sql` + registrador +
  reversa con el cuerpo exacto (md5 `6deebbc3…`), en `CRM-Avance-Corp/supabase/`. Aplicada por Miguel con
  `db query --linked --file`; verificado: función ausente, versión registrada, RPC nueva y métricas responden.
- **26/09 18:33 UTC · F5 «solo lo que toca pagar» PUBLICADA Y VERIFICADA (LEVEL 1).** Pagos = Agenda + buscador:
  sin pestañas ni contadores; `#vistaContratos` solo con texto en el buscador (`buscando()`,
  `actualizarVistaContratos`), `p_tab='todos'`, 5 columnas (sin Capital/Avance); dos tarjetas arriba
  («Cuotas por pagar» número, «Pagos atrasados» → En mora); «Pagados este mes» y «Total pagado» ahora en el
  **Dashboard** (`dashboard.js?v=22`, RPC `admin_pagos_metricas`, `renderMetricasPagos`); subtítulo
  `#agendaResumen` «N cuotas en los próximos 7 días». Commit `d13117a`; bumps `admin.css v24` (11 HTML),
  `pagos.js v43`, `dashboard.js v22`, SW `avance-v129`. TUS 14 archivos con pre-check «producción = 10693b1»,
  purga, 14/14 idénticos en 3 lecturas. 133/133 pruebas. Maqueta de comprobación: copia sin login del
  `pagos.html` real con filas de muestra (`.playwright-mcp/f5-pagos-simplificada.jpg`).
- **26/09 18:20 UTC · F4 PUBLICADA Y VERIFICADA (LEVEL 1, sin Codex).** Todo scoped a Pagos: buscador y moneda en
  una fila (`#filtrosPagos select.input { width:auto; flex:0 0 220px }`); tarjetas `#metricasPagos` legibles
  (12/26/14 px) y las dos con lista detrás pulsables (`role="button"`, teclado, `data-ir`): «Cuotas por pagar» →
  pestaña Por pagar, «Pagos atrasados» → Agenda/En mora (limpian filtros antes); frase del Excel → `.toolbar-hint`
  corto + `.btn-ayuda` «?» con el `title`; `#vistaContratos.is-cargando` + `aria-busy` mientras llega otra página.
  Las tarjetas «de este mes» no enlazan (no hay lista de pagos del mes; idea futura). Commit `10693b1`; bumps
  `admin.css v23` (11 HTML), `pagos.js v42`, SW `avance-v128`. TUS 13 archivos, pre-check «producción = 232b2ea»,
  purga, 13/13 idénticos en 3 lecturas. 133/133 pruebas. **Con esto el plan F1–F4 queda cerrado.**
- **26/09 18:03 UTC · F2 PUBLICADA Y VERIFICADA (LEVEL 2, Codex 2 rondas).** La tabla por contrato ya no descarga
  los 656 contratos (`admin_pagos_resumen`, ~2,8 s): pide páginas de 50 a `pagos_admin_resumen_contratos`
  (existía en la base; invoker; sin migraciones ni permisos nuevos). Nuevo núcleo `js/admin/pagos-tabla-core.js?v=1`
  con test (`parametrosTabla` escapa `\ % _` para el ILIKE sin ESCAPE; `mapearFilaResumen`; `totalDeRespuesta`
  devuelve **null** sin filas; `paginaFueraDeRango`; `ultimaPagina`). En `pagos.js`: `CONTRATOS_PAGINA`,
  `recargarTabla()` con AbortController + debounce 300 ms, cuentas de pago por página (`cuentas_sin_verificar`),
  contadores de pestañas con `p_limit=1`, pie `#paginacionContratos` (`.paginacion-pie`). Pagar/anular conserva
  la página. **Codex (encargos `2026-09-26-codex-pagos-f2-paginacion*.md`):** P1 «con `count(*) OVER()` la página
  vacía no trae total → el recorte nunca ocurría y se pintaba tabla vacía» → corregido sondeando la primera página
  con 1 fila y saltando a `ultimaPagina`; P2 «recargas solapadas pisan estado» → `RECARGA_GEN` + aborto de la carga
  de tabla al iniciar cada `recargar()`. Commit `232b2ea`; bumps `admin.css v22` (11 HTML), `pagos.js v41`,
  SW `avance-v127`. Publicado por TUS (14 archivos) con pre-check «producción = 97895bb», purga y 14/14 idénticos
  en 3 lecturas. 133/133 pruebas. **Pendiente:** pasada visual de Miguel (buscar en «Todos», pagar desde la
  página 2) y retirar `admin_pagos_resumen` de la base pasada una semana (cerrar → observar → derribar).
- **26/09 17:18 UTC · F3 rehecha como PAGINACIÓN y publicada.** Miguel: «haz lo mismo con los pagos de hoy, pero
  que no sea ver más, que sea por página, que el botón sea Siguiente». Nuevo núcleo `js/admin/agenda-paginas-core.js?v=1`
  (`POR_PAGINA_POR_TRAMO` = mora ∞ · hoy 10 · semana 10; `planPagina` recorta la página si la lista encoge;
  `etiquetaPagina`) con test `tests/agenda-paginas-core.test.mjs` (7 casos); pie `.agenda-bucket-pie` con
  «← Anterior · 1–10 de 42 · Página 1 de 5 · Siguiente →», estado `AGENDA_PAGINA` por tramo (a la primera al
  cambiar filtros; se conserva al recargar tras un pago; si el encabezado quedó arriba, al cambiar de página se
  vuelve a él). `agenda-plegado-core.js` retirado del repo (huérfano en el servidor). Commit `97895bb`; bumps
  `admin.css v21` (11 HTML), `pagos.js v40`, SW `avance-v126`. Publicado por TUS (14 archivos) con pre-check
  «producción = bf32942», purga y 14/14 idénticos en 3 lecturas. 123/123 pruebas.
- **26/09 17:07 UTC · F3 PUBLICADA Y VERIFICADA (adelantada).** Miguel: «los pagos semanales me dan un scroll
  infinito». El tramo «Esta semana» (~150 cuotas) salía entero. Nuevo núcleo puro `js/admin/agenda-plegado-core.js?v=1`
  (`LIMITE_PLEGADO_POR_TRAMO` = mora ∞ · hoy ∞ · semana 10; `planPlegado`, etiquetas) con test
  `tests/agenda-plegado-core.test.mjs` (7 casos); `renderAgenda` pinta `plan.visibles` filas y un pie
  `.agenda-bucket-pie` con «Ver las N cuotas restantes» / «Ver solo las 10 más próximas» (`AGENDA_DESPLEGADOS`,
  se pliega al recargar). El Excel sigue leyendo `AGENDA_CACHE` (no la vista). Commit `bf32942`; bumps
  `admin.css v20` (11 HTML), `pagos.js v39`, SW `avance-v125`. Publicación igual que F1 (TUS, 14 archivos, purga);
  14/14 idénticos en 3 lecturas, `agenda-plegado-core.js?v=1` responde 200. 123/123 pruebas. Tramo «Próximos 30 días»
  NO hecho (opcional). `admin/contratos.html` sigue excluido (otra sesión).
- **26/09 16:57 UTC · F1 PUBLICADA Y VERIFICADA.** Miguel autorizó la subida (regla de permisos) y se publicó
  **archivo por archivo por TUS** (`hosting_generateUploadURLV1` + POST/PATCH con `?override=true`), en orden:
  `css/admin.css` → `js/admin/pagos.js` → `admin/pagos.html` + 9 HTML del admin → `service-worker.js`; luego
  `hosting_clearWebsiteCacheV1`. Verificación: los 13 archivos idénticos (sha256) en 3 lecturas consecutivas;
  `admin.css?v=19` trae `.aviso-cuenta`, `pagos.js?v=38` trae `badge-concepto`, SW `avance-v124`; `pagos.html`
  vivo pide v19/v38. **No se subió `admin/contratos.html`** (trabajo de otra sesión) ni nada fuera de los 13.
  Pendiente de F1: que Miguel/Gloria confirmen visualmente en su pantalla (recargar una vez).
- **26/09 · F1 hecha en local, sin publicar.** Commit `12d9d4f` en `public_html` (`main`): tope de 400 ms al
  `animation-delay` de filas/barras/cuotas; `.aviso-cuenta` en línea propia y columna del botón fija (200 px);
  letra mínima 14 px scoped a `.table-pagos` / `.cron-tabla-wrap` / agenda; portátiles ≤1180 px y vista apilada
  desde 960 px. Bumps `admin.css v19` (11 HTML), `pagos.js v38`, SW `avance-v124`; test de pines actualizado.
  Verificación: 116/116 pruebas del portal; página de prueba local con los CSS reales (capturas
  `.playwright-mcp/f1-pagos-1456.jpg` y `f1-pagos-1180.jpg`): columnas alineadas, fila 650 visible (retardo 0,4 s),
  tamaños 16/14 px, botones 40 px. **No se pudo mirar en producción** (la sesión del navegador caducó).
  `admin/contratos.html` NO va en el commit ni en el deploy: tiene cambios de otra sesión (eliminación de contratos);
  el bump a `admin.css?v=19` en ese archivo se publicará con ese trabajo.
  **Publicación: la hace Miguel** (el clasificador de Claude Code bloquea toda escritura en producción, incluida
  la generación de la URL de subida). Los 13 archivos exactos del commit están exportados en
  `_DEV_NO_SUBIR/portal-f1-12d9d4f/` y el orden en `_DEV_NO_SUBIR/portal-f1-12d9d4f.files`.
  ⛔ **No usar el ZIP de sitio completo hoy:** el preflight del 26/09 mostró que el repo lleva trabajo de otras sesiones
  sin publicar (`js/admin/bandeja.js`, alta del analista del 25/09) y que la CDN devuelve versiones mezcladas de
  `analista.js`/`bandeja.js` (HIT ≠ MISS). Un `deployStaticWebsite` publicaría eso y/o retrocedería archivos.
  **Pasos manuales (hPanel → Administrador de archivos, o TUS archivo por archivo):** 1) `css/admin.css` y
  `js/admin/pagos.js` primero (nunca pedir `?v=19`/`?v=38` antes de subirlos: la CDN cachea 7 días por clave);
  2) los 10 HTML del admin; 3) `service-worker.js` al final; 4) purgar caché (hPanel → Rendimiento → Purgar);
  5) en incógnito: `curl -s 'https://miavance.com/css/admin.css?v=19' | grep -c aviso-cuenta` → ≥1 y
  `curl -s 'https://miavance.com/js/admin/pagos.js?v=38' | grep -c badge-concepto` → ≥1, tres lecturas seguidas.

# Portal · Pagos (panel admin) — plan de mejora en Figma

Miguel pidió (26/09/2026) un plan de mejora del frontend de **Pagos** del panel admin del portal
(`public_html/admin/pagos.html` + `js/admin/pagos.js`) y que el plan viva en Figma para darle seguimiento.

**Tablero editable (FigJam):** https://www.figma.com/board/kZ8XNjC5fEsbogzzZMNCK7
Mismo formato que el tablero de [[Gestion Diaria - plan vivo en Figma y mejora visual (2026-09-23)]]:
título, línea «actualizado», leyenda ☑/☐/◉ y tres columnas (Diagnóstico · Fases · Reglas).

**Política:** actualizar ESTE tablero al cerrar cada fase verificada (cambiar ☐→◉→☑ en los ítems,
la línea `Fx/status` y `plan/updated`). No recrearlo. No marcar hecho sin evidencia.

## Diagnóstico (producción, con la sesión de Gloria, 26/09)

Datos vivos: 656 contratos · 5 747 cuotas · 4 852 por pagar · agenda a 7 días 186 cuotas (31 en mora) ·
349 más entre el día 8 y el 30.

Lo que hace hoy la pantalla:
- Llama a la RPC `admin_pagos_resumen()` (devuelve TODOS los contratos, 2,8 s) y pinta 186 filas de agenda
  + 1 304 filas (`652 × 2`) de la tabla por contrato escondida. Alto del documento: 13 133 px; en «Todos», 39 936 px.
- **Filas en blanco:** `.row-contrato { animation-delay: calc(var(--i) * 28ms) }` (`css/admin.css` ~l. 505).
  Con 652 filas, la última tarda ~18 s en aparecer. Es la causa principal del «se ve horrible».
- El aviso «Sin cuenta de pago — requiere conciliación» se inyecta dentro de `.agenda-row-accion` y rompe la
  rejilla de la fila (columnas `minmax(...)` + `auto`).
- Letra: contrato 12 px, avisos 11 px, chips 12 px (regla de Miguel: detalle ≥ 14 px, ver
  [[Fundamentos UX del CRM]]).
- Búsqueda y moneda filtran `CONTRATOS_CACHE` en memoria; sin paginación ni contador.
- **Ya existe en la base** `public.pagos_admin_resumen_contratos(p_tab, p_busqueda, p_moneda, p_offset, p_limit)`
  (security invoker, EXECUTE a `authenticated`, devuelve `total_count` por ventana) y
  `pagos_admin_metricas_globales()`. Ninguna de las dos la usa el front (`grep` en `js/` sin resultados).
  El patrón de paginación a copiar es el de `js/admin/clientes.js` (`PAGE_SIZE=50`, `renderPaginacion`).

## Fases (las mismas que el tablero)

1. **F1 — Que deje de verse rota (solo CSS).** Tope al `animation-delay` (p. ej. `min(var(--i)*28ms, 400ms)`),
   aviso de cuenta en su propia línea, letra mínima 14 px. Sin riesgo.
2. **F2 — Paginar la tabla por contrato.** Conectar `pagos_admin_resumen_contratos`, 50 por página, búsqueda/moneda
   en servidor con `escaparLike`, controles como Clientes, conservar la página tras pagar/anular.
   Nivel 2: Codex revisa antes de publicar. Mapear `cliente_nombre→cliente`, `contrato_id→id`, `proxima_*→proxima{}`.
3. **F3 — Agenda por tramos.** Mora + Hoy desplegados, Esta semana plegado con «Ver los N»; opcional tramo 8–30 días.
   El export de Excel debe seguir respetando los checkboxes aunque el tramo esté plegado.
4. **F4 — Retoques de lectura.** Frase del toolbar a tooltip, tarjetas KPI clicables, botones ≥ 40 px, estados por sección.

## Qué NO cambia · decisiones · diferido
- No cambian: pagar/anular, Excel, cuenta de pago obligatoria, asiento Operaciones, notificaciones. Sin migraciones.
- 50 por página; la agenda se pliega por urgencia, no por números; `admin_pagos_resumen` se retira una semana
  después de la nueva en prod (cerrar → observar → derribar).
- Diferido: vista móvil de la tabla por contrato (`css/mobile.css` solo oculta la columna Capital).

## Publicación (recordatorio)
Subir `pagos.js` con `?v` nuevo en `pagos.html`, `admin.css` con `?v` nuevo, `service-worker.js` al final,
**purgar la caché de Hostinger** y verificar la URL versionada exacta en incógnito
(ver [[CDN delante del portal]] en la memoria del proyecto).

## Nodos del tablero (para actualizar sin buscar)
- Raíz `1:3` · título `1:4` · subtítulo `1:5` · **actualizado `1:6`** · leyenda `1:7`
- Columnas: diagnóstico `1:8` · fases `1:10` · reglas `1:12`
- Diagnóstico: números `2:3` · hallazgos `2:8` (ítems `2:11`–`2:17`)
- F1 `2:19` · status `2:21` · objetivo `5:3` · ítems `2:22`–`2:24` · ves `2:25` · prueba `2:26`
- F2 `2:27` · status `2:29` · objetivo `5:4` · ítems `2:30`–`2:34` · ves `2:35` · prueba `2:36`
- F3 `2:38` · status `2:40` · objetivo `5:5` · ítems `2:41`–`2:43` · ves `2:44` · prueba `2:45`
- F4 `2:46` · status `2:48` · objetivo `5:6` · ítems `2:49`–`2:52` · ves `2:53`
- Reglas: no cambia `2:55` · decisiones `2:61` · diferido `2:66` · riesgos `2:69`

Relacionado: [[Gestion Diaria - plan vivo en Figma y mejora visual (2026-09-23)]] · [[Fundamentos UX del CRM]].
