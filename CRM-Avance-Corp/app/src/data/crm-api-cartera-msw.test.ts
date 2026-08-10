// @vitest-environment node
// La cartera paginada por cursor keyset (F2) contra un Supabase SIMULADO: lo
// que se fija aquí es el CONTRATO con el servidor — qué argumentos viajan, cómo
// se decide "hay más" y de qué fila sale el cursor. El cliente supabase-js es
// el de verdad; lo simulado es la red.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, listarCarteraPagina } from './crm-api'
import { TAMANO_PAGINA_CARTERA } from '@/lib/cartera-keyset'

const RPC = 'http://supabase.test/rest/v1/rpc/cartera_pagina_fn'

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

/** Fila cruda tal como la devuelve la RPC (índice = posición en el orden). */
function fila(i: number, over: Record<string, unknown> = {}) {
  return {
    id: `lead-${String(i).padStart(3, '0')}`,
    nombre_completo: `LEAD ${i}`,
    telefono: `98765${String(i).padStart(4, '0')}`,
    correo: null,
    dni: null,
    genero: null,
    fecha_nacimiento: null,
    distrito: null,
    origen: 'landing',
    etapa: 'nuevo',
    motivo_descarte: null,
    monto_estimado: 1000 + i,
    moneda: 'PEN',
    categoria_interes: null,
    vendedor_id: null,
    asignado_supervisor_id: null,
    creado_en: '2026-08-01T00:00:00.000Z',
    tenencia_desde: null,
    convertido_en: null,
    contrato_id: null,
    // Decreciente: la fila 0 es la más reciente, como el orden del keyset.
    actualizado_en: new Date(Date.UTC(2026, 7, 1, 0, 0, 0) - i * 60_000).toISOString(),
    activo: true,
    nota: null,
    no_contactar: false,
    ultimo_contacto_en: null,
    ...over,
  }
}

describe('listarCarteraPagina — argumentos que viajan', () => {
  it('pide UNA fila de más y omite los filtros en su valor neutro', async () => {
    let cuerpo: unknown = null
    server.use(http.post(RPC, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json([])
    }))

    await listarCarteraPagina({ etapa: 'todas', vendedorId: 'todos', texto: '' }, null)

    expect(cuerpo).toEqual({ p_limite: TAMANO_PAGINA_CARTERA + 1 })
  })

  it('manda el cursor completo (los dos componentes o ninguno)', async () => {
    let cuerpo: Record<string, unknown> = {}
    server.use(http.post(RPC, async ({ request }) => {
      cuerpo = await request.json() as Record<string, unknown>
      return HttpResponse.json([])
    }))

    await listarCarteraPagina({}, { actualizadoEn: '2026-08-01T00:00:00.000Z', id: 'lead-050' })

    expect(cuerpo.p_antes_de).toBe('2026-08-01T00:00:00.000Z')
    expect(cuerpo.p_antes_id).toBe('lead-050')
  })

  it('traduce «sin_asignar» a p_sin_asignar y un vendedor a p_vendedor_id', async () => {
    const cuerpos: Record<string, unknown>[] = []
    server.use(http.post(RPC, async ({ request }) => {
      cuerpos.push(await request.json() as Record<string, unknown>)
      return HttpResponse.json([])
    }))

    await listarCarteraPagina({ vendedorId: 'sin_asignar' }, null)
    await listarCarteraPagina({ vendedorId: 'v-7' }, null)

    expect(cuerpos[0]!).toMatchObject({ p_sin_asignar: true })
    expect(cuerpos[0]!.p_vendedor_id).toBeUndefined()
    expect(cuerpos[1]!).toMatchObject({ p_vendedor_id: 'v-7' })
    expect(cuerpos[1]!.p_sin_asignar).toBeUndefined()
  })

  it('el texto viaja normalizado desde 2 caracteres y NUNCA con uno solo', async () => {
    const cuerpos: Record<string, unknown>[] = []
    server.use(http.post(RPC, async ({ request }) => {
      cuerpos.push(await request.json() as Record<string, unknown>)
      return HttpResponse.json([])
    }))

    // Un carácter: el servidor respondería 22023, así que ni se manda.
    await listarCarteraPagina({ texto: 'a' }, null)
    await listarCarteraPagina({ texto: '  María!  ' }, null)

    expect(cuerpos[0]!.p_texto).toBeUndefined()
    expect(cuerpos[1]!.p_texto).toBe('María')
  })

  it('la etapa viaja tal cual y «todas» no viaja', async () => {
    const cuerpos: Record<string, unknown>[] = []
    server.use(http.post(RPC, async ({ request }) => {
      cuerpos.push(await request.json() as Record<string, unknown>)
      return HttpResponse.json([])
    }))

    await listarCarteraPagina({ etapa: 'todas' }, null)
    await listarCarteraPagina({ etapa: 'convertido' }, null)

    expect(cuerpos[0]!.p_etapa).toBeUndefined()
    expect(cuerpos[1]!.p_etapa).toBe('convertido')
  })
})

