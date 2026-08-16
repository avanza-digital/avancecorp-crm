// @vitest-environment node
// P-048 contra el cliente supabase-js real y una Data API simulada: fija la
// ruta RPC, el schema crm, los siete estados, el AbortSignal y el contrato de
// la creación atómica sin tocar producción.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { delay, http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  CrmApiError,
  actualizarLead,
  insertarLead,
  verificarDisponibilidadLead,
  type DisponibilidadLead,
} from './crm-api'

const RUTA_DISPONIBILIDAD =
  'http://supabase.test/rest/v1/rpc/verificar_disponibilidad_lead'
const RUTA_CREACION =
  'http://supabase.test/rest/v1/rpc/crear_lead_si_disponible'

const ALTA = {
  id: '5c073c2a-f22a-4979-8ea4-8921f746ef22',
  nombre_completo: 'CONTACTO ATÓMICO',
  telefono: '+51987654321',
  origen: 'formulario' as const,
  monto_estimado: 10_000,
  moneda: 'PEN' as const,
}

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

const RESPUESTAS_VALIDAS: Array<[string, DisponibilidadLead]> = [
  ['libre', { estado: 'libre' }],
  ['en_bolsa', { estado: 'en_bolsa' }],
  [
    'tomado',
    {
      estado: 'tomado',
      vendedor: 'ANA ANALISTA',
      tenencia_desde: '2026-08-04T12:30:00.000Z',
    },
  ],
  [
    'enfriamiento',
    {
      estado: 'enfriamiento',
      motivo_descarte: 'no_responde',
      disponible_desde: '2026-08-19T12:30:00.000Z',
      descartado_por: null,
    },
  ],
  ['ya_es_cliente', { estado: 'ya_es_cliente', asesor: 'SIN ASESOR ASIGNADO' }],
  ['no_contactar', { estado: 'no_contactar' }],
  ['error', { estado: 'error', detalle: 'telefono_invalido' }],
]

