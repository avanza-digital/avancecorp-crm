import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { AvisosCortesSchema, estadoCorte } from './gestion-diaria-avisos'

import { avisosFixture } from './gestion-diaria-avisos.fixture'

describe('frontera de avisos F4', () => {
  it('admite el estado OFF sin inventar avisos ni objetivos', () => {
    const respuesta = avisosFixture()
    respuesta.estado_cortes = 'desactivados'
    respuesta.alertas = []
    expect(v.safeParse(AvisosCortesSchema, respuesta).success).toBe(true)
  })
  it.each(['supervisor', 'jornada', 'tipo', 'duplicados', 'sin miembros', 'cumplido', 'fuera de horario', 'canal apagado', 'reconocido'])
  ('rechaza una respuesta incoherente: %s', (caso) => {
    const r = avisosFixture(), a = r.alertas[0]!
    if (caso === 'supervisor') r.supervisor_id = '00000000-0000-4000-8000-000000000099'
    if (caso === 'jornada') r.dia = '2026-09-23'
    if (caso === 'tipo') a.tipo = 'corte_tarde'
    if (caso === 'duplicados') r.alertas.push({ ...a })
    if (caso === 'sin miembros') a.miembros = []
    if (caso === 'cumplido') a.miembros[0]!.llamadas = 3
    if (caso === 'fuera de horario') r.generado_en = a.fin_jornada
    if (caso === 'canal apagado') r.avisos_habilitados = false
    if (caso === 'reconocido') a.estado = 'reconocido'
    expect(v.safeParse(AvisosCortesSchema, r).success).toBe(false)
  })
  it('permite conservar un pendiente después del cierre sin presentarlo otra vez', () => {
    const r = avisosFixture(), a = r.alertas[0]!
    r.generado_en = '2026-09-22T23:30:00Z'
    a.puede_presentar = false
    a.puede_posponer = false
    expect(v.safeParse(AvisosCortesSchema, r).success).toBe(true)
  })
  it('explica un aplazamiento que cae exactamente al cierre sin prometer reaviso', () => {
    const a = avisosFixture().alertas[0]!
    a.estado = 'pospuesto'
    a.pospuesto_hasta = a.fin_jornada
    expect(estadoCorte(a)).toContain('sin reaviso')
    a.pospuesto_hasta = '2026-09-22T18:00:00Z'
    expect(estadoCorte(a)).toContain('13:00')
  })
})
