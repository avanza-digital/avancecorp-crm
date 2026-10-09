// @vitest-environment node
// Frontera HTTP de Facturación (`crm.facturacion_diaria_fn`). Plan de Facturación, fase 0C (09/10/2026): la
// lectura que alimenta la malla no tenía prueba propia. Fija qué se pide, cómo se traduce cada fila y que una fila
// ilegible se DESCARTA Y SE CUENTA —nunca se convierte en «vendió cero»—.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

const observabilidad = vi.hoisted(() => ({ registrarError: vi.fn() }))

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

vi.mock('@/lib/observabilidad', async (importActual) => ({
  ...(await importActual<typeof import('@/lib/observabilidad')>()),
  idCorrelacion: () => 'corr-facturacion-test',
  registrarError: observabilidad.registrarError,
}))

import { CrmApiError, listarFacturacionDiaria, SIN_ANALISTA_ID } from './crm-api'
import { SIN_SUPERVISOR_ID } from '@/lib/facturacion'

const RPC = 'http://supabase.test/rest/v1/rpc/facturacion_diaria_fn'
const server = setupServer()

// Estado de PRODUCCIÓN desde el 09/10/2026 (20261009200000): la venta de un analista de baja llega ya a nombre del
// heredero (aquí ELIZABETH, por una cooperativa de NOELIA). El front no recalcula nada: pinta lo que el servidor dice.
const FILA_HEREDADA = {
  dia: '2026-09-12', tipo: 'cooperativa', moneda: 'PEN',
  analista_id: 'e-1', analista_nombre: 'ELIZABETH CHIROQUE NAVARRO',
  supervisor_id: 's-1', supervisor_nombre: 'SUPERVISORA UNO',
  operaciones: 1, capital: '20000.00',
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  observabilidad.registrarError.mockReset()
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('frontera HTTP de Facturación', () => {
  it('pide el mes al esquema crm y traduce cada fila (números, analista y supervisor)', async () => {
    const cuerpos: unknown[] = []
    const perfiles: Array<string | null> = []
    server.use(http.post(RPC, async ({ request }) => {
      cuerpos.push(await request.json())
      perfiles.push(request.headers.get('content-profile'))
      return HttpResponse.json([FILA_HEREDADA])
    }))

    const filas = await listarFacturacionDiaria('2026-09-01')

    expect(cuerpos).toEqual([{ p_mes: '2026-09-01' }])
    expect(perfiles).toEqual(['crm'])
    expect(filas.descartadas).toBe(0)
    expect([...filas]).toEqual([{
      dia: '2026-09-12', tipo: 'cooperativa', moneda: 'PEN',
      analistaId: 'e-1', analistaNombre: 'ELIZABETH CHIROQUE NAVARRO',
      supervisorId: 's-1', supervisorNombre: 'SUPERVISORA UNO',
      operaciones: 1, capital: 20000,
    }])
  })

  it('un capital sin analista o sin supervisor usa los marcadores, no se pierde', async () => {
    server.use(http.post(RPC, () => HttpResponse.json([
      { ...FILA_HEREDADA, analista_id: null, analista_nombre: 'Sin analista', supervisor_id: null, supervisor_nombre: 'Sin supervisor' },
    ])))

    const [fila] = await listarFacturacionDiaria('2026-09-01')

    expect(fila?.analistaId).toBe(SIN_ANALISTA_ID)
    expect(fila?.supervisorId).toBe(SIN_SUPERVISOR_ID)
    expect(fila?.capital).toBe(20000)
  })

  it('una fila ilegible se DESCARTA y se CUENTA: moneda ajena, importe roto, día raro o forma incompleta', async () => {
    server.use(http.post(RPC, () => HttpResponse.json([
      FILA_HEREDADA,
      { ...FILA_HEREDADA, moneda: 'EUR' },
      { ...FILA_HEREDADA, capital: 'no-es-un-numero' },
      { ...FILA_HEREDADA, dia: '2026-9-12' },
      { dia: '2026-09-12', tipo: 'cooperativa', moneda: 'PEN' },
    ])))

    const filas = await listarFacturacionDiaria('2026-09-01')

    expect(filas).toHaveLength(1)
    expect(filas.descartadas).toBe(4)
    // Ninguna fila rota se convirtió en un cero silencioso.
    expect(filas.every((f) => f.capital === 20000)).toBe(true)
  })

  it('un error del servidor se lanza como CrmApiError (no como un mes vacío)', async () => {
    server.use(http.post(RPC, () => HttpResponse.json(
      { code: '42501', message: 'permission denied for function facturacion_diaria_fn' }, { status: 403 },
    )))

    await expect(listarFacturacionDiaria('2026-09-01')).rejects.toBeInstanceOf(CrmApiError)
  })
})
