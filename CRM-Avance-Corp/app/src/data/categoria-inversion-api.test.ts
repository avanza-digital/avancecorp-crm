// @vitest-environment node
import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { corregirCategoriaInversion } from './categoria-inversion-api'

const contrato = 'cc150000-0000-4000-8000-000000002010'
const ruta = 'http://supabase.test/rest/v1/rpc/corregir_categoria_contrato_fn'
const server = setupServer()
beforeAll(() => server.listen({onUnhandledRequest: 'error'}))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

it('envía la clasificación de inversión y el motivo a su puerta auditada', async () => {
  server.use(http.post(ruta, async ({request}) => {
    expect(request.headers.get('content-profile')).toBe('crm')
    expect(await request.json()).toEqual({p_contrato_id:contrato,p_categoria:'renovacion',p_motivo:'Registro incorrecto'})
    return HttpResponse.json({ok:true,cambio:true,contrato_id:contrato,categoria:'renovacion'})
  }))
  await expect(corregirCategoriaInversion(contrato,'renovacion',' Registro incorrecto ')).resolves.toMatchObject({cambio:true})
})
it.each(['42501','P0409'])('propaga el rechazo %s sin confirmar la corrección', async code => {
  server.use(http.post(ruta, () => HttpResponse.json({code,message:'Corrección rechazada'}, {status:403})))
  await expect(corregirCategoriaInversion(contrato,'nuevo','Registro incorrecto')).rejects.toMatchObject({code})
})
it.each([
  {contrato_id:'cc150000-0000-4000-8000-000000002011',categoria:'renovacion'},
  {contrato_id:contrato,categoria:'upgrade'},
])('rechaza un acuse de otra inversión o categoría', async acuse => {
  server.use(http.post(ruta, () => HttpResponse.json({ok:true,cambio:true,...acuse})))
  await expect(corregirCategoriaInversion(contrato,'renovacion','Registro incorrecto')).rejects.toMatchObject({code:'RESPUESTA_INCOMPLETA'})
})
