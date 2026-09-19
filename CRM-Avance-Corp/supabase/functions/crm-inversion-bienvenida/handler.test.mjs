import test from 'node:test';
import assert from 'node:assert/strict';
import {crearHandlerBienvenida,bienvenidaV1} from './handler.mjs';
const id='55555555-5555-4555-8555-555555555555';
const pedido=(body=JSON.stringify({solicitud_id:id}),headers={Authorization:'Bearer prueba'})=>
  new Request('https://local.invalid/bienvenida',{method:'POST',headers,body});
function banco(fetchImpl){return crearHandlerBienvenida({supabaseUrl:'https://local.invalid',anonKey:'prueba',serviceKey:'servicio-prueba',resendKey:'proveedor-prueba',fetchImpl});}
test('rechaza entradas inválidas antes de consultar datos o enviar correo',async()=>{
  let llamadas=0;const h=banco(async()=>{llamadas++;throw new Error('No debe consultar');});
  for(const [req,estado] of [[new Request('https://local.invalid'),405],[pedido('{}',{}),401],
    [pedido('no-json'),400],[pedido(JSON.stringify({solicitud_id:id,correo:'ajeno@example.test'})),400],
    [pedido(JSON.stringify({solicitud_id:'invalida'})),400],[pedido('x'.repeat(257)),413]])
    assert.equal((await h(req)).status,estado);
  assert.equal(llamadas,0);
});
test('una sesión sin ámbito no obtiene el servicio ni llama al proveedor',async()=>{
  const llamadas=[];const h=banco(async(url,opciones)=>{llamadas.push({url,opciones});return Response.json({message:'No autorizado'},{status:403});});
  assert.equal((await h(pedido())).status,403);assert.equal(llamadas.length,1);
  assert.match(llamadas[0].url,/bienvenida_inversion_estado_fn$/);
  assert.equal(llamadas[0].opciones.headers.Authorization,'Bearer prueba');
});
test('un resultado terminal no vuelve a reclamar ni reenviar',async()=>{
  for(const estado of ['enviada','no_corresponde','verificar_entrega']){
    let llamadas=0;const h=banco(async()=>{llamadas++;return Response.json({estado});});
    assert.deepEqual(await (await h(pedido())).json(),{estado});assert.equal(llamadas,1);
  }
});
test('la plantilla trata el nombre como texto, sin incluir el documento',()=>{
  const cuerpo=bienvenidaV1('<script>contenido</script>','persona@example.test');
  assert(!cuerpo.html.includes('<script>'));assert(cuerpo.html.includes('&lt;script&gt;'));
  assert.deepEqual(cuerpo.to,['persona@example.test']);
});
