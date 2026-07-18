// Tests del motor de siguiente acción: alternancia de canal, cadencia D1/D3,
// ventana legal (domingo/horas) y el flag no_contactar que lo apaga.
import { describe, expect, it } from 'vitest'
import { slotHabil, sugerirSiguiente, type ContextoCierre } from './motor-siguiente'

// Viernes 2026-07-17 12:00 Lima.
const AHORA = Date.parse('2026-07-17T17:00:00Z')

const ctx = (extra: Partial<ContextoCierre>): ContextoCierre => ({
  tareaTipo: 'llamada',
  estado: 'completada',
  resultado: null,
  leadNombre: 'ANA TORRES QUISPE',
  ahora: AHORA,
  ...extra,
})

describe('sugerirSiguiente — alternancia y cadencia', () => {
  it('llamada NO contestada → WhatsApp mañana (alternancia de canal)', () => {
    const s = sugerirSiguiente(ctx({ resultado: 'llamada_no_contestada' }))
    expect(s).toMatchObject({ tipo: 'whatsapp', titulo: 'WhatsApp a Ana' })
    expect(s?.vence_en).toBe(new Date('2026-07-18T10:00:00-05:00').toISOString())
  })

  it('llamada contestada → siguiente toque en D3', () => {
    const s = sugerirSiguiente(ctx({ resultado: 'llamada_realizada' }))
    expect(s?.tipo).toBe('llamada')
    expect(s?.vence_en).toBe(new Date('2026-07-20T10:00:00-05:00').toISOString()) // D3 cae lunes (salta domingo)
  })

  it('WhatsApp enviado sin respuesta → alterna a llamada D1', () => {
    expect(sugerirSiguiente(ctx({ resultado: 'whatsapp_enviado' }))?.tipo).toBe('llamada')
  })

  it('WhatsApp RESPONDIDO → llamada caliente (+2h, dentro de ventana)', () => {
    const s = sugerirSiguiente(ctx({ resultado: 'whatsapp_recibido' }))
    expect(s?.tipo).toBe('llamada')
    expect(s?.vence_en).toBe(new Date(AHORA + 2 * 3600 * 1000).toISOString()) // 14:00 Lima, válido
  })

  it('reunión realizada → propuesta en <24h', () => {
    const s = sugerirSiguiente(ctx({ resultado: 'reunion_realizada' }))
    expect(s).toMatchObject({ tipo: 'tarea', titulo: 'Enviar propuesta a Ana' })
  })

  it('no-show de reunión → reagendar al día siguiente (recuperación temprana)', () => {
    const s = sugerirSiguiente(ctx({ tareaTipo: 'reunion', estado: 'no_show' }))
    expect(s).toMatchObject({ tipo: 'reunion', titulo: 'Reagendar con Ana' })
  })

  it('no_contactar APAGA el motor (Ley 29571) y cancelar no sugiere', () => {
    expect(sugerirSiguiente(ctx({ resultado: 'llamada_realizada', noContactar: true }))).toBeNull()
    expect(sugerirSiguiente(ctx({ estado: 'cancelada' }))).toBeNull()
  })
})

describe('slotHabil — ventana legal L–S 07:00–20:00', () => {
  it('domingo salta a lunes 10:00', () => {
    const domingo = Date.parse('2026-07-19T15:00:00Z') // domingo 10:00 Lima
    expect(slotHabil(domingo)).toBe(new Date('2026-07-20T10:00:00-05:00').toISOString())
  })

  it('antes de las 07:00 → 10:00 del mismo día; 20:00+ → siguiente día 10:00', () => {
    const madrugada = Date.parse('2026-07-17T10:00:00Z') // 05:00 Lima
    expect(slotHabil(madrugada)).toBe(new Date('2026-07-17T10:00:00-05:00').toISOString())
    const noche = Date.parse('2026-07-18T02:00:00Z') // viernes 21:00 Lima
    expect(slotHabil(noche)).toBe(new Date('2026-07-18T10:00:00-05:00').toISOString())
  })

  it('sábado noche encadena: 20h+ → domingo → lunes 10:00', () => {
    const sabadoNoche = Date.parse('2026-07-19T01:30:00Z') // sábado 20:30 Lima
    expect(slotHabil(sabadoNoche)).toBe(new Date('2026-07-20T10:00:00-05:00').toISOString())
  })
})