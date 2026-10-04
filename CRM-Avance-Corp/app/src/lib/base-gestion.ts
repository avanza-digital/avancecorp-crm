// lib/base-gestion.ts — contrato y textos de la «Base para gestión» del analista (B1–B3b, en producción
// desde el 02/10/2026). El SERVIDOR decide qué leads entran (descartados vivos, sin «no contactar», sin
// descanso vigente), en qué orden (rellamada de hoy → etapa máxima → menos días) y aplica las reglas
// (3 intentos → 30 días de descanso; rellamada como máximo a 10 días). Aquí solo se valida la forma de
// cada fila y se redacta lo que la pantalla muestra.
import * as v from 'valibot'
import { DIAS, MESES, fechaLima, horaLima } from './agenda-derivada'
import { etiquetaDeMes, mesLima } from './cartera-meses'
import { EnteroNoNegativoRpcSchema, NumeroRpcSchema } from './esquemas-rpc'
import { isoDeCampos } from './campos-siguiente'
import { normalizar } from './clientes-vista'
import { RESULTADOS_LLAMADA, etiquetaResultado } from './resultado-llamada'
import { ETAPA_INFO, MOTIVOS_DESCARTE, TIPOS_ACTIVIDAD, origenLabel, type Actividad, type Lead, type Miembro } from './tipos'

/** Espejo de `private.base_gestion_constantes()`: solo para redactar; el servidor manda. */
export const MAX_INTENTOS_BASE = 3
export const DIAS_DESCANSO_BASE = 30
export const DIAS_MAX_RELLAMADA = 10

/** Etapa más avanzada que alcanzó el lead en su ciclo vigente (deducida del historial, D6). */
export const ETAPAS_MAXIMAS = ['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada', 'convertido', 'sin_datos'] as const
export type EtapaMaxima = (typeof ETAPAS_MAXIMAS)[number]

const TextoONulo = v.nullable(v.string())

/** Una fila de `crm.obtener_base_gestion`. Los campos de presentación aceptan valores nuevos del catálogo
 *  (se muestran tal cual); los que gobiernan la pantalla (etapa, intentos, rellamada) son estrictos. */
export const FilaBaseGestionSchema = v.object({
  lead_id: v.string(),
  nombre_completo: v.string(),
  telefono: TextoONulo,
  distrito: TextoONulo,
  origen: TextoONulo,
  categoria_interes: TextoONulo,
  monto_estimado: v.nullable(NumeroRpcSchema),
  moneda: v.nullable(v.picklist(['PEN', 'USD'] as const)),
  motivo_descarte: TextoONulo,
  descartado_en: TextoONulo,
  dias_desde_descarte: v.nullable(EnteroNoNegativoRpcSchema),
  etapa_maxima: v.picklist(ETAPAS_MAXIMAS),
  intentos: EnteroNoNegativoRpcSchema,
  ultimo_resultado: TextoONulo,
  ultimo_intento_en: TextoONulo,
  proxima_llamada_en: TextoONulo,
  rellamada_hoy: v.boolean(),
  enfriado_hasta: TextoONulo,
  ciclo_n: v.nullable(EnteroNoNegativoRpcSchema),
  vendedor_id: TextoONulo,
  gestiona: TextoONulo,
  /** Cuándo le llegó el lead al analista (`coalesce(tenencia_desde, creado_en)`): el MES por el que se organiza
   *  (Miguel, 02/10/2026). Lo añade la migración B5; opcional para que la pantalla sirva antes y después de ella. */
  recibido_en: v.optional(TextoONulo, null),
  /** «No contactar» (B6b, F4): la marca y de dónde viene (cuándo, motivo y quién, de la última actividad que la puso
   *  sobre ESTE lead; nulos si vino de otro lead de la persona). Solo Supervisión y Gerencia piden los vetados
   *  (`p_incluir_vetados`). Opcionales sin valor por defecto: antes de la B6b el servidor no los manda y la fila
   *  sencillamente no está vetada (el molde de `recibido_en` antes de la B5). */
  no_contactar: v.optional(v.boolean()),
  no_contactar_en: v.optional(TextoONulo),
  no_contactar_motivo: v.optional(TextoONulo),
  no_contactar_por: v.optional(TextoONulo),
})
export type FilaBaseGestion = v.InferOutput<typeof FilaBaseGestionSchema>

/** El lead lleva «No contactar» (Ley 29571): nadie lo llama; solo se ve con «Ver no contactar» (F4). */
export function esVetada(fila: FilaBaseGestion): boolean {
  return fila.no_contactar === true
}

// ── Vista del supervisor (F4): el panel por analista y el detalle de sus cifras ──────────────────────────────
/** Una fila de `crm.base_gestion_resumen`: un analista ACTIVO del ámbito con sus cuatro cifras. */
export const FilaResumenBaseSchema = v.object({
  vendedor_id: v.string(),
  nombre: v.string(),
  en_base: EnteroNoNegativoRpcSchema,
  rellamadas_hoy: EnteroNoNegativoRpcSchema,
  intentos_hoy: EnteroNoNegativoRpcSchema,
  reactivaciones_mes: EnteroNoNegativoRpcSchema,
})
export type FilaResumenBase = v.InferOutput<typeof FilaResumenBaseSchema>

/** Las dos cifras del panel que se abren en un detalle propio (las otras dos filtran la hoja). */
export const CIFRAS_DETALLE = ['intentos_hoy', 'reactivaciones_mes'] as const
export type CifraDetalle = (typeof CIFRAS_DETALLE)[number]

export const TITULO_CIFRA: Readonly<Record<CifraDetalle, string>> = {
  intentos_hoy: 'Intentos de hoy',
  reactivaciones_mes: 'Reactivaciones del mes',
}

