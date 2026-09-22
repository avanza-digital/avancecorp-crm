// Gestión Diaria — contrato del DÍA DEL ANALISTA (Fase 3) y sus helpers puros.
// La fuente única es `crm.gestion_diaria_analista_fn` (migración 20260920041500):
// marcador del día, compromisos desde mañana, señales por lead abierto y los
// descartes del día con su «Deshacer». La COLA sigue saliendo de
// `crm.cola_accion_v2_fn` (`data/sla-operacion-api.ts`): aquí se ORDENA, no se
// recalcula. Nada de negocio se decide en esta capa: el servidor manda.
import * as v from 'valibot'
import type { ColaSlaPagina } from '@/lib/sla-operacion'

/** Ítem de la cola v2 tal como llega; el bucket es texto libre en el contrato. */
export type ItemColaSla = ColaSlaPagina['items'][number]

export const UmbralesSchema = v.object({
  version: v.literal(1),
  /** Versión de política; distinta de la versión estable del contrato JSON. */
  politica_version: v.optional(v.pipe(v.number(), v.integer(), v.minValue(1))),
  bien_min_pct: v.number(),
  atencion_min_pct: v.number(),
  minimo_llamadas_utiles: v.number(),
})

export const MarcadorSchema = v.object({
  llamadas: v.number(),
  contestadas: v.number(),
  utiles: v.number(),
  /** null cuando no hubo llamadas útiles: «—», nunca 0 %. */
  tasa_contacto_pct: v.nullable(v.number()),
  /** null por debajo del mínimo de llamadas útiles: sin chip (decisión #7). */
  nivel: v.nullable(v.picklist(['bien', 'atencion', 'bajo'])),
  leads_tocados: v.number(),
  citas_agendadas: v.number(),
  primera_llamada_en: v.nullable(v.string()),
  ultima_llamada_en: v.nullable(v.string()),
  por_resultado: v.record(v.string(), v.number()),
  por_hora: v.array(v.object({ hora: v.number(), llamadas: v.number(), contestadas: v.number() })),
})
export type Marcador = v.InferOutput<typeof MarcadorSchema>

export const CompromisoSchema = v.object({
  tarea_id: v.string(),
  lead_id: v.string(),
  lead_nombre: v.string(),
  lead_etapa: v.string(),
  tipo: v.picklist(['llamada', 'reunion']),
  titulo: v.string(),
  vence_en: v.string(),
  modalidad_reunion: v.nullable(v.string()),
})
export type Compromiso = v.InferOutput<typeof CompromisoSchema>

export const SenalCarteraSchema = v.object({
  lead_id: v.string(),
  nombre_completo: v.string(),
  etapa: v.string(),
  tenencia_desde: v.nullable(v.string()),
  ciclo_desde: v.nullable(v.string()),
  llamadas_ciclo: v.number(),
  intentos_sin_respuesta: v.number(),
  ultima_llamada_en: v.nullable(v.string()),
  ultima_llamada_tipo: v.nullable(v.string()),
  ultima_llamada_resultado: v.nullable(v.string()),
  ultima_conversacion_en: v.nullable(v.string()),
  dias_sin_conversacion: v.number(),
  sin_conversacion: v.boolean(),
  numero_errado_detalle: v.nullable(v.string()),
  numero_errado_en: v.nullable(v.string()),
  proxima_tarea_en: v.nullable(v.string()),
  proxima_tarea_tipo: v.nullable(v.string()),
})
export type SenalCartera = v.InferOutput<typeof SenalCarteraSchema>

export const DescartadoSchema = v.object({
  actividad_id: v.string(),
  lead_id: v.string(),
  lead_nombre: v.string(),
  lead_etapa: v.string(),
  resultado: v.nullable(v.string()),
  submotivo: v.nullable(v.string()),
  motivo_descarte: v.nullable(v.string()),
  creado_en: v.string(),
  deshecho: v.boolean(),
  vigente: v.boolean(),
  no_insista: v.boolean(),
  /** El servidor exige ser el AUTOR para deshacer: false cuando miras a otro. */
  puede_deshacer: v.boolean(),
})
export type Descartado = v.InferOutput<typeof DescartadoSchema>

