// @vitest-environment node
// F2.1 del cierre de mes — los DOS caminos por los que el sello llega al
// usuario, contra un Supabase simulado con msw (contrato HTTP real):
//   · el rechazo del trigger 22023 al publicar metas de un mes sellado tiene
//     que llegar al toast COMO MENSAJE DE NEGOCIO, no como el genérico;
//   · `obtenerCierreMesEstado` parsea el payload real y sigue fail-closed.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { mensajeDeError, obtenerCierreMesEstado } from './crm-api'
import { publicarMetas } from './crm-config-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

// Mensaje VERBATIM del trigger `private.trg_metas_no_bajo_mes_sellado`
// (migración 20260815150000). Si el servidor lo reescribe, este test no se
// entera — lo que fija es el lado del cliente: 22023 pasa TAL CUAL.
const RECHAZO_SELLADO = 'No se publican metas de 2026-07: 2026-07 ya esta cerrado'

describe('publicar metas de un mes sellado (msw)', () => {
  it('el 22023 del candado llega al toast como mensaje de negocio', async () => {
    server.use(
      http.post(RPC('publicar_metas_vendedores'), () =>
        HttpResponse.json({ code: '22023', message: RECHAZO_SELLADO }, { status: 400 }),
      ),
    )

    const intento = publicarMetas({ periodo: '2026-07-01', expectedRevision: 3, metas: {} })
    await expect(intento).rejects.toMatchObject({
      code: 'REGLA_SERVIDOR',
      message: RECHAZO_SELLADO,
    })
    // El eslabón final: `mensajeDeError` es lo que la pantalla pinta. Si algún
    // día excluyera REGLA_SERVIDOR, gerencia volvería a ver el genérico.
    const fallo = await intento.catch((error: unknown) => error)
    expect(mensajeDeError(fallo, 'No se pudieron publicar las metas.')).toBe(RECHAZO_SELLADO)
  })
})

// Payload VERBATIM del generador (fixture `quieto`, 2026-08-15) — lo que
// producirá producción el día del estreno de este front.
const ESTADO_QUIETO = {
  hoy: '2026-08-15',
  zona: 'America/Lima',
  version: 1,
  pendiente: null,
  generado_en: '2026-08-15T20:34:50.843856-05:00',
  mes_en_curso: { mes: '2026-08', cierra_el: '2026-09-10', mes_nombre: 'August' },
  ultimo_cerrado: null,
}

describe('obtenerCierreMesEstado (msw)', () => {
  it('parsea el payload real y lo devuelve tipado', async () => {
    server.use(http.post(RPC('cierre_mes_estado_fn'), () => HttpResponse.json(ESTADO_QUIETO)))

    const estado = await obtenerCierreMesEstado()

    expect(estado.pendiente).toBeNull()
    expect(estado.mes_en_curso.cierra_el).toBe('2026-09-10')
  })

  it('sigue fail-closed: un payload con clave desconocida se rechaza como contrato', async () => {
    server.use(
      http.post(RPC('cierre_mes_estado_fn'), () =>
        HttpResponse.json({ ...ESTADO_QUIETO, sorpresa: true }),
      ),
    )

    await expect(obtenerCierreMesEstado()).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('un error del servidor no se disfraza de contrato', async () => {
    server.use(
      http.post(RPC('cierre_mes_estado_fn'), () =>
        HttpResponse.json({ code: '42501', message: 'No autorizado' }, { status: 401 }),
      ),
    )

    await expect(obtenerCierreMesEstado()).rejects.toMatchObject({ code: '42501' })
  })
})
