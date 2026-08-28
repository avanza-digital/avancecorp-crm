import { describe, expect, it } from 'vitest'
import { enlaceGoogleCalendar } from './agenda-derivada'

describe('calendario de reuniones', () => {
  it('lleva ubicación y modalidad presencial a Google Calendar', () => {
    const enlace = enlaceGoogleCalendar({
      titulo: 'Reunión con cliente',
      vence_en: '2026-08-06T15:00:00.000Z',
      modalidad_reunion: 'presencial',
      ubicacion_reunion: 'Av. Arequipa 123, Lima',
    })
    expect(enlace).not.toBeNull()
    const url = new URL(enlace!)
    expect(url.searchParams.get('location')).toBe('Av. Arequipa 123, Lima')
    expect(url.searchParams.get('text')).toBe('Cita con cliente')
    expect(url.searchParams.get('details')).toContain('Modalidad: Presencial')
  })

  it('lleva el enlace de una reunión virtual', () => {
    const enlace = enlaceGoogleCalendar({
      titulo: 'Reunión virtual',
      vence_en: '2026-08-06T15:00:00.000Z',
      modalidad_reunion: 'virtual',
      enlace_reunion: 'https://meet.google.com/abc-defg-hij',
    })
    const url = new URL(enlace!)
    expect(url.searchParams.get('text')).toBe('Cita virtual')
    expect(url.searchParams.get('location')).toBe('https://meet.google.com/abc-defg-hij')
    expect(url.searchParams.get('details')).toContain('Modalidad: Virtual')
  })
})
