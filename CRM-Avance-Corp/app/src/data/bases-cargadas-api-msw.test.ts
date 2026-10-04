// @vitest-environment node
// Contrato HTTP de «Bases cargadas» (F5): lo que viaja a cada puerta y cómo se lee lo que vuelve. B8 está en producción
// (crear_base, cargar_base_lote, armar_base_crm); B9 y B10 AÚN NO: el servidor de hoy responde PGRST202 y eso NO puede
// romper la pantalla (lecturas → null, «disponible pronto»; escrituras → NO_DISPONIBLE), ni fabricar un cero.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  ErrorBases,
  armarBaseCrm,
  cargarBaseLote,
  contactosDeBase,
  crearBase,
  recogerDeBase,
  repartirBase,
  seguimientoBase,
  seguimientoBaseDetalle,
  seguimientoBases,
} from './bases-cargadas-api'
import { reactivarLeadBase, registrarIntentoBase } from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

const OP = '99999999-9999-4999-8999-999999999999'
const BASE = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const SUP = '55555555-5555-4555-8555-555555555555'
const ANA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const LEAD = '11111111-1111-4111-8111-111111111111'

function capturar(fn: string, responder: (cuerpo: Record<string, unknown>, n: number) => Response) {
  const cuerpos: Record<string, unknown>[] = []
  server.use(http.post(RPC(fn), async ({ request }) => {
    const cuerpo = (await request.json()) as Record<string, unknown>
    cuerpos.push(cuerpo)
    return responder(cuerpo, cuerpos.length)
  }))
  return cuerpos
}
const error = (code: string, message: string, details: string | null = null, status = 400) => HttpResponse.json({ code, message, details, hint: null }, { status })
const PGRST202 = (fn: string) => error('PGRST202', `Could not find the function crm.${fn} in the schema cache`, null, 404)

describe('crearBase (B8, en producción)', () => {
  it('Supervisión: operación, nombre sin espacios de más, origen «archivo» y el archivo; SIN supervisor', async () => {
    const cuerpos = capturar('crear_base', () => HttpResponse.json({ ok: true, operacion_id: OP, base_id: BASE, origen: 'archivo', supervisor_id: SUP }))
    const r = await crearBase({ operacionId: OP, nombre: '  Feria 2025 ', archivoNombre: 'feria.xlsx' })
    expect(cuerpos).toEqual([{ p_operacion_id: OP, p_nombre: 'Feria 2025', p_origen: 'archivo', p_archivo_nombre: 'feria.xlsx' }])
    expect(r).toMatchObject({ base_id: BASE, supervisor_id: SUP })
  })
  it('Gerencia manda el supervisor dueño (E11)', async () => {
    const cuerpos = capturar('crear_base', () => HttpResponse.json({ ok: true, base_id: BASE, supervisor_id: SUP }))
    await crearBase({ operacionId: OP, nombre: 'Feria', archivoNombre: 'f.csv', supervisorId: SUP })
    expect(cuerpos[0]).toMatchObject({ p_supervisor_id: SUP })
  })
  it('nombre repetido (23505) llega con el texto del servidor; sin permiso (42501) también', async () => {
    capturar('crear_base', () => error('23505', 'Ya hay una base viva con ese nombre en la bandeja de ese supervisor'))
    await expect(crearBase({ operacionId: OP, nombre: 'Feria', archivoNombre: 'f.csv' })).rejects.toMatchObject({ code: 'NOMBRE_REPETIDO', message: 'Ya hay una base viva con ese nombre en la bandeja de ese supervisor' })
    capturar('crear_base', () => error('42501', 'Solo Supervisión y Gerencia cargan y arman bases', null, 403))
    await expect(crearBase({ operacionId: OP, nombre: 'Feria', archivoNombre: 'f.csv' })).rejects.toMatchObject({ code: 'SIN_PERMISO' })
  })
  it('una respuesta sin base_id es un fallo de contrato, no una base fantasma', async () => {
    capturar('crear_base', () => HttpResponse.json({ ok: true }))
    await expect(crearBase({ operacionId: OP, nombre: 'Feria', archivoNombre: 'f.csv' })).rejects.toMatchObject({ code: 'BASES_CONTRACT' })
  })
})