export const DiaAnalistaSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  dia: v.string(),
  zona: v.literal('America/Lima'),
  analista_id: v.string(),
  umbrales: UmbralesSchema,
  sin_conversacion_dias: v.number(),
  marcador: MarcadorSchema,
  compromisos: v.array(CompromisoSchema),
  compromisos_total: v.number(),
  cartera: v.array(SenalCarteraSchema),
  cartera_truncada: v.boolean(),
  descartados: v.array(DescartadoSchema),
})
export type DiaAnalista = v.InferOutput<typeof DiaAnalistaSchema>

/**
 * Los cuatro grupos del día, EN EL ORDEN QUE MANDA (decisión #2 de Miguel,
 * 19/09/2026): el lead nuevo sin primer intento va primero — el SLA corre desde
 * la asignación —, luego lo vencido, luego lo acordado para hoy y al final los
 * leads que llevan demasiados días sin una conversación real.
 */
export const GRUPOS_DIA = [
  { clave: 'primera_atencion', etiqueta: 'Sin primer intento', ayuda: 'El tiempo corre desde que te lo asignaron' },
  { clave: 'tarea_vencida', etiqueta: 'Vencidas', ayuda: 'Lo primero de lo ya comprometido' },
  { clave: 'tarea_hoy', etiqueta: 'Hoy', ayuda: 'Lo que tú mismo acordaste para hoy' },
  { clave: 'sin_conversacion', etiqueta: 'Sin conversación', ayuda: 'Nadie ha conversado con ellos en días' },
] as const
export type GrupoDia = (typeof GRUPOS_DIA)[number]['clave']
const ORDEN_GRUPO: Record<GrupoDia, number> = { primera_atencion: 0, tarea_vencida: 1, tarea_hoy: 2, sin_conversacion: 3 }

export interface FilaDiaria {
  lead_id: string
  nombre_completo: string
  etapa: string
  grupo: GrupoDia
  /** Instante que ordena dentro del grupo (vencimiento o límite); null al final. */
  referencia_en: string | null
  /** Tarea de la cola que esta fila representa, si la hay. */
  tarea_id: string | null
  severidad: 'critica' | 'media' | 'baja'
  /** Señales del lead (F3) para el detalle de la fila; puede faltar. */
  senal: SenalCartera | null
}

/** Buckets de la cola v2 que entran al día del analista, con su grupo. */
const GRUPO_DE_BUCKET: Record<string, GrupoDia> = {
  primera_atencion: 'primera_atencion',
  tarea_vencida: 'tarea_vencida',
  tarea_hoy: 'tarea_hoy',
}

/**
 * El orden del día: los tres buckets de la cola v2 que le tocan al analista más
 * el grupo `sin_conversacion`, que NO existe en la cola y lo estrena la F3
 * (`crm.politica_abandono`). Un lead aparece UNA sola vez, en su grupo más
 * urgente. Función pura: no llama a nada y no decide negocio, solo ordena.
 *
 * NO se reutiliza `seleccionarPrioridadesVendedor` (screens/hoy): aquella es el
 * TOP-3 de la franja «Ahora» sobre la cola v1 y sigue gobernando esa pantalla.
 * Lo que sí comparten es el primer ítem: el speed-to-lead manda en las dos.
 */
