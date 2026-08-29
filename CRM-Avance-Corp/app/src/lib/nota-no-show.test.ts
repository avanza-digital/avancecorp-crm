// Contrato del rastro del plantón.
//
// Este texto se GRABA en `crm.actividades`, que es un log INMUTABLE: nadie
// puede editarlo después. Por eso los tests vigilan sobre todo dos cosas —
// que nunca salga vacío (la RPC convierte un detalle en blanco a NULL y el
// timeline pintaría "Nota" sin cuerpo, el mismo mudo que esto arregla) y que
// la fecha sea absoluta y en reloj de Lima, no relativa ni del navegador.
import { describe, expect, it } from 'vitest'
import { notaNoShow, PREFIJO_NO_SHOW } from './nota-no-show'

describe('notaNoShow — el plantón queda escrito en el historial', () => {
  it('nombra la reunión plantada con fecha, año y hora de Lima', () => {
    expect(notaNoShow('2026-07-24T20:00:00.000Z')).toBe('No asistió a la reunión del Vie 24 Jul 2026, 15:00')
  })

  it('el AÑO no es opcional: dentro de seis meses "Vie 24 Jul" no diría nada', () => {
    expect(notaNoShow('2026-12-31T03:00:00.000Z')).toContain('2026')
  })

  it('la nota libre del analista se conserva detrás del hecho', () => {
    expect(notaNoShow('2026-07-24T20:00:00.000Z', 'llamó a las 4 pidiendo reprogramar')).toBe(
      'No asistió a la reunión del Vie 24 Jul 2026, 15:00 — llamó a las 4 pidiendo reprogramar',
    )
  })

  it.each(['', '   ', undefined, null])('una nota vacía (%p) no deja un guion colgando', (libre) => {
    expect(notaNoShow('2026-07-24T20:00:00.000Z', libre)).toBe(
      'No asistió a la reunión del Vie 24 Jul 2026, 15:00',
    )
  })

  it('una fecha corrupta DEGRADA en vez de romper — y sigue diciendo qué pasó', () => {
    const texto = notaNoShow('no-es-fecha')
    expect(texto).toBe('No asistió a la reunión')
    expect(texto.trim()).not.toBe('')
  })

  it('JAMÁS devuelve vacío: la RPC convertiría eso en NULL y el timeline quedaría mudo', () => {
    for (const vence of ['', 'basura', '2026-07-24T20:00:00.000Z']) {
      expect(notaNoShow(vence, '   ').trim().length).toBeGreaterThan(0)
      expect(notaNoShow(vence, '   ')).toContain(PREFIJO_NO_SHOW)
    }
  })
})
