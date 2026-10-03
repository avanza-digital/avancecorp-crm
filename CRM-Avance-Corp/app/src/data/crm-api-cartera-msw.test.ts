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
const RPC_INTEGRADA = 'http://supabase.test/rest/v1/rpc/cartera_filtrada_fn'

const server = setupServer()

function payloadFiltrado(n = 60) {
  return {
    version: 1, generado_en: '2026-09-13T12:00:00Z', desde: '2026-09-01', hasta: '2026-09-03',
    items: Array.from({ length: Math.min(n, 51) }, (_, i) => fila(i, {
      recibido_en: '2026-09-02T12:00:00Z', recepcion_aproximada: false,
    })),
    resumen: {
      totales: { vivos: n, abiertos: n, asignados: 0, parkeados: n, convertidos: 0, descartados: 0, asignados_pen: 0, asignados_usd: 0, reasignados: 0 },
      capital: { asignado: { pen: 0, usd: 0 }, parkeado: { pen: 1000 * n, usd: 0 }, ganado: { pen: 0, usd: 0 } },
      embudo: [{ etapa: 'nuevo', n }],
    },
  }
}

describe('cartera integrada: listado y total del mismo filtro', () => {
  const filtros = { integrada: true, recepcion: { desde: '2026-09-01', hasta: '2026-09-03' } }
  it('Gestionado envía etapa nuevo y gestión vigente, también al pedir la segunda página', async () => {
    const cuerpos: Record<string, unknown>[] = []
    server.use(http.post(RPC_INTEGRADA, async ({ request }) => {
      cuerpos.push(await request.json() as Record<string, unknown>)
      return HttpResponse.json(payloadFiltrado())
    }))
    const gestionados = { ...filtros, etapa: 'nuevo' as const, gestion: 'con_gestion' as const }
    const primera = await listarCarteraPagina(gestionados, null)
    await listarCarteraPagina(gestionados, primera.cursor)
    expect(cuerpos[0]).toMatchObject({ p_etapa: 'nuevo', p_gestion: 'con_gestion' })
    expect(cuerpos[1]).toMatchObject({ p_etapa: 'nuevo', p_gestion: 'con_gestion', p_antes_id: primera.cursor?.id })
    expect(primera.resumen?.totales.vivos).toBe(60)
    await listarCarteraPagina(filtros, null)
    expect(cuerpos[2]).not.toHaveProperty('p_gestion')
  })
  it('envía fechas inclusivas y mantiene el total completo al paginar', async () => {
    let cuerpo: unknown
    server.use(http.post(RPC_INTEGRADA, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(payloadFiltrado())
    }))
    const pagina = await listarCarteraPagina(filtros, null)
    expect(cuerpo).toEqual({ p_limite: 51, p_desde: '2026-09-01', p_hasta: '2026-09-03' })
    expect(pagina.items).toHaveLength(50)
    expect(pagina.resumen?.totales.vivos).toBe(60)
    expect(pagina.cursor?.id).toBe('lead-049')
    expect(pagina.items[0]?.recibido_en).toBe('2026-09-02T12:00:00Z')
  })
  it.each(['rango', 'total', 'fila', 'nulo'])('rechaza payload inconsistente: %s', async (caso) => {
    const payload = payloadFiltrado()
    if (caso === 'rango') payload.desde = '2026-08-01'
    if (caso === 'total') payload.resumen.totales.vivos = 1
    if (caso === 'fila') payload.items[0]!.moneda = 'EUR'
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(caso === 'nulo' ? null : payload)))
    await expect(listarCarteraPagina(filtros, null)).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('el origen viaja solo cuando recorta y vuelve aplicado en el payload', async () => {
    let cuerpo: unknown
    server.use(http.post(RPC_INTEGRADA, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json({ ...payloadFiltrado(), origen: 'landing' })
    }))
    const pagina = await listarCarteraPagina({ ...filtros, origen: 'landing' }, null)
    expect(cuerpo).toEqual({ p_limite: 51, p_desde: '2026-09-01', p_hasta: '2026-09-03', p_origen: 'landing' })
    expect(pagina.resumen?.totales.vivos).toBe(60)
    expect(pagina.items.every((l) => l.origen === 'landing')).toBe(true)
  })

  it('«todos» no viaja y un servidor sin eco de origen sigue siendo válido', async () => {
    let cuerpo: unknown
    server.use(http.post(RPC_INTEGRADA, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(payloadFiltrado())
    }))
    const pagina = await listarCarteraPagina({ ...filtros, origen: 'todos' }, null)
    expect(cuerpo).toEqual({ p_limite: 51, p_desde: '2026-09-01', p_hasta: '2026-09-03' })
    expect(pagina.items).toHaveLength(50)
  })

  it.each(['sin eco', 'otro origen', 'fila ajena'])('con origen pedido rechaza el payload que no lo honra: %s', async (caso) => {
    const payload: Record<string, unknown> = { ...payloadFiltrado(), origen: 'landing' }
    if (caso === 'sin eco') delete payload.origen
    if (caso === 'otro origen') payload.origen = 'formulario'
    if (caso === 'fila ajena') (payload.items as Array<Record<string, unknown>>)[3]!.origen = 'referido'
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(payload)))
    await expect(listarCarteraPagina({ ...filtros, origen: 'landing' }, null)).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  // Procedencia (19/09): mismo contrato que origen — viaja solo cuando recorta,
  // vuelve como eco, y las filas traen `procedencia` + `cargado_por`.
  function payloadManual() {
    const payload = payloadFiltrado()
    return {
      ...payload, procedencia: 'manual',
      items: payload.items.map((i) => ({ ...i, procedencia: 'manual', cargado_por: 'perfil-autor' })),
    }
  }
  it('la procedencia viaja solo cuando recorta y vuelve aplicada con el autor por fila', async () => {
    let cuerpo: unknown
    server.use(http.post(RPC_INTEGRADA, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(payloadManual())
    }))
    const pagina = await listarCarteraPagina({ ...filtros, procedencia: 'manual' }, null)
    expect(cuerpo).toEqual({ p_limite: 51, p_desde: '2026-09-01', p_hasta: '2026-09-03', p_procedencia: 'manual' })
    expect(pagina.items).toHaveLength(50)
    expect(pagina.items.every((l) => l.procedencia === 'manual' && l.cargado_por === 'perfil-autor')).toBe(true)
  })
  it('«todas» no viaja, y un servidor sin procedencia deja el lead sin chip (null), nunca inventado', async () => {
    let cuerpo: unknown
    server.use(http.post(RPC_INTEGRADA, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(payloadFiltrado())
    }))
    const pagina = await listarCarteraPagina({ ...filtros, procedencia: 'todas' }, null)
    expect(cuerpo).toEqual({ p_limite: 51, p_desde: '2026-09-01', p_hasta: '2026-09-03' })
    expect(pagina.items[0]?.procedencia).toBeNull()
    expect(pagina.items[0]?.cargado_por).toBeNull()
  })
  it('sin filtro, la fila del sistema llega con procedencia y sin autor', async () => {
    const payload = payloadFiltrado()
    payload.items = payload.items.map((i) => ({ ...i, procedencia: 'sistema', cargado_por: null }))
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json({ ...payload, procedencia: null })))
    const pagina = await listarCarteraPagina(filtros, null)
    expect(pagina.items[0]).toMatchObject({ procedencia: 'sistema', cargado_por: null })
  })
  it.each(['sin eco', 'otra procedencia', 'fila ajena', 'valor inválido'])('con procedencia pedida rechaza el payload que no la honra: %s', async (caso) => {
    const payload: Record<string, unknown> = payloadManual()
    if (caso === 'sin eco') delete payload.procedencia
    if (caso === 'otra procedencia') payload.procedencia = 'sistema'
    if (caso === 'fila ajena') (payload.items as Array<Record<string, unknown>>)[3]!.procedencia = 'sistema'
    if (caso === 'valor inválido') (payload.items as Array<Record<string, unknown>>)[3]!.procedencia = 'puente'
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(payload)))
    await expect(listarCarteraPagina({ ...filtros, procedencia: 'manual' }, null)).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('cuenta reasignados en toda la base filtrada y conserva la procedencia de cada fila', async () => {
    const payload = payloadFiltrado(2)
    payload.resumen.totales.reasignados = 1
    const items = payload.items.map((item, i) => ({ ...item, reasignado: i === 0,
      procedencia: i === 0 ? 'manual' : 'sistema' }))
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json({ ...payload, reasignados: false, items })))
    const pagina = await listarCarteraPagina(filtros, null)
    expect(pagina.resumen?.totales.reasignados).toBe(1)
    expect(pagina.items).toMatchObject([{ reasignado: true, procedencia: 'manual' },
      { reasignado: false, procedencia: 'sistema' }])
  })

  it('el filtro de reasignados viaja al servidor y exige eco, cifra y filas coherentes', async () => {
    let cuerpo: unknown
    const payload = payloadFiltrado(2)
    payload.resumen.totales.reasignados = 2
    server.use(http.post(RPC_INTEGRADA, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json({ ...payload, reasignados: true,
        items: payload.items.map((item) => ({ ...item, reasignado: true })) })
    }))
    const pagina = await listarCarteraPagina({ ...filtros, reasignados: true }, null)
    expect(cuerpo).toEqual({ p_limite: 51, p_desde: '2026-09-01', p_hasta: '2026-09-03', p_reasignados: true })
    expect(pagina.resumen?.totales.reasignados).toBe(2)
    expect(pagina.items.every((lead) => lead.reasignado === true)).toBe(true)
  })

  it.each(['sin eco', 'sin cifra', 'fila sin marca'])('rechaza reasignados inconsistentes: %s', async (caso) => {
    const payload: Record<string, unknown> = payloadFiltrado(2)
    payload.reasignados = true
    const resumen = payload.resumen as ReturnType<typeof payloadFiltrado>['resumen']
    resumen.totales.reasignados = 2
    payload.items = (payload.items as ReturnType<typeof fila>[]).map((item) => ({ ...item, reasignado: true }))
    if (caso === 'sin eco') delete payload.reasignados
    if (caso === 'sin cifra') delete (resumen.totales as { reasignados?: number }).reasignados
    if (caso === 'fila sin marca') (payload.items as Array<Record<string, unknown>>)[0]!.reasignado = false
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(payload)))
    await expect(listarCarteraPagina({ ...filtros, reasignados: true }, null)).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })
})

