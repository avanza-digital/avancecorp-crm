// lib/facturacion.ts — modelo de la malla de Facturación: día × supervisor × analista.
//
// Este archivo NO habla con el servidor. Recibe las filas que ya devuelve
// `crm.facturacion_diaria_fn` (en producción desde el 10/09/2026) y las
// convierte en la matriz que pinta la pantalla. La fuente es intercambiable: la
// misma forma la sirve el fixture de ejemplo (lib/demo-facturacion.ts).
//
// Las filas dicen quién VENDIÓ. Quién PODRÍA haber vendido lo dice el
// organigrama (`crm.equipo_visible_fn`), y por eso el roster se construye con
// los dos: un analista con el mes en cero también tiene que poder consultarse.
//
// Reglas de negocio que el llamador debe respetar al construir esa lista (las
// mismas que ya usan Ranking y Metas, ver CLAUDE.md y la nota del vault):
//   · el día es `contratos.fecha_cierre_comercial` (día comercial de Lima),
//   · solo `categoria = 'nuevo'` y sin demo,
//   · el analista es el de la cadena de atribución, no el que teclea,
//   · ANULAR NO DESCUENTA CAPITAL. Es la regla ATR-4 («solo la conversión,
//     siempre», Miguel 31/08): anular sanciona la tasa de conversión del
//     analista, no borra el dinero que la empresa recibió. El núcleo
//     (`crm.metricas_capital_mes_fn`) tampoco lo descuenta,
//   · PEN y USD JAMÁS se suman: la malla se construye para UNA moneda.
import { tcAplicable, totalEnSoles, type CapitalUnificado } from './capital-unificado'
import { usdAPen } from './tipo-cambio'
import { parseDateLocal, formatDateLocal } from './cronograma'
import type { Moneda } from './format'

/**
 * Una fila tal y como la devuelve `crm.facturacion_diaria_fn`: el servidor YA
 * agrupó por día, tipo, moneda, analista y supervisor. La malla no ve contratos
 * sueltos, y por eso el detalle de una celda tampoco puede listarlos — lo que
 * enseña es el desglose real de esa celda. Es a propósito: un modo demo que
 * mostrara contratos uno a uno prometería algo que producción no puede dar.
 */
export interface FilaFacturacionDia {
  /** `fecha_cierre_comercial` en 'YYYY-MM-DD'. */
  readonly dia: string
  /** `contrato_nuevo`, `contrato_upgrade`, `contrato_renovacion`, `cooperativa`. */
  readonly tipo: string
  readonly moneda: Moneda
  readonly analistaId: string
  readonly analistaNombre: string
  readonly supervisorId: string
  readonly supervisorNombre: string
  readonly operaciones: number
  readonly capital: number
}

/** El tipo que la pantalla muestra por defecto: capital nuevo. */
export const TIPO_CAPITAL_NUEVO = 'contrato_nuevo'

/**
 * Los tipos de capital que la pantalla ofrece, y `'todo'`, que no filtra nada.
 *
 * Miguel, 11/09/2026, al no encontrar un contrato suyo: la malla estaba clavada
 * en capital nuevo y no había perilla, así que renovaciones, upgrades y
 * cooperativa NO tenían dónde aparecer — en setiembre eso dejaba fuera
 * S/ 389 300 y US$ 21 000 de dinero real. El servidor ya devolvía el tipo; lo
 * que faltaba era poder elegirlo.
 *
 * `'todo'` suma los cuatro (y cualquier tipo nuevo que el servidor añada
 * mañana): son capital de la misma moneda, así que sumarlos es legítimo. Lo que
 * NO se mezcla jamás son las monedas.
 */
export const TIPO_TODOS = 'todo'
export const TIPOS_FACTURACION = [
  TIPO_CAPITAL_NUEVO,
  'contrato_renovacion',
  'contrato_upgrade',
  'cooperativa',
  TIPO_TODOS,
] as const
export type TipoFacturacion = (typeof TIPOS_FACTURACION)[number]

/** Qué se está mirando en la malla. Union + `as const`: el proyecto no usa enum. */
export const METRICAS_FACTURACION = ['capital', 'contratos'] as const
export type MetricaFacturacion = (typeof METRICAS_FACTURACION)[number]

export interface CeldaFacturacion {
  readonly capital: number
  readonly contratos: number
}

export interface FilaFacturacion {
  readonly id: string
  readonly nombre: string
  /** Una celda por día del mes, en orden; el índice 0 es el día 1. */
  readonly dias: readonly CeldaFacturacion[]
  readonly total: CeldaFacturacion
}

export interface GrupoFacturacion extends FilaFacturacion {
  readonly analistas: readonly FilaFacturacion[]
}

export interface MallaFacturacion {
  /** Primer día del mes en 'YYYY-MM-DD'. */
  readonly mes: string
  readonly dias: readonly string[]
  readonly grupos: readonly GrupoFacturacion[]
  readonly totalPorDia: readonly CeldaFacturacion[]
  readonly total: CeldaFacturacion
  /** Máximos por tipo de fila — la escala de color se lee sobre iguales. */
  readonly maxAnalista: CeldaFacturacion
  readonly maxGrupo: CeldaFacturacion
  readonly maxDia: CeldaFacturacion
}

const CELDA_VACIA: CeldaFacturacion = { capital: 0, contratos: 0 }

