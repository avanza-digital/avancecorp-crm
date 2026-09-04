import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  ReporteDerivacionesCoordinacionSchema,
  reporteDerivacionesCoordinacionConsistente,
} from './reporte-derivaciones-coordinacion'

const ANALISTA = '00000000-0000-4000-8000-000000000001'
const SUPERVISOR = '00000000-0000-4000-8000-000000000002'

const payload = () => ({
  version: 1 as const,
  generado_en: '2026-09-04T15:00:00Z',
  periodo: {
    desde: '2026-09-02',
    hasta: '2026-09-03',
    dias: '2',
    zona: 'America/Lima' as const,
  },
  total_derivados: '3',
  dias: [
    {
      fecha: '2026-09-03',
      total_derivados: '3',
      analistas: [{
        analista_id: ANALISTA,
        analista_nombre: 'ANA PAREDES',
        supervisor_id: SUPERVISOR,
        supervisor_nombre: 'CARMEN JARAMILLO',
        derivados: '3',
      }],
      entregas: [
        {
          analista_id: ANALISTA,
          analista_nombre: 'ANA PAREDES',
          supervisor_id: SUPERVISOR,
          supervisor_nombre: 'CARMEN JARAMILLO',
          origen: 'landing',
          derivados: '2',
        },
        {
          analista_id: ANALISTA,
          analista_nombre: 'ANA PAREDES',
          supervisor_id: SUPERVISOR,
          supervisor_nombre: 'CARMEN JARAMILLO',
          origen: 'referido',
          derivados: '1',
        },
      ],
    },
    { fecha: '2026-09-02', total_derivados: 0, analistas: [], entregas: [] },
  ],
})

describe('contrato del reporte diario de derivaciones de Coordinación', () => {
  it('normaliza conteos de PostgREST y conserva los días sin derivaciones', () => {
    const resultado = v.parse(ReporteDerivacionesCoordinacionSchema, payload())

    expect(resultado.total_derivados).toBe(3)
    expect(resultado.dias[0]?.analistas[0]?.derivados).toBe(3)
    expect(resultado.dias[0]?.entregas).toMatchObject([
      { origen: 'landing', derivados: 2 },
      { origen: 'referido', derivados: 1 },
    ])
    expect(resultado.dias[1]).toMatchObject({
      fecha: '2026-09-02', total_derivados: 0, analistas: [], entregas: [],
    })
    expect(reporteDerivacionesCoordinacionConsistente(resultado, '2026-09-02', '2026-09-03')).toBe(true)
  })

  it('rechaza totales que no reconcilian y fechas duplicadas', () => {
    const totalInconsistente = v.parse(ReporteDerivacionesCoordinacionSchema, {
      ...payload(),
      total_derivados: 99,
    })
    expect(reporteDerivacionesCoordinacionConsistente(
      totalInconsistente,
      '2026-09-02',
      '2026-09-03',
    )).toBe(false)

    const fechasDuplicadas = v.parse(ReporteDerivacionesCoordinacionSchema, {
      ...payload(),
      dias: [payload().dias[0], payload().dias[0]],
    })
    expect(reporteDerivacionesCoordinacionConsistente(
      fechasDuplicadas,
      '2026-09-02',
      '2026-09-03',
    )).toBe(false)

    const duracionInconsistente = v.parse(ReporteDerivacionesCoordinacionSchema, {
      ...payload(),
      periodo: { ...payload().periodo, dias: 1 },
      dias: [payload().dias[0]],
      total_derivados: 3,
    })
    expect(reporteDerivacionesCoordinacionConsistente(
      duracionInconsistente,
      '2026-09-02',
      '2026-09-03',
    )).toBe(false)
  })

  it('rechaza un desglose por origen que no reconcilia o repite una fila', () => {
    const original = payload()
    const diaConEntregas = original.dias[0]!
    const diaVacio = original.dias[1]!
    const primeraEntrega = diaConEntregas.entregas[0]!
    const origenInconsistente = v.parse(ReporteDerivacionesCoordinacionSchema, {
      ...original,
      dias: [{
        ...diaConEntregas,
        entregas: [{ ...primeraEntrega, derivados: 1 }],
      }, diaVacio],
    })
    expect(reporteDerivacionesCoordinacionConsistente(
      origenInconsistente,
      '2026-09-02',
      '2026-09-03',
    )).toBe(false)

    const filaDuplicada = v.parse(ReporteDerivacionesCoordinacionSchema, {
      ...original,
      dias: [{
        ...diaConEntregas,
        entregas: [primeraEntrega, primeraEntrega],
      }, diaVacio],
    })
    expect(reporteDerivacionesCoordinacionConsistente(
      filaDuplicada,
      '2026-09-02',
      '2026-09-03',
    )).toBe(false)
  })
})
