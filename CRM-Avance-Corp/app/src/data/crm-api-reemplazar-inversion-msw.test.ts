// @vitest-environment node
// «Reemplazar inversión» contra el cliente supabase-js real y una Data API simulada: rutas RPC y esquema crm,
// argumentos EXACTOS, acuse tolerante (lo que prueba el reemplazo es contrato_id) y los RAISE con su texto.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, reemplazarInversion, reemplazarInversionPorExistente, vistaPreviaReemplazo, type CrearContratoInput } from './crm-api'
import type { CuotaCronograma } from '@/lib/cronograma'

const BASE = 'http://supabase.test/rest/v1/rpc'
const FUENTE = '33333333-3333-4333-8333-333333333333'
const OTRA = '55555555-5555-4555-8555-555555555555'
const NUEVO = '66666666-6666-4666-8666-666666666666'
const CLIENTE = '44444444-4444-4444-8444-444444444444'
const PREVIA = { fuente_id: FUENTE, fecha_inicio: '2026-09-28', fecha_comercial_actual: '2026-10-05', mes_actual: '2026-10-01',
  fecha_comercial_resultante: '2026-09-28', mes_resultante: '2026-09-01', cambia_mes: true, fecha_corregida: false, cuotas_pagadas: false }
const INPUT: CrearContratoInput = {
  cliente_id: CLIENTE, capital: 50000, moneda: 'PEN', tasa_anual: 15, modalidad: 'mensual', tipo_interes: 'simple',
  categoria: 'nuevo', fecha_inicio: '2026-09-28', fecha_vencimiento: '2027-09-28', numero_contrato: '2026-01-999999',
  cuenta_pago: { tipo: 'existente', cuenta_id: OTRA }, analista_cierre_id: '11111111-1111-4111-8111-111111111111',
  clave_idempotencia: '99999999-9999-4999-8999-999999999999', titulares: [],
}
const CUOTAS: CuotaCronograma[] = [{ numero_cuota: 1, fecha_programada: '2026-10-28', monto_programado: 625, estado: 'pendiente', tipo: 'cuota' }]

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

describe('vistaPreviaReemplazo (crm.reemplazar_inversion_vista_previa_fn)', () => {
  it('con la fecha de inicio: manda solo p_fuente_id y p_fecha_inicio al esquema crm y devuelve el mes', async () => {
    let cuerpo: unknown = null
    let perfil: string | null = null
    server.use(http.post(`${BASE}/reemplazar_inversion_vista_previa_fn`, async ({ request }) => {
      cuerpo = await request.json(); perfil = request.headers.get('content-profile'); return HttpResponse.json(PREVIA)
    }))
    await expect(vistaPreviaReemplazo(FUENTE, { fechaInicio: '2026-09-28' })).resolves.toEqual(PREVIA)
    expect(cuerpo).toEqual({ p_fuente_id: FUENTE, p_fecha_inicio: '2026-09-28' })
    expect(perfil).toBe('crm')
  })

  it('con la que se conserva: manda p_conservar_id y no la fecha', async () => {
    let cuerpo: unknown = null
    server.use(http.post(`${BASE}/reemplazar_inversion_vista_previa_fn`, async ({ request }) => {
      cuerpo = await request.json(); return HttpResponse.json({ ...PREVIA, cambia_mes: false })
    }))
    await vistaPreviaReemplazo(FUENTE, { conservarId: OTRA })
    expect(cuerpo).toEqual({ p_fuente_id: FUENTE, p_conservar_id: OTRA })
  })

  it('valida antes de llamar: identificadores y fecha', async () => {
    expect((await fallo(vistaPreviaReemplazo('no-uuid', { fechaInicio: '2026-09-28' }))).code).toBe('INVERSION_FUENTE_INVALIDA')
    expect((await fallo(vistaPreviaReemplazo(FUENTE, { fechaInicio: '28/09/2026' }))).code).toBe('INVERSION_FECHA_INVALIDA')
    expect((await fallo(vistaPreviaReemplazo(FUENTE, { conservarId: 'x' }))).code).toBe('INVERSION_FUENTE_INVALIDA')
  })

  it('una respuesta con otra forma o de otra inversión no se muestra como mes', async () => {
    server.use(http.post(`${BASE}/reemplazar_inversion_vista_previa_fn`, () => HttpResponse.json({ ...PREVIA, extra: 1 })))
    expect((await fallo(vistaPreviaReemplazo(FUENTE, { fechaInicio: '2026-09-28' }))).code).toBe('VISTA_PREVIA_CONTRACT')
    server.use(http.post(`${BASE}/reemplazar_inversion_vista_previa_fn`, () => HttpResponse.json({ ...PREVIA, fuente_id: OTRA })))
    expect((await fallo(vistaPreviaReemplazo(FUENTE, { fechaInicio: '2026-09-28' }))).code).toBe('VISTA_PREVIA_CONTRACT')
  })

  it('el corte de red en la previa no habla de un reemplazo que pudo hacerse', async () => {
    server.use(http.post(`${BASE}/reemplazar_inversion_vista_previa_fn`, () => HttpResponse.error()))
    const e = await fallo(vistaPreviaReemplazo(FUENTE, { fechaInicio: '2026-09-28' }))
    expect(e.code).toBe('RESPUESTA_NO_RECIBIDA')
    expect(e.message).not.toMatch(/pudo hacerse/)
  })
})

