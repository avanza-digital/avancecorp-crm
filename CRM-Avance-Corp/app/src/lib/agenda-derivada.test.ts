// Tests del mapper tareas→eventos: labels en Lima, vencida derivada, orden,
// colores por tipo y el slot sugerido del quick-add. Reloj SIEMPRE inyectado.
import { describe, expect, it } from 'vitest'
import {
  agendaDeTareas,
  enlaceGoogleCalendar,
  esDeHoy,
  fechaLima,
  proximoSlotSugerido,
  tareaAEvento,
} from './agenda-derivada'
import type { Tarea } from './tipos'

// Viernes 2026-07-17 12:00 en Lima = 17:00Z (UTC-5).
const AHORA = Date.parse('2026-07-17T17:00:00Z')

const tarea = (extra: Partial<Tarea>): Tarea => ({
  id: 't1',
  lead_id: 'l1',
  tipo: 'llamada',
  titulo: 'Llamar a Ana',
  vence_en: '2026-07-17T20:00:00Z', // hoy 15:00 Lima
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: '2026-07-16T15:00:00Z',
  ...extra,
})

describe('fechaLima', () => {
  it('computa el día calendario en UTC-5 (madrugada UTC = día anterior en Lima)', () => {
    expect(fechaLima(Date.parse('2026-07-18T03:00:00Z'))).toBe('2026-07-17')
    expect(fechaLima(Date.parse('2026-07-18T06:00:00Z'))).toBe('2026-07-18')
  })
})

describe('tareaAEvento', () => {
  it('hoy → "Hoy · HH:MM" con hora Lima y color del tipo', () => {
    const ev = tareaAEvento(tarea({}), AHORA)
    expect(ev.cuando).toBe('Hoy · 15:00')
    expect(ev.vencida).toBe(false)
    expect(ev.color).toBe('#2563eb') // llamada
  })

  it('pasada → vencida, etiqueta "Vencida" y color ámbar (jamás se esconde)', () => {
    const ev = tareaAEvento(tarea({ vence_en: '2026-07-17T13:00:00Z' }), AHORA) // hoy 08:00 Lima
    expect(ev.vencida).toBe(true)
    expect(ev.cuando).toBe('Vencida · 08:00')
    expect(ev.color).toBe('#d97706')
  })

  it('mañana y días siguientes → "Mañana" / día corto', () => {
    expect(tareaAEvento(tarea({ vence_en: '2026-07-18T15:00:00Z' }), AHORA).cuando).toBe('Mañana · 10:00')
    // Lunes 20 de julio 2026, 09:00 Lima.
    expect(tareaAEvento(tarea({ vence_en: '2026-07-20T14:00:00Z' }), AHORA).cuando).toBe('Lun 20 Jul · 09:00')
  })

  it('whatsapp usa el verde que el analista ya asocia al canal', () => {
    expect(tareaAEvento(tarea({ tipo: 'whatsapp' }), AHORA).color).toBe('#16a34a')
  })
})

describe('agendaDeTareas', () => {
  it('solo pendientes activas, orden por vence_en asc → vencidas PRIMERO', () => {
    const eventos = agendaDeTareas(
      [
        tarea({ id: 'hoy', vence_en: '2026-07-17T20:00:00Z' }),
        tarea({ id: 'vencida', vence_en: '2026-07-16T20:00:00Z' }),
        tarea({ id: 'cerrada', estado: 'completada' }),
        tarea({ id: 'inactiva', activo: false }),
        tarea({ id: 'manana', vence_en: '2026-07-18T14:00:00Z' }),
      ],
      AHORA,
    )
    expect(eventos.map((e) => e.id)).toEqual(['vencida', 'hoy', 'manana'])
    expect(eventos[0]?.vencida).toBe(true)
  })
})

describe('esDeHoy', () => {
  it('día calendario Lima, sin arrastrar vencidas de días previos', () => {
    expect(esDeHoy(tareaAEvento(tarea({}), AHORA), AHORA)).toBe(true)
    expect(esDeHoy(tareaAEvento(tarea({ vence_en: '2026-07-16T20:00:00Z' }), AHORA), AHORA)).toBe(false)
  })
})

describe('enlaceGoogleCalendar', () => {
  it('arma la plantilla con inicio UTC y 30 min por defecto', () => {
    const url = new URL(enlaceGoogleCalendar(tarea({}))!)
    expect(url.origin + url.pathname).toBe('https://calendar.google.com/calendar/render')
    expect(url.searchParams.get('action')).toBe('TEMPLATE')
    expect(url.searchParams.get('text')).toBe('Llamar a Ana')
    expect(url.searchParams.get('dates')).toBe('20260717T200000Z/20260717T203000Z')
    expect(url.searchParams.get('ctz')).toBe('America/Lima')
  })

  it('respeta la duración de la tarea y lleva la nota en los detalles', () => {
    const url = new URL(enlaceGoogleCalendar(tarea({ duracion_min: 60, nota: 'Llevar cronograma' }))!)
    expect(url.searchParams.get('dates')).toBe('20260717T200000Z/20260717T210000Z')
    expect(url.searchParams.get('details')).toContain('Llevar cronograma')
  })

  it('fecha ilegible → null (el botón no se pinta, jamás un enlace roto)', () => {
    expect(enlaceGoogleCalendar(tarea({ vence_en: 'no-es-fecha' }))).toBeNull()
  })
})

describe('proximoSlotSugerido', () => {
  it('mañana 10:00 Lima; el domingo se salta (ventana legal L–S)', () => {
    // Viernes → sábado 10:00.
    expect(proximoSlotSugerido(AHORA)).toBe(new Date('2026-07-18T10:00:00-05:00').toISOString())
    // Sábado → el domingo se salta → lunes 10:00.
    const sabado = Date.parse('2026-07-18T17:00:00Z')
    expect(proximoSlotSugerido(sabado)).toBe(new Date('2026-07-20T10:00:00-05:00').toISOString())
  })
})
