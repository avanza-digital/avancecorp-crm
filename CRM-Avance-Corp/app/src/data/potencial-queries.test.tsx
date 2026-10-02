// Hooks del potencial: de dónde sale la marca en cada mundo (demo, sesión real,
// pantalla sin proveedor), cómo se comparte entre vistas y qué pasa al marcar
// (optimista, vuelta atrás con aviso y relectura del servidor).
import type { ReactNode } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { toast } from 'sonner'
import { reiniciarPotencialDemo } from '@/lib/potencial-demo'
import type { PotencialLead, PotencialLeads } from '@/lib/potencial'

let YO: { id: string; rol: string; demo: boolean } | null = null
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('sonner', () => ({ toast: { error: vi.fn(), success: vi.fn() } }))
const api = vi.hoisted(() => ({ obtenerPotencialLeads: vi.fn(), marcarPotencialLead: vi.fn() }))
vi.mock('./potencial-api', () => api)

const { potencialKeys, useMarcarPotencial, usePotencialLead, usePotencialLeads } = await import('./potencial-queries')
const { crmQueryKeys } = await import('./crm-queries')
const { CrmApiError } = await import('./crm-api')

const A = '11111111-1111-4111-8111-111111111111'
const B = '22222222-2222-4222-8222-222222222222'

function item(leadId: string, sobre: Partial<PotencialLead> = {}): PotencialLead {
  return {
    lead_id: leadId, nivel: null, origen: null, nivel_marcado: null, marcado_en: null,
    dias_sin_gestion: null, baja_a: null, baja_el: null, puede_marcar: true, ...sobre,
  }
}
const encendido = (items: PotencialLead[]): PotencialLeads => ({ version: 1, habilitada: true, items })

function conProveedor() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
  return { cliente, wrapper }
}

beforeEach(() => {
  YO = { id: 'v-1', rol: 'vendedor', demo: false }
  api.obtenerPotencialLeads.mockReset()
  api.marcarPotencialLead.mockReset()
})
afterEach(() => { reiniciarPotencialDemo() })

describe('claves de caché', () => {
  it('cuelgan del prefijo de leads: lo que invalida una mutación de lead también refresca el potencial', () => {
    const prefijo = crmQueryKeys.leads()
    expect(potencialKeys.raiz().slice(0, prefijo.length)).toEqual([...prefijo])
    expect(potencialKeys.leads([A]).slice(0, potencialKeys.raiz().length)).toEqual([...potencialKeys.raiz()])
  })

  it('la clave de las listas de la cartera es el prefijo exacto de `crmQueryKeys.carteraPagina`', () => {
    // Se escribe literal en este módulo (no importa crm-queries): si alguien renombra
    // la clave de la cartera, marcar dejaría de refrescar los conteos de Leads.
    const deLaCartera = crmQueryKeys.carteraPagina('todas', 'todos', '', true)
    expect(deLaCartera.slice(0, potencialKeys.cartera().length)).toEqual([...potencialKeys.cartera()])
    // Y no es el prefijo del potencial: invalidar uno no arrastra al otro.
    expect(potencialKeys.cartera()).not.toEqual(potencialKeys.raiz())
  })
})

