---
fecha: 2026-10-19
estado: propuesta-B-aprobada-visualmente-plan-de-construccion-pendiente-de-ok
tags: [crm, citas, supervisor, proyeccion, semanal, diario, plan]
---

# Citas — proyección semanal y diaria por analista (plan)

**Pedido de Miguel, 19/10/2026 ~10:50 Lima:** «en citas necesitamos tener un sistema de reporte tipo una
proyección de citas semanal y diario como ellos (supervisores). Arma un plan para hacer esto posible y
vemos cómo se puede hacer de la mejor forma». Plan escrito 11:10; **sin OK todavía, sin código**.

## Lo que ya existe (medido por tres agentes de lectura, 19/10)

- **Citas → Resultados** (supervisor ve su equipo, gerencia todo; recorte en servidor) ya tiene la
  proyección **mensual** por analista: leads × 1,25 = meta de citas, entrevistas 70 %, depósito 70 %,
  ticket y cierre proyectado por ritmo (`app/src/components/citas/avance.ts:44-213`,
  `avance-mensual.tsx`). La tabla ignora la semana a propósito (`avance-mensual.tsx:100`).
- Filtros: Supervisor · Analista · Mes · Semana comercial (1–7, 8–14, 15–21, 22–fin; `modelo.ts:24-33`).
  El día solo llega por enlace (`lib/router.ts:194`).
- El servidor manda **todo el mes** en una llamada: `crm.citas_gerencia_consulta_fn(p_desde, p_hasta)`
  exige mes completo (`20260913225755_crm_citas_avance_fuentes.sql:41-46`) y cada cita trae `vence_en`
  **y `creado_en`**, estado canónico, `analista_id` (dueño actual de la tarea), supervisor, asistencia.
  → una cuadrícula analista × semana o analista × día se arma **sin tocar el servidor**.
- Metas (`crm.metas_vendedor*`) y control de citas (`crm.control_citas_*`) son **solo mensuales**;
  `mostrar_meta_citas` está forzado a `false` (`20260911212756…:27`). No existe nada semanal ni diario.
- Hoy del supervisor (publicado 18/10): tarjeta «Citas de hoy» por fecha pactada (total del equipo) y
  columna «Citas pendientes hoy» por analista **que no se abre** (`supervisor-jornada.tsx:200,237`).
- Hoy del analista: tira «Próximos 7 días» de citas pendientes (`citas-analista-particion.ts`).
- **El vault NO registra cómo proyectan hoy los supervisores** (ni Excel semanal ni reporte diario).
  El único modelo es el Excel mensual `PROYECCION DE VENTAS 2026 X ANALISTA` (nota del 10/09).
- Reglas ya decididas que NO se vuelven a preguntar: 1,25 citas por lead (interna), 70/70, mes y
  analista del evento, manuales incluidos, entrevista = asistencia, semanas comerciales, la semana solo
  filtra actividad y la meta no se reparte por semana (09-13 — **este plan la reparte: necesita OK**).

## Plan por fases

### Fase 1 — Cuadrícula «Semana a semana» en Citas → Resultados (solo pantalla)
- **Qué se construye:** tabla analista × 4 semanas comerciales + total del mes. Cada celda: meta de la
  semana · citas generadas · falta · proyección a ritmo (semáforo azul/ámbar/rojo/gris, `SenalMetrica`).
  Fila «Total del equipo» con el divisor visible (hallazgo de Jorge 28/09).
- **Meta de la semana** = meta mensual (leads del mes × 1,25, misma base que la tabla mensual) ×
  (días hábiles de la semana ÷ días hábiles del mes). **Proyección** = generadas ÷ hábiles transcurridos ×
  hábiles de la semana.
- **Citas generadas** = `creado_en` (Lima) dentro de la semana, dueño `analista_id`, misma regla de
  manuales que `avance.ts` (`actividad`). Mes cerrado / sin leads → «Sin base» (gate de realidad).
- **Todo número se abre:** celda → filtros semana + analista → Bandeja (ya existe en `propuesta.tsx:163`).
- **Celular:** tarjetas por analista agrupadas por equipo; CSV con `csvAvanceCitas` ampliado.
- **Se comprueba:** tests de `avance-semanal.ts` con fixture y con el estado de producción (mes sin
  leads); E2E Docker `citas-gerencia.spec.ts`; `revisor-a11y`; Codex LEVEL 2; `/release-crm`.
- Trampa conocida: la meta mensual crece con los leads que entran → la meta de una semana pasada se
  recalcula. Se dice en la ayuda; la Fase 3 la fija.

### Fase 2 — «Día a día» (solo pantalla)
- **Qué se construye:** dentro de la semana elegida, hoja analista × días (lun–sáb, domingo en gris),
  `HojaBase`-style: columnas # y nombre fijas, fila/columna «hoy» resaltada, días por venir plegados.
  Celda = generadas hoy / meta del día (meta mensual ÷ hábiles del mes). Segunda línea: pactadas para
  ese día · realizadas · no asistió (por `vence_en`).
- **Hoy del supervisor:** en «Citas de hoy» una línea «Generadas hoy: N de M» por analista; la columna
  «Citas pendientes hoy» pasa a abrirse (lista de citas del día: `gestion_diaria_citas_fn` o filtro `dia`).
- **Se comprueba:** igual que la Fase 1 + `hoy-supervisor-mando.spec.ts`.

### Fase 3 — El plan escrito del supervisor (servidor, LEVEL 3)
- **Qué se construye:** el supervisor escribe su propio plan semanal (o diario) por analista cuando el
  reparto automático no le sirve (vacaciones, campaña). Tabla `crm.plan_citas_semanal` (solo inserción,
  revisión + `expected_revision`, `negocio_id`, RLS por `vendedor_ids_visibles`, sin DELETE), función de
  escritura supervisor (su subárbol) y gerencia con bloqueo de mes sellado y bitácora; lectura en la
  misma consulta mensual. El reporte compara real vs plan del supervisor vs meta del sistema.
- **Requiere:** plan corto de tablas/RLS → OK de Miguel → `/nueva-migracion` → branch Supabase →
  `auditor-rls` → `test-rls` → advisors → merge; `gen:types`. Cualquier lectura nueva de
  `private.citas_episodios` se registra en las exenciones del censo (y se resella).