/** Una fila de `crm.base_gestion_resumen_detalle` (B6b): qué hay detrás de una cifra, del más reciente al más antiguo. */
export const FilaDetalleCifraSchema = v.object({
  lead_id: v.string(),
  nombre_completo: v.string(),
  en: v.string(),
  detalle: TextoONulo,
  autor: TextoONulo,
  sigue_en_base: v.boolean(),
})
export type FilaDetalleCifra = v.InferOutput<typeof FilaDetalleCifraSchema>

/**
 * Lo que se dice tras «Quitar No contactar» (Codex F4 r1): solo lo que pasó —se quitó la marca, para la persona y sus
 * leads— sin prometer que se le puede llamar ya: si el lead está en descanso, sigue en descanso y se dice hasta cuándo.
 */
export function mensajeNoContactarQuitado(leadsAfectados: number, enfriadoHasta: string | null, ahora: number = Date.now()): string {
  const base = leadsAfectados > 1
    ? `«No contactar» quitado para la persona y sus ${leadsAfectados} leads.`
    : leadsAfectados === 1 ? '«No contactar» quitado para la persona y su lead.' : '«No contactar» quitado.'
  const hasta = enfriadoHasta ? Date.parse(enfriadoHasta) : Number.NaN
  if (!Number.isFinite(hasta) || hasta <= ahora) return base
  const [, mes, dia] = fechaLima(hasta).split('-')
  return `${base} Este lead sigue en descanso hasta el ${dia}/${mes}.`
}

/** El detalle de un INTENTO trae la clave del resultado y se lee con su nombre («No contestó»); el de una
 *  reactivación es la nota que escribió quien reactivó y se muestra tal cual, aunque parezca una clave (Codex F4 r1). */
export function etiquetaDetalleCifra(detalle: string | null, cifra: CifraDetalle): string | null {
  if (!detalle) return null
  return cifra === 'intentos_hoy' ? etiquetaResultado(detalle) : detalle
}

/** «Cita agendada», «Entrevista realizada»… con los mismos nombres que el pipeline. */
export function etiquetaEtapaMaxima(etapa: EtapaMaxima): string {
  return etapa === 'sin_datos' ? 'Sin historial' : ETAPA_INFO[etapa].label
}

/** Color de la etapa máxima: el del pipeline, o gris si no hay historial (el punto de la hoja y el chip de la ficha). */
export function colorEtapaMaxima(etapa: EtapaMaxima): string {
  return etapa === 'sin_datos' ? '#94a3b8' : ETAPA_INFO[etapa].color
}

export function etiquetaMotivoDescarte(motivo: string | null): string {
  if (!motivo) return 'Sin motivo'
  return MOTIVOS_DESCARTE.find((m) => m.k === motivo)?.label ?? motivo
}

export function etiquetaOrigen(origen: string | null): string {
  return origen ? origenLabel(origen) : 'Sin origen'
}

export function etiquetaUltimoResultado(resultado: string | null): string {
  return resultado ? etiquetaResultado(resultado) : 'Sin intentos'
}

/** «Hoy», «Ayer», «Hace 12 días». */
export function etiquetaDiasDescarte(dias: number | null): string {
  if (dias === null) return 'Sin fecha'
  if (dias === 0) return 'Hoy'
  if (dias === 1) return 'Ayer'
  return `Hace ${dias} días`
}

/** «2 de 3»: los intentos de la ventana vigente frente al tope que pone a descansar al lead. Con una
 *  rellamada agendada el 3.º no lo pone a descansar (D12), así que puede haber más: «4 intentos». */
export function etiquetaIntentos(intentos: number): string {
  return intentos <= MAX_INTENTOS_BASE ? `${intentos} de ${MAX_INTENTOS_BASE}` : `${intentos} intentos`
}

export type EstadoRellamada = 'vencida' | 'hoy' | 'futura'

/** Cuándo toca la rellamada agendada, en días calendario de Lima. */
export function estadoRellamada(iso: string, ahora: number = Date.now()): EstadoRellamada {
  const dia = fechaLima(Date.parse(iso))
  const hoy = fechaLima(ahora)
  if (dia < hoy) return 'vencida'
  return dia === hoy ? 'hoy' : 'futura'
}

/** Un momento pasado en Lima: «Hoy, 15:30», «Ayer, 10:00» o «Vie 9 Oct, 10:00». */
export function etiquetaMomento(iso: string, ahora: number = Date.now()): string {
  const ms = Date.parse(iso)
  if (!Number.isFinite(ms)) return 'Sin fecha'
  const dia = fechaLima(ms)
  const hora = horaLima(ms)
  if (dia === fechaLima(ahora)) return `Hoy, ${hora}`
  if (dia === fechaLima(ahora - 86_400_000)) return `Ayer, ${hora}`
  const d = new Date(`${dia}T12:00:00Z`)
  return `${DIAS[d.getUTCDay()]} ${d.getUTCDate()} ${MESES[d.getUTCMonth()]}, ${hora}`
}

/** «Hoy, 15:30», «Mañana, 10:00», «Vie 9 Oct, 10:00»; con «Vencida» si quedó atrás. */
export function etiquetaRellamada(iso: string, ahora: number = Date.now()): string {
  const ms = Date.parse(iso)
  if (!Number.isFinite(ms)) return 'Sin fecha'
  const hora = horaLima(ms)
  const estado = estadoRellamada(iso, ahora)
  if (estado === 'hoy') return `Hoy, ${hora}`
  const d = new Date(`${fechaLima(ms)}T12:00:00Z`)
  const fecha = `${DIAS[d.getUTCDay()]} ${d.getUTCDate()} ${MESES[d.getUTCMonth()]}`
  if (estado === 'vencida') return `Vencida: ${fecha}, ${hora}`
  const manana = fechaLima(ahora + 86_400_000) === fechaLima(ms)
  return manana ? `Mañana, ${hora}` : `${fecha}, ${hora}`
}

