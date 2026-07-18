// lib/agenda-vistas.ts — Fase D de la agenda: geometría de calendario
// (Semana/Mes), filtros de la pantalla Agenda y el modo "viernes 13:00"
// (higiene de pipeline). Todo PURO e inyectable (`ahora` en epoch ms), igual
// que agenda-derivada: la zona es America/Lima (UTC-5 FIJO, sin DST) y los
// tests no dependen del reloj.
//
// Evidencia que gobierna este módulo (plan v2, investigación 2026-07-18):
//  * Citas rinden más mar–jue con DOS picos (10–11:30 y 16–18h; Gong: +30%
//    de asistencia a las 4pm) — la vista Semana lo SUGIERE en los huecos,
//    nunca lo impone.
//  * Viernes p.m. es el peor momento para citas en todos los datasets → desde
//    las 13:00 la cola deja de perseguir y pasa a ORDENAR la próxima semana:
//    vencidas, reagendas de no-show fuera de ritmo y leads sin próxima acción.
//  * Domingo queda fuera de la ventana legal de contacto (L–S 07:00–20:00,
//    Ley 29571) — el calendario lo atenúa.
import { DIAS, LIMA_OFFSET_MS, MESES, fechaLima } from './agenda-derivada'
import { normalizar } from './clientes-vista'
import { DIA_MS, sinProximaAccion } from './inteligencia'
import type { EtapaActiva, Lead, Tarea, TipoTarea } from './tipos'

const MESES_LARGOS = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
]

/** Epoch (ms) de las 00:00 en Lima del día que contiene `ms`. */
function inicioDiaLima(ms: number): number {
  const enLima = ms - LIMA_OFFSET_MS
  return enLima - (enLima % DIA_MS) + LIMA_OFFSET_MS
}

/** Día de semana en Lima (0=Dom … 6=Sáb) del instante `ms`. */
function dowLima(ms: number): number {
  return new Date(ms - LIMA_OFFSET_MS).getUTCDay()
}

// ── Semana ────────────────────────────────────────────────────────────────────

/** Un día calendario (Lima) de las vistas Semana/Mes. */
export interface DiaAgenda {
  /** 'YYYY-MM-DD' en Lima — la clave para agrupar tareas. */
  fecha: string
  /** Epoch de las 00:00 Lima de ese día. */
  ms: number
  /** Día del mes (1–31). */
  num: number
  /** 0=Dom … 6=Sáb (Lima). */
  dow: number
  /** "Lun 21" — encabezado de columna. */
  label: string
  esHoy: boolean
  /** Franja de mayor asistencia a citas (mar–jue) — para el hint de ritmo. */
  esMarJue: boolean
  /** Día calendario anterior a hoy (los hints no aplican al pasado). */
  esPasado: boolean
}

function diaDe(ms0: number, ahora: number): DiaAgenda {
  const d = new Date(ms0 - LIMA_OFFSET_MS)
  const dow = d.getUTCDay()
  const fecha = fechaLima(ms0)
  return {
    fecha,
    ms: ms0,
    num: d.getUTCDate(),
    dow,
    label: `${DIAS[dow]} ${d.getUTCDate()}`,
    esHoy: fecha === fechaLima(ahora),
    esMarJue: dow >= 2 && dow <= 4,
    esPasado: fecha < fechaLima(ahora),
  }
}

/** Epoch de las 00:00 Lima del LUNES de la semana de `ahora` ± offset semanas. */
export function lunesDeSemana(ahora: number, offsetSemanas = 0): number {
  const hoy0 = inicioDiaLima(ahora)
  const desdeLunes = (dowLima(hoy0) + 6) % 7 // 0 = lunes
  return hoy0 - desdeLunes * DIA_MS + offsetSemanas * 7 * DIA_MS
}

/** Los 7 días (Lun→Dom, Lima) de la semana de `ahora` ± offset. */
export function diasDeSemana(ahora: number, offsetSemanas = 0): DiaAgenda[] {
  const lunes = lunesDeSemana(ahora, offsetSemanas)
  return Array.from({ length: 7 }, (_, i) => diaDe(lunes + i * DIA_MS, ahora))
}

