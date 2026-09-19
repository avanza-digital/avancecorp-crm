// lib/historial-lead.ts — el historial de UN lead: señales «alguna vez»,
// orden estable y fusión de las filas optimistas con las páginas servidas.
//
// Funciones PURAS (sin React ni red). Las usa el hook `useActividadesDeLead`
// (ficha, descarte, cierre de tarea) y el gate del store que las respalda.
//
// POR QUÉ EXISTE: hasta la Fase 1 del plan «sin topes» (19/09/2026) el
// historial de un lead se filtraba en el navegador de la lista GLOBAL del
// ámbito, que PostgREST recorta a 1 000 filas: un supervisor veía ~4 días de
// gestiones de su equipo y gerencia ~2. Ahora `crm.actividades_de_lead_fn`
// sirve el historial POR LEAD, paginado por cursor y sin ventana de fecha.
import { TIPOS_CONTACTO_K, TIPOS_CONVERSACION_K, type Actividad } from './tipos'

/** Lo que el pipeline pregunta sobre TODO el historial, no sobre una página. */
export interface SenalesLead {
  /** ¿Hubo alguna `reunion_realizada`, alguna vez? Bloquea el retroceso de etapa. */
  tieneReunionRealizada: boolean
  /** ¿Hubo algún contacto real (TIPOS_CONTACTO), alguna vez? Decide a qué etapa se baja. */
  tieneContacto: boolean
  /** ISO de la última CONVERSACIÓN (el cliente respondió), o null si nunca. */
  ultimaConversacionEn: string | null
}

export const SENALES_VACIAS: SenalesLead = {
  tieneReunionRealizada: false,
  tieneContacto: false,
  ultimaConversacionEn: null,
}

/** Épocas comparables de un ISO; una fecha corrupta NO cuenta (fail-closed). */
function epoca(iso: string): number | null {
  const t = Date.parse(iso)
  return Number.isFinite(t) ? t : null
}

/**
 * Señales derivadas de un conjunto de filas. En demo es la ÚNICA fuente; en
 * sesión real complementa a las servidas con las filas locales aún sin
 * confirmar (ver `combinarSenales`).
 */
export function senalesDesdeActividades(
  acts: readonly Pick<Actividad, 'tipo' | 'creado_en'>[],
): SenalesLead {
  let tieneReunionRealizada = false
  let tieneContacto = false
  let ultimaConversacionEn: string | null = null
  let ultimaEpoca = Number.NEGATIVE_INFINITY
  for (const a of acts) {
    if (a.tipo === 'reunion_realizada') tieneReunionRealizada = true
    if (TIPOS_CONTACTO_K.has(a.tipo)) tieneContacto = true
    if (!TIPOS_CONVERSACION_K.has(a.tipo)) continue
    const t = epoca(a.creado_en)
    if (t != null && t > ultimaEpoca) {
      ultimaEpoca = t
      ultimaConversacionEn = a.creado_en
    }
  }
  return { tieneReunionRealizada, tieneContacto, ultimaConversacionEn }
}

/** Una señal solo puede ENCENDERSE al unir dos fuentes; la conversación más reciente gana. */
export function combinarSenales(a: SenalesLead, b: SenalesLead): SenalesLead {
  const ea = a.ultimaConversacionEn ? epoca(a.ultimaConversacionEn) : null
  const eb = b.ultimaConversacionEn ? epoca(b.ultimaConversacionEn) : null
  const ultimaConversacionEn =
    ea == null ? b.ultimaConversacionEn
    : eb == null ? a.ultimaConversacionEn
    : eb > ea ? b.ultimaConversacionEn : a.ultimaConversacionEn
  return {
    tieneReunionRealizada: a.tieneReunionRealizada || b.tieneReunionRealizada,
    tieneContacto: a.tieneContacto || b.tieneContacto,
    ultimaConversacionEn,
  }
}

// A igual `creado_en`, lo que escribe el SISTEMA (cambio de etapa, conversión)
// va DELANTE de la gestión que lo provocó: ocurrió después, dentro de la misma
// transacción (`now()` es el de la transacción, así que empatan). Con páginas
// servidas el desempate por `id` es un uuid aleatorio; sin esta regla la
// pareja «llamada → Contactado» se pintaría al revés la mitad de las veces.
const PRIMERO_EN_EMPATE: ReadonlySet<Actividad['tipo']> = new Set(['cambio_etapa', 'conversion'])

/** Más reciente primero; empates deterministas (ver arriba); nunca muta la entrada. */
export function ordenarHistorial(acts: readonly Actividad[]): Actividad[] {
  return [...acts].sort((a, b) => {
    const ta = epoca(a.creado_en)
    const tb = epoca(b.creado_en)
    if (ta != null && tb != null && ta !== tb) return tb - ta
    if (ta == null && tb != null) return 1
    if (ta != null && tb == null) return -1
    if (ta == null && tb == null && a.creado_en !== b.creado_en) return a.creado_en < b.creado_en ? 1 : -1
    const pa = PRIMERO_EN_EMPATE.has(a.tipo) ? 0 : 1
    const pb = PRIMERO_EN_EMPATE.has(b.tipo) ? 0 : 1
    if (pa !== pb) return pa - pb
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
  })
}

/**
 * Filas optimistas que TODAVÍA merecen pintarse junto a lo servido.
 *
 * Una fila local nace con un id inventado (`uid()`), así que no puede
 * deduplicarse por id contra la fila real. La regla es temporal: una fila
 * local vive mientras NO exista una página del servidor leída DESPUÉS de su
 * creación (`leidoEn` = `dataUpdatedAt` de la consulta; 0 = nunca leída). En
 * cuanto llega una lectura posterior, la verdad del servidor la sustituye —
 * incluida la pareja `cambio_etapa` que el trigger escribe en la misma
 * transacción, que la lectura posterior también trae.
 */
export function localesVivas(locales: readonly Actividad[], leidoEn: number): Actividad[] {
  return locales.filter((a) => a.local === true && (leidoEn === 0 || (a.local_ts ?? 0) > leidoEn))
}

/** Historial fusionado: locales vivas + páginas servidas, sin ids repetidos, más reciente primero. */
export function fusionarHistorial(
  locales: readonly Actividad[],
  servidor: readonly Actividad[],
  leidoEn: number,
): Actividad[] {
  const vistos = new Set<string>()
  const filas: Actividad[] = []
  for (const a of [...localesVivas(locales, leidoEn), ...servidor]) {
    if (vistos.has(a.id)) continue
    vistos.add(a.id)
    filas.push(a)
  }
  return ordenarHistorial(filas)
}
