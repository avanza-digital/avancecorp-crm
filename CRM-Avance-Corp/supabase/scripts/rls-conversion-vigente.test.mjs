import test from 'node:test';
import assert from 'node:assert/strict';
import { claveConversion, convertirCoopVigente } from './rls-conversion-vigente.mjs';

const args = {p_lead_id:'00000000-0000-4000-8000-000000000001',p_cooperativa:'qorilazo',
  p_monto:1000,p_moneda:'PEN',p_documento_tipo:'DNI',p_documento:'99000001',
  p_nombre:'PERSONA FICTICIA',p_numero_transaccion:'FICTICIA-1'};
function actor({fallo,confirmada=false}={}) {
  const llamadas = [];
  const error = {data:null,error:{code:'42501',message:'Denegado de prueba'},status:403};
  const resultado = {data:{ok:true,inversion_id:'inversion-ficticia',reintento:confirmada},error:null,status:200};
  const client = {
    schema(nombre) {assert.equal(nombre,'crm');return {rpc:async(nombre,datos)=>{
      llamadas.push({nombre,datos});
      if(nombre===fallo) return error;
      if(nombre==='preparar_persona_lead_inversion_fn') return {data:{inversionista_id:'persona-ficticia'},error:null};
      if(nombre==='preparar_inversion_fn') return {data:{estado:confirmada?'confirmada':'preparada',revision_datos:0},error:null};
      assert.equal(nombre,'confirmar_inversion_revisada_fn');return resultado;
    }};},
    storage:{from(bucket){assert.equal(bucket,'f4-comprobantes');return {upload:async(ruta,cuerpo,opciones)=>{
      llamadas.push({nombre:'upload',ruta,opciones});assert.ok(Buffer.isBuffer(cuerpo));
      return fallo==='upload'?error:{data:{path:ruta},error:null};
    }};}},
  };
  return {client,llamadas,error,resultado};
}
test('la clave conserva replay de la operación, sin esconder cambios de payload',()=>{
  const id = claveConversion(args.p_lead_id,args.p_numero_transaccion);
  assert.match(id,/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-a[a-f0-9]{3}-[a-f0-9]{12}$/);
  assert.equal(id,claveConversion(args.p_lead_id,args.p_numero_transaccion));
  assert.notEqual(id,claveConversion(args.p_lead_id,'OTRA'));
});
for(const [fallo,n] of [['preparar_persona_lead_inversion_fn',1],['preparar_inversion_fn',2],['upload',3],['confirmar_inversion_revisada_fn',4]]) {
  test(`propaga ${fallo} sin reinterpretar el rechazo ni ejecutar pasos posteriores`,async()=>{
    const a=actor({fallo});assert.equal(await convertirCoopVigente(a.client,args),a.error);
    assert.equal(a.llamadas.length,n);
  });
}
test('confirmación nueva pasa por comprobante privado sin sobrescribir y devuelve el servidor',async()=>{
  const a=actor();assert.equal(await convertirCoopVigente(a.client,args),a.resultado);
  assert.deepEqual(a.llamadas.map(x=>x.nombre),[
    'preparar_persona_lead_inversion_fn','preparar_inversion_fn','upload','confirmar_inversion_revisada_fn']);
  assert.deepEqual(a.llamadas[2].opciones,{contentType:'image/png',upsert:false});
  assert.equal(a.llamadas[3].datos.p_revision_datos_esperada,0);
});
test('el replay confirmado no sobrescribe Storage y consulta de nuevo la confirmación real',async()=>{
  const a=actor({confirmada:true});assert.equal(await convertirCoopVigente(a.client,args),a.resultado);
  assert.equal(a.llamadas.length,3);
  assert.equal(a.llamadas.at(-1).nombre,'confirmar_inversion_revisada_fn');
});
test('el payload cambiado llega a la misma clave: sólo el servidor decide su conflicto',async()=>{
  const a=actor();await convertirCoopVigente(a.client,args);
  const b=actor();await convertirCoopVigente(b.client,{...args,p_monto:2000});
  assert.equal(a.llamadas[1].datos.p_clave,b.llamadas[1].datos.p_clave);
  assert.equal(b.llamadas[1].datos.p_datos.monto,2000);
});