export function ordenarColaDiaria(
  cola: readonly ItemColaSla[],
  cartera: readonly SenalCartera[],
): FilaDiaria[] {
  const senalPorLead = new Map(cartera.map((s) => [s.lead_id, s]))
  const filas: FilaDiaria[] = []
  const vistos = new Set<string>()
  for (const item of cola) {
    const grupo = GRUPO_DE_BUCKET[item.bucket]
    if (grupo === undefined || vistos.has(item.lead_id)) continue
    vistos.add(item.lead_id)
    filas.push({
      lead_id: item.lead_id,
      nombre_completo: item.lead.nombre_completo,
      etapa: item.lead.etapa,
      grupo,
      referencia_en: item.referencia_en,
      tarea_id: item.tarea_id,
      severidad: item.severidad,
      senal: senalPorLead.get(item.lead_id) ?? null,
    })
  }
  for (const s of cartera) {
    if (!s.sin_conversacion || vistos.has(s.lead_id)) continue
    vistos.add(s.lead_id)
    filas.push({
      lead_id: s.lead_id,
      nombre_completo: s.nombre_completo,
      etapa: s.etapa,
      grupo: 'sin_conversacion',
      referencia_en: s.ultima_conversacion_en ?? s.tenencia_desde,
      tarea_id: null,
      severidad: 'media',
      senal: s,
    })
  }
  return filas.sort((a, b) => {
    const porGrupo = ORDEN_GRUPO[a.grupo] - ORDEN_GRUPO[b.grupo]
    if (porGrupo !== 0) return porGrupo
    // Dentro del grupo, lo más antiguo primero; sin referencia, al final.
    if (a.referencia_en === b.referencia_en) return a.lead_id.localeCompare(b.lead_id)
    if (a.referencia_en === null) return 1
    if (b.referencia_en === null) return -1
    return a.referencia_en.localeCompare(b.referencia_en)
  })
}

/**
 * TONO y TEXTO del tiempo de una fila. No dice «SLA»: dice el tiempo que queda
 * o el que se pasó (regla de Miguel, 20/09/2026 — «eso no lo entiendo nada»).
 *
 * `referencia_en` YA ES un vencimiento para los tres buckets de la cola v2
 * (`20260907212612_crm_sla_avisos_por_accion_y_rol.sql`: el límite de primera
 * gestión, o el `vence_en` de la tarea), así que el chip se calcula aquí, sin
 * pedirle nada nuevo al servidor. La EXCEPCIÓN es `sin_conversacion`, que esta
 * misma capa fabrica con la ÚLTIMA CONVERSACIÓN (un instante pasado que no es
 * un límite): decir ahí «se pasó hace 12 días» sería mentir, así que lleva su
 * propio texto.
 *
 * El tono `vencido` equivale exactamente a `severidad === 'critica'` en los dos
 * buckets que la producen, así que el chip DICE la severidad en palabras: por
 * eso desaparece el chip «Crítica» y no se pierde nada (regla de la casa: el
 * estado nunca viaja solo en el color).
 */
export function textoTiempoDeFila(
  fila: FilaDiaria,
  ahora: number,
): { texto: string; tono: 'vencido' | 'pendiente' | 'neutro' } {
  if (fila.grupo === 'sin_conversacion') {
    const dias = fila.senal?.dias_sin_conversacion
    if (dias === undefined) return { texto: 'Sin conversación reciente', tono: 'neutro' }
    return { texto: `Sin conversación hace ${dias} ${dias === 1 ? 'día' : 'días'}`, tono: 'neutro' }
  }
  if (fila.referencia_en === null) return { texto: 'Sin hora confirmada', tono: 'neutro' }
  const limite = Date.parse(fila.referencia_en)
  if (Number.isNaN(limite)) return { texto: 'Sin hora confirmada', tono: 'neutro' }
  const restante = limite - ahora
  // El minuto del vencimiento se dice aparte: con `Math.round` el instante
  // exacto salía como «Se pasó hace 1 min», y un milisegundo antes como
  // «Quedan 1 min». Ojo: el reloj late cada 60 s, así que el paso a «vencido»
  // puede tardar hasta un minuto en pintarse. Es aceptable y queda dicho.
  if (Math.abs(restante) < 60_000) {
    return restante > 0
      ? { texto: 'Vence en menos de 1 min', tono: 'pendiente' }
      : { texto: 'Se pasó hace menos de 1 min', tono: 'vencido' }
  }
  const cuanto = duracionLarga(Math.abs(restante))
  return restante > 0
    ? { texto: `Quedan ${cuanto}`, tono: 'pendiente' }
    : { texto: `Se pasó hace ${cuanto}`, tono: 'vencido' }
}

