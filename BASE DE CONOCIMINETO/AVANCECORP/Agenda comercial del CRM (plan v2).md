---
tags: [crm, agenda, plan, diseño, tareas, 2026-07-18]
actualizado: 2026-07-18
---

# Agenda comercial del CRM — plan v2 (contrastado contra el código real)

Versión mejorada de `CRM-Avance-Corp/agenda-comercial-plan.md` (el original queda intacto como referencia). La idea central del original **se conserva entera**: la agenda no es un calendario, es un **motor de próxima acción** — ningún lead activo sin una acción futura agendada. Lo que cambia es todo lo que el original asumía sobre el terreno y el terreno desmiente.

> Método: recon con 5 lectores de código en paralelo → redacción → verificación adversarial (10/10 afirmaciones factuales confirmadas contra el código con archivo:línea) → panel de diseño (12 hallazgos, todos integrados abajo: FK dual lead/cliente, triggers de coherencia, cierre atómico por RPC, reagenda post no-show, y correcciones de fases).

## Qué cambia respecto al original (y por qué)

### 1. "Una sola tabla `actividades`" NO puede ser — y no es el error que el original teme
El original (§2, §6, §8) propone una tabla `actividades` única como fuente de HOY y Agenda. Pero **`crm.actividades` ya existe en producción y es un log INMUTABLE del pasado**:

- Grants de `authenticated`: solo `SELECT + INSERT` (cimientos `:538`); RLS sin policy de UPDATE/DELETE (`:502` — "SIN UPDATE ni DELETE: log inmutable").
- CHECK cerrado de 9 tipos **en pasado** (`llamada_realizada`, `whatsapp_enviado`…); 3 automáticos vetados al cliente API.
- Su auditoría (`trg_audit_actividades`) solo cubre INSERT: un UPDATE no dejaría rastro.
- El índice `actividades_contacto_episodio_idx` del ledger 0C usa los tipos de contacto como señal de **SLA real** — meter filas "futuras" ahí contaminaría la métrica.

**Arquitectura correcta: dos tablas con roles distintos, no dos fuentes de verdad.**

| | `crm.tareas` (NUEVA) | `crm.actividades` (existe) |
|---|---|---|
| Tiempo | Futuro | Pasado |
| Mutabilidad | Mutable (estado, fecha) | Inmutable (INSERT-only) |
| Pregunta | "¿Qué me toca hacer?" | "¿Qué pasó?" |
| Quién la puebla | El vendedor planificando | El cierre de cada tarea + triggers |

**Completar una tarea = insertar su resultado en `actividades`** (el flujo que YA existe en el botón Llamar: `DialogResultado` → `registrarActividad` → INSERT `llamada_realizada`/`llamada_no_contestada`). La regla de una sola fuente sigue viva donde importa: **HOY y Agenda leen las dos la misma `crm.tareas`**.

### 2. Estados: 4 guardados, no 6 — "vencida" se DERIVA, nunca se guarda
El original propone `pendiente · completada · vencida · reprogramada · cancelada · no-show`. Dos de esos no deben ser estados:

- **`vencida` = derivada** (`estado='pendiente' AND vence_en < now()`). Guardarla exige un cron que barra filas y produce drift; derivarla es un WHERE. El CRM ya tiene el patrón: `useAhora()` (tick por minuto + focus) alimenta comparaciones vivas.
- **`reprogramada` no es un estado, es una edición** de `vence_en` (con contador `reprogramaciones` para la métrica del manager). Un estado "reprogramada" rompe la pregunta básica "¿está viva o cerrada?".

Máquina mínima: `pendiente` (única viva) → `completada` | `cancelada` | `no_show`. Los 6 conceptos del original sobreviven; solo que dos son consultas, no columnas.

**Reagendar tras un no-show NO revive la tarea**: crea una tarea nueva encadenada (`reagendada_de`). Así el no-show queda como fila cerrada (la métrica anti no-show cuenta filas, sin flags) y la cita nueva arranca limpia con su propia fecha.

