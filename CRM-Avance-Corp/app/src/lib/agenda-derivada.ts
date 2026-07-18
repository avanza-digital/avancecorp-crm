// lib/agenda-derivada.ts — de crm.tareas (datos) a EventoAgenda (display).
//
// La tabla guarda `vence_en` timestamptz; las pantallas muestran etiquetas
// humanas ("Vencida · 10:00", "Hoy · 15:30", "Mañana · 09:00", "Vie 24 Jul").
// Este módulo es la ÚNICA traducción timestamp→label: puro e inyectable
// (`ahora` en ms) para que los tests no dependan del reloj.
//
// Reglas (evidencia del plan v2):
//  * "Vencida" SE DERIVA: pendiente + vence_en < ahora. Jamás se esconde:
//    ordena PRIMERO (el sort por vence_en asc lo hace solo).
//  * El día se computa en America/Lima (UTC-5 FIJO, Perú no tiene DST).
//  * El color sale del TIPO (nada de colores por fixture).
import type { Tarea, TipoTarea } from './tipos'

/** Contrato de display de la agenda (HOY héroe + pantalla Agenda). */
export interface EventoAgenda {
  id: string
  lead_id: string
  titulo: string
  tipo: string
  /** Etiqueta humana "Día · HH:MM" — SOLO display; ordenar usa vence_en. */
  cuando: string
  color: string
  /** ISO de la tarea: la fuente de verdad para ordenar/filtrar. */
  vence_en: string
  /** Derivado: pendiente y ya pasó la hora. */
  vencida: boolean
}

const LIMA_OFFSET_MS = 5 * 3600 * 1000 // UTC-5 fijo

export const COLOR_EVENTO: Record<TipoTarea | 'vencimiento', string> = {
  llamada: '#2563eb',
  whatsapp: '#16a34a', // el verde que el vendedor ya asocia a WhatsApp (Ley de Jakob)
  reunion: '#7c3aed',
  tarea: '#64748b',
  vencimiento: '#d97706',
}

const MESES = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic']
const DIAS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb']

/** 'YYYY-MM-DD' del instante en Lima (para comparar días calendario). */
export function fechaLima(ms: number): string {
  return new Date(ms - LIMA_OFFSET_MS).toISOString().slice(0, 10)
}

/** 'HH:MM' del instante en Lima. */
function horaLima(ms: number): string {
  return new Date(ms - LIMA_OFFSET_MS).toISOString().slice(11, 16)
}

/** Etiqueta de día en Lima: Hoy / Mañana / "Vie 24 Jul". */
function etiquetaDia(ms: number, ahora: number): string {
  const dia = fechaLima(ms)
  if (dia === fechaLima(ahora)) return 'Hoy'
  if (dia === fechaLima(ahora + 86_400_000)) return 'Mañana'
  const d = new Date(ms - LIMA_OFFSET_MS)
  return `${DIAS[d.getUTCDay()]} ${d.getUTCDate()} ${MESES[d.getUTCMonth()]}`
}

/** Una tarea PENDIENTE como evento de display. */
export function tareaAEvento(t: Tarea, ahora: number): EventoAgenda {
  const ms = Date.parse(t.vence_en)
  const vencida = Number.isFinite(ms) && ms < ahora
  const dia = vencida ? 'Vencida' : etiquetaDia(ms, ahora)
  return {
    id: t.id,
    lead_id: t.lead_id ?? '',
    titulo: t.titulo,
    tipo: t.tipo,
    cuando: `${dia} · ${horaLima(ms)}`,
    color: vencida ? COLOR_EVENTO.vencimiento : COLOR_EVENTO[t.tipo],
    vence_en: t.vence_en,
    vencida,
  }
}

/**
 * Agenda derivada: SOLO tareas pendientes y activas, ordenadas por vence_en
 * ascendente — las vencidas quedan primero sin ninguna regla extra.
 */
export function agendaDeTareas(tareas: Tarea[], ahora: number): EventoAgenda[] {
  return tareas
    .filter((t) => t.estado === 'pendiente' && t.activo)
    .map((t) => tareaAEvento(t, ahora))
    .sort((a, b) => a.vence_en.localeCompare(b.vence_en))
}

/** ¿El evento cae HOY en Lima (sin contar vencidas de días previos)? */
export function esDeHoy(ev: EventoAgenda, ahora: number): boolean {
  const ms = Date.parse(ev.vence_en)
  return Number.isFinite(ms) && fechaLima(ms) === fechaLima(ahora)
}

/**
 * Enlace "Añadir a Google Calendar" (plantilla pública `render?action=TEMPLATE`):
 * abre Google con el evento prellenado — sin conexión de cuenta ni permisos.
 * Fechas en UTC (sufijo Z); `ctz` fija la vista en Lima. Sin fin conocido,
 * el bloque dura 30 min (una llamada típica; el vendedor lo ajusta en Google).
 */
export function enlaceGoogleCalendar(
  t: Pick<Tarea, 'titulo' | 'vence_en'> & Partial<Pick<Tarea, 'duracion_min' | 'nota'>>,
): string | null {
  const inicio = Date.parse(t.vence_en)
  if (!Number.isFinite(inicio)) return null
  const fin = inicio + (t.duracion_min ?? 30) * 60_000
  const compacta = (ms: number) => `${new Date(ms).toISOString().slice(0, 19).replace(/[-:]/g, '')}Z`
  const p = new URLSearchParams({
    action: 'TEMPLATE',
    text: t.titulo,
    dates: `${compacta(inicio)}/${compacta(fin)}`,
    ctz: 'America/Lima',
    details: t.nota ? `${t.nota}\n\n— CRM Avance Corp` : '— CRM Avance Corp',
  })
  return `https://calendar.google.com/calendar/render?${p.toString()}`
}

/**
 * Default de vencimiento para el quick-add: mañana a las 10:00 Lima, saltando
 * el domingo (ventana legal L–S 07:00–20:00, Ley 29571 — el motor propone
 * siempre un slot válido; el vendedor puede cambiarlo).
 */
export function proximoSlotSugerido(ahora: number): string {
  let ms = ahora + 86_400_000
  // getUTCDay sobre el reloj Lima (UTC-5): 0 = domingo.
  while (new Date(ms - LIMA_OFFSET_MS).getUTCDay() === 0) ms += 86_400_000
  const dia = fechaLima(ms)
  return new Date(`${dia}T10:00:00-05:00`).toISOString()
}