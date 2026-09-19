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

for (const serviceKey of ['sb_secret_SERVICIO_FICTICIO', 'cabecera.servicio.firma']) {
  test(`reclama y confirma bienvenida con ${serviceKey.startsWith('sb_secret_') ? 'secret key' : 'JWT legacy'}`, async () => {
    const pasos = [], clave = `bienvenida:${id}:v1`, token = 'token-ficticio';
    const h = crearHandlerBienvenida({ supabaseUrl: 'https://local.invalid',
      anonKey: 'sb_publishable_PUBLICA_FICTICIA', serviceKey, resendKey: 'proveedor-prueba',
      fetchImpl: async (url, opciones) => {
        const headers = new Headers(opciones.headers), body = JSON.parse(opciones.body);
        if (url.endsWith('/bienvenida_inversion_estado_fn')) {
          pasos.push('estado');
          assert.equal(headers.get('apikey'), 'sb_publishable_PUBLICA_FICTICIA');
          assert.equal(headers.get('Authorization'), 'Bearer prueba');
          return Response.json({ estado: 'pendiente' });
        }
        if (url === 'https://api.resend.com/emails') {
          pasos.push('proveedor');
          assert.equal(headers.get('Authorization'), 'Bearer proveedor-prueba');
          assert.equal(headers.get('apikey'), null);
          assert.equal(headers.get('Idempotency-Key'), clave);
          assert.deepEqual(body.to, ['persona@example.test']);
          return Response.json({ id: 'envio-ficticio' });
        }
        assert(url.endsWith('/bienvenida_inversion_entrega_fn'));
        assert.equal(headers.get('apikey'), serviceKey);
        assert.equal(headers.get('Authorization'), serviceKey.startsWith('sb_secret_') ? null : `Bearer ${serviceKey}`);
        assert.equal(headers.get('Content-Profile'), 'crm');
        pasos.push(body.p_paso);
        if (body.p_paso === 'reclamar') return Response.json({ estado: 'enviar', clave, token,
          nombre: 'Persona ficticia', correo: 'persona@example.test' });
        assert.equal(body.p_token, token); assert.equal(body.p_proveedor_id, 'envio-ficticio');
        return Response.json({ estado: 'enviada' });
      },
    });
    const r = await h(pedido());
    assert.equal(r.status, 200); assert.deepEqual(await r.json(), { estado: 'enviada' });
    assert.deepEqual(pasos, ['estado', 'reclamar', 'proveedor', 'confirmar']);
  });
}