describe('verificarDisponibilidadLead (MSW)', () => {
  it.each(RESPUESTAS_VALIDAS)(
    'valida y devuelve el estado %s',
    async (_nombre, respuesta) => {
      server.use(
        http.post(RUTA_DISPONIBILIDAD, async ({ request }) => {
          expect(request.headers.get('content-profile')).toBe('crm')
          expect(await request.json()).toEqual({
            p_telefono: '987 654 321',
            p_dni: '12345678',
          })
          return HttpResponse.json(respuesta)
        }),
      )

      await expect(
        verificarDisponibilidadLead('987 654 321', '12345678'),
      ).resolves.toEqual(respuesta)
    },
  )

  it.each([
    ['estado desconocido', { estado: 'reservado' }],
    [
      'tomado incompleto',
      { estado: 'tomado', vendedor: 'ANA ANALISTA' },
    ],
    [
      'fecha inválida',
      {
        estado: 'enfriamiento',
        motivo_descarte: 'no_responde',
        disponible_desde: 'mañana',
        descartado_por: null,
      },
    ],
    ['detalle de error desconocido', { estado: 'error', detalle: 'otro' }],
    ['propiedad inesperada', { estado: 'libre', vendedor: 'NO DEBE VIAJAR' }],
  ])('rechaza el contrato inválido: %s', async (_nombre, respuesta) => {
    server.use(
      http.post(RUTA_DISPONIBILIDAD, () => HttpResponse.json(respuesta)),
    )

    const promesa = verificarDisponibilidadLead('+51987654321')

    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({
      code: 'DISPONIBILIDAD_CONTRACT',
      message: 'La disponibilidad del contacto no tiene el formato esperado.',
    })
  })

  it('cancela una RPC en vuelo con el AbortSignal sin convertirla en error de negocio', async () => {
    let avisarInicio: (() => void) | undefined
    const iniciada = new Promise<void>((resolve) => {
      avisarInicio = resolve
    })
    server.use(
      http.post(RUTA_DISPONIBILIDAD, async () => {
        avisarInicio?.()
        await delay(200)
        return HttpResponse.json({ estado: 'libre' })
      }),
    )
    const controlador = new AbortController()

    const promesa = verificarDisponibilidadLead(
      '+51987654321',
      null,
      controlador.signal,
    )
    await iniciada
    controlador.abort()

    await expect(promesa).rejects.toMatchObject({ name: 'AbortError' })
  })

  it('propaga un error PostgREST del RPC con un código estable', async () => {
    server.use(
      http.post(RUTA_DISPONIBILIDAD, () =>
        HttpResponse.json(
          { code: '42501', message: 'Acceso CRM revocado', details: null, hint: null },
          { status: 403 },
        ),
      ),
    )

    await expect(verificarDisponibilidadLead('+51987654321')).rejects.toMatchObject({
      code: 'SIN_PERMISO',
      message: 'No tienes permiso para esa acción',
    })
  })

  it.each(['PGRST106', 'PGRST202'])(
    'distingue la configuración estructural %s de una caída de red',
    async (code) => {
      server.use(
        http.post(RUTA_DISPONIBILIDAD, () =>
          HttpResponse.json(
            { code, message: 'detalle interno', details: null, hint: null },
            { status: 404 },
          ),
        ),
      )

      await expect(verificarDisponibilidadLead('+51987654321')).rejects.toMatchObject({
        code: 'DISPONIBILIDAD_NO_DISPONIBLE',
        message: 'La verificación de disponibilidad no está habilitada.',
      })
    },
  )

  it('tipa un fallo real de transporte (status 0) como red', async () => {
    server.use(http.post(RUTA_DISPONIBILIDAD, () => HttpResponse.error()))

    await expect(verificarDisponibilidadLead('+51987654321')).rejects.toMatchObject({
      code: 'DISPONIBILIDAD_RED',
      message: 'No se pudo contactar el servicio de disponibilidad.',
    })
  })

  it('tipa PGRST001 como indisponibilidad operativa', async () => {
    server.use(
      http.post(RUTA_DISPONIBILIDAD, () =>
        HttpResponse.json(
          { code: 'PGRST001', message: 'database unavailable', details: null, hint: null },
          { status: 503 },
        ),
      ),
    )

    await expect(verificarDisponibilidadLead('+51987654321')).rejects.toMatchObject({
      code: 'DISPONIBILIDAD_RED',
      message: 'No se pudo contactar el servicio de disponibilidad.',
    })
  })

  it('un HTTP con código vacío no se disfraza de transporte si status no es 0', async () => {
    server.use(
      http.post(RUTA_DISPONIBILIDAD, () =>
        HttpResponse.json(
          { code: '', message: 'respuesta malformada', details: null, hint: null },
          { status: 500 },
        ),
      ),
    )

    await expect(verificarDisponibilidadLead('+51987654321')).rejects.toMatchObject({
      code: 'POSTGREST_ERROR',
    })
  })
})

