import * as v from 'valibot'
import { ETAPAS, MOTIVOS_DESCARTE_LECTURA, type MotivoDescarteLectura } from './tipos'

// Catálogo de LECTURA: un contacto de base cargada (descartado con motivo `base_cargada`, E7) puede volver como
// «enfriamiento» o «reutilizable». Con el catálogo cerrado, el veredicto entero fallaba y el alta quedaba sin respuesta.
const MOTIVOS_DISPONIBILIDAD = MOTIVOS_DESCARTE_LECTURA.map((motivo) => motivo.k)

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
  // F2 lead libre (§5.6): contacto con un lead descartado y enfriamiento
  // VENCIDO — se RETOMA en vez de duplicarse. Forma fijada contra el emisor
  // vivo (migración 20260817164745, en prod): las claves llegan SIEMPRE
  // (jsonb_build_object no omite nulos), por eso nullable sin optional.
  // Nulabilidad con evidencia: motivo_descarte jamás es null en un descartado
  // (CHECK de cimientos) y el catálogo de lectura es el CHECK (7) + `base_cargada` (B7);
  // descartado_en lo exige el WHERE del impl; quedo_libre_en siempre se
  // calcula; descartado_por sale de un LEFT JOIN y ultima_conversacion_en de
  // un max() — esos dos sí pueden ser null. Veneno conocido (auditoría
  // 2026-08-17): un 'infinity' de PG17 en un timestamptz NO pasa isoTimestamp
  // — a propósito: fail-closed antes que pintar basura (CHECK de finitud en
  // el servidor = deuda anotada para F3).
  v.strictObject({
    estado: v.literal('reutilizable'),
    motivo_descarte: v.picklist(MOTIVOS_DISPONIBILIDAD),
    descartado_en: v.pipe(v.string(), v.isoTimestamp()),
    quedo_libre_en: v.pipe(v.string(), v.isoTimestamp()),
    descartado_por: v.nullable(v.string()),
    ultima_conversacion_en: v.nullable(v.pipe(v.string(), v.isoTimestamp())),
  }),
  // `via: 'identidad'` (multiempresa, 20260903260000): la persona ya tiene lead
  // reconocido por su documento aunque no tenga perfil. Opcional: con la bandera
  // apagada el servidor no la manda y el veredicto se pinta igual.
  v.strictObject({
    estado: v.literal('ya_es_cliente'),
    asesor: v.string(),
    via: v.optional(v.literal('identidad')),
  }),
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

// ── La toma directa (F2 «Tomar», spec §5.6/§5.7) ─────────────────────────────

const ETAPAS_ACTIVAS = ETAPAS.map((etapa) => etapa.k)

/** Los dos únicos veredictos con puerta de toma. El nombre del modo es el del
 *  servidor ('bolsa' para en_bolsa): así la traza y el front hablan igual. */
export type ModoToma = 'bolsa' | 'reutilizable'

/** ¿El veredicto habilita el botón «Tomar lead e iniciar seguimiento»?
 *  SOLO en_bolsa y reutilizable (espejo exacto de los dos CAS de
 *  crm.tomar_lead_libre) — jamás sobre tomado/enfriamiento/cliente, y sobre
 *  'libre' tampoco: ahí no hay nada que tomar, el camino es CREAR. */
export function contactoTomable(resultado: DisponibilidadLead): ModoToma | null {
  switch (resultado.estado) {
    case 'en_bolsa': return 'bolsa'
    case 'reutilizable': return 'reutilizable'
    default: return null
  }
}

/** Respuesta autoritativa de crm.tomar_lead_libre: o la toma confirmada, o el
 *  veredicto FRESCO de disponibilidad (el perdedor de la carrera jamás roba —
 *  recibe la verdad del momento). Forma fijada contra el emisor vivo
 *  (migración 20260817164745): jsonb_build_object con 6 claves, todas
 *  siempre presentes; etapa espejo del CHECK (bolsa conserva la suya,
 *  reutilizable renace en 'nuevo' — nunca terminal tras una toma). */
