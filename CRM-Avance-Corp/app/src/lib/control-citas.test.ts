import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { ControlCitasSchema, controlCitasInicial, ejemploControlCitas, numeroControlCitas, pendientesControlCitas, validarConsultaControlCitas } from './control-citas'

describe('Control de Citas: acuerdos y borradores', () => {
  it('parte de 1,25 / 70 / 70, incluye manuales y no decide lo pendiente', () => {
    const config = controlCitasInicial()
    expect(v.safeParse(ControlCitasSchema, config).success).toBe(true)
    expect(ejemploControlCitas(config)).toEqual({ leadsBase: 100, citas: 125 })
    expect(ejemploControlCitas({ ...config, excluir_manuales_base: true })).toEqual({ leadsBase: 80, citas: 100 })
    expect(pendientesControlCitas(config)).toHaveLength(4)
    expect(config.actividad_manuales).toBe('incluir')
    expect(config.conteo_entrevistas).toBe('citas_realizadas')
    expect(config.base_depositos).toBeNull()
    expect(config.mostrar_meta_citas).toBe(false)
  })
  it.each(['', ' ', '1,25%', '1.25x', '1,2,5', 'NaN', 'Infinity', '-1', '1e2', '1.251'])('rechaza entradas ambiguas %s', texto => {
    expect(numeroControlCitas(texto)).toBeNull()
  })
  it('acepta coma y punto decimal', () => {
    expect(numeroControlCitas('1,25')).toBe(1.25)
    expect(numeroControlCitas('1.25')).toBe(1.25)
    expect(ejemploControlCitas({ ...controlCitasInicial(), citas_por_lead: 1.1, excluir_manuales_base: false }).citas).toBe(110)
  })
  it.each([
    { citas_por_lead: 0 }, { citas_por_lead: 10.01 }, { citas_por_lead: 1.251 },
    { entrevistas_porcentaje: 100.01 }, { depositos_porcentaje: 0 }, { depositos_porcentaje: Number.NaN },
    { mostrar_meta_citas: true }, { mes_inicio: '2026-13' }, { base_depositos: 'numero_citas' },
    { campo_desconocido: true },
  ])('rechaza configuración inválida %j', patch => {
    expect(v.safeParse(ControlCitasSchema, { ...controlCitasInicial(), ...patch }).success).toBe(false)
  })
  it('distingue una configuración vacía válida de una respuesta incompleta', () => {
    expect(validarConsultaControlCitas({ version_actual: 0, ultimo: null, historial: [] })).not.toBeNull()
    expect(validarConsultaControlCitas({ version_actual: 1, ultimo: null, historial: [] })).toBeNull()
    expect(validarConsultaControlCitas(null)).toBeNull()
  })
})
