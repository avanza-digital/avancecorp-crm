// @vitest-environment node
import {afterAll,afterEach,beforeAll,expect,it,vi} from 'vitest'
import {http,HttpResponse} from 'msw'
import {setupServer} from 'msw/node'
vi.mock('@/lib/supabase',async()=>{
  const {createClient}=await import('@supabase/supabase-js')
  return {sb:createClient('http://supabase.test','anon-fake')}
})
import {prepararSolicitudInversion} from './inversion-solicitud-api'
import {nuevoIntentoInversion,type SolicitudInversion} from '@/lib/inversion-solicitud'
import {ACTOR_F5,PERSONA_F5,FUENTE_F5} from '@/test/fixtures/f5'
const server=setupServer()
beforeAll(()=>server.listen({onUnhandledRequest:'error'}))
afterEach(()=>server.resetHandlers())
afterAll(()=>server.close())
const datos={inversionista_id:PERSONA_F5,empresa:'qorilazo' as const,monto:250,moneda:'PEN' as const}
const base: SolicitudInversion={solicitud_id:FUENTE_F5,estado:'preparada',inversion_id:null,
  inversionista_id:PERSONA_F5,inversionista_origen_id:PERSONA_F5,identidad_fusionada:false,
  responsable_esperado_id:ACTOR_F5,responsable_actual_id:ACTOR_F5,requiere_revision_responsable:false,
  revision_datos:0,revision_responsable:0,hash_datos:'h',necesita_portal:false,
  comprobante_bucket:'f4-comprobantes',comprobante_ruta:null,resultado:null,datos}

it.each(['upgrade','reinversion'] as const)('%s usa su RPC y conserva el origen al releer',async tipo=>{
  const intento=nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,datos,
    tipo==='upgrade'?{tipo,fuenteId:FUENTE_F5}:FUENTE_F5)
  const respuesta={...base,[tipo==='upgrade'?'upgrade_origen_id':'reinversion_origen_id']:FUENTE_F5}
  let llamadas=0
  server.use(http.post(`http://supabase.test/rest/v1/rpc/preparar_${tipo}_fn`,async({request})=>{
    llamadas++
    expect(request.headers.get('content-profile')).toBe('crm')
    expect(await request.json()).toEqual({p_clave:FUENTE_F5,p_fuente:FUENTE_F5,p_datos:datos})
    return HttpResponse.json(respuesta)
  }),http.post('http://supabase.test/rest/v1/rpc/solicitud_inversion_fn',()=>HttpResponse.json(respuesta)))
  expect(await prepararSolicitudInversion(intento)).toEqual(respuesta)
  expect(llamadas).toBe(1)
})

it('rechaza tipos mezclados antes de enviar una solicitud financiera',async()=>{
  const intento=nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,datos,{tipo:'upgrade',fuenteId:FUENTE_F5})
  await expect(prepararSolicitudInversion({...intento,reinversion_origen_id:FUENTE_F5})).rejects.toMatchObject({code:'22023'})
  await expect(prepararSolicitudInversion({...intento,venta_cruzada:{busqueda_id:FUENTE_F5,motivo:'Motivo sintético'}})).rejects.toMatchObject({code:'22023'})
})