describe('reemplazarInversion (crm.reemplazar_inversion_fn)', () => {
  it('manda el contenido del alta SIN analista ni clave del alta, con el motivo recortado; devuelve el acuse', async () => {
    let cuerpo: Record<string, unknown> | null = null
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, async ({ request }) => {
      cuerpo = await request.json() as Record<string, unknown>
      return HttpResponse.json({ ok: true, modo: 'nueva', fuente_id: FUENTE, contrato_id: NUEVO, numero_contrato: '2026-01-999999',
        auditoria_id: OTRA, id: NUEVO, pdf: { estado: 'pendiente' }, conversion: { lead_id: OTRA, estado: 'acreditada', periodo_despues: '2026-09-01' } })
    }))
    const r = await reemplazarInversion(FUENTE, '  El capital se registró mal  ', INPUT, CUOTAS)
    expect(r).toEqual({ contratoId: NUEVO, numeroContrato: '2026-01-999999', modo: 'nueva', idempotente: false, periodoVenta: '2026-09-01' })
    const c = cuerpo as unknown as { p_fuente_id: string; p_motivo: string; p_contrato: Record<string, unknown>; p_cronograma: unknown; p_cuenta: unknown }
    expect(c.p_fuente_id).toBe(FUENTE)
    expect(c.p_motivo).toBe('El capital se registró mal')
    expect(c.p_contrato).toMatchObject({ cliente_id: CLIENTE, capital: 50000, categoria: 'nuevo', numero_contrato: '2026-01-999999' })
    expect(c.p_contrato).not.toHaveProperty('analista_cierre_id')
    expect(c.p_contrato).not.toHaveProperty('clave_idempotencia')
    expect(c.p_cronograma).toEqual(CUOTAS)
    expect(c.p_cuenta).toEqual({ tipo: 'existente', cuenta_id: OTRA })
  })

  it('el motivo se valida antes de llamar (5 a 300)', async () => {
    expect((await fallo(reemplazarInversion(FUENTE, 'abc', INPUT, CUOTAS))).code).toBe('INVERSION_MOTIVO_INVALIDO')
  })

  it('el reintento ya hecho vuelve como idempotente', async () => {
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, () => HttpResponse.json({ ok: true, idempotente: true, fuente_id: FUENTE,
      contrato_id: NUEVO, auditoria_id: OTRA, modo: 'nueva', numero_contrato: '2026-01-999999' })))
    expect((await reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS)).idempotente).toBe(true)
  })

  it.each([
    ['P0409', 'El mes de esta venta ya está cerrado: no se reemplaza', 'CONFLICTO'],
    ['P0409', 'Este contrato ya tiene cuotas pagadas: el reemplazo perdería esos pagos. No se hizo ningún cambio', 'CONFLICTO'],
    ['P0410', 'La tasa de este contrato la fija la política: 15%.', 'CONFLICTO'],
    ['22023', 'El analista de la venta no cambia en un reemplazo', 'REGLA_SERVIDOR'],
    ['P0002', 'La inversión no existe o ya fue eliminada', 'NO_ENCONTRADA'],
    ['42501', 'Esta inversión es la venta de un lead: solo gerencia puede reemplazarla', 'SIN_PERMISO'],
    ['PT409', 'Hay un cierre de mes u otra operación sobre esta venta en curso; vuelve a intentar en unos segundos. No se hizo ningún cambio', 'REINTENTAR'],
  ])('%s se muestra tal cual («%s»)', async (pg, mensaje, code) => {
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, rechazo(pg, mensaje)))
    const e = await fallo(reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS))
    expect(e.code).toBe(code)
    expect(e.message).toBe(mensaje)
  })

  it('lo que redacta Postgres en inglés y el corte de red se traducen; el corte avisa que pudo hacerse', async () => {
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, rechazo('42501', 'permission denied for function reemplazar_inversion_fn')))
    expect((await fallo(reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS))).message).toBe('No tienes permiso para reemplazar esta inversión.')
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, rechazo('55P03', 'could not obtain lock on row')))
    expect((await fallo(reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS))).code).toBe('REINTENTAR')
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, () => HttpResponse.error()))
    const e = await fallo(reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS))
    expect(e.code).toBe('RESPUESTA_NO_RECIBIDA')
    expect(e.message).toMatch(/pudo hacerse/)
  })

  it('un 2xx sin contrato_id (o de otra inversión) no se da por bueno ni por error: «pudo hacerse»', async () => {
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, () => HttpResponse.json({ ok: true, fuente_id: FUENTE, modo: 'nueva' })))
    expect((await fallo(reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS))).code).toBe('INVERSION_REEMPLAZADA_CONTRACT')
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, () => HttpResponse.json({ ok: true, fuente_id: OTRA, contrato_id: NUEVO, modo: 'nueva' })))
    expect((await fallo(reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS))).code).toBe('INVERSION_REEMPLAZADA_CONTRACT')
  })

  it('lo accesorio con otra forma no convierte el reemplazo en error', async () => {
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, () => HttpResponse.json({ ok: true, fuente_id: FUENTE, contrato_id: NUEVO,
      modo: 'nueva', pdf: 'raro', conversion: { periodo_despues: null, otra: true } })))
    expect(await reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS)).toMatchObject({ contratoId: NUEVO, numeroContrato: null, periodoVenta: null })
  })

  it('un accesorio CONOCIDO con otra forma tampoco: se deja en blanco, se REGISTRA y lo demás se conserva (Codex, Fase 2)', async () => {
    const consola = vi.spyOn(console, 'error').mockImplementation(() => {})
    const registrados = () => consola.mock.calls.map(c => (c[1] as { evento?: string; datos?: { error?: { message?: string } } }))
      .filter(e => e?.evento === 'crm.inversiones.reemplazo_fuera_de_contrato.accesorio').length
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, () => HttpResponse.json({ ok: true, fuente_id: FUENTE, contrato_id: NUEVO,
      modo: 'nueva', numero_contrato: '2026-01-999999', idempotente: 'sí', conversion: { periodo_despues: 'raro' } })))
    expect(await reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS)).toEqual({ contratoId: NUEVO,
      numeroContrato: '2026-01-999999', modo: 'nueva', idempotente: false, periodoVenta: null })
    expect(registrados()).toBe(2)                              // idempotente y conversion.periodo_despues
    server.use(http.post(`${BASE}/reemplazar_inversion_fn`, () => HttpResponse.json({ ok: true, fuente_id: FUENTE, contrato_id: NUEVO,
      modo: 'nueva', numero_contrato: 999999, conversion: 'raro' })))
    const antes = registrados()
    expect(await reemplazarInversion(FUENTE, 'Error de carga', INPUT, CUOTAS)).toMatchObject({ contratoId: NUEVO, numeroContrato: null, periodoVenta: null })
    expect(registrados() - antes).toBe(2)                     // numero_contrato y el bloque conversion entero
    consola.mockRestore()
  })
})

