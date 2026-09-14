import { describe, expect, it } from 'vitest'
import { CITAS, CORTE_DIA, EQUIPO, INICIAL, PERSONAS, TRAMOS, metricas, personasConsulta, recorrido } from './modelo'

describe('coherencia del ejemplo visual de Citas', () => {
  it('incluye manuales y leads sin cita, cuenta cada entrevista y cada cliente una vez', () => {
    const personas = personasConsulta({ ...INICIAL, analista: 'ana' })
    const m = metricas(personas, 'personas')
    expect(m).toMatchObject({ leads: 160, manuales: 32, citas: 100, cumplimiento: 50, entrevistas: 70, unicas: 60, clientes: 42, ticket: 10_000, capital: 420_000 })
    expect(m.sinCita).toBeGreaterThan(0)
    expect(m.conversion).toBe(0.7)
    expect(metricas(personas, 'entrevistas').conversion).toBe(0.6)
    expect(personasConsulta({ ...INICIAL, analista: 'ana', registro: 'manual' })).toHaveLength(32)
  })

  it('cada etapa de recuperación conserva vínculo, persona y orden de fechas', () => {
    const r = recorrido(personasConsulta({ ...INICIAL, analista: 'ana' }), '')
    expect([r.length, r.filter(p => p.nueva).length, r.filter(p => p.asistencia).length, r.filter(p => p.cliente).length]).toEqual([20, 12, 8, 5])
    expect(new Set(r.map(p => p.persona.id)).size).toBe(r.length)
    for (const item of r) {
      if (item.nueva) {
        expect(item.nueva.anterior).toBe(item.falta.id)
        expect(item.nueva.lead).toBe(item.persona.id)
        expect(item.nueva.dia).toBeGreaterThan(item.falta.dia)
      }
      if (item.cliente) {
        expect(item.asistencia?.estado).toBe('realizada')
        expect(item.persona.conversion).toBeGreaterThanOrEqual(item.asistencia!.dia)
      }
    }
    expect(TRAMOS.reduce((n, t) => n + recorrido(PERSONAS, t.id).length, 0)).toBe(recorrido(PERSONAS, '').length)
  })

  it('no inventa tasas, ticket o proyección cuando no existe base', () => {
    const paola = metricas(personasConsulta({ ...INICIAL, analista: 'paola' }), 'personas')
    expect(paola).toMatchObject({ leads: 40, citas: 0, cumplimiento: 0, asistencia: null, conversion: null, ticket: null, proyeccion: null })
    expect(personasConsulta({ ...INICIAL, mes: '2026-08' })).toEqual([])
    expect(personasConsulta({ ...INICIAL, moneda: 'USD' })).toEqual([])
    expect(metricas([], 'personas').cumplimiento).toBeNull()
  })

  it('mantiene los eventos dentro del corte y las proyecciones dentro de la población, también con filtros', () => {
    for (const c of CITAS) {
      expect(c.creada).toBeLessThanOrEqual(CORTE_DIA)
      expect(c.creada).toBeLessThanOrEqual(c.dia)
      if (c.estado !== 'programada') expect(c.dia).toBeLessThanOrEqual(CORTE_DIA)
    }
    for (const analista of EQUIPO) for (const origen of ['', 'Facebook', 'Web', 'Referido']) for (const registro of ['', 'manual', 'recibido']) for (const base of ['personas', 'entrevistas'] as const) {
      const p = personasConsulta({ ...INICIAL, analista: analista.id, origen, registro })
      const m = metricas(p, base)
      expect(m.clientes).toBeLessThanOrEqual(m.unicas)
      expect(m.unicas).toBeLessThanOrEqual(m.entrevistas)
      if (m.clientesEsperados !== null) {
        expect(m.clientesEsperados).toBeLessThanOrEqual(m.leads)
        expect(m.clientesEsperados).toBeGreaterThanOrEqual(m.clientes)
      }
      if (m.proyeccion !== null) expect(m.proyeccion).toBeGreaterThanOrEqual(m.capital)
    }
  })
})
