import { beforeEach, describe, expect, it, vi } from 'vitest'
import fixture from '@/lib/gestion-diaria-f5.test.fixture.json'
const dobles = vi.hoisted(() => ({ rpc: vi.fn(), abort: vi.fn(), data: null as unknown, error: null as unknown }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: () => ({ rpc: dobles.rpc }) } }))
const { obtenerPulsoGerencia, obtenerHabitosGerencia } = await import('./gestion-diaria-pulso-api')
beforeEach(() => {
  vi.clearAllMocks(); dobles.data = fixture.pulso; dobles.error = null
  const resolver = () => Promise.resolve({ data: dobles.data, error: dobles.error })
  dobles.abort.mockImplementation(resolver)
  dobles.rpc.mockImplementation(() => ({ abortSignal: dobles.abort, then: (fn: (r: unknown) => unknown) => resolver().then(fn) }))
})
describe('F5: frontera de la API', () => {
  it('transmite fecha/cancelación y exige la foto completa aunque el store esté vacío', async () => {
    const signal = new AbortController().signal
    expect((await obtenerPulsoGerencia(fixture.pulso.dia, signal)).actual.llamadas).toBe(9)
    expect(dobles.rpc).toHaveBeenCalledWith('gestion_diaria_pulso_fn', { p_dia: fixture.pulso.dia })
    expect(dobles.abort).toHaveBeenCalledWith(signal)
  })
  it('rechaza respuestas de otro día o sólo con un total', async () => {
    await expect(obtenerPulsoGerencia('2026-09-22')).rejects.toMatchObject({ code: 'GESTION_DIARIA_CONTRACT' })
    dobles.data = { actual: fixture.pulso.actual }
    await expect(obtenerPulsoGerencia(fixture.pulso.dia)).rejects.toMatchObject({ code: 'GESTION_DIARIA_CONTRACT' })
  })
  it('contrasta el eco del período de hábitos, no sólo su fecha final', async () => {
    dobles.data = fixture.habitos
    expect((await obtenerHabitosGerencia(fixture.habitos.hasta, 7)).dias_incluidos).toBe(7)
    await expect(obtenerHabitosGerencia(fixture.habitos.hasta, 30)).rejects.toMatchObject({ code: 'GESTION_DIARIA_CONTRACT' })
    await expect(obtenerHabitosGerencia('2026-09-22', 7)).rejects.toMatchObject({ code: 'GESTION_DIARIA_CONTRACT' })
  })
  it('mantiene el código de revocación en ambas puertas', async () => {
    dobles.error = { code: '42501', message: 'Acceso revocado' }
    await expect(obtenerPulsoGerencia(fixture.pulso.dia)).rejects.toMatchObject({ code: '42501' })
    await expect(obtenerHabitosGerencia(fixture.habitos.hasta, 7)).rejects.toMatchObject({ code: '42501' })
  })
})
