// Textos y espejo demo de la base para gestión: lo que el analista lee en cada fila tiene que decir lo
// mismo que el servidor decidió (días calendario de Lima, tope de intentos, rellamada vencida o de hoy).
import { describe, expect, it } from 'vitest'
import type { Lead } from './tipos'
import {
  estadoRellamada,
  etiquetaDiasDescarte,
  etiquetaEtapaMaxima,
  etiquetaIntentos,
  etiquetaMomento,
  etiquetaMotivoDescarte,
  etiquetaRellamada,
  etiquetaUltimoResultado,
  filasDemoBaseGestion,
} from './base-gestion'

// Viernes 2 de octubre de 2026, 20:00 en Lima (01:00 UTC del sábado 3): la hora en que el UTC ya es «mañana».
const AHORA = Date.parse('2026-10-03T01:00:00Z')

describe('rellamada en días de Lima', () => {
  it('es de HOY aunque en UTC ya sea el día siguiente', () => {
    expect(estadoRellamada('2026-10-03T02:30:00Z', AHORA)).toBe('hoy') // 21:30 del viernes en Lima
    expect(etiquetaRellamada('2026-10-03T02:30:00Z', AHORA)).toBe('Hoy, 21:30')
  })

  it('marca la vencida con su fecha y la de mañana como «Mañana»', () => {
    expect(estadoRellamada('2026-10-01T15:00:00Z', AHORA)).toBe('vencida')
    expect(etiquetaRellamada('2026-10-01T15:00:00Z', AHORA)).toBe('Vencida: Jue 1 Oct, 10:00')
    expect(etiquetaRellamada('2026-10-03T15:00:00Z', AHORA)).toBe('Mañana, 10:00')
    expect(etiquetaRellamada('2026-10-08T15:00:00Z', AHORA)).toBe('Jue 8 Oct, 10:00')
  })

  it('no inventa una fecha si el servidor manda algo ilegible', () => {
    expect(etiquetaRellamada('no-es-fecha', AHORA)).toBe('Sin fecha')
    expect(etiquetaMomento('no-es-fecha', AHORA)).toBe('Sin fecha')
  })
})

describe('textos de la fila', () => {
  it('cuenta intentos contra el tope y deja pasar los que la rellamada permitió (D12)', () => {
    expect(etiquetaIntentos(0)).toBe('0 de 3')
    expect(etiquetaIntentos(3)).toBe('3 de 3')
    expect(etiquetaIntentos(4)).toBe('4 intentos')
  })

  it('dice los días desde el descarte como se hablan', () => {
    expect(etiquetaDiasDescarte(0)).toBe('Hoy')
    expect(etiquetaDiasDescarte(1)).toBe('Ayer')
    expect(etiquetaDiasDescarte(12)).toBe('Hace 12 días')
    expect(etiquetaDiasDescarte(null)).toBe('Sin fecha')
  })

  it('nombra la etapa máxima, el motivo y el resultado con los rótulos del CRM', () => {
    expect(etiquetaEtapaMaxima('reunion_agendada')).toBe('Cita agendada')
    expect(etiquetaEtapaMaxima('propuesta_enviada')).toBe('Entrevista realizada')
    expect(etiquetaEtapaMaxima('sin_datos')).toBe('Sin historial')
    expect(etiquetaMotivoDescarte('sin_fondos')).toBe('Sin fondos')
    expect(etiquetaMotivoDescarte('motivo_nuevo')).toBe('motivo_nuevo')
    expect(etiquetaMotivoDescarte(null)).toBe('Sin motivo')
    expect(etiquetaUltimoResultado('no_contesto')).toBe('No contestó')
    expect(etiquetaUltimoResultado('volver_a_llamar')).toBe('Volver a llamar')
    expect(etiquetaUltimoResultado(null)).toBe('Sin intentos')
  })

  it('fecha el último intento en Lima: hoy, ayer o el día', () => {
    expect(etiquetaMomento('2026-10-02T23:15:00Z', AHORA)).toBe('Hoy, 18:15')
    expect(etiquetaMomento('2026-10-01T14:00:00Z', AHORA)).toBe('Ayer, 09:00')
    expect(etiquetaMomento('2026-09-28T14:00:00Z', AHORA)).toBe('Lun 28 Sep, 09:00')
  })
})

describe('espejo demo', () => {
  const lead = (sobre: Partial<Lead>): Lead => ({
    id: 'l1', nombre_completo: 'ANA DEMO', telefono: '+51987654321', etapa: 'descartado', origen: 'landing',
    monto_estimado: 10000, moneda: 'PEN', vendedor_id: 'yo', creado_en: '2026-09-01T15:00:00Z',
    actualizado_en: '2026-09-30T15:00:00Z', motivo_descarte: 'no_responde', ...sobre,
  } as Lead)

  it('solo trae los descartados vivos del propio analista y nunca los de «no contactar»', () => {
    const filas = filasDemoBaseGestion([
      lead({ id: 'mio' }),
      lead({ id: 'ajeno', vendedor_id: 'otro' }),
      lead({ id: 'vivo', etapa: 'contactado' }),
      lead({ id: 'vetado', no_contactar: true }),
    ], 'yo', AHORA)
    expect(filas.map((f) => f.lead_id)).toEqual(['mio'])
    expect(filas[0]).toMatchObject({ intentos: 0, etapa_maxima: 'sin_datos', dias_desde_descarte: 2, motivo_descarte: 'no_responde' })
  })
})
