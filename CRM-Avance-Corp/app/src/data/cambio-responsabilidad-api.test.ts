// @vitest-environment node
import {afterAll,afterEach,beforeAll,expect,it,vi} from 'vitest'
import {http,HttpResponse} from 'msw'
import {setupServer} from 'msw/node'
vi.mock('@/lib/supabase',async()=>{
  const {createClient}=await import('@supabase/supabase-js')
  return {sb:createClient('http://supabase.test','anon-fake')}
})
import {previsualizarResponsabilidad,confirmarResponsabilidad,type PreviaResponsabilidad} from './cambio-responsabilidad-api'
const id='11111111-1111-4111-8111-111111111111', destino='22222222-2222-4222-8222-222222222222'
const previa:PreviaResponsabilidad={version:'a'.repeat(32),accion:'venta',id,destino,anterior:null,
  anterior_nombre:null,destino_nombre:'Jorge',persona_id:null,cliente_id:null,perfil_cambia:false,leads:0,tareas:0,aviso:'Conserva el capital',efectos:[]}
const base='http://supabase.test/rest/v1/rpc/'
const server=setupServer()
beforeAll(()=>server.listen({onUnhandledRequest:'error'}))
afterEach(()=>server.resetHandlers())
afterAll(()=>server.close())
it('lee el efecto del servidor sin ejecutar una escritura',async()=>{
  server.use(http.post(base+'previsualizar_cambio_responsabilidad_fn',async({request})=>{
    expect(request.headers.get('content-profile')).toBe('crm')
    expect(await request.json()).toEqual({p_accion:'venta',p_id:id,p_destino:destino})
    return HttpResponse.json(previa)
  }))
  expect(await previsualizarResponsabilidad('venta',id,destino)).toEqual(previa)
})
it('rechaza vista previa de otra acción o destinatario',async()=>{
  server.use(http.post(base+'previsualizar_cambio_responsabilidad_fn',()=>HttpResponse.json({...previa,destino:id})))
  await expect(previsualizarResponsabilidad('venta',id,destino)).rejects.toThrow('no corresponde')
})
it('confirma únicamente la versión revisada y el motivo',async()=>{
  server.use(http.post(base+'confirmar_cambio_responsabilidad_fn',async({request})=>{
    expect(await request.json()).toEqual({p_accion:'venta',p_id:id,p_destino:destino,p_motivo:'Corrección',p_version:previa.version})
    return HttpResponse.json({ok:true,version_confirmada:previa.version,efectos:[]})
  }))
  await expect(confirmarResponsabilidad(previa,' Corrección ')).resolves.toMatchObject({ok:true})
})
it('un conflicto no reintenta por la puerta antigua',async()=>{
  let llamadas=0
  server.use(http.post(base+'confirmar_cambio_responsabilidad_fn',()=>{
    llamadas++;return HttpResponse.json({code:'PT409',message:'La información cambió'},{status:409})
  }))
  await expect(confirmarResponsabilidad(previa,'Corrección')).rejects.toThrow('La información cambió')
  expect(llamadas).toBe(1)
})
it('no acepta éxito sin versión confirmada',async()=>{
  server.use(http.post(base+'confirmar_cambio_responsabilidad_fn',()=>HttpResponse.json({ok:true})))
  await expect(confirmarResponsabilidad(previa,'Corrección')).rejects.toThrow()
})