- Diferida hasta ver las Fases 1–2 en uso.

## Qué NO cambia
Meta 1,25 interna (no se enseña como «meta» al analista), 70/70, mes y analista del evento, tabla
mensual y ticket, semanas comerciales del CRM, recorte por equipo en servidor, una sola llamada al mes.

## Decisiones pendientes de Miguel (19/10)
1. **Cómo lo hacen hoy los supervisores**: foto/Excel del reporte semanal y diario actual (el vault no
   lo tiene). Si sus semanas son lunes–domingo y no 1–7/8–14…, decidir cuál manda.
2. **Base de la meta**: leads del mes × 1,25 repartidos por hábiles (recomendado; es lo vivo) vs leads
   del mes anterior (como el Excel).
3. **Qué cuenta en el día**: citas **generadas** ese día (recomendado; la meta 1,25 es de generación)
   vs citas que se realizan ese día (eso ya lo cubre el 70 % de entrevistas).
4. **Días hábiles**: lunes–sábado (supuesto) o lunes–viernes.

## Anclas técnicas
- Pantalla: `app/src/components/citas/{resultados.tsx:52, avance.ts, avance-mensual.tsx, modelo.ts,
  senal-resultado.tsx, contexto.ts}`, `app/src/screens/hoy/{supervisor-jornada.tsx, use-datos-citas-gerencia.ts}`,
  `app/src/components/base-gestion/{hoja-base.tsx, panel-analistas.tsx, detalle-cifra.tsx}`,
  `app/src/components/common/tabla.tsx`, `app/src/lib/router.ts:194`.
- Servidor (solo lectura en F1–F2): `20260927172931_crm_citas_supervisor_equipo.sql:186-200`,
  `20260913225755_crm_citas_avance_fuentes.sql`, `20260928044910_crm_gestion_diaria_citas_lista.sql`,
  `20260921040335_crm_gestion_diaria_equipo_vista.sql` (`citas_agendadas`), `20260912151320_crm_citas_consulta_nucleos.sql`
  (`private.citas_episodios`, sin `creado_en`).
- Ojo: `gestion_diaria_citas_fn` no filtra tareas/leads inactivos y Citas sí → cifras de «generadas»
  pueden diferir entre pantallas; la F2 usa el payload de Citas para no abrir una segunda verdad.
- Ejecución: worktree propio desde `main` (el taller está en `crm/conversion-adicional-renovacion-20261014`
  con 329 archivos tocados por otra sesión).

Relacionado: [[Citas Gerencia - analisis del Excel de proyeccion por analista 2026-09-10]],
[[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]],
[[Citas Gerencia - decisiones finales para publicar 2026-09-14]],
[[Citas Gerencia - Supervisión por equipo 2026-09-27]],
[[Citas - validacion de cifras del supervisor Jorge (2026-09-28)]],
[[Hoy supervisor - Facturacion de hoy y accesos directos (2026-10-18)]], [[Fundamentos UX del CRM]].

## Pedido reformulado por Miguel (19/10 ~11:30) y dos propuestas visuales

«Necesitamos un módulo que diga Proyección de citas, y que lleve analista · citas · monto (acumulado
en citas) · % de conversión de citas de ese analista, y dos más que digan de dónde sale esa cita:
clientes o leads; que todo tenga filtro tipo Excel, que abarque toda la pantalla; no quiero textos
explicativos; dame 2 propuestas.»

Pieza local (regla [[piezas-visuales-en-local-no-artifact]]): `ui-playground/proyeccion-citas.html`
(hermana del repo, en `DESARROLLO/ui-playground/`), abierta con `open`. Medidas del CRM (riel 64 px,
hoja 14 px, nombre 16 px, cabecera 13 px, tokens de `index.css`), sin verde, datos de ejemplo con semilla.

- **A · Hoja plana:** solo las columnas pedidas (# · Analista · Equipo · Citas · Monto S/ · Monto US$ ·
  % Conv. · Clientes · Leads) + fila Σ; periodo Mes / S1–S4 / Día; embudo tipo Excel en cada cabecera
  (ordenar, buscar, casillas con conteo o Mín/Máx); chips de filtros activos; todo número abre la lista
  lateral (fecha · persona · estado · monto · origen) con su CSV.
- **B · Hoja con semanas y días:** la misma hoja con pastillas pequeñas arriba, bandas plegables por
  equipo y la columna Citas abierta por semanas comerciales (S1–S4) o por días de la semana elegida
  (domingo gris, hoy resaltado, días por venir atenuados); cabe a 1440 px sin scroll horizontal (medido:
  1338/1338).
- PEN y USD nunca sumados (dos columnas). El % de conversión de la fila Σ es clientes ÷ citas del
  total, no promedio de tasas.

**Decisiones que abre la pieza:** divisor del % de conversión (clientes ÷ citas generadas, ÷ citas con
resultado o ÷ personas entrevistadas como el 70 % vigente) · si la cita se cuenta por fecha de creación
o por fecha pactada · «Clientes» = cita con una persona que ya es cliente (perfil) y «Leads» = el resto.

**Ajustes de Miguel sobre la pieza (19/10 ~11:35):**
- «En el filtro de Clientes quiero el detalle de los clientes»: el embudo de Clientes y el de Leads
  listan las PERSONAS (nombre y n.º de citas, buscador, «Seleccionar todo») y recortan las citas de ese
  origen a las marcadas; el otro origen no se toca; un analista sin citas tras el recorte desaparece.
- «Los montos todo en soles, y en el filtro que seleccione dólares y soles»: una sola columna «Monto S/»
  (dólares al TC del día, ejemplo 3,751 como en Facturación); su embudo trae las casillas Soles (n · S/
  total) y Dólares (n · US$ total) más Mín/Máx en soles. La lista lateral muestra el original y su
  equivalente en soles; el CSV lleva ambas columnas.

## Decisiones de Miguel (19/10 11:44, hora de `date`) — «así me gusta»

- **Propuesta elegida: B** (hoja con pastillas, equipos plegables y Citas por semanas / días).
- **Dos tasas, no una:** «% Entrevistas» = entrevistas (citas realizadas) ÷ citas, y «% Conversión» =
  clientes ÷ entrevistas. «En base a eso debo ver un proyectado final».
