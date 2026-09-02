// Tests de las funciones puras de tipo de cambio + el camino REAL del hook
// (edge crm-tipo-cambio): respuesta válida entra, fuera de contrato o error → null.
import { describe, expect, it, vi, afterEach } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import { promedioSemanal, usdAPen, useTipoCambio } from './tipo-cambio'

const invoke = vi.fn()
vi.mock('./supabase', () => ({
  get sb() {
    return { functions: { invoke } }
  },
}))
vi.mock('./auth-context', () => ({
  useAuth: () => ({ yo: { id: 'u1', nombre_completo: 'REAL', rol: 'vendedor', demo: false } }),
}))
vi.mock('./observabilidad', () => ({
  registrarAviso: vi.fn(),
}))

describe('promedioSemanal', () => {
  it('promedia una serie de cotizaciones', () => {
    expect(promedioSemanal([3.7, 3.8])).toBeCloseTo(3.75, 5)
  })

  it('ignora ceros, negativos y NaN', () => {
    expect(promedioSemanal([3.75, 0, -1, Number.NaN, 3.85])).toBeCloseTo(3.8, 5)
  })

  it('serie vacía o toda inválida → 0 (sin dividir por cero)', () => {
    expect(promedioSemanal([])).toBe(0)
    expect(promedioSemanal([0, -2, Number.NaN])).toBe(0)
  })
})

describe('usdAPen', () => {
  it('convierte USD a PEN al tipo de cambio dado', () => {
    expect(usdAPen(100, 3.75)).toBe(375)
  })

  it('sin tipo de cambio (0 o negativo) devuelve 0 — no inventa soles', () => {
    expect(usdAPen(100, 0)).toBe(0)
    expect(usdAPen(100, -1)).toBe(0)
  })

  it('monto 0 → 0', () => {
    expect(usdAPen(0, 3.75)).toBe(0)
  })
})

describe('useTipoCambio (sesión real → edge crm-tipo-cambio)', () => {
  afterEach(() => vi.clearAllMocks())

  it('respuesta válida de la edge → promedio y fuente reales (pasando por «consultando»)', async () => {
    invoke.mockResolvedValue({
      data: { promedio: 3.3965, fuente: 'SBS · prom. 7d', dias: 7 },
      error: null,
    })
    const { result } = renderHook(() => useTipoCambio())
    // Mientras el fetch está en vuelo el estado es «consultando» (undefined),
    // nunca «no disponible»: la UI no debe afirmar lo segundo durante la carga.
    expect(result.current.tc).toBeUndefined()
    await waitFor(() => expect(result.current.tc).not.toBeUndefined())
    expect(result.current.tc).toEqual({ promedio: 3.3965, fuente: 'SBS · prom. 7d' })
    expect(invoke).toHaveBeenCalledWith('crm-tipo-cambio')
  })

  it('fecha de corte mensual → la envía a la misma edge sin crear otra frontera', async () => {
    invoke.mockResolvedValue({
      data: {
        promedio: 3.3965,
        fuente: 'SBS · prom. 7d',
        dias: 7,
        fecha_corte: '2026-08-31',
      },
      error: null,
    })
    const { result } = renderHook(() => useTipoCambio(true, '2026-08-31'))

    await waitFor(() => expect(result.current.tc).toEqual({
      promedio: 3.3965,
      fuente: 'SBS · prom. 7d al 31/08/2026',
    }))
    expect(invoke).toHaveBeenCalledWith('crm-tipo-cambio', {
      body: { fecha_corte: '2026-08-31' },
    })
  })

  it('al cambiar de mes invalida el TC anterior antes de resolver el nuevo corte', async () => {
    invoke.mockResolvedValueOnce({
      data: {
        promedio: 3.53,
        fuente: 'SBS · prom. 7d',
        fecha_corte: '2026-08-31',
      },
      error: null,
    })
    invoke.mockImplementationOnce(() => new Promise(() => {}))
    const { result, rerender } = renderHook(
      ({ corte }) => useTipoCambio(true, corte),
      { initialProps: { corte: '2026-08-31' } },
    )
    await waitFor(() => expect(result.current.tc).toEqual({
      promedio: 3.53,
      fuente: 'SBS · prom. 7d al 31/08/2026',
    }))

    rerender({ corte: '2026-07-31' })

    expect(result.current.tc).toBeUndefined()
    expect(invoke).toHaveBeenLastCalledWith('crm-tipo-cambio', {
      body: { fecha_corte: '2026-07-31' },
    })
  })

  it.each([
    ['otro corte', '2026-09-01'],
    ['sin corte declarado', undefined],
  ])('respuesta válida pero con %s → null (fail-closed)', async (_caso, fecha_corte) => {
    invoke.mockResolvedValue({
      data: { promedio: 3.3965, fuente: 'SBS · prom. 7d', fecha_corte },
      error: null,
    })
    const { result } = renderHook(() => useTipoCambio(true, '2026-08-31'))

    await waitFor(() => expect(result.current.tc).toBeNull())
  })

  it.each([
    ['promedio 0', { promedio: 0, fuente: 'SBS' }],
    ['promedio negativo', { promedio: -1, fuente: 'SBS' }],
    ['promedio string', { promedio: '3.39', fuente: 'SBS' }],
    ['sin fuente', { promedio: 3.39 }],
  ])('respuesta fuera de contrato (%s) → null, jamás inventa TC', async (_caso, data) => {
    invoke.mockResolvedValue({ data, error: null })
    const { result } = renderHook(() => useTipoCambio())
    await waitFor(() => expect(invoke).toHaveBeenCalled())
    await waitFor(() => expect(result.current.tc).toBeNull())
  })

  it('error de la edge (BCRP caído) → null y la pantalla degrada a solo-PEN', async () => {
    invoke.mockResolvedValue({ data: null, error: new Error('502') })
    const { result } = renderHook(() => useTipoCambio())
    await waitFor(() => expect(invoke).toHaveBeenCalled())
    await waitFor(() => expect(result.current.tc).toBeNull())
  })

  it('habilitado=false → null inmediato SIN tocar la red (vistas que no muestran TC)', async () => {
    const { result } = renderHook(() => useTipoCambio(false))
    await waitFor(() => expect(result.current.tc).toBeNull())
    expect(invoke).not.toHaveBeenCalled()
  })

  it('recargar() reintenta tras un fallo transitorio (cableado al Reintentar del panel)', async () => {
    invoke.mockResolvedValueOnce({ data: null, error: new Error('502') })
    invoke.mockResolvedValueOnce({
      data: { promedio: 3.41, fuente: 'SBS · prom. 7d' },
      error: null,
    })
    const { result } = renderHook(() => useTipoCambio())
    await waitFor(() => expect(result.current.tc).toBeNull())

    act(() => result.current.recargar())
    await waitFor(() => expect(result.current.tc).toEqual({ promedio: 3.41, fuente: 'SBS · prom. 7d' }))
    expect(invoke).toHaveBeenCalledTimes(2)
  })
})
