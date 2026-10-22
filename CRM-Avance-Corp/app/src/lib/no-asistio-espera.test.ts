// Contrato del espejo de «No asistió espera a la hora de la cita».
//
// Lo que vigilan estos tests es el BORDE: el servidor rechaza mientras
// `vence_en > reloj` y acepta desde el instante de la hora. Si la pantalla usara
// otro criterio, ofrecería lo que el servidor rechaza —o escondería lo que ya
// acepta— justo en el minuto en que el analista está mirando el reloj.
import { describe, expect, it } from 'vitest'
import { noAsistioEsperaHora } from './no-asistio-espera'

const HORA = '2026-10-06T22:00:00.000Z' // 17:00 en Lima
const MS = Date.parse(HORA)
const REUNION = { tipo: 'reunion', vence_en: HORA } as const

describe('noAsistioEsperaHora — «No asistió» espera a la hora pactada', () => {
  it('antes de la hora, espera', () => {
    expect(noAsistioEsperaHora(REUNION, MS - 3 * 3_600_000)).toBe(true)
  })

  it('un milisegundo antes todavía espera', () => {
    expect(noAsistioEsperaHora(REUNION, MS - 1)).toBe(true)
  })

  it('en el instante exacto de la hora ya no espera (mismo borde que el servidor)', () => {
    expect(noAsistioEsperaHora(REUNION, MS)).toBe(false)
  })

  it('pasada la hora no espera', () => {
    expect(noAsistioEsperaHora(REUNION, MS + 1)).toBe(false)
    expect(noAsistioEsperaHora(REUNION, MS + 86_400_000)).toBe(false)
  })

  it.each(['llamada', 'whatsapp', 'tarea'] as const)('una %s no espera nunca: la regla es solo de reuniones', (tipo) => {
    expect(noAsistioEsperaHora({ tipo, vence_en: HORA }, MS - 3_600_000)).toBe(false)
  })

  it('una hora ilegible no bloquea la pantalla: decide el servidor', () => {
    expect(noAsistioEsperaHora({ tipo: 'reunion', vence_en: 'no-es-una-fecha' }, MS)).toBe(false)
  })
})
