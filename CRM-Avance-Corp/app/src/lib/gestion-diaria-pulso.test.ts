import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import fixture from './gestion-diaria-f5.test.fixture.json'
import { cifraPulso, diaPulsoValido, desplazarDia, PulsoGerenciaSchema } from './gestion-diaria-pulso'
import { HabitosGerenciaSchema } from './gestion-diaria-habitos'

describe('F5: contratos contra respuesta real del banco SQL sintético', () => {
  it('acepta la conciliación del servidor, incluida historia, sin autor y 1.008 vencidas', () => {
    const d = v.parse(PulsoGerenciaSchema, fixture.pulso)
    expect(d.actual).toMatchObject({ llamadas: 9, utiles: 8, contestadas: 5, leads_unicos: 2, tasa_contacto: 62.5 })
    expect(d.vencidas_global).toBe(1008)
    expect(d.referencia.media.llamadas).toBe(4)
  })
  it('acepta hábitos con primera llamada fuera de jornada y hueco de 165 minutos', () => {
    const h = v.parse(HabitosGerenciaSchema, fixture.habitos)
    expect(h.personas.flatMap((p) => p.dias).some((d) => d.jornada.hueco?.minutos === 165)).toBe(true)
    expect(h.umbral_tasa_baja).toBeNull()
  })
  it.each(['llamadas', 'utiles', 'contestadas', 'sin_actividad', 'citas_agendadas'] as const)('rechaza diferencia en el total %s', (k) => {
    const d = structuredClone(fixture.pulso); d.actual[k]++
    expect(v.safeParse(PulsoGerenciaSchema, d).success).toBe(false)
  })
  it('rechaza equipos/personas duplicados, pendientes parciales y base vacía con cifras', () => {
    const d = structuredClone(fixture.pulso); d.equipos.push(d.equipos[0]!)
    expect(v.safeParse(PulsoGerenciaSchema, d).success).toBe(false)
    expect(v.safeParse(PulsoGerenciaSchema, { ...fixture.pulso, vencidas_global: 1000 }).success).toBe(false)
    expect(v.safeParse(PulsoGerenciaSchema, { ...fixture.pulso, referencia: { ...fixture.pulso.referencia, dias: [], cantidad: 0 } }).success).toBe(false)
  })
  it('rechaza una fecha imposible y una media infinita', () => {
    expect(v.safeParse(PulsoGerenciaSchema, { ...fixture.pulso, dia: '2026-02-30' }).success).toBe(false)
    const d = structuredClone(fixture.pulso); d.referencia.media.llamadas = Infinity
    expect(v.safeParse(PulsoGerenciaSchema, d).success).toBe(false)
  })
  it('no acepta períodos de hábitos con jornadas ausentes o fuera de rango', () => {
    const h = structuredClone(fixture.habitos); h.personas[0]!.dias.pop()
    expect(v.safeParse(HabitosGerenciaSchema, h).success).toBe(false)
    expect(v.safeParse(HabitosGerenciaSchema, { ...fixture.habitos, hasta: '2026-09-22' }).success).toBe(false)
  })
  it('el selector permite año bisiesto real, límite de 365 días y rechaza futuro/imposibles', () => {
    expect(diaPulsoValido('2024-02-29', '2024-03-01')).toBe(true)
    expect(diaPulsoValido('2026-09-24', '2026-09-24')).toBe(true)
    expect(diaPulsoValido('2025-09-24', '2026-09-24')).toBe(true)
    for (const dia of ['2025-09-23', '2026-09-25', '2026-02-30', 'infinity', '']) expect(diaPulsoValido(dia, '2026-09-24')).toBe(false)
    expect(desplazarDia('2026-01-01', -1)).toBe('2025-12-31')
  })
  it('distingue cero medido de una cifra desconocida', () => {
    expect(cifraPulso(null)).toBe('—'); expect(cifraPulso(0)).toBe('0')
    expect(cifraPulso(62.5, true)).toBe('62.5 %')
  })
})
