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

/**
 * Presentación única de la conversión canónica (`numeric`, redondeada por el
 * núcleo a dos decimales). Mantiene ambos decimales en todas las superficies:
 * 137.63 nunca vuelve a 137.6 y 9.3 se reconoce como la misma cifra 9.30.
 * NULL/no finito conserva indisponibilidad; no se convierte en 0 %.
 */
export function porcentajeConversionCanonica(
  valor: number | null | undefined,
): string {
  if (valor == null || !Number.isFinite(valor)) return '—'
  return `${valor.toLocaleString('es-PE', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}%`
}

/**
 * Dígitos de lo que hay tecleado en un campo de importe. Tolera separadores,
 * espacios, símbolo de moneda y texto pegado desde una hoja de cálculo.
 */
export function digitosDeMonto(texto: string): string {
  return texto.replace(/\D/g, '')
}

/**
 * Importe tal y como debe verse MIENTRAS se escribe: `500000` → `500,000`.
 *
 * Un campo vacío se queda vacío — es la diferencia entre «todavía no puse
 * meta» y «la meta es cero», y `type="number"` no sabe distinguirlas: al
 * borrar el contenido devuelve `''`, que convertido a número es 0 y se repinta
 * como un `0` imborrable.
 *
 * Sin decimales a propósito: las metas del mes son cifras redondas de seis o
 * siete dígitos, y ahí lo que se confunde es 50 000 con 500 000, no los
 * céntimos.
 */
export function montoEditable(texto: string): string {
  const digitos = digitosDeMonto(texto).replace(/^0+(?=\d)/, '')
  if (digitos === '') return ''
  return Number(digitos).toLocaleString('es-PE', { maximumFractionDigits: 0 })
}

/** Número que representa un importe tecleado; vacío es 0. */
export function montoDesdeTexto(texto: string): number {
  const digitos = digitosDeMonto(texto)
  return digitos === '' ? 0 : Number(digitos)
}

/**
 * Porcentaje tal y como se teclea: admite UN separador decimal y hasta dos
 * decimales, que es lo que la base guarda (`numeric(5,2)`).
 *
 * Deliberadamente NO recorta el valor. Un `Math.min(100, …)` convierte «305»
 * en «100» sin decir nada y deja muerta la validación que debía avisar; peor
 * aún, tirar el punto decimal convierte «1.5» en «15» — un error de un orden de
 * magnitud, plausible y silencioso. Aquí se conserva lo tecleado y quien avisa
 * es la validación al publicar.
 */
export function porcentajeEditable(texto: string): string {
  const normalizado = texto.replace(',', '.').replace(/[^\d.]/g, '')
  if (normalizado === '') return ''
  const [enteros = '', ...resto] = normalizado.split('.')
  const limpio = enteros.replace(/^0+(?=\d)/, '')
  if (!normalizado.includes('.')) return limpio
  return `${limpio === '' ? '0' : limpio}.${resto.join('').slice(0, 2)}`
}

/** Número que representa un porcentaje tecleado; vacío o incompleto es 0. */
export function porcentajeDesdeTexto(texto: string): number {
  const limpio = porcentajeEditable(texto)
  if (limpio === '' || limpio.endsWith('.')) return Number(limpio.slice(0, -1)) || 0
  return Number(limpio) || 0
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