/** «45 min» · «1 h 20 min» · «3 días». Un solo escalón, sin «hace un momento». */
function duracionLarga(ms: number): string {
  // `floor`, no `round`: a los 59 min 30 s decir «1 h» adelanta el reloj y el
  // analista lo lee como que le queda más tiempo del que tiene.
  const minutos = Math.max(Math.floor(ms / 60_000), 1)
  if (minutos < 60) return `${minutos} min`
  if (minutos < 1440) {
    const horas = Math.floor(minutos / 60)
    const resto = minutos % 60
    return resto === 0 ? `${horas} h` : `${horas} h ${resto} min`
  }
  const dias = Math.floor(minutos / 1440)
  return `${dias} ${dias === 1 ? 'día' : 'días'}`
}

/**
 * Las CUATRO pestañas del día, incluidas las vacías: su conteo es lo que deja
 * ver el volumen de los grupos que no están a la vista (a diferencia de
 * `agruparDiaria`, que borra los vacíos porque pintaba todos los bloques).
 */
export function pestanasDiarias(
  filas: readonly FilaDiaria[],
): { clave: GrupoDia; etiqueta: string; ayuda: string; total: number; filas: FilaDiaria[] }[] {
  return GRUPOS_DIA.map((g) => {
    const suyas = filas.filter((f) => f.grupo === g.clave)
    return { clave: g.clave, etiqueta: g.etiqueta, ayuda: g.ayuda, total: suyas.length, filas: suyas }
  })
}

/**
 * Paginación de cliente dentro de un grupo. Devuelve la página ya ACOTADA: la
 * pantalla nunca guarda un número fuera de rango, así que al encoger la lista
 * (un registro que saca una fila) no se queda en una página vacía.
 */
export function paginaDeFilas(
  filas: readonly FilaDiaria[],
  pagina: number,
  porPagina: number,
): { filas: FilaDiaria[]; pagina: number; paginas: number; rango: string; total: number } {
  const total = filas.length
  const paginas = Math.max(Math.ceil(total / porPagina), 1)
  const actual = Math.min(Math.max(pagina, 0), paginas - 1)
  const desde = actual * porPagina
  const visibles = filas.slice(desde, desde + porPagina)
  const rango = total === 0 ? '0 de 0' : `${desde + 1}–${desde + visibles.length} de ${total}`
  return { filas: visibles, pagina: actual, paginas, rango, total }
}

/** Las filas agrupadas y en orden, para pintar un bloque por grupo. */
export function agruparDiaria(filas: readonly FilaDiaria[]): { grupo: GrupoDia; filas: FilaDiaria[] }[] {
  return GRUPOS_DIA
    .map((g) => ({ grupo: g.clave, filas: filas.filter((f) => f.grupo === g.clave) }))
    .filter((g) => g.filas.length > 0)
}

/** El % SIEMPRE con su conteo al lado (decisión #7 de Miguel): «60 % · 5 llamadas». */
export function textoTasa(marcador: Pick<Marcador, 'tasa_contacto_pct' | 'utiles'>): string {
  if (marcador.tasa_contacto_pct === null) return '—'
  const llamadas = marcador.utiles === 1 ? '1 llamada' : `${marcador.utiles} llamadas`
  return `${marcador.tasa_contacto_pct} % · ${llamadas}`
}

/** Etiqueta del chip de nivel; null = sin chip (menos del mínimo de útiles). */
export const ETIQUETA_NIVEL: Record<NonNullable<Marcador['nivel']>, string> = {
  bien: 'Bien',
  atencion: 'Atención',
  bajo: 'Bajo',
}


/**
 * El color de cada nivel del marcador. Verde NO (decisión #3 de Miguel): «Bien»
 * va en navy. Y «Bajo» va en ÁMBAR, no en rojo (decisión del 20/09/2026, sobre
 * el hallazgo de Codex): el rojo de esta pantalla significa UNA sola cosa, «se
 * venció». Teñir de rojo una tasa baja mezclaba el rendimiento del analista con
 * el incumplimiento de un plazo, y dejaba un chip rojo con dos significados.
 * La diferencia entre «Atención» y «Bajo» la dice el TEXTO, nunca el color.
 *
 * Son los tokens de TEXTO («-text»), no los saturados: el chip pinta el color
 * puro sobre un tinte al 12 %, donde los vivos no llegan al contraste.
 */