export const TomaLeadOkSchema = v.strictObject({
  estado: v.literal('tomado_ok'),
  lead_id: v.pipe(v.string(), v.uuid()),
  modo: v.picklist(['bolsa', 'reutilizable']),
  etapa: v.picklist(ETAPAS_ACTIVAS),
  ciclo_actual: v.pipe(v.number(), v.integer()),
  tenencia_desde: v.pipe(v.string(), v.isoTimestamp()),
})

export const ResultadoTomaLeadSchema = v.union([
  TomaLeadOkSchema,
  DisponibilidadLeadSchema,
])

export type ResultadoTomaLead = v.InferOutput<typeof ResultadoTomaLeadSchema>

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
  MOTIVOS_DESCARTE_LECTURA.map(({ k, label }) => [k, label]),
) as Readonly<Record<MotivoDescarteLectura, string>>

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
      // P-047 usa el campo legacy `asesor` y este sentinel histórico cuando el
      // cliente no tiene analista; no es un nombre y no debe producir
      // «a cargo de sin asesor asignado».
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
      // El alta sigue bloqueada (crear duplicaría, §5.6) — el camino es el
      // botón «Tomar lead e iniciar seguimiento», que el formulario ofrece al
      // analista junto a este aviso (contactoTomable decide cuándo).
      return bloquear('Este contacto tiene un seguimiento anterior que puede retomarse en lugar de crear un duplicado.')

    case 'error':
      return bloquear('Ingresa un teléfono válido para verificar su disponibilidad.')

    default:
      return estadoNoSoportado(resultado)
  }
}

/**
 * Presenta el veredicto fresco que devuelve una toma SIN éxito (§5.7): el
 * estado cambió entre el precheck y la escritura — otro se adelantó, un
 * enfriamiento renació, el lead desapareció. El prefijo avisa del cambio solo
 * cuando el veredicto bloquea; un 'libre' fresco no lleva aviso: el alta se
 * habilita y crear es el camino.
 */
export function presentarResultadoToma(
  resultado: DisponibilidadLead,
): PresentacionDisponibilidadLead {
  const base = presentarDisponibilidadLead(resultado)
  if (!base.bloquea || base.mensaje == null) return base
  return { mensaje: `La disponibilidad acaba de cambiar. ${base.mensaje}`, bloquea: true }
}

// ── Tarjeta de la spec §5.2 ──────────────────────────────────────────────────

/**
 * Tarjeta informativa de SOLO LECTURA para el analista que verifica: los datos
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
      if (asesor) lineas.push({ etiqueta: 'Analista', valor: asesor })
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
    case 'reutilizable': {
      // La historia mínima del seguimiento anterior ya recuperable (§5.6):
      // motivo, cuándo se descartó, desde cuándo está libre y la última
      // conversación real. `descartado_por` llega del servidor pero NO se
      // pinta — misma minimización §8 que la tarjeta de enfriamiento.
      const lineas: Array<{ etiqueta: string; valor: string }> = [
        { etiqueta: 'Motivo del descarte', valor: ETIQUETA_MOTIVO[resultado.motivo_descarte] },
      ]
      const descartado = fechaEnLima(resultado.descartado_en)
      if (descartado) lineas.push({ etiqueta: 'Descartado el', valor: descartado })
      const libre = fechaEnLima(resultado.quedo_libre_en)
      if (libre) lineas.push({ etiqueta: 'Libre desde', valor: libre })
      const conversacion = resultado.ultima_conversacion_en != null
        ? fechaEnLima(resultado.ultima_conversacion_en)
        : null
      if (conversacion) lineas.push({ etiqueta: 'Última conversación', valor: conversacion })
      return { titulo: 'Seguimiento anterior disponible', lineas }
    }
    default:
      return null
  }
}
