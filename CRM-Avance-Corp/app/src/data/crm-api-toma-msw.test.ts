// @vitest-environment node
// F2 «Tomar» contra el cliente supabase-js real y una Data API simulada: fija
// la ruta RPC, el schema crm, el payload por contacto, el contrato tomado_ok
// y el trato SIN fail-open de una mutación (a diferencia del precheck P-048).
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, tomarLeadLibre } from './crm-api'

const RUTA_TOMA = 'http://supabase.test/rest/v1/rpc/tomar_lead_libre'

// La forma REAL del retorno ganador (migración 20260817164745).
const TOMADO_OK = {
  estado: 'tomado_ok',
  lead_id: '5c073c2a-f22a-4979-8ea4-8921f746ef22',
  modo: 'bolsa',
  etapa: 'contactado',
  ciclo_actual: 1,
  tenencia_desde: '2026-08-17T21:10:00.123456+00:00',
}

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('tomarLeadLibre — la mutación de la toma directa', () => {
  it('llama a crm.tomar_lead_libre por contacto y devuelve el tomado_ok validado', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RUTA_TOMA, async ({ request }) => {
        cuerpo = await request.json()
        expect(request.headers.get('content-profile')).toBe('crm')
        return HttpResponse.json(TOMADO_OK)
      }),
    )

    const resultado = await tomarLeadLibre('987654321', '12345678')

    expect(cuerpo).toEqual({ p_telefono: '987654321', p_dni: '12345678' })
    expect(resultado).toEqual(TOMADO_OK)
  })

  it('sin DNI la clave se omite del payload (default null del catálogo)', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RUTA_TOMA, async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json(TOMADO_OK)
      }),
    )

    await tomarLeadLibre('987654321', null)

    expect(cuerpo).toEqual({ p_telefono: '987654321' })
  })

  it('el perdedor de la carrera recibe el veredicto fresco, no un error', async () => {
    server.use(
      http.post(RUTA_TOMA, () => HttpResponse.json({
        estado: 'tomado',
        vendedor: 'ANA PÉREZ',
        tenencia_desde: '2026-08-17T21:10:05+00:00',
      })),
    )

    const resultado = await tomarLeadLibre('987654321')

    expect(resultado.estado).toBe('tomado')
  })

  it('una respuesta fuera de contrato NUNCA se presenta como toma: TOMA_LEAD_CONTRACT', async () => {
    server.use(
      http.post(RUTA_TOMA, () => HttpResponse.json({
        estado: 'tomado_ok',
        lead_id: 'no-es-un-uuid',
        modo: 'bolsa',
        etapa: 'contactado',
        ciclo_actual: 1,
        tenencia_desde: '2026-08-17T21:10:00+00:00',
      })),
    )

    await expect(tomarLeadLibre('987654321')).rejects.toMatchObject({
      code: 'TOMA_LEAD_CONTRACT',
    })
  })

  it('un error del servidor se lanza tal cual — la toma no tiene cortesía fail-open', async () => {
    server.use(
      http.post(RUTA_TOMA, () => HttpResponse.json(
        { code: '42501', message: 'La toma directa es solo para analistas; supervisión asigna por el reparto' },
        { status: 403 },
      )),
    )

    const promesa = tomarLeadLibre('987654321')
    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.not.toMatchObject({ code: 'TOMA_LEAD_CONTRACT' })
  })
})
