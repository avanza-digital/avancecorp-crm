// lib/metricas.ts — helpers PUROS de pivoteo para las gráficas de gerencia.
// Entrada: filas de las RPCs crm.metricas_*_fn (ya validadas y con numeric
// coercionado a number por data/crm-api). Salida: puntos listos para recharts.
//
// Reglas duras que este módulo garantiza:
//  - PEN y USD JAMÁS se mezclan en una serie: cada pivot filtra por UNA moneda
//    y el caller pinta un chart (o tab) por moneda.
//  - Huecos de meses rellenados con 0 entre el primero y el último mes con
//    datos: el eje X queda continuo (sin saltos que mientan tendencia).
//  - `categoria` null (contratos viejos sin categoría) se agrupa como '—'.
// Sin Date/TZ: los meses se manejan como texto 'YYYY-MM' + aritmética entera,
// así los tests son deterministas en cualquier zona horaria.
import type { Moneda } from './format'

// ── Filas crudas de las 4 RPCs (contrato compartido con data/crm-api y con la
//    derivación demo) ───────────────────────────────────────────────────────────
export interface FilaCapitalMes {
  mes: string // 'YYYY-MM-01' (date del GROUP BY mensual)
  moneda: Moneda
  categoria: string | null
  contratos: number
  capital_colocado: number
}

export interface FilaPagosMes {
  mes: string
  moneda: Moneda
  tipo: string // 'cuota' | 'retorno' | 'devolucion'
  estado: string // 'pendiente' | 'pagado' | 'vencido' | 'trasladado'
  cuotas: number
  monto_programado: number
  monto_pagado: number
}

export interface FilaAltasAnalista {
  mes: string
  analista_id: string
  analista_nombre: string
  altas: number
}

export interface FilaVencimientos {
  mes: string
  moneda: Moneda
  contratos_por_vencer: number
  capital_por_vencer: number
}

// ── Meses como texto (sin Date: cero sorpresas de zona horaria) ────────────────

/** 'YYYY-MM' desde un date/timestamp ISO; null si no empieza como fecha. */
export function claveMes(fecha: string): string | null {
  const m = /^(\d{4})-(\d{2})/.exec(fecha)
  if (!m) return null
  const mesNum = Number(m[2])
  if (mesNum < 1 || mesNum > 12) return null
  return `${m[1]}-${m[2]}`
}

/** Etiqueta corta es-PE del eje X: '2026-07' → 'jul 26'. */
const MESES_CORTOS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'] as const

export function etiquetaMes(clave: string): string {
  const [anio, mes] = clave.split('-')
  const nombre = MESES_CORTOS[Number(mes) - 1]
  if (!anio || !nombre) return clave
  return `${nombre} ${anio.slice(2)}`
}

// 'YYYY-MM' ⇄ índice entero (año*12 + mes-1) para iterar rangos sin Date.
function aIndiceMes(clave: string): number {
  const [anio, mes] = clave.split('-')
  return Number(anio) * 12 + (Number(mes) - 1)
}

function aClaveMes(indice: number): string {
  const anio = Math.floor(indice / 12)
  const mes = (indice % 12) + 1
  return `${String(anio).padStart(4, '0')}-${String(mes).padStart(2, '0')}`
}

// Tope del relleno: una fecha basura (año 0201 por un typo) no debe fabricar
// miles de meses en cero. Si el rango excede esto, se devuelven solo los meses
// CON datos (eje discontinuo pero honesto, sin bomba de memoria).
const MAX_MESES_RELLENO = 120

/**
 * Meses continuos entre el menor y el mayor de las claves dadas (ambos
 * inclusive), ordenados ascendente. Vacío → []. Con claves inválidas se ignoran.
 */
export function mesesContinuos(claves: readonly string[]): string[] {
  const validas = [...new Set(claves.filter((c) => /^\d{4}-\d{2}$/.test(c)))]
  if (validas.length === 0) return []
  const indices = validas.map(aIndiceMes)
  const desde = Math.min(...indices)
  const hasta = Math.max(...indices)
  if (hasta - desde + 1 > MAX_MESES_RELLENO) return validas.sort()
  const meses: string[] = []
  for (let i = desde; i <= hasta; i += 1) meses.push(aClaveMes(i))
  return meses
}

/** Monedas presentes en las filas, en orden fijo PEN → USD (jamás mezcladas). */
export function monedasConDatos(filas: readonly { moneda: Moneda }[]): Moneda[] {
  const presentes = new Set(filas.map((f) => f.moneda))
  return (['PEN', 'USD'] as const).filter((m) => presentes.has(m))
}

// ── (a) Capital colocado por mes, apilado por categoría ───────────────────────

/** Clave del bucket "sin categoría" (categoria null o desconocida) — label '—'. */
export const SIN_CATEGORIA = 'sin_categoria'

const CATEGORIAS_CONOCIDAS = new Set(['nuevo', 'renovacion', 'upgrade'])

export interface PuntoCapitalMes {
  mes: string
  etiqueta: string
  nuevo: number
  renovacion: number
  upgrade: number
  sin_categoria: number
}

function puntoCapitalCero(mes: string): PuntoCapitalMes {
  return { mes, etiqueta: etiquetaMes(mes), nuevo: 0, renovacion: 0, upgrade: 0, sin_categoria: 0 }
}