/** Rango de la etapa máxima, el de `private.base_gestion_etapa_rango`: ordena como el servidor (más lejos, antes). */
const RANGO_ETAPA: Readonly<Record<EtapaMaxima, number>> = {
  sin_datos: 0, nuevo: 1, contactado: 2, reunion_agendada: 3, propuesta_enviada: 4, convertido: 5,
}

const DIA_MS = 86_400_000

/** Días calendario de Lima entre un instante y hoy (lo que el servidor llama `dias_desde_descarte`). */
function diasLimaDesde(iso: string, ahora: number): number {
  const hoy = Date.parse(`${fechaLima(ahora)}T12:00:00Z`)
  return Math.max(0, Math.round((hoy - Date.parse(`${fechaLima(Date.parse(iso))}T12:00:00Z`)) / DIA_MS))
}

/** El ORDEN de `crm.obtener_base_gestion` (rellamada de hoy o vencida → etapa máxima → descarte más reciente → hora de la
 *  rellamada → id). Solo lo usa el espejo demo: con la sesión real el orden lo trae el servidor y no se toca. */
function ordenDelServidor(a: FilaBaseGestion, b: FilaBaseGestion): number {
  const ms = (iso: string | null) => (iso ? Date.parse(iso) : Number.POSITIVE_INFINITY)
  return Number(b.rellamada_hoy) - Number(a.rellamada_hoy)
    || RANGO_ETAPA[b.etapa_maxima] - RANGO_ETAPA[a.etapa_maxima]
    || (a.dias_desde_descarte ?? Number.POSITIVE_INFINITY) - (b.dias_desde_descarte ?? Number.POSITIVE_INFINITY)
    || ms(a.proxima_llamada_en) - ms(b.proxima_llamada_en)
    || (a.lead_id < b.lead_id ? -1 : a.lead_id > b.lead_id ? 1 : 0)
}

/** Leads de MUESTRA de la demo (F3). En demo no hay historial de intentos: sin ellos no se verían ni el bloque
 *  «Llamar hoy» ni los filtros. Viven solo en la base, como un descartado de meses atrás que el store no carga.
 *  `rellamada` = días desde hoy (−1 = ayer, vencida) y hora de Lima. Con rellamada, el 3.er intento no descansa (D12). */
const MUESTRA_DEMO_BASE: ReadonlyArray<{
  id: string; nombre: string; telefono: string; distrito: string; origen: string; motivo: string; dias: number
  etapa: EtapaMaxima; intentos: number; resultado: string | null; haceIntento: number
  rellamada: { dia: number; hora: string } | null; recibidoHace: number; monto: number
}> = [
  { id: 'demo-base-1', nombre: 'ROBERTO MEZA LIZARRAGA', telefono: '+51981112233', distrito: 'Santiago de Surco', origen: 'landing', motivo: 'sin_fondos', dias: 20, etapa: 'reunion_agendada', intentos: 2, resultado: 'volver_a_llamar', haceIntento: 2, rellamada: { dia: 0, hora: '10:00' }, recibidoHace: 62, monto: 30000 },
  { id: 'demo-base-2', nombre: 'LUCÍA PAREDES OCHOA', telefono: '+51982223344', distrito: 'Lince', origen: 'whatsapp', motivo: 'no_responde', dias: 12, etapa: 'contactado', intentos: 1, resultado: 'volver_a_llamar', haceIntento: 4, rellamada: { dia: -1, hora: '16:30' }, recibidoHace: 35, monto: 15000 },
  { id: 'demo-base-3', nombre: 'VÍCTOR HUAMÁN SALAS', telefono: '+51983334455', distrito: 'Los Olivos', origen: 'formulario', motivo: 'competencia', dias: 30, etapa: 'propuesta_enviada', intentos: 1, resultado: 'no_contesto', haceIntento: 6, rellamada: null, recibidoHace: 64, monto: 50000 },
  { id: 'demo-base-4', nombre: 'SOFÍA RAMÍREZ CÓRDOVA', telefono: '+51984445566', distrito: 'Barranco', origen: 'referido', motivo: 'sin_interes', dias: 9, etapa: 'contactado', intentos: 3, resultado: 'volver_a_llamar', haceIntento: 1, rellamada: { dia: 2, hora: '11:00' }, recibidoHace: 34, monto: 20000 },
  { id: 'demo-base-5', nombre: 'ANDRÉS QUISPE MORALES', telefono: '+51985556677', distrito: 'Comas', origen: 'campania', motivo: 'no_responde', dias: 45, etapa: 'nuevo', intentos: 0, resultado: null, haceIntento: 0, rellamada: null, recibidoHace: 70, monto: 8000 },
  { id: 'demo-base-6', nombre: 'KAREN TORRES VILCHEZ', telefono: '+51986667788', distrito: 'San Miguel', origen: 'landing', motivo: 'sin_fondos', dias: 5, etapa: 'contactado', intentos: 1, resultado: 'no_interesado', haceIntento: 3, rellamada: null, recibidoHace: 12, monto: 12000 },
]

function filasMuestraDemo(analistaId: string, gestiona: string | null, ahora: number): FilaBaseGestion[] {
  const hoy = fechaLima(ahora)
  return MUESTRA_DEMO_BASE.map((m) => {
    const proxima = m.rellamada ? new Date(Date.parse(`${fechaLima(ahora + m.rellamada.dia * DIA_MS)}T${m.rellamada.hora}:00-05:00`)).toISOString() : null
    const descartadoEn = new Date(ahora - m.dias * DIA_MS).toISOString()
    return {
      lead_id: m.id, nombre_completo: m.nombre, telefono: m.telefono, distrito: m.distrito, origen: m.origen,
      categoria_interes: null, monto_estimado: m.monto, moneda: 'PEN' as const, motivo_descarte: m.motivo,
      descartado_en: descartadoEn, dias_desde_descarte: diasLimaDesde(descartadoEn, ahora), etapa_maxima: m.etapa,
      intentos: m.intentos, ultimo_resultado: m.resultado,
      ultimo_intento_en: m.resultado ? new Date(ahora - m.haceIntento * DIA_MS).toISOString() : null,
      // Como el servidor: «de hoy» = la próxima llamada cae HOY o antes en Lima (la vencida sigue tocando).
      proxima_llamada_en: proxima, rellamada_hoy: proxima !== null && fechaLima(Date.parse(proxima)) <= hoy,
      enfriado_hasta: null, ciclo_n: 1, vendedor_id: analistaId, gestiona,
      recibido_en: new Date(ahora - m.recibidoHace * DIA_MS).toISOString(),
    }
  })
}

