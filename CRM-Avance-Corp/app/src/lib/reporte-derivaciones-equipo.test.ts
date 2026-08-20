import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  ReporteDerivacionesEquipoSchema,
  ResultadoDerivarLeadsEquipoSchema,
  ResultadoRevertirDerivacionEquipoSchema,
} from './reporte-derivaciones-equipo'

const ASESOR = '00000000-0000-4000-8000-000000000001'
const LEAD = '00000000-0000-4000-8000-000000000002'

describe('contrato del reporte de derivaciones del equipo', () => {
  it('acepta numeric/bigint serializados por PostgREST y los normaliza a número', () => {
    const resultado = v.parse(ReporteDerivacionesEquipoSchema, {
      version: 1,
      generado_en: '2026-08-20T18:00:00+00:00',
      periodo: { desde: '2026-08-19', hasta: '2026-08-19', dias: '1', zona: 'America/Lima' },
      asesores: [{
        asesor_id: ASESOR,
        asesor_nombre: 'Ana Paredes',
        derivados: '2',
        capital_pen: '120000.50',
        capital_usd: '0',
        sin_primer_contacto: '1',
        contactados: '1',
        contactabilidad_pct: '50.0',
        repartido_hoy: '3',
      }],
      movimientos_hoy: [{
        lead_id: LEAD,
        asesor_id: ASESOR,
        asesor_nombre: 'Ana Paredes',
        nombre_completo: 'Cliente de prueba',
        monto_estimado: '35000',
        moneda: 'PEN',
        derivado_en: '2026-08-20T17:30:00+00:00',
        reversible: true,
      }],
    })

    expect(resultado.asesores[0]).toMatchObject({
      derivados: 2,
      capital_pen: 120000.5,
      contactabilidad_pct: 50,
      repartido_hoy: 3,
    })
  })

  it('rechaza un porcentaje imposible y contratos de mutación incompletos', () => {
    const reporteInvalido = v.safeParse(ReporteDerivacionesEquipoSchema, {
      version: 1,
      generado_en: '2026-08-20T18:00:00+00:00',
      periodo: { desde: '2026-08-19', hasta: '2026-08-19', dias: 1, zona: 'America/Lima' },
      asesores: [{
        asesor_id: ASESOR,
        asesor_nombre: 'Ana Paredes',
        derivados: 1,
        capital_pen: 1,
        capital_usd: 0,
        sin_primer_contacto: 0,
        contactados: 1,
        contactabilidad_pct: 101,
        repartido_hoy: 0,
      }],
      movimientos_hoy: [],
    })

    expect(reporteInvalido.success).toBe(false)
    expect(v.safeParse(ResultadoDerivarLeadsEquipoSchema, { version: 1, derivados: 1 }).success).toBe(false)
    expect(v.safeParse(ResultadoRevertirDerivacionEquipoSchema, {
      version: 1,
      lead_id: LEAD,
      devuelto_a_bandeja: false,
    }).success).toBe(false)
  })
})
