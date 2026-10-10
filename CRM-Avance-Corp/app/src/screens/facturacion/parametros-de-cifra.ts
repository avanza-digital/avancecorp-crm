import { SIN_ANALISTA_ID, type ListaOperacionesFacturacion, type ParametrosOperacionesFacturacion } from '@/data/crm-api'
import { SIN_SUPERVISOR_ID, TIPO_TODOS, type FilaFacturacionDia } from '@/lib/facturacion'
import { totalEnSoles } from '@/lib/capital-unificado'
import type { Moneda } from '@/lib/format'

/** El ámbito pertenece al número, no al estado posterior de los filtros. */
export interface CifraFacturacion {
  dias: readonly string[]
  diasMarcados?: readonly string[] | undefined
  analistaId?: string | undefined
  analistas?: readonly string[] | undefined
  equipoId?: string | undefined
  tipo?: string | undefined
  vista: 'TOTAL' | Moneda
}

/** Celda/día/tipo pasan sus días propios; los totales pasan además los días marcados. */
export function parametrosDeCifra(cifra: CifraFacturacion, pagina = 1, tamano: 25 | 50 | 100 = 25): ParametrosOperacionesFacturacion {
  const dias = [...new Set(cifra.diasMarcados?.length ? cifra.diasMarcados : cifra.dias)].sort()
  const desde = dias[0]
  const hasta = dias.at(-1)
  if (!desde || !hasta || !dias.every((d) => /^\d{4}-\d{2}-\d{2}$/.test(d) && Number.isFinite(Date.parse(d)) && new Date(d).toISOString().slice(0, 10) === d) ||
      (Date.parse(hasta) - Date.parse(desde)) / 86400000 > 30) throw new Error('Elige un tramo de entre 1 y 31 días.')
  const analistas = cifra.analistaId ? [cifra.analistaId] : [...(cifra.analistas ?? [])]
  if (analistas.includes(SIN_ANALISTA_ID) && analistas.length > 1) throw new Error('Abre «Sin analista» por separado.')
  const params: ParametrosOperacionesFacturacion = { p_desde: desde, p_hasta: hasta, p_pagina: pagina, p_tamano: tamano }
  if (cifra.diasMarcados?.length || dias.some((d, i) => i > 0 && Date.parse(d) - Date.parse(dias[i - 1]!) !== 86400000)) params.p_dias = dias
  if (analistas[0] === SIN_ANALISTA_ID) params.p_sin_analista = true
  else if (analistas.length) params.p_analistas = analistas
  if (cifra.equipoId === SIN_SUPERVISOR_ID) params.p_sin_equipo = true
  else if (cifra.equipoId) params.p_equipo = cifra.equipoId
  if (cifra.tipo && cifra.tipo !== TIPO_TODOS) params.p_tipos = [cifra.tipo]
  if (cifra.vista !== 'TOTAL') params.p_moneda = cifra.vista
  return params
}

export function filasDeCifra(filas: readonly FilaFacturacionDia[], p: ParametrosOperacionesFacturacion): FilaFacturacionDia[] {
  return filas.filter((f) => f.dia >= p.p_desde && f.dia <= p.p_hasta &&
    (!p.p_dias || p.p_dias.includes(f.dia)) && (!p.p_analistas || p.p_analistas.includes(f.analistaId)) &&
    (!p.p_sin_analista || f.analistaId === SIN_ANALISTA_ID) && (!p.p_equipo || f.supervisorId === p.p_equipo) &&
    (!p.p_sin_equipo || f.supervisorId === SIN_SUPERVISOR_ID) && (!p.p_tipos || p.p_tipos.includes(f.tipo)) &&
    (!p.p_moneda || f.moneda === p.p_moneda))
}

export function totalesDeCifra(filas: readonly FilaFacturacionDia[], p: ParametrosOperacionesFacturacion): ListaOperacionesFacturacion['totales'] {
  const elegidas = filasDeCifra(filas, p)
  return (['PEN', 'USD'] as const).flatMap((moneda) => {
    const propias = elegidas.filter((f) => f.moneda === moneda)
    const operaciones = propias.reduce((n, f) => n + f.operaciones, 0)
    return operaciones ? [{ moneda, operaciones, monto: propias.reduce((n, f) => n + f.capital, 0) }] : []
  })
}

export function mismosTotales(a: ListaOperacionesFacturacion['totales'], b: ListaOperacionesFacturacion['totales']): boolean {
  return (['PEN', 'USD'] as const).every((moneda) => {
    const x = a.find((t) => t.moneda === moneda)
    const y = b.find((t) => t.moneda === moneda)
    return (x?.operaciones ?? 0) === (y?.operaciones ?? 0) && Math.round((x?.monto ?? 0) * 100) === Math.round((y?.monto ?? 0) * 100)
  })
}

export function valorDeTotales(totales: ListaOperacionesFacturacion['totales'], vista: CifraFacturacion['vista'], metrica: 'capital' | 'contratos', tasa?: number): number {
  if (metrica === 'contratos') return totales.reduce((n, t) => n + t.operaciones, 0)
  const monto = (moneda: Moneda) => totales.find((t) => t.moneda === moneda)?.monto ?? 0
  return vista === 'TOTAL' ? totalEnSoles(monto('PEN'), monto('USD'), tasa).total ?? 0 : monto(vista)
}

export interface NumeroAbierto {
  titulo: string
  cifra: CifraFacturacion
  totales: ListaOperacionesFacturacion['totales']
  valor: number
  metrica: 'capital' | 'contratos'
  tasa?: number | undefined
  cuenta?: { modo: 'promedio'; divisor: number } | { modo: 'porcentaje'; actual: number; cifraActual: CifraFacturacion } | undefined
}

/** Contrasta tanto la composición por moneda como el número pulsado (incluida su fórmula). */
export function listaCuadraConNumero(abierto: NumeroAbierto, lista: ListaOperacionesFacturacion): boolean {
  if (!mismosTotales(abierto.totales, lista.totales)) return false
  const base = valorDeTotales(lista.totales, abierto.cifra.vista, abierto.metrica, abierto.tasa)
  let calculado = base
  if (abierto.cuenta?.modo === 'promedio') {
    calculado = base / abierto.cuenta.divisor
    if (abierto.metrica === 'capital') calculado = Math.round(calculado)
  } else if (abierto.cuenta?.modo === 'porcentaje') {
    if (base === 0) return Number.isNaN(abierto.valor)
    calculado = (abierto.cuenta.actual - base) / base * 100
  }
  if (abierto.cuenta?.modo === 'porcentaje') return Math.abs(calculado - abierto.valor) < 0.000001
  return abierto.metrica === 'contratos' ? calculado === abierto.valor : Math.abs(calculado - abierto.valor) < 0.005
}