/**
 * Espejo DEMO (sin red): los descartados vivos del propio analista en el store, sin «no contactar», con la
 * misma forma que la RPC, más unos leads de MUESTRA con intentos, rellamadas (dos para hoy, una vencida) y
 * motivos, etapas y resultados variados (F3). Ordenado como el servidor.
 */
export function filasDemoBaseGestion(leads: readonly Lead[], analistaId: string, ahora: number = Date.now()): FilaBaseGestion[] {
  if (!analistaId) return []
  const propios: FilaBaseGestion[] = leads
    .filter((l) => l.etapa === 'descartado' && l.vendedor_id === analistaId && l.no_contactar !== true)
    .map((l) => {
      const descartadoEn = l.actualizado_en ?? l.creado_en
      return {
        lead_id: l.id, nombre_completo: l.nombre_completo, telefono: l.telefono, distrito: l.distrito ?? null,
        origen: l.origen, categoria_interes: l.categoria_interes ?? null, monto_estimado: l.monto_estimado, moneda: l.moneda,
        motivo_descarte: l.motivo_descarte ?? null, descartado_en: descartadoEn, dias_desde_descarte: diasLimaDesde(descartadoEn, ahora),
        etapa_maxima: 'sin_datos' as const, intentos: 0, ultimo_resultado: null, ultimo_intento_en: null,
        proxima_llamada_en: null, rellamada_hoy: false, enfriado_hasta: null, ciclo_n: null,
        vendedor_id: analistaId, gestiona: l.vendedor_nombre ?? null,
        recibido_en: l.tenencia_desde ?? l.creado_en,
      }
    })
  const gestiona = leads.find((l) => l.vendedor_id === analistaId)?.vendedor_nombre ?? null
  return [...propios, ...filasMuestraDemo(analistaId, gestiona, ahora)].sort(ordenDelServidor)
}

// ── Demo de la vista del supervisor (F4) ──────────────────────────────────────────────────────────────────────
/** Muestra del EQUIPO para la demo de Supervisión y Gerencia: leads repartidos entre los analistas del ámbito (por
 *  turno), uno en la bandeja (sin analista) y tres con «No contactar» (uno con la marca de otro lead de la persona y
 *  otro en descanso). `intentoHoy` = el último intento fue hoy (alimenta «Intentos de hoy»). */
const MUESTRA_DEMO_EQUIPO: ReadonlyArray<{
  nombre: string; distrito: string; origen: string; motivo: string; dias: number; etapa: EtapaMaxima; intentos: number
  resultado: string | null; intentoHoy: boolean; rellamada: { dia: number; hora: string } | null; recibidoHace: number
  bandeja?: boolean; veto?: { haceDias: number; motivo: string | null; por: string | null }; descansa?: number
}> = [
  { nombre: 'ROBERTO MEZA LIZARRAGA', distrito: 'Santiago de Surco', origen: 'landing', motivo: 'sin_fondos', dias: 20, etapa: 'reunion_agendada', intentos: 2, resultado: 'volver_a_llamar', intentoHoy: false, rellamada: { dia: 0, hora: '10:00' }, recibidoHace: 62 },
  { nombre: 'LUCÍA PAREDES OCHOA', distrito: 'Lince', origen: 'whatsapp', motivo: 'no_responde', dias: 12, etapa: 'contactado', intentos: 1, resultado: 'volver_a_llamar', intentoHoy: false, rellamada: { dia: -1, hora: '16:30' }, recibidoHace: 35 },
  { nombre: 'VÍCTOR HUAMÁN SALAS', distrito: 'Los Olivos', origen: 'formulario', motivo: 'competencia', dias: 30, etapa: 'propuesta_enviada', intentos: 1, resultado: 'no_contesto', intentoHoy: true, rellamada: null, recibidoHace: 64 },
  { nombre: 'SOFÍA RAMÍREZ CÓRDOVA', distrito: 'Barranco', origen: 'referido', motivo: 'sin_interes', dias: 9, etapa: 'contactado', intentos: 3, resultado: 'volver_a_llamar', intentoHoy: true, rellamada: { dia: 2, hora: '11:00' }, recibidoHace: 34 },
  { nombre: 'ANDRÉS QUISPE MORALES', distrito: 'Comas', origen: 'campania', motivo: 'no_responde', dias: 45, etapa: 'nuevo', intentos: 0, resultado: null, intentoHoy: false, rellamada: null, recibidoHace: 70 },
  { nombre: 'KAREN TORRES VILCHEZ', distrito: 'San Miguel', origen: 'landing', motivo: 'sin_fondos', dias: 5, etapa: 'contactado', intentos: 1, resultado: 'no_interesado', intentoHoy: true, rellamada: null, recibidoHace: 12 },
  { nombre: 'MARÍA ELENA CASTRO RÍOS', distrito: 'Jesús María', origen: 'landing', motivo: 'no_responde', dias: 16, etapa: 'contactado', intentos: 2, resultado: 'no_contesto', intentoHoy: true, rellamada: null, recibidoHace: 40 },
  { nombre: 'JORGE LUIS PALACIOS VEGA', distrito: 'La Molina', origen: 'referido', motivo: 'pide_credito', dias: 7, etapa: 'reunion_agendada', intentos: 1, resultado: 'volver_a_llamar', intentoHoy: false, rellamada: { dia: 0, hora: '17:00' }, recibidoHace: 22 },
  { nombre: 'PATRICIA NÚÑEZ ARANDA', distrito: 'Surquillo', origen: 'formulario', motivo: 'sin_interes', dias: 25, etapa: 'nuevo', intentos: 0, resultado: null, intentoHoy: false, rellamada: null, recibidoHace: 58 },
  { nombre: 'CÉSAR AUGUSTO LEÓN TAPIA', distrito: 'Ate', origen: 'campania', motivo: 'otro', dias: 3, etapa: 'contactado', intentos: 1, resultado: 'no_contesto', intentoHoy: false, rellamada: null, recibidoHace: 9, bandeja: true },
  { nombre: 'ELENA VARGAS PRADO', distrito: 'Miraflores', origen: 'landing', motivo: 'sin_interes', dias: 14, etapa: 'contactado', intentos: 2, resultado: 'no_interesado', intentoHoy: false, rellamada: null, recibidoHace: 30, veto: { haceDias: 4, motivo: 'Pidió por WhatsApp que no lo llamen más', por: 'ANALISTA UNO' } },
  { nombre: 'RAÚL MENDOZA CHÁVEZ', distrito: 'San Borja', origen: 'referido', motivo: 'no_responde', dias: 21, etapa: 'nuevo', intentos: 3, resultado: 'no_contesto', intentoHoy: false, rellamada: null, recibidoHace: 50, veto: { haceDias: 11, motivo: null, por: null }, descansa: 19 },
  { nombre: 'GLADYS FLORES CANALES', distrito: 'Pueblo Libre', origen: 'whatsapp', motivo: 'sin_fondos', dias: 33, etapa: 'propuesta_enviada', intentos: 1, resultado: 'no_interesado', intentoHoy: false, rellamada: null, recibidoHace: 66, veto: { haceDias: 2, motivo: 'Molesto: dice que ya lo llamaron cinco veces', por: 'SUPERVISOR UNO' } },
]

