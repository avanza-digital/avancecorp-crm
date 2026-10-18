// @vitest-environment node
// «Reemplazar inversión» de COOPERATIVA (Fase 4) contra el cliente supabase-js real y una Data API simulada: rutas RPC
// y esquema crm, argumentos EXACTOS (p_cierre solo con las claves que cambian), acuse tolerante (lo que prueba el
// reemplazo es cierre_id) y los RAISE con su texto.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, reemplazarInversionCooperativa, vistaPreviaReemplazoCooperativa, type CambiosReemplazoCooperativa } from './crm-api'

const BASE = 'http://supabase.test/rest/v1/rpc'
const FUENTE = '33333333-3333-4333-8333-333333333333'
const OTRA = '55555555-5555-4555-8555-555555555555'
const NUEVO = '66666666-6666-4666-8666-666666666666'
const AUDITORIA = '77777777-7777-4777-8777-777777777777'
const RUTA = `22222222-2222-4222-8222-222222222222/reemplazo-${FUENTE}/88888888-8888-4888-8888-888888888888.pdf`
const PREVIA = { fuente_id: FUENTE, cooperativa: 'prodelco', es_inicial: true, anulada: false, venta_de_lead: true, comprobante: true,
  fecha_comercial_actual: '2026-10-05', mes_actual: '2026-10-01', fecha_comercial_resultante: '2026-09-28', mes_resultante: '2026-09-01',
  cambia_mes: true, fecha_futura: false, mes_sellado: false, plazo_vencido: false, no_reemplazable: null }
const ACUSE = { ok: true, modo: 'nueva', fuente_id: FUENTE, cierre_id: NUEVO, inversion_id: OTRA, auditoria_id: AUDITORIA,
  cooperativa: 'qorilazo', fecha_comercial: '2026-09-28', vence_en: '2027-09-23', comprobante_cambiado: false,
  conversion: { lead_id: OTRA, estado: 'acreditada', periodo_antes: '2026-10-01', periodo_despues: '2026-09-01' } }

const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => { vi.spyOn(console, 'error').mockImplementation(() => {}) })

async function fallo(p: Promise<unknown>): Promise<CrmApiError> {
  try { await p } catch (e) { if (e instanceof CrmApiError) return e; throw e }
  throw new Error('no falló')
}
const rechazo = (code: string, message: string, status = 400) => () => HttpResponse.json({ code, message, details: null, hint: null }, { status })

describe('vistaPreviaReemplazoCooperativa (crm.reemplazar_inversion_cooperativa_vista_previa_fn)', () => {
  it('manda solo p_fuente_id y p_fecha_comercial al esquema crm y devuelve la previa', async () => {
    let cuerpo: unknown = null
    let perfil: string | null = null
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_vista_previa_fn`, async ({ request }) => {
      cuerpo = await request.json(); perfil = request.headers.get('content-profile'); return HttpResponse.json(PREVIA)
    }))
    await expect(vistaPreviaReemplazoCooperativa(FUENTE, '2026-09-28')).resolves.toEqual(PREVIA)
    expect(cuerpo).toEqual({ p_fuente_id: FUENTE, p_fecha_comercial: '2026-09-28' })
    expect(perfil).toBe('crm')
  })

  it('sin fecha, el servidor usa la de la original: no se manda la clave', async () => {
    let cuerpo: unknown = null
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_vista_previa_fn`, async ({ request }) => {
      cuerpo = await request.json(); return HttpResponse.json({ ...PREVIA, fecha_comercial_resultante: '2026-10-05', mes_resultante: '2026-10-01', cambia_mes: false })
    }))
    await vistaPreviaReemplazoCooperativa(FUENTE)
    expect(cuerpo).toEqual({ p_fuente_id: FUENTE })
  })

  it('una original sin fecha comercial propia y una que no se puede reemplazar también son respuestas válidas', async () => {
    const r = { ...PREVIA, fecha_comercial_actual: null, no_reemplazable: 'La inversión tiene movimientos: no se elimina', anulada: false }
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_vista_previa_fn`, () => HttpResponse.json(r)))
    await expect(vistaPreviaReemplazoCooperativa(FUENTE, '2026-09-28')).resolves.toEqual(r)
  })

  it('valida antes de llamar: identificador y fecha', async () => {
    expect((await fallo(vistaPreviaReemplazoCooperativa('no-uuid', '2026-09-28'))).code).toBe('INVERSION_FUENTE_INVALIDA')
    expect((await fallo(vistaPreviaReemplazoCooperativa(FUENTE, '28/09/2026'))).code).toBe('INVERSION_FECHA_INVALIDA')
  })

  it('una respuesta con otra forma o de otra inversión no se muestra como mes', async () => {
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_vista_previa_fn`, () => HttpResponse.json({ ...PREVIA, extra: 1 })))
    expect((await fallo(vistaPreviaReemplazoCooperativa(FUENTE, '2026-09-28'))).code).toBe('VISTA_PREVIA_CONTRACT')
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_vista_previa_fn`, () => HttpResponse.json({ ...PREVIA, fuente_id: OTRA })))
    expect((await fallo(vistaPreviaReemplazoCooperativa(FUENTE, '2026-09-28'))).code).toBe('VISTA_PREVIA_CONTRACT')
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_vista_previa_fn`, () => HttpResponse.json({ ...PREVIA, cooperativa: 'avance' })))
    expect((await fallo(vistaPreviaReemplazoCooperativa(FUENTE, '2026-09-28'))).code).toBe('VISTA_PREVIA_CONTRACT')
  })

  it('los rechazos llegan tal cual y el corte de red no habla de un reemplazo que pudo hacerse', async () => {
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_vista_previa_fn`, rechazo('P0002', 'La inversión no existe o ya fue eliminada')))
    const e = await fallo(vistaPreviaReemplazoCooperativa(FUENTE, '2026-09-28'))
    expect([e.code, e.message]).toEqual(['NO_ENCONTRADA', 'La inversión no existe o ya fue eliminada'])
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_vista_previa_fn`, () => HttpResponse.error()))
    const red = await fallo(vistaPreviaReemplazoCooperativa(FUENTE, '2026-09-28'))
    expect(red.code).toBe('RESPUESTA_NO_RECIBIDA')
    expect(red.message).not.toMatch(/pudo hacerse/)
  })
})