export const COLOR_NIVEL: Record<NonNullable<Marcador['nivel']>, string> = {
  bien: 'var(--primary)',
  atencion: 'var(--warning-text)',
  bajo: 'var(--warning-text)',
}
/**
 * Detalle de una fila en una línea, con lo que el analista necesita ANTES de
 * marcar. Sin señales del servidor no se inventa nada: se dice lo que se sabe.
 */
export function detalleDeFila(fila: FilaDiaria, sinConversacionDias: number): string {
  const s = fila.senal
  if (s === null) return fila.grupo === 'primera_atencion' ? 'Ningún intento todavía' : 'Sin señales cargadas'
  if (s.numero_errado_detalle !== null) return `Número errado: ${s.numero_errado_detalle}`
  if (fila.grupo === 'sin_conversacion') {
    return `Sin conversación hace ${s.dias_sin_conversacion} ${s.dias_sin_conversacion === 1 ? 'día' : 'días'} (el límite es ${sinConversacionDias})`
  }
  if (s.llamadas_ciclo === 0) return 'Ningún intento todavía'
  if (s.intentos_sin_respuesta > 0) {
    const n = s.intentos_sin_respuesta
    return `${n} ${n === 1 ? 'intento' : 'intentos'} sin respuesta · ${s.llamadas_ciclo} ${s.llamadas_ciclo === 1 ? 'llamada' : 'llamadas'} en el ciclo`
  }
  return `${s.llamadas_ciclo} ${s.llamadas_ciclo === 1 ? 'llamada' : 'llamadas'} en el ciclo · ya conversaron`
}

/** «10:30» Lima de un instante ISO, o «—» si no es una fecha. */
export function horaLimaDe(iso: string | null): string {
  if (iso === null) return '—'
  const ms = Date.parse(iso)
  if (!Number.isFinite(ms)) return '—'
  return new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(ms))
}

/** «Lun 21 · 10:30» Lima, para compromisos que pueden caer en otro día. */
export function cuandoLimaDe(iso: string): string {
  const ms = Date.parse(iso)
  if (!Number.isFinite(ms)) return '—'
  const fecha = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', weekday: 'short', day: 'numeric', month: 'short' }).format(new Date(ms))
  return `${fecha} · ${horaLimaDe(iso)}`
}

/** Barras de llamadas por hora 08–20 Lima (decisión #8), con el máximo para escalar. */
export const FRANJA_LLAMADAS = { desde: 8, hasta: 20 } as const

export function barrasPorHora(marcador: Pick<Marcador, 'por_hora'>): { hora: number; llamadas: number; contestadas: number; maximo: number }[] {
  const porHora = new Map(marcador.por_hora.map((h) => [h.hora, h]))
  const horas = Array.from({ length: FRANJA_LLAMADAS.hasta - FRANJA_LLAMADAS.desde + 1 }, (_, i) => i + FRANJA_LLAMADAS.desde)
  const maximo = Math.max(1, ...horas.map((h) => porHora.get(h)?.llamadas ?? 0))
  return horas.map((hora) => ({
    hora,
    llamadas: porHora.get(hora)?.llamadas ?? 0,
    contestadas: porHora.get(hora)?.contestadas ?? 0,
    maximo,
  }))
}

/** Llamadas que quedan fuera de la franja 08–20 (se declaran, no se esconden). */
export function llamadasFueraDeFranja(marcador: Pick<Marcador, 'por_hora'>): number {
  return marcador.por_hora.filter((h) => h.hora < FRANJA_LLAMADAS.desde || h.hora > FRANJA_LLAMADAS.hasta).reduce((total, h) => total + h.llamadas, 0)
}

/**
 * El tiempo de la fila EN PALABRAS: «Quedan 40 min», «Se pasó hace 45 min».
 * Regla de Miguel (20/09/2026): en pantalla no se dice «SLA» ni se muestra una
 * hora suelta que el analista tenga que restar de memoria — se dice cuánto
 * falta. `referencia_en` YA es el límite que manda en los tres buckets de la
 * cola (`cola_accion_v2_fn`: `v_primera` o el `vence_en` de la tarea).
 *
 * `sin_conversacion` NO tiene hora límite: ese grupo se mide en días, y se
 * dice así. Y si la hora no se puede leer no se inventa un reloj: si el
 * servidor marcó la fila como crítica, eso sí se dice (la severidad nunca
 * viaja solo en el color).
 */