/** Reactivaciones del mes de la demo: leads que volvieron a la cartera (ya no están en la base). */
const REACTIVADOS_DEMO = ['HÉCTOR SALAZAR PINTO', 'ROSA ELVIRA QUISPE', 'DIEGO ALARCÓN SOTO', 'MILAGROS TELLO RUIZ', 'FERNANDO OCAMPO LUNA']

export interface DemoBaseEquipo {
  /** La base del ámbito, con los «No contactar» al final (como `p_incluir_vetados = true`). */
  filas: FilaBaseGestion[]
  resumen: FilaResumenBase[]
  detalle: (vendedorId: string, cifra: CifraDetalle) => FilaDetalleCifra[]
}

/**
 * Espejo DEMO (sin red) de la vista del supervisor: los analistas activos del ámbito (Gerencia: todos; Supervisión: los
 * suyos), sus descartados del store y una muestra repartida por turno, con el panel y el detalle calculados de esas
 * mismas filas (las cifras cuadran con la hoja). Ordenado como el servidor: los vetados, al final.
 */
export function demoBaseEquipo(
  leads: readonly Lead[],
  equipo: readonly Miembro[],
  yo: { id: string; rol: string } | null,
  ahora: number = Date.now(),
): DemoBaseEquipo {
  if (!yo) return { filas: [], resumen: [], detalle: () => [] }
  const analistas = equipo
    .filter((m) => m.activo && m.rol_crm === 'vendedor' && (yo.rol === 'gerencia' || m.supervisor_id === yo.id))
    .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es'))
  const hoy = fechaLima(ahora)
  // Los momentos «de hoy» y «de este mes» se acotan al día y al mes de Lima (la demo también se abre a medianoche).
  const inicioHoy = Date.parse(`${hoy}T00:00:00-05:00`)
  const inicioMes = Date.parse(`${hoy.slice(0, 8)}01T00:00:00-05:00`)
  const propios = analistas.flatMap((a) =>
    filasDemoBaseGestion(leads, a.perfil_id, ahora).filter((f) => !f.lead_id.startsWith('demo-base-')))
  const muestra: FilaBaseGestion[] = analistas.length === 0 ? [] : MUESTRA_DEMO_EQUIPO.map((m, i) => {
    const a = analistas[i % analistas.length]!
    const proxima = m.rellamada ? new Date(Date.parse(`${fechaLima(ahora + m.rellamada.dia * DIA_MS)}T${m.rellamada.hora}:00-05:00`)).toISOString() : null
    const descartadoEn = new Date(ahora - m.dias * DIA_MS).toISOString()
    const haceUnRato = Math.min(ahora, Math.max(inicioHoy + (i + 1) * 60_000, ahora - (i + 1) * 37 * 60_000))
    const ultimoIntento = m.resultado ? new Date(m.intentoHoy ? haceUnRato : ahora - (i + 2) * DIA_MS).toISOString() : null
    const vetada = m.veto !== undefined
    return {
      lead_id: `demo-equipo-${i + 1}`, nombre_completo: m.nombre, telefono: `+5198${String(1000000 + i * 1111).padStart(7, '0')}`,
      distrito: m.distrito, origen: m.origen, categoria_interes: null, monto_estimado: 10000 + i * 2500, moneda: 'PEN' as const,
      motivo_descarte: m.motivo, descartado_en: descartadoEn, dias_desde_descarte: diasLimaDesde(descartadoEn, ahora),
      etapa_maxima: m.etapa, intentos: m.intentos, ultimo_resultado: m.resultado, ultimo_intento_en: ultimoIntento,
      proxima_llamada_en: proxima,
      // Como el servidor: un vetado nunca está en «Llamar hoy».
      rellamada_hoy: !vetada && proxima !== null && fechaLima(Date.parse(proxima)) <= hoy,
      enfriado_hasta: m.descansa ? new Date(ahora + m.descansa * DIA_MS).toISOString() : null, ciclo_n: 1,
      vendedor_id: m.bandeja ? null : a.perfil_id, gestiona: m.bandeja ? null : a.nombre_completo,
      recibido_en: new Date(ahora - m.recibidoHace * DIA_MS).toISOString(),
      no_contactar: vetada,
      no_contactar_en: m.veto && (m.veto.motivo || m.veto.por) ? new Date(ahora - m.veto.haceDias * DIA_MS).toISOString() : null,
      no_contactar_motivo: m.veto?.motivo ?? null,
      no_contactar_por: m.veto?.por ?? null,
    }
  })
  const todas = [...propios, ...muestra]
  const vivas = todas.filter((f) => !esVetada(f)).sort(ordenDelServidor)
  const vetadas = todas.filter(esVetada).sort(ordenDelServidor)
  const intentosHoy = (id: string) => vivas.filter((f) => f.vendedor_id === id && f.ultimo_intento_en !== null && fechaLima(Date.parse(f.ultimo_intento_en)) === hoy)
  const reactivados = (indice: number, a: Miembro): FilaDetalleCifra[] =>
    REACTIVADOS_DEMO.filter((_, j) => j % analistas.length === indice).map((nombre, j) => ({
      lead_id: `demo-reactivado-${indice}-${j}`, nombre_completo: nombre,
      en: new Date(Math.min(ahora, Math.max(inicioMes + (j + 1) * 3_600_000, ahora - (j + 1) * 3 * 3_600_000))).toISOString(),
      detalle: 'Reactivado desde la base', autor: a.nombre_completo, sigue_en_base: false,
    }))
  const resumen: FilaResumenBase[] = analistas.map((a, i) => ({
    vendedor_id: a.perfil_id, nombre: a.nombre_completo,
    en_base: vivas.filter((f) => f.vendedor_id === a.perfil_id).length,
    rellamadas_hoy: vivas.filter((f) => f.vendedor_id === a.perfil_id && f.rellamada_hoy).length,
    intentos_hoy: intentosHoy(a.perfil_id).length,
    reactivaciones_mes: reactivados(i, a).length,
  }))
  const detalle = (vendedorId: string, cifra: CifraDetalle): FilaDetalleCifra[] => {
    const i = analistas.findIndex((a) => a.perfil_id === vendedorId)
    const a = analistas[i]
    if (!a) return []
    if (cifra === 'reactivaciones_mes') return reactivados(i, a)
    return intentosHoy(vendedorId)
      .map((f) => ({ lead_id: f.lead_id, nombre_completo: f.nombre_completo, en: f.ultimo_intento_en ?? '', detalle: f.ultimo_resultado, autor: f.gestiona, sigue_en_base: true }))
      .sort((x, y) => (x.en < y.en ? 1 : x.en > y.en ? -1 : 0))
  }
  return { filas: [...vivas, ...vetadas], resumen, detalle }
}

