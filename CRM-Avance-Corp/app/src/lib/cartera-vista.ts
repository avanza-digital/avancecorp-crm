// Helper PURO de la pantalla Cartera (la fusión Clientes + Contratos del
// analista): agrupa cada cliente con SUS contratos (1:N) y calcula el capital
// EN JUEGO por cliente — PEN y USD en acumuladores SEPARADOS, jamás sumados.
// Vive aparte de la pantalla para probarse sin montar React (cartera-vista.test.ts)
// y SIN importar UI: cruza las dos vistas hermanas que el servidor ya scopeó por
// rol (crm.clientes_basicos + la lista de contratos de la cartera); aquí solo se
// unen. El chip del StatStrip lo arma la pantalla (patrón de equipo.tsx), no este
// módulo, para no acoplar lib con componentes.
import type { ClienteBasico, ContratoRow } from './clientes-tipos'
import { fechaLima } from './agenda-derivada'

/** Un cliente con sus contratos y el capital activo por moneda (separado). */
export interface GrupoCartera {
  cliente: ClienteBasico
  /** TODOS los contratos del cliente (cualquier estado); se pintan al expandir. */
  contratos: ContratoRow[]
  /** Suma de capital de contratos ACTIVOS en soles (nunca mezcla monedas). */
  capitalActivoPen: number
  /** Suma de capital de contratos ACTIVOS en dólares (acumulador aparte). */
  capitalActivoUsd: number
  contratosActivos: number
  /** contratosActivos > 0 — el cliente genera ingreso hoy. */
  tieneCapital: boolean
  /** Vencimiento más próximo entre los activos (YYYY-MM-DD), o null. */
  proximoVencimiento: string | null
}

function redondear2(n: number): number {
  return Math.round(n * 100) / 100
}

/** Desempate por fecha ISO descendente (más reciente primero) sin parsear Date. */
function compararFechaDesc(a: string, b: string): number {
  if (a === b) return 0
  return a > b ? -1 : 1
}

/**
 * Une clientes y contratos por `contrato.cliente_id === cliente.id` con
 * semántica LEFT JOIN: un cliente SIN contratos aparece igual (con su vacío
 * accionable). Un contrato cuyo cliente no está cargado se DESCARTA sin lanzar
 * (en real no ocurre: ambas listas son del mismo ámbito por rol). El capital
 * solo suma contratos `estado==='activo'`, separando PEN de USD. Orden: mayor
 * capital activo PEN primero (PEN es la moneda-hero del desempate), luego USD,
 * luego el cliente más reciente. El orden de los contratos DENTRO del grupo se
 * conserva tal como llegan (la pantalla decide su orden de pintado).
 */
export function agruparCartera(clientes: ClienteBasico[], contratos: ContratoRow[]): GrupoCartera[] {
  const porCliente = new Map<string, ContratoRow[]>()
  for (const cli of clientes) porCliente.set(cli.id, [])
  for (const c of contratos) {
    const arr = porCliente.get(c.cliente_id)
    if (arr) arr.push(c) // huérfano (sin cliente cargado en el ámbito) → descartado
  }

  const grupos = clientes.map((cliente) => resumirCliente(cliente, porCliente.get(cliente.id) ?? []))
  grupos.sort(ordenDeCartera)
  return grupos
}

/**
 * Resumen de UN cliente sobre EL CONJUNTO DE CONTRATOS QUE SE LE PASE. Se
 * extrajo de `agruparCartera` (2026-08-14) para que la vista por meses
 * (lib/cartera-meses.ts) pueda recalcularlo sobre los contratos DE ESE MES: si
 * reutilizara el resumen global, la fila de julio enseñaría el capital de toda
 * la vida del cliente y el mismo importe se repetiría en cada bloque.
 */
export function resumirCliente(cliente: ClienteBasico, contratos: ContratoRow[]): GrupoCartera {
  let pen = 0
  let usd = 0
  let activos = 0
  let proximo: string | null = null
  for (const c of contratos) {
    if (c.estado !== 'activo') continue
    activos += 1
    const cap = Number(c.capital) || 0 // defensa: numeric-como-string de PostgREST
    if (c.moneda === 'USD') usd += cap
    else pen += cap
    if (c.fecha_vencimiento && (proximo === null || c.fecha_vencimiento < proximo)) {
      proximo = c.fecha_vencimiento
    }
  }
  return {
    cliente,
    contratos,
    capitalActivoPen: redondear2(pen),
    capitalActivoUsd: redondear2(usd),
    contratosActivos: activos,
    tieneCapital: activos > 0,
    proximoVencimiento: proximo,
  }
}

/** Orden de la cartera: mayor capital activo PEN, luego USD, luego el más reciente. */
export function ordenDeCartera(a: GrupoCartera, b: GrupoCartera): number {
  return (
    b.capitalActivoPen - a.capitalActivoPen ||
    b.capitalActivoUsd - a.capitalActivoUsd ||
    compararFechaDesc(a.cliente.creado_en, b.cliente.creado_en)
  )
}

