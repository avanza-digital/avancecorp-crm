// La línea «Base: N rellamadas para hoy» de «Hoy» del analista (F3 de la Base para gestión): cuenta la MISMA
// lectura que abre el destino (`crm.obtener_base_gestion`, clave `crmQueryKeys.baseGestion(null, DIA)`), así que
// las dos pantallas comparten UNA petición. Fail-closed: cargando, error (42501 incluido), refresco fallido,
// foto de otro día o rol que no es analista ⇒ sin cifra (la pantalla no pinta nada). Contrato HTTP con MSW.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { delay, http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
import type { ReactNode } from 'react'
import type { Lead, Yo } from '@/lib/tipos'
import type { Rol } from '@/lib/roles'

const dobles = vi.hoisted(() => ({
  // Sábado 2026-10-03, 10:00 en Lima (15:00Z).
  ahora: Date.parse('2026-10-03T15:00:00Z'),
  yo: null as Yo | null,
  leads: [] as Lead[],
}))
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake', { auth: { persistSession: false } }) }
})
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ leads: dobles.leads }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => dobles.ahora }))

const { contarRellamadasHoy, useConteoBaseGestion } = await import('./use-conteo-base-gestion')
const { crmQueryKeys, useBaseGestion } = await import('./crm-queries')
const { filasDemoBaseGestion } = await import('@/lib/base-gestion')

const AHORA = Date.parse('2026-10-03T15:00:00Z')
/** El día de Lima de AHORA: va en la clave (Codex F4 r1). */
const DIA = '2026-10-03'
const RPC = 'http://supabase.test/rest/v1/rpc/obtener_base_gestion'
const servidor = setupServer()
let cuerpos: unknown[] = []

beforeAll(() => servidor.listen({ onUnhandledRequest: 'error' }))
beforeEach(() => {
  // Solo se finge el reloj de pared: `dataUpdatedAt` de TanStack sale de Date.now() y debe ser «hoy en Lima».
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(AHORA)
  dobles.ahora = AHORA
  dobles.yo = analista()
  dobles.leads = []
  cuerpos = []
})
afterEach(() => {
  servidor.resetHandlers()
  vi.useRealTimers()
})
afterAll(() => servidor.close())

function analista(over: Partial<Yo> = {}): Yo {
  return { id: '22222222-2222-4222-8222-222222222222', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: false, puede_contratar: true, ...over }
}

let n = 0
/** Una fila con la forma del servidor (la misma de crm-api-base-gestion-msw.test.ts). */
function fila(over: Record<string, unknown> = {}): Record<string, unknown> {
  n += 1
  return {
    lead_id: `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`,
    nombre_completo: `LEAD ${n}`,
    telefono: '+51987654321',
    distrito: null,
    origen: 'landing',
    categoria_interes: null,
    monto_estimado: '30000.00',
    moneda: 'USD',
    motivo_descarte: 'no_responde',
    descartado_en: '2026-09-20T14:00:00+00:00',
    dias_desde_descarte: 13,
    etapa_maxima: 'contactado',
    intentos: 1,
    ultimo_resultado: 'no_contesto',
    ultimo_intento_en: '2026-10-01T15:00:00+00:00',
    proxima_llamada_en: null,
    rellamada_hoy: false,
    enfriado_hasta: null,
    ciclo_n: 1,
    vendedor_id: '22222222-2222-4222-8222-222222222222',
    gestiona: 'ANALISTA UNO',
    ...over,
  }
}

/** La base del analista HOY a las 10:00 de Lima: 3 rellamadas que tocan hoy (2 ya pasaron su hora) y 2 que no. */
const BASE_CON_RELLAMADAS = [
  fila({ proxima_llamada_en: '2026-10-03T14:00:00+00:00', rellamada_hoy: true }), // hoy 09:00 → vencida
  fila({ proxima_llamada_en: '2026-10-03T21:00:00+00:00', rellamada_hoy: true }), // hoy 16:00 → a tiempo
  fila({ proxima_llamada_en: '2026-10-02T20:00:00+00:00', rellamada_hoy: true }), // ayer 15:00, sin hacer → vencida
  fila({ proxima_llamada_en: '2026-10-05T15:00:00+00:00', rellamada_hoy: false }), // el lunes
  fila(), // sin agendar
]

function responder(filas: unknown[]): void {
  servidor.use(
    http.post(RPC, async ({ request }) => {
      cuerpos.push(await request.json())
      return HttpResponse.json(filas)
    }),
  )
}

function clienteDePrueba(): QueryClient {
  return new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: Infinity } } })
}

