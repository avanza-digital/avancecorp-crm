// El hook que decide la FUENTE de la tabla de Cartera (F2). Las dos cosas que
// se prueban son las dos que romperían el producto sin que ningún tipo se
// queje: que en demo no salga NI UN request (fail-closed) y que en sesión real
// «hay más» lo diga el cursor del servidor, no el tamaño de la última página.
import { createElement, type ReactNode } from 'react'
import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { TAMANO_PAGINA_CARTERA } from '@/lib/cartera-keyset'
import type { Lead } from '@/lib/tipos'

const mocks = vi.hoisted(() => ({
  listarCarteraPagina: vi.fn(),
  yo: { id: 'u-1', rol: 'vendedor', demo: false } as { id: string; rol: string; demo: boolean } | null,
}))

vi.mock('@/lib/supabase', () => ({ sb: null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: mocks.yo }) }))
vi.mock('./crm-api', async (importOriginal) => ({
  ...await importOriginal<typeof import('./crm-api')>(),
  listarCarteraPagina: mocks.listarCarteraPagina,
}))

const { useCarteraPaginada } = await import('./use-cartera-paginada')

function lead(i: number): Lead {
  return {
    id: `lead-${String(i).padStart(3, '0')}`,
    nombre_completo: `LEAD ${i}`,
    telefono: `98765${String(i).padStart(4, '0')}`,
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 1000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: '2026-08-01T00:00:00.000Z',
    actualizado_en: new Date(Date.UTC(2026, 7, 1) - i * 60_000).toISOString(),
    activo: true,
  }
}

function arnes() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client: cliente }, children)
  return { wrapper }
}

beforeEach(() => {
  vi.clearAllMocks()
  mocks.yo = { id: 'u-1', rol: 'vendedor', demo: false }
})

describe('sesión demo', () => {
  const ambito = Array.from({ length: TAMANO_PAGINA_CARTERA + 10 }, (_, i) => lead(i))

  beforeEach(() => { mocks.yo = { id: 'u-demo', rol: 'vendedor', demo: true } })

  it('pagina el ámbito vivo del store sin tocar la red', () => {
    const { wrapper } = arnes()
    const { result } = renderHook(() => useCarteraPaginada(ambito, {}), { wrapper })

    expect(mocks.listarCarteraPagina).not.toHaveBeenCalled()
    expect(result.current.leads).toHaveLength(TAMANO_PAGINA_CARTERA)
    expect(result.current.hayMas).toBe(true)
    // El total corresponde a TODOS los resultados, no a las 50 filas cargadas.
    expect(result.current.resumenDemo?.totales.vivos).toBe(60)
    expect(result.current.resumenDemo?.capital.asignado.pen).toBe(60_000)
  })

  it('«cargar más» amplía la ventana en memoria hasta agotar el ámbito', () => {
    const { wrapper } = arnes()
    const { result } = renderHook(() => useCarteraPaginada(ambito, {}), { wrapper })

    act(() => { result.current.cargarMas() })

    expect(result.current.leads).toHaveLength(ambito.length)
    expect(result.current.hayMas).toBe(false)
    expect(mocks.listarCarteraPagina).not.toHaveBeenCalled()
  })

  it('aplica los filtros con las MISMAS reglas que el servidor', () => {
    const { wrapper } = arnes()
    const { result } = renderHook(
      () => useCarteraPaginada([lead(1), { ...lead(2), nombre_completo: 'ANA TORRES' }], { texto: 'ana' }),
      { wrapper },
    )

    expect(result.current.leads.map((l) => l.nombre_completo)).toEqual(['ANA TORRES'])
  })

  it('el origen recorta el ámbito demo con la misma regla que el servidor, sin red', () => {
    const { wrapper } = arnes()
    const { result } = renderHook(
      () => useCarteraPaginada([lead(1), { ...lead(2), origen: 'web' }], { origen: 'web' }),
      { wrapper },
    )
    expect(result.current.leads.map((l) => l.id)).toEqual(['lead-002'])
    expect(result.current.resumenDemo?.totales.vivos).toBe(1)
    expect(mocks.listarCarteraPagina).not.toHaveBeenCalled()
  })

  // La gestión se decide con el timeline, y este espejo solo conoce leads: en
  // demo NO recorta (lo hace el Pipeline con `columnaDeLead`). Se fija para que
  // nadie cuente con un filtro que aquí no existe — y para que siga sin red.
  it('la gestión no saca ni un request en demo y no recorta la foto', () => {
    const { wrapper } = arnes()
    const foto = [lead(1), lead(2), lead(3)]
    const { result } = renderHook(
      () => useCarteraPaginada(foto, { etapa: 'nuevo', gestion: 'con_gestion', integrada: true }),
      { wrapper },
    )

    expect(mocks.listarCarteraPagina).not.toHaveBeenCalled()
    expect(result.current.leads).toHaveLength(3)
  })

  it('cambiar de filtro devuelve la lista a la primera página', () => {
    const { wrapper } = arnes()
    const { rerender, result } = renderHook(
      ({ texto }: { texto: string }) => useCarteraPaginada(ambito, { texto }),
      { initialProps: { texto: '' }, wrapper },
    )
    act(() => { result.current.cargarMas() })
    expect(result.current.leads).toHaveLength(ambito.length)

    rerender({ texto: 'LEAD' })

    expect(result.current.leads).toHaveLength(TAMANO_PAGINA_CARTERA)
  })

  it('recepción filtra la colección completa antes de contar y paginar', () => {
    const { wrapper } = arnes()
    const recibidos = ambito.map((l, i) => ({ ...l, tenencia_desde: i < 55
      ? '2026-09-01T12:00:00-05:00' : '2026-09-02T12:00:00-05:00' }))
    const { rerender, result } = renderHook(
      ({ dia }) => useCarteraPaginada(recibidos, { recepcionDemo: { desde: dia, hasta: dia } }),
      { initialProps: { dia: '2026-09-01' }, wrapper },
    )
    expect(result.current.leads).toHaveLength(50)
    expect(result.current.resumenDemo?.totales.vivos).toBe(55)
    act(() => result.current.cargarMas())
    expect(result.current.leads).toHaveLength(55)
    rerender({ dia: '2026-09-02' })
    expect(result.current.leads).toHaveLength(5)
    expect(result.current.resumenDemo?.totales.vivos).toBe(5)
    expect(result.current.hayMas).toBe(false)
    expect(mocks.listarCarteraPagina).not.toHaveBeenCalled()
  })
})

