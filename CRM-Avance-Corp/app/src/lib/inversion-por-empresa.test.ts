import {describe, expect, it} from 'vitest'
import {empresasSinHistorial} from './inversion-por-empresa'
import type {EmpresaInversion, ResumenEmpresa} from './inversionistas'

function totales(...empresas: EmpresaInversion[]): ResumenEmpresa[] {
  return empresas.map(empresa => ({empresa, moneda:'PEN', cantidad:1, capital_registrado:0, capital_activo:0}))
}

describe('Primera inversión por empresa desde la ficha multiempresa', () => {
  it.each([
    [[], ['avance','qorilazo','prodelco']],
    [['avance'], ['qorilazo','prodelco']],
    [['qorilazo'], ['avance','prodelco']],
    [['prodelco'], ['avance','qorilazo']],
    [['avance','qorilazo'], ['prodelco']],
    [['avance','prodelco'], ['qorilazo']],
    [['qorilazo','prodelco'], ['avance']],
    [['avance','qorilazo','prodelco'], []],
  ] satisfies [EmpresaInversion[], EmpresaInversion[]][])('historial %j permite %j aunque no quede capital activo', (historial, disponibles) => {
    expect(empresasSinHistorial({inversiones_total:historial.length,totales:totales(...historial)})).toEqual(disponibles)
  })

  it('conserva empresas de otras páginas y agrupa las dos monedas', () => {
    expect(empresasSinHistorial({inversiones_total:61,totales:[
      {...totales('avance')[0]!,cantidad:25},
      {...totales('avance')[0]!,moneda:'USD',cantidad:35},
      ...totales('qorilazo'),
    ]})).toEqual(['prodelco'])
  })

  it.each([0,2,26])('no convierte totales incompletos en empresas sin historial: total %s', inversiones_total => {
    expect(empresasSinHistorial({inversiones_total,totales:totales('qorilazo')})).toBeNull()
  })
})