### 3. El punto de enchufe del frontend es UNO — pero el contrato actual es de display
Verificado en código: la agenda héroe de HOY lee `agenda` del store; en demo es `AGENDA_DEMO` (5 eventos estáticos, `demo.ts:133-142`) y **en real es SIEMPRE `[]`** (`store.tsx:469`). Reconectar es tocar `cargarReal` (`store.tsx:390-395`) + `resincronizarReal` (`:412-426`, hoy no refresca agenda) y las dos pantallas quedan conectadas gratis (HOY y `screens/agenda.tsx` leen el mismo campo).

**Trampa real:** `EventoAgenda.cuando` es un string de display (`"Hoy · 10:00"`) que la pantalla **parsea para ordenar y filtrar** (`claveOrden`, `vendedor.tsx:163-173`). La tabla real trae `timestamptz` → la Fase A incluye cambiar el contrato a timestamp + capa de mapeo timestamp→label en el store (y derivar `color` del tipo, hoy viene hardcodeado por fixture).

### 4. El botón Llamar del original está equivocado PARA ESTE CRM — y la solución ya está construida
El original (§4.4) propone `tel:`. Decisión ya tomada y documentada en el código: **`tel:` no marca desde la laptop** — `AccionesContacto` (`contacto.tsx`) copia el número (E.164 `+51…`, garantizado por doble normalización front+trigger) y abre el registro de resultado. Y `wa.me` **ya existe** en el mismo componente, con diálogo diferido de 4s al volver de la pestaña.

**La tarjeta de agenda monta `AccionesContacto` tal cual** (props `compacto`/`soloIcono` ya existen) y hereda gratis: llamar+copiar, WhatsApp, registro de resultado al timeline, gate por rol (`puedeEscribir`) y escudo de propagación. El patrón de fila ya está probado en la cola (`FilaCola`: fila clicable + `LeadHoverCard` + acciones). Ojo: `LeadHoverCard` exige el objeto `Lead` completo — la tarjeta resuelve el lead por `lead_id` contra `ambito.leads` (igual que hace hoy el capital en juego).

Lo que SÍ es funcionalidad nueva de verdad: **plantillas de mensaje por etapa** (hoy no existe ni el dato ni la UI).

### 5. RLS: el "por vendedor_id" del original se queda corto — el patrón real es jerárquico y ya existe
No hay que diseñar el modelo de permisos: se **calca de `leads_*`** con los helpers que ya existen:

- `private.vendedor_ids_visibles(uid)`: vendedor=él; supervisor=su subárbol (CTE recursivo); gerencia=todos.
- `private.es_lector_global()`: directorio/admin/superadmin **solo en SELECT** (por eso son solo-lectura: no aparecen en INSERT/UPDATE).
- Sin policy DELETE jamás: cancelar = `estado='cancelada'` (el WITH CHECK gatea quién).
- Miembro desactivado no ve nada de lo suyo; su supervisor sí (comportamiento que el gate ya asevera para leads).

Y las reglas de la casa que el original no conocía:
- **Ciclo innegociable**: branch de Supabase → migración → `seed:demo` + `test:rls` → advisors → merge → fila en `MIGRACIONES.md`.
- **Añadir la tabla al gate toca 3 archivos**: `fixtures.mjs` (fixtures deterministas + matriz por las 12 sesiones), `seed-demo.mjs` (ensure* idempotente), `test-rls.mjs` (visibilidad exacta + sondas negativas + cleanup). Más un oráculo `test-agenda.sql` (patrón 4A–4C).
- **Grants explícitos en la migración** (authenticated: select/insert/update; nunca delete). Recordar la trampa de `crm.leads`: sus grants son POR COLUMNA (ver `MIGRACIONES.md` 2026-07-18).

### 6. Recordatorios: el push NO es posible hoy — re-alcance honesto de la Fase F del original
Verificado: el app CRM **no tiene** service worker, ni manifest, ni vite-plugin-pwa, ni código de notificaciones. Y el deploy es estático a Hostinger con `base './'` — añadir SW toca el pipeline, no solo React.

Re-alcance:
- **v1**: el recordatorio ES la pantalla HOY (el vendedor la abre cada mañana; las tareas vencidas gritan solas) + **recordatorio manual al cliente** por `wa.me` prellenado ("Nos vemos mañana a las 10…") a un toque desde la cita.
- **Después**: push real = construir la capa PWA completa (decisión aparte, con su propio costo). Recordatorio *automático* al cliente = WhatsApp Business API (costo/aprobación aparte; el original lo daba por sentado).

