import {describe,it,expect} from 'vitest'
import {datosAvanceRevisados,mismoContenidoInversion,guardarBorradorAcceso,guardarBorradorCondiciones,guardarIntentoInversion,
  leerBorradorAcceso,leerBorradorCondiciones,leerIntentoInversion,limpiarIntentosInversion,nuevoIntentoInversion,
  solicitudCorresponde,type DatosBorradorCondiciones,type SolicitudInversion,type DatosInversion} from './inversion-solicitud'
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
  it('aísla los datos de acceso por actor, persona, lead y solicitud; los borra al perder acceso',()=>{
    sessionStorage.clear()
    const actor='22222222-2222-4222-8222-222222222222'
    const otroActor='99999999-9999-4999-8999-999999999999'
    const otraPersona='44444444-4444-4444-8444-444444444444'
    const lead='33333333-3333-4333-8333-333333333333'
    const solicitud='55555555-5555-4555-8555-555555555555'
    const datos={apellidos:'PRUEBA',nombres:'PERSONA',correo:'persona@example.invalid',telefono:'999999999',domicilio:'Av. Prueba 123, Lima'}
    guardarBorradorAcceso(actor,base.inversionista_id,lead,null,datos)
    guardarBorradorAcceso(actor,base.inversionista_id,lead,solicitud,{...datos,correo:'corregido@example.invalid'})
    guardarBorradorAcceso(actor,otraPersona,lead,null,{...datos,correo:'otra@example.invalid'})
    guardarBorradorAcceso(otroActor,base.inversionista_id,lead,null,{...datos,correo:'otro-actor@example.invalid'})
    guardarBorradorAcceso(actor,base.inversionista_id,undefined,null,{...datos,correo:'cartera@example.invalid'})
    expect(leerBorradorAcceso(actor,base.inversionista_id,lead)?.correo).toBe(datos.correo)
    expect(leerBorradorAcceso(actor,base.inversionista_id,lead,solicitud)?.correo).toBe('corregido@example.invalid')
    expect(leerBorradorAcceso(actor,base.inversionista_id)?.correo).toBe('cartera@example.invalid')
    expect(leerBorradorAcceso(actor,otraPersona,lead)?.correo).toBe('otra@example.invalid')
    limpiarIntentosInversion(actor,base.inversionista_id)
    expect(leerBorradorAcceso(actor,base.inversionista_id)?.correo).toBeUndefined()
    expect(leerBorradorAcceso(actor,base.inversionista_id,lead)?.correo).toBe(datos.correo)
    limpiarIntentosInversion(actor,base.inversionista_id,lead)
    expect(leerBorradorAcceso(actor,base.inversionista_id,lead)).toBeNull()
    expect(leerBorradorAcceso(actor,base.inversionista_id,lead,solicitud)).toBeNull()
    expect(leerBorradorAcceso(actor,otraPersona,lead)?.correo).toBe('otra@example.invalid')
    expect(leerBorradorAcceso(otroActor,base.inversionista_id,lead)?.correo).toBe('otro-actor@example.invalid')
    limpiarIntentosInversion()
    expect(leerBorradorAcceso(actor,otraPersona,lead)).toBeNull()
    expect(leerBorradorAcceso(otroActor,base.inversionista_id,lead)).toBeNull()
  })
  it('recupera condiciones parciales solo en la revisión vigente de la misma solicitud',()=>{
    sessionStorage.clear()
    const actor='22222222-2222-4222-8222-222222222222'
    const lead='33333333-3333-4333-8333-333333333333'
    const solicitud='55555555-5555-4555-8555-555555555555'
    const datos:DatosBorradorCondiciones={analistaCierre:actor,categoria:'nuevo',tipoInteres:'simple',modalidad:'mensual',
      capital:'23000',capitalRenovado:'',capitalAdicional:'',moneda:'PEN',tasa:'15',origenUpgrade:'',
      fechaInicio:'2026-09-22',plazo:'12',vencManual:'',prefijo:'2026-01-',numero:'000719',notas:'',
      cuentaSeleccionada:'cuenta-prueba',requiereReingresarDatosSensibles:false,domicilio:''}
    guardarBorradorCondiciones(actor,base.inversionista_id,lead,solicitud,0,datos)
    guardarBorradorCondiciones(actor,base.inversionista_id,undefined,solicitud,0,{...datos,capital:'24000'})
    expect(leerBorradorCondiciones(actor,base.inversionista_id,lead,solicitud,0)?.capital).toBe('23000')
    expect(leerBorradorCondiciones(actor,base.inversionista_id,lead,solicitud,1)).toBeNull()
    expect(leerBorradorCondiciones(actor,base.inversionista_id,undefined,solicitud,0)?.capital).toBe('24000')
    expect(leerBorradorCondiciones(actor,'44444444-4444-4444-8444-444444444444',lead,solicitud,0)).toBeNull()
    limpiarIntentosInversion(actor,base.inversionista_id)
    expect(leerBorradorCondiciones(actor,base.inversionista_id,undefined,solicitud,0)).toBeNull()
    expect(leerBorradorCondiciones(actor,base.inversionista_id,lead,solicitud,0)?.capital).toBe('23000')
    limpiarIntentosInversion(actor,base.inversionista_id,lead)
    expect(leerBorradorCondiciones(actor,base.inversionista_id,lead,solicitud,0)).toBeNull()
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
