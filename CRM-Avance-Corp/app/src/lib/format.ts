// Helpers de formato (multimoneda desde el día 1 — lección de VITANOVA).
export type Moneda = 'PEN' | 'USD'

const SIMBOLO: Record<Moneda, string> = { PEN: 'S/', USD: 'US$' }

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
  const pila = limpio.split(/\s+/)[0]
  return pila.charAt(0) + pila.slice(1).toLowerCase()
}

export function fmtFecha(iso: string | null | undefined): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' })
}
