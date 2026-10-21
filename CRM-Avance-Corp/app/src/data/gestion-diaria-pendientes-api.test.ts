import { beforeEach, describe, expect, it, vi } from 'vitest'
import { paginaPendientes, pedidoPendientes } from '@/lib/gestion-diaria-pendientes.fixture'
const dobles = vi.hoisted(() => ({ rpc: vi.fn(), abort: vi.fn(), data: null as unknown, error: null as unknown }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: () => ({ rpc: dobles.rpc }) } }))
const { listarPendientesSupervisor } = await import('./gestion-diaria-pendientes-api')
beforeEach(() => {
  vi.clearAllMocks(); dobles.data = paginaPendientes(); dobles.error = null
  dobles.abort.mockImplementation(() => Promise.resolve({ data: dobles.data, error: dobles.error }))
  dobles.rpc.mockImplementation(() => ({ abortSignal: dobles.abort,
    then: (f: (v: unknown) => unknown) => Promise.resolve({ data: dobles.data, error: dobles.error }).then(f) }))
})
describe('Puerta de pendientes', () => {
  it('pide sólo el ámbito y límite; transmite abort; no usa la cartera del navegador', async () => {
    const signal = new AbortController().signal
    expect(await listarPendientesSupervisor(pedidoPendientes, signal)).toEqual(dobles.data)
    expect(dobles.rpc).toHaveBeenCalledWith('gestion_diaria_pendientes_v3_fn', { p_analista_id: pedidoPendientes.analista, p_solo_vencidas: false, p_limite: 25 })
    expect(dobles.abort).toHaveBeenCalledWith(signal)
  })
  it('con cursor manda las dos mitades («después» = más antiguo que la última fila)', async () => {
    const cursor = { despues_de: '2026-09-23T15:00:00.000001+00:00', despues_id: pedidoPendientes.analista }
    dobles.data = paginaPendientes([], { resumen: { tareas_pendientes: 1, tareas_vencidas: 1 } })
    await listarPendientesSupervisor({ ...pedidoPendientes, cursor })
    expect(dobles.rpc).toHaveBeenCalledWith('gestion_diaria_pendientes_v3_fn',
      { p_analista_id: pedidoPendientes.analista, p_solo_vencidas: false, p_limite: 25, p_despues_de: cursor.despues_de, p_despues_id: cursor.despues_id })
  })
  it.each(['42501', 'PGRST202', '22023', 'XX000'])('preserva %s sin convertirlo en vacío', async code => {
    dobles.error = { code, message: 'Error controlado' }
    await expect(listarPendientesSupervisor(pedidoPendientes)).rejects.toMatchObject({ code })
  })
  it('rechaza un contrato parcial', async () => {
    dobles.data = { items: [] }
    await expect(listarPendientesSupervisor(pedidoPendientes)).rejects.toMatchObject({ code: 'GESTION_DIARIA_PENDIENTES_CONTRACT' })
  })
})