function envoltorio(cliente: QueryClient) {
  return function Envoltorio({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
  }
}

function montar(cliente: QueryClient = clienteDePrueba()) {
  return { cliente, ...renderHook(() => useConteoBaseGestion(), { wrapper: envoltorio(cliente) }) }
}

describe('contarRellamadasHoy (pura)', () => {
  it('cuenta solo `rellamada_hoy` y marca vencidas las que ya pasaron su hora', () => {
    const filas = [
      { rellamada_hoy: true, proxima_llamada_en: '2026-10-03T14:59:00Z' }, // un minuto antes → vencida
      { rellamada_hoy: true, proxima_llamada_en: '2026-10-03T15:00:00Z' }, // justo ahora → aún no
      { rellamada_hoy: true, proxima_llamada_en: '2026-10-03T22:00:00Z' },
      { rellamada_hoy: true, proxima_llamada_en: null }, // no debería llegar así: cuenta, pero no es vencida
      { rellamada_hoy: true, proxima_llamada_en: 'no-es-fecha' },
      { rellamada_hoy: false, proxima_llamada_en: '2026-10-01T15:00:00Z' }, // el servidor manda: no cuenta
    ]
    expect(contarRellamadasHoy(filas, AHORA)).toEqual({ paraHoy: 5, vencidas: 1 })
  })

  it('sin filas no hay nada que contar', () => {
    expect(contarRellamadasHoy([], AHORA)).toEqual({ paraHoy: 0, vencidas: 0 })
  })
})

describe('useConteoBaseGestion · sesión real del analista', () => {
  it('pide SU base sin parámetros y cuenta las rellamadas de hoy y las vencidas', async () => {
    responder(BASE_CON_RELLAMADAS)
    const { result } = montar()
    await waitFor(() => expect(result.current.disponible).toBe(true))
    expect(result.current).toEqual({ paraHoy: 3, vencidas: 2, disponible: true })
    expect(cuerpos).toEqual([{}])
  })

  it('el reloj vivo mueve las vencidas sin volver a pedir', async () => {
    responder(BASE_CON_RELLAMADAS)
    const { result, rerender } = montar()
    await waitFor(() => expect(result.current.disponible).toBe(true))
    expect(result.current.vencidas).toBe(2)
    dobles.ahora = Date.parse('2026-10-03T21:30:00Z') // 16:30 en Lima: la de las 16:00 ya pasó
    rerender()
    expect(result.current).toEqual({ paraHoy: 3, vencidas: 3, disponible: true })
    expect(cuerpos).toHaveLength(1)
  })

  it('una base sin rellamadas de hoy da 0 con cifra fiable (la pantalla no pinta la línea)', async () => {
    responder([fila(), fila({ proxima_llamada_en: '2026-10-06T15:00:00+00:00' })])
    const { result } = montar()
    await waitFor(() => expect(result.current.disponible).toBe(true))
    expect(result.current).toEqual({ paraHoy: 0, vencidas: 0, disponible: true })
  })

  it('COMPARTE la caché con la lista de la base: «Hoy» y el destino hacen UNA sola petición', async () => {
    responder(BASE_CON_RELLAMADAS)
    const cliente = clienteDePrueba()
    // Montados a la vez (la misma pantalla) …
    const juntos = renderHook(
      () => ({ conteo: useConteoBaseGestion(), lista: useBaseGestion(true) }),
      { wrapper: envoltorio(cliente) },
    )
    await waitFor(() => expect(juntos.result.current.conteo.disponible).toBe(true))
    expect(juntos.result.current.lista.data).toHaveLength(5)
    expect(cuerpos).toHaveLength(1)
    expect(cliente.getQueryData(crmQueryKeys.baseGestion(null, DIA))).toHaveLength(5)
    // … y al navegar de «Hoy» a la base dentro del tiempo de frescura: el destino lee la caché.
    const destino = renderHook(() => useBaseGestion(true), { wrapper: envoltorio(cliente) })
    expect(destino.result.current.data).toHaveLength(5)
    await act(async () => { await Promise.resolve() })
    expect(cuerpos).toHaveLength(1)
  })
})

describe('useConteoBaseGestion · fail-closed', () => {
  it('cargando: sin cifra (ni un «0» que se lea como «nada que hacer»)', async () => {
    servidor.use(
      http.post(RPC, async ({ request }) => {
        cuerpos.push(await request.json())
        await delay('infinite')
        return HttpResponse.json([])
      }),
    )
    const { result } = montar()
    await waitFor(() => expect(cuerpos).toHaveLength(1))
    expect(result.current).toEqual({ paraHoy: 0, vencidas: 0, disponible: false })
  })

  it('42501 (sin permiso): sin cifra y sin error hacia «Hoy»', async () => {
    servidor.use(http.post(RPC, () => HttpResponse.json({ code: '42501', message: 'Sin permiso' }, { status: 403 })))
    const { result, cliente } = montar()
    await waitFor(() => expect(cliente.getQueryState(crmQueryKeys.baseGestion(null, DIA))?.status).toBe('error'))
    expect(cliente.getQueryState(crmQueryKeys.baseGestion(null, DIA))?.error).toMatchObject({ code: 'SIN_PERMISO' })
    expect(result.current).toEqual({ paraHoy: 0, vencidas: 0, disponible: false })
  })

  it('error del servidor: sin cifra', async () => {
    servidor.use(http.post(RPC, () => HttpResponse.json({ code: 'XX000', message: 'caída' }, { status: 500 })))
    const { result, cliente } = montar()
    await waitFor(() => expect(cliente.getQueryState(crmQueryKeys.baseGestion(null, DIA))?.status).toBe('error'))
    expect(result.current.disponible).toBe(false)
  })

  it('un refresco que falla apaga la cifra aunque TanStack conserve la foto anterior', async () => {
    responder(BASE_CON_RELLAMADAS)
    const { result, cliente } = montar()
    await waitFor(() => expect(result.current.disponible).toBe(true))
    servidor.use(http.post(RPC, () => HttpResponse.json({ code: 'XX000', message: 'caída' }, { status: 500 })))
    await act(async () => { await cliente.invalidateQueries({ queryKey: crmQueryKeys.baseGestion(null, DIA) }) })
    await waitFor(() => expect(result.current.disponible).toBe(false))
    expect(cliente.getQueryData(crmQueryKeys.baseGestion(null, DIA))).toHaveLength(5) // la foto vieja sigue en caché
    expect(result.current).toEqual({ paraHoy: 0, vencidas: 0, disponible: false })
  })

  it('una foto de OTRO día de Lima (la pestaña cruzó la medianoche) no se cuenta como de hoy', async () => {
    responder(BASE_CON_RELLAMADAS)
    const { result, rerender } = montar()
    await waitFor(() => expect(result.current.disponible).toBe(true))
    dobles.ahora = Date.parse('2026-10-04T05:30:00Z') // domingo 00:30 en Lima
    rerender()
    expect(result.current.disponible).toBe(false)
  })

  it('al cruzar la medianoche (sin cambiar el foco) se vuelve a pedir la base del NUEVO día, una sola vez para «Hoy» y la lista', async () => {
    responder(BASE_CON_RELLAMADAS)
    const cliente = clienteDePrueba()
    const juntos = renderHook(() => ({ conteo: useConteoBaseGestion(), lista: useBaseGestion(true) }), { wrapper: envoltorio(cliente) })
    await waitFor(() => expect(juntos.result.current.conteo.disponible).toBe(true))
    expect(cuerpos).toHaveLength(1)
    // El reloj vivo marca las 00:01 del domingo en Lima.
    vi.setSystemTime(Date.parse('2026-10-04T05:01:00Z'))
    dobles.ahora = Date.parse('2026-10-04T05:01:00Z')
    juntos.rerender()
    // La foto de ayer no se presenta como de hoy mientras llega la nueva.
    expect(juntos.result.current.lista.data).toBeUndefined()
    expect(juntos.result.current.conteo.disponible).toBe(false)
    await waitFor(() => expect(juntos.result.current.conteo.disponible).toBe(true))
    expect(cuerpos).toHaveLength(2)
    expect(cliente.getQueryData(crmQueryKeys.baseGestion(null, '2026-10-04'))).toHaveLength(5)
  })

  it.each<Rol>(['supervisor', 'gerencia', 'directorio', 'coordinador'])('rol %s: ni pide ni cuenta', async (rol) => {
    responder(BASE_CON_RELLAMADAS)
    dobles.yo = analista({ rol })
    const { result } = montar()
    await act(async () => { await Promise.resolve() })
    expect(cuerpos).toHaveLength(0)
    expect(result.current.disponible).toBe(false)
  })

  it('sin sesión: ni pide ni cuenta', async () => {
    responder(BASE_CON_RELLAMADAS)
    dobles.yo = null
    const { result } = montar()
    await act(async () => { await Promise.resolve() })
    expect(cuerpos).toHaveLength(0)
    expect(result.current.disponible).toBe(false)
  })
})

describe('useConteoBaseGestion · demo (sin red)', () => {
  const DESCARTADO: Lead = {
    id: 'demo-1', nombre_completo: 'LEAD DEMO', telefono: '+51900000001', etapa: 'descartado', origen: 'landing',
    monto_estimado: 10_000, moneda: 'PEN', vendedor_id: '22222222-2222-4222-8222-222222222222',
    creado_en: '2026-09-01T15:00:00Z', activo: true, motivo_descarte: 'no_responde',
  } as Lead

  // El espejo lo mantiene lib/base-gestion (descartados del store + leads de MUESTRA): aquí no se fija su
  // contenido, solo que «Hoy» cuenta EXACTAMENTE lo que pintará #/rescate y que no sale a la red.
  it.each([
    ['sin descartados propios', [] as Lead[]],
    ['con un descartado propio', [DESCARTADO]],
  ])('%s: sin petición y con la cifra del MISMO espejo que el destino (`filasDemoBaseGestion`)', async (_caso, leads) => {
    responder(BASE_CON_RELLAMADAS)
    dobles.yo = analista({ demo: true })
    dobles.leads = leads
    const { result } = montar()
    await act(async () => { await Promise.resolve() })
    expect(cuerpos).toHaveLength(0)
    const espejo = filasDemoBaseGestion(leads, dobles.yo.id, AHORA)
    expect(result.current).toEqual({ ...contarRellamadasHoy(espejo, AHORA), disponible: true })
  })
})