describe('usePotencialLeads · sesión real', () => {
  it('pide los leads en pantalla una vez, normalizados, y los indexa por lead', async () => {
    api.obtenerPotencialLeads.mockResolvedValue(encendido([item(A, { nivel: 'estrella', origen: 'manual', nivel_marcado: 'estrella' }), item(B)]))
    const { wrapper } = conProveedor()
    const { result, rerender } = renderHook(({ ids }) => usePotencialLeads(ids), { wrapper, initialProps: { ids: [B, A, B] } })
    expect(result.current.habilitada).toBe(false)
    await waitFor(() => expect(result.current.habilitada).toBe(true))
    expect(api.obtenerPotencialLeads).toHaveBeenCalledTimes(1)
    expect(api.obtenerPotencialLeads.mock.calls[0]?.[0]).toEqual([A, B])
    expect(result.current.porLead.get(A)?.nivel).toBe('estrella')
    expect(result.current.porLead.get(B)?.nivel).toBeNull()
    // Los mismos leads en otro orden comparten caché: no se vuelve a pedir.
    rerender({ ids: [A, B] })
    expect(api.obtenerPotencialLeads).toHaveBeenCalledTimes(1)
  })

  it('bandera apagada: no se pinta nada', async () => {
    api.obtenerPotencialLeads.mockResolvedValue({ version: 1, habilitada: false, items: [] })
    const { wrapper } = conProveedor()
    const { result } = renderHook(() => usePotencialLeads([A]), { wrapper })
    await waitFor(() => expect(api.obtenerPotencialLeads).toHaveBeenCalled())
    await act(async () => { await Promise.resolve() })
    expect(result.current.habilitada).toBe(false)
    expect(result.current.porLead.size).toBe(0)
  })

  it('si la lectura falla, la pantalla sigue sin el potencial (no se cae ni inventa marcas)', async () => {
    api.obtenerPotencialLeads.mockRejectedValue(new CrmApiError('No se pudo leer el potencial de los leads.', '42501'))
    const { wrapper } = conProveedor()
    const { result } = renderHook(() => usePotencialLeads([A]), { wrapper })
    await waitFor(() => expect(api.obtenerPotencialLeads).toHaveBeenCalled())
    await act(async () => { await Promise.resolve() })
    expect(result.current.habilitada).toBe(false)
  })

  it('sin leads en pantalla o sin sesión no pregunta', async () => {
    const { wrapper } = conProveedor()
    renderHook(() => usePotencialLeads([]), { wrapper })
    YO = null
    renderHook(() => usePotencialLeads([A]), { wrapper })
    await act(async () => { await Promise.resolve() })
    expect(api.obtenerPotencialLeads).not.toHaveBeenCalled()
  })

  it('una pantalla montada sin proveedor se queda con el potencial apagado, sin red', async () => {
    const { result } = renderHook(() => usePotencialLeads([A]))
    await act(async () => { await Promise.resolve() })
    expect(result.current.habilitada).toBe(false)
    expect(api.obtenerPotencialLeads).not.toHaveBeenCalled()
  })

  it('al cargar otra página conserva las marcas ya pintadas mientras llega la nueva', async () => {
    api.obtenerPotencialLeads.mockResolvedValueOnce(encendido([item(A, { nivel: 'tibio', origen: 'manual', nivel_marcado: 'tibio' })]))
    let entregar: (r: PotencialLeads) => void = () => {}
    api.obtenerPotencialLeads.mockImplementationOnce(() => new Promise<PotencialLeads>((resolver) => { entregar = resolver }))
    const { wrapper } = conProveedor()
    const { result, rerender } = renderHook(({ ids }) => usePotencialLeads(ids), { wrapper, initialProps: { ids: [A] } })
    await waitFor(() => expect(result.current.porLead.get(A)?.nivel).toBe('tibio'))
    rerender({ ids: [A, B] })
    expect(result.current.porLead.get(A)?.nivel).toBe('tibio')
    await act(async () => { entregar(encendido([item(A, { nivel: 'tibio', origen: 'manual', nivel_marcado: 'tibio' }), item(B, { nivel: 'frio', origen: 'manual', nivel_marcado: 'frio' })])) })
    await waitFor(() => expect(result.current.porLead.get(B)?.nivel).toBe('frio'))
  })
})

