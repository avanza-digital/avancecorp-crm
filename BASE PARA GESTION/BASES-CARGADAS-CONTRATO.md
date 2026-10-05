# Bases cargadas — contrato servidor ↔ pantalla para B9, B10, F5 y F6 (04/10)

En producción ya: B7 (tablas `crm.bases_carga`, `crm.base_carga_leads`, `crm.base_carga_operaciones`; origen/motivo
`base_cargada`; capital vacío del dormido) y B8 (`crm.crear_base(p_operacion_id, p_nombre, p_origen, p_supervisor_id,
p_archivo_nombre)`, `crm.cargar_base_lote(p_operacion_id, p_base_id, p_filas jsonb)` — lote ≤ 100, base ≤ 5000;
`crm.armar_base_crm(p_operacion_id, p_nombre, p_supervisor_id, p_lead_ids uuid[])` ≤ 2000). Decisiones E1–E14 en
`BASES-CARGADAS.md`. Todas las puertas: DEFINER, rol y ámbito del servidor, idempotentes por `p_operacion_id`
(replay = misma respuesta), 42501 sin permiso, P0002 fuera de ámbito, 22023 entrada inválida, 55P03 «otra operación en
curso; reintenta». Ninguna devuelve datos de leads fuera del ámbito del actor.

## B9 · repartir y recoger
- `crm.repartir_base(p_operacion_id uuid, p_base_id uuid, p_reparto jsonb) returns jsonb`
  - Bloque: `{"modo":"bloque","asignaciones":[{"analista_id":"…","cantidad":40}, …]}` — el servidor elige contactos SIN
    REPARTIR de la base (los más antiguos en la base primero), saltando los que tienen seguimiento activo (B6), veto o
    descanso; si no alcanzan, falla TODO con 22023 y `detail` = disponibles.
  - Individual: `{"modo":"individual","asignaciones":[{"lead_id":"…","analista_id":"…"}, …]}` — cada lead debe ser de la
    base y estar sin repartir (o repartido a otro: se reasigna) y elegible.
  - Todo o nada. Analista: activo, rol vendedor, del subárbol del supervisor dueño de la base (gerencia: cualquiera).
  - Efecto: `crm.leads.vendedor_id` = analista (sigue descartado/dormido), `base_carga_leads.analista_id/asignado_en/
    asignado_por`; rastro en recibos (B6 y la actividad «reasignación» corren solos).
  - Respuesta: `{"repartidos": n, "por_analista":[{"analista_id","cantidad"}], "omitidos":[{"lead_id"|null,"motivo"}]}`.
- `crm.recoger_de_base(p_operacion_id uuid, p_base_id uuid, p_analista_id uuid) returns jsonb` — devuelve a «sin
  repartir» (vuelve a la bandeja del supervisor dueño) los contactos asignados a ese analista SIN intento desde
  `asignado_en` y sin seguimiento activo. Respuesta: `{"recogidos": n, "omitidos": n}`.
- `crm.contactos_de_base(p_base_id uuid, p_estado text default 'sin_repartir') returns table(lead_id uuid,
  nombre_completo text, telefono text, distrito text, agregado_en timestamptz, analista_id uuid, analista_nombre text,
  estado text)` — `p_estado` ∈ `sin_repartir | repartidos | todos`; para el reparto individual y la lista de la base.
  `estado` ∈ `sin_repartir | sin_tocar | trabajado | en_descanso | cita | reactivado | movido_otra_via | no_contactar`.

## B10 · seguimiento, lista del analista y capital al reactivar
- `crm.seguimiento_bases() returns table(base_id uuid, nombre text, origen text, supervisor_id uuid,
  supervisor_nombre text, creado_en timestamptz, total int, sin_repartir int, repartidos int, sin_tocar int,
  trabajados int, en_descanso int, citas int, reactivados int, avance numeric)` — supervisor: las de su subárbol;
  gerencia: todas; analista: 42501. `avance` = trabajados / repartidos (0–1).
- `crm.seguimiento_base(p_base_id uuid) returns table(analista_id uuid, analista_nombre text, asignados int,
  sin_tocar int, sin_tocar_3_dias int, trabajados int, en_descanso int, citas int, reactivados int,
  ultimo_intento_en timestamptz, movidos_otra_via int)` — una fila por analista con contactos de la base.
  «Sin tocar 3 días» (E6) = asignado hace ≥ 3 días y sin intento desde `asignado_en` (la pantalla lo pinta en rojo).
- `crm.seguimiento_base_detalle(p_base_id uuid, p_analista_id uuid default null, p_cifra text) returns table(lead_id uuid,
  nombre_completo text, estado text, asignado_en timestamptz, ultimo_intento_en timestamptz, ultimo_resultado text)` —
  `p_cifra` = cualquier columna numérica de las dos funciones de arriba (todo número se abre); filas = la cifra.
- `crm.obtener_base_gestion(p_vendedor_id, p_incluir_vetados)` — misma firma; AÑADE al final `base_id uuid`,
  `base_nombre text` (NULL si el lead no está en una base viva) y EXCLUYE de la vista de supervisión/gerencia los
  dormidos de base SIN REPARTIR (viven en la pestaña «Bases»). El analista ve sus contactos de base repartidos como
  cualquier lead de su base (mismas reglas: intentos, rellamada, descanso).
- `crm.reactivar_lead_base` — nueva firma con `p_monto_estimado numeric default null` (y `p_moneda text default null`):
  si el lead no tiene capital, es OBLIGATORIO (22023 «Indica el capital estimado para reactivar»); con capital ya
  puesto se ignora. Mantener la firma vieja como envoltorio compatible hasta que el front nuevo esté publicado, o
  versionar (`reactivar_lead_base_v2`) — decide B10 con evidencia y documenta.

## Pantalla
- **F5 · pestaña «Bases»** (tercera pestaña de «Base para gestión», supervisor y gerencia): hoja de bases
  (`seguimiento_bases`) con avance; «Cargar base» → (a) subir .xlsx/.csv (lector cargado solo al usarlo), mapeo de
  columnas (nombre, teléfono, DNI, distrito, comentario, capital), vista previa con validación local, nombre de la base,
  gerencia elige supervisor; envía `crear_base` + lotes de 100 con `cargar_base_lote` (progreso, reintento ante 55P03,
  informe final por veredicto con «descargar informe»); (b) «Armar desde el CRM» con los filtros de la hoja de F4 y
  `armar_base_crm` (incluidos/excluidos con motivo). Dentro de una base: reparto por cantidades («Ana 40 · Luis 30»,
  «En partes iguales», contador «70 de 85 por repartir») y por selección («Asignar a…»); seguimiento por analista
  (`seguimiento_base`, rojo «sin tocar hace 3 días»), todo número se abre (`seguimiento_base_detalle`); «Recoger».
- **F6 · analista**: columna «Base» y selector «Base: Todas · Feria 2025 (40)» junto al de «Mes» en su hoja; «Reactivar»
  pide capital si el lead no lo tiene.
- Hasta que B9/B10 estén en producción, la pantalla degrada (PGRST202 → «Bases: disponible pronto»), como F4.
