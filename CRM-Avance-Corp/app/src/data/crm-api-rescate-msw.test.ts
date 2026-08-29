// @vitest-environment node
// Contrato HTTP de las RPCs de Base para gestión: el frontend solo recibe el
// historial mínimo y manda parámetros de reactivación con nombres estables.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  CrmApiError,
  descartesRescateDelMes,
  mesesRescateDescartes,
  rescatarDescartes,
} from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

const EPISODIO = {
  episodio_id: 'episodio-1',
  lead_id: 'lead-1',
  nombre_completo: 'ROSA QUISPE',
  distrito: 'Miraflores',
  origen: 'landing',
  categoria_interes: 'nuevo',
  monto_estimado: '30000.00',
  moneda: 'USD',
  motivo_descarte: 'sin_interes',
  descartado_en: '2026-08-20T14:00:00Z',
  asesor_id: 'asesor-1',
  asesor_nombre: 'CARMEN JARAMILLO',
  puede_rescatar: true,
  estado: 'pendiente',
}

describe('Base para gestión (msw)', () => {
  it('convierte los conteos de la franja mensual y descarta filas corruptas', async () => {
    server.use(
      http.post(RPC('rescate_descartes_meses'), () =>
        HttpResponse.json([
          { mes: '2026-08-01', total: '13', pendientes: '4' },
          { mes: '2026-07-01', total: 7, pendientes: 0 },
          { mes: '2026-06-01', total: 'no-es-numero', pendientes: 1 },
        ]),
      ),
    )

    await expect(mesesRescateDescartes()).resolves.toEqual([
      { mes: '2026-08-01', total: 13, pendientes: 4 },
      { mes: '2026-07-01', total: 7, pendientes: 0 },
    ])
  })

  it('pide el mes exacto y nunca deja pasar episodios fuera del contrato', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('rescate_descartes_mes'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json([
          EPISODIO,
          { ...EPISODIO, episodio_id: 'episodio-corrupto', estado: 'fuera_de_contrato' },
        ])
      }),
    )

    await expect(descartesRescateDelMes('2026-08-01')).resolves.toEqual([
      expect.objectContaining({
        episodio_id: 'episodio-1',
        monto_estimado: 30000,
        puede_rescatar: true,
        estado: 'pendiente',
      }),
    ])
    expect(cuerpo).toEqual({ p_mes: '2026-08-01' })
  })

  it('manda el bloque, los destinos y la regla de no devolver al analista de origen', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('rescatar_descartes'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({ rescatados: 2, asesores_destino: 1 })
      }),
    )

    await expect(rescatarDescartes(['episodio-1', 'episodio-2'], ['asesor-2'], true)).resolves.toBeUndefined()
    expect(cuerpo).toEqual({
      p_episodios: ['episodio-1', 'episodio-2'],
      p_analistas_destino: ['asesor-2'],
      p_evitar_asesor_origen: true,
    })
  })

  it.each([
    ['P0429', 'NO_INSISTA', 'Uno de los leads tiene la restricción «No insistir» y no puede reactivarse'],
    ['P0002', 'FUERA_DE_COLA', 'Uno de los descartes ya no está disponible para rescate'],
    ['42501', 'SIN_PERMISO', 'permission denied'],
  ])('mapea el SQLSTATE %s a un error seguro para la interfaz', async (pg, code, message) => {
    server.use(
      http.post(RPC('rescatar_descartes'), () =>
        HttpResponse.json({ code: pg, message }, { status: 400 }),
      ),
    )

    await expect(rescatarDescartes(['episodio-1'], ['asesor-2']))
      .rejects.toBeInstanceOf(CrmApiError)
    await expect(rescatarDescartes(['episodio-1'], ['asesor-2']))
      .rejects.toMatchObject({ code })
  })
})
