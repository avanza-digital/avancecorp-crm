import * as v from 'valibot'
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
    // Claves que el servidor estrena en fases posteriores del plan «lead
    // libre» (F1: última conversación real; F4: fecha estimada de revisión).
    // OPCIONALES a propósito: el front tolera ambas versiones del servidor
    // — la lección del 2026-08-15: una clave nueva en la RESPUESTA de una
    // RPC con contrato estricto apaga la pantalla entera si el front no
    // salió primero. strictObject se conserva: una clave NO declarada sigue
    // siendo error (caza typos y respuestas inesperadas).
    ultima_conversacion_en: v.optional(v.nullable(v.pipe(v.string(), v.isoTimestamp()))),
    fecha_estimada: v.optional(v.nullable(v.pipe(v.string(), v.isoTimestamp()))),
  }),
  v.strictObject({
    estado: v.literal('enfriamiento'),
    motivo_descarte: v.picklist(MOTIVOS_DISPONIBILIDAD),
    disponible_desde: v.pipe(v.string(), v.isoTimestamp()),
    descartado_por: v.nullable(v.string()),
  }),
  // Estado FUTURO (F2 del plan «lead libre»: contacto con un lead anterior
  // que puede RETOMARSE en vez de duplicarse). looseObject a propósito: hasta
  // que exista quien sepa manejarlo solo importa el discriminante, y su forma
  // final la decide la Fase 2 — tolerar hoy evita el apagón del 15-ago.
  v.looseObject({ estado: v.literal('reutilizable') }),
  v.strictObject({ estado: v.literal('ya_es_cliente'), asesor: v.string() }),
  v.strictObject({ estado: v.literal('no_contactar') }),
  v.strictObject({ estado: v.literal('error'), detalle: v.literal('telefono_invalido') }),
])

// Del CONTRATO, no de los tipos generados: el generador typea el retorno de
// una RPC jsonb como `Json` y el variant de arriba es la verdad de runtime.
export type DisponibilidadLead = v.InferOutput<typeof DisponibilidadLeadSchema>

/** Respuesta de la mutación: o confirma la identidad creada, o devuelve el
 * mismo veredicto bloqueante de P-047. Nunca existe «libre sin insertar». */
export const ResultadoCreacionLeadAtomicaSchema = v.union([
  v.strictObject({
    estado: v.literal('creado'),
    lead_id: v.pipe(v.string(), v.uuid()),
  }),
  // Resultado FUTURO (F2): el alta sobre un contacto reutilizable REABRE el
  // mismo lead en vez de insertar. Tolerado desde ya por la misma razón que
  // 'reutilizable' — quien lo maneja nace en la Fase 2.
  v.looseObject({
    estado: v.literal('reutilizado'),
    lead_id: v.optional(v.pipe(v.string(), v.uuid())),
  }),
  DisponibilidadLeadSchema,
])

export type ResultadoCreacionLeadAtomica =
  v.InferOutput<typeof ResultadoCreacionLeadAtomicaSchema>

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

    case 'reutilizable':
      // Estado futuro (F2): mientras no exista el botón «Tomar», el alta se
      // bloquea con un mensaje honesto — dejarla pasar duplicaría el lead,
      // exactamente lo que la spec §5.6 prohíbe.
      return bloquear('Este contacto tiene un seguimiento anterior que puede retomarse. La toma directa aún no está habilitada.')

    case 'error':
      return bloquear('Ingresa un teléfono válido para verificar su disponibilidad.')

    default:
      return estadoNoSoportado(resultado)
  }
}

// ── Tarjeta de la spec §5.2 ──────────────────────────────────────────────────

/**
 * Tarjeta informativa de SOLO LECTURA para el vendedor que verifica: los datos
 * mínimos del seguimiento, nada más (spec §8: sin notas, sin montos, sin
 * detalle ajeno). Función hermana de presentarDisponibilidadLead — NO amplía
 * su contrato {mensaje, bloquea}, que está fijado por prueba — y consume el
 * JSON una sola vez, igual que él.
 *
 * «Revisable desde (estimado)» solo aparece cuando el servidor manda una fecha
 * con motor real detrás (enfriamiento hoy; leads tomados recién en la F4 del
 * plan): la tarjeta no inventa promesas.
 */
export type TarjetaDisponibilidadLead = Readonly<{
  titulo: string
  lineas: ReadonlyArray<Readonly<{ etiqueta: string; valor: string }>>
}>

export function tarjetaDisponibilidadLead(
  resultado: DisponibilidadLead,
): TarjetaDisponibilidadLead | null {
  switch (resultado.estado) {
    case 'tomado': {
      const lineas: Array<{ etiqueta: string; valor: string }> = []
      const asesor = textoPresentable(resultado.vendedor)
      if (asesor) lineas.push({ etiqueta: 'Asesor', valor: asesor })
      const desde = resultado.tenencia_desde != null ? fechaEnLima(resultado.tenencia_desde) : null
      if (desde) lineas.push({ etiqueta: 'En seguimiento desde', valor: desde })
      const conversacion = resultado.ultima_conversacion_en != null
        ? fechaEnLima(resultado.ultima_conversacion_en)
        : null
      if (conversacion) lineas.push({ etiqueta: 'Última conversación', valor: conversacion })
      const estimada = resultado.fecha_estimada != null ? fechaEnLima(resultado.fecha_estimada) : null
      if (estimada) lineas.push({ etiqueta: 'Revisable desde (estimado)', valor: estimada })
      return { titulo: 'Seguimiento activo', lineas }
    }
    case 'enfriamiento': {
      const lineas: Array<{ etiqueta: string; valor: string }> = [
        { etiqueta: 'Motivo del descarte', valor: ETIQUETA_MOTIVO[resultado.motivo_descarte] },
      ]
      // Quién lo descartó NO va en la tarjeta (minimización §8); la fecha sí:
      // es la única «disponible desde» con regla real detrás hoy.
      const fecha = fechaEnLima(resultado.disponible_desde)
      if (fecha) lineas.push({ etiqueta: 'Disponible desde', valor: fecha })
      return { titulo: 'En enfriamiento', lineas }
    }
    default:
      return null
  }
}
