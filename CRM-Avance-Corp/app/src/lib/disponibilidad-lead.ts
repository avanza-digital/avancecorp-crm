import * as v from 'valibot'
import type { Database } from './database.types'
import { MOTIVOS_DESCARTE, type MotivoDescarte } from './tipos'

const MOTIVOS_DISPONIBILIDAD = MOTIVOS_DESCARTE.map((motivo) => motivo.k)

/** Contrato estricto de P-047. Vive junto a su presentación para que consulta
 * y creación atómica compartan una sola frontera runtime, sin ciclos con API. */
export const DisponibilidadLeadSchema = v.variant('estado', [
  v.strictObject({ estado: v.literal('libre') }),
  v.strictObject({ estado: v.literal('en_bolsa') }),
  v.strictObject({
    estado: v.literal('tomado'),
    vendedor: v.nullable(v.string()),
    tenencia_desde: v.nullable(v.pipe(v.string(), v.isoTimestamp())),
  }),
  v.strictObject({
    estado: v.literal('enfriamiento'),
    motivo_descarte: v.picklist(MOTIVOS_DISPONIBILIDAD),
    disponible_desde: v.pipe(v.string(), v.isoTimestamp()),
    descartado_por: v.nullable(v.string()),
  }),
  v.strictObject({ estado: v.literal('ya_es_cliente'), asesor: v.string() }),
  v.strictObject({ estado: v.literal('no_contactar') }),
  v.strictObject({ estado: v.literal('error'), detalle: v.literal('telefono_invalido') }),
])

export type DisponibilidadLead =
  Database['crm']['Functions']['verificar_disponibilidad_lead']['Returns']

/** Respuesta de la mutación: o confirma la identidad creada, o devuelve el
 * mismo veredicto bloqueante de P-047. Nunca existe «libre sin insertar». */
export const ResultadoCreacionLeadAtomicaSchema = v.union([
  v.strictObject({
    estado: v.literal('creado'),
    lead_id: v.pipe(v.string(), v.uuid()),
  }),
  DisponibilidadLeadSchema,
])

export type ResultadoCreacionLeadAtomica =
  Database['crm']['Functions']['crear_lead_si_disponible']['Returns']

/**
 * Único estado que la UI necesita conservar después del precheck P-047.
 *
 * No incluye el veredicto ni los demás campos del JSON: nombres, fechas y
 * motivos se consumen una vez para redactar el mensaje y luego se descartan.
 */
export type PresentacionDisponibilidadLead = Readonly<{
  mensaje: string | null
  bloquea: boolean
}>

const PRESENTACION_LIBRE: PresentacionDisponibilidadLead = Object.freeze({
  mensaje: null,
  bloquea: false,
})

const ETIQUETA_MOTIVO = Object.fromEntries(
  MOTIVOS_DESCARTE.map(({ k, label }) => [k, label]),
) as Readonly<Record<MotivoDescarte, string>>

/** Texto de BD listo para una oración: acotado y sin caracteres de control. */
function textoPresentable(valor: string | null): string | null {
  const limpio = (valor ?? '')
    .normalize('NFKC')
    .replace(/[\p{Cc}\p{Cf}]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 100)
  return limpio || null
}

/** Fecha del servidor expresada siempre en la zona de negocio, no la del equipo. */
function fechaEnLima(iso: string): string | null {
  const instante = Date.parse(iso)
  if (!Number.isFinite(instante)) return null
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(instante)
}

function bloquear(mensaje: string): PresentacionDisponibilidadLead {
  return { mensaje, bloquea: true }
}

function estadoNoSoportado(_resultado: never): never {
  // Mensaje deliberadamente estático: si el borde tipado se rompe, no volcamos
  // el JSON recibido en consola, telemetría ni una excepción mostrable.
  throw new TypeError('Estado de disponibilidad no soportado')
}

/**
 * Consume la respuesta ya validada de P-047 y la reduce al estado mínimo que
 * puede renderizar el formulario. P-047 es consultivo: los errores de red no
 * pasan por aquí y deben dejar el alta habilitada; `estado: error`, en cambio,
 * es un veredicto válido del servidor para un teléfono inválido y sí bloquea.
 */
export function presentarDisponibilidadLead(
  resultado: DisponibilidadLead,
): PresentacionDisponibilidadLead {
  switch (resultado.estado) {
    case 'libre':
      return PRESENTACION_LIBRE

    case 'en_bolsa':
      return bloquear('Este contacto ya se encuentra en la bolsa de leads.')

    case 'tomado': {
      const vendedor = textoPresentable(resultado.vendedor)
      return bloquear(
        vendedor
          ? `Este contacto ya está asignado a ${vendedor}.`
          : 'Este contacto ya está asignado a otro miembro del equipo.',
      )
    }

    case 'enfriamiento': {
      const fecha = fechaEnLima(resultado.disponible_desde)
      const motivo = ETIQUETA_MOTIVO[resultado.motivo_descarte]
      return bloquear(
        fecha
          ? `Este contacto está en periodo de enfriamiento por «${motivo}» hasta el ${fecha}.`
          : `Este contacto todavía está en periodo de enfriamiento por «${motivo}».`,
      )
    }

    case 'ya_es_cliente': {
      const asesorPresentable = textoPresentable(resultado.asesor)
      // P-047 usa este sentinel histórico cuando el cliente no tiene asesor;
      // no es un nombre y no debe producir «a cargo de sin asesor asignado».
      const asesor = asesorPresentable?.toLocaleLowerCase('es-PE') === 'sin asesor asignado'
        ? null
        : asesorPresentable
      return bloquear(
        asesor
          ? `Esta persona ya es cliente y está a cargo de ${asesor}.`
          : 'Esta persona ya es cliente de Avance Corp.',
      )
    }

    case 'no_contactar':
      return bloquear('Este contacto está marcado como «No contactar» y no se puede registrar nuevamente.')

    case 'error':
      return bloquear('Ingresa un teléfono válido para verificar su disponibilidad.')

    default:
      return estadoNoSoportado(resultado)
  }
}