describe('cargarBaseLote (B8)', () => {
  const RESPUESTA = {
    ok: true, operacion_id: OP, base_id: BASE,
    lote: { filas: 3, cargadas: 1, ya_existian: 1, no_contactar: 1, invalidas: 0, repetidas: 0 },
    base: { filas_recibidas: 3, cargadas: 1, ya_existian: 1, no_contactar: 1, invalidas: 0, repetidas: 0 },
    filas: [{ fila: '2', veredicto: 'cargada' }, { fila: 3, veredicto: 'ya_existia', motivo: 'con_dueno', lead_id: LEAD }, { fila: 4, veredicto: 'no_contactar', motivo: 'no_insistir' }],
  }
  it('manda las filas tal cual (con su número de fila) y lee el veredicto de cada una', async () => {
    const cuerpos = capturar('cargar_base_lote', () => HttpResponse.json(RESPUESTA))
    const filas = [{ fila: 2, nombre: 'ROSA', telefono: '+51987654321', dni: '45871236' }, { fila: 3, nombre: 'LUIS', telefono: '+51987000111' }]
    const r = await cargarBaseLote({ operacionId: OP, baseId: BASE, filas })
    expect(cuerpos).toEqual([{ p_operacion_id: OP, p_base_id: BASE, p_filas: filas }])
    expect(r.filas).toEqual([
      { fila: 2, veredicto: 'cargada', motivo: null, lead_id: null },
      { fila: 3, veredicto: 'ya_existia', motivo: 'con_dueno', lead_id: LEAD },
      { fila: 4, veredicto: 'no_contactar', motivo: 'no_insistir', lead_id: null },
    ])
    expect(r.lote.cargadas).toBe(1)
  })
  it('otra carga de la misma base en curso (55P03) → OCUPADO (la carga lo reintenta sola)', async () => {
    capturar('cargar_base_lote', () => error('55P03', 'Hay otra carga en curso de esta base; reintenta'))
    await expect(cargarBaseLote({ operacionId: OP, baseId: BASE, filas: [] })).rejects.toMatchObject({ code: 'OCUPADO', message: 'Hay otra carga en curso de esta base; reintenta' })
  })
  it('la red se cortó → RED (la pantalla ofrece «Reintentar» con el mismo id)', async () => {
    server.use(http.post(RPC('cargar_base_lote'), () => HttpResponse.error()))
    await expect(cargarBaseLote({ operacionId: OP, baseId: BASE, filas: [] })).rejects.toMatchObject({ code: 'RED' })
  })
  it('una regla del servidor (22023: tope de la base) llega con su texto', async () => {
    capturar('cargar_base_lote', () => error('22023', 'Una base recibe hasta 5000 filas: ya tiene 4950 y este lote trae 100'))
    await expect(cargarBaseLote({ operacionId: OP, baseId: BASE, filas: [] })).rejects.toMatchObject({ code: 'REGLA_SERVIDOR', message: expect.stringContaining('hasta 5000 filas') })
  })
})

