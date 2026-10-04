// @vitest-environment node
// Contrato HTTP de la vista del supervisor (F4): la base del ámbito con o sin los «No contactar» (B6b), el panel por
// analista (`base_gestion_resumen`, en producción), el detalle de una cifra (B6b) y «Quitar No contactar» (B2, en
// producción). La B6b AÚN NO está en producción: el servidor de hoy responde PGRST202 a `p_incluir_vetados` y a la
// lectura del detalle, y eso NO puede romper la lista ni fabricar un cero.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  CrmApiError,
  baseGestionResumen,
  baseGestionResumenDetalle,
  leerBaseGestion,
  levantarNoContactar,
  obtenerBaseGestion,
} from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

const ANALISTA = '22222222-2222-4222-8222-222222222222'
const LEAD = '11111111-1111-4111-8111-111111111111'
const FILA = {
  lead_id: LEAD, nombre_completo: 'ROSA QUISPE', telefono: '+51987654321', distrito: 'Miraflores', origen: 'landing',
  categoria_interes: null, monto_estimado: '30000.00', moneda: 'USD', motivo_descarte: 'no_responde',
  descartado_en: '2026-09-20T14:00:00+00:00', dias_desde_descarte: 12, etapa_maxima: 'reunion_agendada', intentos: '2',
  ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-10-01T15:00:00+00:00', proxima_llamada_en: null,
  rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: ANALISTA, gestiona: 'CARMEN JARAMILLO',
  recibido_en: '2026-08-15T15:00:00+00:00',
}
// Lo que manda la B6b al final de cada fila.
const SIN_VETO = { no_contactar: false, no_contactar_en: null, no_contactar_motivo: null, no_contactar_por: null }
const VETADA = {
  ...FILA, lead_id: '33333333-3333-4333-8333-333333333333', nombre_completo: 'JUAN VETADO',
  no_contactar: true, no_contactar_en: '2026-09-28T16:00:00+00:00', no_contactar_motivo: 'Pidió que no lo llamen más', no_contactar_por: 'ANA PÉREZ',
}
const PGRST202 = (fn: string) => HttpResponse.json(
  { code: 'PGRST202', message: `Could not find the function crm.${fn}(p_incluir_vetados) in the schema cache`, details: null, hint: null },
  { status: 404 },
)

/** Registra el cuerpo de CADA petición a la RPC (para contar reintentos). */
function capturar(fn: string, responder: (cuerpo: Record<string, unknown>, n: number) => Response) {
  const cuerpos: Record<string, unknown>[] = []
  server.use(http.post(RPC(fn), async ({ request }) => {
    const cuerpo = (await request.json()) as Record<string, unknown>
    cuerpos.push(cuerpo)
    return responder(cuerpo, cuerpos.length)
  }))
  return cuerpos
}

