// Potencial del lead: lo que una fila o una tarjeta necesita para pintarlo.
//
// Cada vista esparce UN objeto en su elemento (`{...potencialFila(marca)}`):
// el atributo `data-potencial` que enciende la franja y el dorado en
// `potencial.css`, y —solo en Estrella— los eventos de puntero.
//
// El movimiento NO pasa por React: los eventos escriben variables CSS en el
// propio elemento, así mover el mouse sobre una lista no re-renderiza nada.
import type { PointerEvent } from 'react'
import type { NivelPotencial, PotencialLead } from '@/lib/potencial'

type AlPuntero = (e: PointerEvent<HTMLElement>) => void

export interface AtributosFilaPotencial {
  'data-potencial'?: NivelPotencial
  onPointerMove?: AlPuntero
}

export interface AtributosCartaPotencial extends AtributosFilaPotencial {
  'data-pot-quieta'?: ''
  onPointerDown?: AlPuntero
  onPointerUp?: AlPuntero
  onPointerCancel?: AlPuntero
  onPointerLeave?: AlPuntero
}

/**
 * Ids para un `aria-describedby`, saltando los que no aplican (undefined si no
 * queda ninguno: el atributo no se pinta vacío).
 */
export function idsDescripcion(...ids: ReadonlyArray<string | false | null | undefined>): string | undefined {
  return ids.filter(Boolean).join(' ') || undefined
}

/** ¿La persona pidió menos movimiento? (también es el mundo de las pruebas). */
export function sinMovimiento(): boolean {
  return typeof window !== 'undefined'
    && typeof window.matchMedia === 'function'
    && window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/** Foco de luz que sigue al cursor: su posición dentro del elemento, en px. */
export function seguirCursorPotencial(e: PointerEvent<HTMLElement>): void {
  const el = e.currentTarget
  const caja = el.getBoundingClientRect()
  el.style.setProperty('--pot-mx', `${Math.round(e.clientX - caja.left)}px`)
  el.style.setProperty('--pot-my', `${Math.round(e.clientY - caja.top)}px`)
}

/**
 * Fila con marca (tabla de Leads, cola de hoy): la franja del color del nivel
 * y, en Estrella, el foco que sigue al cursor. Sin marca no añade nada.
 */
export function potencialFila(marca: PotencialLead | undefined): AtributosFilaPotencial {
  const nivel = marca?.nivel
  if (!nivel) return {}
  return nivel === 'estrella'
    ? { 'data-potencial': nivel, onPointerMove: seguirCursorPotencial }
    : { 'data-potencial': nivel }
}

const VARIABLES_INCLINACION = ['--pot-rx', '--pot-ry', '--pot-alza', '--pot-luz'] as const

function enderezar(el: HTMLElement): void {
  for (const variable of VARIABLES_INCLINACION) el.style.removeProperty(variable)
}

/** La tarjeta se inclina hacia el cursor (±6° / ±7°), sube 3 px y enciende el reflejo. */
function inclinar(e: PointerEvent<HTMLElement>): void {
  const el = e.currentTarget
  // Con el botón pulsado puede empezar un arrastre: la tarjeta espera derecha.
  if (el.dataset.potPulsada != null || sinMovimiento()) return
  const caja = el.getBoundingClientRect()
  if (caja.width === 0 || caja.height === 0) return
  const x = Math.min(Math.max((e.clientX - caja.left) / caja.width, 0), 1)
  const y = Math.min(Math.max((e.clientY - caja.top) / caja.height, 0), 1)
  el.style.setProperty('--pot-rx', `${((0.5 - y) * 12).toFixed(2)}deg`)
  el.style.setProperty('--pot-ry', `${((x - 0.5) * 14).toFixed(2)}deg`)
  el.style.setProperty('--pot-alza', '-3px')
  el.style.setProperty('--pot-mx', `${(x * 100).toFixed(1)}%`)
  el.style.setProperty('--pot-my', `${(y * 100).toFixed(1)}%`)
  el.style.setProperty('--pot-luz', '1')
}

/** Al pulsar se endereza: si de ahí nace un arrastre, la imagen que viaja sale derecha. */
function pulsar(e: PointerEvent<HTMLElement>): void {
  e.currentTarget.dataset.potPulsada = ''
  enderezar(e.currentTarget)
}

function liberar(e: PointerEvent<HTMLElement>): void {
  delete e.currentTarget.dataset.potPulsada
}

function salir(e: PointerEvent<HTMLElement>): void {
  liberar(e)
  enderezar(e.currentTarget)
}

/**
 * Tarjeta del Pipeline con marca: la franja y, en Estrella, la inclinación
 * hacia el cursor con su reflejo. `quieta` la apaga mientras se arrastra o
 * tiene su menú abierto (inclinarla movería lo que la persona está usando).
 */
export function potencialCarta(marca: PotencialLead | undefined, quieta: boolean): AtributosCartaPotencial {
  const nivel = marca?.nivel
  if (!nivel) return {}
  if (nivel !== 'estrella') return { 'data-potencial': nivel }
  if (quieta) return { 'data-potencial': nivel, 'data-pot-quieta': '' }
  return {
    'data-potencial': nivel,
    onPointerMove: inclinar,
    onPointerDown: pulsar,
    onPointerUp: liberar,
    onPointerCancel: liberar,
    onPointerLeave: salir,
  }
}