describe('armarBaseCrm (B8)', () => {
  it('manda los leads elegidos; lee incluidos y excluidos por motivo', async () => {
    const cuerpos = capturar('armar_base_crm', () => HttpResponse.json({
      ok: true, operacion_id: OP, base_id: BASE, origen: 'crm', supervisor_id: SUP, recibidos: 3, incluidos: 1, excluidos: 2,
      excluidos_por_motivo: { ocupado: [2], en_gestion: [3] },
      excluidos_detalle: [{ posicion: 2, lead_id: 'l2', motivo: 'ocupado' }, { posicion: 3, lead_id: 'l3', motivo: 'en_gestion' }],
    }))
    const r = await armarBaseCrm({ operacionId: OP, nombre: ' Julio ', leadIds: ['l1', 'l2', 'l3'], supervisorId: SUP })
    expect(cuerpos).toEqual([{ p_operacion_id: OP, p_nombre: 'Julio', p_lead_ids: ['l1', 'l2', 'l3'], p_supervisor_id: SUP }])
    expect(r).toMatchObject({ incluidos: 1, excluidos: 2, excluidos_por_motivo: { ocupado: [2], en_gestion: [3] } })
  })
  it('ningún elegible (22023 con detail): SIN_ELEGIBLES con los motivos', async () => {
    capturar('armar_base_crm', () => error('22023', 'Ningún lead de la lista es elegible: no se crea la base', JSON.stringify({ excluidos_por_motivo: { en_gestion: [1, 2] } })))
    const promesa = armarBaseCrm({ operacionId: OP, nombre: 'Julio', leadIds: ['l1', 'l2'] })
    await expect(promesa).rejects.toBeInstanceOf(ErrorBases)
    await expect(promesa).rejects.toMatchObject({ code: 'SIN_ELEGIBLES', detalle: { en_gestion: [1, 2] } })
  })
})

describe('B10 · seguimiento: con el servidor de hoy (PGRST202) es «disponible pronto», nunca un cero', () => {
  const BASE_FILA = {
    base_id: BASE, nombre: 'Feria 2025', origen: 'archivo', supervisor_id: SUP, supervisor_nombre: 'SUPERVISOR UNO', creado_en: '2026-10-04T15:00:00Z',
    total: 85, sin_repartir: 15, repartidos: '70', sin_tocar: 10, trabajados: 35, en_descanso: 2, citas: 3, reactivados: 1, avance: '0.5',
  }
  it('seguimiento_bases: lee las filas (números de texto incluidos); una fila fuera de contrato no se pinta', async () => {
    capturar('seguimiento_bases', () => HttpResponse.json([BASE_FILA, { ...BASE_FILA, base_id: 'x', total: -1 }]))
    expect(await seguimientoBases()).toEqual([expect.objectContaining({ base_id: BASE, repartidos: 70, avance: 0.5 })])
  })
  it('PGRST202 → null en las tres lecturas', async () => {
    capturar('seguimiento_bases', () => PGRST202('seguimiento_bases'))
    capturar('seguimiento_base', () => PGRST202('seguimiento_base'))
    capturar('seguimiento_base_detalle', () => PGRST202('seguimiento_base_detalle'))
    expect(await seguimientoBases()).toBeNull()
    expect(await seguimientoBase(BASE)).toBeNull()
    expect(await seguimientoBaseDetalle(BASE, null, 'sin_repartir')).toBeNull()
  })
  it('detalle: un contacto fuera del ámbito llega sin id ni nombre (NULL) y se lee igual', async () => {
    capturar('seguimiento_base_detalle', () => HttpResponse.json([{ lead_id: null, nombre_completo: null, estado: 'movido_otra_via', asignado_en: null, ultimo_intento_en: null, ultimo_resultado: null }]))
    expect(await seguimientoBaseDetalle(BASE, null, 'repartidos')).toEqual([expect.objectContaining({ lead_id: null, nombre_completo: null })])
  })

  it('seguimiento_base y su detalle: la base, el analista (solo si hay) y la cifra', async () => {
    const cuerpos = capturar('seguimiento_base', () => HttpResponse.json([{
      analista_id: ANA, analista_nombre: 'ANA', asignados: 40, sin_tocar: 12, sin_tocar_3_dias: 4, trabajados: 28, en_descanso: 2, citas: 3, reactivados: 1,
      ultimo_intento_en: '2026-10-03T15:00:00Z', movidos_otra_via: 1,
    }]))
    expect(await seguimientoBase(BASE)).toEqual([expect.objectContaining({ analista_id: ANA, sin_tocar_3_dias: 4 })])
    expect(cuerpos).toEqual([{ p_base_id: BASE }])
    const detalle = capturar('seguimiento_base_detalle', () => HttpResponse.json([{ lead_id: LEAD, nombre_completo: 'ROSA', estado: 'sin_tocar', asignado_en: '2026-10-01T15:00:00Z', ultimo_intento_en: null, ultimo_resultado: null }]))
    await seguimientoBaseDetalle(BASE, ANA, 'sin_tocar_3_dias')
    await seguimientoBaseDetalle(BASE, null, 'total')
    expect(detalle).toEqual([{ p_base_id: BASE, p_analista_id: ANA, p_cifra: 'sin_tocar_3_dias' }, { p_base_id: BASE, p_cifra: 'total' }])
  })
  it('un fallo de verdad (no PGRST202) sí es error', async () => {
    capturar('seguimiento_bases', () => error('42501', 'Solo Supervisión y Gerencia', null, 403))
    await expect(seguimientoBases()).rejects.toMatchObject({ code: 'SIN_PERMISO' })
  })
})