// «Gestión vigente» (01/10/2026): parte la etapa `nuevo` del Pipeline en
// «Nuevo» y «Gestionado». A diferencia de origen y procedencia, el servidor NO
// devuelve eco: la forma de la respuesta es la misma con o sin el recorte. Lo
// que se fija aquí es qué viaja — y, sobre todo, cuándo NO viaja.
describe('cartera integrada: recorte por gestión vigente (p_gestion)', () => {
  /** Respuesta de una columna del Pipeline: sin rango de fechas. */
  function payloadColumna(n = 2) {
    return {
      ...payloadFiltrado(n), desde: null, hasta: null,
      items: Array.from({ length: n }, (_, i) => fila(i, { recibido_en: null, recepcion_aproximada: null })),
    }
  }
  async function cuerpoDe(filtros: Parameters<typeof listarCarteraPagina>[0], ruta = RPC_INTEGRADA) {
    let cuerpo: unknown
    server.use(http.post(ruta, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(ruta === RPC ? [] : payloadColumna())
    }))
    const pagina = await listarCarteraPagina(filtros, null)
    return { cuerpo, pagina }
  }

  it.each(['con_gestion', 'sin_gestion'] as const)('«%s» viaja tal cual junto a la etapa de la columna', async (gestion) => {
    const { cuerpo, pagina } = await cuerpoDe({ integrada: true, etapa: 'nuevo', vendedorId: 'todos', gestion })

    expect(cuerpo).toEqual({ p_limite: 51, p_etapa: 'nuevo', p_gestion: gestion })
    // Sin eco que comprobar: la respuesta se acepta con su forma de siempre.
    expect(pagina.items).toHaveLength(2)
    expect(pagina.resumen?.totales.vivos).toBe(2)
  })

  it('las columnas que no parten su etapa NO mandan p_gestion', async () => {
    for (const etapa of ['contactado', 'reunion_agendada', 'propuesta_enviada'] as const) {
      const { cuerpo } = await cuerpoDe({ integrada: true, etapa, vendedorId: 'todos' })
      expect(cuerpo).toEqual({ p_limite: 51, p_etapa: etapa })
      expect(cuerpo).not.toHaveProperty('p_gestion')
    }
  })

  it('viaja con el analista del filtro, y con «por repartir»', async () => {
    const conAnalista = await cuerpoDe({ integrada: true, etapa: 'nuevo', vendedorId: 'v-7', gestion: 'con_gestion' })
    expect(conAnalista.cuerpo).toEqual({ p_limite: 51, p_etapa: 'nuevo', p_vendedor_id: 'v-7', p_gestion: 'con_gestion' })

    const sinAsignar = await cuerpoDe({ integrada: true, etapa: 'nuevo', vendedorId: 'sin_asignar', gestion: 'sin_gestion' })
    expect(sinAsignar.cuerpo).toEqual({ p_limite: 51, p_etapa: 'nuevo', p_sin_asignar: true, p_gestion: 'sin_gestion' })
  })

  it('la página siguiente conserva el recorte junto al cursor', async () => {
    let cuerpo: unknown
    server.use(http.post(RPC_INTEGRADA, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(payloadColumna())
    }))

    await listarCarteraPagina(
      { integrada: true, etapa: 'nuevo', gestion: 'con_gestion' },
      { actualizadoEn: '2026-08-01T00:00:00.000Z', id: 'lead-050' },
    )

    expect(cuerpo).toEqual({
      p_limite: 51, p_antes_de: '2026-08-01T00:00:00.000Z', p_antes_id: 'lead-050', p_etapa: 'nuevo', p_gestion: 'con_gestion',
    })
  })

  it('fuera de la lista integrada no viaja: `cartera_pagina_fn` no conoce el parámetro', async () => {
    const { cuerpo } = await cuerpoDe({ integrada: false, etapa: 'nuevo', gestion: 'con_gestion' }, RPC)

    expect(cuerpo).toEqual({ p_limite: 51, p_etapa: 'nuevo' })
  })

  // ESTADO DE PRODUCCIÓN: la pantalla puede llegar antes que la migración. Un
  // servidor que aún no tiene el parámetro no encuentra la función con esa
  // firma (PGRST202). Eso es un ERROR con su código, nunca una lista vacía que
  // la columna pintaría como «sin leads».
  it('servidor todavía sin p_gestion: falla con su código, no devuelve una lista vacía', async () => {
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(
      { code: 'PGRST202', message: 'Could not find the function crm.cartera_filtrada_fn(p_etapa, p_gestion, p_limite) in the schema cache', details: null, hint: null },
      { status: 404 },
    )))

    const intento = listarCarteraPagina({ integrada: true, etapa: 'nuevo', gestion: 'con_gestion' }, null)

    await expect(intento).rejects.toBeInstanceOf(CrmApiError)
    await expect(intento).rejects.toMatchObject({ code: 'PGRST202', message: 'No se pudo cargar la cartera.' })
  })

  it('un valor que el servidor rechaza (22023) también llega como error', async () => {
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(
      { code: '22023', message: 'Gestión no válida', details: null, hint: null },
      { status: 400 },
    )))

    await expect(listarCarteraPagina({ integrada: true, etapa: 'nuevo', gestion: 'sin_gestion' }, null))
      .rejects.toMatchObject({ code: '22023' })
  })

  // Regla del 01/10: un resultado de llamada DESHECHO no cuenta como gestión,
  // pero la fila conserva su sello de último contacto. Una fila «sin gestión»
  // con analista y con un contacto POSTERIOR a su tenencia es correcta: quien
  // decide es el servidor mirando cada gestión, y aquí no se valida el recíproco.
  it('acepta una fila «sin gestión» cuyo último contacto es posterior a su tenencia', async () => {
    const deshecha = fila(0, {
      vendedor_id: 'v-7',
      tenencia_desde: '2026-09-20T15:00:00.000Z',
      ultimo_contacto_en: '2026-09-28T16:30:00.000Z',
      recibido_en: null, recepcion_aproximada: null,
    })
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json({ ...payloadColumna(1), items: [deshecha] })))

    const pagina = await listarCarteraPagina({ integrada: true, etapa: 'nuevo', vendedorId: 'v-7', gestion: 'sin_gestion' }, null)

    expect(pagina.items).toHaveLength(1)
    expect(pagina.items[0]).toMatchObject({
      id: 'lead-000', vendedor_id: 'v-7',
      tenencia_desde: '2026-09-20T15:00:00.000Z', ultimo_contacto_en: '2026-09-28T16:30:00.000Z',
    })
    expect(pagina.resumen?.totales.vivos).toBe(1)
  })

  // …y el otro lado tampoco: un lead sin sello de último contacto puede venir en
  // «con gestión» (el sello y la regla son dos lecturas distintas del timeline).
  it('acepta una fila «con gestión» sin sello de último contacto', async () => {
    const sinSello = fila(0, {
      vendedor_id: 'v-7', tenencia_desde: '2026-09-20T15:00:00.000Z', ultimo_contacto_en: null,
      recibido_en: null, recepcion_aproximada: null,
    })
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json({ ...payloadColumna(1), items: [sinSello] })))

    const pagina = await listarCarteraPagina({ integrada: true, etapa: 'nuevo', vendedorId: 'v-7', gestion: 'con_gestion' }, null)

    expect(pagina.items).toHaveLength(1)
    expect(pagina.items[0]).toMatchObject({ id: 'lead-000', ultimo_contacto_en: null })
  })
})

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