// ── El MES del lead: «mis leads de enero, de marzo, de agosto» (Miguel, 02/10/2026) ──────────────────────────
/** Valor del selector que apaga el recorte por mes. */
export const MES_TODOS = 'todos'

/** 'YYYY-MM' en Lima del mes en que le llegó el lead al analista; null si el servidor aún no lo manda. */
export function mesDelLead(fila: FilaBaseGestion): string | null {
  return mesLima(fila.recibido_en)
}

/** 'Agosto 2026' (rótulo largo de la casa, el de los bloques de «Mi cartera»). */
export function etiquetaMesLead(clave: string): string {
  return etiquetaDeMes(clave)
}

export interface MesDeLaBase {
  clave: string
  etiqueta: string
  leads: number
}

/** Los meses presentes en la base con su conteo, del más reciente al más antiguo. Vacío si ninguna fila trae el mes. */
export function mesesDeLaBase(filas: readonly FilaBaseGestion[]): MesDeLaBase[] {
  const conteo = new Map<string, number>()
  for (const f of filas) {
    const mes = mesDelLead(f)
    if (mes) conteo.set(mes, (conteo.get(mes) ?? 0) + 1)
  }
  return [...conteo.entries()]
    .sort(([a], [b]) => (a < b ? 1 : a > b ? -1 : 0))
    .map(([clave, leads]) => ({ clave, etiqueta: etiquetaMesLead(clave), leads }))
}

// ── Organizar el trabajo (F3): «Llamar hoy» arriba y filtros en el navegador ─────────────────────────────────
// El servidor ya decide QUÉ filas y en qué ORDEN; aquí solo se separa y se recorta lo que llegó, sin reordenar.

/** Valor de un filtro apagado (el mismo que el del Mes). */
export const FILTRO_TODOS = MES_TODOS
/** Clave de la opción «sin dato» (lead sin motivo de descarte o sin intentos): no choca con ninguna clave del catálogo. */
export const SIN_DATO = '(sin dato)'

/** `analista` (F4) solo lo ofrece la vista del supervisor: la base del analista es toda suya y no lo muestra. */
export type DimensionFiltro = 'mes' | 'motivo' | 'etapa' | 'resultado' | 'analista'
const DIMENSIONES: readonly DimensionFiltro[] = ['mes', 'motivo', 'etapa', 'resultado', 'analista']

export interface FiltrosBase {
  mes: string
  motivo: string
  etapa: string
  resultado: string
  /** Quién lo gestiona (`vendedor_id`); {@link SIN_DATO} = la bandeja, sin analista. */
  analista: string
  /** Solo los que tienen una rellamada agendada para otro día (la pastilla «Rellamadas agendadas» se abre así). */
  agendadas: boolean
}

export const SIN_FILTROS: FiltrosBase = { mes: FILTRO_TODOS, motivo: FILTRO_TODOS, etapa: FILTRO_TODOS, resultado: FILTRO_TODOS, analista: FILTRO_TODOS, agendadas: false }

