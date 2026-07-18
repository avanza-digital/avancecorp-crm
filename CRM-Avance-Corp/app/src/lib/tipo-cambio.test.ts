// Tests de las funciones puras de tipo de cambio + el camino REAL del hook
// (edge crm-tipo-cambio): respuesta válida entra, fuera de contrato o error → null.
import { describe, expect, it, vi, afterEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
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

  it('respuesta válida de la edge → promedio y fuente reales', async () => {
    invoke.mockResolvedValue({
      data: { promedio: 3.3965, fuente: 'SBS · prom. 7d', dias: 7 },
      error: null,
    })
    const { result } = renderHook(() => useTipoCambio())
    await waitFor(() => expect(result.current).not.toBeNull())
    expect(result.current).toEqual({ promedio: 3.3965, fuente: 'SBS · prom. 7d' })
    expect(invoke).toHaveBeenCalledWith('crm-tipo-cambio')
  })

  it.each([
    ['promedio 0', { promedio: 0, fuente: 'SBS' }],
    ['promedio negativo', { promedio: -1, fuente: 'SBS' }],
    ['promedio string', { promedio: '3.39', fuente: 'SBS' }],
    ['sin fuente', { promedio: 3.39 }],
  ])('respuesta fuera de contrato (%s) → null, jamás inventa TC', async (_caso, data) => {
    invoke.mockResolvedValue({ data, error: null })
    const { result } = renderHook(() => useTipoCambio())
    // El hook arranca en null y DEBE seguir en null: se espera al ciclo del efecto.
    await waitFor(() => expect(invoke).toHaveBeenCalled())
    await waitFor(() => expect(result.current).toBeNull())
  })

  it('error de la edge (BCRP caído) → null y la meta degrada a solo-PEN', async () => {
    invoke.mockResolvedValue({ data: null, error: new Error('502') })
    const { result } = renderHook(() => useTipoCambio())
    await waitFor(() => expect(invoke).toHaveBeenCalled())
    await waitFor(() => expect(result.current).toBeNull())
  })
})
