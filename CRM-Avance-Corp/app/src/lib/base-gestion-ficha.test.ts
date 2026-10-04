// La ficha del lead de la base (F2): lo que la pantalla valida antes de enviar (la puerta vuelve a validar y manda),
// cómo se lee cada fila del historial y el buscador que lo filtra.
import { describe, expect, it } from 'vitest'
import type { Actividad } from './tipos'
import { etiquetaActividadBase, filtrarHistorial, firmaIntento, validarRellamada } from './base-gestion'

// Viernes 2 de octubre de 2026, 12:00 en Lima (17:00 UTC).
const AHORA = Date.parse('2026-10-02T17:00:00Z')

function act(sobre: Partial<Actividad>): Actividad {
  return { id: 'a', lead_id: 'l', tipo: 'nota', detalle: null, autor_nombre: 'ANA PÉREZ', creado_en: '2026-10-01T15:00:00Z', ...sobre }
}

describe('validarRellamada', () => {
  it('vacía (o un input vaciado a mano) no es un instante: pide fecha y hora', () => {
    expect(validarRellamada('', '', AHORA)).toEqual({ error: 'Elige la fecha y la hora de la próxima llamada.' })
    expect(validarRellamada('2026-10-03', '', AHORA)).toEqual({ error: 'Elige la fecha y la hora de la próxima llamada.' })
  })
  it('en el pasado o ahora mismo, no', () => {
    expect(validarRellamada('2026-10-02', '11:59', AHORA)).toEqual({ error: 'La próxima llamada tiene que ser más adelante que ahora.' })
  })
  it('más allá de 10 días, no', () => {
    expect(validarRellamada('2026-10-12', '12:01', AHORA)).toEqual({ error: 'La próxima llamada puede agendarse como máximo a 10 días.' })
  })
  it('dentro de la ventana: el instante es hora de LIMA (-05:00) en ISO', () => {
    expect(validarRellamada('2026-10-03', '10:30', AHORA)).toEqual({ iso: '2026-10-03T15:30:00.000Z' })
    expect(validarRellamada('2026-10-12', '12:00', AHORA)).toEqual({ iso: '2026-10-12T17:00:00.000Z' })
  })
})

describe('firmaIntento', () => {
  it('el mismo contenido da la misma firma (la nota sin espacios de más); otro contenido, otra', () => {
    const base = { resultado: 'no_contesto', nota: 'sin respuesta', proximaLlamada: null }
    expect(firmaIntento(base)).toBe(firmaIntento({ ...base, nota: '  sin respuesta ' }))
    expect(firmaIntento(base)).not.toBe(firmaIntento({ ...base, resultado: 'numero_errado' }))
    expect(firmaIntento(base)).not.toBe(firmaIntento({ ...base, nota: 'otra' }))
    expect(firmaIntento({ ...base, resultado: 'volver_a_llamar', proximaLlamada: 'a' })).not.toBe(firmaIntento({ ...base, resultado: 'volver_a_llamar', proximaLlamada: 'b' }))
  })
})

describe('etiquetaActividadBase', () => {
  it('un intento de la base dice su número y su resultado', () => {
    expect(etiquetaActividadBase(act({ tipo: 'llamada_no_contestada', metadata: { evento: 'intento_base', intento_n: 2, resultado: 'no_contesto' } }))).toBe('Intento 2 · No contestó')
    expect(etiquetaActividadBase(act({ tipo: 'llamada_realizada', metadata: { evento: 'intento_base', intento_n: '3', resultado: 'volver_a_llamar' } }))).toBe('Intento 3 · Volver a llamar')
  })
  it('la reactivación y el resto se leen por lo que fueron', () => {
    expect(etiquetaActividadBase(act({ metadata: { evento: 'reactivacion_base' } }))).toBe('Reactivado desde la base')
    expect(etiquetaActividadBase(act({ tipo: 'reasignacion' }))).toBe('Reasignación')
  })
  it('«No contactar» (una nota con evento) dice si se marcó o se levantó, no «Nota»', () => {
    expect(etiquetaActividadBase(act({ metadata: { evento: 'no_contactar', accion: 'marcar', motivo: 'Lo pidió' } }))).toBe('Marcado «No contactar»')
    expect(etiquetaActividadBase(act({ metadata: { evento: 'no_contactar', accion: 'levantar', rol: 'supervisor' } }))).toBe('Levantado «No contactar»')
    // Sin `accion` no se adivina cuál fue: se dice solo qué evento es.
    expect(etiquetaActividadBase(act({ metadata: { evento: 'no_contactar' } }))).toBe('No contactar')
    expect(etiquetaActividadBase(act({ detalle: 'Marcado como No contactar' }))).toBe('Nota')
  })
  it('el buscador encuentra el «No contactar» por lo que el analista lee', () => {
    const items = [act({ id: 'nc', metadata: { evento: 'no_contactar', accion: 'levantar' } }), act({ id: 'n' })]
    expect(filtrarHistorial(items, 'no contactar').map((a) => a.id)).toEqual(['nc'])
    expect(filtrarHistorial(items, 'LEVANTADO').map((a) => a.id)).toEqual(['nc'])
  })
})

describe('filtrarHistorial', () => {
  const items = [
    act({ id: '1', detalle: 'Pidió que lo llamen después del almuerzo', autor_nombre: 'ANA PÉREZ' }),
    act({ id: '2', tipo: 'reasignacion', detalle: 'LUIS → ANA PÉREZ', autor_nombre: 'CARMEN' }),
    act({ id: '3', tipo: 'llamada_no_contestada', metadata: { evento: 'intento_base', intento_n: 1, resultado: 'no_contesto' }, autor_nombre: 'ANA PÉREZ' }),
  ]
  it('sin texto devuelve todo, en el mismo orden', () => {
    expect(filtrarHistorial(items, '  ').map((a) => a.id)).toEqual(['1', '2', '3'])
  })
  it('sin mayúsculas ni tildes, sobre la nota, quién y qué pasó', () => {
    expect(filtrarHistorial(items, 'ALMUERZO').map((a) => a.id)).toEqual(['1'])
    expect(filtrarHistorial(items, 'perez').map((a) => a.id)).toEqual(['1', '2', '3'])
    expect(filtrarHistorial(items, 'no contesto').map((a) => a.id)).toEqual(['3'])
    expect(filtrarHistorial(items, 'reasignacion').map((a) => a.id)).toEqual(['2'])
    expect(filtrarHistorial(items, 'xyz')).toEqual([])
  })
})
