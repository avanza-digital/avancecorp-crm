import { StrictMode } from 'react'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import * as v from 'valibot'
import { cumplimientoDesdeRpc, CumplimientoMetasV2Schema, objetivosCero } from '@/lib/objetivos'
import valorado from '@/lib/__fixtures__/capital-valorado/activo.json'
import { useDatosSupervisor } from './datos-supervisor'

const rpc = v.parse(CumplimientoMetasV2Schema, valorado)
const supervisor = rpc.vendedores[0]!.supervisor_id!
let actor = { id: supervisor, demo: false }
let ahora = Date.parse('2026-10-18T17:00:00Z')
const recargar = vi.fn<() => Promise<boolean>>()
const conversion = vi.fn(async () => {})
const tipoCambio = vi.fn()
const crearStore = () => ({ ambito: { leads: [], vendedores: [] }, actividades: [], equipo: [],
  objetivos: objetivosCero('2026-10-01'), objetivosError: false,
  cumplimientoMetas: cumplimientoDesdeRpc(rpc, supervisor), cumplimientoMetasError: false, recargar })
let store = crearStore()
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: actor }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => ahora }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => store }))
vi.mock('@/data/use-resumen-cartera-operativo', () => ({ useResumenCarteraOperativo: () => ({ resumen: null }) }))
vi.mock('@/data/use-metricas-vendedores-operativas', () => ({ useMetricasVendedoresOperativas: () => ({ metricas: null }) }))
vi.mock('@/lib/tipo-cambio', async importOriginal => ({ ...await importOriginal<typeof import('@/lib/tipo-cambio')>(), useTipoCambio: () => ({ tc: { promedio: 3.75, fuente: 'fixture' }, recargar: tipoCambio }) }))
vi.mock('@/data/crm-queries', () => ({ useConversionMensual: () => ({ data: null, isPending: false, isError: false, refetch: conversion }), useMetricasAgenda: () => ({ data: null }) }))
const useDatosPrueba = () => useDatosSupervisor({ conConsultaOperativa: false })
beforeEach(() => {
  vi.clearAllMocks(); recargar.mockReset(); recargar.mockResolvedValue(true)
  actor = { id: supervisor, demo: false }; ahora = Date.parse('2026-10-18T17:00:00Z'); store = crearStore()
})

describe('refresco mensual de la jornada', () => {
  it.each(['false', 'rechazo'])('retira la confirmación de la foto vigente tras %s y se recupera al reintentar', async modo => {
    const { result } = renderHook(useDatosPrueba)
    expect(result.current.cumplimientoMensualError).toBe(false)
    if (modo === 'false') recargar.mockResolvedValue(false)
    else recargar.mockRejectedValueOnce(new Error('sin red'))
    await act(() => result.current.recargarMensual())
    expect(result.current.cumplimientoMensualError).toBe(true)
    expect(result.current.objetivosMensualesError).toBe(true)
    expect(result.current.hayErrorMensual).toBe(true)
    recargar.mockResolvedValue(true)
    act(() => result.current.reintentarMensual())
    await waitFor(() => expect(result.current.cumplimientoMensualError).toBe(false))
    expect(result.current.objetivosMensualesError).toBe(false)
    expect(tipoCambio).not.toHaveBeenCalled()
  })
  it('el refresco automático y manual comparten la petición mensual en curso', async () => {
    let resolver!: (ok: boolean) => void
    recargar.mockImplementationOnce(() => new Promise(resolve => { resolver = resolve }))
    const { result } = renderHook(useDatosPrueba)
    let uno!: Promise<void>, dos!: Promise<void>
    act(() => { uno = result.current.recargarMensual(); dos = result.current.recargarMensual() })
    await waitFor(() => expect(recargar).toHaveBeenCalledOnce())
    await act(async () => { resolver(true); await Promise.all([uno, dos]) })
    expect(result.current.cumplimientoMensualError).toBe(false)
  })
  it('un cambio de mes fallido acaba en error recuperable, no en carga perpetua ni cifras del mes anterior', async () => {
    ahora = Date.parse('2026-11-01T05:01:00Z'); recargar.mockResolvedValue(false)
    const { result, rerender } = renderHook(useDatosPrueba)
    await waitFor(() => expect(result.current.cumplimientoMensualError).toBe(true))
    expect(result.current.fotoMensualStoreCargando).toBe(false)
    expect(result.current.cumplimientoMensual).toBeNull()
    act(() => result.current.reintentarMensual())
    await waitFor(() => expect(recargar).toHaveBeenCalledTimes(4))
    expect(result.current.fotoMensualStoreCargando).toBe(false)
    recargar.mockImplementation(async () => {
      store = { ...store, objetivos: objetivosCero('2026-11-01'), cumplimientoMetas: { ...store.cumplimientoMetas, periodo: '2026-11-01' } }; return true
    })
    await act(() => result.current.recargarMensual()); rerender()
    expect(result.current.hayErrorMensual).toBe(false)
    expect(result.current.fotoMensualStoreCargando).toBe(false)
  })
  it('el remonte de efectos en StrictMode no deja un cambio de mes cargando para siempre', async () => {
    ahora = Date.parse('2026-11-01T05:01:00Z'); recargar.mockResolvedValue(false)
    const { result } = renderHook(useDatosPrueba, { wrapper: ({ children }) => <StrictMode>{children}</StrictMode> })
    await waitFor(() => expect(result.current.cumplimientoMensualError).toBe(true))
    expect(result.current.fotoMensualStoreCargando).toBe(false)
    expect(recargar).toHaveBeenCalledTimes(2)
  })
  it('una respuesta tardía de otra sesión no borra el fallo del actor actual', async () => {
    let resolver!: (ok: boolean) => void
    recargar.mockImplementationOnce(() => new Promise(resolve => { resolver = resolve }))
    const { result, rerender } = renderHook(useDatosPrueba)
    let anterior!: Promise<void>
    act(() => { anterior = result.current.recargarMensual() })
    await waitFor(() => expect(recargar).toHaveBeenCalledOnce())
    actor = { id: 'otro', demo: false }; rerender()
    recargar.mockResolvedValue(false)
    await act(() => result.current.recargarMensual())
    expect(result.current.cumplimientoMensualError).toBe(true)
    await act(async () => { resolver(true); await anterior })
    expect(result.current.cumplimientoMensualError).toBe(true)
  })
  it('recupera la disponibilidad si el store actualiza la foto por foco u otra acción', async () => {
    const { result, rerender } = renderHook(useDatosPrueba)
    recargar.mockResolvedValue(false)
    await act(() => result.current.recargarMensual())
    expect(result.current.cumplimientoMensualError).toBe(true)
    store = { ...store, objetivos: { ...store.objetivos }, cumplimientoMetas: { ...store.cumplimientoMetas } }
    rerender()
    expect(result.current.hayErrorMensual).toBe(false)
  })
  it('recupera un descarte temporal del store con un único segundo intento', async () => {
    const { result } = renderHook(useDatosPrueba)
    recargar.mockResolvedValueOnce(false).mockResolvedValueOnce(true)
    await act(() => result.current.recargarMensual())
    expect(recargar).toHaveBeenCalledTimes(2)
    expect(result.current.hayErrorMensual).toBe(false)
  })
  it('la actualización de una demo no consulta datos reales', async () => {
    actor = { id: 'd-sup1', demo: true }
    const { result } = renderHook(useDatosPrueba)
    await act(() => result.current.recargarMensual())
    expect(recargar).not.toHaveBeenCalled(); expect(conversion).not.toHaveBeenCalled()
  })
})