describe('cartera integrada: filtro y conteos por potencial (p_potencial)', () => {
  /** Diez leads repartidos: lo que el servidor cuenta ANTES de aplicar el filtro. */
  const CONTEOS = { filtro: null, estrella: 2, tibio: 3, frio: 1, sin_marca: 4 }
  /** Respuesta de la tabla de Leads (sin rango de fechas) con `n` leads y el bloque de potencial dado. */
  function payloadLeads(n: number, potencial?: unknown) {
    const base = {
      ...payloadFiltrado(n), desde: null, hasta: null,
      items: Array.from({ length: Math.min(n, 51) }, (_, i) => fila(i, { recibido_en: null, recepcion_aproximada: null })),
    }
    return potencial === undefined ? base : { ...base, resumen: { ...base.resumen, potencial } }
  }
  async function pedir(filtros: Parameters<typeof listarCarteraPagina>[0], respuesta: ReturnType<typeof payloadLeads>, cursor: Parameters<typeof listarCarteraPagina>[1] = null) {
    let cuerpo: unknown
    server.use(http.post(RPC_INTEGRADA, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(respuesta)
    }))
    const pagina = await listarCarteraPagina(filtros, cursor)
    return { cuerpo, pagina }
  }

  it('sin filtro no viaja, y los conteos del servidor llegan a la pantalla', async () => {
    const { cuerpo, pagina } = await pedir({ integrada: true }, payloadLeads(10, CONTEOS))
    expect(cuerpo).toEqual({ p_limite: 51 })
    expect(pagina.resumen?.potencial).toEqual(CONTEOS)
    expect(pagina.resumen?.totales.vivos).toBe(10)
  })

  it.each(['estrella', 'tibio', 'frio', 'sin_marca'] as const)('«%s» viaja tal cual y vuelve con su eco y el total del nivel', async (nivel) => {
    const { cuerpo, pagina } = await pedir({ integrada: true, potencial: nivel }, payloadLeads(CONTEOS[nivel], { ...CONTEOS, filtro: nivel }))
    expect(cuerpo).toEqual({ p_limite: 51, p_potencial: nivel })
    expect(pagina.items).toHaveLength(CONTEOS[nivel])
    // Los cuatro conteos son los de SIN filtro: no cambian al elegir un nivel.
    expect(pagina.resumen?.potencial).toEqual({ ...CONTEOS, filtro: nivel })
  })

  it('se combina con los demás filtros y la página siguiente lo conserva junto al cursor', async () => {
    const { cuerpo } = await pedir(
      { integrada: true, etapa: 'contactado', vendedorId: 'v-1', potencial: 'estrella' },
      payloadLeads(2, { ...CONTEOS, filtro: 'estrella' }),
      { actualizadoEn: '2026-08-01T00:00:00.000Z', id: 'lead-049' },
    )
    expect(cuerpo).toEqual({
      p_limite: 51, p_antes_de: '2026-08-01T00:00:00.000Z', p_antes_id: 'lead-049',
      p_etapa: 'contactado', p_vendedor_id: 'v-1', p_potencial: 'estrella',
    })
  })

  it('ESTADO con el potencial apagado: un resumen sin el bloque es válido y no trae conteos', async () => {
    const { pagina } = await pedir({ integrada: true }, payloadLeads(10))
    expect(pagina.resumen).toBeDefined()
    expect(pagina.resumen && 'potencial' in pagina.resumen).toBe(false)
  })

  it.each([
    ['sin el bloque', payloadLeads(3)],
    ['con el bloque en null', payloadLeads(3, null)],
    ['con el eco de otro nivel', payloadLeads(3, { ...CONTEOS, filtro: 'estrella' })],
    ['sin eco', payloadLeads(3, CONTEOS)],
    ['con un total que no es el del nivel', payloadLeads(5, { ...CONTEOS, filtro: 'tibio' })],
    ['con un bloque que no se entiende', payloadLeads(3, { ...CONTEOS, filtro: 'tibio', tibio: '3' })],
  ])('con el filtro pedido, una respuesta %s se rechaza: nunca una lista sin acreditar', async (_caso, respuesta) => {
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(respuesta)))
    await expect(listarCarteraPagina({ integrada: true, potencial: 'tibio' }, null)).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it.each([
    ['conteos que no suman el total', payloadLeads(9, CONTEOS)],
    ['un eco que nadie pidió', payloadLeads(3, { ...CONTEOS, filtro: 'tibio' })],
  ])('sin filtro, se rechaza %s', async (_caso, respuesta) => {
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(respuesta)))
    await expect(listarCarteraPagina({ integrada: true }, null)).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('sin filtro, un bloque que este bundle no entiende NO tumba la lista: se queda sin fila de potencial', async () => {
    // Un nivel nuevo en el servidor antes que en la pantalla: la lista sigue viva.
    const { pagina } = await pedir({ integrada: true }, payloadLeads(10, { ...CONTEOS, filtro: 'caliente' }))
    expect(pagina.items).toHaveLength(10)
    expect(pagina.resumen && 'potencial' in pagina.resumen).toBe(false)
  })

  it('55000 con el filtro puesto = el potencial se apagó: error propio, no «se cayó la cartera»', async () => {
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(
      { code: '55000', message: 'El potencial del lead no está habilitado', details: null, hint: null }, { status: 400 },
    )))
    const intento = listarCarteraPagina({ integrada: true, potencial: 'estrella' }, null)
    await expect(intento).rejects.toBeInstanceOf(CrmApiError)
    await expect(intento).rejects.toMatchObject({ code: 'POTENCIAL_APAGADO' })
  })

  it('un 55000 sin el filtro pedido se queda con su código', async () => {
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(
      { code: '55000', message: 'otra cosa', details: null, hint: null }, { status: 400 },
    )))
    await expect(listarCarteraPagina({ integrada: true }, null)).rejects.toMatchObject({ code: '55000', message: 'No se pudo cargar la cartera.' })
  })

  it('servidor todavía sin p_potencial: falla con su código, no devuelve una lista vacía', async () => {
    server.use(http.post(RPC_INTEGRADA, () => HttpResponse.json(
      { code: 'PGRST202', message: 'Could not find the function crm.cartera_filtrada_fn(p_limite, p_potencial) in the schema cache', details: null, hint: null },
      { status: 404 },
    )))
    await expect(listarCarteraPagina({ integrada: true, potencial: 'frio' }, null)).rejects.toMatchObject({ code: 'PGRST202' })
  })

  it('fuera de la lista integrada no viaja: `cartera_pagina_fn` no conoce el parámetro', async () => {
    let cuerpo: unknown
    server.use(http.post(RPC, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json([])
    }))
    await listarCarteraPagina({ potencial: 'estrella' }, null)
    expect(cuerpo).toEqual({ p_limite: 51 })
  })
})

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

  it('traduce «sin_asignar» a p_sin_asignar y un analista a p_vendedor_id', async () => {
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
