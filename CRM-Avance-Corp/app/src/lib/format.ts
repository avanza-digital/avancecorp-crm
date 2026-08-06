// Helpers de formato (multimoneda desde el día 1 — lección de VITANOVA).
import { formatDateLocal, parseDateLocal } from './cronograma'

export type Moneda = 'PEN' | 'USD'

export function esMoneda(valor: string): valor is Moneda {
  return valor === 'PEN' || valor === 'USD'
}

/** Símbolo por moneda — fuente única (no re-derivar `moneda === 'USD' ? … : …` en pantallas). */
export const SIMBOLO: Record<Moneda, string> = { PEN: 'S/', USD: 'US$' }

/** Cantidades legibles en todo el CRM: 1500000 -> 1,500,000 en es-PE. */
export function numero(
  n: number | null | undefined,
  maximosDecimales = 0,
): string {
  if (n == null || !Number.isFinite(n)) return '—'
  return n.toLocaleString('es-PE', {
    minimumFractionDigits: 0,
    maximumFractionDigits: maximosDecimales,
  })
}

export function money(n: number | null | undefined, moneda: Moneda = 'PEN'): string {
  if (n == null || !Number.isFinite(n)) return `${SIMBOLO[moneda]} 0`
  return `${SIMBOLO[moneda]} ${n.toLocaleString('es-PE', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`
}

export function moneyK(n: number | null | undefined, moneda: Moneda = 'PEN'): string {
  if (n == null || !Number.isFinite(n)) return `${SIMBOLO[moneda]} 0`
  if (Math.abs(n) >= 1000) return `${SIMBOLO[moneda]} ${(n / 1000).toFixed(n % 1000 === 0 ? 0 : 1)}k`
  return money(n, moneda)
}

/** Iniciales para avatar — nunca vacía. */
export function iniciales(nombre: string | null | undefined): string {
  const limpio = (nombre ?? '').trim()
  if (!limpio) return '·'
  const partes = limpio.split(/\s+/)
  return ((partes[0]?.[0] ?? '') + (partes[1]?.[0] ?? '')).toUpperCase() || '·'
}

/** Primer nombre de pila (saludos, convención del portal). */
export function primerNombre(nombre: string | null | undefined): string {
  const limpio = (nombre ?? '').trim()
  if (!limpio) return ''
  const pila = limpio.split(/\s+/)[0] ?? ''
  return pila.charAt(0).toUpperCase() + pila.slice(1).toLowerCase()
}

/** Fecha date-only (sin hora): 'YYYY-MM-DD'. `new Date()` la leería como UTC. */
const SOLO_FECHA = /^\d{4}-\d{2}-\d{2}$/

/** Lee 'YYYY-MM-DD' en zona local; null si desborda (mes 13 → enero del año que viene). */
function fechaLocalValida(s: string): Date | null {
  const d = parseDateLocal(s)
  if (Number.isNaN(d.getTime()) || formatDateLocal(d) !== s) return null
  return d
}

export function fmtFecha(iso: string | null | undefined): string {
  if (!iso) return '—'
  const d = SOLO_FECHA.test(iso) ? fechaLocalValida(iso) : new Date(iso)
  if (d == null || Number.isNaN(d.getTime())) return '—'
  return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' })
}

/**
 * Fecha + hora local de un registro (espejo de fechaHora de analista.js): para
 * un timestamp completo toLocaleString SÍ respeta hora/minuto en todos los
 * motores (toLocaleDateString las ignora en iOS/WebKit). Aquí `new Date(ts)` es
 * correcto porque creado_en es un timestamp ISO completo, no un 'YYYY-MM-DD'
 * (esos van por fmtFecha, que parsea en local para evitar el bug UTC).
 */
export function fechaHora(ts: string | null | undefined): string {
  if (!ts) return '—'
  const d = new Date(ts)
  if (Number.isNaN(d.getTime())) return '—'
  // Con la cartera completa de la empresa, el AÑO es obligatorio (la historia
  // supera los 12 meses; el formato sin año venía del portal, otra escala).
  return d.toLocaleString('es-PE', { day: '2-digit', month: 'short', year: '2-digit', hour: '2-digit', minute: '2-digit' })
}
