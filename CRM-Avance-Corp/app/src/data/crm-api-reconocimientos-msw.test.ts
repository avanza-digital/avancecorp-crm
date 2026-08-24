// @vitest-environment node
// F4.2 — frontera HTTP REAL de crm.alertas_reconocimientos (Codex #9: sin
// prueba de transporte, quitar el `.from` de la vista, el orden por secuencia
// o una clave del INSERT sobrevivía a toda la suite). Contra el cliente de
// Supabase de verdad, como el arnés de recordatorios (F3.1).
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

const observabilidad = vi.hoisted(() => ({ registrarError: vi.fn() }))

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

vi.mock('@/lib/observabilidad', () => ({
  idCorrelacion: () => 'corr-reconocimientos-test',
  registrarError: observabilidad.registrarError,
}))

import {
  listarReconocimientosAlertas,
  reconocerAlertaSupervisor,
} from './crm-api'

const VISTA = 'http://supabase.test/rest/v1/alertas_reconocimientos_vigentes'
const TABLA = 'http://supabase.test/rest/v1/alertas_reconocimientos'
const server = setupServer()

const ASIENTO_SERVIDOR = {
  id: '4c1f2a10-9f6a-49a4-8f7e-1a2b3c4d5e6f',
  alerta_id: 'grupo:por_repartir:e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
  accion: 'reconocer',
  miembros: ['0b0b2f6a-3d55-49a4-9a10-1f2f6f6e0001'],
  severidad: 'atencion',
  hasta: null,
  creado_en: '2026-08-23T15:00:00+00:00',
  secuencia: 7,
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  observabilidad.registrarError.mockReset()
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('frontera HTTP de los reconocimientos (F4.2)', () => {
  it('la lectura va a la VISTA de vigentes, ordenada por secuencia y SIN filtro de fecha del cliente', async () => {
    const urls: string[] = []
    server.use(
      http.get(VISTA, ({ request }) => {
        urls.push(request.url)
        return HttpResponse.json([ASIENTO_SERVIDOR])
      }),
    )

    const filas = await listarReconocimientosAlertas()

    expect(urls).toHaveLength(1)
    const parametros = new URL(urls[0]!).searchParams
    expect(parametros.get('order')).toBe('secuencia.desc')
    expect(parametros.get('limit')).toBe('1000')
    // La vigencia la corta el reloj de POSTGRES dentro de la vista: un
    // filtro de fecha fabricado con el reloj del dispositivo reabriría el
    // bloqueante Codex #2.
    expect(parametros.get('creado_en')).toBeNull()
    expect(filas).toEqual([ASIENTO_SERVIDOR])
  })

  it('el INSERT va a la TABLA con exactamente las claves del contrato', async () => {
    const cuerpos: Array<Record<string, unknown>> = []
    server.use(
      http.post(TABLA, async ({ request }) => {
        cuerpos.push(await request.json() as Record<string, unknown>)
        return new HttpResponse(null, { status: 201 })
      }),
    )

    await reconocerAlertaSupervisor(
      'e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
      'grupo:por_repartir:e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
      'posponer',
      ['0b0b2f6a-3d55-49a4-9a10-1f2f6f6e0001'],
      'critica',
      '2026-08-26T15:00:00.000Z',
    )

    expect(cuerpos).toHaveLength(1)
    expect(cuerpos[0]).toEqual({
      perfil_id: 'e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
      alerta_id: 'grupo:por_repartir:e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
      accion: 'posponer',
      miembros: ['0b0b2f6a-3d55-49a4-9a10-1f2f6f6e0001'],
      severidad: 'critica',
      hasta: '2026-08-26T15:00:00.000Z',
    })
  })

  it('una fila fuera de contrato NO pasa: se registra y se lanza', async () => {
    server.use(
      http.get(VISTA, () => HttpResponse.json([{ ...ASIENTO_SERVIDOR, accion: 'silenciar' }])),
    )

    await expect(listarReconocimientosAlertas()).rejects.toMatchObject({
      code: 'RECONOCIMIENTOS_CONTRACT',
    })
    expect(observabilidad.registrarError).toHaveBeenCalledWith(
      'crm.reconocimientos.fuera_de_contrato',
      expect.anything(),
    )
  })
})
