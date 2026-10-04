// @vitest-environment node
// Contrato HTTP de las escrituras de la ficha de la base (F2): registrar_intento_base, reactivar_lead_base y
// marcar_no_contactar (en producción desde el 02/10). Lo que viaja (sin claves vacías: la puerta decide los
// defaults), cómo se lee la respuesta (cifras que llegan como texto) y que un error del servidor llega con su texto.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, marcarNoContactar, reactivarLeadBase, registrarIntentoBase } from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

const OP = '33333333-3333-4333-8333-333333333333'
const LEAD = '11111111-1111-4111-8111-111111111111'
const RESPUESTA_INTENTO = {
  ok: true, replay: false, intento_n: 2, etapa: 'descartado', reactivado: false, enfriado_hasta: null,
  proxima_llamada_en: null, ciclo_n: '1', lead_id: LEAD, evento: 'intento_base', resultado: 'no_contesto',
}

function capturar(fn: string, respuesta: unknown, estado = 200) {
  const recibido: { cuerpo: unknown } = { cuerpo: undefined }
  server.use(http.post(RPC(fn), async ({ request }) => {
    recibido.cuerpo = await request.json()
    return HttpResponse.json(respuesta as never, { status: estado })
  }))
  return recibido
}

describe('registrarIntentoBase (msw)', () => {
  it('sin nota ni rellamada no manda esas claves; la respuesta se lee con sus cifras', async () => {
    const r = capturar('registrar_intento_base', RESPUESTA_INTENTO)
    const respuesta = await registrarIntentoBase({ operacionId: OP, leadId: LEAD, resultado: 'no_contesto', nota: '   ', proximaLlamada: null })
    expect(r.cuerpo).toEqual({ p_operacion_id: OP, p_lead_id: LEAD, p_resultado: 'no_contesto' })
    expect(respuesta).toMatchObject({ ok: true, replay: false, intento_n: 2, reactivado: false, enfriado_hasta: null })
  })

  it('con nota y rellamada las manda tal cual (la nota sin espacios de más)', async () => {
    const r = capturar('registrar_intento_base', { ...RESPUESTA_INTENTO, intento_n: '3', proxima_llamada_en: '2026-10-05T15:00:00+00:00' })
    const respuesta = await registrarIntentoBase({ operacionId: OP, leadId: LEAD, resultado: 'volver_a_llamar', nota: ' llamar lunes ', proximaLlamada: '2026-10-05T15:00:00.000Z' })
    expect(r.cuerpo).toEqual({ p_operacion_id: OP, p_lead_id: LEAD, p_resultado: 'volver_a_llamar', p_nota: 'llamar lunes', p_proxima_llamada: '2026-10-05T15:00:00.000Z' })
    expect(respuesta.intento_n).toBe(3)
  })

  it('un rechazo de la puerta (22023) llega con su texto', async () => {
    capturar('registrar_intento_base', { code: '22023', message: 'El lead esta en descanso hasta el 01/11/2026', details: null, hint: null }, 400)
    await expect(registrarIntentoBase({ operacionId: OP, leadId: LEAD, resultado: 'no_contesto' }))
      .rejects.toMatchObject({ message: 'El lead esta en descanso hasta el 01/11/2026' })
  })

  it('una respuesta fuera de contrato no se toma por buena', async () => {
    capturar('registrar_intento_base', { ok: true })
    const promesa = registrarIntentoBase({ operacionId: OP, leadId: LEAD, resultado: 'no_contesto' })
    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({ code: 'INTENTO_BASE_CONTRACT' })
  })
})

describe('reactivarLeadBase (msw)', () => {
  it('manda operación, lead y nota; lee la etapa y el ciclo', async () => {
    const r = capturar('reactivar_lead_base', { replay: false, etapa: 'contactado', ciclo_n: '2', reactivado_en: '2026-10-03T15:00:00+00:00' })
    const respuesta = await reactivarLeadBase({ operacionId: OP, leadId: LEAD, nota: 'volvió a interesarse' })
    expect(r.cuerpo).toEqual({ p_operacion_id: OP, p_lead_id: LEAD, p_nota: 'volvió a interesarse' })
    expect(respuesta).toMatchObject({ replay: false, etapa: 'contactado', ciclo_n: 2 })
  })

  it('sin nota no manda la clave', async () => {
    const r = capturar('reactivar_lead_base', { replay: true, etapa: 'contactado', ciclo_n: 2 })
    await reactivarLeadBase({ operacionId: OP, leadId: LEAD, nota: '' })
    expect(r.cuerpo).toEqual({ p_operacion_id: OP, p_lead_id: LEAD })
  })
})

describe('marcarNoContactar (msw)', () => {
  it('manda el lead y el motivo sin espacios de más', async () => {
    const r = capturar('marcar_no_contactar', { ok: true })
    await marcarNoContactar(LEAD, '  pidió que no lo llamen  ')
    expect(r.cuerpo).toEqual({ p_lead_id: LEAD, p_motivo: 'pidió que no lo llamen' })
  })

  it('fuera de su ámbito (P0002) llega con el texto del servidor', async () => {
    capturar('marcar_no_contactar', { code: 'P0002', message: 'Lead no encontrado o fuera de tu ambito', details: null, hint: null }, 400)
    await expect(marcarNoContactar(LEAD, 'motivo largo')).rejects.toMatchObject({ message: 'Lead no encontrado o fuera de tu ambito' })
  })
})