describe('listarCarteraPagina — cómo se decide "hay más"', () => {
  it('con la fila extra devuelve la página recortada y el cursor de la última', async () => {
    const filas = Array.from({ length: TAMANO_PAGINA_CARTERA + 1 }, (_, i) => fila(i))
    server.use(http.post(RPC, () => HttpResponse.json(filas)))

    const pagina = await listarCarteraPagina({}, null)

    expect(pagina.items).toHaveLength(TAMANO_PAGINA_CARTERA)
    const ultima = filas[TAMANO_PAGINA_CARTERA - 1]!
    expect(pagina.cursor).toEqual({ actualizadoEn: ultima.actualizado_en, id: ultima.id })
    // La fila extra es una SONDA: no se pinta, solo demuestra que hay más.
    expect(pagina.items.at(-1)?.id).toBe(ultima.id)
  })

  it('sin fila extra el cursor es null aunque la página venga llena', async () => {
    const filas = Array.from({ length: TAMANO_PAGINA_CARTERA }, (_, i) => fila(i))
    server.use(http.post(RPC, () => HttpResponse.json(filas)))

    const pagina = await listarCarteraPagina({}, null)

    expect(pagina.items).toHaveLength(TAMANO_PAGINA_CARTERA)
    expect(pagina.cursor).toBeNull()
  })

  it('sin filas: página vacía y sin cursor', async () => {
    server.use(http.post(RPC, () => HttpResponse.json([])))

    const pagina = await listarCarteraPagina({}, null)

    expect(pagina).toEqual({ items: [], cursor: null })
  })
})

describe('listarCarteraPagina — contrato de las filas', () => {
  it('copia ultimo_contacto_en al lead (el semáforo del kanban)', async () => {
    server.use(http.post(RPC, () => HttpResponse.json([
      fila(0, { ultimo_contacto_en: '2026-08-09T15:00:00.000Z' }),
      fila(1),
    ])))

    const pagina = await listarCarteraPagina({}, null)

    expect(pagina.items[0]!.ultimo_contacto_en).toBe('2026-08-09T15:00:00.000Z')
    // null ≠ ausente: «nadie lo contactó jamás» es una respuesta, no un hueco.
    expect(pagina.items[1]!.ultimo_contacto_en).toBeNull()
  })

  it('descarta la fila fuera de contrato pero NO pierde el cursor', async () => {
    const filas = Array.from({ length: TAMANO_PAGINA_CARTERA + 1 }, (_, i) => fila(i))
    // La última fila de la VENTANA (la que da el cursor) llega corrupta.
    filas[TAMANO_PAGINA_CARTERA - 1] = fila(TAMANO_PAGINA_CARTERA - 1, { moneda: 'EUR' })
    server.use(http.post(RPC, () => HttpResponse.json(filas)))

    const pagina = await listarCarteraPagina({}, null)

    expect(pagina.items).toHaveLength(TAMANO_PAGINA_CARTERA - 1)
    // Si el cursor saliera de la última fila VÁLIDA, la página siguiente
    // repetiría la corrupta; y si se anulara, la lista se cortaría en seco.
    expect(pagina.cursor?.id).toBe(filas[TAMANO_PAGINA_CARTERA - 1]!.id)
  })

  it('un fallo del servidor se traduce a CrmApiError con su código', async () => {
    server.use(http.post(RPC, () => HttpResponse.json(
      { code: '42501', message: 'No autorizado' },
      { status: 403 },
    )))

    await expect(listarCarteraPagina({}, null)).rejects.toBeInstanceOf(CrmApiError)
  })
})
