// @vitest-environment node
// listarLeads contra un Supabase SIMULADO con msw: se verifica el contrato
// HTTP real (query params PostgREST, header content-range, cuerpo de error)
// sin tocar la red — el cliente supabase-js es el de verdad.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

// El módulo real exige VITE_SUPABASE_URL/ANON_KEY; aquí se sustituye por un
// cliente apuntando al host ficticio que msw intercepta. Solo se exporta lo
// que crm-api usa en runtime (sb) — ClienteCrm es un tipo y se borra.
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, listarLeads, listarLeadsDelAmbito } from './crm-api'

const RUTA_LEADS = 'http://supabase.test/rest/v1/leads'

/** Fila con el shape exacto de LeadRow (todas las columnas del select). */
function fila(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'l-api-1',
    nombre_completo: 'Juan Prueba',
    telefono: '+51987650000',
    correo: null,
    dni: null,
    distrito: null,
    origen: 'landing',
    etapa: 'nuevo',
    motivo_descarte: null,
    monto_estimado: 1000,
    moneda: 'PEN',
    categoria_interes: null,
    vendedor_id: null,
    asignado_supervisor_id: null,
    creado_en: '2026-07-01T12:00:00.000Z',
    actualizado_en: '2026-07-02T12:00:00.000Z',
    activo: true,
    nota: null,
    ...sobre,
  }
}

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  // registrarError escribe en console.error; se silencia para no ensuciar la
  // salida (restoreMocks:true lo repone tras cada test).
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('listarLeads (msw)', () => {
  it('mapea la página feliz: filas → Lead, total desde content-range y monto string → number', async () => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json(
          [
            fila({ id: 'l-api-1', monto_estimado: '1500.50' }),
            fila({ id: 'l-api-2', etapa: 'contactado', monto_estimado: 200 }),
          ],
          { headers: { 'content-range': '0-1/2' } },
        ),
      ),
    )

    const pagina = await listarLeads({ pagina: 0 })

    expect(pagina.items).toHaveLength(2)
    expect(pagina.items[0]).toMatchObject({
      id: 'l-api-1',
      nombre_completo: 'Juan Prueba',
      origen: 'landing',
      etapa: 'nuevo',
      monto_estimado: 1500.5, // numeric(12,2) serializado como string por PostgREST
      activo: true,
    })
    expect(pagina.items[1]).toMatchObject({ id: 'l-api-2', monto_estimado: 200 })
    expect(pagina).toMatchObject({ pagina: 0, tamano: 50, total: 2, paginas: 1 })
  })

  it.each([null, 0, '0'])('descarta una fila sin capital positivo: %s', async (monto) => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json([fila({ monto_estimado: monto })], {
          headers: { 'content-range': '0-0/1' },
        }),
      ),
    )

    const pagina = await listarLeads({ pagina: 0 })

    expect(pagina.items).toEqual([])
  })

  it.each(['landing', 'formulario', 'web', 'campania', 'whatsapp'] as const)(
    'acepta el origen activo o histórico %s al leer Supabase',
    async (origen) => {
      server.use(
        http.get(RUTA_LEADS, () =>
          HttpResponse.json([fila({ origen })], { headers: { 'content-range': '0-0/1' } }),
        ),
      )

      const pagina = await listarLeads({ pagina: 0 })

      expect(pagina.items[0]?.origen).toBe(origen)
    },
  )

  it('descarta la fila fuera de contrato (etapa zombie) sin reventar y conserva las válidas', async () => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json(
          [
            fila({ id: 'l-ok-1' }),
            fila({ id: 'l-zombie', etapa: 'zombie' }),
            fila({ id: 'l-ok-2', etapa: 'convertido' }),
          ],
          { headers: { 'content-range': '0-2/3' } },
        ),
      ),
    )

    const pagina = await listarLeads({ pagina: 0 })

    expect(pagina.items.map((l) => l.id)).toEqual(['l-ok-1', 'l-ok-2'])
    // El total sigue siendo el del servidor: la fila inválida se descarta, no se re-cuenta.
    expect(pagina.total).toBe(3)
  })

  it('un error PostgREST (500 con message/code) lanza CrmApiError con el code original', async () => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json(
          { message: 'boom interno', code: 'PGRST123', details: null, hint: null },
          { status: 500 },
        ),
      ),
    )

    const promesa = listarLeads({ pagina: 0 })

    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({
      code: 'PGRST123',
      message: 'No se pudo cargar la cartera.',
    })
  })

  it('los filtros viajan como query params PostgREST: etapa=eq.… y vendedor_id=is.null', async () => {
    const capturadas: URL[] = []
    server.use(
      http.get(RUTA_LEADS, ({ request }) => {
        capturadas.push(new URL(request.url))
        return HttpResponse.json([], { headers: { 'content-range': '*/0' } })
      }),
    )

    await listarLeads({ pagina: 0, etapa: 'contactado', vendedorId: 'sin_asignar' })

    const url = capturadas[0]
    expect(url?.searchParams.get('etapa')).toBe('eq.contactado')
    expect(url?.searchParams.get('vendedor_id')).toBe('is.null')
    // Sin incluirInactivos, la consulta recorta a activos.
    expect(url?.searchParams.get('activo')).toBe('eq.true')
  })

  it('la búsqueda con caracteres peligrosos llega saneada al parámetro or=', async () => {
    const capturadas: URL[] = []
    server.use(
      http.get(RUTA_LEADS, ({ request }) => {
        capturadas.push(new URL(request.url))
        return HttpResponse.json([], { headers: { 'content-range': '*/0' } })
      }),
    )

    await listarLeads({ pagina: 0, texto: 'juan,or(activo' })

    const or = capturadas[0]?.searchParams.get('or')
    expect(or).toBeTruthy()
    // La coma y el paréntesis del usuario se volvieron espacios: solo queda
    // un patrón ILIKE, nunca sintaxis lógica inyectada.
    expect(or).toContain('nombre_completo.ilike.%juan or activo%')
    expect(or).not.toContain('juan,')
    expect(or).not.toContain('or(activo')
  })
})

describe('listarLeadsDelAmbito (msw)', () => {
  it('descarta y registra filas inválidas también en la ruta real del store', async () => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json([
          fila({ id: 'l-ambito-ok' }),
          fila({ id: 'l-ambito-sin-capital', monto_estimado: null }),
        ]),
      ),
    )

    const leads = await listarLeadsDelAmbito()

    expect(leads.map((lead) => lead.id)).toEqual(['l-ambito-ok'])
    expect(console.error).toHaveBeenCalledWith(
      '[ac-crm]',
      expect.objectContaining({ evento: 'crm.leads.ambito_filas_invalidas' }),
    )
  })
})
