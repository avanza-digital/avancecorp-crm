// @vitest-environment node
// F3.1 — frontera HTTP REAL de crm.recordatorios_disponibilidad (auditoría
// 18/08): los tests del formulario mockean crm-api entero, así que lo que
// VIAJA por la red (el dni explícito del upsert, el select mínimo de la
// campana) solo se prueba aquí, contra el cliente de Supabase de verdad.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

const observabilidad = vi.hoisted(() => ({ registrarError: vi.fn() }))

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

vi.mock('@/lib/observabilidad', () => ({
  idCorrelacion: () => 'corr-recordatorios-test',
  registrarError: observabilidad.registrarError,
}))

import {
  guardarRecordatorioDisponibilidad,
  listarRecordatoriosDisponibilidad,
} from './crm-api'

const TABLA = 'http://supabase.test/rest/v1/recordatorios_disponibilidad'
const server = setupServer()

const FILA_SERVIDOR = {
  id: '5c073c2a-f22a-4979-8ea4-8921f746ef22',
  perfil_id: 'e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
  telefono: '+51987654321',
  dni: null,
  recordar_en: '2026-09-10T14:00:00+00:00',
  creado_en: '2026-08-18T06:00:00+00:00',
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  observabilidad.registrarError.mockReset()
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('frontera HTTP de los recordatorios (F3.1)', () => {
  it('el upsert manda el dni EXPLÍCITO — null LIMPIA el vínculo anterior', async () => {
    const cuerpos: Array<Record<string, unknown>> = []
    const urls: string[] = []
    server.use(
      http.post(TABLA, async ({ request }) => {
        urls.push(request.url)
        cuerpos.push(await request.json() as Record<string, unknown>)
        return HttpResponse.json(FILA_SERVIDOR)
      }),
    )

    await guardarRecordatorioDisponibilidad(
      'e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
      '987654321',
      null,
      '2026-09-10T09:00:00-05:00',
    )

    // La CLAVE dni presente con null: omitirla hacía que el upsert CONSERVARA
    // el DNI del guardado anterior (vínculo teléfono↔DNI ya no afirmado).
    expect(cuerpos).toHaveLength(1)
    expect('dni' in cuerpos[0]!).toBe(true)
    expect(cuerpos[0]!.dni).toBeNull()
    expect(cuerpos[0]!.telefono).toBe('987654321')
    expect(urls[0]).toContain('on_conflict=perfil_id%2Ctelefono')
  })

  it('la campana se pide SIN dni (select mínimo, §8) y parsea la forma mínima', async () => {
    const selects: Array<string | null> = []
    server.use(
      http.get(TABLA, ({ request }) => {
        selects.push(new URL(request.url).searchParams.get('select'))
        const { dni: _sinDni, ...filaCampana } = FILA_SERVIDOR
        return HttpResponse.json([filaCampana])
      }),
    )

    const filas = await listarRecordatoriosDisponibilidad()

    expect(selects).toHaveLength(1)
    expect(selects[0]).not.toContain('dni')
    expect(filas).toHaveLength(1)
    expect(filas[0]!.telefono).toBe('+51987654321')
  })

  it('una cancelación de navegación no se registra como caída de la campana', async () => {
    const control = new AbortController()
    control.abort()

    await expect(listarRecordatoriosDisponibilidad(control.signal)).rejects.toMatchObject({
      name: 'AbortError',
    })
    expect(observabilidad.registrarError).not.toHaveBeenCalled()
  })
})