/** Serie mensual apilada por categoría para UNA moneda (huecos en 0). */
export function pivotCapitalPorMes(filas: readonly FilaCapitalMes[], moneda: Moneda): PuntoCapitalMes[] {
  const porMes = new Map<string, PuntoCapitalMes>()
  for (const fila of filas) {
    if (fila.moneda !== moneda) continue
    const mes = claveMes(fila.mes)
    if (!mes) continue
    const punto = porMes.get(mes) ?? puntoCapitalCero(mes)
    const categoria =
      fila.categoria != null && CATEGORIAS_CONOCIDAS.has(fila.categoria)
        ? (fila.categoria as 'nuevo' | 'renovacion' | 'upgrade')
        : SIN_CATEGORIA
    punto[categoria] += fila.capital_colocado
    porMes.set(mes, punto)
  }
  return mesesContinuos([...porMes.keys()]).map((mes) => porMes.get(mes) ?? puntoCapitalCero(mes))
}

// ── (b) Pagos: pagado vs vencido por mes ───────────────────────────────────

export interface PuntoPagosMes {
  mes: string
  etiqueta: string
  /** Suma de monto_pagado de las cuotas en estado 'pagado' del mes. */
  pagado: number
  /** Suma de monto_programado de las cuotas en estado 'vencido' del mes. */
  vencido: number
}

function puntoPagosCero(mes: string): PuntoPagosMes {
  return { mes, etiqueta: etiquetaMes(mes), pagado: 0, vencido: 0 }
}

/**
 * Pivot estado→series para UNA moneda: pagado = estado pagado → monto_pagado y
 * vencido = vencido.monto_programado (lo vencido aún no se pagó — su realidad
 * es lo programado). 'pendiente'/'trasladado' no son pagos: se ignoran.
 * El RETORNO de capital tampoco entra: devolver el capital del contrato no es
 * pagos de intereses, y su monto (el capital entero) aplasta la escala 40x
 * y vuelve ilegible la tendencia mensual (hallazgo de revisión 2026-07-16).
 * Sí entran 'cuota' (interés mensual, simple) y 'devolucion' (interés al
 * vencimiento, compuesto): juntas son "los intereses del cronograma".
 */
export function pivotPagosPorMes(filas: readonly FilaPagosMes[], moneda: Moneda): PuntoPagosMes[] {
  const porMes = new Map<string, PuntoPagosMes>()
  for (const fila of filas) {
    if (fila.moneda !== moneda) continue
    if (fila.tipo === 'retorno') continue
    if (fila.estado !== 'pagado' && fila.estado !== 'vencido') continue
    const mes = claveMes(fila.mes)
    if (!mes) continue
    const punto = porMes.get(mes) ?? puntoPagosCero(mes)
    if (fila.estado === 'pagado') punto.pagado += fila.monto_pagado
    else punto.vencido += fila.monto_programado
    porMes.set(mes, punto)
  }
  return mesesContinuos([...porMes.keys()]).map((mes) => porMes.get(mes) ?? puntoPagosCero(mes))
}

// ── (c) Altas por analista (top-N del período, todos los meses sumados) ────────

export interface AltasDeAnalista {
  analista_id: string
  nombre: string
  altas: number
}

/** Ranking descendente de altas por analista (empate → alfabético estable). */
export function topAltasPorAnalista(filas: readonly FilaAltasAnalista[], topN = 8): AltasDeAnalista[] {
  const porAnalista = new Map<string, AltasDeAnalista>()
  for (const fila of filas) {
    const actual = porAnalista.get(fila.analista_id) ?? {
      analista_id: fila.analista_id,
      nombre: fila.analista_nombre,
      altas: 0,
    }
    actual.altas += fila.altas
    porAnalista.set(fila.analista_id, actual)
  }
  return [...porAnalista.values()]
    .sort((a, b) => b.altas - a.altas || a.nombre.localeCompare(b.nombre, 'es'))
    .slice(0, Math.max(0, topN))
}

// ── (d) Vencimientos próximos por mes ──────────────────────────────────────────

export interface PuntoVencimientosMes {
  mes: string
  etiqueta: string
  contratos: number
  capital: number
}

function puntoVencimientosCero(mes: string): PuntoVencimientosMes {
  return { mes, etiqueta: etiquetaMes(mes), contratos: 0, capital: 0 }
}

/** Capital y contratos por vencer por mes para UNA moneda (huecos en 0). */
export function pivotVencimientosPorMes(
  filas: readonly FilaVencimientos[],
  moneda: Moneda,
): PuntoVencimientosMes[] {
  const porMes = new Map<string, PuntoVencimientosMes>()
  for (const fila of filas) {
    if (fila.moneda !== moneda) continue
    const mes = claveMes(fila.mes)
    if (!mes) continue
    const punto = porMes.get(mes) ?? puntoVencimientosCero(mes)
    punto.contratos += fila.contratos_por_vencer
    punto.capital += fila.capital_por_vencer
    porMes.set(mes, punto)
  }
  return mesesContinuos([...porMes.keys()]).map((mes) => porMes.get(mes) ?? puntoVencimientosCero(mes))
}
