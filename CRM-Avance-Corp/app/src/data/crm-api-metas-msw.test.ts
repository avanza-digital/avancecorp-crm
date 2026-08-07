// @vitest-environment node
// Frontera HTTP de los dos lectores mensuales de Metas. Comprueba que el
// frontend consume solo los RPC versionados y rechaza respuestas permisivas.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, obtenerCumplimientoMetas, obtenerMetasDelMes } from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const VENDEDOR_ID = '10000000-0000-4000-8000-000000000001'
const SUPERVISOR_ID = '10000000-0000-4000-8000-000000000002'
const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => vi.spyOn(console, 'error').mockImplementation(() => {}))

function detallesMeta(): Record<string, unknown>[] {
  return (['nuevo', 'renovacion', 'upgrade'] as const).flatMap((categoria) => [
    { categoria, moneda: 'PEN', capital_objetivo: '100000.50', contratos_objetivo: '2' },
    { categoria, moneda: 'USD', capital_objetivo: '10000', contratos_objetivo: '1' },
  ])
}

function configuracionValida(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    version: 1,
    periodo: '2026-08-01',
    revision: '4',
    publicada_en: '2026-08-07T18:00:00.000Z',
    publicada_por: null,
    publicada_por_nombre: null,
    puede_editar: true,
    vendedores: [{
      vendedor_id: VENDEDOR_ID,
      nombre: 'ANA TORRES',
      supervisor_id: SUPERVISOR_ID,
      supervisor_nombre: 'SUPERVISORA UNO',
      conversion_objetivo: '25',
      detalles: detallesMeta(),
    }],
    ...sobre,
  }
}

function cumplimientoValido(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    version: 1,
    periodo: '2026-08-01',
    revision: '4',
    publicada_en: '2026-08-07T18:00:00.000Z',
    fuentes_reales: {
      capital_y_contratos: 'contratos_confirmados',
      conversion: 'leads_resueltos',
    },
    vendedores: [{
      vendedor_id: VENDEDOR_ID,
      nombre: 'ANA TORRES',
      supervisor_id: SUPERVISOR_ID,
      supervisor_nombre: 'SUPERVISORA UNO',
      conversion_objetivo: '25',
      conversion_real: '20',
      convertidos: '2',
      resueltos: '10',
      detalles: detallesMeta().map((detalle) => ({
        ...detalle,
        capital_real: detalle.moneda === 'PEN' ? '50000' : '2500',
        capital_cumplimiento_pct: '50',
        contratos_real: '1',
        contratos_cumplimiento_pct: '50',
      })),
    }],
    ...sobre,
  }
}

describe('lectores versionados de metas', () => {
  it('consulta ambos RPC en crm, envía el período y coerciona numeric/bigint', async () => {
    const cuerpos: unknown[] = []
    const perfiles: Array<string | null> = []
    server.use(
      http.post(RPC('configuracion_metas_fn'), async ({ request }) => {
        cuerpos.push(await request.json())
        perfiles.push(request.headers.get('content-profile'))
        return HttpResponse.json(configuracionValida())
      }),
      http.post(RPC('cumplimiento_metas_fn'), async ({ request }) => {
        cuerpos.push(await request.json())
        perfiles.push(request.headers.get('content-profile'))
        return HttpResponse.json(cumplimientoValido())
      }),
    )

    const [configuracion, cumplimiento] = await Promise.all([
      obtenerMetasDelMes('2026-08-01'),
      obtenerCumplimientoMetas('2026-08-01'),
    ])

    expect(cuerpos).toEqual([
      { p_periodo: '2026-08-01' },
      { p_periodo: '2026-08-01' },
    ])
    expect(perfiles).toEqual(['crm', 'crm'])
    expect(configuracion).toMatchObject({ revision: 4 })
    expect(configuracion.vendedores[0]?.detalles[0]).toMatchObject({
      capital_objetivo: 100000.5,
      contratos_objetivo: 2,
    })
    expect(cumplimiento).toMatchObject({
      fuentes_reales: {
        capital_y_contratos: 'contratos_confirmados',
        conversion: 'leads_resueltos',
      },
    })
    expect(cumplimiento.vendedores[0]).toMatchObject({ conversion_real: 20, resueltos: 10 })
  })

  it('rechaza claves desconocidas y dimensiones incompletas en vez de degradarlas', async () => {
    server.use(
      http.post(RPC('configuracion_metas_fn'), () =>
        HttpResponse.json(configuracionValida({ campo_legacy: true })),
      ),
      http.post(RPC('cumplimiento_metas_fn'), () => {
        const respuesta = cumplimientoValido()
        const vendedores = respuesta.vendedores as Array<Record<string, unknown>>
        const detalles = vendedores[0]?.detalles
        if (!Array.isArray(detalles)) throw new Error('fixture de cumplimiento inválido')
        vendedores[0] = {
          ...vendedores[0],
          detalles: detalles.slice(0, 5),
        }
        return HttpResponse.json(respuesta)
      }),
    )

    await expect(obtenerMetasDelMes('2026-08-01')).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
    await expect(obtenerCumplimientoMetas('2026-08-01')).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('rechaza una fuente distinta y el campo legado ambiguo', async () => {
    server.use(
      http.post(RPC('cumplimiento_metas_fn'), () =>
        HttpResponse.json(cumplimientoValido({
          fuentes_reales: {
            capital_y_contratos: 'contratos_confirmados',
            conversion: 'pipeline_abierto',
          },
        })),
      ),
    )

    const promesa = obtenerCumplimientoMetas('2026-08-01')
    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({ code: 'ROW_CONTRACT' })

    server.use(
      http.post(RPC('cumplimiento_metas_fn'), () =>
        HttpResponse.json(cumplimientoValido({ fuente_reales: 'contratos_confirmados' })),
      ),
    )
    await expect(obtenerCumplimientoMetas('2026-08-01')).rejects.toMatchObject({
      code: 'ROW_CONTRACT',
    })
  })
})