- **Proyectado S/** (nueva columna y pastilla): citas esperadas al cierre del periodo (ritmo de los días
  transcurridos, nunca menos que las citas ya puestas) × % entrevistas × % conversión × monto medio por
  cita en soles. El total suma los proyectados con base; no promedia tasas.
- **Clientes** = cita con una persona que ya es cliente; **Leads** = cita con prospecto.
- Montos todo en soles (US$ al TC del día); embudo de Monto con casillas Soles/Dólares + rango.
- Vista por días cabe a 1440 px (medido 1338/1338) apretando celdas solo en esa vista.

## Plan de construcción (v2, pedido 19/10 ~11:47, escrito 11:51: «todo el plan por fases y subfases, verifica el backend, dónde va»)

**Dónde va:** Citas → cuarta pestaña **«Proyección»**, al lado de Resultados (`propuesta.tsx:24-28`
`VISTAS`), misma consulta y filtros; la hoja ocupa todo el ancho. Ruta `#/reuniones` con la vista.

**Verificación de conexiones con el servidor (lector `private.citas_gerencia_consulta`,
`20260913225755…:113-132`, gate de rol `20260927172931…:101-108`):**

| Dato de la hoja | De dónde sale | Estado |
|---|---|---|
| Analista / equipo | `analista_id` (= dueño actual de la tarea), `supervisor_id` | ✅ |
| Citas por mes / semana / día | `creado_en` y `vence_en` por cita; la RPC solo admite mes completo y la pantalla recorta (ya lo hace) | ✅ |
| Monto | `monto_estimado` + `moneda` por cita | ✅ |
| Todo en soles | `useTipoCambio` + `usdAPen` (ya lo usa la tabla mensual) | ✅ |
| Entrevista | `estado_comercial='realizada'` / `asistencia_registrada_en` | ✅ |
| Conversión de la entrevista | `conversiones[]` (lead, `convertido_en`) con entrevista anterior a la conversión (regla de `avance.ts` vinculados) | ✅ |
| **Cliente vs lead** | el servidor solo cuenta `citas_clientes` (tareas con `perfil_id`); **no marca cada cita** | ⚠️ Fase 0 |
| Citas con cliente sin lead | hoy no entran en Citas (el historial exige lead) | decisión: fuera, como hoy |
| Supervisor ve su equipo | `vendedor_ids_visibles` en servidor | ✅ |
| Volumen / refresco | tope 10 000 citas/mes (54000) · 60 s · sin RPC nueva | ✅ |

**Fase 0 · Servidor: la marca «es cliente» en cada cita** (LEVEL 3, pequeña)
- 0.1 Migración: `'es_cliente', t.perfil_id is not null` (y `perfil_id`) en `v_filas` del lector v1 y v2
  (`20261016233037`), con la receta de `20260927172931` (lock de exenciones, huella md5 previa,
  reemplazo anclado único, re-sello del censo).
- 0.2 Branch Supabase → `auditor-rls` → `test-rls` → advisors; paridad del payload (idéntico salvo el campo).
- 0.3 Merge, `gen:types`, esquema del front (`data/citas-gerencia.ts:20-26`) acepta el campo (opcional
  mientras el servidor viejo no lo mande).

**Fase 1 · La hoja del mes** (solo pantalla)
- 1.1 Pestaña «Proyección» y marco a todo el ancho; respeta Supervisor/Analista/Mes/Semana de arriba.
- 1.2 Cálculo `components/citas/proyeccion.ts` (cohorte por fecha de generación): citas, monto S/,
  % entrevistas, % conversión, proyectado por ritmo, clientes, leads, Σ sin promediar tasas. Tests:
  mes lleno, mes vacío (estado de producción), sin TC, mes cerrado, analista sin citas.
- 1.3 Hoja: # y Analista fijos, pastillas, bandas por equipo plegables, semáforo azul/ámbar/rojo/gris,
  todo número abre la lista lateral (`Sheet`), CSV.
- 1.4 Embudos tipo Excel por cabecera: ordenar; texto con casillas; Clientes/Leads con personas y
  buscador; Monto con Soles/Dólares + rango; chips de filtros activos; Limpiar.
- 1.5 `npm run check`, E2E Docker (spec nuevo `citas-proyeccion.spec.ts`), `revisor-a11y`, Codex LEVEL 2,
  `/release-crm`, nota en el vault.

**Fase 2 · Semanas y días** (solo pantalla)
- 2.1 Botón Mes / Semanas / Días: columnas de tiempo (semanas comerciales; días con hoy y domingo);
  proyectado del periodo visible.
- 2.2 Enlaces: «Citas de hoy» del Hoy del supervisor → Proyección en Días; URL con la vista.
- 2.3 Verificación y release como 1.5.

**Fase 3 · Remate**
- 3.1 Celular: tarjetas por analista agrupadas por equipo, cada cifra botón.
- 3.2 Exportación completa (hoja + detalle) y párrafo en la Ayuda existente (nada en pantalla).
- 3.3 Archivar la pieza del laboratorio; cierre en el vault.

**Decisiones tomadas (objetar si no):** la cita cuenta el día que el analista la GENERÓ (`creado_en`), y
sus entrevistas y clientes siguen a esa cita (cohorte) · semanas comerciales 1–7/8–14/15–21/22–fin ·
analista = dueño actual de la tarea, como en Resultados · TC del día, como la tabla mensual · citas de
clientes sin lead quedan fuera, como hoy.

## Ejecución (DALE de Miguel 19/10 ~11:55: «siempre ayúdate con Codex»)

- Worktree propio `/Users/usuario/dev/avancecorp-crm-proyeccion-citas` (rama `crm/proyeccion-citas-20261019`)
  desde `avancecorp/main` `6479402d` (el `main` local `6ace3d44` está detrás y lo tiene en uso otro worktree:
  no se tocó). `node_modules` clonado con APFS.
- **Decisiones nuevas de Miguel (12:00–12:20):** columna «Ticket S/» (monto ÷ citas, el que usa el
  proyectado) · origen en TRES columnas: Referidos (lead `origen='referido'`) · Clientes (ya era cliente)
  · Leads · el proyectado usa ese ticket promedio.
- **Medido en producción (solo lectura):** desde agosto 1 139 citas, 0 con cliente (ninguna tarea
  `reunion` con `perfil_id`; ningún lead con persona ya convertida antes); octubre: 608 citas, 13
  referidos, 70 de leads con persona (convertidos DESPUÉS de la cita); la lógica de la auxiliar en
  línea tarda 151 ms.
- **Fase 0 escrita:** `20261019170214_crm_citas_es_cliente_por_cita.sql` (auxiliar
  `private.cita_con_cliente(uuid,timestamptz)` INVOKER solo postgres + reemplazo anclado único en los
  dos lectores + re-declaración de huellas + re-sello + postflight con `assert_analitica_leads_citas`).
  Ledger actualizado (pendiente de branch). Auditor RLS y Codex (encargo
  `docs/encargos/2026-10-19-codex-citas-es-cliente.md`) en curso; rama Supabase
  `proyeccion-citas-es-cliente-20261019` (`qrdqmlrxwvjebxhazcip`) creándose. **No se instala en
  producción sin enseñar el SQL a Miguel.**
- **Fase 1 en curso** (agente implementador en el worktree): pestaña «Proyección», `proyeccion.ts`,
  hoja, embudos, lista lateral, CSV, tests, E2E.

### Fase 0 — ensayada (19/10, 12:40)
- Revisiones: auditor RLS y Codex (CHANGES_REQUESTED las dos; todo aceptado). Hallazgo clave del auditor,
  confirmado en producción: `assert_analitica_leads_citas()` está en ROJO por 9 piezas ajenas → la
  migración usa la FOTO del censo (patrón 20261017043000) y no llama al guardián.
- Definición cerrada por el PRIMARY tras Codex: «ya era cliente» = conversión/cierre externo anterior a la
  cita y VIGENTE HOY (anulación posterior la quita; igual que la venta). `convertido_en = creado_en` → no.
- La rama de Supabase murió (MIGRATIONS_FAILED, como siempre aquí; borrada). Banco Docker PROPIO
  `crm-banco-proyeccion-citas-20261019` (127.0.0.1:55511) con `supabase db dump --linked`: paridad al
  byte de lectores y auxiliares; censo sembrado (46 exenciones + sello + tope + 15 F7) con el sello
  real. Scripts en el scratchpad de la sesión (`banco/`): `banco-up.sh`, `banco-cargar.sh`,
  `semilla-censo.sql`, `prueba-es-cliente.sql`, `bpsql`.
- Resultados: migración aplicada limpia (un solo mensaje); 11/11 casos de la auxiliar; lector v1 y lector
  de cortes devuelven `es_cliente` correcto con fixtures; coste real 507 ms/609 citas (pg_temp en prod,
  deshecho); reversión `supabase/scripts/revertir-20261019170214-citas-es-cliente.sql` ensayada: md5 y
  sello de producción restaurados.
- Segunda pasada de Codex con la evidencia nueva en curso. **Instalación en producción: solo con el OK de
  Miguel y por su `!`** (`supabase db query --linked --file supabase/migrations/20261019170214_crm_citas_es_cliente_por_cita.sql`
  desde `CRM-Avance-Corp`, un solo mensaje), después `gen:types`.
- **12:50 — Fase 0 LISTA PARA INSTALAR** (segunda pasada de Codex atendida: enlace vivo primero, md5 final
  verificado en el postflight, reversión con comprobación de sello y ensayo negativo, puerta v2 con corte
  existente OK). Commit en el worktree `crm/proyeccion-citas-20261019`. Instalación: Miguel con `!`:
  `cd CRM-Avance-Corp && supabase db query --linked --file supabase/migrations/20261019170214_crm_citas_es_cliente_por_cita.sql`
  (desde el worktree o tras fusionar); luego `cd app && npm run gen:types`.

### Cambio de plan (Miguel, 19/10 ~13:00): periodo por RANGO de fechas
«Necesito poder seleccionar rangos de fechas, no un día en específico». En «Proyección» el periodo es
**Desde – Hasta** (control propio de la pestaña, validado, tope 6 meses) con atajos Hoy · Esta semana ·
Mes · Mes pasado · S1–S4. La cohorte = citas generadas dentro del rango; los filtros Supervisor/Analista
de arriba se respetan, `semana`/`dia` de arriba no aplican aquí. Si el rango cruza meses, la pantalla
carga cada mes (el servidor sigue entregando meses completos) y fusiona (dedupe por lead). Proyectado
sobre el rango. La Fase 2 (Semanas/Días como columnas) se abre sobre el rango elegido.

### Fase 1 — construida (19/10, 13:38)
- Pestaña «Proyección» en Citas (commit en el worktree): hoja por analista con las 10 columnas, bandas por
  equipo, pastillas, Σ, embudos Excel, lista lateral por número, CSV, rango Desde–Hasta con atajos y
  carga multi-mes fusionada; `es_cliente` opcional con respaldo. Archivos nuevos
  `app/src/components/citas/proyeccion*.{ts,tsx,css}` (+ tests) y `app/e2e/citas-proyeccion.spec.ts`.
- Verificación del PRIMARY: `npm run check` PASS (460 archivos / 7 351 pruebas, cobertura sobre umbrales,
  build, jscpd 0,74 %); `revisor-a11y` sin P0/P1 (P2 aplicados por el implementador); visto en el navegador
  (demo, puerto 5181). E2E Docker (3 specs) y Codex (LEVEL 2) en curso.
- Riesgo descartado por lectura del SQL: una cita creada en el rango pero agendada para el mes siguiente SÍ
  llega (el historial del lector cubre todas las tareas de los leads de la cohorte, y la cohorte incluye
  «citas generadas en el mes aunque su fecha prevista esté en otro mes»).
- **13:44 — Fase 1 revisada.** E2E Docker 9/9 + 1 intermitente (carrera prueba-lista lateral/embudo: la prueba
  ahora espera el cierre; 3 repeticiones sin reintentos 6/6). Codex (front, LEVEL 2, sin acceso al árbol:
  revisó el diff): P2 aceptado y corregido — la pestaña ya no depende de la carga/error del mes de arriba
  cuando tiene cargador propio (test de integración nuevo); «sin entrevistas» → proyectado 0. Riesgo
  aceptado: un séptimo mes (el de arriba) puede seguir refrescando cada 60 s fuera del rango. Tres commits
  en `crm/proyeccion-citas-20261019`. Check final y E2E finales corriendo; después, PR a `avancecorp/main`
  y `/release-crm` (lo invoca Miguel).
- **13:47 — PR #337 abierta** (`avanza-digital/avancecorp-crm`, rama `crm/proyeccion-citas-20261019`, 3 commits;
  fusionar con merge commit). Check final 7 352 pruebas PASS; E2E 19/19 sin reintentos. Pendiente de Miguel:
  (1) instalar la Fase 0 con sus dos líneas `!`; (2) fusionar la PR; (3) `/release-crm`. Después: traer
  `avancecorp/main` al `main` local (lo tiene otro worktree), `gen:types`, borrar el banco Docker
  `crm-banco-proyeccion-citas-20261019` y el worktree. Fase 2 (semanas/días sobre el rango) y Fase 3
  (celular, acceso desde Hoy, ayuda) siguen pendientes.
- **13:47–14:07 — Fase 0 INSTALADA EN PRODUCCIÓN** por Miguel (`!`, desde el worktree). Verificado por consulta:
  auxiliar existe, md5 de los lectores = los ensayados (`676f078a…` / `387c8f36…`), sello cuadra, censo
  47/9 intacto. Falta la línea de registro (`migration repair --status applied 20261019170214 --linked`).
- **~14:09 — Fase 0 REGISTRADA** en `supabase_migrations.schema_migrations` (`migration repair`, Miguel). Fase 0
  cerrada: instalada, verificada y registrada. Tipos del front sin cambios (`gen:types`). Siguen: fusionar #337
  y `/release-crm`.
- **15:23 — PR #337 FUSIONADA** por Miguel con merge commit (`bc7ad4fb`), sobre `6479402d` (#336).
- **15:24–15:33 — `/release-crm` (Miguel) → FASE 1 EN PRODUCCIÓN.** `main` local ← `avancecorp/main` por
  fast-forward (`6ace3d44` → `bc7ad4fb`; el worktree `/private/tmp/crm-citas-fecha-comercial-20261017` lo tenía
  en uso y estaba limpio). Build en el worktree limpio `~/dev/avancecorp-wt/texto-adicional-renovacion-20261016`
  movido a `bc7ad4fb` con `npm ci`: `npm run check` PASS (460 archivos / 7 352 pruebas, build, bundle, dup);
  artefacto `crm-20261019T202847Z-bc7ad4fb4080` (sha256 `d3e6b667…835a`, 167 archivos; copia del ZIP y el
  manifiesto en `releases/` del taller); `release:crm:verify` OK; preflight OK (vivo `6479402d` ⊂ candidato).
  Frente al vivo solo crecen `gerencia-*` (95 → 225 KB, la pestaña) y `ui-vendor` (+1,1 KB, el icono); los
  demás chunks conservan su tamaño (solo cambia el hash en cascada); `data-vendor` idéntico. Publicado con
  el MCP de Hostinger (`hosting_deploy-static-website`, conectó a la primera con `@hostinger/mcp@3.1.0`)
  ~15:29; `version.json` vivo `build-20261019T202846524Z` a las 15:29:51; home 200; `index.html` e
  `index-C827lOrm.js` idénticos al dist; humo 154/167 (12 PNG recomprimidos por la CDN + `.htaccess` 403).
- **15:33 — Limpieza.** Banco Docker `crm-banco-proyeccion-citas-20261019` (contenedor y volumen) retirado;
  worktree `~/dev/avancecorp-crm-proyeccion-citas` retirado; rama `crm/proyeccion-citas-20261019` borrada en
  local y en GitHub. `main` = `avancecorp/main` = `bc7ad4fb` = VIVO. Quedan: Fase 2 (semanas/días como
  columnas sobre el rango, enlaces desde Hoy del supervisor) y Fase 3 (celular en tarjetas, exportación
  completa, párrafo en Ayuda: «Cómo usar Citas» aún dice «las tres vistas»).

### Fase 2 — en curso (19/10, «dale con la fase 2»; ~15:50 «todo lo que se pueda en paralelo con agentes»)
- Worktree nuevo `~/dev/avancecorp-crm-proyeccion-f2` (rama `crm/proyeccion-citas-f2-20261019`, base `bc7ad4fb` = vivo).
- **Ajustes de Miguel sobre lo publicado (capturas 15:41–15:44):**
  1. Fuera la fila de pastillas de totales («están de más»): la fila Σ ya da esos totales y abre sus listas.
     «Exportar CSV» pasa a la barra del periodo; «Reintentar TC» solo cuando falta.
  2. Fuera las bandas por equipo («me separa mucho el título de la columna, visualmente confunde»): hoja
     plana, orden global, # continuo.
  3. En Proyección los filtros de arriba no sirven («o los reutilizamos o los eliminamos»): se ocultan
     (`Filtros`, «Exportar citas», «Citas: …»); se reutiliza el selector Supervisor dentro de la barra de la
     Proyección; el analista se filtra con el embudo de su columna; búsqueda y analista de arriba dejan de
     aplicar en esta pestaña.
- **Fase 2 propiamente:** selector Mes · Semanas · Días; columnas de tiempo antes de «Citas» (semanas
  comerciales recortadas al rango; días con hoy, domingo y futuro; Días hasta 31 días); cada celda abre su
  lista; CSV con los tramos. Enlace por URL `#/reuniones/proyeccion/<desde>/<hasta>[/semanas|dias][/equipo/<id>]`
  y el título «Citas de hoy» de Hoy del supervisor abre la Proyección del mes en Días (la Agenda del día
  sigue en «Ver citas del equipo»).
- Reparto: dos agentes en paralelo con archivos separados (pantalla · enlace/Hoy); el coordinador integra,
  corre `npm run check`, E2E en Docker y Codex.

### Auditoría de consistencia de datos (19/10, terminó 16:20 aprox., agente de solo lectura en producción; pedido de Miguel: «no puede haber data distinta»)
- **Base ↔ Proyección: CONSISTENTE.** SQL directo contra tablas = lector de Gerencia pasado por `calcularProyeccion`,
  al 100 % en 1–7, 1–19, 1–31 oct y 25 set–19 oct (81 filas, 0 diferencias en citas, realizadas, PEN, USD,
  referidos, clientes, leads; mismas ids). La fusión multi-mes no pierde ni duplica (dedupe por id de cita).
  Citas 1–19 oct: 625 = «Citas» de Resultados (también por creación).
- **Misma palabra, otra cifra (INCONSISTENTE) y decisión:**
  - «Citas de hoy» (Hoy del supervisor) cuenta citas PREVISTAS hoy; la columna de hoy en Días cuenta citas CREADAS
    (p. ej. 17 vs 10): **se quitó el enlace del título a la Proyección** (el enlace por URL sigue existiendo).
  - % Entrev.: la Proyección dividía por TODAS las citas (14,1 %) y Resultados por las RESUELTAS (realizada +
    no asistió, 26,9 %); además infravaloraba el proyectado → **se alinea a la base de Resultados**.
  - % Conv.: la Proyección vinculaba por `convertido_en` (25 personas); Resultados por fecha comercial ≥ día de la
    entrevista (17) → **se alinea a la regla de Resultados** (`entrevistaCompatibleConVenta`).
  - «Ticket» de la Proyección (monto estimado ÷ citas) vs «Ticket del mes» de Resultados (capital ÷ clientes) →
    **se renombra a «Ticket cita S/»**.
  - **Pendiente de Miguel:** «Clientes» = 0 porque el lector de Citas solo trae citas con lead; hay 37 reuniones de
    octubre con clientes SIN lead (sección «Citas de clientes»). Incluirlas = cambio de servidor (LEVEL 3) o
    renombrar. Gestión Diaria «Citas agendadas» hoy también las cuenta (46 vs 42).
  - **Pendiente de Miguel:** «Proyectado S/» (citas × tasas × ticket estimado) convive con «Cierre proyectado» de
    Resultados (otra fórmula).
  - Hallazgos aparte: 5 ventas con fecha comercial anterior al día de su entrevista (datos); en Resultados el
    «Cierre proyectado» total (S/ 4,54 M) queda por debajo del capital ya cerrado (S/ 4,78 M).
- Borrador de invariantes del auditor → prueba `proyeccion-invariantes.test.ts` (incluye igualdad con Resultados).
- **Decisiones de Miguel (19/10 16:25 aprox., tras la auditoría):** (1) las reuniones con clientes SIN lead
  **se incluyen** en la Proyección; (2) «Proyectado S/» **se renombra a «Proyectado citas S/»**.
- **Fase 0b (servidor, LEVEL 3), separada de la PR de la Fase 2:** lector NUEVO y propio
  `crm.citas_clientes_proyeccion_fn(date,date)` → `private.citas_clientes_proyeccion` (reuniones con perfil o
  inversionista y sin lead, por fecha de CREACIÓN, misma visibilidad que `citas_clientes_core`, misma atribución
  que el lector de Citas). NO se toca el lector compartido: Resultados, Agenda y Bandeja no cambian. Lo instala
  Miguel con `!`. Luego la pantalla las fusiona como origen «Cliente».
- **Regla de tasas con clientes dentro (propuesta del coordinador):** cuentan en Citas, Clientes, columnas de
  tiempo y % Entrev. (una asistencia es entrevista, como en Gestión Diaria); NO en la base de % Conv. ni en el
  Proyectado (un cliente no se «convierte»): esos se calculan sobre prospectos (Referidos + Leads), alineados con
  Resultados.
- **16:47 — Codex Fase 2 (LEVEL 2): CHANGES_REQUESTED, 2 aceptados.** P1: la venta convertía la fila del analista
  equivocado (Resultados exige que la venta sea del dueño de la fila y, en el total, que su dueño esté en el ámbito)
  → regla compartida en `app/src/components/citas/atribucion.ts`, usada por `avance.ts` (sin cambiar su resultado)
  y `proyeccion.ts`; 4 contraejemplos contra `calcularAvanceCitas` real y 5 mutantes muertos. P2: al entrar en
  Proyección desde un enlace de Agenda o sin enlace la URL no la describía → ahora siempre la escribe (mutante muerto).
  Rechazado con evidencia: «una cita creada en el rango y prevista fuera podría faltar» (la auditoría midió en
  producción 100 % de coincidencia SQL directo ↔ lector).
- **17:35 aprox. — Fase 0b ensayada:** `20261019213516_crm_citas_clientes_proyeccion.sql` (lector nuevo), banco Docker
  propio `crm-banco-proyeccion-0b-20261019` (48/48 casos, 7/7 mutantes, reversión ×2, censo idéntico), auditor-rls
  sin P0/P1; producción (solo lectura): 37 reuniones con clientes sin lead creadas 1–19 oct (Jorge 22, Carmen 15),
  190–540 ms. Codex LEVEL 3 en curso. Instalación: Miguel con `!` (dos líneas en el ledger).
- Commits en `crm/proyeccion-citas-f2-20261019`: `d3599519` (Fase 2), `00c32abb` (0b, sin aplicar), `4c53307d`
  (merge de `avancecorp/main` con #338/#339; conflicto solo en el ledger, resuelto conservando las dos entradas).
- **17:40 — verificación final** sobre `4c53307d`: `npm run check` PASS (7 414 pruebas), E2E Docker 85/85.
- **18:03 — PR #340** (solo pantalla, rama `crm/proyeccion-citas-f2-pantalla` = `d3599519`, fusión limpia con
  `avancecorp/main`): https://github.com/avanza-digital/avancecorp-crm/pull/340 — fusionar con merge commit y
  `/release-crm`.
- **Codex 0b (LEVEL 3): CHANGES_REQUESTED, sin fugas.** Aceptados: preflight por identidad completa
  (`md5(pg_get_functiondef)` + dueño + ACL; un `STRICT` en `gestiones_validar` desactivaba la validación sin cambiar
  `md5(prosrc)`), corte de la cohorte en `creado_en <= generado_en`, batería que falle de verdad. Como la 0b ya está
  commiteada, va una migración de ENMIENDA nueva (en curso); PR aparte con las cuatro líneas `!`.
- **18:10 aprox. — Enmienda 0b lista:** `20261019224227_crm_citas_clientes_proyeccion_corte.sql` (commit `ecd958ee`):
  preflight por identidad completa (7 dependencias + la 0b tal como se commiteó), corte `creado_en <= generado_en`,
  batería 53/53 que falla de verdad, 9/9 mutantes (incluido el STRICT de Codex), dos sesiones reales, reversiones.
  `tareas_un_solo_sujeto` impide una reunión con lead y cliente a la vez (23514). **Riesgo de coste aceptado:** con
  clientes de tipo PERFIL la identidad compartida cuesta ~6 ms por perfil (más de ~1 000 perfiles distintos en el
  rango → 57014 por el límite de 8 s); hoy producción tiene 0 reuniones con perfil y 39 históricas de persona F6
  (0,68 s por 1 000). Codex segunda pasada en curso.
- Instalación (Miguel, en orden, desde el worktree): 0b, enmienda, y los dos `migration repair`.
- **18:15 — Codex segunda pasada sobre la enmienda: PASS_WITH_NOTES** (sin cambios en SQL ni reversión; P3: el caso del
  corte en la batería del banco depende del calendario; nota: 0b y enmienda no son atómicas, si la enmienda se niega
  hay que revertir la 0b a mano).
- **18:18 — PR #340 FUSIONADA por Miguel** (Fase 2, pantalla). Falta `/release-crm`.
- **PAUSA pedida por Miguel (~18:20).** Estado al pausar: rama `crm/proyeccion-citas-f2-20261019` empujada
  (`1601b604`: 0b `00c32abb` + merge #338/#339 + enmienda `ecd958ee` + docs Codex r2); **PR de la 0b SIN ABRIR**;
  0b y enmienda SIN APLICAR (cuatro líneas `!` en el ledger); banco Docker `crm-banco-proyeccion-0b-20261019`
  (55521) levantado; worktree `~/dev/avancecorp-crm-proyeccion-f2`. Al retomar: `/release-crm` de #340 (si Miguel
  lo pide), abrir PR de la 0b, instalar con `!`, y conectar las reuniones de clientes en la pantalla (regla
  propuesta: cuentan en Citas, Clientes, tiempo y % Entrev.; NO en % Conv. ni Proyectado citas).
- **Retomado («sigue»).** Rama de la 0b al día con `main` (merge `30dbc696`, incluye #340). **PR #341 (borrador)**:
  https://github.com/avanza-digital/avancecorp-crm/pull/341 — servidor 0b + enmienda, con las cuatro líneas `!`
  (se pueden instalar ya: el lector es aditivo y nadie lo llama todavía). Agente conectando esas reuniones en la
  pantalla (se añade a #341). Vivo: `fcf159c0` (la Fase 2 espera `/release-crm`).
- **19:07–19:10 — `/release-crm` (Miguel) → FASE 2 EN PRODUCCIÓN.** `main` local ← `avancecorp/main` (ff a `265efe2a`, #340).
  Build en `~/dev/avancecorp-wt/texto-adicional-renovacion-20261016` (lock sin cambios): `npm run check` PASS (7 400
  pruebas), artefacto `crm-20261020T000859Z-265efe2a43ac` (sha256 `96c3acd4…f372`, copia en `releases/` del taller),
  verify OK, preflight OK sobre `fcf159c0`, publicado con el MCP de Hostinger; `version.json` vivo
  `build-20261020T000858999Z` a las 19:09:34; home 200; `index.html` e `index-B16p4Dyk.js` idénticos; humo 154/167.
- **19:10–19:16 — Fase 0b + enmienda INSTALADAS EN PRODUCCIÓN Y REGISTRADAS** (Miguel, cuatro líneas `!`). Verificado
  (solo lectura): tras la 0b, núcleo `ac59c50f…` y puerta `a9b64034…` = lo commiteado; tras la enmienda, núcleo
  `44006907…` con el corte; ACL `{postgres, authenticated}`; las dos versiones en `schema_migrations`; llamada real
  como Gerencia (deshecha): 37 reuniones 1–19 oct, 19 completadas, 2 supervisores, 0 después del corte. Ledger
  actualizado (`63f777ee`). Falta: pantalla (agente en curso), `gen:types` y quitar el cast, check/E2E, fusionar #341
  y `/release-crm`.
- **Pantalla de la 0b (agente + coordinador):** la Proyección suma las reuniones con clientes sin lead (Citas, Clientes,
  tiempo, % Entrev.; no Monto, Ticket cita, % Conv. ni Proyectado citas). `gen:types` tras instalar y sin cast.
  Codex pantalla: REQUEST_CHANGES, 3 aceptados con prueba y mutante (cargador siempre presente en sesión real;
  «Actualizar» relee todo; rango grande sin refresco por foco/conexión). Codex sobre el Proyectado: usar la tasa de
  entrevistas con lead es defendible; conviene explicarlo en la Ayuda (Fase 3).
- **Verificación final** (`c9322fbb`): `npm run check` PASS (7 452); E2E 85/86 con un fallo intermitente de la
  prueba (foco tardío de la lista lateral al abrir un embudo) → la prueba espera el foco; repetido 8×: 32/32.
- **PR #341 lista para fusionar** (fuera de borrador, MERGEABLE): https://github.com/avanza-digital/avancecorp-crm/pull/341
  → Miguel: «Create a merge commit» y `/release-crm`.
- Queda Fase 3: celular en tarjetas, exportación completa, Ayuda («Cómo usar Citas» dice «las tres vistas»; explicar
  Ticket cita y Proyectado citas), archivar la pieza del laboratorio; limpieza del banco `crm-banco-proyeccion-0b-20261019`
  y del worktree tras publicar.
- **20:18 — PR #341 fusionada** (por squash: `c01b6d23`). **20:18–20:22 — `/release-crm` → FASE 0b EN PRODUCCIÓN.**
  `main` local ← `avancecorp/main` (ff). Build en el worktree de release (lock igual): check PASS (7 452), artefacto
  `crm-20261020T012024Z-c01b6d231fac` (sha256 `822b959a…be7d`), verify OK, preflight OK sobre `265efe2a`, MCP de
  Hostinger; vivo `build-20261020T012024007Z` a las 20:21:20; home 200; `index.html` e `index-D3ONr-rG.js` idénticos;
  humo 154/167.
- **Limpieza (20:23):** banco `crm-banco-proyeccion-0b-20261019` y volúmenes E2E propios borrados; worktree
  `~/dev/avancecorp-crm-proyeccion-f2` retirado; ramas `crm/proyeccion-citas-f2-*` borradas en local y GitHub (el árbol
  de la rama final es idéntico a `c01b6d23`: nada perdido pese al squash).
- **Estado:** F0, F1, F2 y 0b en producción. **Siguiente: Fase 3** (celular en tarjetas, exportación completa, Ayuda
  —«las tres vistas» y explicar Ticket cita y Proyectado citas—, archivar la pieza del laboratorio).

### Fase 3 — ✅ EN PRODUCCIÓN 19/10 22:58 (pedida con «dale con la fase 3»)
- Worktree `~/dev/avancecorp-crm-proyeccion-f3` (rama `crm/proyeccion-citas-f3-20261019`, base `c01b6d23` = vivo).
- **3.1 Celular en tarjetas + 3.2 Exportar (hoja por analista / citas del periodo):** agente en curso.
- **Ayuda «Cómo usar Citas» (coordinador):** «las tres vistas» → «Bandeja, Agenda y Resultados»; viñeta de Proyección en el
  paso 4; paso nuevo «5. Lee la Proyección» (periodo propio, cuenta por creación e incluye reuniones con clientes sin
  lead; Semanas/Días; definición de Monto S/, Ticket cita S/ —no es el «Ticket del mes»—, % Entrev., % Conv., Proyectado
  citas S/ —no es el «Cierre proyectado»—, Referidos/Clientes/Leads); el paso de exportar menciona el menú de la
  Proyección.
- **3.3 Pieza del laboratorio archivada:** `ui-playground/proyeccion-citas.html` →
  `ui-playground/_archivo/2026-10-19-proyeccion-citas-PUBLICADA.html` (movida, no borrada).
- **Agente F3 terminado:** tarjetas en el celular (Total primero; orden y embudos de la hoja vía «Ordenar por» y
  «Filtros»; tramos en fila desplazable dentro de la tarjeta), «Exportar» con «Hoja por analista» y «Citas del periodo»,
  embudo que se abre hacia arriba si no cabe. Coordinador: etiquetas de tarjeta a 14 px.
- **Codex F3 (LEVEL 2): REQUEST_CHANGES, 2 aceptados:** Ticket cita y Proyectado citas no abrían lista aunque la Ayuda
  decía «cada número abre su lista» → ahora abren su base («Citas con lead»); detalle de tramos 13 → 14 px. Prueba nueva:
  «Citas del periodo» = unión exacta de las filas visibles con embudos combinados.
- **21:06 — verificación final** (`8da7d506`): `npm run check` PASS (7 459), E2E Docker 86/86.
- **PR #342:** https://github.com/avanza-digital/avancecorp-crm/pull/342 → Miguel: fusionar y `/release-crm`.
- Fuera de alcance (anotado): la lista lateral en el celular sigue siendo la tabla de escritorio.
- **22:58 — EN PRODUCCIÓN** (`/release-crm` de Miguel): #342 fusionada por SQUASH como `a980bb71` (árbol idéntico a
  `8da7d506`); `main` = `avancecorp/main` = `a980bb71`. Check en el worktree de release 7 459 PASS; artefacto
  `crm-20261020T035800Z-a980bb719bde` (sha256 `b4ff431e…7f59`); preflight OK sobre `c01b6d23`;
  `build-20261020T035759531Z` vivo; humo 154/167 (12 PNG de la CDN + `.htaccess` 403), `index-CqtHOqKz.js` igual al dist.
- **Limpieza (23:00):** worktree `~/dev/avancecorp-crm-proyeccion-f3` retirado, volumen E2E `crm-e2e-proyf3-1019-nm`
  borrado, rama `crm/proyeccion-citas-f3-20261019` borrada en local y en GitHub.
- **Estado:** F0, F1, F2, 0b y F3 en producción. El plan queda CERRADO. Mejora posible, no pedida: la lista lateral
  en el celular como tarjetas.

### Lista lateral sin deslizar de lado — PR #343 (20/10 00:04)
- Pedido: Miguel vio en local que la lista lateral del celular era la tabla de escritorio (892 px en 358) → «sí» a tarjetas;
  luego «sí» a ensanchar también en escritorio (Monto y Origen cortados en el panel de 760 px). «Hazlo bien, no quiero deudas técnicas.»
- Hecho: < 1 080 px la lista usa tarjetas (nombre 16 px, detalle 14 px, origen junto al nombre); ≥ 1 080 px panel de 980 px con las
  7 columnas; nombre sin espacios, estado largo («Cancelada por sistema») y millones en dólares parten línea en vez de desbordar.
  Fila y tarjeta comparten las piezas de cada dato. Ayuda: «la hoja y sus listas se muestran en tarjetas».
- Codex r1: 2 aceptados (44 px de ancho al tacto; orden exacto en la prueba). r2: 1 aceptado (desborde con contenido extremo).
- Verificación: check 7 461 PASS; E2E completo en Docker 478 pasadas / 26 omitidas; mutante (tabla en el celular) mata 3 pruebas.
- ✅ Publicada el 20/10/2026 a las 09:53 (commit `c7c150f3`, build `build-20261020T060525358Z`): humo 154/167 y el `index` vivo coincide con el build. Worktree, volumen y rama borrados.


### % Entrev. y % Conv. iguales a Resultados — PR #346 (20/10/2026)

- Miguel vio a ALAN YUTRONIC con 15,0 % de entrevistas en Resultados de octubre y 11,3 % en la Proyección 1–20 oct.
- Causa: la Proyección calculaba las tasas con las citas **creadas** en el rango; Resultados, con las citas cuyo **resultado** ocurrió en el mes (27 resultados de octubre de Alan eran de citas creadas en septiembre).
- Decisión de Miguel: las dos tasas de la Proyección son las de Resultados. Citas, Monto, Ticket cita y columnas de tiempo siguen por fecha de creación. Las reuniones con clientes sin lead dejan de contar en % Entrev.
- Cómo se evita que vuelva a pasar: un solo cálculo (`citas/resultados-periodo.ts`) que usan Resultados y la Proyección.
- Verificado con los datos reales de Alan: 15,0 % en las dos pestañas.
- Lección: las pruebas de paridad deben usar citas que se crean en un mes y se resuelven en otro; con fechas iguales no se ve la diferencia.
- ✅ Publicada el 20/10/2026 a las 13:17 (commit `4086bbf0`, build `build-20261020T181717473Z`).
- Guía PDF para supervisores: `ui-playground/guia-proyeccion-supervisores/Guia-Proyeccion-de-citas-supervisores.pdf`.
