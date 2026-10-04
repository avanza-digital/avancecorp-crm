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
import { ETAPA_INFO, MOTIVOS_DESCARTE, TIPOS_ACTIVIDAD, origenLabel, type Actividad, type Lead } from './tipos'

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
})
export type FilaBaseGestion = v.InferOutput<typeof FilaBaseGestionSchema>

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

export type DimensionFiltro = 'mes' | 'motivo' | 'etapa' | 'resultado'
const DIMENSIONES: readonly DimensionFiltro[] = ['mes', 'motivo', 'etapa', 'resultado']

export interface FiltrosBase {
  mes: string
  motivo: string
  etapa: string
  resultado: string
  /** Solo los que tienen una rellamada agendada para otro día (la pastilla «Rellamadas agendadas» se abre así). */
  agendadas: boolean
}

export const SIN_FILTROS: FiltrosBase = { mes: FILTRO_TODOS, motivo: FILTRO_TODOS, etapa: FILTRO_TODOS, resultado: FILTRO_TODOS, agendadas: false }

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
    const opciones = [...conteo.entries()].map(([clave, leads]) => ({ clave, etiqueta: etiquetaOpcion(dimension, clave), leads }))
    return { total, opciones: ordenarOpciones(dimension, opciones) }
  }
  return { mes: faceta('mes'), motivo: faceta('motivo'), etapa: faceta('etapa'), resultado: faceta('resultado') }
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

