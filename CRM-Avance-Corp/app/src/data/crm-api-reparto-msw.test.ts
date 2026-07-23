// @vitest-environment node
// C1 — las 3 RPCs de reparto contra un Supabase SIMULADO con msw: contrato HTTP
// real (POST /rpc/*), coerción numeric string→number, descarte de filas fuera de
// contrato y — lo importante — el MAPEO DE ERRORES: el veto legal P0429 debe
// llegar al frontend como NO_INSISTA y jamás confundirse con SIN_PERMISO.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  CrmApiError,
  leadsPorRepartir,
  repartirLead,
  supervisoresParaReparto,
} from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

const FILA_COLA = {
  id: 'lead-1',
  nombre_completo: 'ROSA QUISPE',
  distrito: 'Miraflores',
  origen: 'landing',
  categoria_interes: 'nuevo',
  monto_estimado: '30000.00',
  moneda: 'USD',
  creado_en: '2026-07-21T20:33:33Z',
}

describe('leadsPorRepartir (msw)', () => {
  it('coerciona el monto numeric string→number y conserva distrito null', async () => {
    server.use(
      http.post(RPC('leads_por_repartir'), () =>
        HttpResponse.json([
          FILA_COLA,
          { ...FILA_COLA, id: 'lead-2', distrito: null, categoria_interes: null, monto_estimado: 4500, moneda: 'PEN' },
        ]),
      ),
    )

    const filas = await leadsPorRepartir()

    expect(filas).toHaveLength(2)
    expect(filas[0]).toMatchObject({ id: 'lead-1', monto_estimado: 30000, moneda: 'USD' })
    expect(filas[1]).toMatchObject({ distrito: null, categoria_interes: null, monto_estimado: 4500 })
  })

  it('descarta filas fuera de contrato sin tumbar las válidas', async () => {
    server.use(
      http.post(RPC('leads_por_repartir'), () =>
        HttpResponse.json([
          { ...FILA_COLA, id: 'zombie', moneda: 'EUR' },
          { ...FILA_COLA, id: 'buena' },
        ]),
      ),
    )

    const filas = await leadsPorRepartir()

    expect(filas).toHaveLength(1)
    expect(filas[0]?.id).toBe('buena')
  })

  it('un rechazo de permisos sube como CrmApiError', async () => {
    server.use(
      http.post(RPC('leads_por_repartir'), () =>
        HttpResponse.json({ code: '42501', message: 'Solo el coordinador puede ver la cola' }, { status: 403 }),
      ),
    )

    await expect(leadsPorRepartir()).rejects.toBeInstanceOf(CrmApiError)
  })
})

describe('supervisoresParaReparto (msw)', () => {
  it('devuelve destinos con el conteo de bandeja coercionado', async () => {
    server.use(
      http.post(RPC('supervisores_para_reparto'), () =>
        HttpResponse.json([
          { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', activo: true, bandeja_pendiente: '3' },
          { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', activo: true, bandeja_pendiente: 0 },
        ]),
      ),
    )

    const filas = await supervisoresParaReparto()

    expect(filas).toEqual([
      { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', activo: true, bandeja_pendiente: 3 },
      { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', activo: true, bandeja_pendiente: 0 },
    ])
  })
})

describe('repartirLead (msw) — mapeo de errores del servidor', () => {
  it('manda los parámetros con el nombre exacto de la RPC', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('repartir_lead'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({ lead_id: 'lead-1', asignado_supervisor_id: 'sup-1' })
      }),
    )

    await repartirLead('lead-1', 'sup-1')

    expect(cuerpo).toEqual({ p_lead: 'lead-1', p_supervisor: 'sup-1' })
  })

  it.each([
    ['P0429', 'NO_INSISTA', 'Lead marcado No Insista (Ley 29571): no se puede repartir'],
    ['P0002', 'FUERA_DE_COLA', 'El lead ya no está en la cola por repartir'],
    ['40001', 'REINTENTAR', 'conflicto de serializacion'],
    ['42501', 'SIN_PERMISO', 'permission denied'],
    ['22023', 'REGLA_SERVIDOR', 'La bandeja destino no pertenece a un supervisor activo'],
    ['P0001', 'REGLA_SERVIDOR', 'La bandeja destino no pertenece a un supervisor activo'],
  ])('el SQLSTATE %s se traduce a %s', async (pg, code, message) => {
    server.use(
      http.post(RPC('repartir_lead'), () =>
        HttpResponse.json({ code: pg, message }, { status: 400 }),
      ),
    )

    await expect(repartirLead('lead-1', 'sup-1')).rejects.toMatchObject({ code })
  })

  it('el veto legal NUNCA se degrada a SIN_PERMISO (candado del contrato)', async () => {
    // Si alguien cambiara el errcode del servidor a 42501, este test seguiría
    // pasando — por eso el candado REAL vive en el gate RLS (código exacto
    // P0429 + oráculo de estado). Aquí se fija el lado del cliente: mientras
    // llegue P0429, el mensaje legal se surfacea tal cual y no como permisos.
    server.use(
      http.post(RPC('repartir_lead'), () =>
        HttpResponse.json(
          { code: 'P0429', message: 'Lead marcado No Insista (Ley 29571): no se puede repartir' },
          { status: 400 },
        ),
      ),
    )

    await expect(repartirLead('lead-1', 'sup-1')).rejects.toMatchObject({
      code: 'NO_INSISTA',
      message: 'Lead marcado No Insista (Ley 29571): no se puede repartir',
    })
  })
})