### 7. Convivencia con la inteligencia actual (el original no la conocía)
`colaDe()` (inteligencia.ts:160-178) hoy deriva TODO por inactividad. Con `crm.tareas`:

- **Sobreviven tal cual**: buckets `por_repartir` (estado de asignación, no tarea) y `sin_responder` (lead nuevo sin ninguna actividad = literalmente "sin próxima acción"); todas las métricas/embudo/semáforos; `indexarUltimaActividad`/`diasSinActividad` como detector.
- **Pasan a fallback**: umbrales fijos de 3/5 días (`seguimiento`, `propuesta_sin_respuesta`) — solo aplican a leads **sin tarea pendiente**. Hoy `colaDe` no recibe la agenda como input; la cola nueva = **tareas vencidas + leads sin próxima acción**, y eso obliga a redefinir el comparador (severidad/hora) y extender `inteligencia.test.ts` (que congela el contrato actual).
- **Quedan obsoletos**: `EventoAgenda` con `cuando` string, `claveOrden`, `AGENDA_DEMO`, el copy "Aún no conectamos tu calendario" (quedaría mintiendo) y `screens/agenda.tsx` entero tal como está.
- **Bug conceptual que esto arregla**: hoy un lead con reunión agendada la próxima semana igual aparece "estancado" a los 5–7 días (el supervisor ve riesgo donde hay plan). Con tareas, la señal de riesgo del supervisor y el plan del vendedor miden lo mismo.
- El KPI "Nuevos sin responder" del supervisor se cuenta desde el bucket de la cola — cambia de fuente con ella (probarlo).

### 8. "Leads sin próxima acción" — sin vista SQL en v1
Leads abiertos del ámbito sin tarea `pendiente` futura. Con `MAX_LEADS_AMBITO=2000` y la cartera ya cargada en el store, **se computa en el cliente** (un `Set` de lead_ids con tarea pendiente). La vista/RPC servidor puede llegar con las métricas del manager (Fase F), no antes.

### 9. Reglas de la casa que toda tarjeta/vista debe respetar
- **Capital en juego por cita**: se resuelve por `lead_id` contra el ámbito (la tabla NO duplica el monto). Ya implementado así en el héroe.
- **PEN y USD jamás sumados**: la franja "En juego hoy" ya usa `capitalPorMoneda` con dedupe por lead. Toda métrica nueva de carga hereda la regla.
- **Zona horaria**: "hoy" se computa en America/Lima (UTC-5 fijo, sin DST). Guardar `timestamptz`, derivar el día en Lima.
- Un evento cuyo lead quede fuera del ámbito desaparece del recorte del cliente — es el comportamiento RLS deseado (ya pasa hoy con el filtro por `idsMios`).

---

## Modelo de datos v2 — `crm.tareas`

```sql
create table crm.tareas (
  id                uuid primary key default gen_random_uuid(),
  -- Exactamente UNO de los dos: lead (venta) o perfil de cliente (postventa/
  -- cobranza, fase posterior). La columna nace HOY para no migrar después;
  -- en v1 la UI solo usa lead_id.
  lead_id           uuid references crm.leads(id),
  perfil_id         uuid references public.perfiles(id),
  vendedor_id       uuid,                      -- null = tarea de bandeja (lead parkeado → la ve/opera el supervisor)
  tipo              text not null check (tipo in ('llamada','whatsapp','reunion','tarea')),
  titulo            text not null,
  nota              text,
  vence_en          timestamptz not null,      -- cuándo toca; "vencida" se DERIVA de aquí
  duracion_min      smallint,                  -- null = tarea sin bloque horario
  estado            text not null default 'pendiente'
                    check (estado in ('pendiente','completada','cancelada','no_show')),
  resultado_actividad_id uuid references crm.actividades(id), -- liga el cierre al log
  reagendada_de     uuid references crm.tareas(id),           -- cadena de reagendas post no-show
  reprogramaciones  smallint not null default 0,
  activo            boolean not null default true,
  creado_por        uuid,
  creado_en         timestamptz not null default now(),
  actualizado_en    timestamptz not null default now(),
  constraint tareas_un_solo_sujeto check (num_nonnulls(lead_id, perfil_id) = 1)
);
-- RLS calcada de leads_* (vendedor_ids_visibles / rama parkeo / gerencia;
-- es_lector_global SOLO en SELECT). Sin DELETE. Grants explícitos.
-- Triggers: touch actualizado_en + log_audit_crm.
-- Índices: (vendedor_id, estado, vence_en) para HOY; parcial estado='pendiente' para huérfanos.
```