/** Valor de una celda según la métrica activa. Fuente única: nadie re-deriva el ternario. */
export function valorCelda(
  celda: CeldaFacturacion | undefined,
  metrica: MetricaFacturacion,
): number {
  if (celda == null) return 0
  return metrica === 'capital' ? celda.capital : celda.contratos
}

/** Primer día del mes de una fecha 'YYYY-MM-DD' (o de un epoch). */
export function primerDiaDelMes(fecha: string | number): string {
  const d = typeof fecha === 'number' ? new Date(fecha) : parseDateLocal(fecha)
  return formatDateLocal(new Date(d.getFullYear(), d.getMonth(), 1))
}

/** Mes vecino: `mesDesplazado('2026-09-01', -1)` → '2026-08-01'. */
export function mesDesplazado(mes: string, delta: number): string {
  const d = parseDateLocal(mes)
  return formatDateLocal(new Date(d.getFullYear(), d.getMonth() + delta, 1))
}

/** Todos los días del mes en 'YYYY-MM-DD', del 1 al último. */
export function diasDelMes(mes: string): string[] {
  const d = parseDateLocal(mes)
  const anio = d.getFullYear()
  const indiceMes = d.getMonth()
  const cuantos = new Date(anio, indiceMes + 1, 0).getDate()
  const dias: string[] = []
  for (let i = 1; i <= cuantos; i += 1) dias.push(formatDateLocal(new Date(anio, indiceMes, i)))
  return dias
}

/** 0 = domingo … 6 = sábado, leído en zona local (nunca `new Date(iso)`, que sería UTC). */
export function diaSemana(dia: string): number {
  return parseDateLocal(dia).getDay()
}

export function esDomingo(dia: string): boolean {
  return diaSemana(dia) === 0
}

export function esFinDeSemana(dia: string): boolean {
  const n = diaSemana(dia)
  return n === 0 || n === 6
}

// Dos letras, no una: con «M» para martes y para miércoles la cabecera obligaba
// a contar desde el lunes. (Auditoría de Facturación, 08/10/2026.)
const LETRAS_DIA = ['Do', 'Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá'] as const

/** Abreviatura del día de la semana para la cabecera estrecha de la malla. */
export function letraDia(dia: string): string {
  return LETRAS_DIA[diaSemana(dia)] ?? '·'
}

/** Número del día del mes, tal cual va en la cabecera de columna. */
export function numeroDia(dia: string): number {
  return parseDateLocal(dia).getDate()
}

/** 'setiembre de 2026' — rótulo del selector de mes. */
export function etiquetaMes(mes: string): string {
  return parseDateLocal(mes).toLocaleDateString('es-PE', { month: 'long', year: 'numeric' })
}

/** 'jueves 10 de setiembre' — título del panel de detalle. */
export function etiquetaDiaLargo(dia: string): string {
  return parseDateLocal(dia).toLocaleDateString('es-PE', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  })
}

/**
 * Paso de color 0..6 de una celda dentro de su escala. Secuencial de un solo
 * tono (regla del proyecto: nunca un arcoíris para representar magnitud), y el
 * 0 es su propio paso — «no vendió» no es «vendió poco».
 */
export function nivelFacturacion(valor: number, maximo: number): number {
  if (valor <= 0 || maximo <= 0) return 0
  const p = valor / maximo
  if (p <= 0.1) return 1
  if (p <= 0.25) return 2
  if (p <= 0.44) return 3
  if (p <= 0.64) return 4
  if (p <= 0.85) return 5
  return 6
}

/* ───────────────────── ESCALA DE COLOR DE LA MALLA ─────────────────────
 * Vive aquí, y no en la pantalla, para que su contraste se pueda MEDIR en una
 * prueba. Nació de un fallo real: el paso del 66 % con texto blanco daba 2.83:1
 * —muy por debajo del 4.5:1 de la WCAG— y era justo el escalón de las celdas de
 * más volumen. La regla que quedó: el blanco solo entra cuando el fondo es
 * acento puro o navy; por debajo, tinta oscura.
 *
 * El CRM es de tema claro único (ver index.css), así que los hexadecimales de
 * los tokens se pueden resolver aquí sin mentir. `bg`/`fg` son lo que consume el
 * `style` de la celda; `bgHex`/`fgHex` son los MISMOS colores ya resueltos, y
 * ambos salen de la misma fuente: nadie puede cambiar uno y olvidarse del otro.
 */

const ACENTO_HEX = '#2563eb' // --accent
const CARD_HEX = '#ffffff' // --card
const NAVY_HEX = '#111e3d' // --primary
const TINTA_TENUE_HEX = '#475569' // --muted-foreground-strong

export interface PasoEscalaFacturacion {
  readonly bg: string
  readonly fg: string
  readonly bgHex: string
  readonly fgHex: string
}

function canal(hex: string, desde: number): number {
  return Number.parseInt(hex.slice(desde, desde + 2), 16)
}

/** Mezcla sRGB de dos hexadecimales, el mismo cálculo que hace `color-mix`. */
function mezclarHex(a: string, b: string, pct: number): string {
  const p = pct / 100
  const partes = [1, 3, 5].map((i) => Math.round(canal(a, i) * p + canal(b, i) * (1 - p)))
  return `#${partes.map((n) => n.toString(16).padStart(2, '0')).join('')}`
}

function pasoMezclado(pct: number): PasoEscalaFacturacion {
  return {
    bg: `color-mix(in srgb, var(--accent) ${pct}%, var(--card))`,
    fg: 'var(--primary)',
    bgHex: mezclarHex(ACENTO_HEX, CARD_HEX, pct),
    fgHex: NAVY_HEX,
  }
}