describe('B9 · repartir, recoger y contactos', () => {
  it('contactos_de_base: la base y el estado pedido; PGRST202 → null', async () => {
    const cuerpos = capturar('contactos_de_base', (_c, n) => (n === 1 ? HttpResponse.json([{
      lead_id: LEAD, nombre_completo: 'ROSA', telefono: '+51987654321', distrito: null, agregado_en: '2026-10-04T15:00:00Z', analista_id: null, analista_nombre: null, estado: 'sin_repartir',
    }]) : PGRST202('contactos_de_base')))
    expect(await contactosDeBase(BASE, 'todos')).toHaveLength(1)
    expect(await contactosDeBase(BASE)).toBeNull()
    expect(cuerpos).toEqual([{ p_base_id: BASE, p_estado: 'todos' }, { p_base_id: BASE, p_estado: 'sin_repartir' }])
  })
  it('repartir en bloque: «Ana 40 · Luis 30» tal cual; lee repartidos, por analista y los omitidos POR MOTIVO (B9)', async () => {
    const cuerpos = capturar('repartir_base', () => HttpResponse.json({
      ok: true, operacion_id: OP, base_id: BASE, modo: 'bloque', repartidos: 70,
      por_analista: [{ analista_id: ANA, cantidad: 40 }, { analista_id: 'luis', cantidad: 30 }],
      omitidos: [{ lead_id: null, motivo: 'en_gestion', cantidad: '3' }, { lead_id: null, motivo: 'ocupado', cantidad: 1 }],
    }))
    const reparto = { modo: 'bloque' as const, asignaciones: [{ analista_id: ANA, cantidad: 40 }, { analista_id: 'luis', cantidad: 30 }] }
    const r = await repartirBase({ operacionId: OP, baseId: BASE, reparto })
    expect(cuerpos).toEqual([{ p_operacion_id: OP, p_base_id: BASE, p_reparto: reparto }])
    expect(r.repartidos).toBe(70)
    expect(r.omitidos).toEqual([{ lead_id: null, motivo: 'en_gestion', cantidad: 3 }, { lead_id: null, motivo: 'ocupado', cantidad: 1 }])
  })

  it('individual con un «ya_asignado»: el omitido trae su lead (cantidad 1 por defecto)', async () => {
    capturar('repartir_base', () => HttpResponse.json({ ok: true, modo: 'individual', repartidos: 1, por_analista: [{ analista_id: ANA, cantidad: 1 }], omitidos: [{ lead_id: LEAD, motivo: 'ya_asignado' }] }))
    const r = await repartirBase({ operacionId: OP, baseId: BASE, reparto: { modo: 'individual', asignaciones: [{ lead_id: LEAD, analista_id: ANA }, { lead_id: 'otro', analista_id: ANA }] } })
    expect(r.omitidos).toEqual([{ lead_id: LEAD, motivo: 'ya_asignado', cantidad: 1 }])
  })

  it('individual con un contacto no elegible (22023, detail {rechazados}): RECHAZADOS con cada lead y su motivo', async () => {
    capturar('repartir_base', () => error('22023', 'Hay contactos que no se pueden repartir', JSON.stringify({ rechazados: [{ lead_id: LEAD, motivo: 'en_gestion' }, { lead_id: 'otro', motivo: 'en_descanso' }] })))
    await expect(repartirBase({ operacionId: OP, baseId: BASE, reparto: { modo: 'individual', asignaciones: [{ lead_id: LEAD, analista_id: ANA }] } }))
      .rejects.toMatchObject({ code: 'RECHAZADOS', detalle: [{ lead_id: LEAD, motivo: 'en_gestion' }, { lead_id: 'otro', motivo: 'en_descanso' }], message: expect.stringContaining('2 contactos no se pueden repartir') })
  })
  it('no alcanzan (22023 con los disponibles en el detail): SIN_DISPONIBLES y no se repartió ninguno', async () => {
    capturar('repartir_base', () => error('22023', 'Solo hay 62 contactos disponibles para repartir en esta base (pediste 70)', '62'))
    await expect(repartirBase({ operacionId: OP, baseId: BASE, reparto: { modo: 'bloque', asignaciones: [{ analista_id: ANA, cantidad: 70 }] } }))
      .rejects.toMatchObject({ code: 'SIN_DISPONIBLES', detalle: 62, message: expect.stringContaining('hay 62 contactos disponibles') })
    capturar('repartir_base', () => error('22023', 'No alcanzan', JSON.stringify({ disponibles: 1 })))
    await expect(repartirBase({ operacionId: OP, baseId: BASE, reparto: { modo: 'bloque', asignaciones: [{ analista_id: ANA, cantidad: 7 }] } }))
      .rejects.toMatchObject({ code: 'SIN_DISPONIBLES', detalle: 1 })
  })
  it('individual: un par lead/analista por contacto; un 22023 sin disponibles llega con su texto', async () => {
    const cuerpos = capturar('repartir_base', () => error('22023', 'Un contacto ya no está en la base'))
    const reparto = { modo: 'individual' as const, asignaciones: [{ lead_id: LEAD, analista_id: ANA }] }
    await expect(repartirBase({ operacionId: OP, baseId: BASE, reparto })).rejects.toMatchObject({ code: 'REGLA_SERVIDOR', message: 'Un contacto ya no está en la base' })
    expect(cuerpos[0]).toEqual({ p_operacion_id: OP, p_base_id: BASE, p_reparto: reparto })
  })
  it('antes de la B9 (PGRST202): repartir y recoger dicen «disponible pronto»', async () => {
    capturar('repartir_base', () => PGRST202('repartir_base'))
    capturar('recoger_de_base', () => PGRST202('recoger_de_base'))
    await expect(repartirBase({ operacionId: OP, baseId: BASE, reparto: { modo: 'bloque', asignaciones: [] } })).rejects.toMatchObject({ code: 'NO_DISPONIBLE', message: expect.stringContaining('disponible pronto') })
    await expect(recogerDeBase({ operacionId: OP, baseId: BASE, analistaId: ANA })).rejects.toMatchObject({ code: 'NO_DISPONIBLE' })
  })
  it('recoger: operación, base y analista; lee recogidos, omitidos y pendientes (tope de 500 por llamada)', async () => {
    const cuerpos = capturar('recoger_de_base', () => HttpResponse.json({ ok: true, operacion_id: OP, base_id: BASE, analista_id: ANA, recogidos: '500', omitidos: 3, pendientes: 20 }))
    expect(await recogerDeBase({ operacionId: OP, baseId: BASE, analistaId: ANA })).toMatchObject({ recogidos: 500, omitidos: 3, pendientes: 20 })
    expect(cuerpos).toEqual([{ p_operacion_id: OP, p_base_id: BASE, p_analista_id: ANA }])
    capturar('recoger_de_base', () => HttpResponse.json({ recogidos: 1, omitidos: 0 }))
    expect(await recogerDeBase({ operacionId: OP, baseId: BASE, analistaId: ANA })).toMatchObject({ pendientes: 0 })
  })
})

