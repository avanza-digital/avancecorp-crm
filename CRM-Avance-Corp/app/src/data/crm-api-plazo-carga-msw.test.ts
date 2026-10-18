// @vitest-environment node
// Plazo de carga por mes contra el cliente supabase-js real y una Data API
// simulada: rutas RPC y esquema crm, argumentos EXACTOS, contratos estrictos y
// los RAISE de la puerta con su texto (son mensajes de negocio).
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, fijarPlazoCargaMes, obtenerPlazosCargaMes } from './crm-api'

const RUTA_LEER = 'http://supabase.test/rest/v1/rpc/plazos_carga_mes_fn'
const RUTA_FIJAR = 'http://supabase.test/rest/v1/rpc/fijar_plazo_carga_mes'
const REAPERTURA = '55555555-5555-4555-8555-555555555555'

const PLAZOS = {
  version: 1,
  generado_en: '2026-10-14T15:00:00.123456+00:00',
  hoy: '2026-10-14',
  zona: 'America/Lima',
  meses: [
    {
      mes: '2026-09', mes_nombre: 'setiembre 2026', sellado: false,
      plazo_base_ultimo_dia: '2026-10-10', plazo_ultimo_dia: '2026-10-10', ampliado: false,
      decision: null, reabrible: false, motivo_no_reabrible: null, ultima_reapertura: null,
    },
    {
      mes: '2026-10', mes_nombre: 'octubre 2026', sellado: false,
      plazo_base_ultimo_dia: '2026-11-10', plazo_ultimo_dia: '2026-11-10', ampliado: false,
      decision: null, reabrible: false, motivo_no_reabrible: null, ultima_reapertura: null,
    },
  ],
}
const ACUSE = {
  ok: true, mes: '2026-09', ultimo_dia: '2026-10-20', plazo_hasta: '2026-10-21T05:00:00+00:00',
  reabierto: false, reapertura_id: null, acreditaciones_reevaluadas: 12, conflictos_identidad: 0, ventas_devueltas: [],
}
const DATOS = { mes: '2026-09', ultimoDia: '2026-10-20', motivo: '  Los analistas aún cargan ventas  ' }

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

async function fallo(p: Promise<unknown>): Promise<CrmApiError> {
  try {
    await p
  } catch (e) {
    if (e instanceof CrmApiError) return e
    throw e
  }
  throw new Error('no falló')
}

describe('obtenerPlazosCargaMes (crm.plazos_carga_mes_fn)', () => {
  it('pide la función del esquema crm sin argumentos y devuelve el plazo de cada mes', async () => {
    let cuerpo: unknown = 'sin cuerpo'
    let perfil: string | null = null
    server.use(http.post(RUTA_LEER, async ({ request }) => {
      cuerpo = await request.json()
      perfil = request.headers.get('content-profile')
      return HttpResponse.json(PLAZOS)
    }))

    const plazos = await obtenerPlazosCargaMes()

    expect(cuerpo).toEqual({})
    expect(perfil).toBe('crm')
    expect(plazos.meses.map((m) => [m.mes, m.plazo_ultimo_dia])).toEqual([['2026-09', '2026-10-10'], ['2026-10', '2026-11-10']])
  })

  it('una clave de más es otra respuesta: ROW_CONTRACT, no un plazo a medias', async () => {
    server.use(http.post(RUTA_LEER, () => HttpResponse.json({ ...PLAZOS, pendiente: null })))
    const e = await fallo(obtenerPlazosCargaMes())
    expect(e.code).toBe('ROW_CONTRACT')
  })

  it.each([
    ['PGRST202', 404, 'NO_DISPONIBLE'],
    ['42501', 403, 'SIN_PERMISO'],
    ['XX000', 500, 'XX000'],
  ])('el error %s llega como %s', async (pg, status, codigo) => {
    server.use(http.post(RUTA_LEER, () => HttpResponse.json({ code: pg, message: 'x', details: null, hint: null }, { status })))
    const e = await fallo(obtenerPlazosCargaMes())
    expect(e.code).toBe(codigo)
  })
})