/** "13 – 19 Jul" (o "29 Jun – 5 Jul" si la semana cruza de mes). */
export function tituloSemana(dias: DiaAgenda[]): string {
  const a = dias[0]
  const b = dias[dias.length - 1]
  if (!a || !b) return ''
  const mesA = MESES[new Date(a.ms - LIMA_OFFSET_MS).getUTCMonth()]
  const mesB = MESES[new Date(b.ms - LIMA_OFFSET_MS).getUTCMonth()]
  return mesA === mesB ? `${a.num} – ${b.num} ${mesB}` : `${a.num} ${mesA} – ${b.num} ${mesB}`
}

// ── Mes ───────────────────────────────────────────────────────────────────────

export interface CeldaMes extends DiaAgenda {
  /** false = relleno de la semana que pertenece al mes vecino (se atenúa). */
  delMes: boolean
}

/**
 * Rejilla del mes de `ahora` ± offset meses: semanas completas Lun→Dom (las
 * puntas traen días del mes vecino con `delMes: false`), 4–6 filas según mes.
 */
export function rejillaMes(ahora: number, offsetMeses = 0): { titulo: string; semanas: CeldaMes[][] } {
  const hoy = new Date(inicioDiaLima(ahora) - LIMA_OFFSET_MS)
  // Día 1 del mes destino, a las 00:00 Lima (Date.UTC normaliza el offset).
  const dia1 = Date.UTC(hoy.getUTCFullYear(), hoy.getUTCMonth() + offsetMeses, 1) + LIMA_OFFSET_MS
  const d1 = new Date(dia1 - LIMA_OFFSET_MS)
  const mes = d1.getUTCMonth()
  let cursor = dia1 - (((d1.getUTCDay() + 6) % 7) * DIA_MS) // lunes de la semana del día 1
  const semanas: CeldaMes[][] = []
  do {
    const fila: CeldaMes[] = []
    for (let i = 0; i < 7; i++) {
      fila.push({ ...diaDe(cursor, ahora), delMes: new Date(cursor - LIMA_OFFSET_MS).getUTCMonth() === mes })
      cursor += DIA_MS
    }
    semanas.push(fila)
  } while (new Date(cursor - LIMA_OFFSET_MS).getUTCMonth() === mes)
  return { titulo: `${MESES_LARGOS[mes]} ${d1.getUTCFullYear()}`, semanas }
}

/**
 * Tareas agrupadas por día calendario Lima de su `vence_en`. Conserva el orden
 * de entrada (las pantallas ya ordenan por vence_en asc → cada grupo queda
 * cronológico solo).
 */
export function tareasPorDia(tareas: Tarea[]): ReadonlyMap<string, Tarea[]> {
  const out = new Map<string, Tarea[]>()
  for (const t of tareas) {
    const ms = Date.parse(t.vence_en)
    if (!Number.isFinite(ms)) continue
    const dia = fechaLima(ms)
    const grupo = out.get(dia)
    if (grupo) grupo.push(t)
    else out.set(dia, [t])
  }
  return out
}

// ── Filtros de la pantalla Agenda ─────────────────────────────────────────────

export interface FiltrosAgenda {
  /** Texto libre contra título, nota y nombre del lead (sin acentos). */
  q: string
  tipo: TipoTarea | 'todos'
  /** Estados DERIVADOS sobre pendientes (las cerradas no viajan al cliente). */
  estado: 'todas' | 'vencida' | 'sin_confirmar' | 'confirmada'
  /** Etapa del LEAD de la tarea. */
  etapa: EtapaActiva | 'todas'
}

export const FILTROS_APAGADOS: FiltrosAgenda = { q: '', tipo: 'todos', estado: 'todas', etapa: 'todas' }

export function hayFiltros(f: FiltrosAgenda): boolean {
  return f.q.trim() !== '' || f.tipo !== 'todos' || f.estado !== 'todas' || f.etapa !== 'todas'
}

/**
 * Aplica los filtros sobre tareas PENDIENTES. `sin_confirmar` refiere a
 * reuniones futuras sin `confirmada_en` (el hueco del anti no-show);
 * `vencida` es la derivada de siempre (pendiente + vence_en < ahora).
 */