describe('leerBaseGestion: la base del ámbito para Supervisión y Gerencia (F4)', () => {
  it('con el interruptor apagado pide p_incluir_vetados = false (así sabe si el servidor ya tiene la B6b)', async () => {
    const cuerpos = capturar('obtener_base_gestion', () => HttpResponse.json([{ ...FILA, ...SIN_VETO }]))
    const lectura = await leerBaseGestion(null, { incluirVetados: false })
    expect(cuerpos).toEqual([{ p_incluir_vetados: false }])
    expect(lectura.conVetados).toBe(true)
    expect(lectura.filas).toEqual([expect.objectContaining({ lead_id: LEAD, intentos: 2, no_contactar: false })])
  })

  it('con «Ver no contactar» pide los vetados y lee la marca: cuándo, motivo y quién', async () => {
    const cuerpos = capturar('obtener_base_gestion', () => HttpResponse.json([{ ...FILA, ...SIN_VETO }, VETADA]))
    const { filas, conVetados } = await leerBaseGestion(null, { incluirVetados: true })
    expect(cuerpos).toEqual([{ p_incluir_vetados: true }])
    expect(conVetados).toBe(true)
    expect(filas[1]).toMatchObject({
      nombre_completo: 'JUAN VETADO', no_contactar: true, no_contactar_en: '2026-09-28T16:00:00+00:00',
      no_contactar_motivo: 'Pidió que no lo llamen más', no_contactar_por: 'ANA PÉREZ',
    })
  })

  it('la marca que vino de OTRO lead de la persona llega sin cuándo, motivo ni quién: la fila se pinta igual', async () => {
    capturar('obtener_base_gestion', () => HttpResponse.json([{ ...VETADA, no_contactar_en: null, no_contactar_motivo: null, no_contactar_por: null }]))
    const { filas } = await leerBaseGestion(null, { incluirVetados: true })
    expect(filas).toEqual([expect.objectContaining({ no_contactar: true, no_contactar_en: null, no_contactar_por: null })])
  })

  it('ESTADO DE PRODUCCIÓN (B6b sin aplicar): PGRST202 → se vuelve a pedir SIN el parámetro, la lista llega y conVetados = false', async () => {
    const cuerpos = capturar('obtener_base_gestion', (cuerpo) => ('p_incluir_vetados' in cuerpo ? PGRST202('obtener_base_gestion') : HttpResponse.json([FILA])))
    const lectura = await leerBaseGestion(null, { incluirVetados: true })
    expect(cuerpos).toEqual([{ p_incluir_vetados: true }, {}])
    expect(lectura.conVetados).toBe(false)
    // Sin los campos de la B6b la fila no está vetada (y se pinta).
    expect(lectura.filas).toEqual([expect.objectContaining({ lead_id: LEAD })])
    expect(lectura.filas[0]?.no_contactar).toBeUndefined()
  })

  it('el filtro por analista viaja junto al de los vetados, y se conserva en el reintento', async () => {
    const cuerpos = capturar('obtener_base_gestion', (cuerpo) => ('p_incluir_vetados' in cuerpo ? PGRST202('obtener_base_gestion') : HttpResponse.json([])))
    await leerBaseGestion(ANALISTA, { incluirVetados: false })
    expect(cuerpos).toEqual([{ p_vendedor_id: ANALISTA, p_incluir_vetados: false }, { p_vendedor_id: ANALISTA }])
  })

  it('sin la opción no pregunta (la llamada del analista, idéntica a la de siempre)', async () => {
    const cuerpos = capturar('obtener_base_gestion', () => HttpResponse.json([FILA]))
    const lectura = await leerBaseGestion()
    expect(cuerpos).toEqual([{}])
    expect(lectura.conVetados).toBeNull()
    expect(await obtenerBaseGestion()).toHaveLength(1)
  })

  it('una fila vetada fuera de contrato (marca que no es booleana) no se pinta; las demás sí', async () => {
    capturar('obtener_base_gestion', () => HttpResponse.json([{ ...FILA, ...SIN_VETO }, { ...VETADA, no_contactar: 'si' }, { ...VETADA, lead_id: 'motivo-raro', no_contactar_motivo: 42 }]))
    const { filas } = await leerBaseGestion(null, { incluirVetados: true })
    expect(filas.map((f) => f.lead_id)).toEqual([LEAD])
  })

  it('un analista que pide los vetados recibe SIN_PERMISO (42501), no una lista vacía', async () => {
    capturar('obtener_base_gestion', () => HttpResponse.json({ code: '42501', message: 'Solo Supervision y Gerencia ven los No contactar' }, { status: 403 }))
    await expect(leerBaseGestion(null, { incluirVetados: true })).rejects.toMatchObject({ code: 'SIN_PERMISO' })
  })

  it('si el reintento sin parámetro también falla, es un error con su código (no una base vacía)', async () => {
    capturar('obtener_base_gestion', (cuerpo) => ('p_incluir_vetados' in cuerpo ? PGRST202('obtener_base_gestion') : HttpResponse.json({ code: 'XX000', message: 'boom' }, { status: 500 })))
    const error = await leerBaseGestion(null, { incluirVetados: false }).catch((e: unknown) => e)
    expect(error).toBeInstanceOf(CrmApiError)
  })
})