describe('reemplazarInversionCooperativa (crm.reemplazar_inversion_cooperativa_fn)', () => {
  function capturar(respuesta: Record<string, unknown> = ACUSE) {
    const visto = { cuerpo: null as Record<string, unknown> | null }
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_fn`, async ({ request }) => {
      visto.cuerpo = await request.json() as Record<string, unknown>
      return HttpResponse.json(respuesta)
    }))
    return visto
  }

  it.each<[string, CambiosReemplazoCooperativa, Record<string, string>]>([
    ['solo la cooperativa', { cooperativa: 'qorilazo' }, { cooperativa: 'qorilazo' }],
    ['solo la fecha comercial', { fechaComercial: '2026-09-28' }, { fecha_comercial: '2026-09-28' }],
    ['solo el comprobante', { comprobanteRuta: RUTA }, { comprobante_ruta: RUTA }],
    ['las tres', { cooperativa: 'qorilazo', fechaComercial: '2026-09-28', comprobanteRuta: RUTA },
      { cooperativa: 'qorilazo', fecha_comercial: '2026-09-28', comprobante_ruta: RUTA }],
    ['lo indefinido no viaja', { cooperativa: undefined, fechaComercial: '2026-09-28', comprobanteRuta: undefined }, { fecha_comercial: '2026-09-28' }],
  ])('%s: p_cierre lleva SOLO las claves que cambian', async (_n, cambios, esperado) => {
    const visto = capturar()
    await reemplazarInversionCooperativa(FUENTE, '  Se cargó en la cooperativa equivocada  ', cambios)
    expect(visto.cuerpo).toEqual({ p_fuente_id: FUENTE, p_motivo: 'Se cargó en la cooperativa equivocada', p_cierre: esperado })
  })

  it('devuelve el acuse: el cierre que queda, la cooperativa, la fecha y el mes de la venta', async () => {
    capturar()
    expect(await reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'qorilazo' })).toEqual({
      cierreId: NUEVO, cooperativa: 'qorilazo', fechaComercial: '2026-09-28', idempotente: false, periodoVenta: '2026-09-01' })
  })

  it('sin venta del lead (conversion null) no hay mes que decir', async () => {
    capturar({ ...ACUSE, conversion: null })
    expect((await reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'qorilazo' })).periodoVenta).toBeNull()
  })

  it('el reintento ya hecho vuelve como idempotente (sin modo ni conversión)', async () => {
    capturar({ ok: true, idempotente: true, fuente_id: FUENTE, cierre_id: NUEVO, auditoria_id: AUDITORIA, cooperativa: 'qorilazo', fecha_comercial: '2026-10-05' })
    expect(await reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'qorilazo' })).toEqual({
      cierreId: NUEVO, cooperativa: 'qorilazo', fechaComercial: '2026-10-05', idempotente: true, periodoVenta: null })
  })

  it('valida antes de llamar: identificador, motivo, cooperativa, fecha, ruta y que algo cambie', async () => {
    expect((await fallo(reemplazarInversionCooperativa('x', 'Cooperativa equivocada', { cooperativa: 'qorilazo' }))).code).toBe('INVERSION_FUENTE_INVALIDA')
    expect((await fallo(reemplazarInversionCooperativa(FUENTE, 'abc', { cooperativa: 'qorilazo' }))).code).toBe('INVERSION_MOTIVO_INVALIDO')
    expect((await fallo(reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'avance' as 'qorilazo' }))).code).toBe('INVERSION_COOPERATIVA_INVALIDA')
    expect((await fallo(reemplazarInversionCooperativa(FUENTE, 'Fecha equivocada', { fechaComercial: '28/09/2026' }))).code).toBe('INVERSION_FECHA_INVALIDA')
    expect((await fallo(reemplazarInversionCooperativa(FUENTE, 'Comprobante equivocado', { comprobanteRuta: '  ' }))).code).toBe('INVERSION_COMPROBANTE_INVALIDO')
    expect((await fallo(reemplazarInversionCooperativa(FUENTE, 'Nada que cambiar', {}))).code).toBe('INVERSION_SIN_CAMBIOS')
  })

  it.each([
    ['P0409', 'El mes de esta venta ya está cerrado: no se reemplaza', 'CONFLICTO'],
    ['P0409', 'Venció el plazo de carga de 09/2026: el reemplazo dejaría la venta fuera de plazo. No se hizo ningún cambio', 'CONFLICTO'],
    ['P0409', 'Ese número de operación del depósito ya está registrado en otra inversión; no se hizo ningún cambio', 'CONFLICTO'],
    ['P0409', 'Solo se reemplaza la inversión inicial de la cooperativa (la venta del lead); un aporte adicional se corrige con «Corregir» o se elimina', 'CONFLICTO'],
    ['22023', 'Nada que reemplazar: la cooperativa, la fecha comercial y el comprobante son los mismos. Para el monto, el plazo o la tasa usa «Corregir»', 'REGLA_SERVIDOR'],
    ['22023', 'La fecha comercial no puede ser futura', 'REGLA_SERVIDOR'],
    ['0A000', 'Esta puerta reemplaza inversiones de cooperativa; una inversión de Avance se reemplaza con la puerta de Avance', 'REGLA_SERVIDOR'],
    ['P0002', 'La inversión no existe o ya fue eliminada', 'NO_ENCONTRADA'],
    ['42501', 'Solo gerencia puede reemplazar una inversión de cooperativa: es la venta de un lead', 'SIN_PERMISO'],
    ['PT409', 'Otra operación está usando el mes 09/2026; vuelve a intentar en unos segundos', 'REINTENTAR'],
  ])('%s se muestra tal cual («%s»)', async (pg, mensaje, code) => {
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_fn`, rechazo(pg, mensaje)))
    const e = await fallo(reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'qorilazo' }))
    expect(e.code).toBe(code)
    expect(e.message).toBe(mensaje)
  })

  it('lo que redacta Postgres en inglés y el corte de red se traducen; el corte avisa que pudo hacerse', async () => {
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_fn`, rechazo('42501', 'permission denied for function reemplazar_inversion_cooperativa_fn')))
    expect((await fallo(reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'qorilazo' }))).message)
      .toBe('No tienes permiso para reemplazar esta inversión.')
    server.use(http.post(`${BASE}/reemplazar_inversion_cooperativa_fn`, () => HttpResponse.error()))
    const e = await fallo(reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'qorilazo' }))
    expect(e.code).toBe('RESPUESTA_NO_RECIBIDA')
    expect(e.message).toMatch(/pudo hacerse/)
  })

  it('un 2xx sin cierre_id (o de otra inversión) no se da por bueno ni por error: «pudo hacerse»', async () => {
    capturar({ ok: true, fuente_id: FUENTE, modo: 'nueva' })
    const e = await fallo(reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'qorilazo' }))
    expect([e.code, e.message]).toEqual(['INVERSION_REEMPLAZADA_CONTRACT', expect.stringMatching(/pudo hacerse/)])
    capturar({ ...ACUSE, fuente_id: OTRA })
    expect((await fallo(reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'qorilazo' }))).code).toBe('INVERSION_REEMPLAZADA_CONTRACT')
  })

  it('un accesorio con otra forma se deja en blanco y se REGISTRA; el reemplazo no se vuelve error', async () => {
    const consola = vi.spyOn(console, 'error').mockImplementation(() => {})
    const registrados = () => consola.mock.calls.map(c => (c[1] as { evento?: string } | undefined))
      .filter(e => e?.evento === 'crm.inversiones.reemplazo_cooperativa_fuera_de_contrato.accesorio').length
    capturar({ ...ACUSE, cooperativa: 'avance', fecha_comercial: 'raro', conversion: { periodo_despues: 7 } })
    expect(await reemplazarInversionCooperativa(FUENTE, 'Cooperativa equivocada', { cooperativa: 'qorilazo' })).toEqual({
      cierreId: NUEVO, cooperativa: null, fechaComercial: null, idempotente: false, periodoVenta: null })
    expect(registrados()).toBe(3)                                // cooperativa, fecha_comercial y conversion.periodo_despues
    consola.mockRestore()
  })
})