export function aplicarFiltros(
  tareas: Tarea[],
  f: FiltrosAgenda,
  ahora: number,
  leadDe: (id: string | null) => Lead | undefined,
): Tarea[] {
  const q = normalizar(f.q.trim())
  return tareas.filter((t) => {
    if (f.tipo !== 'todos' && t.tipo !== f.tipo) return false
    if (f.estado !== 'todas') {
      const vencida = Date.parse(t.vence_en) < ahora
      if (f.estado === 'vencida' && !vencida) return false
      if (f.estado === 'confirmada' && t.confirmada_en == null) return false
      if (f.estado === 'sin_confirmar' && (t.tipo !== 'reunion' || t.confirmada_en != null || vencida)) return false
    }
    const lead = f.etapa !== 'todas' || q ? leadDe(t.lead_id) : undefined
    if (f.etapa !== 'todas' && lead?.etapa !== f.etapa) return false
    if (q && !normalizar(`${t.titulo} ${t.nota ?? ''} ${lead?.nombre_completo ?? ''}`).includes(q)) return false
    return true
  })
}

// ── Modo "viernes 13:00" — higiene de pipeline ────────────────────────────────

/**
 * Viernes desde las 13:00 en Lima: el peor momento para citas nuevas y el
 * mejor para ordenar la próxima semana. La cola de HOY cambia de perseguir
 * a hacer higiene.
 */
export function esViernesDeHigiene(ahora: number): boolean {
  const d = new Date(ahora - LIMA_OFFSET_MS)
  return d.getUTCDay() === 5 && d.getUTCHours() >= 13
}

/**
 * Siguiente día mar–jue a las 10:00 Lima, empezando MAÑANA — el default para
 * reubicar reagendas de no-show en la franja que sí asiste (desde viernes o
 * fin de semana cae siempre en martes).
 */
export function siguienteMarJue(ahora: number): string {
  let ms = inicioDiaLima(ahora) + DIA_MS
  while (dowLima(ms) < 2 || dowLima(ms) > 4) ms += DIA_MS
  return new Date(ms + 10 * 3_600_000).toISOString()
}

/** Ítem de la cola de higiene del viernes (cada uno con su acción obvia). */
export type ItemHigiene =
  | { k: 'vencida'; tarea: Tarea } // cerrar o reprogramar — nunca se esconde
  | { k: 'no_show_fuera_ritmo'; tarea: Tarea } // reagenda de no-show fuera de mar–jue → moverla
  | { k: 'sin_accion'; lead: Lead } // amarillo: lead abierto sin próxima acción → agendarle una

/**
 * La cola del modo viernes: vencidas (cronológicas) → reagendas de no-show
 * caídas fuera de mar–jue (la evidencia de recuperación pide reubicarlas) →
 * leads sin próxima acción (orden de sinProximaAccion: capital PEN desc,
 * luego USD — jamás mezclados). El speed-to-lead NO viene aquí: esos ítems
 * saltan cualquier cola y la pantalla los mantiene arriba.
 */
export function colaHigiene(
  tareas: Tarea[],
  leads: Lead[],
  conTareaPendiente: ReadonlySet<string>,
  ahora: number,
): ItemHigiene[] {
  const pendientes = [...tareas]
    .filter((t) => t.estado === 'pendiente' && t.activo)
    .sort((a, b) => a.vence_en.localeCompare(b.vence_en))
  const items: ItemHigiene[] = []
  for (const t of pendientes) {
    if (Date.parse(t.vence_en) < ahora) items.push({ k: 'vencida', tarea: t })
  }
  for (const t of pendientes) {
    if (t.reagendada_de == null) continue
    const ms = Date.parse(t.vence_en)
    if (!Number.isFinite(ms) || ms < ahora) continue // las vencidas ya están arriba
    const dow = dowLima(ms)
    if (dow < 2 || dow > 4) items.push({ k: 'no_show_fuera_ritmo', tarea: t })
  }
  for (const lead of sinProximaAccion(leads, conTareaPendiente)) items.push({ k: 'sin_accion', lead })
  return items
}
