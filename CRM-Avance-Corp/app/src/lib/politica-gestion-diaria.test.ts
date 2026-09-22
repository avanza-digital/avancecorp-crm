import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { PoliticaGestionDiariaSchema, ejemploSegundoCorte, jornadaLimaIso, desplazarJornada } from './politica-gestion-diaria'

import { politicaFixture } from './politica-gestion-diaria.fixture'
describe('política de Gestión Diaria', () => {
  it('valida la política inicial OFF y admite la tasa muy baja vacía', () => {
    expect(v.safeParse(PoliticaGestionDiariaSchema, politicaFixture).success).toBe(true)
  })
  it.each([
    { corte_1_hora: '09:00' }, { corte_1_hora: '13:00' }, { corte_2_hora: '18:00' },
    { corte_2_hora: '11:00' }, { corte_1_minimo: 2.5 }, { sabado_minimo: 0 },
    { bien_min_pct: 25 }, { corte_2_techo: 7 }, { corte_2_incremento_pct: 1001 },
    { cortes_activos: 'true' }, { tasa_baja_diferencia_pp: -1 }, { tasa_baja_diferencia_pp: 20 }, { clave_extra: true },
  ])('rechaza parámetros fuera del contrato: %j', (cambio) => {
    expect(v.safeParse(PoliticaGestionDiariaSchema, { ...politicaFixture, ...cambio }).success).toBe(false)
  })
  it.each([[0, 8], [8, 20], [20, 30]])('explica base %s con objetivo final %s', (base, esperado) => {
    expect(ejemploSegundoCorte(base!, politicaFixture).objetivo).toBe(esperado)
  })
  it('explica el redondeo hacia arriba y separa el cálculo del techo', () => {
    expect(ejemploSegundoCorte(8, { ...politicaFixture, corte_2_incremento_pct: 30 })).toEqual({ sinLimites: 11, objetivo: 11 })
    expect(ejemploSegundoCorte(20, politicaFixture)).toEqual({ sinLimites: 50, objetivo: 30 })
  })
  it('resuelve medianoche Lima y cambios de mes/año sin el reloj del dispositivo', () => {
    expect(jornadaLimaIso('2026-09-23')).toBe('2026-09-23T05:00:00.000Z')
    expect(desplazarJornada('2026-12-31', 1)).toBe('2027-01-01')
    expect(() => jornadaLimaIso('2026-02-30')).toThrow('Jornada inválida')
  })
})