export function tiempoDeFila(fila: FilaDiaria, ahora: number): { texto: string; vencido: boolean } {
  if (fila.grupo === 'sin_conversacion') {
    const dias = fila.senal?.dias_sin_conversacion ?? null
    if (dias === null) return { texto: 'Sin conversación', vencido: false }
    return { texto: `Sin conversación hace ${dias} ${dias === 1 ? 'día' : 'días'}`, vencido: false }
  }
  const ms = fila.referencia_en === null ? Number.NaN : Date.parse(fila.referencia_en)
  if (!Number.isFinite(ms)) {
    return fila.severidad === 'critica'
      ? { texto: 'Crítica, sin hora', vencido: true }
      : { texto: 'Sin hora límite', vencido: false }
  }
  const resta = ms - ahora
  return resta < 0
    ? { texto: `Se pasó hace ${duracionEnPalabras(-resta)}`, vencido: true }
    : { texto: `Quedan ${duracionEnPalabras(resta)}`, vencido: false }
}

/** «1 h 20 min», «40 min», «3 días». Nunca «0 min». */
function duracionEnPalabras(ms: number): string {
  const minutos = Math.floor(ms / 60_000)
  if (minutos < 1) return 'menos de 1 min'
  if (minutos < 60) return `${minutos} min`
  const horas = Math.floor(minutos / 60)
  if (horas < 24) {
    const resto = minutos % 60
    return resto === 0 ? `${horas} h` : `${horas} h ${String(resto).padStart(2, '0')} min`
  }
  const dias = Math.floor(horas / 24)
  return dias === 1 ? '1 día' : `${dias} días`
}

/**
 * El marcador del día en UNA línea, para la cabecera (decisión de Miguel,
 * 20/09/2026: el marcador es contexto, no trabajo pendiente). Respeta la
 * decisión #7: el % NUNCA va solo — lleva pegado el conteo de útiles sobre el
 * que se calcula, que no es el total de llamadas.
 */
export function resumenMarcador(dia: Pick<DiaAnalista, 'marcador' | 'umbrales'>): string {
  const m = dia.marcador
  const llamadas = m.llamadas === 1 ? '1 llamada' : `${m.llamadas} llamadas`
  const tasa = m.tasa_contacto_pct === null
    ? `sin tasa aún (desde ${dia.umbrales.minimo_llamadas_utiles} útiles)`
    : `${m.tasa_contacto_pct} % contacto (${m.utiles === 1 ? '1 útil' : `${m.utiles} útiles`})`
  const citas = m.citas_agendadas === 1 ? '1 cita' : `${m.citas_agendadas} citas`
  return `${llamadas} · ${tasa} · ${citas}`
}

// ── Espejo DEMO ─────────────────────────────────────────────────────────────
// En demo no hay servidor: el día se arma con la MISMA regla escrita, sobre el
// ámbito en memoria (que ya viene recortado por rol, espejo de la RLS). Es un
// espejo, no una segunda verdad: si la regla cambia en el servidor, cambia aquí.

interface LeadDemo { id: string; nombre_completo: string; etapa: string; activo?: boolean | undefined; vendedor_id?: string | null | undefined; creado_en: string; tenencia_desde?: string | null | undefined }
interface ActividadDemo { id: string; lead_id: string; tipo: string; detalle?: string | null | undefined; creado_en: string; autor_nombre?: string | undefined }
interface TareaDemo { id: string; lead_id: string | null; tipo: string; titulo: string; vence_en: string; estado: string; activo: boolean; creado_en: string; modalidad_reunion?: string | null | undefined }

const ABIERTAS = ['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada']
const CONVERSACION = ['llamada_realizada', 'whatsapp_recibido', 'reunion_realizada']
const LLAMADAS = ['llamada_realizada', 'llamada_no_contestada']
const DIA_MS = 86_400_000

