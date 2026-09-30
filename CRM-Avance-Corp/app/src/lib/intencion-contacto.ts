// lib/intencion-contacto.ts — el coordinador de la INTENCIÓN de contacto
// (F1.1.1 del plan «Llamadas desde el celular al CRM», 30/09/2026).
//
// Hasta hoy, «me fui a llamar y volví» vivía en un ref de CADA AccionesContacto:
// si esa instancia se desmontaba (la cola se repintó, la PWA se recargó al
// volver del marcador) la pregunta del resultado se perdía, y nadie de fuera
// —el enlace que arma el celular al colgar— podía pedirla. Aquí vive una sola
// cola de intenciones por pestaña: quién la armó (actor), a quién llamó (lead),
// por dónde (canal), con qué número, cuándo, hasta cuándo vale y si alguien ya
// tiene abierto su formulario. AccionesContacto y el receptor del enlace hablan
// con esto, no entre sí.
//
// Reglas:
//  · UNA cabeza a la vez. Mientras la cabeza está `abierta` (alguien registra),
//    las demás esperan: una segunda llamada no interrumpe el registro de la
//    primera. Al cerrarla, la siguiente pasa a cabeza y se ofrece.
//  · Se persiste en sessionStorage (misma pestaña): una recarga —Android
//    descarta la PWA mientras se está en el marcador— no pierde la pregunta.
//    Otra pestaña no la ve: cada una tiene su propia cola.
//  · «Abierta» solo vale para la PÁGINA que la abrió: tras recargar, un
//    formulario que quedó abierto ya no existe, así que se vuelve a ofrecer.
//  · Caduca: nadie pregunta por una llamada de hace horas.
//  · La cola es del actor: al salir de la cuenta se vacía (auth.tsx).
import { useSyncExternalStore } from 'react'
import type { Canal } from './contacto-tarea'

/** De dónde nació: un tap en «Llamar» o el enlace que arma el celular al colgar. */
export type OrigenIntencion = 'pantalla' | 'enlace'

export interface IntencionContacto {
  id: string
  actor: string
  leadId: string
  canal: Canal
  /** El número que trajo el enlace, ya canonizado por el receptor; `null` si nació de un tap. */
  numero: string | null
  origen: OrigenIntencion
  /** Cuándo se armó (ms). Con `origen: 'pantalla'` es el momento del tap en «Llamar». */
  ts: number
  /** Pasado este momento (ms) ya no se ofrece. */
  caduca: number
  /** Alguien tiene abierto su formulario (ver `abiertaEn`). */
  abierta: boolean
  /** Página que la abrió: si no es la actual, esa apertura murió con su página. */
  abiertaEn?: string | undefined
  /** Instancia de AccionesContacto que la armó: al volver, ella responde primero. */
  instancia?: string | undefined
}

/** Tiempo mínimo fuera de la pestaña para considerar que hubo un intento real. */
export const ESPERA_MS = 4_000
/** Una llamada no dura más que esto; pasado, no se pregunta por ella. */
export const CADUCIDAD_MS = 2 * 60 * 60_000