describe('baseGestionResumen: el panel por analista', () => {
  const FILA_RESUMEN = { vendedor_id: ANALISTA, nombre: 'CARMEN JARAMILLO', en_base: '12', rellamadas_hoy: 3, intentos_hoy: '5', reactivaciones_mes: 2 }

  it('pide el panel sin parámetros (el ámbito lo pone la sesión) y lee las cifras como números', async () => {
    const cuerpos = capturar('base_gestion_resumen', () => HttpResponse.json([FILA_RESUMEN]))
    expect(await baseGestionResumen()).toEqual([{ vendedor_id: ANALISTA, nombre: 'CARMEN JARAMILLO', en_base: 12, rellamadas_hoy: 3, intentos_hoy: 5, reactivaciones_mes: 2 }])
    expect(cuerpos).toEqual([{}])
  })

  it('supervisor sin analistas: lista vacía (es un estado real, no un error)', async () => {
    capturar('base_gestion_resumen', () => HttpResponse.json([]))
    expect(await baseGestionResumen()).toEqual([])
  })

  it('una fila corrupta (cifra negativa, sin nombre) no se pinta', async () => {
    capturar('base_gestion_resumen', () => HttpResponse.json([FILA_RESUMEN, { ...FILA_RESUMEN, vendedor_id: 'x', en_base: -1 }, { ...FILA_RESUMEN, vendedor_id: 'y', nombre: null }]))
    expect((await baseGestionResumen()).map((f) => f.vendedor_id)).toEqual([ANALISTA])
  })

  it('el analista recibe SIN_PERMISO (42501)', async () => {
    capturar('base_gestion_resumen', () => HttpResponse.json({ code: '42501', message: 'Solo Supervision y Gerencia ven el resumen de la base' }, { status: 403 }))
    await expect(baseGestionResumen()).rejects.toMatchObject({ code: 'SIN_PERMISO' })
  })
})

describe('baseGestionResumenDetalle: lo que hay detrás de una cifra (B6b)', () => {
  const DETALLE = { lead_id: LEAD, nombre_completo: 'ROSA QUISPE', en: '2026-10-03T15:00:00+00:00', detalle: 'no_contesto', autor: 'CARMEN JARAMILLO', sigue_en_base: true }

  it('manda el analista y la cifra, y lee las filas', async () => {
    const cuerpos = capturar('base_gestion_resumen_detalle', () => HttpResponse.json([DETALLE, { ...DETALLE, lead_id: 'otro', detalle: null, autor: null, sigue_en_base: false }]))
    const filas = await baseGestionResumenDetalle(ANALISTA, 'intentos_hoy')
    expect(cuerpos).toEqual([{ p_vendedor_id: ANALISTA, p_cifra: 'intentos_hoy' }])
    expect(filas).toEqual([DETALLE, { ...DETALLE, lead_id: 'otro', detalle: null, autor: null, sigue_en_base: false }])
  })

  it('ESTADO DE PRODUCCIÓN (B6b sin aplicar): PGRST202 → null («no disponible»), nunca una lista vacía', async () => {
    capturar('base_gestion_resumen_detalle', () => PGRST202('base_gestion_resumen_detalle'))
    expect(await baseGestionResumenDetalle(ANALISTA, 'reactivaciones_mes')).toBeNull()
  })

  it('filas corruptas (sin booleano, sin fecha) no se pintan', async () => {
    capturar('base_gestion_resumen_detalle', () => HttpResponse.json([DETALLE, { ...DETALLE, lead_id: 'a', sigue_en_base: 'si' }, { ...DETALLE, lead_id: 'b', en: null }]))
    expect((await baseGestionResumenDetalle(ANALISTA, 'intentos_hoy'))?.map((f) => f.lead_id)).toEqual([LEAD])
  })

  it('un analista fuera del ámbito del supervisor (P0002) y el rol sin permiso (42501) son errores con su código', async () => {
    capturar('base_gestion_resumen_detalle', () => HttpResponse.json({ code: 'P0002', message: 'Analista fuera de tu ámbito' }, { status: 400 }))
    await expect(baseGestionResumenDetalle(ANALISTA, 'intentos_hoy')).rejects.toMatchObject({ code: 'FUERA_DE_COLA', message: 'Analista fuera de tu ámbito' })
    capturar('base_gestion_resumen_detalle', () => HttpResponse.json({ code: '42501', message: 'x' }, { status: 403 }))
    await expect(baseGestionResumenDetalle(ANALISTA, 'intentos_hoy')).rejects.toMatchObject({ code: 'SIN_PERMISO' })
  })
})