**Coherencia con el ciclo de vida del lead (misma migración — sin esto la tabla miente):**
1. **Trigger "las tareas siguen al lead"**: reasignar el lead propaga `vendedor_id` a sus tareas `pendiente` (si no, quedan huérfanas en el vendedor viejo e invisibles para el nuevo). Repartir un lead parkeado asigna también sus tareas de bandeja (`vendedor_id null` → nuevo dueño).
2. **Trigger "lead cerrado cancela sus tareas"**: descartar/convertir el lead pone sus `pendiente` en `cancelada` — si no, gritan "vencida" para siempre en la cola. Defensa doble: la cola además filtra `esAbierto` (estilo de la casa).
3. **RPC `crm.cerrar_tarea` (SECURITY DEFINER, transaccional)**: el cierre son DOS escrituras (INSERT del resultado en `actividades` + UPDATE de la tarea) — sin RPC atómica, un fallo a medias deja tarea completada sin log o log sin cerrar. La RPC recibe además la tarea siguiente opcional (el "completar y agendar siguiente" del original, atómico de punta a punta).

Notas:
- `tipo` arranca con 4 (regla del original que se conserva: menos tipos = adopción). `vencimiento` NO es un tipo de tarea: los vencimientos de contrato son eventos **derivados** de cronograma y se mezclan en la vista, no en la tabla. Cobranza llega con `perfil_id` (fase posterior), no como tipo nuevo prematuro.
- El mapa UI `TIPO_EVENTO`/`ICONO_EVENTO` solo conoce reunion/llamada/vencimiento — hay que ampliarlo con whatsapp/tarea o los nuevos caen al fallback con slug crudo.
- Time-blocking sin sujeto (ni lead ni cliente) = Fase H, relajando el CHECK a `(tipo='bloque' OR num_nonnulls(...)=1)`.

## Fases v2 (reordenadas: el motor antes que las vistas)

El original ponía el motor de próxima acción en Fase D, detrás de dos fases de vistas de calendario. Eso contradice su propia §0 ("todo lo demás es secundario") y la regla de layout comercial: **lo que genera ingreso, primero**. Las vistas Semana/Mes son panorama; el motor es plata.

**Principio transversal (del original §4.2, se declara aquí para que ninguna fase lo diluya):** el vendedor **nunca "va a la agenda" a programar** — agenda desde donde está. Puntos de enganche por fase: drawer del lead (A) → cierre de actividad y cola de HOY (B) → Cartera/pipeline (C).

### Fase A — `crm.tareas` + reconexión de HOY (el cimiento)
Migración completa (tabla + triggers de coherencia + RPC `cerrar_tarea` + RLS + grants + gate + oráculo `test-tareas.sql`) por el ciclo branch→gate→merge — **una sola pasada de gate** para toda la BD de la agenda. Frontera: `database.types.ts`, `crm-api.ts` (listar/insertar/actualizar con Valibot **`optional` en columnas nuevas** — regla aprendida hoy), store (`cargarReal`/`resincronizarReal`/adiós `agenda: []`), contrato timestamp→label, crear tarea desde la ficha del lead.
**Listo cuando:** un vendedor real crea "Llamar a X mañana 10:00" desde el drawer y la ve en HOY; gate RLS en verde con la matriz de tareas (incl. reasignación propaga + lead cerrado cancela); el supervisor NO ve tareas de otro subárbol.

