// @vitest-environment node
// Las 4 RPCs de métricas contra un Supabase SIMULADO con msw: contrato HTTP
// real (POST /rpc/*, args p_meses/p_dias) + coerción numeric string→number +
// descarte de filas fuera de contrato. El cliente supabase-js es el de verdad.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  CrmApiError,
  listarMetricasCapitalMes,
  listarMetricasPagosMes,
  listarMetricasVencimientos,
} from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  // registrarError escribe en console.error; se silencia para no ensuciar la salida.
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('listarMetricasCapitalMes (msw)', () => {
  it('manda p_meses, coerciona numeric string→number y conserva categoria null', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('metricas_capital_mes_fn'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json([
          { mes: '2026-05-01', moneda: 'PEN', categoria: null, contratos: '2', capital_colocado: '30000.50' },
          { mes: '2026-06-01', moneda: 'USD', categoria: 'renovacion', contratos: 1, capital_colocado: 50000 },
        ])
      }),
    )

    const filas = await listarMetricasCapitalMes()

    expect(cuerpo).toEqual({ p_meses: 12 })
    expect(filas).toEqual([
      { mes: '2026-05-01', moneda: 'PEN', categoria: null, contratos: 2, capital_colocado: 30000.5 },
      { mes: '2026-06-01', moneda: 'USD', categoria: 'renovacion', contratos: 1, capital_colocado: 50000 },
    ])
  })

  it('descarta la fila fuera de contrato (moneda zombie) y conserva las válidas', async () => {
    server.use(
      http.post(RPC('metricas_capital_mes_fn'), () =>
        HttpResponse.json([
          { mes: '2026-05-01', moneda: 'EUR', categoria: null, contratos: 1, capital_colocado: 1 },
          { mes: '2026-05-01', moneda: 'PEN', categoria: 'nuevo', contratos: 1, capital_colocado: 9000 },
        ]),
      ),
    )

    const filas = await listarMetricasCapitalMes()

    expect(filas).toHaveLength(1)
    expect(filas[0]).toMatchObject({ moneda: 'PEN', capital_colocado: 9000 })
  })
})

describe('listarMetricasPagosMes (msw)', () => {
  it('coerciona montos y respeta tipo/estado del catálogo', async () => {
    server.use(
      http.post(RPC('metricas_pagos_mes_fn'), () =>
        HttpResponse.json([
          {
            mes: '2026-04-01', moneda: 'PEN', tipo: 'cuota', estado: 'pagado',
            cuotas: '3', monto_programado: '1500.00', monto_pagado: '1500.00',
          },
          {
            mes: '2026-04-01', moneda: 'PEN', tipo: 'cuota', estado: 'vencido',
            cuotas: 1, monto_programado: 500, monto_pagado: 0,
          },
        ]),
      ),
    )

    const filas = await listarMetricasPagosMes(6)

    expect(filas).toEqual([
      {
        mes: '2026-04-01', moneda: 'PEN', tipo: 'cuota', estado: 'pagado',
        cuotas: 3, monto_programado: 1500, monto_pagado: 1500,
      },
      {
        mes: '2026-04-01', moneda: 'PEN', tipo: 'cuota', estado: 'vencido',
        cuotas: 1, monto_programado: 500, monto_pagado: 0,
      },
    ])
  })
})

describe('listarMetricasVencimientos (msw)', () => {
  it('manda p_dias y coerciona el capital', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('metricas_vencimientos_fn'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json([
          { mes: '2026-09-01', moneda: 'PEN', contratos_por_vencer: '2', capital_por_vencer: '110000.00' },
        ])
      }),
    )

    const filas = await listarMetricasVencimientos(365)

    expect(cuerpo).toEqual({ p_dias: 365 })
    expect(filas).toEqual([
      { mes: '2026-09-01', moneda: 'PEN', contratos_por_vencer: 2, capital_por_vencer: 110000 },
    ])
  })

  it('un error PostgREST lanza CrmApiError con el code original', async () => {
    server.use(
      http.post(RPC('metricas_vencimientos_fn'), () =>
        HttpResponse.json(
          { message: 'boom interno', code: 'PGRST123', details: null, hint: null },
          { status: 500 },
        ),
      ),
    )

    const promesa = listarMetricasVencimientos()

    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({ code: 'PGRST123' })
  })
})