describe('levantarNoContactar: «Quitar No contactar» (D5)', () => {
  it('manda el lead y el motivo sin espacios de más; devuelve cuántos leads de la persona se liberaron', async () => {
    const cuerpos = capturar('levantar_no_contactar', () => HttpResponse.json({ ok: true, lead_id: LEAD, inversionista_id: null, leads_afectados: '3' }))
    expect(await levantarNoContactar(LEAD, '  Volvió a pedir información  ')).toEqual({ leadsAfectados: 3 })
    expect(cuerpos).toEqual([{ p_lead_id: LEAD, p_motivo: 'Volvió a pedir información' }])
  })

  it('42501 de Supervisión con leads de la persona fuera de su equipo: «pídelo a Gerencia»', async () => {
    capturar('levantar_no_contactar', () => HttpResponse.json({ code: '42501', message: 'La persona tiene leads fuera de tu equipo: pídelo a Gerencia' }, { status: 403 }))
    await expect(levantarNoContactar(LEAD, 'motivo largo')).rejects.toMatchObject({ code: 'SIN_PERMISO', message: 'La persona tiene leads fuera de tu equipo: pídelo a Gerencia.' })
  })

  it('42501 de otro rol: dice quién puede', async () => {
    capturar('levantar_no_contactar', () => HttpResponse.json({ code: '42501', message: 'Solo Gerencia o Supervisión pueden levantar No contactar' }, { status: 403 }))
    await expect(levantarNoContactar(LEAD, 'motivo largo')).rejects.toMatchObject({ code: 'SIN_PERMISO', message: 'Solo Supervisión o Gerencia pueden quitar «No contactar».' })
  })

  it('40001 (otra sesión tiene un lead de la persona): pide reintentar con un texto que no habla de repartos', async () => {
    capturar('levantar_no_contactar', () => HttpResponse.json({ code: '40001', message: 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo' }, { status: 409 }))
    await expect(levantarNoContactar(LEAD, 'motivo largo')).rejects.toMatchObject({
      code: 'REINTENTAR', message: 'Otra sesión está trabajando uno de los leads de la persona. Vuelve a intentarlo en unos segundos.',
    })
  })

  it('22023 (el motivo lleva el documento) llega con el texto del servidor', async () => {
    capturar('levantar_no_contactar', () => HttpResponse.json({ code: '22023', message: 'El motivo no debe contener el número de documento' }, { status: 400 }))
    await expect(levantarNoContactar(LEAD, 'DNI 12345678')).rejects.toMatchObject({ code: 'REGLA_SERVIDOR', message: 'El motivo no debe contener el número de documento' })
  })

  it('una respuesta fuera de contrato no se toma por buena', async () => {
    capturar('levantar_no_contactar', () => HttpResponse.json({ ok: true }))
    await expect(levantarNoContactar(LEAD, 'motivo largo')).rejects.toMatchObject({ code: 'LEVANTAR_NO_CONTACTAR_CONTRACT' })
  })
})