### Fase B — Motor de próxima acción (el diferenciador, adelantado)
Incluye su superficie mínima operable — **no espera a la pantalla Agenda**: la fila de tarea en HOY (patrón `FilaCola` + botón completar) y el cierre desde `DialogResultado` extendido. Flujo: completar → RPC atómica (resultado a `actividades`) → **propone la siguiente** con cadencia sugerida 1→3→5→7 → si el resultado cambia el destino del lead (agendó reunión / cerró / descartó — la taxonomía §4.7 del original), el mismo diálogo dispara la transición de etapa reusando `cambiarEtapa`/`descartar` del store. Cola nueva = tareas vencidas + leads sin próxima acción (cómputo cliente); umbrales 3/5 días pasan a fallback; **aquí mismo se arregla "estancados"** (colaDe es código compartido — un lead con reunión futura deja de alarmar al supervisor en esta fase, no después).
**Sobre la obligatoriedad:** sugerencia con "saltar" de UN toque, no un candado — un forcing duro induce tareas basura para esquivarlo. Medir la tasa de salto primero; endurecer solo si los datos lo piden (el original decía "invita/obliga"; empezamos por invitar con fricción mínima).
**Listo cuando:** completar una tarea desde HOY deja el resultado en el timeline y la siguiente propuesta a un toque, y la cola muestra los huérfanos.

### Fase C — Pantalla Agenda: Lista + Día
Reescritura de `screens/agenda.tsx` sobre tareas reales. Lista cronológica (default, móvil-first) + vista Día con huecos. Tarjeta = patrón `FilaCola` + `LeadHoverCard` + `AccionesContacto` + capital en juego. Reprogramar rápido (+1d/+3d/+1sem → `reprogramaciones++`; reagendar un no-show crea tarea nueva encadenada). "+ Nueva tarea" también desde Cartera/pipeline.
**Listo cuando:** ver el día, crear, completar y reprogramar desde el celular.

### Fase D — Semana/Mes + navegación + filtros
Semana (7 columnas), Mes (densidad), mini-calendario, buscador, filtros tipo/estado/etapa. Atajos de teclado desktop. **Hint de ritmo semanal** (del original §1, se conserva): mar–jue por la mañana concentran reuniones; viernes para limpiar pipeline y planificar — la vista Semana lo sugiere en los huecos, no lo impone.

### Fase E — Recordatorios v1 (sin push)
Vencidas destacadas en HOY al abrir + toast in-app en sesión + **botón "recordar al cliente" por `wa.me` prellenado** en citas de mañana/hoy. ⚠️ En el radar: este recordatorio es 100% manual (depende de que el vendedor se acuerde) — mitigación: badge insistente en la cita de mañana; la automatización real es Fase H.

### Fase F — Supervisor/gerencia + métricas
Vista de equipo con carga por vendedor; métricas por RPC `SECURITY DEFINER` patrón `metricas_*_fn` (+ `es_lector_global`): toques/día, % completadas, vencidas, reprogramaciones, no-shows (filas `no_show`), reuniones/semana. (El fix de "estancados" ya llegó en B; aquí solo se mide.)

### Fase H — Premium (decisiones aparte, cada una con costo real)
PWA completa (SW+manifest+pipeline) → push · WhatsApp Business API (recordatorio automático) · plantillas por etapa · Google Calendar (**ICS de solo-lectura primero**; el sync bidireccional del original es carísimo para 20 personas) · time-blocking sin lead · drag-and-drop.

## Lo que el original ya tenía bien (se conserva sin cambios)
Idea central del motor de próxima acción y su regla de oro · cadencia 5–8 toques con espaciados · WhatsApp-first Perú · arrancar con 4 tipos · móvil/pulgar primero · agendar desde cualquier lugar (§4.2, ahora principio transversal declarado) · ritmo semanal (§1, ahora en Fase D) · taxonomía de resultado (§4.7, ahora en el cierre de Fase B) · "listo cuando" por fase · los errores a evitar del §8 (con la corrección del #1: dos tablas plan/log no son dos fuentes de verdad).

## Relacionadas
[[Pasada de UX del CRM 2026-07-17]] · [[CRM conexión a datos reales]] · [[Acceso y roles del CRM]] · [[Refactor de tablas y datos del CRM]] · original: `CRM-Avance-Corp/agenda-comercial-plan.md`