/** Los siete pasos, del vacío al navy. El índice lo elige `nivelFacturacion`. */
export const ESCALA_FACTURACION: readonly PasoEscalaFacturacion[] = [
  { bg: 'transparent', fg: 'var(--muted-foreground-strong)', bgHex: CARD_HEX, fgHex: TINTA_TENUE_HEX },
  pasoMezclado(12),
  pasoMezclado(24),
  pasoMezclado(42),
  pasoMezclado(66),
  { bg: 'var(--accent)', fg: 'var(--accent-foreground)', bgHex: ACENTO_HEX, fgHex: CARD_HEX },
  { bg: 'var(--primary)', fg: 'var(--primary-foreground)', bgHex: NAVY_HEX, fgHex: CARD_HEX },
]

/** El paso que toca, ya resuelto; nunca `undefined`. */
export function pasoDeEscala(valor: number, maximo: number): PasoEscalaFacturacion {
  const paso = ESCALA_FACTURACION[nivelFacturacion(valor, maximo)]
  return paso ?? { bg: 'transparent', fg: 'inherit', bgHex: CARD_HEX, fgHex: TINTA_TENUE_HEX }
}

function sumar(a: CeldaFacturacion, fila: FilaFacturacionDia): CeldaFacturacion {
  return { capital: a.capital + fila.capital, contratos: a.contratos + fila.operaciones }
}

function acumular(a: CeldaFacturacion, b: CeldaFacturacion): CeldaFacturacion {
  return { capital: a.capital + b.capital, contratos: a.contratos + b.contratos }
}

function maximo(a: CeldaFacturacion, b: CeldaFacturacion): CeldaFacturacion {
  return { capital: Math.max(a.capital, b.capital), contratos: Math.max(a.contratos, b.contratos) }
}

interface Acumulador {
  nombre: string
  supervisorId: string
  supervisorNombre: string
  dias: Map<number, CeldaFacturacion>
}

/**
 * Convierte las filas del servidor en la matriz del mes, PARA UNA MONEDA y UN
 * TIPO. Lo que cae fuera se ignora en silencio: la pantalla pide siempre un mes,
 * una moneda y un tipo concretos, y mezclarlos sería mentir (PEN y USD jamás se
 * suman, y una renovación no es capital nuevo).
 */
export function construirMalla(
  filas: readonly FilaFacturacionDia[],
  mes: string,
  moneda: Moneda,
  tipo: string = TIPO_CAPITAL_NUEVO,
  roster: readonly PersonaFacturacion[] = [],
): MallaFacturacion {
  return construirMallaDeDias(filas, diasDelMes(mes), mes, moneda, tipo, roster)
}

/**
 * La misma malla, pero sobre un TRAMO de días cualquiera — Miguel, 11/09/2026:
 * quiere mirar una semana o un día suelto, no solo el mes.
 *
 * `construirMalla` es el caso particular «todos los días del mes». Se separan
 * para que la semana y el día no sean un recorte visual: los totales, el mejor
 * día y el promedio se calculan SOBRE EL TRAMO, que es lo que se está mirando.
 */
