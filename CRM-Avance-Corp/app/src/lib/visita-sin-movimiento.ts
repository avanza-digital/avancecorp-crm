// F4.3 «Hoy del supervisor, sin ruido»: qué EMPEORÓ en «Sin movimiento» desde
// la última visita del supervisor. La pestaña lista hasta 50 estancados y el
// ojo humano no recuerda cuáles ya revisó — el sistema absorbe esa memoria
// (Tesler) con una FOTO local por supervisor en localStorage.
//
// Reglas de la casa que este módulo custodia:
// · «Empeoró» son DOS cosas y solo dos: un lead que ENTRÓ a la lista desde la
//   visita anterior, o uno que CRUZÓ a crítico (≥7 días) habiéndose visto en
//   ámbar. Que un estancado acumule un día más no es novedad: es el paso del
//   tiempo, y marcarlo sería ruido.
// · localStorage es una COMODIDAD por dispositivo, no un dato: puede faltar,
//   estar corrupto o lanzar (Safari privado) — en todos esos casos la pestaña
//   se pinta completa y SIN marcas, jamás rota ni con marcas inventadas.
// · La primera visita no marca nada: sin foto anterior no hay «desde cuándo».
// · El fallo va en la dirección segura: una foto perdida marca DE MÁS en la
//   siguiente visita (cosas ya vistas como nuevas), nunca calla una novedad.
// · La lista puede llegar RECORTADA al tope del RPC (los N más antiguos):
//   fuera de lo visible puede empeorar algo sin que aquí se marque, así que
//   el resumen confiesa su alcance cuando habla sobre una lista recortada.
import * as v from 'valibot'
import type { EstancadoCola } from './cola-accion'

/** Desde cuántos días un estancado es CRÍTICO (la tira roja de la pestaña). */
export const UMBRAL_CRITICO_ESTANCADO_DIAS = 7

/** La foto que se guarda al abrir la pestaña: ids → días vistos. Sin nombres
 *  (sin PII en el storage del navegador) y con la fecha de la visita. */
export const FotoVisitaSchema = v.strictObject({
  vistoEn: v.pipe(v.string(), v.isoTimestamp()),
  dias: v.record(v.string(), v.number()),
})

export type FotoVisita = v.InferOutput<typeof FotoVisitaSchema>

export interface NovedadesVisita {
  /** Leads que NO estaban en la foto: entraron desde la última visita. */
  nuevos: ReadonlySet<string>
  /** Vistos en ámbar (<7 días) que ahora son críticos (≥7): cruzaron. */
  agravados: ReadonlySet<string>
  vistoEn: string
}

function claveVisita(supervisorId: string): string {
  return `crm:sin-movimiento:visita:${supervisorId}`
}

/** Lo mínimo que este módulo usa de Storage — inyectable en pruebas. El
 *  default es el localStorage GLOBAL (patrón del sidebar): hasta el ACCESO
 *  puede lanzar en navegadores que bloquean datos de sitio, por eso todo va
 *  dentro del try. */
type AlmacenVisita = Pick<Storage, 'getItem' | 'setItem'>

function almacenPorDefecto(): AlmacenVisita {
  return localStorage
}

/** null = sin foto utilizable (no existe, corrupta o storage inaccesible). */
export function leerFotoVisita(
  supervisorId: string,
  almacen?: AlmacenVisita,
): FotoVisita | null {
  try {
    const crudo = (almacen ?? almacenPorDefecto()).getItem(claveVisita(supervisorId))
    if (crudo == null) return null
    const resultado = v.safeParse(FotoVisitaSchema, JSON.parse(crudo))
    return resultado.success ? resultado.output : null
  } catch {
    return null
  }
}

/** Best-effort: si el storage lanza, la visita simplemente no queda anotada
 *  (la próxima marcará de más — la dirección segura). */
export function guardarFotoVisita(
  supervisorId: string,
  foto: FotoVisita,
  almacen?: AlmacenVisita,
): void {
  try {
    ;(almacen ?? almacenPorDefecto()).setItem(claveVisita(supervisorId), JSON.stringify(foto))
  } catch {
    // sin storage no hay memoria de visita — y no pasa nada más.
  }
}

export function fotoDeVisita(
  estancados: readonly EstancadoCola[],
  ahora: number,
): FotoVisita {
  const dias: Record<string, number> = {}
  for (const e of estancados) dias[e.leadId] = e.dias
  return { vistoEn: new Date(ahora).toISOString(), dias }
}

/**
 * Compara los estancados ACTUALES contra la foto de la visita anterior.
 * Con foto null devuelve null: sin «desde cuándo» no se marca nada.
 */
export function derivarNovedades(
  estancados: readonly EstancadoCola[],
  foto: FotoVisita | null,
): NovedadesVisita | null {
  if (foto == null) return null
  const nuevos = new Set<string>()
  const agravados = new Set<string>()
  for (const e of estancados) {
    const visto = foto.dias[e.leadId]
    if (visto == null) {
      nuevos.add(e.leadId)
      continue
    }
    if (visto < UMBRAL_CRITICO_ESTANCADO_DIAS && e.dias >= UMBRAL_CRITICO_ESTANCADO_DIAS) {
      agravados.add(e.leadId)
    }
  }
  return { nuevos, agravados, vistoEn: foto.vistoEn }
}

/** «Desde tu última visita: 2 nuevos · 1 cruzó a crítico» — o null si no hay
 *  nada que decir (el silencio también es información). Con la lista recortada
 *  al tope del RPC, `recortadaAl` hace que la frase confiese su alcance:
 *  fuera de los N más antiguos pudo empeorar algo que aquí no se ve. */
export function resumenNovedades(
  novedades: NovedadesVisita | null,
  recortadaAl?: number,
): string | null {
  if (novedades == null) return null
  const partes: string[] = []
  if (novedades.nuevos.size > 0) {
    partes.push(`${novedades.nuevos.size} ${novedades.nuevos.size === 1 ? 'nuevo' : 'nuevos'}`)
  }
  if (novedades.agravados.size > 0) {
    partes.push(`${novedades.agravados.size} ${novedades.agravados.size === 1 ? 'cruzó' : 'cruzaron'} a crítico`)
  }
  if (partes.length === 0) return null
  const alcance = recortadaAl == null ? '' : ` · entre los ${recortadaAl} más antiguos`
  return `Desde tu última visita: ${partes.join(' · ')}${alcance}`
}
