// @vitest-environment node
// «Eliminar lead (error de carga)» contra el cliente supabase-js real y una Data API
// simulada: ruta RPC y esquema crm, argumentos EXACTOS, acuse estricto (una clave de
// más o un tipo distinto es otra respuesta) y los RAISE de la puerta con su texto.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, eliminarLeadErrorCarga } from './crm-api'

const RUTA = 'http://supabase.test/rest/v1/rpc/eliminar_lead_error_carga'
const LEAD = 'de667c0d-1111-4111-8111-111111111111'
const COPIA = '77777777-7777-4777-8777-777777777777'
const FILAS = { lead: 1, tareas: 2, actividades: 3, lead_asignaciones: 1, sla_operacion_recibos: 0 }
const ACUSE = { ok: true, lead_id: LEAD, copia_id: COPIA, filas: FILAS }
const MOTIVO = 'Se cargó dos veces desde oficina'

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

describe('eliminarLeadErrorCarga (crm.eliminar_lead_error_carga)', () => {
  it('manda exactamente p_lead_id y p_motivo (recortado) al esquema crm y devuelve el acuse', async () => {
    let cuerpo: unknown = null
    let perfil: string | null = null
    server.use(http.post(RUTA, async ({ request }) => {
      cuerpo = await request.json()
      perfil = request.headers.get('content-profile')
      return HttpResponse.json(ACUSE)
    }))

    const resultado = await eliminarLeadErrorCarga(LEAD, `\n  ${MOTIVO} \t`)

    expect(cuerpo).toEqual({ p_lead_id: LEAD, p_motivo: MOTIVO })
    expect(perfil).toBe('crm')
    expect(resultado).toEqual({ copiaId: COPIA, filas: FILAS })
  })

  it('acepta el acuse aunque el servidor cuente una tabla que hoy no conoce', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json({ ...ACUSE, filas: { ...FILAS, tabla_nueva: 4 } })))
    await expect(eliminarLeadErrorCarga(LEAD, MOTIVO)).resolves.toEqual({
      copiaId: COPIA, filas: { ...FILAS, tabla_nueva: 4 },
    })
  })

  it.each([
    ['una clave de más', { ...ACUSE, detalle: 'extra' }],
    ['una copia que no es uuid', { ...ACUSE, copia_id: 'copia-1' }],
    ['un conteo negativo', { ...ACUSE, filas: { ...FILAS, tareas: -1 } }],
    ['un conteo como texto', { ...ACUSE, filas: { ...FILAS, tareas: '2' } }],
    ['ok distinto de true', { ...ACUSE, ok: false }],
    ['una clave que falta', { ok: true, lead_id: LEAD, copia_id: COPIA }],
    ['otro lead', { ...ACUSE, lead_id: COPIA }],
    ['un cuerpo vacío', null],
  ])('rechaza un acuse con %s y no lo presenta como eliminado', async (_, cuerpo) => {
    server.use(http.post(RUTA, () => HttpResponse.json(cuerpo)))
    const e = await fallo(eliminarLeadErrorCarga(LEAD, MOTIVO))
    expect(e.code).toBe('LEAD_ELIMINADO_CONTRACT')
    expect(e.message).toMatch(/pudo completarse/)
  })

  it.each([
    ['42501', 'Inicia sesión para eliminar un lead', 'SIN_PERMISO', 'Inicia sesión para eliminar un lead'],
    ['42501', 'Solo gerencia o un admin del portal pueden eliminar un lead', 'SIN_PERMISO',
      'Solo gerencia o un admin del portal pueden eliminar un lead'],
    ['42501', 'permission denied for function eliminar_lead_error_carga', 'SIN_PERMISO', 'No tienes permiso para eliminar este lead.'],
    ['PGRST301', 'JWT expired', 'SIN_PERMISO', 'No tienes permiso para eliminar este lead.'],
    ['22023', 'Escribe el motivo de la eliminación (al menos 10 caracteres)', 'REGLA_SERVIDOR',
      'Escribe el motivo de la eliminación (al menos 10 caracteres)'],
    ['22023', 'El motivo admite como máximo 500 caracteres', 'REGLA_SERVIDOR', 'El motivo admite como máximo 500 caracteres'],
    ['P0002', 'El lead no existe o ya fue eliminado', 'NO_ENCONTRADA', 'El lead no existe o ya fue eliminado'],
    ['P0409', 'No se puede eliminar este lead: tiene un contrato enlazado; se creó hace más de 30 días (01/09/2026).', 'CONFLICTO',
      'No se puede eliminar este lead: tiene un contrato enlazado; se creó hace más de 30 días (01/09/2026).'],
    ['55000', 'Hay tablas nuevas enlazadas al lead que esta eliminación no conoce (crm.x → crm.leads); hay que revisarla antes',
      'CONFLICTO', 'Hay tablas nuevas enlazadas al lead que esta eliminación no conoce (crm.x → crm.leads); hay que revisarla antes'],
    ['55000', 'La eliminación quedó incompleta; no se aplicó nada', 'CONFLICTO', 'La eliminación quedó incompleta; no se aplicó nada'],
    ['55P03', 'canceling statement due to lock timeout', 'REINTENTAR',
      'Otra operación está usando este lead. Vuelve a intentarlo en unos segundos.'],
    ['40001', 'could not serialize access due to concurrent update', 'REINTENTAR',
      'Otra operación está usando este lead. Vuelve a intentarlo en unos segundos.'],
    ['XX000', 'internal error', 'POSTGREST_ERROR', 'No se pudo eliminar el lead.'],
  ])('el rechazo %s («%s») llega como %s', async (pg, textoServidor, codigo, mensaje) => {
    server.use(http.post(RUTA, () => HttpResponse.json(
      { code: pg, message: textoServidor, details: null, hint: null }, { status: pg === '42501' ? 403 : 400 })))
    const e = await fallo(eliminarLeadErrorCarga(LEAD, MOTIVO))
    expect(e.code).toBe(codigo)
    expect(e.message).toBe(mensaje)
  })

  it('sin respuesta del servidor no afirma que la eliminación falló', async () => {
    server.use(http.post(RUTA, () => HttpResponse.error()))
    const e = await fallo(eliminarLeadErrorCarga(LEAD, MOTIVO))
    expect(e.code).toBe('RESPUESTA_NO_RECIBIDA')
    expect(e.message).toMatch(/pudo eliminarse/)
  })

  it.each([
    ['un id que no es uuid', 'lead-1', MOTIVO, 'LEAD_ELIMINAR_INVALIDO'],
    ['un motivo de 9 caracteres', LEAD, '  123456789  ', 'LEAD_ELIMINAR_MOTIVO_INVALIDO'],
    ['un motivo de solo blancos', LEAD, ' \n\t\u00a0'.repeat(5), 'LEAD_ELIMINAR_MOTIVO_INVALIDO'],
    ['un motivo de 501 caracteres', LEAD, 'x'.repeat(501), 'LEAD_ELIMINAR_MOTIVO_INVALIDO'],
  ])('%s no viaja al servidor', async (_, lead, motivo, codigo) => {
    // Sin handler: con onUnhandledRequest 'error', cualquier petición haría fallar la prueba.
    const e = await fallo(eliminarLeadErrorCarga(lead, motivo))
    expect(e.code).toBe(codigo)
  })

  it('cuenta caracteres como Postgres: 500 emojis caben, 501 no', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json(ACUSE)))
    await expect(eliminarLeadErrorCarga(LEAD, '🙂'.repeat(500))).resolves.toMatchObject({ copiaId: COPIA })
    const e = await fallo(eliminarLeadErrorCarga(LEAD, '🙂'.repeat(501)))
    expect(e.code).toBe('LEAD_ELIMINAR_MOTIVO_INVALIDO')
  })
})