describe('insertarLead: RPC atómica', () => {
  it('envía solo el DTO permitido y acepta la confirmación estricta del mismo id', async () => {
    server.use(
      http.post(RUTA_CREACION, async ({ request }) => {
        expect(request.headers.get('content-profile')).toBe('crm')
        // Los opcionales vacíos se OMITEN (tipos generados + sinIndefinidos):
        // todos tienen DEFAULT NULL en el catálogo — clave ausente ≡ null.
        expect(await request.json()).toEqual({
          p_nombre_completo: ALTA.nombre_completo,
          p_telefono: ALTA.telefono,
          p_origen: 'formulario',
          p_monto_estimado: 10_000,
          p_moneda: 'PEN',
          p_id: ALTA.id,
          p_etapa: 'nuevo',
        })
        return HttpResponse.json({ estado: 'creado', lead_id: ALTA.id })
      }),
    )

    await expect(insertarLead(ALTA)).resolves.toEqual({
      estado: 'creado',
      lead_id: ALTA.id,
    })
  })

  it.each(RESPUESTAS_VALIDAS.filter(([, respuesta]) => respuesta.estado !== 'libre'))(
    'conserva el veredicto bloqueante %s devuelto dentro de la transacción',
    async (_nombre, respuesta) => {
      server.use(http.post(RUTA_CREACION, () => HttpResponse.json(respuesta)))
      await expect(insertarLead(ALTA)).resolves.toEqual(respuesta)
    },
  )

  it.each([
    ['libre sin INSERT', { estado: 'libre' }],
    ['id ausente', { estado: 'creado' }],
    ['id no UUID', { estado: 'creado', lead_id: 'lead-1' }],
    ['campo extra', { estado: 'creado', lead_id: ALTA.id, creado_por: 'oculto' }],
  ])('rechaza una confirmación fuera de contrato: %s', async (_nombre, respuesta) => {
    server.use(http.post(RUTA_CREACION, () => HttpResponse.json(respuesta)))

    await expect(insertarLead(ALTA)).rejects.toMatchObject({
      code: 'CREACION_LEAD_CONTRACT',
      message: 'El servidor no confirmó la creación del lead.',
    })
  })

  it('mapea el bloqueo defensivo P0481 del trigger sin volcar el JSON crudo', async () => {
    server.use(
      http.post(RUTA_CREACION, () =>
        HttpResponse.json(
          {
            code: 'P0481',
            message: 'Contacto no disponible',
            details: JSON.stringify({ estado: 'no_contactar' }),
            hint: null,
          },
          { status: 409 },
        ),
      ),
    )

    await expect(insertarLead(ALTA)).rejects.toMatchObject({
      code: 'CONTACTO_NO_DISPONIBLE',
      message: 'Este contacto está marcado como «No contactar» y no se puede registrar nuevamente.',
    })
  })

  it.each(['55P03', '40P01'])(
    'convierte %s en una instrucción estable de reintento',
    async (code) => {
      server.use(
        http.post(RUTA_CREACION, () =>
          HttpResponse.json(
            { code, message: 'detalle interno', details: null, hint: null },
            { status: 409 },
          ),
        ),
      )

      await expect(insertarLead(ALTA)).rejects.toMatchObject({
        code: 'CONTACTO_EN_PROCESO',
        message: 'Otro usuario está procesando este contacto. Inténtalo nuevamente.',
      })
    },
  )

  it.each(['uq_leads_telefono_vivo', 'uq_leads_dni_vivo'])(
    'mantiene la defensa 23505 de %s ante un escritor externo',
    async (constraint) => {
      server.use(
        http.post(RUTA_CREACION, () =>
          HttpResponse.json(
            {
              code: '23505',
              message: 'duplicate key value violates unique constraint',
              details: constraint,
              hint: null,
            },
            { status: 409 },
          ),
        ),
      )

      await expect(
        insertarLead(ALTA),
      ).rejects.toMatchObject({
        code: 'CONTACTO_RECIEN_REGISTRADO',
        message: 'Este contacto acaba de ser registrado por otro usuario',
      })
    },
  )

  it('no disfraza como carrera de contacto un 23505 de otra restricción', async () => {
    server.use(
      http.post(RUTA_CREACION, () =>
        HttpResponse.json(
          {
            code: '23505',
            message: 'duplicate key value violates unique constraint',
            details: 'leads_pkey',
            hint: null,
          },
          { status: 409 },
        ),
      ),
    )

    await expect(
      insertarLead(ALTA),
    ).rejects.toMatchObject({
      code: 'POSTGREST_ERROR',
      message: 'No se pudo guardar el cambio.',
    })
  })
})

describe('actualizarLead: identidad protegida por P-048', () => {
  it('mapea el veto P0481 sin revelar el veredicto global del contacto', async () => {
    server.use(
      http.patch('http://supabase.test/rest/v1/leads', () =>
        HttpResponse.json(
          {
            code: 'P0481',
            message: 'Contacto no disponible',
            details: JSON.stringify({ estado: 'ya_es_cliente', asesor: 'OCULTO' }),
            hint: null,
          },
          { status: 409 },
        ),
      ),
    )

    await expect(
      actualizarLead(ALTA.id, { telefono: '+51911111111' }),
    ).rejects.toMatchObject({
      code: 'CONTACTO_NO_DISPONIBLE',
      message: 'Ese teléfono o DNI no está disponible para este lead.',
    })
  })
})
