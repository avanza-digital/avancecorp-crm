// Celulares (F4-c): contrato de las cinco puertas de gerencia y las reglas de la tarjeta «Celulares».
// Fuentes: crm.celulares_salud_fn (20261001212258; su núcleo desde la undécima 20261006150254 ya no trae horas
// exactas), crm.celulares_asignaciones_fn, crm.asignar_celular, crm.rotar_credencial_celular y
// crm.cerrar_asignacion_celular (20261001160219). Aquí se valida la FORMA en la frontera y se arman los textos; quién
// puede, la etiqueta repetida y el analista de baja los decide el servidor (42501, 23505 y 22023).
import * as v from 'valibot'

/** La misma regla que el servidor (private.celular_asignar): C1 … C999. */
export const ETIQUETA_CELULAR = /^C[1-9][0-9]{0,2}$/
export const ESTADOS_LATIDO = ['al_dia', 'sin_latido', 'nunca'] as const
export type EstadoLatido = (typeof ESTADOS_LATIDO)[number]
/** La versión de la macro que une la llamada con la encuesta (decisión D5 de F4-d). Otra = «macro vieja». */
export const VERSION_MACRO_VIGENTE = 'llamadas-v3'

/** Una fila de crm.celulares_salud_fn. Estricta: si el servidor volviera a mandar la hora del latido, se nota. */
export const CelularSaludSchema = v.strictObject({
  asignacion_id: v.string(),
  etiqueta: v.string(),
  analista_id: v.string(),
  analista_nombre: v.nullable(v.string()),
  vigente_desde: v.string(),
  estado_latido: v.picklist(ESTADOS_LATIDO),
  /** Horas enteras desde el último latido; null si nunca hubo. */
  horas_sin_latido: v.nullable(v.number()),
  /** El reloj del celular y el del servidor difieren en más de 5 minutos. */
  reloj_desfasado: v.boolean(),
  version_macro: v.nullable(v.string()),
  eventos_en_cola: v.nullable(v.number()),
})
export type CelularSalud = v.InferOutput<typeof CelularSaludSchema>
export const CelularesSaludSchema = v.array(CelularSaludSchema)

/** Una fila de crm.celulares_asignaciones_fn: vigentes y cerradas, sin el hash. */
export const AsignacionCelularSchema = v.strictObject({
  asignacion_id: v.string(),
  etiqueta: v.string(),
  analista_id: v.string(),
  analista_nombre: v.nullable(v.string()),
  vigente_desde: v.string(),
  vigente_hasta: v.nullable(v.string()),
  motivo_cierre: v.nullable(v.string()),
})
export type AsignacionCelular = v.InferOutput<typeof AsignacionCelularSchema>
export const AsignacionesCelularSchema = v.array(AsignacionCelularSchema)

/** Lo que devuelven asignar y rotar. La credencial sale UNA sola vez: 32 bytes en hexadecimal. */
export const CredencialCelularSchema = v.object({
  asignacion_id: v.string(),
  etiqueta: v.string(),
  analista_id: v.string(),
  credencial: v.pipe(v.string(), v.regex(/^[0-9a-f]{64}$/)),
  /** Solo al rotar: la asignación que se cerró. */
  anterior_id: v.optional(v.string()),
})
export type CredencialCelular = v.InferOutput<typeof CredencialCelularSchema>

export const CierreCelularSchema = v.object({ asignacion_id: v.string(), repetido: v.boolean() })

/** Lista cerrada del servidor. `rotacion` la pone la rotación: la pantalla no la ofrece. */
export const MOTIVOS_CIERRE = [
  { clave: 'baja_analista', etiqueta: 'Baja del analista', detalle: 'Dejó el CRM o ya no capta llamadas con este celular.' },
  { clave: 'extravio', etiqueta: 'Extravío del celular', detalle: 'Se perdió o lo robaron. La clave muere al instante.' },
  { clave: 'reemplazo', etiqueta: 'Reemplazo por otro celular', detalle: 'Después se asigna el nuevo con la misma etiqueta.' },
  { clave: 'otro', etiqueta: 'Otro motivo', detalle: 'Queda en el historial con la etiqueta «Otro».' },
] as const
export type MotivoCierre = (typeof MOTIVOS_CIERRE)[number]['clave']
const ETIQUETA_MOTIVO: Record<string, string> = {
  rotacion: 'Rotación de clave',
  baja_analista: 'Baja del analista',
  extravio: 'Extravío',
  reemplazo: 'Reemplazo',
  otro: 'Otro',
}
export function etiquetaMotivoCierre(motivo: string | null): string {
  if (!motivo) return '—'
  return ETIQUETA_MOTIVO[motivo] ?? motivo
}