describe('reactivarLeadBase con capital (F6: la puerta versionada reactivar_lead_base_v2 de la B10)', () => {
  it('sin capital en el lead: va a la _v2 con el capital y la moneda', async () => {
    const cuerpos = capturar('reactivar_lead_base_v2', () => HttpResponse.json({ replay: false, etapa: 'contactado', ciclo_n: 2 }))
    await reactivarLeadBase({ operacionId: OP, leadId: LEAD, nota: 'retoma', montoEstimado: 20000, moneda: 'USD' })
    expect(cuerpos).toEqual([{ p_operacion_id: OP, p_lead_id: LEAD, p_nota: 'retoma', p_monto_estimado: 20000, p_moneda: 'USD' }])
  })
  it('el servidor de hoy no la tiene (PGRST202): «disponible pronto», no se reactiva', async () => {
    capturar('reactivar_lead_base_v2', () => PGRST202('reactivar_lead_base_v2'))
    await expect(reactivarLeadBase({ operacionId: OP, leadId: LEAD, montoEstimado: 20000 })).rejects.toMatchObject({ code: 'NO_DISPONIBLE', message: expect.stringContaining('disponible pronto') })
  })
  it('con capital ya puesto: la llamada de siempre (sin claves nuevas)', async () => {
    const cuerpos = capturar('reactivar_lead_base', () => HttpResponse.json({ replay: false, etapa: 'contactado', ciclo_n: 2 }))
    await reactivarLeadBase({ operacionId: OP, leadId: LEAD })
    expect(cuerpos).toEqual([{ p_operacion_id: OP, p_lead_id: LEAD }])
  })
  it('el servidor exige el capital (22023): su texto llega tal cual', async () => {
    capturar('reactivar_lead_base_v2', () => error('22023', 'Indica el capital estimado para reactivar'))
    await expect(reactivarLeadBase({ operacionId: OP, leadId: LEAD, montoEstimado: 1 })).rejects.toMatchObject({ message: 'Indica el capital estimado para reactivar' })
  })
})