/** El día del analista a partir del ámbito demo, con la misma forma del servidor. */
export function diaAnalistaDesdeDemo(
  analistaId: string,
  leads: readonly LeadDemo[],
  actividades: readonly ActividadDemo[],
  tareas: readonly TareaDemo[],
  ahora: number,
  diaLima: string,
  sinConversacionDias = 7,
): DiaAnalista {
  const enElDia = (iso: string) => fechaLimaDe(iso) === diaLima
  const mias = actividades.filter((a) => LLAMADAS.includes(a.tipo) && enElDia(a.creado_en))
  const contestadas = mias.filter((a) => a.tipo === 'llamada_realizada')
  const utiles = mias // el demo no tipifica el resultado: todas cuentan como útiles
  const tasa = utiles.length > 0 ? Math.round((100 * contestadas.length) / utiles.length) : null
  const umbrales = { version: 1 as const, bien_min_pct: 45, atencion_min_pct: 25, minimo_llamadas_utiles: 5 }
  const nivel = tasa === null || utiles.length < umbrales.minimo_llamadas_utiles ? null
    : tasa >= umbrales.bien_min_pct ? 'bien' as const : tasa >= umbrales.atencion_min_pct ? 'atencion' as const : 'bajo' as const
  const porHora = new Map<number, { hora: number; llamadas: number; contestadas: number }>()
  for (const a of mias) {
    const hora = Number(new Intl.DateTimeFormat('en-GB', { timeZone: 'America/Lima', hour: '2-digit', hour12: false }).format(new Date(Date.parse(a.creado_en))))
    const fila = porHora.get(hora) ?? { hora, llamadas: 0, contestadas: 0 }
    fila.llamadas += 1
    if (a.tipo === 'llamada_realizada') fila.contestadas += 1
    porHora.set(hora, fila)
  }
  const abiertos = leads.filter((l) => l.activo !== false && l.vendedor_id === analistaId && ABIERTAS.includes(l.etapa))
  const pendientes = tareas.filter((t) => t.activo && t.estado === 'pendiente')
  const cartera: SenalCartera[] = abiertos.map((l) => {
    const suyas = actividades.filter((a) => a.lead_id === l.id)
    const ultimaLlamada = ultimaDe(suyas.filter((a) => LLAMADAS.includes(a.tipo)))
    const ultimaConv = ultimaDe(suyas.filter((a) => CONVERSACION.includes(a.tipo)))
    const desde = l.tenencia_desde ?? l.creado_en
    const referencia = Math.max(ultimaConv ? Date.parse(ultimaConv.creado_en) : 0, Date.parse(desde))
    const proxima = pendientes.filter((t) => t.lead_id === l.id).sort((a, b) => a.vence_en.localeCompare(b.vence_en))[0]
    const dias = Math.max(0, Math.floor((ahora - referencia) / DIA_MS))
    return {
      lead_id: l.id,
      nombre_completo: l.nombre_completo,
      etapa: l.etapa,
      tenencia_desde: l.tenencia_desde ?? null,
      ciclo_desde: l.creado_en,
      llamadas_ciclo: suyas.filter((a) => LLAMADAS.includes(a.tipo)).length,
      intentos_sin_respuesta: suyas.filter((a) => (a.tipo === 'llamada_no_contestada' || a.tipo === 'whatsapp_enviado')
        && (ultimaConv === null || a.creado_en > ultimaConv.creado_en)).length,
      ultima_llamada_en: ultimaLlamada?.creado_en ?? null,
      ultima_llamada_tipo: ultimaLlamada?.tipo ?? null,
      ultima_llamada_resultado: null,
      ultima_conversacion_en: ultimaConv?.creado_en ?? null,
      dias_sin_conversacion: dias,
      sin_conversacion: dias > sinConversacionDias,
      numero_errado_detalle: null,
      numero_errado_en: null,
      proxima_tarea_en: proxima?.vence_en ?? null,
      proxima_tarea_tipo: proxima?.tipo ?? null,
    }
  })
  // Los compromisos empiezan MAÑANA 00:00 Lima (lo de hoy y lo vencido vive en la cola).
  const manana = Date.parse(`${diaLima}T00:00:00-05:00`) + DIA_MS
  const compromisos: Compromiso[] = pendientes
    .filter((t) => t.lead_id !== null && (t.tipo === 'llamada' || t.tipo === 'reunion') && Date.parse(t.vence_en) >= manana)
    .map((t) => ({ t, lead: leads.find((l) => l.id === t.lead_id) }))
    .filter((x): x is { t: TareaDemo; lead: LeadDemo } => x.lead !== undefined && x.lead.vendedor_id === analistaId
      && x.lead.activo !== false && ['contactado', 'reunion_agendada', 'propuesta_enviada'].includes(x.lead.etapa))
    .map(({ t, lead }) => ({
      tarea_id: t.id, lead_id: lead.id, lead_nombre: lead.nombre_completo, lead_etapa: lead.etapa,
      tipo: t.tipo as 'llamada' | 'reunion', titulo: t.titulo, vence_en: t.vence_en,
      modalidad_reunion: t.modalidad_reunion ?? null,
    }))
    .sort((a, b) => a.vence_en.localeCompare(b.vence_en) || a.tarea_id.localeCompare(b.tarea_id))
  return {
    version: 1,
    generado_en: new Date(ahora).toISOString(),
    dia: diaLima,
    zona: 'America/Lima',
    analista_id: analistaId,
    umbrales,
    sin_conversacion_dias: sinConversacionDias,
    marcador: {
      llamadas: mias.length,
      contestadas: contestadas.length,
      utiles: utiles.length,
      tasa_contacto_pct: tasa,
      nivel,
      leads_tocados: new Set(mias.map((a) => a.lead_id)).size,
      citas_agendadas: tareas.filter((t) => t.tipo === 'reunion' && enElDia(t.creado_en)
        && leads.some((l) => l.id === t.lead_id && l.vendedor_id === analistaId)).length,
      primera_llamada_en: mias.map((a) => a.creado_en).sort()[0] ?? null,
      ultima_llamada_en: mias.map((a) => a.creado_en).sort().at(-1) ?? null,
      por_resultado: mias.length > 0 ? { sin_resultado: mias.length } : {},
      por_hora: [...porHora.values()].sort((a, b) => a.hora - b.hora),
    },
    compromisos: compromisos.slice(0, 100),
    compromisos_total: compromisos.length,
    cartera: cartera.sort((a, b) => b.dias_sin_conversacion - a.dias_sin_conversacion || a.lead_id.localeCompare(b.lead_id)),
    cartera_truncada: false,
    descartados: [],
  }
}

