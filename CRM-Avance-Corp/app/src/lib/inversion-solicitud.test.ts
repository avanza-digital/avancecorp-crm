import {describe,it,expect} from 'vitest'
import {datosAvanceRevisados,mismoContenidoInversion,guardarIntentoInversion,leerIntentoInversion,
  limpiarIntentosInversion,nuevoIntentoInversion,solicitudCorresponde,type SolicitudInversion,type DatosInversion} from './inversion-solicitud'
const base: DatosInversion={inversionista_id:'11111111-1111-4111-8111-111111111111',empresa:'avance'}
describe('Contenido de una solicitud F5',()=>{
  it('releer JSONB con otro orden no exige corregir; cambiar importe u orden de cuotas sí',()=>{
    const a={...base,contrato:{capital:1500,moneda:'PEN'},cuenta:{banco:'BCP',tipo:'nueva'},cronograma:[1,2]}
    const b={...base,cuenta:{tipo:'nueva',banco:'BCP'},contrato:{moneda:'PEN',capital:1500},cronograma:[1,2]}
    expect(mismoContenidoInversion(a,b)).toBe(true)
    expect(mismoContenidoInversion(a,{...b,contrato:{...b.contrato,capital:1600}})).toBe(false)
    expect(mismoContenidoInversion(a,{...b,cronograma:[2,1]})).toBe(false)
  })
  it('F4 resuelve propietario/perfil/UUID; el formulario conserva los datos reservados de acceso',()=>{
    const acceso={correo:'prueba@example.com',nombre_completo:'FICTICIO',nombres:'FICTICIO',apellidos:'PRUEBA',telefono:'999999999',domicilio:'CALLE FICTICIA 123'}
    const r=datosAvanceRevisados({...base,alta_portal:acceso},{capital:1500,cliente_id:'perfil-ajeno',analista_cierre_id:'actor-ajeno',clave_idempotencia:'otro-id'},[],{})
    expect(r.contrato).toEqual({capital:1500});expect(r.alta_portal).toEqual(acceso)
  })
  it('separa el borrador de Cartera del lead y limpia sólo el origen revocado',()=>{
    sessionStorage.clear()
    const actor='22222222-2222-4222-8222-222222222222',lead='33333333-3333-4333-8333-333333333333'
    const cartera=nuevoIntentoInversion(actor,base.inversionista_id,crypto.randomUUID(),base)
    const inicial=nuevoIntentoInversion(actor,base.inversionista_id,crypto.randomUUID(),{...base,lead_id:lead})
    guardarIntentoInversion(cartera);guardarIntentoInversion(inicial)
    expect(leerIntentoInversion(actor,base.inversionista_id)?.clave).toBe(cartera.clave)
    expect(leerIntentoInversion(actor,base.inversionista_id,lead)?.clave).toBe(inicial.clave)
    limpiarIntentosInversion(actor,base.inversionista_id,lead)
    expect(leerIntentoInversion(actor,base.inversionista_id,lead)).toBeNull()
    expect(leerIntentoInversion(actor,base.inversionista_id)?.clave).toBe(cartera.clave)
    limpiarIntentosInversion(actor)
  })
  it('recupera la identidad original tras fusionar, sin aceptar otra persona u otro lead',()=>{
    const origen=base.inversionista_id,canonica='22222222-2222-4222-8222-222222222222',lead='33333333-3333-4333-8333-333333333333'
    const s={inversionista_id:canonica,inversionista_origen_id:origen,datos:base} as SolicitudInversion
    expect(solicitudCorresponde(s,origen)).toBe(true)
    expect(solicitudCorresponde(s,canonica)).toBe(true)
    expect(solicitudCorresponde(s,lead)).toBe(false)
    expect(solicitudCorresponde(s,origen,lead)).toBe(false)
    expect(solicitudCorresponde({...s,datos:{...base,lead_id:lead}},origen,lead)).toBe(true)
  })
})
