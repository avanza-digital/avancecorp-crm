// Tests del recordatorio anti no-show: pide confirmación, ancla el capital,
// viaja por wa.me, y solo se ofrece cuando todavía salva el slot.
import { describe, expect, it } from 'vitest'
import { ameritaRecordatorio, enlaceRecordatorio, mensajeRecordatorio } from './recordatorio'
import type { Lead, Tarea } from './tipos'

const AHORA = Date.parse('2026-07-17T17:00:00Z') // viernes 12:00 Lima

const LEAD = {
  id: 'l1',
  nombre_completo: 'ANA TORRES QUISPE',
  telefono: '+51999888777',
  etapa: 'reunion_agendada',
  origen: 'oficina',
  monto_estimado: 50_000,
  moneda: 'PEN',
  creado_en: '2026-07-10T15:00:00.000Z',
  activo: true,
} as Lead

const cita = (extra: Partial<Tarea>): Tarea => ({
  id: 't1',
  lead_id: 'l1',
  tipo: 'reunion',
  titulo: 'Reunión con Ana',
  vence_en: '2026-07-17T21:00:00Z', // hoy 16:00 Lima
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: '2026-07-16T15:00:00.000Z',
  ...extra,
})

describe('mensajeRecordatorio', () => {
  it('pide confirmación explícita y ancla el capital del lead (RCT −32%)', () => {
    const msg = mensajeRecordatorio(cita({}), LEAD, AHORA)
    expect(msg).toContain('¿Confirmamos nuestra reunión de hoy a las 16:00?')
    expect(msg).toContain('tu inversión de S/ 50,000')
    expect(msg).toContain('Hola Ana')
    expect(msg).toContain('lo movemos') // salida fácil: mover > no-show silencioso
  })
})

describe('enlaceRecordatorio', () => {
  it('wa.me con dígitos E.164 y el texto urlencoded', () => {
    const url = enlaceRecordatorio(cita({}), LEAD, AHORA)
    expect(url).toMatch(/^https:\/\/wa\.me\/51999888777\?text=/)
    expect(decodeURIComponent(url ?? '')).toContain('¿Confirmamos')
  })

  it('sin teléfono utilizable → null (jamás un enlace roto)', () => {
    expect(enlaceRecordatorio(cita({}), { ...LEAD, telefono: '' } as Lead, AHORA)).toBeNull()
  })
})

describe('ameritaRecordatorio', () => {
  it('reunión pendiente de hoy/mañana sin confirmar → sí', () => {
    expect(ameritaRecordatorio(cita({}), AHORA)).toBe(true)
    expect(ameritaRecordatorio(cita({ vence_en: '2026-07-18T15:00:00Z' }), AHORA)).toBe(true) // mañana
  })

  it('confirmada, vencida, lejana o de otro tipo → no', () => {
    expect(ameritaRecordatorio(cita({ confirmada_en: '2026-07-17T10:00:00Z' }), AHORA)).toBe(false)
    expect(ameritaRecordatorio(cita({ vence_en: '2026-07-17T13:00:00Z' }), AHORA)).toBe(false) // ya vencida
    expect(ameritaRecordatorio(cita({ vence_en: '2026-07-22T15:00:00Z' }), AHORA)).toBe(false) // martes
    expect(ameritaRecordatorio(cita({ tipo: 'llamada' }), AHORA)).toBe(false)
  })
})