export function construirMallaDeDias(
  filas: readonly FilaFacturacionDia[],
  dias: readonly string[],
  mes: string,
  moneda: Moneda,
  tipo: string = TIPO_CAPITAL_NUEVO,
  roster: readonly PersonaFacturacion[] = [],
): MallaFacturacion {
  const indicePorDia = new Map<string, number>()
  dias.forEach((dia, i) => indicePorDia.set(dia, i))

  // CLAVE COMPUESTA: analista + supervisor de entonces.
  //
  // Antes se acumulaba solo por analista y cada fila sobrescribía el supervisor,
  // así que un analista que vendió bajo DOS supervisores en el mismo mes —el que
  // cambia de equipo a mitad de mes— acababa con TODO su dinero en uno solo, el
  // de la última fila. El total de la empresa cuadraba igual, de modo que ninguna
  // prueba de totales lo habría cazado nunca. Ahora sale en los dos equipos, cada
  // uno con lo que de verdad se cerró bajo él. (Auditoría de Codex, 11/09/2026.)
  const clave = (analistaId: string, supervisorId: string): string =>
    `${analistaId}\u0000${supervisorId}`
  const porFila = new Map<string, Acumulador & { analistaId: string }>()

  // Las VENTAS primero: cada una entra en su equipo de entonces.
  for (const f of filas) {
    // `TIPO_TODOS` no filtra: entra cualquier tipo, incluso uno que el servidor
    // añada en el futuro y que esta pantalla todavía no sepa rotular.
    if (f.moneda !== moneda || (tipo !== TIPO_TODOS && f.tipo !== tipo)) continue
    const indice = indicePorDia.get(f.dia)
    if (indice == null) continue
    const k = clave(f.analistaId, f.supervisorId)
    let acc = porFila.get(k)
    if (acc == null) {
      acc = {
        analistaId: f.analistaId,
        nombre: f.analistaNombre,
        supervisorId: f.supervisorId,
        supervisorNombre: f.supervisorNombre,
        dias: new Map(),
      }
      porFila.set(k, acc)
    }
    acc.dias.set(indice, sumar(acc.dias.get(indice) ?? CELDA_VACIA, f))
  }

  // El roster siembra después los ceros: equipos históricos donde esta moneda
  // o tipo no tuvo ventas y personas sin ventas del equipo actual. No se añade
  // un equipo actual extra a quien ya vendió bajo otro supervisor.
  const conVentas = new Set([...porFila.values()].map((a) => a.analistaId))
  for (const p of roster) {
    const k = clave(p.id, p.supervisorId)
    // Un equipo histórico conserva su fila en cero al cambiar de tipo o moneda.
    // El equipo actual no añade una fila fantasma si la persona ya vendió.
    if (porFila.has(k) || (conVentas.has(p.id) && !p.historico)) continue
    porFila.set(k, {
      analistaId: p.id,
      nombre: p.nombre,
      supervisorId: p.supervisorId,
      supervisorNombre: p.supervisorNombre,
      dias: new Map(),
    })
  }

  // Fila por analista y equipo, ya con su vector de días completo.
  const porPersona: Array<{ fila: FilaFacturacion; supervisorId: string; supervisorNombre: string }> = []
  for (const acc of porFila.values()) {
    const vector = dias.map((_, i) => acc.dias.get(i) ?? CELDA_VACIA)
    const total = vector.reduce(acumular, CELDA_VACIA)
    porPersona.push({
      // El `id` sigue siendo el del ANALISTA: es lo que usan el filtro y la
      // casilla de comparar, y marcarle debe traer sus dos equipos.
      fila: { id: acc.analistaId, nombre: acc.nombre, dias: vector, total },
      supervisorId: acc.supervisorId,
      supervisorNombre: acc.supervisorNombre,
    })
  }

  // Agrupación por supervisor, conservando el orden de aparición del equipo.
  const porSupervisor = new Map<string, { nombre: string; filas: FilaFacturacion[] }>()
  for (const f of porPersona) {
    let grupo = porSupervisor.get(f.supervisorId)
    if (grupo == null) {
      grupo = { nombre: f.supervisorNombre, filas: [] }
      porSupervisor.set(f.supervisorId, grupo)
    }
    grupo.filas.push(f.fila)
  }

  const grupos: GrupoFacturacion[] = []
  for (const [id, g] of porSupervisor) {
    const analistas = [...g.filas].sort(
      (a, b) => b.total.capital - a.total.capital || a.nombre.localeCompare(b.nombre, 'es-PE'),
    )
    const vector = dias.map((_, i) =>
      analistas.reduce((acc, a) => acumular(acc, a.dias[i] ?? CELDA_VACIA), CELDA_VACIA),
    )
    grupos.push({
      id,
      nombre: g.nombre,
      dias: vector,
      total: vector.reduce(acumular, CELDA_VACIA),
      analistas,
    })
  }
  grupos.sort(
    (a, b) => b.total.capital - a.total.capital || a.nombre.localeCompare(b.nombre, 'es-PE'),
  )

  const totalPorDia = dias.map((_, i) =>
    grupos.reduce((acc, g) => acumular(acc, g.dias[i] ?? CELDA_VACIA), CELDA_VACIA),
  )

  let maxAnalista = CELDA_VACIA
  let maxGrupo = CELDA_VACIA
  for (const g of grupos) {
    for (const celda of g.dias) maxGrupo = maximo(maxGrupo, celda)
    for (const a of g.analistas) for (const celda of a.dias) maxAnalista = maximo(maxAnalista, celda)
  }

  return {
    mes,
    dias,
    grupos,
    totalPorDia,
    total: totalPorDia.reduce(acumular, CELDA_VACIA),
    maxAnalista,
    maxGrupo,
    maxDia: totalPorDia.reduce(maximo, CELDA_VACIA),
  }
}

/* ────────────────────────────── FILTRO ──────────────────────────────
 * Misma forma que la consulta del módulo Citas: campos planos, «sin filtro»
 * es SIEMPRE la cadena vacía o el array vacío — nunca null. Así el filtrado
 * es una sola expresión booleana y restablecer es volver a `filtroInicial()`.
 */

export interface FiltroFacturacion {
  /** id del supervisor; '' = todos los equipos. */
  readonly equipo: string
  /** ids de analista; [] = todos. Con uno se aísla; con varios se comparan. */
  readonly analistas: readonly string[]
}

export function filtroInicial(): FiltroFacturacion {
  return { equipo: '', analistas: [] }
}

export function filtroVacio(filtro: FiltroFacturacion): boolean {
  return filtro.equipo === '' && filtro.analistas.length === 0
}

/** Una persona tal como la ofrece el selector, ya con su equipo. */
export interface PersonaFacturacion {
  readonly id: string
  readonly nombre: string
  readonly supervisorId: string
  readonly supervisorNombre: string
  /** La pareja analista + supervisor existió en una venta del tramo. */
  readonly historico?: boolean
}

/**
 * Id y rótulo de la fila «sin supervisor». El servidor ya emite el rótulo
 * (`coalesce(ps.nombre_completo, 'Sin supervisor')`); el id lo pone el cliente
 * porque la RPC manda NULL y un `Map` necesita una clave. Viven aquí, en el
 * modelo, y no en la capa de datos: son parte del dominio de la malla.
 */
export const SIN_SUPERVISOR_ID = 'sin-supervisor'
export const SIN_SUPERVISOR_NOMBRE = 'Sin supervisor'

/**
 * Un miembro del organigrama, en la forma mínima que el roster necesita. Es la
 * proyección de `crm.equipo_visible_fn` (ver `Miembro` en lib/tipos.ts); no se
 * reutiliza ese tipo para que el modelo siga siendo puro y comprobable sin
 * arrastrar los tipos de la capa de datos.
 */
