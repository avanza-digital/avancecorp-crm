// @vitest-environment node
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { delay, http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

const observabilidad = vi.hoisted(() => ({ registrarError: vi.fn() }))

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

vi.mock('@/lib/observabilidad', () => ({
  idCorrelacion: () => 'corr-ayuda-test',
  registrarError: observabilidad.registrarError,
}))

import { consultarAyudaVendedor, CrmApiError, obtenerInicioAyudaVendedor } from './crm-api'

const RPC = (funcion: string) => `http://supabase.test/rest/v1/rpc/${funcion}`
const server = setupServer()

const respuestaValida = {
  version: 1,
  tipo: 'respuesta',
  respuesta: {
    id: 'anular-tarea-pendiente',
    titulo: 'Quitar una acción pendiente de tu agenda',
    resumen: 'Anula la acción que ya no realizarás.',
    duracion: '1 min',
    pasos: [{ titulo: 'Ubica la acción', detalle: 'Encuéntrala en Agenda.' }],
    accion: { tipo: 'navegar', vista: 'agenda', etiqueta: 'Ir a Agenda' },
    fuente: 'Manual del vendedor · versión aprobada',
  },
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  observabilidad.registrarError.mockReset()
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('frontera HTTP del centro de ayuda', () => {
  it('consulta solo las RPC crm con el payload esperado', async () => {
    const cuerpos: unknown[] = []
    const perfiles: Array<string | null> = []
    server.use(
      http.post(RPC('ayuda_vendedor_inicio'), async ({ request }) => {
        cuerpos.push(await request.json())
        perfiles.push(request.headers.get('content-profile'))
        return HttpResponse.json({
          version: 1,
          preguntas: ['¿Cómo elimino una acción?'],
        })
      }),
      http.post(RPC('consultar_ayuda_vendedor'), async ({ request }) => {
        cuerpos.push(await request.json())
        perfiles.push(request.headers.get('content-profile'))
        return HttpResponse.json(respuestaValida)
      }),
    )

    const [inicio, resultado] = await Promise.all([
      obtenerInicioAyudaVendedor('agenda'),
      consultarAyudaVendedor('  ¿Cómo elimino una acción?  ', 'agenda'),
    ])

    expect(cuerpos).toEqual([{ p_vista: 'agenda' }, { p_consulta: '¿Cómo elimino una acción?', p_vista: 'agenda' }])
    expect(perfiles).toEqual(['crm', 'crm'])
    expect(inicio.preguntas).toEqual(['¿Cómo elimino una acción?'])
    expect(resultado).toEqual(respuestaValida)
  })

  it('rechaza campos internos o acciones fuera del contrato público', async () => {
    server.use(
      http.post(RPC('consultar_ayuda_vendedor'), () => HttpResponse.json({ ...respuestaValida, puntuacion: 0.99 })),
    )
    await expect(consultarAyudaVendedor('como elimino una accion', 'agenda')).rejects.toMatchObject({
      code: 'ROW_CONTRACT',
    })

    server.use(
      http.post(RPC('consultar_ayuda_vendedor'), () =>
        HttpResponse.json({
          ...respuestaValida,
          respuesta: {
            ...respuestaValida.respuesta,
            accion: {
              tipo: 'navegar',
              vista: 'ruta-inexistente',
              etiqueta: 'Ir',
            },
          },
        }),
      ),
    )
    await expect(consultarAyudaVendedor('como elimino una accion', 'agenda')).rejects.toMatchObject({
      code: 'ROW_CONTRACT',
    })
  })

  it('cancela la petición en curso mediante AbortSignal', async () => {
    server.use(
      http.post(RPC('consultar_ayuda_vendedor'), async () => {
        await delay('infinite')
        return HttpResponse.json(respuestaValida)
      }),
    )
    const controlador = new AbortController()
    const promesa = consultarAyudaVendedor('como elimino una accion', 'agenda', controlador.signal)
    controlador.abort()

    await expect(promesa).rejects.toMatchObject({ name: 'AbortError' })
  })

  it('nunca copia el texto consultado a observabilidad del navegador', async () => {
    server.use(
      http.post(RPC('consultar_ayuda_vendedor'), () =>
        HttpResponse.json({ message: 'fallo temporal' }, { status: 500 }),
      ),
    )
    const consulta = 'Juan Perez 987654321 juan@example.com'

    await expect(consultarAyudaVendedor(consulta, 'agenda')).rejects.toBeInstanceOf(CrmApiError)
    expect(observabilidad.registrarError).toHaveBeenCalledWith('crm.ayuda.consulta_fallida', expect.any(CrmApiError), {
      vista: 'agenda',
      longitud: consulta.length,
    })
    expect(JSON.stringify(observabilidad.registrarError.mock.calls)).not.toContain(consulta)
  })
})
