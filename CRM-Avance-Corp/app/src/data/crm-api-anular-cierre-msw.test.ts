// @vitest-environment node
// «Anular un cierre» (Avance y cooperativa) contra el cliente supabase-js real y una Data API simulada.
// Bloque 2.6 (20261009210000): la puerta toma el cerrojo del mes de la venta y, si mientras esperaba cambió la
// acreditación de esa venta, responde PT409 sin escribir nada («La acreditacion cambio durante la anulacion; vuelve a
// intentar»; el disparador de acreditación de la cooperativa tiene su gemelo, «…mientras esperaba el candado…»). Basta con
// reintentar, así que la pantalla tiene que decirlo con un texto claro, no con «No se pudo anular el cierre».
// Los demás rechazos, exactamente como estaban.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, anularCierreAvance, anularCierreExterno } from './crm-api'

const LEAD = '33333333-3333-4333-8333-333333333333'
const CIERRE = '44444444-4444-4444-8444-444444444444'
const CLARO = 'La venta cambió mientras la anulabas. Vuelve a intentarlo.'
const SELLADO = 'No se puede anular: el mes de esta venta (2026-07) ya está sellado'

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

async function fallo(p: Promise<unknown>): Promise<CrmApiError> {
  try {
    await p
  } catch (e) {
    if (e instanceof CrmApiError) return e
    throw e
  }
  throw new Error('no falló')
}

function rechazo(ruta: string, code: string, message: string) {
  const status = code === '42501' ? 403 : code === 'PT409' ? 409 : 400
  server.use(http.post(ruta, () => HttpResponse.json({ code, message, details: null, hint: null }, { status })))
}

describe.each([
  {
    nombre: 'anularCierreAvance (crm.anular_cierre_avance)',
    ruta: 'http://supabase.test/rest/v1/rpc/anular_cierre_avance',
    llamar: () => anularCierreAvance({ leadId: LEAD, motivo: 'Cierre registrado con datos que no corresponden' }),
    generico: 'No se pudo anular el cierre.',
    negocio: 'CIERRE_AVANCE_INVALIDO',
    sinPermiso: 'Solo gerencia anula cierres.',
  },
  {
    nombre: 'anularCierreExterno (crm.anular_cierre_externo)',
    ruta: 'http://supabase.test/rest/v1/rpc/anular_cierre_externo',
    llamar: () => anularCierreExterno({ cierreId: CIERRE, motivo: 'Depósito digitado dos veces' }),
    generico: 'No se pudo anular el cierre externo.',
    negocio: 'CIERRE_EXTERNO_INVALIDO',
    sinPermiso: 'Solo gerencia anula cierres externos.',
  },
])('$nombre', ({ ruta, llamar, generico, negocio, sinPermiso }) => {
  it.each([
    ['del detector del mes sellado (2.6)', 'La acreditacion cambio durante la anulacion; vuelve a intentar'],
    ['de la acreditación, al esperar el candado', 'La acreditacion cambio mientras esperaba el candado; vuelve a intentar'],
  ])('un PT409 %s llega con un texto claro, no con el genérico', async (_, textoServidor) => {
    rechazo(ruta, 'PT409', textoServidor)
    const e = await fallo(llamar())
    expect(e.code).toBe('PT409')
    expect(e.message).toBe(CLARO)
    expect(e.message).not.toBe(generico)
  })

  it.each([
    ['42501', 'Solo gerencia anula cierres', 'SIN_PERMISO', 'sinPermiso'],
    ['P0409', SELLADO, 'NEGOCIO', SELLADO],
    ['P0409', 'Ese cierre ya estaba anulado', 'NEGOCIO', 'Ese cierre ya estaba anulado'],
    ['22023', 'Escribe el motivo de la anulacion', 'NEGOCIO', 'Escribe el motivo de la anulacion'],
    ['XX000', 'internal error', 'XX000', 'generico'],
  ])('los demás rechazos no cambian: %s («%s»)', async (pg, textoServidor, codigo, mensaje) => {
    rechazo(ruta, pg, textoServidor)
    const e = await fallo(llamar())
    expect(e.code).toBe(codigo === 'NEGOCIO' ? negocio : codigo)
    expect(e.message).toBe(mensaje === 'sinPermiso' ? sinPermiso : mensaje === 'generico' ? generico : mensaje)
  })
})