/** Las filas del día en demo: la cola v2 no corre, así que se derivan de las señales. */
export function filasDiariasDemo(cartera: readonly SenalCartera[], ahora: number, diaLima: string): FilaDiaria[] {
  const cola: ItemColaSla[] = []
  for (const s of cartera) {
    const bucket = s.llamadas_ciclo === 0 && s.etapa === 'nuevo' ? 'primera_atencion'
      : s.proxima_tarea_en !== null && Date.parse(s.proxima_tarea_en) <= ahora ? 'tarea_vencida'
        : s.proxima_tarea_en !== null && fechaLimaDe(s.proxima_tarea_en) === diaLima ? 'tarea_hoy'
          : null
    if (bucket === null) continue
    cola.push({
      lead_id: s.lead_id, bucket, severidad: bucket === 'tarea_vencida' ? 'critica' : 'media',
      prioridad: 0, referencia_en: bucket === 'primera_atencion' ? s.tenencia_desde ?? s.ciclo_desde : s.proxima_tarea_en,
      tarea_id: null,
      lead: { id: s.lead_id, nombre_completo: s.nombre_completo, etapa: s.etapa, analista_id: null, analista_nombre: null },
    } as unknown as ItemColaSla)
  }
  return ordenarColaDiaria(cola, cartera)
}

function ultimaDe(actividades: readonly ActividadDemo[]): ActividadDemo | null {
  return actividades.reduce<ActividadDemo | null>((mejor, a) => (mejor === null || a.creado_en > mejor.creado_en ? a : mejor), null)
}

function fechaLimaDe(iso: string): string {
  const ms = Date.parse(iso)
  if (!Number.isFinite(ms)) return ''
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' }).format(new Date(ms))
}
