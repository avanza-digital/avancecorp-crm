import { beforeEach, describe, expect, it, vi } from 'vitest'
import { diaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
const dobles = vi.hoisted(() => ({ rpc: vi.fn(), abort: vi.fn(), data: null as unknown, error: null as unknown }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: () => ({ rpc: dobles.rpc }) } }))
const { obtenerDiaEquipo } = await import('./gestion-diaria-api')

beforeEach(() => {
  vi.clearAllMocks()
  dobles.data = diaEquipoPrueba(); dobles.error = null
  dobles.abort.mockImplementation(() => Promise.resolve({ data: dobles.data, error: dobles.error }))
  dobles.rpc.mockImplementation(() => ({ abortSignal: dobles.abort,
    then: (resolve: (v: unknown) => unknown) => Promise.resolve({ data: dobles.data, error: dobles.error }).then(resolve) }))
})
describe('RPC de equipo: contrato y eco de ámbito', () => {
  it('pide la foto al servidor y transmite cancelación', async () => {
    const signal = new AbortController().signal
    expect(await obtenerDiaEquipo('2026-09-21', 's1', signal)).toEqual(dobles.data)
    expect(dobles.rpc).toHaveBeenCalledWith('gestion_diaria_equipo_fn', { p_dia: '2026-09-21', p_supervisor_id: 's1' })
    expect(dobles.abort).toHaveBeenCalledWith(signal)
  })
  it.each(['dia', 'supervisor_id'])('rechaza eco equivocado en %s', async (campo) => {
    dobles.data = { ...diaEquipoPrueba(), [campo]: 'otro' }
    await expect(obtenerDiaEquipo('2026-09-21', 's1')).rejects.toMatchObject({ code: 'GESTION_DIARIA_CONTRACT' })
  })
  it('no transforma un payload incompleto en un equipo vacío', async () => {
    dobles.data = { equipo: [] }
    await expect(obtenerDiaEquipo('2026-09-21', 's1')).rejects.toMatchObject({ code: 'GESTION_DIARIA_CONTRACT' })
  })
  it('preserva la denegación explícita de permisos', async () => {
    dobles.error = { code: '42501', message: 'No autorizado' }
    await expect(obtenerDiaEquipo('2026-09-21', 's1')).rejects.toMatchObject({ code: '42501' })
  })
})