describe('reemplazarInversionPorExistente (crm.reemplazar_inversion_por_existente_fn)', () => {
  it('manda exactamente p_fuente_id, p_conservar_id y p_motivo', async () => {
    let cuerpo: unknown = null
    server.use(http.post(`${BASE}/reemplazar_inversion_por_existente_fn`, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json({ ok: true, modo: 'existente', fuente_id: FUENTE, contrato_id: OTRA, numero_contrato: '2026-01-999998', conversion: null })
    }))
    expect(await reemplazarInversionPorExistente(FUENTE, OTRA, ' Cargada dos veces ')).toEqual(
      { contratoId: OTRA, numeroContrato: '2026-01-999998', modo: 'existente', idempotente: false, periodoVenta: null })
    expect(cuerpo).toEqual({ p_fuente_id: FUENTE, p_conservar_id: OTRA, p_motivo: 'Cargada dos veces' })
  })

  it('valida los dos identificadores y el motivo antes de llamar', async () => {
    expect((await fallo(reemplazarInversionPorExistente(FUENTE, 'x', 'Cargada dos veces'))).code).toBe('INVERSION_FUENTE_INVALIDA')
    expect((await fallo(reemplazarInversionPorExistente(FUENTE, OTRA, 'no'))).code).toBe('INVERSION_MOTIVO_INVALIDO')
  })

  it('«no es una carga doble» llega tal cual', async () => {
    const m = 'La inversión que se conserva no es igual a la original (capital, moneda, tasa, fechas o modalidad): no es una carga doble. Usa el reemplazo con los datos correctos'
    server.use(http.post(`${BASE}/reemplazar_inversion_por_existente_fn`, rechazo('P0409', m)))
    expect((await fallo(reemplazarInversionPorExistente(FUENTE, OTRA, 'Cargada dos veces'))).message).toBe(m)
  })
})
