// El contrato del editor de metas, con foco en la clave `sin_supervisor`.
//
// Esa clave nace en el servidor DESPUÉS de que el front se despliegue: el
// contrato es `strictObject`, así que una clave desconocida rompe la pantalla
// entera y el orden de deploy tiene que ser front primero. Estos casos fijan
// las dos mitades de ese acuerdo: el front nuevo tolera al servidor viejo, y
// sigue rechazando cualquier forma que no sea la pactada.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { ConfiguracionMetasSchema, payloadPublicacionMetas } from './metas-versionadas'

const VENDEDOR = '10000000-0000-4000-8000-000000000001'
const SUPERVISOR = '10000000-0000-4000-8000-000000000002'

function detalles(): Record<string, unknown>[] {
  return (['nuevo', 'renovacion', 'upgrade'] as const).flatMap((categoria) => [
    { categoria, moneda: 'PEN', capital_objetivo: '1000', contratos_objetivo: '1' },
    { categoria, moneda: 'USD', capital_objetivo: '0', contratos_objetivo: '0' },
  ])
}

function payload(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    version: 1,
    periodo: '2026-08-01',
    revision: '0',
    publicada_en: null,
    publicada_por: null,
    publicada_por_nombre: null,
    puede_editar: true,
    vendedores: [{
      vendedor_id: VENDEDOR,
      nombre: 'ANA TORRES',
      supervisor_id: SUPERVISOR,
      supervisor_nombre: 'SUPERVISORA UNO',
      conversion_objetivo: '0',
      detalles: detalles(),
    }],
    ...sobre,
  }
}

describe('ConfiguracionMetasSchema', () => {
  it('acepta al servidor que todavía no manda sin_supervisor', () => {
    const resultado = v.safeParse(ConfiguracionMetasSchema, payload())
    expect(resultado.success).toBe(true)
    // Sin la clave, nadie queda señalado: el aviso simplemente no se pinta.
    expect(resultado.success && resultado.output.sin_supervisor).toEqual([])
  })

  it('lee la lista cuando el servidor ya la manda', () => {
    const resultado = v.safeParse(ConfiguracionMetasSchema, payload({
      sin_supervisor: [{ vendedor_id: SUPERVISOR, nombre: 'IVETT SIN JEFE', motivo: 'sin_supervisor' }],
    }))
    expect(resultado.success).toBe(true)
    expect(resultado.success && resultado.output.sin_supervisor)
      .toEqual([{ vendedor_id: SUPERVISOR, nombre: 'IVETT SIN JEFE', motivo: 'sin_supervisor' }])
  })

  it('rechaza una lista con forma distinta a la pactada', () => {
    for (const roto of [
      [{ vendedor_id: 'no-es-uuid', nombre: 'X', motivo: 'sin_supervisor' }],
      [{ vendedor_id: SUPERVISOR, nombre: '', motivo: 'sin_supervisor' }],
      [{ vendedor_id: SUPERVISOR, motivo: 'sin_supervisor' }],
      [{ vendedor_id: SUPERVISOR, nombre: 'X' }],
      [{ vendedor_id: SUPERVISOR, nombre: 'X', motivo: 'se_fue_de_vacaciones' }],
      [{ vendedor_id: SUPERVISOR, nombre: 'X', motivo: 'sin_supervisor', extra: 1 }],
      'IVETT',
    ]) {
      expect(v.safeParse(ConfiguracionMetasSchema, payload({ sin_supervisor: roto })).success)
        .toBe(false)
    }
  })

  it('mantiene sin_supervisor fuera de lo que se publica', () => {
    const config = v.parse(ConfiguracionMetasSchema, payload({
      sin_supervisor: [{ vendedor_id: SUPERVISOR, nombre: 'IVETT SIN JEFE', motivo: 'supervisor_inactivo' }],
    }))
    // El servidor exige una meta por analista DEL ROSTER; colar al excluido
    // haría fallar la publicación con 22023.
    expect(Object.keys(payloadPublicacionMetas(config))).toEqual([VENDEDOR])
  })
})
