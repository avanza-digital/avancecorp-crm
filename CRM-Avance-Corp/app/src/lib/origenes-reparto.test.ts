import { describe, expect, it } from 'vitest'
import { diaRepartoCoherente, origenesRepartoCoherentes } from './origenes-reparto'
import type { AsignacionAgendaReparto } from './tipos'

function asignacion(): AsignacionAgendaReparto {
  const turno = { supervisor_id: 'turno', supervisor_nombre: 'SUPERVISORA UNO', supervisor_alias: 'Uno', derivados: 7, coincide_turno: true }
  const externo = { supervisor_id: 'externo', supervisor_nombre: 'SUPERVISORA DOS', supervisor_alias: 'Dos', derivados: 2, coincide_turno: false }
  return {
    origen: 'formulario', supervisor_id: 'turno', supervisor_nombre: turno.supervisor_nombre,
    supervisor_alias: 'Uno', derivados: 9, fuera_turno: 2, entregas: [turno, externo],
    origenes: [
      { origen: 'formulario_3', derivados: 5, fuera_turno: 2, entregas: [{ ...turno, derivados: 3 }, externo] },
      { origen: 'formulario', derivados: 4, fuera_turno: 0, entregas: [{ ...turno, derivados: 4 }] },
    ],
  }
}

describe('integridad del desglose de campañas en Coordinación', () => {
  it('acepta el contrato anterior y un nuevo desglose completo, incluido un día vacío', () => {
    expect(origenesRepartoCoherentes({ derivados: 9 })).toBe(true)
    expect(origenesRepartoCoherentes(asignacion())).toBe(true)
    expect(origenesRepartoCoherentes({ derivados: 0, fuera_turno: 0, entregas: [], origenes: [] })).toBe(true)
  })

  it.each<[string, (valor: AsignacionAgendaReparto) => void]>([
    ['total sin explicar', (v) => { v.derivados = 10 }],
    ['fuera de turno incorrecto', (v) => { v.fuera_turno = 0 }],
    ['campaña duplicada', (v) => { v.origenes![1]!.origen = 'formulario_3' }],
    ['destino duplicado', (v) => { v.origenes![0]!.entregas.push(v.origenes![0]!.entregas[0]!) }],
    ['totales por destino alterados', (v) => { v.entregas![0]!.derivados = 6; v.entregas![1]!.derivados = 3 }],
    ['nombre de destino discordante', (v) => { v.origenes![1]!.entregas[0]!.supervisor_nombre = 'OTRA' }],
    ['turno discordante', (v) => { v.origenes![1]!.entregas[0]!.coincide_turno = false }],
    ['cantidad negativa', (v) => { v.origenes![1]!.derivados = -4 }],
    ['cantidad decimal', (v) => { v.origenes![1]!.derivados = 4.5 }],
    ['origen de otro turno', (v) => { v.origenes![1]!.origen = 'landing' }],
    ['detalle omitido', (v) => { delete v.entregas }],
    ['campaña sin destino conocido', (v) => { v.origenes![1]!.entregas[0]!.supervisor_id = 'desconocido' }],
    ['campañas vacías con entregas existentes', (v) => { v.origenes = [] }],
  ])('rechaza %s', (_, corromper) => {
    const valor = asignacion()
    corromper(valor)
    expect(origenesRepartoCoherentes(valor)).toBe(false)
  })
})

describe('conciliación de tabla diaria con turnos', () => {
  const dia = () => {
    const formulario = asignacion()
    return {
      asignaciones: [formulario, { ...formulario, origen: 'landing' as const, derivados: 0, fuera_turno: 0, entregas: [], origenes: [] }],
      origenes: formulario.origenes!.map((grupo) => ({ ...structuredClone(grupo), turno: 'formulario' as const })),
    }
  }
  it('reconcilia la tabla nueva y admite ausencia en el contrato anterior', () => {
    expect(diaRepartoCoherente(dia())).toBe(true)
    expect(diaRepartoCoherente({ asignaciones: [asignacion()] })).toBe(true)
  })
  it.each(['vacio', 'duplicado', 'cantidad', 'turno', 'detalle'] as const)('rechaza %s en la tabla aunque los turnos estén correctos', (cambio) => {
    const valor = dia()
    if (cambio === 'vacio') valor.origenes = []
    if (cambio === 'duplicado') valor.origenes.push(valor.origenes[0]!)
    if (cambio === 'cantidad') valor.origenes[0]!.derivados = -1
    if (cambio === 'turno') Object.assign(valor.origenes[0]!, { turno: null })
    if (cambio === 'detalle') valor.origenes[0]!.entregas[0]!.supervisor_nombre = 'OTRO'
    expect(diaRepartoCoherente(valor)).toBe(false)
  })
})
