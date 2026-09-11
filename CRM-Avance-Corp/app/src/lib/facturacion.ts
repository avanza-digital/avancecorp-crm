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
import { totalEnSoles, type CapitalUnificado } from './capital-unificado'
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

const LETRAS_DIA = ['D', 'L', 'M', 'M', 'J', 'V', 'S'] as const

/** Inicial del día de la semana para la cabecera estrecha de la malla. */
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
  const dias = diasDelMes(mes)
  const indicePorDia = new Map<string, number>()
  dias.forEach((dia, i) => indicePorDia.set(dia, i))

  const porAnalista = new Map<string, Acumulador>()
  // El roster SIEMBRA la malla antes que las ventas: así el analista que no
  // vendió nada tiene su fila, en cero, en lugar de desaparecer. Se siembra
  // primero y no después para que la venta, si la hay, sobrescriba el
  // supervisor de hoy por el HISTÓRICO que trae la fila.
  for (const p of roster) {
    porAnalista.set(p.id, {
      nombre: p.nombre,
      supervisorId: p.supervisorId,
      supervisorNombre: p.supervisorNombre,
      dias: new Map(),
    })
  }
  for (const f of filas) {
    if (f.moneda !== moneda || f.tipo !== tipo) continue
    const indice = indicePorDia.get(f.dia)
    if (indice == null) continue
    let acc = porAnalista.get(f.analistaId)
    if (acc == null) {
      acc = {
        nombre: f.analistaNombre,
        supervisorId: f.supervisorId,
        supervisorNombre: f.supervisorNombre,
        dias: new Map(),
      }
      porAnalista.set(f.analistaId, acc)
    } else {
      // Venía sembrado desde el roster, con el equipo de HOY. La fila manda:
      // trae el supervisor de entonces, que es a quien le corresponde la venta.
      acc.nombre = f.analistaNombre
      acc.supervisorId = f.supervisorId
      acc.supervisorNombre = f.supervisorNombre
    }
    acc.dias.set(indice, sumar(acc.dias.get(indice) ?? CELDA_VACIA, f))
  }

  // Fila por analista, ya con su vector de días completo.
  const porPersona: Array<{ fila: FilaFacturacion; supervisorId: string; supervisorNombre: string }> = []
  for (const [id, acc] of porAnalista) {
    const vector = dias.map((_, i) => acc.dias.get(i) ?? CELDA_VACIA)
    const total = vector.reduce(acumular, CELDA_VACIA)
    porPersona.push({
      fila: { id, nombre: acc.nombre, dias: vector, total },
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
 * El roster que sale SOLO de lo vendido. Se conserva porque es la base de
 * `rosterDeEquipoYFilas` y porque el supervisor que trae es el HISTÓRICO —el de
 * entonces, reconstruido por el servidor—, que es el dato bueno para quien sí
 * vendió. Por sí sola deja fuera al analista sin ventas: para eso está la otra.
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
  const porId = new Map<string, PersonaFacturacion>()
  for (const p of rosterDeFilas(filas)) porId.set(p.id, p)

  const nombrePorId = new Map<string, string>()
  for (const m of equipo) nombrePorId.set(m.id, m.nombre)

  for (const m of equipo) {
    if (m.rol !== 'vendedor' || !m.activo || porId.has(m.id)) continue
    const supervisorId = m.supervisorId ?? SIN_SUPERVISOR_ID
    porId.set(m.id, {
      id: m.id,
      nombre: m.nombre,
      supervisorId,
      supervisorNombre: nombrePorId.get(supervisorId) ?? SIN_SUPERVISOR_NOMBRE,
    })
  }
  return [...porId.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es-PE'))
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
    (id) => roster.find((p) => p.id === id)?.supervisorId === filtro.equipo,
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

/** Las filas de analista de la malla, en plano y con su equipo — la vista de comparación. */
export function filasComparadas(
  malla: MallaFacturacion,
): Array<FilaFacturacion & { supervisorNombre: string }> {
  return malla.grupos
    .flatMap((g) => g.analistas.map((a) => ({ ...a, supervisorNombre: g.nombre })))
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
): FilaFacturacionDia[] {
  return filas
    .filter((f) => f.analistaId === analistaId && (dia == null || f.dia === dia))
    .sort((a, b) => a.dia.localeCompare(b.dia) || b.capital - a.capital)
}