describe('sesión real', () => {
  it('las fechas cambian la consulta completa y un rango inválido no consulta', async () => {
    mocks.listarCarteraPagina.mockResolvedValue({ items: [lead(0)], cursor: null })
    const { wrapper } = arnes()
    const { rerender } = renderHook(({ desde, hasta }) => useCarteraPaginada([], { recepcion: { desde, hasta } }),
      { initialProps: { desde: '2026-09-01', hasta: '2026-09-01' }, wrapper })
    await waitFor(() => expect(mocks.listarCarteraPagina).toHaveBeenCalledTimes(1))
    expect(mocks.listarCarteraPagina.mock.calls[0]![0]).toMatchObject({ integrada: true, recepcion: { desde: '2026-09-01', hasta: '2026-09-01' } })
    rerender({ desde: '2026-09-02', hasta: '2026-09-02' })
    await waitFor(() => expect(mocks.listarCarteraPagina).toHaveBeenCalledTimes(2))
    expect(mocks.listarCarteraPagina.mock.calls[1]![1]).toBeNull()
    rerender({ desde: '2026-09-03', hasta: '2026-09-01' })
    expect(mocks.listarCarteraPagina).toHaveBeenCalledTimes(2)
  })
  it('concatena páginas y pide la siguiente con el cursor que dio el servidor', async () => {
    mocks.listarCarteraPagina
      .mockResolvedValueOnce({
        items: [lead(0), lead(1)],
        cursor: { actualizadoEn: lead(1).actualizado_en, id: lead(1).id },
      })
      .mockResolvedValueOnce({ items: [lead(2)], cursor: null })
    const { wrapper } = arnes()
    const { result } = renderHook(() => useCarteraPaginada([], {}), { wrapper })

    await waitFor(() => { expect(result.current.leads).toHaveLength(2) })
    expect(result.current.hayMas).toBe(true)

    act(() => { result.current.cargarMas() })

    await waitFor(() => { expect(result.current.leads).toHaveLength(3) })
    // La segunda llamada viaja con el cursor de la última fila de la primera.
    expect(mocks.listarCarteraPagina.mock.calls[1]![1]).toEqual({
      actualizadoEn: lead(1).actualizado_en,
      id: lead(1).id,
    })
    // Y el servidor cerró la lista: nada de ofrecer una página que no existe.
    expect(result.current.hayMas).toBe(false)
  })

  it('cambiar de origen tras varias páginas empieza una lista nueva desde el cursor inicial', async () => {
    mocks.listarCarteraPagina
      .mockResolvedValueOnce({
        items: [lead(0), lead(1)],
        cursor: { actualizadoEn: lead(1).actualizado_en, id: lead(1).id },
      })
      .mockResolvedValueOnce({ items: [lead(2)], cursor: null })
      .mockResolvedValueOnce({ items: [{ ...lead(5), origen: 'web' }], cursor: null })
    const { wrapper } = arnes()
    const inicial: { origen: 'todos' | 'web' } = { origen: 'todos' }
    const { result, rerender } = renderHook(
      ({ origen }: { origen: 'todos' | 'web' }) => useCarteraPaginada([], { origen }),
      { initialProps: inicial, wrapper },
    )
    await waitFor(() => { expect(result.current.leads).toHaveLength(2) })
    act(() => { result.current.cargarMas() })
    await waitFor(() => { expect(result.current.leads).toHaveLength(3) })

    rerender({ origen: 'web' })

    // Consulta propia (clave nueva) y SIN cursor: no se reutiliza el de la lista anterior.
    await waitFor(() => { expect(mocks.listarCarteraPagina).toHaveBeenCalledTimes(3) })
    expect(mocks.listarCarteraPagina.mock.calls[2]![0]).toMatchObject({ integrada: true, origen: 'web' })
    expect(mocks.listarCarteraPagina.mock.calls[2]![1]).toBeNull()
    await waitFor(() => { expect(result.current.leads.map((l) => l.id)).toEqual(['lead-005']) })
    expect(result.current.hayMas).toBe(false)
  })

  // P1 de Codex (19/09): la procedencia tiene que estar en la CLAVE de la
  // consulta. Si solo cambiara el request, TanStack Query serviría la lista
  // anterior sin pedir nada y el filtro «funcionaría» en silencio: no.
  it('cambiar de procedencia tras varias páginas es una consulta nueva desde el cursor inicial', async () => {
    mocks.listarCarteraPagina
      .mockResolvedValueOnce({
        items: [lead(0), lead(1)],
        cursor: { actualizadoEn: lead(1).actualizado_en, id: lead(1).id },
      })
      .mockResolvedValueOnce({ items: [lead(2)], cursor: null })
      .mockResolvedValueOnce({ items: [{ ...lead(7), procedencia: 'manual', cargado_por: 'v-1' }], cursor: null })
      .mockResolvedValueOnce({ items: [{ ...lead(0), procedencia: 'sistema', cargado_por: null }], cursor: null })
    const { wrapper } = arnes()
    const inicial: { procedencia: 'todas' | 'manual' | 'sistema' } = { procedencia: 'todas' }
    const { result, rerender } = renderHook(
      ({ procedencia }: { procedencia: 'todas' | 'manual' | 'sistema' }) => useCarteraPaginada([], { procedencia }),
      { initialProps: inicial, wrapper },
    )
    await waitFor(() => { expect(result.current.leads).toHaveLength(2) })
    // «todas» no viaja: el primer request no lleva procedencia.
    expect(mocks.listarCarteraPagina.mock.calls[0]![0]).not.toHaveProperty('procedencia')
    act(() => { result.current.cargarMas() })
    await waitFor(() => { expect(result.current.leads).toHaveLength(3) })

    rerender({ procedencia: 'manual' })
    await waitFor(() => { expect(mocks.listarCarteraPagina).toHaveBeenCalledTimes(3) })
    expect(mocks.listarCarteraPagina.mock.calls[2]![0]).toMatchObject({ integrada: true, procedencia: 'manual' })
    expect(mocks.listarCarteraPagina.mock.calls[2]![1]).toBeNull()
    await waitFor(() => { expect(result.current.leads.map((l) => l.id)).toEqual(['lead-007']) })

    // Sistema y manual son listas distintas entre sí, no solo distintas de «todas».
    rerender({ procedencia: 'sistema' })
    await waitFor(() => { expect(mocks.listarCarteraPagina).toHaveBeenCalledTimes(4) })
    expect(mocks.listarCarteraPagina.mock.calls[3]![0]).toMatchObject({ integrada: true, procedencia: 'sistema' })
    await waitFor(() => { expect(result.current.leads.map((l) => l.id)).toEqual(['lead-000']) })
  })

  it('activar reasignados reinicia el cursor y usa una clave de consulta distinta', async () => {
    mocks.listarCarteraPagina
      .mockResolvedValueOnce({ items: [lead(0)], cursor: { actualizadoEn: lead(0).actualizado_en, id: lead(0).id } })
      .mockResolvedValueOnce({ items: [lead(1)], cursor: null })
      .mockResolvedValueOnce({ items: [{ ...lead(2), reasignado: true }], cursor: null })
    const { wrapper } = arnes()
    const { result, rerender } = renderHook(
      ({ reasignados }: { reasignados: boolean }) => useCarteraPaginada([], { reasignados }),
      { initialProps: { reasignados: false }, wrapper },
    )
    await waitFor(() => { expect(result.current.leads).toHaveLength(1) })
    act(() => { result.current.cargarMas() })
    await waitFor(() => { expect(result.current.leads).toHaveLength(2) })
    rerender({ reasignados: true })
    await waitFor(() => { expect(mocks.listarCarteraPagina).toHaveBeenCalledTimes(3) })
    expect(mocks.listarCarteraPagina.mock.calls[2]![0]).toMatchObject({ reasignados: true })
    expect(mocks.listarCarteraPagina.mock.calls[2]![1]).toBeNull()
    await waitFor(() => { expect(result.current.leads.map((l) => l.id)).toEqual(['lead-002']) })
  })

  // 01/10/2026 — «Nuevo» y «Gestionado» del Pipeline piden la MISMA etapa y el
  // mismo analista; solo las separa la gestión. Si la gestión no estuviera en
  // la clave de la consulta compartirían caché: una sola petición y las dos
  // columnas pintando la misma lista, sin que ningún tipo se queje.
  it('dos columnas de la misma etapa con distinta gestión son dos consultas, cada una con su lista', async () => {
    const nuevo = { ...lead(1), nombre_completo: 'SIN INTENTOS' }
    const gestionado = { ...lead(2), nombre_completo: 'YA INTENTADO' }
    mocks.listarCarteraPagina.mockImplementation(async (filtros: { gestion?: string }) => ({
      items: filtros.gestion === 'con_gestion' ? [gestionado] : [nuevo],
      cursor: null,
      resumen: { totales: { vivos: 1 } },
    }))
    const { wrapper } = arnes()
    // MISMO QueryClient para las dos, como en el tablero.
    const { result } = renderHook(() => ({
      nuevo: useCarteraPaginada([], { etapa: 'nuevo', vendedorId: 'v-1', gestion: 'sin_gestion', integrada: true }),
      gestionado: useCarteraPaginada([], { etapa: 'nuevo', vendedorId: 'v-1', gestion: 'con_gestion', integrada: true }),
    }), { wrapper })

    await waitFor(() => {
      expect(result.current.nuevo.leads.map((l) => l.nombre_completo)).toEqual(['SIN INTENTOS'])
      expect(result.current.gestionado.leads.map((l) => l.nombre_completo)).toEqual(['YA INTENTADO'])
    })
    expect(mocks.listarCarteraPagina).toHaveBeenCalledTimes(2)
    expect(mocks.listarCarteraPagina.mock.calls.map(([filtros]) => filtros)).toEqual([
      { integrada: true, etapa: 'nuevo', vendedorId: 'v-1', texto: '', gestion: 'sin_gestion' },
      { integrada: true, etapa: 'nuevo', vendedorId: 'v-1', texto: '', gestion: 'con_gestion' },
    ])
  })

  it('sin gestión, el filtro no viaja: ni la clave ni el request la llevan', async () => {
    mocks.listarCarteraPagina.mockResolvedValue({ items: [], cursor: null })
    const { wrapper } = arnes()
    renderHook(() => useCarteraPaginada([], { etapa: 'contactado', vendedorId: 'v-1', integrada: true }), { wrapper })

    await waitFor(() => { expect(mocks.listarCarteraPagina).toHaveBeenCalled() })
    expect(mocks.listarCarteraPagina.mock.calls[0]![0]).not.toHaveProperty('gestion')
  })

  it('cambiar de gestión tras varias páginas empieza una lista nueva desde el cursor inicial', async () => {
    mocks.listarCarteraPagina
      .mockResolvedValueOnce({ items: [lead(0)], cursor: { actualizadoEn: lead(0).actualizado_en, id: lead(0).id } })
      .mockResolvedValueOnce({ items: [lead(1)], cursor: null })
      .mockResolvedValueOnce({ items: [lead(7)], cursor: null })
    const { wrapper } = arnes()
    const inicial: { gestion: 'sin_gestion' | 'con_gestion' } = { gestion: 'sin_gestion' }
    const { result, rerender } = renderHook(
      ({ gestion }: { gestion: 'sin_gestion' | 'con_gestion' }) => useCarteraPaginada([], { etapa: 'nuevo', gestion }),
      { initialProps: inicial, wrapper },
    )
    await waitFor(() => { expect(result.current.leads).toHaveLength(1) })
    act(() => { result.current.cargarMas() })
    await waitFor(() => { expect(result.current.leads).toHaveLength(2) })

    rerender({ gestion: 'con_gestion' })

    await waitFor(() => { expect(mocks.listarCarteraPagina).toHaveBeenCalledTimes(3) })
    expect(mocks.listarCarteraPagina.mock.calls[2]![0]).toMatchObject({ etapa: 'nuevo', gestion: 'con_gestion' })
    expect(mocks.listarCarteraPagina.mock.calls[2]![1]).toBeNull()
    await waitFor(() => { expect(result.current.leads.map((l) => l.id)).toEqual(['lead-007']) })
  })

  // ESTADO DE PRODUCCIÓN: un servidor que aún no conoce `p_gestion` rechaza las
  // dos listas que lo mandan. La columna que falla expone su error; la vecina,
  // que no lo manda, sigue sirviendo — un fallo no arrastra al otro.
  it('una lista caída no tumba a la vecina: cada columna expone su propio estado', async () => {
    mocks.listarCarteraPagina.mockImplementation(async (filtros: { gestion?: string }) => {
      if (filtros.gestion) throw new Error('PGRST202')
      return { items: [lead(3)], cursor: null, resumen: { totales: { vivos: 1 } } }
    })
    const { wrapper } = arnes()
    const { result } = renderHook(() => ({
      gestionado: useCarteraPaginada([], { etapa: 'nuevo', gestion: 'con_gestion', integrada: true }),
      contactado: useCarteraPaginada([], { etapa: 'contactado', integrada: true }),
    }), { wrapper })

    await waitFor(() => { expect(result.current.gestionado.error).toBeTruthy() })
    await waitFor(() => { expect(result.current.contactado.leads).toHaveLength(1) })
    // Sin datos y sin total: quien pinta la columna no tiene de dónde sacar un cero.
    expect(result.current.gestionado.leads).toEqual([])
    expect(result.current.gestionado.resumen).toBeUndefined()
    expect(result.current.gestionado.hayMas).toBe(false)
    expect(result.current.contactado.error).toBeNull()
    expect(result.current.contactado.resumen?.totales.vivos).toBe(1)
  })

  it('una página llena SIN cursor no promete más páginas', async () => {
    mocks.listarCarteraPagina.mockResolvedValue({
      items: Array.from({ length: TAMANO_PAGINA_CARTERA }, (_, i) => lead(i)),
      cursor: null,
    })
    const { wrapper } = arnes()
    const { result } = renderHook(() => useCarteraPaginada([], {}), { wrapper })

    await waitFor(() => { expect(result.current.leads).toHaveLength(TAMANO_PAGINA_CARTERA) })
    expect(result.current.hayMas).toBe(false)
  })

  it('ignora el ámbito del store: en real la verdad es el servidor', async () => {
    mocks.listarCarteraPagina.mockResolvedValue({ items: [], cursor: null })
    const { wrapper } = arnes()
    const { result } = renderHook(
      () => useCarteraPaginada([lead(1), lead(2)], {}),
      { wrapper },
    )

    await waitFor(() => { expect(result.current.cargando).toBe(false) })
    expect(result.current.leads).toEqual([])
  })

  it('con la RPC caída no promete más páginas y expone el error', async () => {
    mocks.listarCarteraPagina.mockRejectedValue(new Error('RPC caída'))
    const { wrapper } = arnes()
    const { result } = renderHook(() => useCarteraPaginada([], {}), { wrapper })

    await waitFor(() => { expect(result.current.error).toBeTruthy() })
    expect(result.current.hayMas).toBe(false)
    expect(result.current.leads).toEqual([])
  })

  it('los filtros viajan al servidor, no se aplican sobre lo ya cargado', async () => {
    mocks.listarCarteraPagina.mockResolvedValue({ items: [], cursor: null })
    const { wrapper } = arnes()
    renderHook(
      () => useCarteraPaginada([], { etapa: 'convertido', vendedorId: 'v-9', texto: 'ro', origen: 'formulario' }),
      { wrapper },
    )

    await waitFor(() => { expect(mocks.listarCarteraPagina).toHaveBeenCalled() })
    expect(mocks.listarCarteraPagina.mock.calls[0]![0]).toEqual({
      integrada: true,
      etapa: 'convertido',
      vendedorId: 'v-9',
      texto: 'ro',
      origen: 'formulario',
    })
  })
})
