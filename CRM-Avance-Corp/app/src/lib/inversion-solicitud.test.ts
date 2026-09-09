import {describe,it,expect} from 'vitest'
import {datosAvanceRevisados,mismoContenidoInversion,type DatosInversion} from './inversion-solicitud'
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
})
