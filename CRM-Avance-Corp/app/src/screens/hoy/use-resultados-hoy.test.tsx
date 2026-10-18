import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import type { FacturacionDelMes } from '@/data/crm-api'
import type { CoberturaCapital } from '@/lib/capital-valorado'
import { useResultadosHoy } from './use-resultados-hoy'

let actor = { id: 's1', rol: 'supervisor', demo: false }
const filas = (): FacturacionDelMes => Object.assign([{ dia: '2026-10-18', tipo: 'contrato_nuevo', moneda: 'PEN' as const,
  analistaId: 'a1', analistaNombre: 'Ana', supervisorId: 's1', supervisorNombre: 'Supervisor', operaciones: 2, capital: 30000 }], { descartadas: 0 })
const refetch = vi.fn(async () => {})
let consulta: { data: FacturacionDelMes | undefined; error: Error | null; isPending: boolean; refetch: typeof refetch }
const leer = vi.fn((_habilitada: boolean, _mes: string) => consulta)
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: actor }) }))
vi.mock('@/data/crm-queries', () => ({ useFacturacionDiaria: (habilitada: boolean, mes: string) => leer(habilitada, mes) }))
vi.mock('@/lib/demo-metricas', () => ({ demoFacturacionDiaria: () => filas() }))

const cobertura: CoberturaCapital = { corte: '2026-10-18', estado: 'completo', pendientes: { cantidad: 0, pen: 0, usd: 0 },
  por_incorporar: { cantidad: 0, pen: 0, usd: 0 }, ventas_pendientes: [] }
beforeEach(() => {
  actor = { id: 's1', rol: 'supervisor', demo: false }
  consulta = { data: filas(), error: null, isPending: false, refetch }
  leer.mockClear(); refetch.mockClear()
})
afterEach(() => vi.unstubAllEnvs())

describe('resultados de hoy desde Facturación', () => {
  it('consulta el mes comercial de Lima y retira la foto en caché al fallar el refresco', async () => {
    const { result, rerender } = renderHook(() => useResultadosHoy('2026-10-18'))
    expect(leer).toHaveBeenLastCalledWith(true, '2026-10-01')
    expect(result.current.resultados).toMatchObject({ operaciones: 2, pen: 30000, usd: 0 })
    consulta.error = new Error('Sin acceso')
    rerender()
    expect(result.current.resultados).toBeNull()
    expect(result.current.error).toBe(true)
    await act(async () => result.current.recargar())
    expect(refetch).toHaveBeenCalledOnce()
  })
  it('no afirma cero durante la carga, ante filas descartadas, recorte legado o ausencia del primer corte', () => {
    consulta = { ...consulta, data: undefined, isPending: true }
    const { result, rerender } = renderHook(() => useResultadosHoy('2026-10-18'))
    expect(result.current.resultados).toBeNull()
    expect(result.current.cargando).toBe(true)
    consulta = { ...consulta, data: Object.assign(filas(), { descartadas: 1 }), isPending: false }
    rerender()
    expect(result.current.resultados).toBeNull()
    consulta.data = Object.assign(Array.from({ length: 1000 }, () => filas()[0]!), { descartadas: 0, posibleRecorte: true as const })
    rerender()
    expect(result.current.resultados).toBeNull()
    consulta.data = Object.assign(filas(), { capitalValoracion: { activa: true as const, corteId: null, corte: null, cobertura } })
    rerender()
    expect(result.current.resultados).toBeNull()
    expect(result.current.aviso).toBe('Resultados pendientes de confirmar.')
  })
  it('acompaña el corte disponible con un aviso si quedan cierres por incorporar', () => {
    consulta.data = Object.assign(filas(), { capitalValoracion: { activa: true as const, corteId: 'c1', corte: '2026-10-18',
      cobertura: { ...cobertura, por_incorporar: { cantidad: 1, pen: 2000, usd: 0 } } } })
    const { result, rerender } = renderHook(() => useResultadosHoy('2026-10-18'))
    expect(result.current.resultados?.pen).toBe(30000)
    expect(result.current.aviso).toContain('pendientes de incorporar')
    consulta.error = new Error('Fallo con foto anterior')
    rerender()
    expect(result.current.resultados).toBeNull()
    expect(result.current.aviso).toBeNull()
  })
  it('un corte de ayer no acredita cero cierres hoy', () => {
    consulta.data = Object.assign([], { descartadas: 0, capitalValoracion: { activa: true as const,
      corteId: 'c1', corte: '2026-10-17', cobertura: { ...cobertura, corte: '2026-10-17' } } })
    const { result } = renderHook(() => useResultadosHoy('2026-10-18'))
    expect(result.current.resultados).toBeNull()
    expect(result.current.aviso).toBe('Los cierres de hoy aún están por confirmar.')
  })
  it('no recorta un sobre JSON completo ni activa la lectura para otro rol', () => {
    consulta.data = Object.assign(Array.from({ length: 1000 }, () => filas()[0]!), { descartadas: 0 })
    const { result, rerender } = renderHook(() => useResultadosHoy('2026-10-18'))
    expect(result.current.resultados?.operaciones).toBe(2000)
    actor = { ...actor, rol: 'vendedor' }
    rerender()
    expect(leer).toHaveBeenLastCalledWith(false, '2026-10-01')
    expect(result.current.resultados).toBeNull()
  })
  it('la demo no activa la consulta real ni usa datos reales que estén en caché', async () => {
    vi.stubEnv('VITE_ENABLE_DEMO', 'true')
    actor = { ...actor, demo: true }
    consulta.data![0] = { ...consulta.data![0]!, capital: 999999 }
    const { result } = renderHook(() => useResultadosHoy('2026-10-18'))
    await waitFor(() => expect(result.current.resultados?.pen).toBe(30000))
    expect(leer).toHaveBeenLastCalledWith(false, '2026-10-01')
    expect(refetch).not.toHaveBeenCalled()
  })
})
