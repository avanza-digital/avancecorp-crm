// @vitest-environment node
// F2.b [D-15] — las dos puertas del front (reabrir; editar la ficha en una transacción), contra un
// Supabase SIMULADO con msw: contrato HTTP real (POST /rpc/*, argumentos exactos) y el
// MAPEO DE ERRORES: los conflictos de identidad (P0409) llegan con el texto del servidor
// (antes se tapaban con «No se pudo guardar el cambio»), el veto P0429 como NO_INSISTA,
// la fila retenida 55P03 como REINTENTAR, y el 23505 del teléfono vivo como DUP_TELEFONO.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, editarLeadFn, reabrirLead } from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

const pgError = (code: string, message: string, status = 400) =>
  HttpResponse.json({ code, message, details: null, hint: null }, { status })

async function fallo(p: Promise<unknown>): Promise<CrmApiError> {
  try {
    await p
  } catch (e) {
    if (e instanceof CrmApiError) return e
    throw e
  }
  throw new Error('no falló')
}

describe('reabrirLead (crm.reabrir_lead_fn)', () => {
  it('manda p_lead_id exacto y nada más', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('reabrir_lead_fn'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({ ok: true, lead_id: 'lead-1', etapa: 'nuevo', enlazado: false })
      }),
    )
    await expect(reabrirLead('lead-1')).resolves.toBeUndefined()
    expect(cuerpo).toEqual({ p_lead_id: 'lead-1' })
  })

  it('P0409 (otro lead / ya cliente / conversión en curso) → CONFLICTO con el texto del servidor', async () => {
    server.use(http.post(RPC('reabrir_lead_fn'), () =>
      pgError('P0409', 'La persona ya es cliente o ya tiene su lead: no se puede reabrir')))
    const e = await fallo(reabrirLead('lead-1'))
    expect(e.code).toBe('CONFLICTO')
    expect(e.message).toBe('La persona ya es cliente o ya tiene su lead: no se puede reabrir')
  })

  it('P0429 (la persona tiene «No insistir») → NO_INSISTA, nunca SIN_PERMISO', async () => {
    server.use(http.post(RPC('reabrir_lead_fn'), () =>
      pgError('P0429', 'La persona tiene la restricción «No insistir»: no se puede reabrir')))
    const e = await fallo(reabrirLead('lead-1'))
    expect(e.code).toBe('NO_INSISTA')
    expect(e.message).toContain('No insistir')
  })

  it('P0002 (ajeno o inexistente) → FUERA_DE_COLA con el texto; 55P03 → REINTENTAR; 23505 del teléfono → DUP_TELEFONO', async () => {
    server.use(http.post(RPC('reabrir_lead_fn'), () => pgError('P0002', 'Lead no encontrado o fuera de tu ambito')))
    expect((await fallo(reabrirLead('lead-1'))).code).toBe('FUERA_DE_COLA')
    server.use(http.post(RPC('reabrir_lead_fn'), () => pgError('55P03', 'canceling statement due to lock timeout')))
    expect((await fallo(reabrirLead('lead-1'))).code).toBe('REINTENTAR')
    server.use(http.post(RPC('reabrir_lead_fn'), () =>
      pgError('23505', 'duplicate key value violates unique constraint "uq_leads_telefono_vivo"', 409)))
    expect((await fallo(reabrirLead('lead-1'))).code).toBe('DUP_TELEFONO')
  })

  it('42501 (sin rol CRM) → SIN_PERMISO', async () => {
    server.use(http.post(RPC('reabrir_lead_fn'), () =>
      pgError('42501', 'Solo un analista, un supervisor o Gerencia reabre un lead', 403)))
    expect((await fallo(reabrirLead('lead-1'))).code).toBe('SIN_PERMISO')
  })
})

describe('editarLeadFn (crm.editar_lead_fn)', () => {
  it('manda p_lead_id y p_cambios EXACTOS (la fila que manda la ficha, DNI incluido; el null viaja explícito)', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('editar_lead_fn'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({ ok: true, lead_id: 'lead-1', dni_por_puerta: false })
      }),
    )
    await expect(editarLeadFn('lead-1', { dni: null, nota: 'sin documento', monto_estimado: 25000 })).resolves.toBeUndefined()
    expect(cuerpo).toEqual({ p_lead_id: 'lead-1', p_cambios: { dni: null, nota: 'sin documento', monto_estimado: 25000 } })
  })

  it('P0409 de la puerta del DNI («ya tiene su lead» / «solo lo corrige Gerencia») → CONFLICTO con el texto; 22023 → REGLA_SERVIDOR', async () => {
    server.use(http.post(RPC('editar_lead_fn'), () =>
      pgError('P0409', 'La persona de ese documento ya es cliente o ya tiene su lead: no se puede asignar a este')))
    const e = await fallo(editarLeadFn('lead-1', { dni: '45678901' }))
    expect(e.code).toBe('CONFLICTO')
    expect(e.message).toContain('ya tiene su lead')
    server.use(http.post(RPC('editar_lead_fn'), () => pgError('22023', 'Campo no editable desde la ficha: etapa')))
    const e2 = await fallo(editarLeadFn('lead-1', { nota: 'x' }))
    expect(e2.code).toBe('REGLA_SERVIDOR')
    expect(e2.message).toBe('Campo no editable desde la ficha: etapa')
  })

  it('el DNI local viejo (otro usuario lo cambió): P0409 «se fija por su puerta» → mensaje de recargar, sin PII', async () => {
    server.use(http.post(RPC('editar_lead_fn'), () =>
      pgError('P0409', 'Con la identidad unificada encendida, el DNI de un lead se fija por su puerta (fijar_dni_lead_fn) o lo corrige Gerencia')))
    const e = await fallo(editarLeadFn('lead-1', { dni: '45678901', nota: 'x' }))
    expect(e.code).toBe('CONFLICTO')
    expect(e.message).toContain('La ficha cambió en otra sesión')
  })

  it('40001 → REINTENTAR; 23505 del DNI vivo → DUP_DNI; P0002 (fuera de ámbito) → FUERA_DE_COLA; 42501 → SIN_PERMISO', async () => {
    server.use(http.post(RPC('editar_lead_fn'), () => pgError('40001', 'El documento de este lead cambió mientras se bloqueaba; vuelve a intentarlo')))
    expect((await fallo(editarLeadFn('lead-1', { dni: '45678901' }))).code).toBe('REINTENTAR')
    server.use(http.post(RPC('editar_lead_fn'), () => pgError('23505', 'duplicate key value violates unique constraint "uq_leads_dni_vivo"', 409)))
    expect((await fallo(editarLeadFn('lead-1', { dni: '45678901' }))).code).toBe('DUP_DNI')
    server.use(http.post(RPC('editar_lead_fn'), () => pgError('P0002', 'Lead no encontrado o fuera de tu ambito')))
    expect((await fallo(editarLeadFn('lead-1', { nota: 'x' }))).code).toBe('FUERA_DE_COLA')
    server.use(http.post(RPC('editar_lead_fn'), () => pgError('42501', 'Sesión requerida', 403)))
    expect((await fallo(editarLeadFn('lead-1', { nota: 'x' }))).code).toBe('SIN_PERMISO')
    server.use(http.post(RPC('editar_lead_fn'), () => pgError('40P01', 'deadlock detected')))
    const e = await fallo(editarLeadFn('lead-1', { nota: 'x' }))
    expect(e.code).toBe('REINTENTAR')
    expect(e.message).toContain('Vuelve a intentarlo')
  })
})