/**
 * Días de calendario entre `hoy` y una fecha YYYY-MM-DD. Extrae el año/mes/día
 * de Lima de `hoy` (también fuera de Perú), igual que el resumen del servidor, y
 * compara medianoches UTC → conteo de días estable, sin deriva por zona horaria.
 */
function diasHasta(fecha: string, hoy: Date): number {
  const [y, m, d] = fecha.split('-').map(Number)
  if (!y || !m || !d) return Number.NaN
  if (!Number.isFinite(hoy.getTime())) return Number.NaN
  const [hy, hm, hd] = fechaLima(hoy.getTime()).split('-').map(Number)
  const base = Date.UTC(hy!, hm! - 1, hd!)
  const objetivo = Date.UTC(y, m - 1, d)
  return Math.round((objetivo - base) / 86_400_000)
}

/**
 * Ventana de la ALARMA de renovación, en días. Una sola constante para que el
 * chip («Por vencer ≤30 d»), el filtro de la tabla y la marca de la sub-fila no
 * puedan discrepar entre sí.
 */
export const DIAS_ALARMA_RENOVACION = 30

/**
 * ¿Este contrato es una renovación por atender? Activo y venciendo dentro de la
 * ventana, con HOY incluido. Una fecha ya pasada no cuenta (el contrato ya está
 * vencido, no "por vencer") y una malformada tampoco: `diasHasta` devuelve NaN y
 * toda comparación con NaN es false → nunca lanza ni inventa una alarma.
 */
export function esPorVencer(
  c: ContratoRow,
  hoy: Date,
  dias: number = DIAS_ALARMA_RENOVACION,
): boolean {
  if (c.estado !== 'activo' || !c.fecha_vencimiento) return false
  const d = diasHasta(c.fecha_vencimiento, hoy)
  return d >= 0 && d <= dias
}

/**
 * ids de los contratos por vencer en TODA la cartera — incluidos los de clientes
 * DADOS DE BAJA en el portal (`cliente.activo === false`). La alarma NO se
 * filtra por ese flag: el contrato sigue vigente y hay que renovarlo aunque su
 * titular ya no figure como cliente activo, y esta es la única superficie del
 * CRM que lo avisa (la tabla filtra por estado de CONTRATO, no por vencimiento).
 * Devolver el Set —y no un booleano por grupo— deja que la pantalla filtre las
 * filas Y marque el contrato exacto con un solo recorrido.
 */
export function idsPorVencer(grupos: GrupoCartera[], hoy: Date = new Date()): Set<string> {
  const ids = new Set<string>()
  for (const g of grupos) {
    for (const c of g.contratos) {
      if (esPorVencer(c, hoy)) ids.add(c.id)
    }
  }
  return ids
}

/** Números del StatStrip: dinero de la cartera en gestión + alarma de toda ella. */
export interface ResumenCartera {
  capitalActivoPen: number
  capitalActivoUsd: number
  clientesConCapital: number
  /** Clientes EN GESTIÓN (los dados de baja los cuenta aparte la pantalla). */
  totalClientes: number
  /** Contratos activos que vencen ≤30 d en TODA la cartera (alarma, no total). */
  porVencer30: number
  /** De esos, cuántos son de clientes dados de baja — para decirlo, no ocultarlo. */
  porVencer30DeBaja: number
}

/**
 * Números del StatStrip. Recibe la cartera COMPLETA y separa dos conceptos que
 * NO se miden sobre lo mismo:
 *
 *  · DINERO y conteo de clientes → solo la cartera EN GESTIÓN (`cliente.activo`).
 *    Es un TOTAL, y sumar a quien ya fue dado de baja en el portal le inflaría al
 *    analista un capital que no puede trabajar ni renovar.
 *  · ALARMA de vencimiento → TODOS los clientes. No es un total inflable sino un
 *    aviso: un contrato activo que vence en ≤30 d hay que renovarlo aunque su
 *    titular esté dado de baja, la renovación es el ingreso más rentable del
 *    negocio y si no salta aquí no salta en ningún otro sitio del CRM.
 *
 * Por eso además del conteo va el desglose `porVencer30DeBaja`: el chip dice
 * cuántos vienen de bajas en vez de mezclarlos en silencio.
 * `hoy` es inyectable para pruebas deterministas.
 */
export function resumenCartera(grupos: GrupoCartera[], hoy: Date = new Date()): ResumenCartera {
  let pen = 0
  let usd = 0
  let conCapital = 0
  let enGestion = 0
  let porVencer = 0
  let porVencerDeBaja = 0
  for (const g of grupos) {
    const gestionable = g.cliente.activo
    if (gestionable) {
      enGestion += 1
      pen += g.capitalActivoPen
      usd += g.capitalActivoUsd
      if (g.tieneCapital) conCapital += 1
    }
    for (const c of g.contratos) {
      if (!esPorVencer(c, hoy)) continue
      porVencer += 1
      if (!gestionable) porVencerDeBaja += 1
    }
  }
  return {
    capitalActivoPen: redondear2(pen),
    capitalActivoUsd: redondear2(usd),
    clientesConCapital: conCapital,
    totalClientes: enGestion,
    porVencer30: porVencer,
    porVencer30DeBaja: porVencerDeBaja,
  }
}