describe('fijarPlazoCargaMes (crm.fijar_plazo_carga_mes)', () => {
  it('manda exactamente p_periodo (primer día), p_ultimo_dia y p_motivo recortado al esquema crm', async () => {
    let cuerpo: unknown = null
    let perfil: string | null = null
    server.use(http.post(RUTA_FIJAR, async ({ request }) => {
      cuerpo = await request.json()
      perfil = request.headers.get('content-profile')
      return HttpResponse.json(ACUSE)
    }))

    const acuse = await fijarPlazoCargaMes(DATOS)

    expect(cuerpo).toEqual({ p_periodo: '2026-09-01', p_ultimo_dia: '2026-10-20', p_motivo: 'Los analistas aún cargan ventas' })
    expect(perfil).toBe('crm')
    expect(acuse).toMatchObject({ mes: '2026-09', ultimo_dia: '2026-10-20', reabierto: false, acreditaciones_reevaluadas: 12 })
  })

  it('una reapertura llega con su fila y las ventas devueltas (monto numérico como texto)', async () => {
    server.use(http.post(RUTA_FIJAR, () => HttpResponse.json({
      ...ACUSE, reabierto: true, reapertura_id: REAPERTURA,
      ventas_devueltas: [{ cooperativa: 'qorilazo', monto: '20000.00', moneda: 'PEN', fecha_comercial: '2026-09-15', imputada_antes_a: '2026-10-13' }],
    })))
    const acuse = await fijarPlazoCargaMes(DATOS)
    expect(acuse.reapertura_id).toBe(REAPERTURA)
    expect(acuse.ventas_devueltas).toEqual([
      { cooperativa: 'qorilazo', monto: 20000, moneda: 'PEN', fecha_comercial: '2026-09-15', imputada_antes_a: '2026-10-13' },
    ])
  })

  it.each([
    ['una clave de más', { ...ACUSE, detalle: 'extra' }],
    ['otro mes', { ...ACUSE, mes: '2026-08' }],
    ['otro último día', { ...ACUSE, ultimo_dia: '2026-10-21' }],
    ['reabierto sin fila de reapertura', { ...ACUSE, reabierto: true }],
    ['un cuerpo vacío', null],
  ])('un acuse con %s no se presenta como guardado, pero avisa que pudo guardarse', async (_caso, cuerpo) => {
    server.use(http.post(RUTA_FIJAR, () => HttpResponse.json(cuerpo)))
    const e = await fallo(fijarPlazoCargaMes(DATOS))
    expect(e.code).toBe('PLAZO_CARGA_CONTRACT')
    expect(e.message).toMatch(/pudo guardarse/)
  })

  it.each([
    ['42501', 'Solo Gerencia decide el plazo de carga de un mes', 'SIN_PERMISO', 'Solo Gerencia decide el plazo de carga de un mes'],
    ['42501', 'permission denied for function fijar_plazo_carga_mes', 'SIN_PERMISO', 'Solo Gerencia decide el plazo de carga.'],
    ['22023', 'El plazo de setiembre 2026 no puede terminar antes del 10/10/2026, su plazo de siempre', 'REGLA_SERVIDOR',
      'El plazo de setiembre 2026 no puede terminar antes del 10/10/2026, su plazo de siempre'],
    ['22023', 'El último día de carga no puede ser anterior a hoy (14/10/2026)', 'REGLA_SERVIDOR',
      'El último día de carga no puede ser anterior a hoy (14/10/2026)'],
    ['P0409', 'Solo se reabre el mes anterior al mes en curso (setiembre 2026)', 'CONFLICTO',
      'Solo se reabre el mes anterior al mes en curso (setiembre 2026)'],
    // Postflight de private.reabrir_mes (raise sin código = P0001): habla del mecanismo; la transacción se deshizo entera.
    ['P0001', 'REAPERTURA: el mes sigue sellado', 'REAPERTURA_INCOMPLETA',
      'No se reabrió el mes: una comprobación interna no cuadró y no se cambió nada. Avisa a soporte.'],
    ['P0001', 'El motivo debe tener entre 5 y 300 caracteres', 'REGLA_SERVIDOR', 'El motivo debe tener entre 5 y 300 caracteres'],
    ['55P03', 'canceling statement due to lock timeout', 'REINTENTAR',
      'Otra operación está usando el cierre de este mes. Vuelve a intentarlo en unos segundos.'],
    ['PGRST202', 'Could not find the function', 'NO_DISPONIBLE', 'Ampliar el plazo de carga llega con la próxima actualización del servidor.'],
    ['XX000', 'internal error', 'POSTGREST_ERROR', 'No se pudo guardar el plazo de carga.'],
  ])('el rechazo %s («%s») llega como %s', async (pg, textoServidor, codigo, mensaje) => {
    server.use(http.post(RUTA_FIJAR, () => HttpResponse.json(
      { code: pg, message: textoServidor, details: null, hint: null }, { status: pg === '42501' ? 403 : 400 })))
    const e = await fallo(fijarPlazoCargaMes(DATOS))
    expect(e.code).toBe(codigo)
    expect(e.message).toBe(mensaje)
  })

  it('sin respuesta del servidor no afirma que el plazo no se guardó', async () => {
    server.use(http.post(RUTA_FIJAR, () => HttpResponse.error()))
    const e = await fallo(fijarPlazoCargaMes(DATOS))
    expect(e.code).toBe('RESPUESTA_NO_RECIBIDA')
    expect(e.message).toMatch(/pudo guardarse/)
  })

  it.each([
    ['un mes que no es YYYY-MM', { ...DATOS, mes: '2026-9' }, 'PLAZO_CARGA_MES_INVALIDO'],
    ['una fecha que no es YYYY-MM-DD', { ...DATOS, ultimoDia: '20/10/2026' }, 'PLAZO_CARGA_FECHA_INVALIDA'],
    ['un motivo de 4 caracteres', { ...DATOS, motivo: '  abcd  ' }, 'PLAZO_CARGA_MOTIVO_INVALIDO'],
    ['un motivo de 301 caracteres', { ...DATOS, motivo: 'x'.repeat(301) }, 'PLAZO_CARGA_MOTIVO_INVALIDO'],
  ])('%s no viaja al servidor', async (_caso, datos, codigo) => {
    // Sin handler: con onUnhandledRequest 'error', cualquier petición haría fallar la prueba.
    const e = await fallo(fijarPlazoCargaMes(datos))
    expect(e.code).toBe(codigo)
  })
})
