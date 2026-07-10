# Inventario de módulos funcionales — CRM VITANOVA (Clínica Álvarez) → esqueleto para CRM Avance Corp (React Native/Expo)

Base analizada: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/crm-vitanova-vite/src` (READ-ONLY, no se modificó nada).
Stack VITANOVA: Vite + React 19 + TS + shadcn/Radix + Tailwind + recharts + @dnd-kit + jsPDF + Supabase (auth, Postgres+RLS, realtime, edge functions). SPA sin router (estado `view` en `App.tsx:59`).

---

## 0. Arquitectura de arranque y navegación

- `App.tsx:16-25` — todas las pantallas con `lazy()` (code-split por pantalla). `App.tsx:104-118` — árbol de providers: `AuthGate > CotizadorProvider > GestionProvider > FichaProvider > NuevoProspectoProvider > Workspace`. Providers de dominio montados UNA vez; cualquier pantalla abre ficha/cotizador/gestión vía hooks de contexto.
- `App.tsx:77-99` — ErrorBoundary POR PANTALLA con `resetKeys=[view]` + `logError` (un crash no tumba el shell). Route-guards por estado: `App.tsx:66-69` (config solo-gerente, leads solo quien tiene `repartirLeads`).
- `components/app/sidebar.tsx:17-27` — NAV: dash, leads (staff), pipe, calendario, prospectos, inbox, cotizaciones, reportes, inteligencia (+ Configuración si `verConfiguracion`). Badges vivos: `sidebar.tsx:35-38` (prospectos activos, no-leídos inbox, leads sin repartir).
- `components/app/auth-gate.tsx` — máquina de fases `init|anon|booting|ready|error` con timeout de boot 15s; renderiza `Login` si anon.
- `components/app/topbar.tsx` — buscador global (Enter → `setSearchQuery` + navega a Prospectos), campana de notificaciones, botón "+" (nuevo prospecto), toggle tema.

**Mapeo Avance:** el patrón shell + providers globales + guards por capacidad transfiere como IDEA a RN (expo-router con tabs/drawer + contextos), pero TODO el shell es DOM/Tailwind → ADAPTA. `components/ui/*` (24 wrappers Radix) NO existe en RN → DESCARTA.

---

## 1. lib/store.ts — NÚCLEO (2.385 líneas). Patrón useSyncExternalStore pub/sub

Es un **store singleton a mano, sin Redux/Zustand**, 100% TypeScript puro + supabase-js. Piezas:

1. **Cache mutable `S`** (`store.ts:112-135`): `me, lineas(Map), usuarios(Map), prospectos[], convs[], plantillas[], notifs[], activeConvId, configClinica`. Los datos llegan YA recortados por RLS ("el cache es el scope del rol").
2. **Pub/sub + snapshot estable** (`store.ts:140-195`): `listeners: Set<()=>void>`; `buildSnapshot()` crea un objeto NUEVO solo cuando se llama `notifyAll()` — cumple el contrato de `useSyncExternalStore` (getSnapshot estable entre cambios). Transcripción literal del hook:
   ```ts
   export function useStore(): StoreSnapshot {
     return useSyncExternalStore(subscribe, getSnapshot, getSnapshot)
   }
   ```
   Cada mutación hace `await load*(); notifyAll()` → TODAS las pantallas suscritas re-renderizan. `citasRev` (`store.ts:153-159`) es un contador que sube con cada cambio realtime de `citas`/`cotizaciones` para que el Calendario re-lea sin recargar.
3. **Boot secuencial** (`store.ts:266-282`): usuario → (líneas ∥ usuarios) → (prospectos ∥ plantillas) → conversaciones → (notifs ∥ configClinica) → `suscribirRealtime()` → `notifyAll()`.
4. **Realtime** (`store.ts:794-820`): UN canal `inbox-rt` con 5 binds postgres_changes: `conversaciones` (*), `actividades` (INSERT, solo refresca si es la conv activa), `notificaciones` (filtro `usuario_id=eq.`), `citas` (*→citasRev++), `cotizaciones` (*→citasRev++).
5. **Escrituras optimistas con rollback**: `moverEtapa` (`store.ts:366-391`) muta el cache, `notifyAll()`, y si el UPDATE falla revierte; ídem `registrarContacto` (`store.ts:770-791`, sella `primera_respuesta_en` optimista) y `marcarNotificacionesLeidas` (`store.ts:706-716`).
6. **Convención de resultado**: `ActionResult {ok, error?, code?, id?}` + toasts sonner centralizados en `notify()` (`store.ts:104-110`).
7. **Adaptadores puros `adapt`** (`store.ts:824-940`): fila BD → shape de UI (`adaptProspecto`, `adaptSla`, `adaptActividad`, `adaptMensaje`, `adaptConv`, `etapaId/etapaToSnake` snake⇄short). La UI NUNCA toca filas crudas de BD directamente para presentación.
8. **Regla de oro del cliente** (`types.ts:1-4`): "Donde la BD calcula valores, se reflejan como solo lectura (el cliente NUNCA recalcula score ni SLA)". `score_actual` y `sla_estado/sla_proximo_vencimiento` los sella la BD (triggers/cron).
9. **API pública** (`store.ts:2341-2383`): ~70 métodos agrupados: auth, cargas, pipeline, cotizaciones, calendario, inbox, dashboard, IC, reportes, configuración, pub/sub, adaptadores, constantes.

**Constantes de dominio** (`store.ts:39-94`): ETAPAS = nuevo→contacto_inicial→consulta_agendada→cotizacion_enviada→cirugia_agendada ("Venta cerrada") + TERMINALES cerrado_ganado/cerrado_perdido; `GANADAS=[cirugia_agendada,cerrado_ganado]`; MOTIVOS de pérdida (precio/tiempo/competencia/medico/no_responde/otro); ACT (11 tipos de actividad → color/icono/label).

**Transición de etapa** (`store.ts:357-364`) — transcripción literal:
```ts
function validTransition(from: string, to: string): boolean {
  if (from === to) return false
  if (to === 'cerrado_perdido') return from !== 'cerrado_ganado'
  if (to === 'cerrado_ganado') return from === 'cirugia_agendada'
  const fi = ORDER.indexOf(from), ti = ORDER.indexOf(to)
  if (fi === -1 || ti === -1) return false
  return ti === fi + 1 || ti < fi // adelante contiguo o cualquier retroceso
}
```

**Ley 29733** (privacidad Perú): `anonimizarProspecto` (`store.ts:429-435`, RPC gerente-gated, soft-close + auditoría), `exportarProspecto` (`store.ts:439-455`, derecho de acceso: prospecto+actividades+cotizaciones+citas → JSON). Consentimiento en alta (`nuevo-prospecto-provider.tsx:50-55`).

**Mapeo Avance:** el PATRÓN (cache + pub/sub + useSyncExternalStore + optimista + adaptadores + "la BD calcula, el cliente muestra") funciona IDÉNTICO en React Native — `useSyncExternalStore` es de React, no del DOM. Lo único web del núcleo es sonner (toasts) → reemplazar por toast RN. Los ~70 métodos son de dominio clínico → renombrar entidades (prospecto→lead/cliente de inversión, cotización→propuesta, cita→reunión/llamada, línea_servicio→producto de inversión, clinica_id→empresa_id). OJO: `loadProspectos` hace `select('*')` sin paginación (`store.ts:302-306`) — con 5.000 clientes hay que paginar o particionar el cache.

---

## 2. Pantallas (screens/)

### 2.1 dashboard.tsx (633 líneas) — "centro de acción del día"
- **Datos**: `store.dashboardData(rol)` (`store.ts:1047-1384`, async: cache + query de metas + citas de hoy + tareas de cadencia) + `inteligenciaComercial()`/`inteligenciaComercialPlus()` (síncronas sobre cache).
- **Roles** (`lib/roles.ts:41-43` `dashboardVariant`): TODOS ven KPIs+charts; variante **asesor** antepone bloque "HOY" (`dashboard.tsx:445-495`): cola "Tu siguiente acción hoy" + "Tu agenda de hoy" + "Tu meta del mes" (MetaBar cirugías/ingreso/conversión); **supervisor** (`dashboard.tsx:549-587`): Ranking del equipo por conversión + "Respuesta en riesgo" (SLA vencidos); **gerente** (`dashboard.tsx:590-612`): Comparativa por equipo (por supervisor).
- **KPIs** (4, `store.ts:1090-1102`): Prospectos activos, Conversión a venta (cohorte C8: ganadas ÷ los-que-alcanzaron-consulta usando `etapa_maxima_idx`), Valor en proceso (Σ ticket abiertos), Ventas cerradas — con sparkline acumulado 7 semanas y **desglose contextual por KPI** (`dashboard.tsx:250-298`, popover KpiBreakdown con secciones por canal/asesor/servicio que cambian según rol).
- **Acciones**: llamar/WhatsApp desde la cola (→ GestionProvider "¿Lograste contacto?"), abrir ficha, descartar/reactivar tarea de cadencia (`dashboard.tsx:313-319`: descartar = `moverEtapa(id,'cerrado_perdido','no_responde')`).
- **"Resultados por semana"** (`store.ts:1221-1294`, card `bi/resultados-semana.tsx`): 4 semanas fijas del mes (1–8, 9–15, 16–22, 23–fin), monto cerrado + conversión same-week + 2 conversiones de scope; desglose por asesor y por supervisor según rol.
- Ingreso del mes = Σ cotizaciones ACEPTADAS por `aceptada_en` (`store.ts:1201-1212`) — misma fuente que Reportes para que no discrepen.
- **Mapeo Avance:** ADAPTA — la estructura (cola accionable + agenda + meta + KPIs por rol) es oro para vendedores de inversiones; KPIs pasan a: capital captado, contratos firmados, renovaciones, vencimientos próximos. Recharts (Pie/donut) no corre en RN → victory-native/react-native-svg.

### 2.2 pipeline.tsx (262) — Kanban
- 5 columnas desde ETAPAS (`pipeline.tsx:19-21`); tarjeta simple: nombre · servicio · monto · SLA ("cuándo vence") · avatar asesor + botón "Cotizar" al hover (`pipeline.tsx:34-92`). Header de columna con conteo, Σ monto y barra proporcional al máximo (`pipeline.tsx:189-201`).
- **Drag-and-drop HTML5 nativo** (`pipeline.tsx:134-147`): drop → `store.moverEtapa` (que valida `validTransition` y hace toast del error si la transición no está permitida).
- Rol: filtro por asesor solo staff (`can(rol,'filtrarPorAsesor')`, `pipeline.tsx:97`); el asesor solo ve lo suyo por RLS.
- **Mapeo Avance:** ADAPTA — kanban de etapas de venta de inversión (p. ej. nuevo → contactado → reunión → propuesta enviada → contrato firmado). DnD HTML5 NO existe en RN → react-native-gesture-handler/reanimated o drop-down "mover a etapa" (más honesto en móvil).

### 2.3 prospectos.tsx (311) — tabla de cartera
- Chips de filtro por rol (`prospectos.tsx:41-42`): staff = Todos/Sin asignar/Respuesta urgente/Alto valor(≥12k); asesor sin "Sin asignar". Filtro asesor (staff), búsqueda nombre/tel/DNI (con matching por dígitos, `prospectos.tsx:76-84`), botón Importar CSV (staff).
- `StatStrip` + `SegmentBar` (`prospectos.tsx:139-166`): resumen de LO VISIBLE (conteo == lista) + distribución por etapa.
- Tabla: prospecto (avatar por línea), línea, etapa (badge color), valor, puntaje (color por score), SLA texto, asesor (staff), creado; fila → ficha.
- **Mapeo Avance:** ADAPTA — la vista "cartera" para 5.000 clientes exige FlatList virtualizada + búsqueda server-side (aquí es filtro en memoria). "Alto valor" umbral 12k → parametrizar por monto de inversión.

### 2.4 leads-nuevos.tsx (149) — bandeja de reparto
- Solo staff (guard `repartirLeads`). Leads "parkeados" = `!asesor_id && eliminado !== true` (`leads-nuevos.tsx:35-41`), ordenados por `ordenarLeadsParaRepartir` (SLA vencido → warn → ok; luego el más antiguo).
- Asignación 1-clic a asesor: supervisor solo a SU equipo (`u.supervisor_id === supId`), gerente a cualquiera (`leads-nuevos.tsx:44-47`); gerente además "rebalancea" el lead a otro supervisor (`store.rebalancearSupervisor`, `store.ts:467-473`, columna `asignado_supervisor_id`).
- **Mapeo Avance:** ADAPTA — patrón exacto para reparto de leads de inversión vendedor←supervisor←gerencia. El modelo "lead parkeado con supervisor de turno" (asignado_supervisor_id) transfiere conceptualmente tal cual.

### 2.5 inbox.tsx (602) — inbox WhatsApp 3 paneles
- Lista de chats (`adapt.conv`: estado urgente/espera/resuelto derivado de último entrante vs saliente, `store.ts:910-930`) + hilo con burbujas + panel de contexto del prospecto (etapa, score, valor, asesor, SLA, CTA cotizar/ficha).
- **Modo auditoría** (`inbox.tsx:161-164` + `roles.ts:46-51`): SOLO el asesor DUEÑO responde; staff ve banner "Estás viendo como auditor" sin composer. Banner ventana 24h de WhatsApp (`inbox.tsx:180-186`).
- Envío: `store.enviarMensaje` (`store.ts:680-695`) — si `WHATSAPP_LIVE` invoca edge `whatsapp-enviar`, si no registra actividad (modo demo con aviso). "Simular entrante" (staff, RPC `simular_whatsapp_entrante`) es tooling de demo.
- Realtime ya integrado vía store (recarga conv + hilo activo).
- **Mapeo Avance:** ADAPTA — comunicación con inversionistas por WhatsApp aplica igual; el "modo auditoría dueño-responde" encaja con el nivel directorio/auditoría. DESCARTA el simulador demo. La integración real Meta Cloud API sigue pendiente también en VITANOVA.

### 2.6 cotizaciones.tsx (343) — lista + visor + PDF
- Lista con StatStrip (monto cotizado, aceptadas, por vencer ≤7d) + SegmentBar por estado (borrador/enviada/vista/aceptada/rechazada/vencida). "Enviar" borrador solo el dueño (`cotizaciones.tsx:206`); staff audita solo-lectura. Visor Dialog de solo lectura + Descargar PDF (import dinámico de jsPDF).
- Reglas de negocio en `store.guardarCotizacion` (`store.ts:495-525`): subtotal a céntimos, **IGV 18% con exoneración por "Servicio de salud exonerado de IGV" por defecto**, validez_dias (15), estado borrador/enviada; `vence_en` lo calcula trigger al enviar; `reprogramarCotizacion` (`store.ts:537-543`) cambia vencimiento (drag en calendario).
- **Mapeo Avance:** ADAPTA → **propuesta de inversión**: ítems = producto de inversión (Nuevo/Renovación/Upgrade) con monto/plazo/tasa (≤15% anual) en PEN/USD; la exoneración de IGV salud se DESCARTA (dominio clínico); el ciclo borrador→enviada→vista→aceptada→vencida y "por vencer" transfieren como idea.

### 2.7 calendario.tsx (216) + components/calendario/
- Vistas Mes/Semana/Día. **3 fuentes fusionadas** en `store.calendarioEventos` (`store.ts:556-615`): citas (editables) + cotizaciones por vencer (overlay solo-lectura) + SLA por vencer (overlay desde cache). Filtro asesor (staff).
- **Reprogramación estilo Google Calendar** (`calendario.tsx:84-117`): drag con @dnd-kit (snap 15 min en Semana/Día; cambio de día en Mes conservando hora), optimista local + persistencia en background + toast con "Deshacer" + reversión en error; refresco en vivo por `citasRev`.
- `modal-cita.tsx`: crear/editar/estado(programada/realizada/cancelada/no_show)/eliminar; tipos consulta/cirugía/llamada/seguimiento/recordatorio (`calendario/shared.ts:6-15`). `agendarCita` (`store.ts:628-651`): sin asesor explícito el trigger hereda el dueño del prospecto.
- **Mapeo Avance:** ADAPTA — cita→reunión/llamada con inversionista; overlay "cotización por vencer"→**vencimiento de contrato/propuesta**; overlay SLA transfiere. dnd-kit es DOM → gestos RN. OJO: `eliminarCita` es HARD DELETE (`store.ts:665-671`) — contradice la política soft-delete del destino.

### 2.8 inteligencia.tsx (643) — BI de conversión
- Consume `inteligenciaComercial()` (`store.ts:1409-1501`): conversión general (esConsulta→esCirugia), por canal/asesor/servicio, cruces asesor×canal y asesor×servicio; y `inteligenciaComercialPlus()` (`store.ts:1512-1729`): embudo de ALCANCE monótono + `stageToStage` + `mayorFuga`, tiempo de 1ª respuesta (avg, %enSLA, rápidos≤60min vs lentos con gate de evidencia base≥3), tendencia 8 semanas, **insights accionables auto-generados** (tarjetas clicables con lista de prospectos: sin_responder/caliente/cotización; + diagnósticos: mejor canal, canal oportunidad, mejor asesor, fuga, respuesta lenta, "rápido convierte más").
- UI: hero conversión general, cards-preview por dimensión → `DimensionDetailDialog` full-screen (buscador+orden+CSV, pensado para 70+ filas), matrices heat → `CruceDetailDialog` (sticky headers, CSV). Filtro asesor staff; títulos cambian por rol ("Tus canales" vs "Por canal").
- **Mapeo Avance:** ADAPTA — misma matriz para conversión lead→contrato por canal/vendedor/producto; el motor de insights (accionables > tablas mudas) es de lo más valioso a portar. Recharts→RN charts.

### 2.9 reportes.tsx (1.112) + lib/reportes.ts (524) — centro de reportes
- Filtros globales: preset de período (hoy/7d/30d/mes/mesPasado/trimestre/año/custom con Calendar) + asesor + equipo + línea + canal (`reportes.tsx:122`, selects gateados por `can()`).
- 6 tabs: Resumen · Embudo · Equipo (cap `verEquipo`: asesor NO la ve) · Dinero · Velocidad · Origen (`reportes.tsx:106-113`). Export **PDF (window.print con vn-print-head)** y **CSV con BOM** (`reportes.tsx:48-77`); cada sección abre full-screen (`report-detail.tsx`: FullTable con buscador+orden+CSV).
- Motor `construirReportes` (`lib/reportes.ts:499-519`): 14 bloques — embudo cohorte, estatus por servicio, conversión vs período anterior, motivos de pérdida, estancados (breach o >7 días sin mover), ranking, conversión por asesor, ingresos (cotizaciones aceptadas: ventana/serie 6m/por línea/ticket prom), pipeline ponderado + forecast (PROB por etapa 10/25/50/70/90, `reportes.ts:51-53`), SLA donut, 1ª respuesta (% dentro de 4h), no-show, actividad por asesor, canal/origen + referidos, comparativa equipos + productividad por supervisor, avance de metas con semáforo (`reportes.ts:69-71`), KPIs con delta vs período anterior. Todo en cliente sobre datos RLS-scoped; `fetchDataset` (`store.ts:1912-1925`) trae cotizaciones (≤5000), actividades de la ventana (≤10000), metas.
- Legacy paralelo: `reportesGerente` (RPCs `kpi_conversion_cohorte`, `kpi_ingreso_mes`, `kpi_no_show`, `kpi_tiempo_etapas`, `store.ts:1830-1862`) y `reportesEquipo` (`store.ts:1865-1898`).
- **Mapeo Avance:** ADAPTA — el motor de "un dataset filtrado → todos los reportes" transfiere entero como patrón; métricas renombradas (ingresos = capital captado/intereses; forecast por etapa aplica igual). `window.print` NO existe en RN → expo-print. Con 5.000 clientes el cálculo 100% en cliente puede requerir RPCs agregadas.

### 2.10 configuracion.tsx (73) + components/config/
- Solo gerente (guard `verConfiguracion` + edición `editarConfiguracion`, `configuracion.tsx:35-48`). 6 tabs CRUD (todas contra store, `store.ts:1969-2334`):
  1. **Líneas** (`config-lineas.tsx`): nombre/categoría/ticket_promedio/orden/activa (toggle con AlertDialog). → productos de inversión.
  2. **Tiempos/SLA** (`config-sla.tsx`): umbral 1ª respuesta en minutos (JSONB `clinicas.configuracion.sla.primera_respuesta_min`, default 5, `store.ts:2263-2286`) + reglas por etapa (horas_max, warning_pct, accion_breach, activa).
  3. **Plantillas WhatsApp** (`config-plantillas.tsx`): nombre/categoría/contenido/activa; `estado_meta` solo-lectura (aprobación Meta).
  4. **Cadencias** (`config-cadencias.tsx`): cabecera (nombre, evento_disparador, modo 'auto'|'tarea', activa) + editor de pasos (paso, offset_dias, canal, plantilla_mensaje); `guardarPasos` = delete+insert con BACKUP/restore si falla (`store.ts:2110-2134`).
  5. **Usuarios** (`config-usuarios.tsx`): cupo 3 supervisores / 6 asesores (límites en JSONB, `store.ts:2154-2172`), crear vía **Edge Function `admin-crear-usuario`** (gerente-gated, cuota server-side, devuelve contraseña temporal, NUNCA crea gerente, `store.ts:2177-2208`), editar rol/supervisor/activo/nombre/teléfono.
  6. **Metas** (`config-metas.tsx`): por asesor y mes (`YYYY-MM-01`): meta_cirugias/meta_ingreso/meta_conversion; meta default con `usuario_id null`.
- **Mapeo Avance:** ADAPTA completo — mismas 6 secciones con dominio renombrado (líneas→productos; metas→metas de captación); cupos 3/6 se recalibran; el patrón edge-function para alta de usuarios + contraseña temporal ya existe también en el portal Avance (`crear-admin`).

### 2.11 login.tsx (116) + auth-gate
- signInWithPassword de Supabase; sin registro público. ADAPTA a RN (supabase-js con AsyncStorage).

---

## 3. lib/ restantes

- **roles.ts (51)** — matriz `CAPS: Record<Rol, Caps>` con 10 capacidades (`verTodaClinica, verEquipo, filtrarPorAsesor, filtrarPorEquipo, reasignar, repartirLeads, inboxVerAjeno, verConfiguracion, editarConfiguracion, verReportes`) + `can()` + `dashboardVariant()` + `inboxPuedeResponder()`. Cabecera literal: "NO es seguridad (eso vive en RLS) — es la UX". Solo 3 roles (gerente/supervisor/asesor). **ADAPTA: Avance necesita 4º nivel `directorio` (solo-lectura/auditoría) — el mecanismo escala trivialmente añadiendo una fila a CAPS.**
- **leads-reparto.ts (10)** — pura, testeada (vitest): orden por urgencia SLA→antigüedad. ADAPTA (renombres de tipo).
- **import-prospectos.ts (118)** — wizard CSV 100% cliente (dry-run): PapaParse (worker, auto-delimitador, BOM), `autoMapear` por sinónimos de cabecera (`import-prospectos.ts:23-31`), validación (tel peruano `telE164` = igual que `normalizar_telefono()` SQL, DNI 8 dígitos, email), dedupe intra-archivo y contra cache por tel/DNI, resultado nuevo/dup_archivo/dup_existente/error; insert real en `store.importarProspectos` (`store.ts:410-425`: lotes de 500 con reintento fila-a-fila para aislar 23505). **ADAPTA — clave para migrar los ~5.000 clientes de Avance; en RN Papa parsea strings (expo-document-picker + FileSystem), sin worker.**
- **reportes.ts (524)** — ver §2.9.
- **search.ts (26)** — singleton módulo puente buscador→pantalla (pendingQuery + listeners). TRANSFIERE tal cual (TS puro, cero web).
- **pdf-cotizacion.ts (193) + pdf-font.ts** — jsPDF+autotable, fuente Roboto embebida en base64 (UTF-8/ñ), paleta de marca, nota legal Ley 29733, `doc.save()`. ADAPTA: en RN jsPDF no descarga (expo-print/HTML-to-PDF); fuente → Plus Jakarta Sans; contenido → propuesta de inversión (monto, plazo, tasa, cronograma).
- **config.ts (34)** — CONFIG desde `import.meta.env` (VITE_*), MARCA/SEDE/CLINICA_NOMBRE, flag `WHATSAPP_LIVE`. ADAPTA (Expo: `process.env.EXPO_PUBLIC_*` / app.config).
- **format.ts (116)** — money/moneyK es-PE "S/", fmtFecha/fmtFechaHora, `telE164` (+51, 9 dígitos, empieza en 9), fmtTelefono, iniciales, dias/horas, `scoreColor` (verde ≥70/ámbar ≥40/gris — **usa verde, prohibido en destino**), `humanizarDuracion` (min→h→días→meses, fuente única de "hace…"), cortoT, tiempoCorto. Testeado. ADAPTA: money debe ser multimoneda PEN/USD; el resto (tiempo/teléfono/iniciales) TRANSFIERE literal.
- **log-error.ts (52)** — logging best-effort a tabla `app_errores` (RLS por clínica, lectura solo gerente): scrub de PII/tokens ANTES de salir del cliente (regex `log-error.ts:10` incluye DNI de 8 dígitos), de-dup con TTL 30s, fire-and-forget, jamás lanza. ADAPTA (usa `location`/`navigator` web → equivalentes RN); el patrón es excelente y barato.
- **types.ts (1.078)** — todos los tipos del data layer (ver secciones). ADAPTA: se reescribe con el modelo de inversiones, conservando las convenciones (RO para columnas calculadas por BD, payloads Input con `id?` insert/update, `ActionResult`).
- **supabase.ts (7)** — cliente único compartido. ADAPTA (RN: storage AsyncStorage, `detectSessionInUrl:false`).
- **theme.tsx / utils.ts (cn)** — web/Tailwind → DESCARTA en RN.

---

## 4. Componentes de dominio (inventario por carpeta)

- **prospecto/**: `nuevo-prospecto-provider.tsx` (477) — alta con validación inline, tel `telE164`, asesor oculto si rol=asesor (se auto-asigna), consentimiento Ley 29733 opcional (fecha+canal 'presencial'), error 23505 inline en teléfono. `import-prospectos-dialog.tsx` (179) — wizard subir→revisar(mapeo editable+resumen)→importar; solo staff. Ambos ADAPTA.
- **ficha/**: `ficha-provider.tsx` (617) — LA ficha 360° en Sheet lateral global: hero (avatar por línea, StageMenu para mover etapa con submenú de motivo de pérdida; solo-lectura en modo auditoría `ficha-provider.tsx:116-130`), tabs Resumen/Actividad(timeline `adapt.actividad`)/Cotizaciones, footer WhatsApp/Llamar/Nota/Cita/Cotizar (integra Gestión y Cotizador), bloque Ley 29733 solo gerente (exportar JSON / anonimizar con confirm, `ficha-provider.tsx:279-296,426-437`). ADAPTA (Sheet→bottom-sheet/stack screen RN). Es el hub de acciones sobre un cliente: pieza central a replicar.
- **cotizador/**: `cotizador-provider.tsx` (465) — modal global: selector de prospecto, ítems desde catálogo (líneas con ticket_promedio), IGV exonerado por defecto (toggle 18%), validaciones (≥1 ítem, total>0), guardar borrador / enviar (+ prefill WhatsApp). ADAPTA → constructor de propuesta de inversión (monto, producto Nuevo/Renovación/Upgrade, plazo, tasa, moneda).
- **gestion/**: `gestion-provider.tsx` (79) — patrón "registrar gestión": abre deep link (wa.me / tel:) y al volver pregunta **"¿Lograste contacto?"** → inserta actividad (`whatsapp_enviado` | `llamada_realizada` | `llamada_no_contestada`) que sella `primera_respuesta_en` vía trigger y saca al prospecto de "sin responder"; Cancelar no registra (clic accidental). ADAPTA (window.open/tel: → `Linking` de RN; en móvil este patrón es INCLUSO más natural). Pieza estrella.
- **calendario/**: `shared.ts` (colores/labels por tipo, helpers fecha PE, semana lunes), `modal-cita.tsx`, `vista-mes.tsx` (grilla 6×7, chips arrastrables @dnd-kit), `vista-semana.tsx` (franjas 07–21, snap 15min, banda all-day para overlays), `vista-dia.tsx` (rejilla horaria), `ev-chip.tsx` (overlays punteados con candado). ADAPTA en bloque (dnd-kit y CSS absolutos → RN).
- **reportes/**: `rep-primitives.tsx` (217: KpiCardR, Panel, HBars, DonutLegend, Funnel, ConvGauge, IngresosBar, ProbBar) y `report-detail.tsx` (404: ReportSectionCard preview→full-screen, FullTable genérica con buscador/orden/CSV, BigHBars, DetailSplit). ADAPTA.
- **bi/**: `kpi-breakdown` (popover de desglose por KPI), `insights-band`/`AccionableInsights` (callouts good/warn/info; clic→lista), `insight-prospectos-dialog` (modo full asesor con CTAs vs modo audit staff), `resultados-semana` (barras ingresados vs convertidos same-week), `funnel-stages` (embudo de alcance + mayor fuga), `response-time-panel` (1ª respuesta), `dimension-detail`/`cruce-detail` (full-screen escalables a 70+ filas, CSV), `ic-bars`, `conversion-card`. ADAPTA en bloque; la lógica que consumen ya vive en el store (separación limpia datos/presentación).
- **config/**: 6 CRUDs (ver §2.10). ADAPTA.
- **common/**: `animated-value` (count-up accesible, prefers-reduced-motion, sr-only), `sparkline` (recharts área), `stat-strip` (StatChip+SegmentBar "conteo==lista"), `detail-window` (Dialog full-screen reutilizable + downloadCsv), `cot-badge` (fuente única estado→color de cotización). ADAPTA (conceptos portables; implementación DOM).
- **app/**: `auth-gate` (135), `shell` (19), `sidebar` (104), `topbar` (99), `error-fallback` (29). ADAPTA (→ expo-router + contextos).
- **components/ui/** (24 archivos shadcn/Radix): DESCARTA para RN — se sustituye por un design system RN propio (navy #111e3d / azul #2563eb / blanco / Plus Jakarta Sans).

---

## 5. Patrones estrella (documentación específica)

### 5.1 Cola "Tu siguiente acción hoy" — `bucketsAccionables` (store.ts:963-1020) + ensamblado (store.ts:1328-1355)
PREDICADO ÚNICO compartido entre la cola del dashboard y las tarjetas de insights (el conteo del insight == largo de su lista). 4 buckets calculados + 1 de cadencia:
1. `sin_responder`: `!primera_respuesta_en`; sev red >15 min, amber ≥ umbral (default 5 min), green si no. Motivo: "Entró hace X y nadie la ha tocado".
2. `sla`: `sla_estado ∈ {breach, warning}`; texto "La respuesta venció hace…" / "vence en…".
3. `cotizacion`: etapa cotizacion_enviada y ≥2 días sin cambio.
4. `caliente`: score ≥70 y >48 h sin contacto REAL (usa max(primera_respuesta_en, fecha_cambio_etapa), NO `actualizado_en` porque se re-sella con cualquier UPDATE — comentario en `store.ts:1007-1009`).
5. `seguimiento` (cadencia): citas `tipo='seguimiento'` `estado='programada'` con `inicia_en ≤ hoy` (`store.ts:1296-1326`); `metadata.cadencia_fin` ⇒ tarea de DESCARTE ("Último intento sin respuesta — decide si descartar") con acciones Reactivar/Descartar; `metadata.mensaje` prefillea el WhatsApp con `{nombre}` sustituido.
Dedup por prioridad de bucket (`sin_responder > seguimiento > sla > cotizacion > caliente`), luego severidad (red>amber>green), luego score (`store.ts:1338-1343`). `Cola = {foco, items, all, counts}` — el primero es EL foco.
**Avance:** ADAPTA — buckets re-mapeados: lead sin responder / seguimiento de cadencia / SLA / propuesta sin respuesta / **contrato por vencer (renovación)** / cliente caliente. El mecanismo (predicado único + dedupe + foco) transfiere íntegro.

### 5.2 SLA de 1ª respuesta
La BD sella `sla_estado` (breach/warning/pendiente/cumplido) y `sla_proximo_vencimiento` (triggers + cron); config por etapa en `sla_config` (horas_max, warning_pct, accion_breach) + umbral de minutos en JSONB clínica. Cliente: `adaptSla` (`store.ts:831-852`) → {vencido|warn|ok} + texto humano (con caso "cron aún no volteó warning→breach"); `registrarContacto` sella `primera_respuesta_en` en la primera actividad saliente. Los eventos SLA aparecen en el calendario como overlay. **ADAPTA: idéntico para leads de inversión.**

### 5.3 Cadencias (3-3-7-7)
Modelo `cadencias` (evento_disparador, modo 'auto' registra el toque / 'tarea' crea tareas al asesor) + `cadencia_pasos` (paso, offset_dias, canal, plantilla_mensaje) — la secuencia 3-3-7-7 vive como DATOS (offsets de pasos), no hardcodeada. Los pasos 'tarea' se materializan como citas tipo `seguimiento` que caen en la cola; el último paso lleva `cadencia_fin` → decisión de descarte (mover a cerrado_perdido·no_responde) o reactivar (cerrar la tarea como realizada). **ADAPTA: cadencia de seguimiento post-propuesta y de RENOVACIÓN pre-vencimiento de contrato.**

### 5.4 Registrar gestión ("¿Lograste contacto?") — ver §4 gestion/. Convierte cada toque del vendedor en dato (actividad tipada) sin fricción.

### 5.5 Scoring
`score_actual` calculado 100% en BD ("el cliente NUNCA recalcula score ni SLA", `types.ts:3-4`); el cliente solo lo pinta (`scoreColor`: verde/ámbar/gris — recolorear sin verde) y lo usa para ordenar (`loadProspectos` order by score desc), para "calientes" (≥70) y para la prioridad IA del dashboard (`prioridad = score + urgencia_sla + min(20, ticket/2000)`, `store.ts:1123-1129`). **ADAPTA: score de propensión de inversión en BD.**

### 5.6 Kanban por etapa + validTransition — ver §2.2 y transcripción en §1. **ADAPTA: etapas del funnel de inversión; la regla "adelante contiguo o cualquier retroceso + terminales protegidas" transfiere literal.**

---

## 6. Huecos para Avance Corp (FALTA) — lo que VITANOVA NO tiene

1. **Rol directorio/auditoría (4º nivel)** — CAPS solo tiene 3 roles; el "modo auditor" del inbox es la semilla, pero no hay rol de solo-lectura global.
2. **Multimoneda PEN/USD** — todo es "S/" hardcodeado (format.ts, moneyK del store, PDF).
3. **Módulo de CONTRATOS de Asociación en Participación** — no existe entidad contrato: alta, vigencia, monto, tasa (≤15% anual), moneda, cronograma de pagos de intereses, estado (vigente/vencido/renovado/cancelado), documentos.
4. **Categorización de inversión Nuevo/Renovación/Upgrade** — VITANOVA no distingue tipo de operación (nota ya existente en el vault de Avance: `Categorización de inversiones - Nuevo Renovación Upgrade.md`).
5. **Ciclo POST-VENTA del cliente** — VITANOVA muere en "venta cerrada"; Avance necesita cartera viva: pagos de intereses, vencimientos, renovaciones, upgrades, comprobantes.
6. **Soft-delete estandarizado `activo=false`** — prospectos tienen `eliminado` (semántica invertida al estándar del destino) y las citas se BORRAN con DELETE (`store.ts:665-671`); el destino exige nunca hard-delete de clientes.
7. **Push notifications móviles** — VITANOVA usa realtime web + tabla `notificaciones`; en Expo hace falta expo-notifications (Avance ya tiene edge `notificar-pagos`/`diagnostico-push` en el portal — reutilizable).
8. **Paginación/consulta server-side para 5.000 clientes** — `loadProspectos` trae todo el scope a memoria; en móvil hay que paginar + FlatList + búsqueda en servidor.
9. **Persistencia offline / rehidratación del cache** — el store es memoria pura; en móvil conviene cache persistente (al menos snapshot inicial).
10. **Tipo de cambio y consolidación PEN/USD en reportes/KPIs.**
11. **Gestión documental del contrato** (PDF firmado, vouchers) — solo hay PDF de cotización generado en cliente.

## 7. Conflictos de diseño destino (a resolver al portar)

- Paleta VITANOVA: brand magenta #9c1a84, éxito/OK **verde** #18a06b/emerald (score, SLA ok, burbujas WhatsApp emerald-600) → destino navy #111e3d + azul #2563eb, **SIN verde** → todo el mapa semántico de color se redefine.
- Tipografía: destino Plus Jakarta Sans (incluye la fuente embebida del PDF).
- Naming: VITANOVA YA es español snake_case en BD y código (prospectos, lineas_servicio, actividades, citas, cotizaciones, usuarios, metas, cadencias, plantillas_whatsapp, sla_config, clinicas, app_errores) → la convención TRANSFIERE; solo cambian los sustantivos de dominio.