describe('usePotencialLead · la ficha se abre desde una lista', () => {
  it('empieza con lo que la lista ya sabe de ese lead y aun así pregunta por el suyo', async () => {
    const tibio = item(A, { nivel: 'tibio', origen: 'manual', nivel_marcado: 'tibio' })
    api.obtenerPotencialLeads.mockResolvedValueOnce(encendido([tibio, item(B)]))
    const { wrapper } = conProveedor()
    const lista = renderHook(() => usePotencialLeads([A, B]), { wrapper })
    await waitFor(() => expect(lista.result.current.habilitada).toBe(true))

    // La lectura propia de la ficha tarda: mientras, ya pinta lo de la lista.
    let entregar: (r: PotencialLeads) => void = () => {}
    api.obtenerPotencialLeads.mockImplementationOnce(() => new Promise<PotencialLeads>((resolver) => { entregar = resolver }))
    const ficha = renderHook(() => usePotencialLead(A), { wrapper })
    expect(ficha.result.current).toMatchObject({ habilitada: true, item: { nivel: 'tibio' } })
    await waitFor(() => expect(api.obtenerPotencialLeads).toHaveBeenCalledTimes(2))
    expect(api.obtenerPotencialLeads.mock.calls[1]?.[0]).toEqual([A])
    // Y cuando llega, manda lo del servidor.
    await act(async () => { entregar(encendido([item(A, { nivel: 'frio', origen: 'caducidad', nivel_marcado: 'tibio' })])) })
    await waitFor(() => expect(ficha.result.current.item?.nivel).toBe('frio'))
  })

  it('un lead que ninguna lista trae espera a su propia respuesta (no inventa «sin marca»)', async () => {
    api.obtenerPotencialLeads.mockResolvedValueOnce(encendido([item(B)]))
    const { wrapper } = conProveedor()
    const lista = renderHook(() => usePotencialLeads([B]), { wrapper })
    await waitFor(() => expect(lista.result.current.habilitada).toBe(true))
    api.obtenerPotencialLeads.mockImplementationOnce(() => new Promise<PotencialLeads>(() => {}))
    const ficha = renderHook(() => usePotencialLead(A), { wrapper })
    expect(ficha.result.current).toEqual({ habilitada: false, item: undefined })
  })

  it('con la bandera apagada en la lista, la ficha tampoco adelanta nada', async () => {
    api.obtenerPotencialLeads.mockResolvedValueOnce({ version: 1, habilitada: false, items: [] })
    const { wrapper } = conProveedor()
    renderHook(() => usePotencialLeads([A]), { wrapper })
    await waitFor(() => expect(api.obtenerPotencialLeads).toHaveBeenCalledTimes(1))
    api.obtenerPotencialLeads.mockImplementationOnce(() => new Promise<PotencialLeads>(() => {}))
    const ficha = renderHook(() => usePotencialLead(A), { wrapper })
    expect(ficha.result.current).toEqual({ habilitada: false, item: undefined })
  })
})

describe('usePotencialLeads · demo', () => {
  it('encendido y sin red: marcas sembradas con la misma forma que el servidor', () => {
    YO = { id: 'd-v1', rol: 'vendedor', demo: true }
    const { result } = renderHook(() => usePotencialLeads(['l17', 'l15']))
    expect(result.current.habilitada).toBe(true)
    expect(result.current.porLead.get('l17')).toMatchObject({ nivel: 'estrella', origen: 'manual', puede_marcar: true })
    expect(result.current.porLead.get('l15')).toMatchObject({ nivel: null, puede_marcar: true })
    expect(api.obtenerPotencialLeads).not.toHaveBeenCalled()
  })

  it.each([['supervisor', true], ['gerencia', false], ['directorio', false], ['coordinador', false]])('en demo, %s puede marcar: %s', (rol, puede) => {
    YO = { id: 'd-x', rol, demo: true }
    const { result } = renderHook(() => usePotencialLeads(['l17']))
    expect(result.current.porLead.get('l17')?.puede_marcar).toBe(puede)
  })

  it('marcar en demo cambia la marca en todas las vistas que la miran y reinicia el reloj', () => {
    YO = { id: 'd-v1', rol: 'vendedor', demo: true }
    const lista = renderHook(() => usePotencialLeads(['l15', 'l17']))
    const ficha = renderHook(() => usePotencialLead('l15'))
    const accion = renderHook(() => useMarcarPotencial())
    expect(ficha.result.current.item?.nivel).toBeNull()
    act(() => { accion.result.current.marcar('l15', 'estrella') })
    expect(ficha.result.current.item).toMatchObject({ nivel: 'estrella', origen: 'manual', dias_sin_gestion: 0, baja_a: 'tibio' })
    expect(lista.result.current.porLead.get('l15')?.nivel).toBe('estrella')
    expect(api.marcarPotencialLead).not.toHaveBeenCalled()
  })
})