export interface MiembroEquipo {
  readonly id: string
  readonly nombre: string
  readonly rol: string
  readonly supervisorId: string | null
  readonly activo: boolean
}

/**
 * Un roster simple derivado de ventas, con una entrada por analista. El roster
 * completo conserva además cada pareja histórica de analista y supervisor.
 */
export function rosterDeFilas(
  filas: readonly FilaFacturacionDia[],
): PersonaFacturacion[] {
  const porId = new Map<string, PersonaFacturacion>()
  for (const f of filas) {
    if (!porId.has(f.analistaId)) {
      porId.set(f.analistaId, {
        id: f.analistaId,
        nombre: f.analistaNombre,
        supervisorId: f.supervisorId,
        supervisorNombre: f.supervisorNombre,
        historico: true,
      })
    }
  }
  return [...porId.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es-PE'))
}

/**
 * El roster COMPLETO: quien vendió, más todo analista vigente que no vendió.
 *
 * Miguel, 11/09/2026: «arregla lo de el analista que no ha vendido, sí quiero
 * que salga». Antes el selector se llenaba con las propias ventas, así que un
 * analista con el mes en cero era invisible — y no poder preguntar por él es
 * justo lo contrario de lo que sirve un tablero de ventas: el cero es la
 * respuesta, no la ausencia de pregunta.
 *
 * Dos procedencias, y el orden importa:
 *  · quien VENDIÓ entra con su supervisor HISTÓRICO (el de entonces, que el
 *    servidor reconstruye desde `crm.usuario_eventos`). Manda sobre el equipo
 *    de hoy: si alguien cambió de equipo, su venta sigue contando donde estaba.
 *  · quien NO vendió entra con su supervisor de HOY, porque no hay venta que
 *    anclar a una fecha. Es la única lectura posible y no engaña a nadie: una
 *    fila en cero no atribuye dinero a ningún equipo.
 *
 * Solo se añaden analistas ACTIVOS. Un analista dado de baja que no vendió nada
 * este mes no tiene por qué aparecer; si vendió, ya entró por la primera vía.
 */
export function rosterDeEquipoYFilas(
  equipo: readonly MiembroEquipo[],
  filas: readonly FilaFacturacionDia[],
): PersonaFacturacion[] {
  // Una persona puede haber vendido bajo dos supervisores durante el tramo.
  // El selector necesita ambas parejas, aunque la selección siga siendo por id.
  const porPareja = new Map<string, PersonaFacturacion>()
  const conVentas = new Set<string>()
  for (const f of filas) {
    conVentas.add(f.analistaId)
    const clave = `${f.analistaId}\u0000${f.supervisorId}`
    if (!porPareja.has(clave)) {
      porPareja.set(clave, {
        id: f.analistaId,
        nombre: f.analistaNombre,
        supervisorId: f.supervisorId,
        supervisorNombre: f.supervisorNombre,
        historico: true,
      })
    }
  }

  const nombrePorId = new Map<string, string>()
  for (const m of equipo) nombrePorId.set(m.id, m.nombre)

  for (const m of equipo) {
    if (m.rol !== 'vendedor' || !m.activo || conVentas.has(m.id)) continue
    const supervisorId = m.supervisorId ?? SIN_SUPERVISOR_ID
    porPareja.set(`${m.id}\u0000${supervisorId}`, {
      id: m.id,
      nombre: m.nombre,
      supervisorId,
      supervisorNombre: nombrePorId.get(supervisorId) ?? SIN_SUPERVISOR_NOMBRE,
    })
  }
  return [...porPareja.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es-PE'))
}

/** Los equipos presentes en un roster, sin repetir y por nombre. */
export function equiposDeRoster(
  roster: readonly PersonaFacturacion[],
): Array<{ id: string; nombre: string }> {
  const porId = new Map<string, string>()
  for (const p of roster) if (!porId.has(p.supervisorId)) porId.set(p.supervisorId, p.supervisorNombre)
  return [...porId.entries()]
    .map(([id, nombre]) => ({ id, nombre }))
    .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es-PE'))
}

/** Aplica el filtro ANTES de construir la malla: así los totales ya son los del filtro. */
export function filtrarFilas(
  filas: readonly FilaFacturacionDia[],
  filtro: FiltroFacturacion,
): FilaFacturacionDia[] {
  return filas.filter(
    (f) =>
      (filtro.equipo === '' || f.supervisorId === filtro.equipo) &&
      (filtro.analistas.length === 0 || filtro.analistas.includes(f.analistaId)),
  )
}

/**
 * El mismo filtro, aplicado a personas. Hace falta porque la malla ya no se
 * construye solo con lo vendido: también se siembra con el roster, y sembrarlo
 * sin filtrar haría que elegir a un analista siguiera enseñando a todos los
 * demás en cero. Las dos funciones deciden con las MISMAS dos condiciones.
 */
export function filtrarRoster(
  roster: readonly PersonaFacturacion[],
  filtro: FiltroFacturacion,
): PersonaFacturacion[] {
  return roster.filter(
    (p) =>
      (filtro.equipo === '' || p.supervisorId === filtro.equipo) &&
      (filtro.analistas.length === 0 || filtro.analistas.includes(p.id)),
  )
}

/**
 * Corrige el filtro tras un cambio de equipo: los analistas elegidos que ya no
 * pertenecen a ese equipo se caen. Quitar el equipo ('') NO borra la selección
 * de analistas — misma guarda que en Citas, y por el mismo motivo: dejar de
 * acotar no debería costarte lo que ya habías elegido.
 */
export function conciliarFiltro(
  filtro: FiltroFacturacion,
  roster: readonly PersonaFacturacion[],
): FiltroFacturacion {
  if (filtro.equipo === '' || filtro.analistas.length === 0) return filtro
  const permitidos = filtro.analistas.filter(
    (id) => roster.some((p) => p.id === id && p.supervisorId === filtro.equipo),
  )
  return permitidos.length === filtro.analistas.length ? filtro : { ...filtro, analistas: permitidos }
}

/**
 * El total del día con las DOS monedas juntas — Miguel, 11/09/2026: «necesito
 * ver el total de soles y dólares por día; me gusta verlo por separado, pero
 * necesito ver un total».
 *
 * El CAPITAL no se suma a ciegas: se convierte el USD a soles con el mismo motor
 * que ya usa Gestión de equipo (`totalEnSoles`, decisión #10 de Miguel del
 * 10/08/2026), a un tipo de cambio real y conocido. Sin tipo de cambio el total
 * queda SOLO en soles y el dólar viaja aparte, rotulado — jamás se inventa tasa.
 * Convertir a tasa real ≠ sumar peras con manzanas; la regla «PEN y USD jamás se
 * suman» sigue intacta para el capital crudo de la tabla de arriba.
 *
 * Los CONTRATOS sí se suman tal cual: son cuentas, no dinero. Tres contratos en
 * soles y uno en dólares son cuatro contratos, sin conversión que valga.
 */
export interface TotalDiaFacturacion {
  readonly capital: CapitalUnificado
  readonly contratos: number
}

/**
 * ¿Se puede AFIRMAR este total en soles?
 *
 * Sí cuando la conversión ocurrió de verdad… y también cuando no había nada que
 * convertir: un día sin un solo dólar tiene su total completo en soles, haya o
 * no tipo de cambio. Exigir tasa ahí pondría un guion sobre una cifra que sí se
 * conoce. (Lo señaló Codex el 11/09/2026; mi versión pedía tasa siempre.)
 *
 * No cuando falta la tasa y SÍ hay dólares: ese total excluiría dinero real, y
 * enseñarlo bajo el rótulo «en soles» se leería como si estuviera todo dentro.
 */
export function totalAfirmable(capital: CapitalUnificado): boolean {
  if (capital.total == null) return false
  return capital.estado === 'convertido' || capital.usd === 0
}

export function totalesUnificados(
  mallaPen: MallaFacturacion,
  mallaUsd: MallaFacturacion,
  tc: number | null | undefined,
): { porDia: readonly TotalDiaFacturacion[]; mes: TotalDiaFacturacion } {
  // PRECONDICIÓN: las dos mallas son del MISMO mes, así que comparten calendario.
  // Se usa el de soles sin más. (Antes había un `Math.min` de las dos longitudes:
  // no protegía de nada —construirMalla genera los días a partir del mes— y, si
  // alguna vez divergieran, habría escondido el fallo recortando días en
  // silencio. Codex, 11/09/2026.)
  const porDia: TotalDiaFacturacion[] = []
  for (let i = 0; i < mallaPen.dias.length; i += 1) {
    const pen = mallaPen.totalPorDia[i] ?? CELDA_VACIA
    const usd = mallaUsd.totalPorDia[i] ?? CELDA_VACIA
    porDia.push({
      capital: totalEnSoles(pen.capital, usd.capital, tc),
      contratos: pen.contratos + usd.contratos,
    })
  }
  return {
    porDia,
    mes: {
      capital: totalEnSoles(mallaPen.total.capital, mallaUsd.total.capital, tc),
      contratos: mallaPen.total.contratos + mallaUsd.total.contratos,
    },
  }
}

/**
 * Las DOS monedas en una sola malla, celda a celda — Miguel, 11/09/2026: «en el
 * tablero quiero ver el total de cada analista por día».
 *
 * Cada celda pasa a ser `soles + dólares × tipo de cambio`. Es la misma
 * excepción que el proyecto ya aprobó para el titular y el pie (decisión #10,
 * `totalEnSoles`): no se suman peras con manzanas, se CONVIERTE a una tasa real
 * y conocida, y quien la pinta está obligado a rotularla.
 *
 * Devuelve `null` SIN TASA. No hay versión degradada: una malla entera rotulada
 * «total» que en realidad solo trae los soles sería la mentira más cara de esta
 * pantalla, porque se lee celda a celda y nadie mira la letra pequeña 31 veces.
 *
 * Los CONTRATOS se suman sin convertir: son cuentas, no dinero.
 */
export function combinarEnSoles(
  mallaPen: MallaFacturacion,
  mallaUsd: MallaFacturacion,
  tc: number | null | undefined,
): MallaFacturacion | null {
  const tasa = tcAplicable(tc)
  if (tasa == null) return null

  const aSoles = (pen: CeldaFacturacion, usd: CeldaFacturacion): CeldaFacturacion => ({
    capital: pen.capital + usdAPen(usd.capital, tasa),
    contratos: pen.contratos + usd.contratos,
  })
  const VACIA: CeldaFacturacion = { capital: 0, contratos: 0 }

  // Índice por id para casar analistas y equipos que solo existen en una moneda:
  // quien vendió únicamente en dólares tiene que aparecer igual.
  const filasUsdPorGrupo = new Map<string, Map<string, FilaFacturacion>>()
  for (const g of mallaUsd.grupos) {
    filasUsdPorGrupo.set(g.id, new Map(g.analistas.map((a) => [a.id, a])))
  }
  const gruposUsd = new Map(mallaUsd.grupos.map((g) => [g.id, g]))

  const combinarFila = (pen: FilaFacturacion | null, usd: FilaFacturacion | null): FilaFacturacion => {
    const base = pen ?? usd
    if (base == null) throw new Error('combinarFila sin ninguna de las dos monedas')
    const dias = base.dias.map((_, i) =>
      aSoles(pen?.dias[i] ?? VACIA, usd?.dias[i] ?? VACIA),
    )
    return {
      id: base.id,
      nombre: base.nombre,
      dias,
      total: aSoles(pen?.total ?? VACIA, usd?.total ?? VACIA),
    }
  }

  const grupos: GrupoFacturacion[] = []
  for (const gp of mallaPen.grupos) {
    const gu = gruposUsd.get(gp.id) ?? null
    const usdDelGrupo = filasUsdPorGrupo.get(gp.id) ?? new Map<string, FilaFacturacion>()
    const analistas = gp.analistas.map((a) => combinarFila(a, usdDelGrupo.get(a.id) ?? null))
    // Los que solo vendieron en dólares dentro de este equipo.
    for (const [id, a] of usdDelGrupo) {
      if (!gp.analistas.some((x) => x.id === id)) analistas.push(combinarFila(null, a))
    }
    analistas.sort((a, b) => b.total.capital - a.total.capital || a.nombre.localeCompare(b.nombre, 'es-PE'))
    grupos.push({ ...combinarFila(gp, gu), analistas })
  }
  // Equipos que solo existen en la malla de dólares.
  for (const gu of mallaUsd.grupos) {
    if (mallaPen.grupos.some((g) => g.id === gu.id)) continue
    grupos.push({
      ...combinarFila(null, gu),
      analistas: gu.analistas.map((a) => combinarFila(null, a)),
    })
  }
  grupos.sort((a, b) => b.total.capital - a.total.capital || a.nombre.localeCompare(b.nombre, 'es-PE'))

  const totalPorDia = mallaPen.dias.map((_, i) =>
    aSoles(mallaPen.totalPorDia[i] ?? VACIA, mallaUsd.totalPorDia[i] ?? VACIA),
  )
  let maxAnalista = VACIA
  let maxGrupo = VACIA
  for (const g of grupos) {
    for (const c of g.dias) maxGrupo = maximo(maxGrupo, c)
    for (const a of g.analistas) for (const c of a.dias) maxAnalista = maximo(maxAnalista, c)
  }
  return {
    mes: mallaPen.mes,
    dias: mallaPen.dias,
    grupos,
    totalPorDia,
    total: aSoles(mallaPen.total, mallaUsd.total),
    maxAnalista,
    maxGrupo,
    maxDia: totalPorDia.reduce(maximo, VACIA),
  }
}

/**
 * La misma malla, con TODAS sus columnas, pero con los totales calculados solo
 * sobre los días marcados a mano.
 *
 * Miguel, 11/09/2026: quiere marcar el 3, el 7 y el 12 y ver cuánto suman. La
 * primera versión escondía las demás columnas, y entonces no había forma de
 * marcar un cuarto día: la tabla se queda entera, los días elegidos se resaltan
 * y lo que cambia son los totales. Así se puede seguir añadiendo y quitando.
 *
 * Los días NO marcados conservan su cifra en la celda —el dato es cierto— pero
 * no entran en ningún total.
 */
export function totalesSoloDeDias(
  malla: MallaFacturacion,
  diasMarcados: readonly string[],
): MallaFacturacion {
  const marcados = new Set(diasMarcados)
  const indices = malla.dias.flatMap((d, i) => (marcados.has(d) ? [i] : []))
  if (indices.length === 0) return malla

  const sumar = (celdas: readonly CeldaFacturacion[]): CeldaFacturacion =>
    indices.reduce(
      (acc, i) => acumular(acc, celdas[i] ?? CELDA_VACIA),
      CELDA_VACIA,
    )

  const grupos = malla.grupos.map((g) => ({
    ...g,
    total: sumar(g.dias),
    analistas: g.analistas.map((a) => ({ ...a, total: sumar(a.dias) })),
  }))
  return {
    ...malla,
    grupos,
    total: sumar(malla.totalPorDia),
    // El «mejor día» y la escala solo miran lo marcado: un día no elegido no
    // puede ganar un ranking del que está fuera.
    maxDia: indices.reduce(
      (acc, i) => maximo(acc, malla.totalPorDia[i] ?? CELDA_VACIA),
      CELDA_VACIA,
    ),
  }
}

/** Las filas de analista de la malla, en plano y con su equipo — la vista de comparación. */
export function filasComparadas(
  malla: MallaFacturacion,
): Array<FilaFacturacion & { supervisorId: string; supervisorNombre: string }> {
  return malla.grupos
    .flatMap((g) => g.analistas.map((a) => ({ ...a, supervisorId: g.id, supervisorNombre: g.nombre })))
    .sort((a, b) => b.total.capital - a.total.capital || a.nombre.localeCompare(b.nombre, 'es-PE'))
}

/** El mejor día del mes según la métrica activa; null si el mes no tiene nada. */
export function mejorDia(
  malla: MallaFacturacion,
  metrica: MetricaFacturacion,
): { dia: string; valor: number } | null {
  let mejor: { dia: string; valor: number } | null = null
  malla.dias.forEach((dia, i) => {
    const valor = valorCelda(malla.totalPorDia[i], metrica)
    if (valor > 0 && (mejor == null || valor > mejor.valor)) mejor = { dia, valor }
  })
  return mejor
}

/* ───────────────────── PERIODO: mes, semana o día ─────────────────────
 * Miguel, 11/09/2026: «quiero que gerencia tenga filtros de semana y de días, ya
 * tenemos por mes». Las flechas que ya existían pasan a moverse en la unidad
 * elegida, y TODO lo de la pantalla se recalcula sobre el tramo — si el titular
 * siguiera diciendo el mes mientras la tabla enseña una semana, habría dos
 * verdades a la vez.
 *
 * La semana es de LUNES a DOMINGO: es como se habla del trabajo aquí, y deja el
 * domingo —el día que no se vende— al final, sin partir la semana en dos.
 */
export const GRANULARIDADES = ['mes', 'semana', 'dia'] as const
export type Granularidad = (typeof GRANULARIDADES)[number]

/** Lunes de la semana que contiene `dia`. */
export function lunesDeLaSemana(dia: string): string {
  const d = parseDateLocal(dia)
  // getDay(): 0 domingo … 6 sábado. Se retrocede al lunes; el domingo, 6 días.
  const retroceso = (d.getDay() + 6) % 7
  return formatDateLocal(new Date(d.getFullYear(), d.getMonth(), d.getDate() - retroceso))
}

/** Los días que abarca el periodo, en orden. */
export function diasDelPeriodo(granularidad: Granularidad, ancla: string): string[] {
  if (granularidad === 'dia') return [ancla]
  if (granularidad === 'mes') return diasDelMes(primerDiaDelMes(ancla))
  const lunes = parseDateLocal(lunesDeLaSemana(ancla))
  return Array.from({ length: 7 }, (_, i) =>
    formatDateLocal(new Date(lunes.getFullYear(), lunes.getMonth(), lunes.getDate() + i)),
  )
}

/** Los meses (primer día) que toca una lista de días, sin repetir y en orden. */
export function mesesQueTocan(dias: readonly string[]): string[] {
  const vistos = new Set<string>()
  for (const d of dias) vistos.add(primerDiaDelMes(d))
  return [...vistos].sort()
}

/** Mueve el ancla `delta` periodos (negativo = atrás). */
export function periodoDesplazado(
  granularidad: Granularidad,
  ancla: string,
  delta: number,
): string {
  if (granularidad === 'mes') return primerDiaDelMes(mesDesplazado(primerDiaDelMes(ancla), delta))
  const paso = granularidad === 'semana' ? 7 : 1
  const d = parseDateLocal(ancla)
  return formatDateLocal(new Date(d.getFullYear(), d.getMonth(), d.getDate() + delta * paso))
}

/** Cómo se nombra el periodo en la barra. */
export function etiquetaPeriodo(granularidad: Granularidad, ancla: string): string {
  if (granularidad === 'mes') return etiquetaMes(primerDiaDelMes(ancla))
  if (granularidad === 'dia') return etiquetaDiaLargo(ancla)
  const dias = diasDelPeriodo(granularidad, ancla)
  const primero = dias[0] ?? ancla
  const ultimo = dias[dias.length - 1] ?? ancla
  const corto = (d: string): string =>
    parseDateLocal(d).toLocaleDateString('es-PE', { day: 'numeric', month: 'short' })
  return `${corto(primero)} al ${corto(ultimo)}`
}

/**
 * Días con actividad posible hasta `hasta` (incluido): todo salvo domingo.
 * Es el divisor del promedio — contar los domingos lo hundiría un 17 % sin
 * que nadie haya dejado de vender.
 */
export function diasHabilesHasta(malla: MallaFacturacion, hasta: string): number {
  return malla.dias.filter((dia) => dia <= hasta && !esDomingo(dia)).length
}

/**
 * El desglose de una celda: qué tipos de capital y en qué monedas la componen.
 * NO son los contratos uno a uno — el servidor ya agrupó, y fingir una lista de
 * contratos aquí sería inventarla. Con `dia` en null, el mes entero del analista.
 */
export function desgloseDeCelda(
  filas: readonly FilaFacturacionDia[],
  analistaId: string,
  dia: string | null,
  tipo: TipoFacturacion = TIPO_TODOS,
  moneda?: Moneda,
  supervisorId?: string,
  diasElegidos?: readonly string[],
): FilaFacturacionDia[] {
  return filas
    .filter(
      (f) =>
        f.analistaId === analistaId &&
        (supervisorId === undefined || f.supervisorId === supervisorId) &&
        (dia == null || f.dia === dia) &&
        (dia != null || diasElegidos === undefined || diasElegidos.includes(f.dia)) &&
        // El detalle habla de LO QUE SE ESTÁ VIENDO: abrir una celda de
        // renovaciones y que el panel liste también los contratos nuevos
        // contradiría la cifra sobre la que se acaba de pinchar.
        (tipo === TIPO_TODOS || f.tipo === tipo) &&
        // Y de la MONEDA que se está viendo. Sin esto, abrir una celda de
        // dólares enseñaba soles dentro, con un rótulo que decía «Dólares».
        // (Auditoría de Codex, 11/09/2026.)
        (moneda === undefined || f.moneda === moneda),
    )
    .sort((a, b) => a.dia.localeCompare(b.dia) || b.capital - a.capital)
}
