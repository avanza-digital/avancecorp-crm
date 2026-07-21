// Helper PURO de la pantalla Cartera (la fusión Clientes + Contratos del
// vendedor): agrupa cada cliente con SUS contratos (1:N) y calcula el capital
// EN JUEGO por cliente — PEN y USD en acumuladores SEPARADOS, jamás sumados.
// Vive aparte de la pantalla para probarse sin montar React (cartera-vista.test.ts)
// y SIN importar UI: cruza las dos vistas hermanas que el servidor ya scopeó por
// rol (crm.clientes_basicos + la lista de contratos de la cartera); aquí solo se
// unen. El chip del StatStrip lo arma la pantalla (patrón de equipo.tsx), no este
// módulo, para no acoplar lib con componentes.
import type { ClienteBasico, ContratoRow } from './clientes-tipos'

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

  const grupos = clientes.map((cliente): GrupoCartera => {
    const cs = porCliente.get(cliente.id) ?? []
    let pen = 0
    let usd = 0
    let activos = 0
    let proximo: string | null = null
    for (const c of cs) {
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
      contratos: cs,
      capitalActivoPen: redondear2(pen),
      capitalActivoUsd: redondear2(usd),
      contratosActivos: activos,
      tieneCapital: activos > 0,
      proximoVencimiento: proximo,
    }
  })

  grupos.sort(
    (a, b) =>
      b.capitalActivoPen - a.capitalActivoPen ||
      b.capitalActivoUsd - a.capitalActivoUsd ||
      compararFechaDesc(a.cliente.creado_en, b.cliente.creado_en),
  )
  return grupos
}

/**
 * Días de calendario entre `hoy` y una fecha YYYY-MM-DD. Extrae el año/mes/día
 * LOCAL de `hoy` (= Lima en prod y en los tests, TZ fijada en vitest.config) y
 * compara medianoches UTC → conteo de días estable, sin deriva por zona horaria.
 */
function diasHasta(fecha: string, hoy: Date): number {
  const [y, m, d] = fecha.split('-').map(Number)
  if (!y || !m || !d) return Number.NaN
  const base = Date.UTC(hoy.getFullYear(), hoy.getMonth(), hoy.getDate())
  const objetivo = Date.UTC(y, m - 1, d)
  return Math.round((objetivo - base) / 86_400_000)
}

/** Números del StatStrip. `hoy` es inyectable para pruebas deterministas. */
export function resumenCartera(
  grupos: GrupoCartera[],
  hoy: Date = new Date(),
): {
  capitalActivoPen: number
  capitalActivoUsd: number
  clientesConCapital: number
  totalClientes: number
  porVencer30: number
} {
  let pen = 0
  let usd = 0
  let conCapital = 0
  let porVencer = 0
  for (const g of grupos) {
    pen += g.capitalActivoPen
    usd += g.capitalActivoUsd
    if (g.tieneCapital) conCapital += 1
    for (const c of g.contratos) {
      if (c.estado !== 'activo' || !c.fecha_vencimiento) continue
      const dias = diasHasta(c.fecha_vencimiento, hoy)
      if (dias >= 0 && dias <= 30) porVencer += 1
    }
  }
  return {
    capitalActivoPen: redondear2(pen),
    capitalActivoUsd: redondear2(usd),
    clientesConCapital: conCapital,
    totalClientes: grupos.length,
    porVencer30: porVencer,
  }
}
