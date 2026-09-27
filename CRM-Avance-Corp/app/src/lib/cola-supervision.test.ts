import { describe, expect, it } from 'vitest'
import { estadoCasoSupervision, momentoCaso, nombresCortos } from './cola-supervision'

const AHORA = Date.parse('2026-09-27T15:00:00Z')

describe('estadoCasoSupervision', () => {
  it('nombra el ESTADO del caso, no la orden al analista', () => {
    expect(estadoCasoSupervision('primera_atencion')).toBe('Primera gestión pendiente')
    expect(estadoCasoSupervision('tarea_vencida')).toBe('Actividad vencida')
    expect(estadoCasoSupervision('por_repartir')).toBe('Sin analista asignado')
  })

  it('un bucket desconocido no rompe la fila', () => {
    expect(estadoCasoSupervision('algo_nuevo')).toBe('Revisar oportunidad')
  })
})

describe('momentoCaso', () => {
  it('en un bucket con PLAZO pasado dice cuánto hace que venció', () => {
    expect(momentoCaso('primera_atencion', '2026-09-25T15:00:00Z', AHORA)).toBe('venció hace 2 días')
    expect(momentoCaso('tarea_vencida', '2026-09-27T12:00:00Z', AHORA)).toBe('venció hace 3 horas')
  })

  it('con el plazo por delante dice cuánto falta', () => {
    expect(momentoCaso('seguimiento', '2026-09-27T18:30:00Z', AHORA)).toBe('vence en 3 horas')
  })

  it('en un bucket SIN plazo la fecha es el inicio del caso', () => {
    expect(momentoCaso('por_repartir', '2026-09-24T15:00:00Z', AHORA)).toBe('desde hace 3 días')
    expect(momentoCaso('revision_comercial', '2026-09-27T14:20:00Z', AHORA)).toBe('desde hace 40 minutos')
  })

  it('sin fecha (null o ilegible) lo dice en vez de inventar un tiempo', () => {
    expect(momentoCaso('primera_atencion', null, AHORA)).toBe('sin fecha confirmada')
    expect(momentoCaso('seguimiento', 'no-es-fecha', AHORA)).toBe('sin fecha confirmada')
  })
})

describe('nombresCortos', () => {
  it('primer nombre cuando no se repite', () => {
    expect([...nombresCortos(['KAREN ZAPATA', 'JORGE HUAMÁN']).values()]).toEqual(['Karen', 'Jorge'])
  })

  it('si dos comparten el primer nombre, los distingue con la inicial del apellido', () => {
    const m = nombresCortos(['KAREN ZAPATA', 'KAREN LÓPEZ', 'JORGE HUAMÁN', 'KAREN ZAPATA'])
    expect(m.get('KAREN ZAPATA')).toBe('Karen Z.')
    expect(m.get('KAREN LÓPEZ')).toBe('Karen L.')
    expect(m.get('JORGE HUAMÁN')).toBe('Jorge')
  })
})