export type TonoSalud = 'bien' | 'aviso' | 'quieto' | 'mal'
export interface AvisoSalud { texto: string; tono: TonoSalud }
export interface SaludPresentada {
  /** El estado principal: uno solo por celular. */
  principal: AvisoSalud
  /** Avisos que se suman al estado (reloj, macro vieja). */
  extras: readonly AvisoSalud[]
  /** Una línea de ayuda bajo los chips, o nada. */
  pista: string | null
  macroTexto: string
  colaTexto: string
  /** Hay avisos atascados: el celular guardó llamadas que no pudo enviar. */
  colaAviso: boolean
  /** Rotar solo tiene sentido con el analista activo: el servidor lo rechaza (22023) si está de baja. */
  rotable: boolean
}

/**
 * Las reglas de la columna «Salud». `analistaActivo` sale del catálogo de usuarios; `null` = no se pudo saber, y
 * entonces se confía en el servidor (rotar sigue habilitado y, si corresponde, él lo niega con su texto).
 */
export function presentarSalud(c: CelularSalud, analistaActivo: boolean | null): SaludPresentada {
  const deBaja = analistaActivo === false
  const principal: AvisoSalud = deBaja ? { texto: 'Analista de baja', tono: 'mal' }
    : c.estado_latido === 'nunca' ? { texto: 'Nunca habló', tono: 'quieto' }
      : c.estado_latido === 'sin_latido' ? { texto: `Sin latido · ${c.horas_sin_latido ?? '?'} h`, tono: 'aviso' }
        : { texto: 'Al día', tono: 'bien' }
  const extras: AvisoSalud[] = []
  const macroVieja = c.version_macro !== null && c.version_macro !== VERSION_MACRO_VIGENTE
  if (!deBaja && c.reloj_desfasado) extras.push({ texto: 'Reloj desfasado', tono: 'aviso' })
  if (!deBaja && macroVieja) extras.push({ texto: 'Macro vieja', tono: 'aviso' })
  const pista = deBaja ? 'Sin rotación: ciérralo y asígnalo a otro analista.'
    : c.estado_latido === 'nunca' ? 'Esperando el primer latido de la macro.'
      : c.reloj_desfasado ? 'El reloj del celular difiere del servidor en más de 5 min: revisa la hora automática.'
        : macroVieja ? `Falta cambiar el texto del latido a ${VERSION_MACRO_VIGENTE}.` : null
  const cola = c.eventos_en_cola
  return {
    principal,
    extras,
    pista,
    macroTexto: c.version_macro ?? '—',
    colaTexto: cola === null ? '—' : String(cola),
    colaAviso: cola !== null && cola > 0,
    rotable: !deBaja,
  }
}

const FECHA_CORTA = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'America/Lima' })
/** «7 oct 2026», en hora de Lima. Un valor inválido se dice tal cual, nunca «Invalid Date». */
export function fechaCortaLima(iso: string): string {
  const ms = Date.parse(iso)
  return Number.isFinite(ms) ? FECHA_CORTA.format(ms) : iso
}

export function resumenVigentes(vigentes: readonly CelularSalud[], activo: (analistaId: string) => boolean | null): {
  etiqueta: string
  detalle: string
} {
  const n = vigentes.length
  if (n === 0) return { etiqueta: 'Sin celulares', detalle: 'Ningún celular asignado todavía.' }
  let sinLatido = 0
  let nunca = 0
  let baja = 0
  for (const c of vigentes) {
    if (activo(c.analista_id) === false) baja += 1
    else if (c.estado_latido === 'sin_latido') sinLatido += 1
    else if (c.estado_latido === 'nunca') nunca += 1
  }
  const partes: string[] = []
  if (sinLatido) partes.push(`${sinLatido} sin latido`)
  if (nunca) partes.push(nunca === 1 ? '1 nunca habló' : `${nunca} nunca hablaron`)
  if (baja) partes.push(`${baja} con analista de baja`)
  return { etiqueta: `${n} ${n === 1 ? 'vigente' : 'vigentes'}`, detalle: partes.length ? partes.join(' · ') : 'Todos al día.' }
}