/** Quién gestiona el lead, como lo lee el supervisor: su analista o «Sin analista» (la bandeja del equipo). */
export function etiquetaAnalista(fila: Pick<FilaBaseGestion, 'vendedor_id' | 'gestiona'>): string {
  if (!fila.vendedor_id) return 'Sin analista'
  return fila.gestiona ?? 'Analista sin nombre'
}

/** Rellamada agendada para más adelante (las de hoy o vencidas van en «Llamar hoy»). */
export function tieneRellamadaAgendada(fila: FilaBaseGestion): boolean {
  return fila.proxima_llamada_en !== null && !fila.rellamada_hoy
}

/** La clave de la fila en cada filtro. El mes puede faltar (antes de la B5): esa fila solo pasa con «Todos». */
function claveDe(fila: FilaBaseGestion, dimension: DimensionFiltro): string | null {
  switch (dimension) {
    case 'mes': return mesDelLead(fila)
    case 'motivo': return fila.motivo_descarte ?? SIN_DATO
    case 'etapa': return fila.etapa_maxima
    case 'resultado': return fila.ultimo_resultado ?? SIN_DATO
    case 'analista': return fila.vendedor_id ?? SIN_DATO
  }
}

/** ¿La fila pasa los filtros? `salvo` deja fuera uno (para contar las opciones de ese mismo filtro). */
function pasa(fila: FilaBaseGestion, filtros: FiltrosBase, salvo?: DimensionFiltro): boolean {
  for (const d of DIMENSIONES) {
    if (d !== salvo && filtros[d] !== FILTRO_TODOS && claveDe(fila, d) !== filtros[d]) return false
  }
  return !filtros.agendadas || tieneRellamadaAgendada(fila)
}

/** ¿Hay algún filtro encendido (el Mes incluido)? */
export function hayFiltros(filtros: FiltrosBase): boolean {
  return filtros.agendadas || DIMENSIONES.some((d) => filtros[d] !== FILTRO_TODOS)
}

/** Las filas que pasan todos los filtros, en el MISMO orden en que llegaron del servidor. */
export function filtrarBase(filas: readonly FilaBaseGestion[], filtros: FiltrosBase): FilaBaseGestion[] {
  return filas.filter((f) => pasa(f, filtros))
}

/** «Llamar hoy» (rellamadas de hoy o vencidas) y «El resto», cada bloque en el orden del servidor. */
export function separarLlamarHoy(filas: readonly FilaBaseGestion[]): { hoy: FilaBaseGestion[]; resto: FilaBaseGestion[] } {
  const hoy: FilaBaseGestion[] = []
  const resto: FilaBaseGestion[] = []
  for (const f of filas) (f.rellamada_hoy ? hoy : resto).push(f)
  return { hoy, resto }
}

export interface OpcionFiltro {
  clave: string
  etiqueta: string
  leads: number
}
/** Un filtro: «Todos (total)» y cada opción con su conteo. */
export interface FacetaFiltro {
  total: number
  opciones: OpcionFiltro[]
}
export type OpcionesFiltro = Record<DimensionFiltro, FacetaFiltro>

const esEtapaMaxima = (clave: string): clave is EtapaMaxima => (ETAPAS_MAXIMAS as readonly string[]).includes(clave)

/** Cómo se lee una opción: con los mismos rótulos que las columnas de la hoja. */
export function etiquetaOpcion(dimension: DimensionFiltro, clave: string): string {
  switch (dimension) {
    case 'mes': return etiquetaMesLead(clave)
    case 'motivo': return etiquetaMotivoDescarte(clave === SIN_DATO ? null : clave)
    case 'etapa': return esEtapaMaxima(clave) ? etiquetaEtapaMaxima(clave) : clave
    case 'resultado': return etiquetaUltimoResultado(clave === SIN_DATO ? null : clave)
    // El nombre lo sabe la fila (`gestiona`): `opcionesFiltro` lo pone. Sin filas, solo se reconoce la bandeja.
    case 'analista': return clave === SIN_DATO ? 'Sin analista' : clave
  }
}

/** Orden ESTABLE de las opciones (no salta al cambiar los conteos): el motivo y el resultado, el del catálogo; la etapa,
 *  la que llegó más lejos primero (como la hoja). Lo que el catálogo no conoce va después y «sin dato», al final. */
function rangoOpcion(dimension: DimensionFiltro, clave: string): number {
  if (clave === SIN_DATO) return Number.POSITIVE_INFINITY
  const i = dimension === 'motivo' ? MOTIVOS_DESCARTE.findIndex((m) => m.k === clave)
    : dimension === 'resultado' ? (RESULTADOS_LLAMADA as readonly string[]).indexOf(clave)
      : dimension === 'etapa' && esEtapaMaxima(clave) ? (clave === 'sin_datos' ? 99 : 5 - RANGO_ETAPA[clave])
        : -1
  return i === -1 ? 100 : i
}

function ordenarOpciones(dimension: DimensionFiltro, opciones: OpcionFiltro[]): OpcionFiltro[] {
  // El analista, por nombre (como el panel); «Sin analista» al final (su clave es la de «sin dato»).
  // El mes, del más reciente al más antiguo (como el selector de F1).
  if (dimension === 'mes') return opciones.sort((a, b) => (a.clave < b.clave ? 1 : a.clave > b.clave ? -1 : 0))
  return opciones.sort((a, b) => rangoOpcion(dimension, a.clave) - rangoOpcion(dimension, b.clave) || a.etiqueta.localeCompare(b.etiqueta, 'es'))
}

/**
 * Las opciones de cada filtro con su conteo. Cada filtro cuenta sobre lo que dejan pasar LOS DEMÁS (el Mes incluido):
 * el número de una opción es exactamente lo que el analista verá al elegirla. Solo se listan las opciones que existen;
 * la elegida se lista siempre (aunque los otros filtros la dejen en 0), para que el selector no muestre un valor ausente.
 */