const LLAVE = 'crm.intencion-contacto.v1'
const EVENTO = 'crm:intencion-contacto'
/** Identidad de ESTA carga de la página; no sobrevive a la recarga, a propósito. */
const PAGINA = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`

let cola: IntencionContacto[] | null = null
let secuencia = 0

function esCanal(v: unknown): v is Canal {
  return v === 'tel' || v === 'wa'
}
function esOrigen(v: unknown): v is OrigenIntencion {
  return v === 'pantalla' || v === 'enlace'
}
function esTextoOpcional(v: unknown): v is string | undefined {
  return v === undefined || typeof v === 'string'
}

function valida(v: unknown): v is IntencionContacto {
  if (!v || typeof v !== 'object') return false
  const i = v as Record<string, unknown>
  return typeof i.id === 'string' && typeof i.actor === 'string' && typeof i.leadId === 'string'
    && esCanal(i.canal) && (i.numero === null || typeof i.numero === 'string') && esOrigen(i.origen)
    && typeof i.ts === 'number' && typeof i.caduca === 'number' && typeof i.abierta === 'boolean'
    && esTextoOpcional(i.abiertaEn) && esTextoOpcional(i.instancia)
}

function cargar(): IntencionContacto[] {
  try {
    const crudo = sessionStorage.getItem(LLAVE)
    if (!crudo) return []
    const dato: unknown = JSON.parse(crudo)
    if (!Array.isArray(dato)) return []
    return dato.filter(valida).map((i) =>
      // La página que la abrió ya no existe: se vuelve a ofrecer.
      i.abierta && i.abiertaEn !== PAGINA ? { ...i, abierta: false, abiertaEn: undefined } : i)
  } catch {
    return [] // Almacenamiento deshabilitado o dato corrupto: se empieza limpio.
  }
}

function guardar(): void {
  try {
    if (cola && cola.length > 0) sessionStorage.setItem(LLAVE, JSON.stringify(cola))
    else sessionStorage.removeItem(LLAVE)
  } catch { /* Sin almacenamiento la cola vive solo en memoria. */ }
}

function notificar(): void {
  if (typeof window !== 'undefined') window.dispatchEvent(new Event(EVENTO))
}

/** La cola vigente (sin caducadas). Escribe solo si algo caducó. */
function vigentes(ahora: number): IntencionContacto[] {
  cola ??= cargar()
  const vivas = cola.filter((i) => i.caduca > ahora)
  if (vivas.length !== cola.length) {
    cola = vivas
    guardar()
  }
  return cola
}

function escribir(nueva: IntencionContacto[]): void {
  cola = nueva
  guardar()
  notificar()
}

/** ¿Ya se puede ofrecer? Un enlace, siempre; un tap, solo si pasó el tiempo de un intento real. */
export function estaLista(intencion: IntencionContacto, ahora: number = Date.now()): boolean {
  return intencion.origen === 'enlace' || ahora - intencion.ts >= ESPERA_MS
}

/**
 * Arma (o renueva) la intención de contactar a un lead. Una PENDIENTE del mismo
 * actor, lead y canal se reemplaza —un segundo tap en «Llamar» es la misma
 * llamada, no dos—; una abierta se respeta y la nueva espera detrás.
 */
export function armarIntencion(
  datos: { actor: string; leadId: string; canal: Canal; origen: OrigenIntencion; numero?: string | null; instancia?: string },
  ahora: number = Date.now(),
): IntencionContacto {
  const actual = vigentes(ahora)
  secuencia += 1
  const nueva: IntencionContacto = {
    id: `${ahora.toString(36)}-${PAGINA}-${secuencia}`,
    actor: datos.actor,
    leadId: datos.leadId,
    canal: datos.canal,
    numero: datos.numero ?? null,
    origen: datos.origen,
    ts: ahora,
    caduca: ahora + CADUCIDAD_MS,
    abierta: false,
    ...(datos.instancia ? { instancia: datos.instancia } : {}),
  }
  const indice = actual.findIndex((i) =>
    !i.abierta && i.actor === datos.actor && i.leadId === datos.leadId && i.canal === datos.canal)
  escribir(indice === -1 ? [...actual, nueva] : actual.map((i, n) => (n === indice ? nueva : i)))
  return nueva
}

/**
 * La cabeza de la cola del actor, o `null`. Con `leadId`, solo si la cabeza es
 * de ese lead: lo que espera detrás de una abierta NO se ofrece a nadie.
 */
export function intencionDe(actor: string | null | undefined, leadId?: string, ahora: number = Date.now()): IntencionContacto | null {
  if (!actor) return null
  const cabeza = vigentes(ahora)[0]
  if (!cabeza || cabeza.actor !== actor) return null
  if (leadId !== undefined && cabeza.leadId !== leadId) return null
  return cabeza
}

/** Se queda con la intención para abrir su formulario. `false` si ya no es la cabeza o alguien la tomó antes. */
export function reclamarIntencion(id: string, ahora: number = Date.now()): boolean {
  const actual = vigentes(ahora)
  const cabeza = actual[0]
  if (!cabeza || cabeza.id !== id || cabeza.abierta) return false
  escribir([{ ...cabeza, abierta: true, abiertaEn: PAGINA }, ...actual.slice(1)])
  return true
}

/** Termina con la intención (registrada, cancelada o descartada): la siguiente pasa a cabeza. */
export function cerrarIntencion(id: string): void {
  cola ??= cargar()
  if (!cola.some((i) => i.id === id)) return
  escribir(cola.filter((i) => i.id !== id))
}

/** Al salir de la cuenta: nada de la intención de una cuenta llega a la siguiente. */
export function limpiarIntencionesContacto(): void {
  cola = []
  guardar()
  notificar()
}

export function suscribirIntenciones(callback: () => void): () => void {
  window.addEventListener(EVENTO, callback)
  return () => window.removeEventListener(EVENTO, callback)
}

/** La cabeza de la cola para este actor y lead, reactiva. */
export function useIntencionContacto(actor: string | null | undefined, leadId: string): IntencionContacto | null {
  return useSyncExternalStore(suscribirIntenciones, () => intencionDe(actor, leadId), () => null)
}

/** La cola entera del actor (depuración y pruebas). */
export function listarIntenciones(actor: string | null | undefined, ahora: number = Date.now()): IntencionContacto[] {
  if (!actor) return []
  return vigentes(ahora).filter((i) => i.actor === actor)
}
