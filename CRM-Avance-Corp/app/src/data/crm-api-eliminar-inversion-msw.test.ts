// @vitest-environment node
// «Eliminar inversión» contra el cliente supabase-js real y una Data API simulada:
// ruta RPC y esquema crm, argumentos EXACTOS, acuse estricto (una clave de más o
// un tipo distinto es otra respuesta) y los RAISE de la puerta con su texto.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, eliminarInversion } from './crm-api'

const RUTA = 'http://supabase.test/rest/v1/rpc/eliminar_inversion_fn'
const FUENTE = '33333333-3333-4333-8333-333333333333'
const AUDITORIA = '55555555-5555-4555-8555-555555555555'
const ACUSE = {
  ok: true, fuente_id: FUENTE, empresa: 'qorilazo', auditoria_id: AUDITORIA,
  conversion_anulada: false, mes_cerrado: false,
}

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

describe('eliminarInversion (crm.eliminar_inversion_fn)', () => {
  it('manda exactamente p_fuente_id y p_motivo (recortado) al esquema crm y devuelve el acuse', async () => {
    let cuerpo: unknown = null
    let perfil: string | null = null
    server.use(http.post(RUTA, async ({ request }) => {
      cuerpo = await request.json()
      perfil = request.headers.get('content-profile')
      return HttpResponse.json(ACUSE)
    }))

    const resultado = await eliminarInversion(FUENTE, '  Se registró dos veces  ')

    expect(cuerpo).toEqual({ p_fuente_id: FUENTE, p_motivo: 'Se registró dos veces' })
    expect(perfil).toBe('crm')
    expect(resultado).toEqual({ auditoriaId: AUDITORIA, empresa: 'qorilazo', conversionAnulada: false, mesCerrado: false })
  })

  it('la conversión anulada en un mes cerrado llega a la pantalla', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json({ ...ACUSE, empresa: 'avance', conversion_anulada: true, mes_cerrado: true })))
    await expect(eliminarInversion(FUENTE, 'Registro duplicado')).resolves.toEqual({
      auditoriaId: AUDITORIA, empresa: 'avance', conversionAnulada: true, mesCerrado: true,
    })
  })

  it.each([
    ['una clave de más', { ...ACUSE, detalle: 'extra' }],
    ['un booleano como texto', { ...ACUSE, conversion_anulada: 'false' }],
    ['una auditoría que no es uuid', { ...ACUSE, auditoria_id: 'copia-1' }],
    ['una empresa desconocida', { ...ACUSE, empresa: 'otra' }],
    ['ok distinto de true', { ...ACUSE, ok: false }],
    ['una clave que falta', { ok: true, fuente_id: FUENTE, empresa: 'qorilazo', auditoria_id: AUDITORIA, conversion_anulada: false }],
    ['otra fuente', { ...ACUSE, fuente_id: AUDITORIA }],
    ['un cuerpo vacío', null],
  ])('rechaza un acuse con %s y no lo presenta como eliminado', async (_, cuerpo) => {
    server.use(http.post(RUTA, () => HttpResponse.json(cuerpo)))
    const e = await fallo(eliminarInversion(FUENTE, 'Registro duplicado'))
    expect(e.code).toBe('INVERSION_ELIMINADA_CONTRACT')
    expect(e.message).toMatch(/pudo completarse/)
  })

  it.each([
    ['42501', 'Solo admin o gerencia pueden eliminar inversiones', 'SIN_PERMISO', 'Solo admin o gerencia pueden eliminar inversiones'],
    ['42501', 'Una inversión de Avance la elimina un admin del portal', 'SIN_PERMISO', 'Una inversión de Avance la elimina un admin del portal'],
    ['42501', 'Esta inversión es la conversión de un lead: solo gerencia puede anularla y eliminarla', 'SIN_PERMISO',
      'Esta inversión es la conversión de un lead: solo gerencia puede anularla y eliminarla'],
    ['42501', 'permission denied for function eliminar_inversion_fn', 'SIN_PERMISO', 'No tienes permiso para eliminar esta inversión.'],
    ['22023', 'El motivo admite como máximo 300 caracteres', 'REGLA_SERVIDOR', 'El motivo admite como máximo 300 caracteres'],
    ['P0002', 'La inversión no existe o ya fue eliminada', 'NO_ENCONTRADA', 'La inversión no existe o ya fue eliminada'],
    ['P0409', 'Este contrato ya se renovó: tiene historia propia y no se elimina', 'CONFLICTO',
      'Este contrato ya se renovó: tiene historia propia y no se elimina'],
    ['55000', 'El PDF se está generando; reintenta la eliminación en unos minutos', 'CONFLICTO',
      'El PDF se está generando; reintenta la eliminación en unos minutos'],
    ['PT409', 'El lead tiene otra operacion en curso; reintenta la retirada', 'REINTENTAR',
      'El lead tiene otra operacion en curso; reintenta la retirada'],
    ['55P03', 'canceling statement due to lock timeout', 'REINTENTAR', 'Otra operación está usando esta inversión. Vuelve a intentarlo en unos segundos.'],
    ['XX000', 'internal error', 'POSTGREST_ERROR', 'No se pudo eliminar la inversión.'],
  ])('el rechazo %s («%s») llega como %s', async (pg, textoServidor, codigo, mensaje) => {
    server.use(http.post(RUTA, () => HttpResponse.json(
      { code: pg, message: textoServidor, details: null, hint: null }, { status: pg === '42501' ? 403 : 400 })))
    const e = await fallo(eliminarInversion(FUENTE, 'Registro duplicado'))
    expect(e.code).toBe(codigo)
    expect(e.message).toBe(mensaje)
  })

  it('sin respuesta del servidor no afirma que la eliminación falló', async () => {
    server.use(http.post(RUTA, () => HttpResponse.error()))
    const e = await fallo(eliminarInversion(FUENTE, 'Registro duplicado'))
    expect(e.code).toBe('RESPUESTA_NO_RECIBIDA')
    expect(e.message).toMatch(/pudo eliminarse/)
  })

  it.each([
    ['un id que no es uuid', 'fuente-1', 'Registro duplicado', 'INVERSION_FUENTE_INVALIDA'],
    ['un motivo de 4 caracteres', FUENTE, '  abcd  ', 'INVERSION_MOTIVO_INVALIDO'],
    ['un motivo de 301 caracteres', FUENTE, 'x'.repeat(301), 'INVERSION_MOTIVO_INVALIDO'],
  ])('%s no viaja al servidor', async (_, fuente, motivo, codigo) => {
    // Sin handler: con onUnhandledRequest 'error', cualquier petición haría fallar la prueba.
    const e = await fallo(eliminarInversion(fuente, motivo))
    expect(e.code).toBe(codigo)
  })
})