export function opcionesFiltro(filas: readonly FilaBaseGestion[], filtros: FiltrosBase = SIN_FILTROS): OpcionesFiltro {
  // El nombre de cada analista, de sus filas (el de la primera que lo trae).
  const nombres = new Map<string, string>()
  for (const f of filas) if (f.vendedor_id && !nombres.has(f.vendedor_id)) nombres.set(f.vendedor_id, etiquetaAnalista(f))
  const etiqueta = (dimension: DimensionFiltro, clave: string) =>
    (dimension === 'analista' ? nombres.get(clave) : undefined) ?? etiquetaOpcion(dimension, clave)
  const faceta = (dimension: DimensionFiltro): FacetaFiltro => {
    const conteo = new Map<string, number>()
    let total = 0
    for (const f of filas) {
      if (!pasa(f, filtros, dimension)) continue
      total += 1
      const clave = claveDe(f, dimension)
      if (clave !== null) conteo.set(clave, (conteo.get(clave) ?? 0) + 1)
    }
    const elegido = filtros[dimension]
    if (elegido !== FILTRO_TODOS && !conteo.has(elegido)) conteo.set(elegido, 0)
    const opciones = [...conteo.entries()].map(([clave, leads]) => ({ clave, etiqueta: etiqueta(dimension, clave), leads }))
    return { total, opciones: ordenarOpciones(dimension, opciones) }
  }
  return { mes: faceta('mes'), motivo: faceta('motivo'), etapa: faceta('etapa'), resultado: faceta('resultado'), analista: faceta('analista') }
}

/**
 * Tras un refresco, el filtro cuyo valor ya no existe en la base (el último lead de ese motivo salió) vuelve a «Todos» y
 * se OLVIDA, como el Mes de F1: si un refresco posterior lo trae de vuelta, la hoja no se filtra sola. Devuelve el MISMO
 * objeto si nada cambia (la pantalla lo compara por identidad).
 */
export function depurarFiltros(filas: readonly FilaBaseGestion[], filtros: FiltrosBase): FiltrosBase {
  let depurados: FiltrosBase | null = null
  for (const d of DIMENSIONES) {
    if (filtros[d] !== FILTRO_TODOS && !filas.some((f) => claveDe(f, d) === filtros[d])) depurados = { ...(depurados ?? filtros), [d]: FILTRO_TODOS }
  }
  if (filtros.agendadas && !filas.some(tieneRellamadaAgendada)) depurados = { ...(depurados ?? filtros), agendadas: false }
  return depurados ?? filtros
}

// ── La ficha del lead de la base (F2) ─────────────────────────────────────────────────────────────────────
/** «Volver a llamar» exige fecha y hora: futura y como máximo a {@link DIAS_MAX_RELLAMADA} días. La pantalla avisa
 *  antes de enviar; la puerta vuelve a validar (manda ella). Devuelve el instante ISO o el motivo para no enviarlo. */
export function validarRellamada(fecha: string, hora: string, ahora: number = Date.now()): { iso: string } | { error: string } {
  const iso = isoDeCampos({ tipo: 'llamada', titulo: '', fecha, hora })
  if (!iso) return { error: 'Elige la fecha y la hora de la próxima llamada.' }
  const ms = Date.parse(iso)
  if (ms <= ahora) return { error: 'La próxima llamada tiene que ser más adelante que ahora.' }
  if (ms > ahora + DIAS_MAX_RELLAMADA * 86_400_000) return { error: `La próxima llamada puede agendarse como máximo a ${DIAS_MAX_RELLAMADA} días.` }
  return { iso }
}

/** Lo que se envía con un intento, como texto estable: el MISMO contenido reusa su `p_operacion_id` (un doble clic o
 *  un reintento tras un corte devuelven la respuesta original); otro contenido lleva un id nuevo (si no, 23505). */
export function firmaIntento(entrada: { resultado: string; nota: string; proximaLlamada: string | null }): string {
  return JSON.stringify([entrada.resultado, entrada.nota.trim(), entrada.proximaLlamada])
}

/** Cómo se lee una actividad en el historial de la base: los intentos, la reactivación y el «No contactar» dicen lo
 *  que fueron (el servidor los guarda como `nota` con el evento en la metadata; sin esto se leerían «Nota»). */
export function etiquetaActividadBase(a: Actividad): string {
  const meta = a.metadata ?? {}
  if (meta.evento === 'intento_base') {
    const n = typeof meta.intento_n === 'number' ? meta.intento_n : Number(meta.intento_n)
    const resultado = typeof meta.resultado === 'string' ? etiquetaResultado(meta.resultado) : 'Intento'
    return Number.isFinite(n) && n > 0 ? `Intento ${n} · ${resultado}` : resultado
  }
  if (meta.evento === 'reactivacion_base') return 'Reactivado desde la base'
  if (meta.evento === 'no_contactar') {
    // `accion` la escriben crm.marcar_no_contactar ('marcar') y crm.levantar_no_contactar ('levantar').
    if (meta.accion === 'marcar') return 'Marcado «No contactar»'
    if (meta.accion === 'levantar') return 'Levantado «No contactar»'
    return 'No contactar'
  }
  return TIPOS_ACTIVIDAD[a.tipo] ?? 'Actividad'
}

/** Buscador del historial: sin mayúsculas ni tildes, sobre lo que el analista lee (qué pasó, nota y quién). */
export function filtrarHistorial(items: readonly Actividad[], texto: string): Actividad[] {
  const buscado = normalizar(texto.trim())
  if (!buscado) return [...items]
  return items.filter((a) => normalizar(`${etiquetaActividadBase(a)} ${a.detalle ?? ''} ${a.autor_nombre}`).includes(buscado))
}

