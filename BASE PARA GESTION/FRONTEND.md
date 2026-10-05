# Plan técnico del frontend (F1–F4) — preparado el 03/10/2026 con reconocimiento de solo lectura

> El frontend empieza SOLO después del merge de las 7 migraciones (regla del encargo). Esto es el plan; nada está escrito.
> Fuente: mapa del front (`app/src`) hecho por un agente de solo lectura; rutas relativas a `CRM-Avance-Corp/app/src`.

## Hechos del front que mandan
- **Router por hash** (`lib/router.ts`): `rescate` y `rescate-carpeta` ya existen en `VISTAS`; tabla de pantallas en `App.tsx`
  (`PANTALLA_POR_VISTA`, `satisfies Record<Vista, …>`). Acceso por vista en `lib/vistas.ts`: hoy `rescate` exige la capacidad
  `repartirLeads`, que el analista NO tiene (`lib/roles.ts:72`). **F1 abre `#/rescate` al analista como hace `gestion-diaria`**
  (`vistas.ts:106`: por rol), sin regalarle `repartirLeads`. El menú (`sidebar.tsx`, `NAV_META.rescate = «Base para gestión»`)
  aparece solo al abrir la vista; **no hay patrón de contador en el menú** (el teléfono de Gestión Diaria vive en «Hoy»).
- **Despacho por rol:** `screens/gestion-diaria.tsx:62-78` (`switch (yo.rol)` → analista/supervisor/gerencia; `PanelVacio` por
  defecto). `yo.rol` sale de `mi_acceso_fn` (`lib/auth.tsx:64`). F1 crea `screens/rescate.tsx` con ese molde: vendedor → vista
  nueva del analista; supervisor/gerencia → `RescateDescartados` actual (+ F4).
- **Capa de datos:** `data/crm-api.ts` (wrappers con valibot, `aErrorApi` mapea SQLSTATE → texto es-PE: 42501 SIN_PERMISO,
  P0429 NO_INSISTA, P0002 FUERA_DE_COLA, 23505, 40001…). Tipos de RPC desde `lib/database.types.ts` → **regenerar tras el
  merge** (`obtener_base_gestion`, `registrar_intento_base`, `reactivar_lead_base`, `base_gestion_resumen` no están). React Query
  en `data/crm-queries.ts` (`crmQueryKeys`, invalidaciones). El rescate actual NO usa React Query (useState + AbortController).
- **El drawer del lead NO sirve para la base:** abre `lead(id)` del store, cuyo ámbito no incluye descartados fuera de la cartera
  (`components/app/lead-drawer.tsx:134-139`). El historial (`Timeline`, `useActividadesDeLead` con cursor) **no tiene buscador**.
  El formulario de resultado de Gestión Diaria (`components/gestion-diaria/registrar-resultado.tsx`) depende de
  `useCRMData().registrarLlamada` (store + `registrar_llamada_v4`, rechaza leads cerrados): **se reutiliza el catálogo**
  (`lib/resultado-llamada.ts`, 7 resultados con atajos 1–7, submotivos) pero no el componente.
- **No contactar:** no hay UI de lead para `marcar_no_contactar`/`levantar_no_contactar` (solo en tipos). Patrón más cercano:
  `components/app/postventa-persona.tsx:60-126` (botón con diálogo de motivo; `levantar` oculto salvo gerencia → **ajustar a D5:
  también supervisor**). Badge: `inversionista-ficha.tsx:221`.
- **Estados y UX:** `VacioCompacto`, `PanelCargando/PanelError/PanelVacio`, `Dialog` (`components/ui/dialog.tsx`), toasts `sonner`,
  fechas Lima (`lib/agenda-derivada.ts`: `fechaLima`, `horaLima`, `fechaHoraLima`). Reglas: navy autoridad / azul acción / ámbar
  semana / rojo hoy, **sin verde**; Plus Jakarta Sans, jerarquía por peso, `tabular-nums`; filas ≥ 40 px; todo componente con
  default/hover/focus/vacío/cargando/error; cada vacío dice qué hacer. Regla de Miguel: **legibilidad antes que densidad**
  (detalle ≥ 14 px; la tabla del rescate actual usa 10–12 px: no copiarla para el analista).
- **Pruebas:** contrato MSW (`data/crm-api-rescate-msw.test.ts` como molde: cuerpo de la petición, filas corruptas descartadas,
  mapeo de errores), pantalla (`screens/rescate-descartados.test.tsx`: mocks de `auth-context`, `store-context`, `crm-api`),
  `revisor-a11y` (role=button con tabIndex y teclado, inputs con label, tablas con cabeceras, foco visible, contraste),
  E2E Docker (`npm run test:e2e:docker`; referencias `e2e/historial-lead.spec.ts`, `e2e/gestion-diaria-resultado.spec.ts`).

## F1 · Vista del analista (`#/rescate`)
1. `lib/vistas.ts`: `rescate` permitida para vendedor/supervisor/gerencia (molde de `gestion-diaria`); `rescate-carpeta` sigue
   siendo de supervisor/gerencia. `topbar.tsx`: subtítulo por rol («Tus leads descartados: llama, agenda, reactiva»).