describe('useMarcarPotencial · sesión real', () => {
  let ultimoWrapper: ({ children }: { children: ReactNode }) => ReactNode = ({ children }) => children

  function montar() {
    const { cliente, wrapper } = conProveedor()
    ultimoWrapper = wrapper
    const lista = renderHook(() => usePotencialLeads([A, B]), { wrapper })
    const ficha = renderHook(() => usePotencialLead(A), { wrapper })
    const accion = renderHook(() => useMarcarPotencial(), { wrapper })
    return { cliente, lista, ficha, accion }
  }

  it('optimista: el NIVEL cambia al instante en la lista y en la ficha, sin predecir cuándo baja', async () => {
    api.obtenerPotencialLeads.mockImplementation(async (ids: string[]) => encendido(ids.map((x) => item(x))))
    const { lista, ficha, accion } = montar()
    await waitFor(() => expect(lista.result.current.habilitada && ficha.result.current.habilitada).toBe(true))
    let confirmar: () => void = () => {}
    api.marcarPotencialLead.mockImplementation(() => new Promise<void>((resolver) => { confirmar = resolver }))
    // La relectura posterior la entrega la prueba cuando quiera: así se ve qué hay en pantalla mientras tanto.
    const delServidor = item(A, { nivel: 'estrella', origen: 'manual', nivel_marcado: 'estrella', dias_sin_gestion: 0, baja_a: 'tibio', baja_el: '2026-10-09' })
    const relecturas: Array<() => void> = []
    api.obtenerPotencialLeads.mockImplementation((ids: string[]) => new Promise<PotencialLeads>((resolver) => {
      relecturas.push(() => resolver(encendido(ids.map((x) => (x === A ? delServidor : item(x))))))
    }))

    act(() => { accion.result.current.marcar(A, 'estrella') })
    await waitFor(() => expect(lista.result.current.porLead.get(A)?.nivel).toBe('estrella'))
    // Lo único cierto es el nivel y que el reloj vuelve a cero: la regla de caducidad NO se calcula aquí.
    expect(ficha.result.current.item).toEqual({
      lead_id: A, nivel: 'estrella', origen: 'manual', nivel_marcado: 'estrella', marcado_en: expect.any(String),
      dias_sin_gestion: 0, baja_a: null, baja_el: null, puede_marcar: true,
    })
    expect(lista.result.current.porLead.get(B)?.nivel).toBeNull()
    expect(api.marcarPotencialLead).toHaveBeenCalledWith(A, 'estrella')
    await waitFor(() => expect(accion.result.current.marcando).toBe(true))
    expect(relecturas).toHaveLength(0)

    // El servidor confirma: empieza la relectura y `marcando` SIGUE en true hasta que termina.
    await act(async () => { confirmar() })
    await waitFor(() => expect(relecturas.length).toBeGreaterThanOrEqual(2))
    expect(accion.result.current.marcando).toBe(true)
    expect(ficha.result.current.item).toMatchObject({ nivel: 'estrella', baja_a: null, baja_el: null })

    // Llega la relectura: lo que queda pintado es lo que dice el servidor.
    await act(async () => { for (const entregar of relecturas.splice(0)) entregar() })
    await waitFor(() => expect(accion.result.current.marcando).toBe(false))
    expect(ficha.result.current.item).toMatchObject({ nivel: 'estrella', baja_a: 'tibio', baja_el: '2026-10-09' })
    expect(lista.result.current.porLead.get(A)?.baja_el).toBe('2026-10-09')
    expect(toast.error).not.toHaveBeenCalled()
  })

  it('una marca aceptada deja viejas las listas de la cartera (conteos y filtro por potencial); una rechazada, no', async () => {
    api.obtenerPotencialLeads.mockImplementation(async (ids: string[]) => encendido(ids.map((x) => item(x))))
    const { cliente, lista, accion } = montar()
    await waitFor(() => expect(lista.result.current.habilitada).toBe(true))
    const sinFiltro = crmQueryKeys.carteraPagina('todas', 'todos', '', true)
    const tibio = crmQueryKeys.carteraPagina('todas', 'todos', '', true, null, null, 'todos', 'todas', false, null, 'tibio')
    const ajena = crmQueryKeys.leadsSinAsignar()
    for (const clave of [sinFiltro, tibio, ajena]) cliente.setQueryData(clave, { pages: [], pageParams: [] })

    api.marcarPotencialLead.mockRejectedValueOnce(new CrmApiError('Solo el analista del lead o su supervisor pueden marcar su potencial', '42501'))
    act(() => { accion.result.current.marcar(A, 'tibio') })
    await waitFor(() => expect(toast.error).toHaveBeenCalled())
    await waitFor(() => expect(accion.result.current.marcando).toBe(false))
    expect(cliente.getQueryState(sinFiltro)?.isInvalidated).toBe(false)

    api.marcarPotencialLead.mockResolvedValueOnce(undefined)
    act(() => { accion.result.current.marcar(A, 'tibio') })
    await waitFor(() => expect(cliente.getQueryState(sinFiltro)?.isInvalidated).toBe(true))
    expect(cliente.getQueryState(tibio)?.isInvalidated).toBe(true)
    // Solo las listas de la cartera: otras listas de leads no se tocan por una marca.
    expect(cliente.getQueryState(ajena)?.isInvalidated).toBe(false)
  })

  it('dos activaciones en el mismo instante mandan UNA sola marca, sin esperar a que la pantalla se repinte', async () => {
    api.obtenerPotencialLeads.mockImplementation(async (ids: string[]) => encendido(ids.map((x) => item(x))))
    const { ficha, accion } = montar()
    await waitFor(() => expect(ficha.result.current.habilitada).toBe(true))
    let confirmar: () => void = () => {}
    api.marcarPotencialLead.mockImplementation(() => new Promise<void>((resolver) => { confirmar = resolver }))

    // Doble clic: las dos llamadas salen de la MISMA función, antes de cualquier render.
    const { marcar } = accion.result.current
    act(() => { marcar(A, 'estrella'); marcar(A, 'tibio') })
    await waitFor(() => expect(api.marcarPotencialLead).toHaveBeenCalledTimes(1))
    expect(api.marcarPotencialLead).toHaveBeenCalledWith(A, 'estrella')
    // Mientras viaja, otra ficha (otra instancia del hook) tampoco puede mandar una segunda.
    const otra = renderHookConLaMismaCache()
    act(() => { otra.result.current.marcar(B, 'frio') })
    expect(api.marcarPotencialLead).toHaveBeenCalledTimes(1)

    // Terminada la primera, ya se puede marcar otra vez.
    await act(async () => { confirmar() })
    await waitFor(() => expect(accion.result.current.marcando).toBe(false))
    act(() => { accion.result.current.marcar(A, 'tibio') })
    await waitFor(() => expect(api.marcarPotencialLead).toHaveBeenCalledTimes(2))
    expect(api.marcarPotencialLead).toHaveBeenLastCalledWith(A, 'tibio')
    await act(async () => { confirmar() })

    function renderHookConLaMismaCache() {
      return renderHook(() => useMarcarPotencial(), { wrapper: ultimoWrapper })
    }
  })

  it('si el servidor rechaza la marca, se deshace y se avisa con su mensaje', async () => {
    const tibio = item(A, { nivel: 'tibio', origen: 'manual', nivel_marcado: 'tibio', dias_sin_gestion: 2, baja_a: 'frio', baja_el: '2026-10-12' })
    api.obtenerPotencialLeads.mockImplementation(async (ids: string[]) => encendido(ids.map((x) => (x === A ? tibio : item(x)))))
    const { lista, ficha, accion } = montar()
    await waitFor(() => expect(ficha.result.current.item?.nivel).toBe('tibio'))
    let rechazar: (e: Error) => void = () => {}
    api.marcarPotencialLead.mockImplementation(() => new Promise<void>((_ok, fallar) => { rechazar = fallar }))
    // La relectura posterior NO llega: lo que devuelva el Tibio solo puede ser la vuelta atrás.
    api.obtenerPotencialLeads.mockImplementation(() => new Promise<PotencialLeads>(() => {}))

    act(() => { accion.result.current.marcar(A, 'estrella') })
    await waitFor(() => expect(ficha.result.current.item?.nivel).toBe('estrella'))
    await act(async () => { rechazar(new CrmApiError('Solo el analista del lead o su supervisor pueden marcar su potencial.', 'SIN_PERMISO')) })
    await waitFor(() => expect(ficha.result.current.item?.nivel).toBe('tibio'))
    expect(lista.result.current.porLead.get(A)).toMatchObject({ nivel: 'tibio', dias_sin_gestion: 2 })
    expect(toast.error).toHaveBeenCalledWith('Solo el analista del lead o su supervisor pueden marcar su potencial.')
  })

  it('un fallo que no es de la capa de datos se avisa con un texto propio, nunca crudo', async () => {
    api.obtenerPotencialLeads.mockImplementation(async (ids: string[]) => encendido(ids.map((x) => item(x))))
    const { ficha, accion } = montar()
    await waitFor(() => expect(ficha.result.current.habilitada).toBe(true))
    api.marcarPotencialLead.mockRejectedValue(new TypeError('Failed to fetch'))
    act(() => { accion.result.current.marcar(A, 'frio') })
    await waitFor(() => expect(toast.error).toHaveBeenCalledWith('No se pudo guardar la marca de potencial.'))
    await waitFor(() => expect(ficha.result.current.item?.nivel).toBeNull())
  })
})