describe('registrarIntentoBase con capital (F6: «agendó cita» de un lead sin capital → registrar_intento_base_v2)', () => {
  const RESPUESTA = { ok: true, replay: false, intento_n: 1, etapa: 'contactado', reactivado: true, enfriado_hasta: null, proxima_llamada_en: null }
  it('con capital: va a la _v2 con el resultado, el capital y la moneda', async () => {
    const cuerpos = capturar('registrar_intento_base_v2', () => HttpResponse.json(RESPUESTA))
    const r = await registrarIntentoBase({ operacionId: OP, leadId: LEAD, resultado: 'agendo_reunion', nota: ' cita el lunes ', montoEstimado: 15000, moneda: 'PEN' })
    expect(cuerpos).toEqual([{ p_operacion_id: OP, p_lead_id: LEAD, p_resultado: 'agendo_reunion', p_nota: 'cita el lunes', p_monto_estimado: 15000, p_moneda: 'PEN' }])
    expect(r.reactivado).toBe(true)
  })
  it('sin capital (el resto de intentos): la puerta de siempre, sin claves nuevas', async () => {
    const cuerpos = capturar('registrar_intento_base', () => HttpResponse.json({ ...RESPUESTA, reactivado: false, etapa: 'descartado' }))
    await registrarIntentoBase({ operacionId: OP, leadId: LEAD, resultado: 'no_contesto' })
    expect(cuerpos).toEqual([{ p_operacion_id: OP, p_lead_id: LEAD, p_resultado: 'no_contesto' }])
  })
  it('el servidor de hoy no la tiene (PGRST202): «disponible pronto», no se registra nada', async () => {
    capturar('registrar_intento_base_v2', () => PGRST202('registrar_intento_base_v2'))
    await expect(registrarIntentoBase({ operacionId: OP, leadId: LEAD, resultado: 'agendo_reunion', montoEstimado: 1 })).rejects.toMatchObject({ code: 'NO_DISPONIBLE', message: expect.stringContaining('disponible pronto') })
  })
})
