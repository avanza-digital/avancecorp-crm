import { describe, expect, it } from 'vitest'
import { consultaInicial, consultarCitas, citasPorLead, rangoConsulta, resumenLeads, seguimientoInasistencias, CITAS_CRM, type CitaConLead } from './datos'

describe('lecturas comerciales del ejemplo de Citas', () => {
  it('las cuatro semanas cubren el mes completo incluso febrero bisiesto y días 29–31', () => {
    for (const [mes, ultimo] of [['2026-02', 28], ['2028-02', 29], ['2026-09', 30], ['2026-10', 31]] as const) {
      expect(rangoConsulta({ ...consultaInicial(), mes })).toEqual([`${mes}-01`, `${mes}-${ultimo}`])
      const semanas = [1, 2, 3, 4].map(semana => rangoConsulta({ ...consultaInicial(), mes, semana: String(semana) }))
      expect(semanas).toEqual([[`${mes}-01`, `${mes}-07`], [`${mes}-08`, `${mes}-14`], [`${mes}-15`, `${mes}-21`], [`${mes}-22`, `${mes}-${ultimo}`]])
      const dias = Array.from({ length: ultimo }, (_, indice) => ({ ...CITAS_CRM[0]!, id: `dia-${indice + 1}`, fecha: `${mes}-${String(indice + 1).padStart(2, '0')}` }))
      const particion = [1, 2, 3, 4].map(semana => consultarCitas({ ...consultaInicial(), mes, semana: String(semana) }, dias))
      expect(particion.map(citas => citas.length)).toEqual([7, 7, 7, ultimo - 21])
      expect(particion.flat()).toEqual(consultarCitas({ ...consultaInicial(), mes }, dias))
      expect(new Set(particion.flat().map(cita => cita.id)).size).toBe(ultimo)
      expect(particion[3]!.at(-1)?.fecha).toBe(`${mes}-${ultimo}`)
    }
    expect(consultarCitas({ ...consultaInicial(), semana: '2' })).toHaveLength(8)
    expect(consultarCitas({ ...consultaInicial(), semana: '4' })).toEqual([])
  })

  it('cada id del ejemplo conserva una sola identidad y las relaciones apuntan al mismo lead', () => {
    for (const lead of citasPorLead(CITAS_CRM)) {
      expect(new Set(lead.citas.map(cita => `${cita.nombre}|${cita.telefono}`)).size).toBe(1)
      const original = CITAS_CRM[Number(lead.id.slice(2)) - 1]
      expect(original?.leadId).toBe(lead.id)
    }
    for (const cita of CITAS_CRM.filter(cita => cita.citaAnteriorId)) {
      expect(CITAS_CRM.find(original => original.id === cita.citaAnteriorId)?.leadId).toBe(cita.leadId)
    }
  })

  it('distingue leads por id, cuenta episodios repetidos y no promedia promedios', () => {
    const base = CITAS_CRM[0]!
    const citas = [
      { ...base, id: 'c1', leadId: 'lead-a', analista: 'ana' },
      { ...base, id: 'c2', leadId: 'lead-a', analista: 'ana' },
      { ...base, id: 'c3', leadId: 'lead-a', analista: 'diego' },
      { ...base, id: 'c4', leadId: 'lead-b', analista: 'diego' },
    ]
    expect(resumenLeads(citas)).toEqual({ leads: 2, promedio: 2, repetidos: 1 })
    expect(resumenLeads(citas.filter(c => c.analista === 'ana')).promedio).toBe(2)
    expect(resumenLeads(citas.filter(c => c.analista === 'diego')).promedio).toBe(1)
    expect(citasPorLead(citas).map(lead => [lead.id, lead.citas.length])).toEqual([['lead-a', 3], ['lead-b', 1]])
    expect(resumenLeads([])).toEqual({ leads: 0, promedio: null, repetidos: 0 })
  })

  it('el detalle por lead y el promedio usan exactamente los mismos filtros', () => {
    const ana = consultarCitas({ ...consultaInicial(), analista: 'ana' })
    expect(resumenLeads(ana)).toEqual({ leads: 4, promedio: 1.75, repetidos: 2 })
    const lead = citasPorLead(ana)[0]!
    expect(consultarCitas({ ...consultaInicial(), analista: 'ana', leadId: lead.id })).toEqual(lead.citas)
    expect(resumenLeads(consultarCitas({ ...consultaInicial(), analista: 'ana', estados: ['realizada'] }))).toEqual({ leads: 2, promedio: 1, repetidos: 0 })
  })

  it('sigue vínculos de inasistencia fuera de la semana y conserva el resultado original', () => {
    const original = consultarCitas({ ...consultaInicial(), semana: '1', estados: ['no_show'] })
    const seguimiento = seguimientoInasistencias(original)
    expect(original).toHaveLength(4)
    expect(seguimiento.filter(fila => fila.nueva)).toHaveLength(3)
    expect(seguimiento.filter(fila => fila.estado === 'recuperada')).toHaveLength(1)
    expect(seguimiento.filter(fila => fila.estado === 'pendiente')).toHaveLength(2)
    expect(seguimiento.filter(fila => fila.estado === 'sin_reprogramar')).toHaveLength(1)
    expect(original.every(cita => cita.estado === 'no_show')).toBe(true)
  })

  it('otra cita del mismo lead no es reprogramación; respeta el corte y sigue una cadena sin duplicar', () => {
    const original = CITAS_CRM[30]!
    const nueva = CITAS_CRM[18]!
    const sinVinculo: CitaConLead = { ...nueva }
    delete sinVinculo.citaAnteriorId
    expect(seguimientoInasistencias([original], [original, sinVinculo])[0]?.estado).toBe('sin_reprogramar')
    expect(seguimientoInasistencias([original], [original, { ...nueva, reprogramadaEn: '2026-09-08T10:00:00-05:00' }])[0]?.estado).toBe('sin_reprogramar')
    const segunda = { ...nueva, id: 'siguiente', citaAnteriorId: nueva.id, reprogramadaEn: '2026-09-04T10:00:00-05:00', fecha: '2026-09-05', estado: 'no_show' as const }
    const cadena = seguimientoInasistencias([original], [original, { ...nueva, estado: 'reprogramada' }, segunda])
    expect(cadena).toHaveLength(1)
    expect(cadena[0]?.nueva?.id).toBe('siguiente')
    expect(cadena[0]?.estado).toBe('otra_inasistencia')
  })
})
