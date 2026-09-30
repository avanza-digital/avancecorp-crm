// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { editarLeadFn, insertarLead } from './crm-api'
import { obtenerDocumentoLead } from './documento-lead'

const id = 'd0000000-0000-4000-8000-000000000001'
const identificador = 'd0000000-0000-4000-8000-000000000002'
const documento = { lead_id: id, tipo: 'CE', numero: '001234567',
  inversionista_id: identificador, identificador_id: identificador, puede_corregir: true }
const rpc = (nombre: string) => `http://supabase.test/rest/v1/rpc/${nombre}`
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('documento tipado del lead — contrato HTTP', () => {
  it('crea en una sola RPC conservando tipo y ceros, sin enviar el DNI legado', async () => {
    let body: unknown
    server.use(http.post(rpc('crear_lead_documento_fn'), async ({ request }) => {
      body = await request.json()
      return HttpResponse.json({ estado: 'creado', lead_id: id })
    }))
    const datos = { id, nombre_completo: 'PERSONA CE', telefono: '+51988770001', origen: 'referido', monto_estimado: 5000, moneda: 'PEN' }
    await insertarLead({ ...datos, dni: null, documento: { tipo: 'CE', numero: '001234567' } })
    expect(body).toEqual({ p_datos: datos, p_tipo: 'CE', p_documento: '001234567' })
  })

  it('edita datos y corrección administrativa en una sola transacción', async () => {
    let body: unknown
    server.use(http.post(rpc('editar_lead_documento_fn'), async ({ request }) => {
      body = await request.json()
      return HttpResponse.json(documento)
    }))
    await editarLeadFn(id, { dni: null, distrito: 'Lima', documento: { tipo: 'CE', numero: '001234567' },
      correccion_documento: { identificador_anterior: identificador, motivo: 'Tipo incorrecto en el alta' } })
    expect(body).toEqual({ p_lead_id: id, p_cambios: { distrito: 'Lima' }, p_tipo: 'CE', p_documento: '001234567',
      p_identificador_anterior: identificador, p_motivo: 'Tipo incorrecto en el alta' })
  })

  it('no anuncia una corrección si el servidor devuelve el documento anterior', async () => {
    server.use(http.post(rpc('editar_lead_documento_fn'), () => HttpResponse.json({ ...documento, tipo: 'DNI', numero: '00123456' })))
    await expect(editarLeadFn(id, { documento: { tipo: 'CE', numero: '001234567' } })).rejects.toMatchObject({ code: 'DOCUMENTO_LEAD_CONTRACT' })
  })

  it('lee la identidad canónica del lead solicitado', async () => {
    server.use(http.post(rpc('documento_lead_fn'), async ({ request }) => {
      expect(await request.json()).toEqual({ p_lead_id: id })
      return HttpResponse.json(documento)
    }))
    await expect(obtenerDocumentoLead(id)).resolves.toEqual(documento)
  })

  it('rechaza una respuesta que pertenece a otro lead', async () => {
    server.use(http.post(rpc('documento_lead_fn'), () => HttpResponse.json({ ...documento, lead_id: identificador })))
    await expect(obtenerDocumentoLead(id)).rejects.toMatchObject({ code: 'DOCUMENTO_LEAD_CONTRACT' })
  })
})
