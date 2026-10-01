import {describe,it,expect} from 'vitest'
import {datosAvanceRevisados,mismoContenidoInversion,guardarBorradorAcceso,guardarBorradorCondiciones,guardarIntentoInversion,
  guardarConversionAbierta,leerConversionAbierta,limpiarConversionAbierta,
  leerBorradorAcceso,leerBorradorCondiciones,leerIntentoInversion,limpiarIntentosInversion,nuevoIntentoInversion,
  solicitudCorresponde,SolicitudInversionSchema,type DatosBorradorCondiciones,type SolicitudInversion,type DatosInversion} from './inversion-solicitud'
import * as v from 'valibot'
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
  it('la venta cruzada guarda su intento aparte, con su búsqueda y su motivo, y se limpia sola',()=>{
    sessionStorage.clear()
    const actor='22222222-2222-4222-8222-222222222222',busqueda='44444444-4444-4444-8444-444444444444'
    const cartera=nuevoIntentoInversion(actor,base.inversionista_id,crypto.randomUUID(),base)
    const cruzada=nuevoIntentoInversion(actor,base.inversionista_id,crypto.randomUUID(),base,undefined,
      {busqueda_id:busqueda,motivo:'El cliente pidió invertir conmigo'})
    guardarIntentoInversion(cartera);guardarIntentoInversion(cruzada)
    expect(leerIntentoInversion(actor,base.inversionista_id)?.clave).toBe(cartera.clave)
    expect(leerIntentoInversion(actor,base.inversionista_id,{ventaCruzada:true})).toMatchObject({clave:cruzada.clave,
      venta_cruzada:{busqueda_id:busqueda,motivo:'El cliente pidió invertir conmigo'}})
    limpiarIntentosInversion(actor,base.inversionista_id,{ventaCruzada:true})
    expect(leerIntentoInversion(actor,base.inversionista_id,{ventaCruzada:true})).toBeNull()
    expect(leerIntentoInversion(actor,base.inversionista_id)?.clave).toBe(cartera.clave)
    // Un intento de cartera no se lee como venta cruzada aunque alguien lo copie a su clave.
    sessionStorage.setItem(`crm:f5:solicitud:${actor}:ce-${base.inversionista_id}`,JSON.stringify(cartera))
    expect(()=>leerIntentoInversion(actor,base.inversionista_id,{ventaCruzada:true})).toThrow()
    limpiarIntentosInversion(actor)
    expect(leerIntentoInversion(actor,base.inversionista_id)).toBeNull()
  })
  it('la solicitud de una venta cruzada declara su puerta y su analista',()=>{
    const s=v.parse(SolicitudInversionSchema,{solicitud_id:base.inversionista_id,estado:'preparada',inversion_id:null,
      inversionista_id:base.inversionista_id,inversionista_origen_id:base.inversionista_id,identidad_fusionada:false,
      responsable_esperado_id:null,responsable_actual_id:null,requiere_revision_responsable:false,revision_datos:0,
      revision_responsable:0,hash_datos:'h',necesita_portal:false,comprobante_bucket:null,comprobante_ruta:null,resultado:null,
      puerta:'cliente_existente',analista_cierre_id:'22222222-2222-4222-8222-222222222222'})
    expect(s).toMatchObject({puerta:'cliente_existente',analista_cierre_id:'22222222-2222-4222-8222-222222222222'})
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
  it('la venta cruzada no comparte borradores con la cartera propia, ni al leerlos ni al limpiarlos',()=>{
    sessionStorage.clear()
    const actor='22222222-2222-4222-8222-222222222222'
    const persona=base.inversionista_id
    const solPropia='55555555-5555-4555-8555-555555555555'
    const solCruzada='66666666-6666-4666-8666-666666666666'
    const acceso={apellidos:'PRUEBA',nombres:'PERSONA',correo:'cartera@example.invalid',telefono:'999999999',domicilio:'Av. Prueba 123, Lima'}
    const condiciones:DatosBorradorCondiciones={analistaCierre:actor,categoria:'nuevo',tipoInteres:'simple',modalidad:'mensual',
      capital:'1000',capitalRenovado:'',capitalAdicional:'',moneda:'PEN',tasa:'15',origenUpgrade:'',fechaInicio:'2026-09-24',plazo:'12',
      vencManual:'',prefijo:'2026-01-',numero:'000720',notas:'',cuentaSeleccionada:'',requiereReingresarDatosSensibles:false,domicilio:''}
    const sembrar=()=>{
      guardarBorradorAcceso(actor,persona,undefined,null,acceso)
      guardarBorradorAcceso(actor,persona,{ventaCruzada:true},null,{...acceso,correo:'cruzada@example.invalid'})
      guardarBorradorCondiciones(actor,persona,undefined,solPropia,0,condiciones)
      guardarBorradorCondiciones(actor,persona,{ventaCruzada:true},solCruzada,0,{...condiciones,capital:'2000'})
    }
    sembrar()
    expect(leerBorradorAcceso(actor,persona)?.correo).toBe('cartera@example.invalid')
    expect(leerBorradorAcceso(actor,persona,{ventaCruzada:true})?.correo).toBe('cruzada@example.invalid')
    // Cerrar la venta cruzada no toca los borradores de la cartera propia…
    limpiarIntentosInversion(actor,persona,{ventaCruzada:true})
    expect(leerBorradorAcceso(actor,persona,{ventaCruzada:true})).toBeNull()
    expect(leerBorradorCondiciones(actor,persona,{ventaCruzada:true},solCruzada,0)).toBeNull()
    expect(leerBorradorAcceso(actor,persona)?.correo).toBe('cartera@example.invalid')
    expect(leerBorradorCondiciones(actor,persona,undefined,solPropia,0)?.capital).toBe('1000')
    // …ni la cartera propia los de la venta cruzada.
    sembrar()
    limpiarIntentosInversion(actor,persona)
    expect(leerBorradorAcceso(actor,persona)).toBeNull()
    expect(leerBorradorCondiciones(actor,persona,undefined,solPropia,0)).toBeNull()
    expect(leerBorradorAcceso(actor,persona,{ventaCruzada:true})?.correo).toBe('cruzada@example.invalid')
    expect(leerBorradorCondiciones(actor,persona,{ventaCruzada:true},solCruzada,0)?.capital).toBe('2000')
    // Un borrador de cartera copiado a la clave de la venta cruzada no se lee como suyo.
    sessionStorage.setItem(`crm:f5:acceso:${actor}:${persona}:ce:nuevo`,sessionStorage.getItem(`crm:f5:acceso:${actor}:${persona}:cartera:nuevo`) ??
      JSON.stringify({version:1,actor,persona,solicitud:null,datos:acceso}))
    expect(leerBorradorAcceso(actor,persona,{ventaCruzada:true})).toBeNull()
    limpiarIntentosInversion(actor)
  })
  it('un flujo no adopta la solicitud del otro: la de venta cruzada solo corresponde a la venta cruzada',()=>{
    const s=v.parse(SolicitudInversionSchema,{solicitud_id:base.inversionista_id,estado:'preparada',inversion_id:null,
      inversionista_id:base.inversionista_id,inversionista_origen_id:base.inversionista_id,identidad_fusionada:false,
      responsable_esperado_id:null,responsable_actual_id:null,requiere_revision_responsable:false,revision_datos:0,
      revision_responsable:0,hash_datos:'h',necesita_portal:false,comprobante_bucket:null,comprobante_ruta:null,resultado:null,
      datos:base,puerta:'cliente_existente',analista_cierre_id:'22222222-2222-4222-8222-222222222222'})
    expect(solicitudCorresponde(s,base.inversionista_id,{ventaCruzada:true})).toBe(true)
    expect(solicitudCorresponde(s,base.inversionista_id)).toBe(false)
    const {puerta:_puerta,...propia}=s
    expect(solicitudCorresponde(propia as SolicitudInversion,base.inversionista_id)).toBe(true)
    expect(solicitudCorresponde(propia as SolicitudInversion,base.inversionista_id,{ventaCruzada:true})).toBe(false)
  })
  it('la conversión abierta se retoma solo para su actor y su lead; revocar un lead no la toca y salir las borra todas',()=>{
    sessionStorage.clear()
    const actor='22222222-2222-4222-8222-222222222222',otro='55555555-5555-4555-8555-555555555555'
    const lead='33333333-3333-4333-8333-333333333333',otroLead='66666666-6666-4666-8666-666666666666'
    guardarConversionAbierta(actor,lead,base.inversionista_id)
    guardarConversionAbierta(actor,otroLead,otro)
    expect(leerConversionAbierta(actor,lead)).toBe(base.inversionista_id)
    expect(leerConversionAbierta(actor,otroLead)).toBe(otro)
    expect(leerConversionAbierta(otro,lead)).toBeNull()
    // Solo de quién es: ni la solicitud ni nada de lo que el analista escribe viaja en la marca.
    expect(Object.keys(JSON.parse(sessionStorage.getItem(`crm:f5:conversion-abierta:${actor}:${lead}`)!)).sort())
      .toEqual(['actor','inversionista_id','lead','version'])
    limpiarIntentosInversion(actor,base.inversionista_id,lead)
    expect(leerConversionAbierta(actor,lead)).toBe(base.inversionista_id)
    limpiarConversionAbierta(actor,lead)
    expect(leerConversionAbierta(actor,lead)).toBeNull()
    expect(leerConversionAbierta(actor,otroLead)).toBe(otro)
    limpiarIntentosInversion()
    expect(leerConversionAbierta(actor,otroLead)).toBeNull()
  })
  it('una marca dañada, de otra versión o copiada a otra clave equivale a no tenerla',()=>{
    sessionStorage.clear()
    const actor='22222222-2222-4222-8222-222222222222',lead='33333333-3333-4333-8333-333333333333'
    const clave=`crm:f5:conversion-abierta:${actor}:${lead}`
    const marca={version:1,actor,lead,inversionista_id:base.inversionista_id}
    sessionStorage.setItem(clave,'{no es json');expect(leerConversionAbierta(actor,lead)).toBeNull()
    sessionStorage.setItem(clave,JSON.stringify({...marca,version:2}));expect(leerConversionAbierta(actor,lead)).toBeNull()
    sessionStorage.setItem(clave,JSON.stringify({...marca,inversionista_id:'no-es-uuid'}));expect(leerConversionAbierta(actor,lead)).toBeNull()
    sessionStorage.setItem(clave,JSON.stringify({...marca,lead:base.inversionista_id}));expect(leerConversionAbierta(actor,lead)).toBeNull()
    sessionStorage.setItem(clave,JSON.stringify(marca));expect(leerConversionAbierta(actor,lead)).toBe(base.inversionista_id)
  })
})