2. `data/crm-api.ts`: `obtenerBaseGestion(vendedorId?)`, `registrarIntentoBase(op, lead, resultado, nota?, proxima?)`,
   `reactivarLeadBase(op, lead, nota?)`, `baseGestionResumen()`, `marcarNoContactar(lead, motivo?)`, `levantarNoContactar(lead, motivo)`;
   esquemas valibot; en `aErrorApi` los textos nuevos: 22023 «descanso»/«10 días»/«fecha», 23505 «otro contenido», P0429.
3. `data/crm-queries.ts`: `crmQueryKeys.baseGestion(vendedorId)`, `baseGestionResumen()`; `useBaseGestion`, `useBaseGestionResumen`;
   mutaciones con `p_operacion_id = crypto.randomUUID()` fijo por clic (doble clic → mismo id → replay) e invalidación de la base,
   del historial del lead y de la cartera (el lead reactivado vuelve al pipeline).
4. `screens/rescate.tsx` (despacho) + `screens/rescate/analista.tsx`: lista plana (no mosaico) con ≥ 14 px: Lead · Motivo ·
   Etapa máxima · Días · Intentos · Último resultado · Próxima llamada · acciones (Llamar/Registrar, Ver ficha). Vacío claro
   («No tienes leads descartados por gestionar»). Sin acciones de supervisor.
   **Término:** analista A ve solo los suyos (la RPC lo garantiza; prueba de pantalla con dos `yo`).

## F2 · Ficha del lead de la base (hoja propia)
- `components/base-gestion/ficha-base.tsx` sobre `components/ui/sheet.tsx` (no el drawer). Cabecera con datos del lead y badges
  (motivo, etapa máxima, intentos, próxima llamada, «No contactar»).
- **Historial completo** con `actividades_de_lead_fn` recorriendo el cursor hasta el final (el encargo pide leerlo de corrido, sin
  truncar ni colapsar) + **buscador por palabra** en cliente (filtra sobre `detalle` y resultado); reasignaciones visibles (ya vienen
  como actividades `reasignacion`). Del más reciente al más antiguo, con fecha, hora, autor y resultado.
- **Formulario de intento** propio: 7 resultados del catálogo (atajos 1–7), nota libre, fecha y hora obligatorias si «volver a
  llamar» (máx. 10 días: validar en pantalla y dejar que la puerta mande), submotivo cuando aplique. Guardado → toast, cierra o
  limpia; «agendó cita» → el lead sale de la base y la UI ofrece abrir el flujo normal de agendar cita del lead vivo.
- **Reactivar** con `Dialog` de confirmación (nota opcional), idempotente; al éxito, el lead desaparece de la base y toast con
  enlace a la cartera. **No contactar** con motivo (todos); **Quitar** solo supervisor/gerencia (D5).
- Errores: reasignación en medio → P0002 «Lead no encontrado o fuera de tu ámbito» con texto claro y recarga de la lista.

## F3 · Organización del trabajo
- Bloque superior **«Llamar hoy»** (filas con `rellamada_hoy`), luego el resto; filtros: motivo de descarte, etapa máxima, último
  resultado (en cliente sobre la respuesta de la RPC); contador de intentos por fila. Orden lo trae el servidor.
- `screens/hoy/vendedor.tsx`: línea «Base: N rellamadas para hoy» bajo la fecha (:1332-1334), navegando con `escribirHash('rescate')`;
  hook `data/use-conteo-base-gestion.ts` que comparte la query key de la lista (molde `use-conteo-gestion-diaria.ts`, fail-closed).
  **Término:** una rellamada agendada para hoy aparece primera (la RPC) y la línea de «Hoy» la cuenta.

## F4 · Vista del supervisor
- En `RescateDescartados` (mosaico/carpeta actual) o en una pestaña «Gestión de la base»: tabla por lead con Intentos · Último
  resultado · Gestiona (de `obtener_base_gestion`, filtro `p_vendedor_id` por analista) + panel «Reactivaciones por analista»
  (`base_gestion_resumen`: en base, rellamadas hoy, intentos hoy, reactivaciones del mes).
- **Punto abierto para B5 (pequeña migración, pedir OK):** `obtener_base_gestion` EXCLUYE los leads con «no contactar», así que el
  supervisor no los ve para «quitar la marca». Opciones: (a) `p_incluir_vetados boolean default false` solo para supervisor/gerencia
  con columna `no_contactar` en la salida; (b) hacerlo desde la carpeta del rescate actual (`rescate_descartes_mes` no filtra el
  veto, pero tampoco devuelve el flag). Recomendación: (a).
- Sin perder ninguna función actual del Centro de rescate (repartir, abrir carpeta en otra pestaña).

## Orden sugerido y verificación
F1 (acceso + datos + lista) → F2 (ficha) → F3 (Llamar hoy, filtros, Hoy) → F4. Por fase: pruebas MSW de los wrappers, pruebas
de pantalla con `yo` analista y supervisor, `revisor-a11y`, `npm run check`, E2E Docker para F2 (registrar, reactivar), Codex
LEVEL 2 al cerrar F1–F2 y F3–F4. Publicar con preflight; actualizar tablero y vault; borrar `BASE PARA GESTION/` al cerrar QA.
