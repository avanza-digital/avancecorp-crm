// Frontera HTTP y binaria: dobles controlados para errores que no deben
// construirse en datos reales. flujo/pdf.test usan Auth/RLS/Storage reales.
import test from 'node:test';
import assert from 'node:assert/strict';
import {crearHandlerDocumentoInversion} from '../../../../_supabase_functions/functions/crm-inversion-documento/handler.mjs';
const id='11111111-1111-4111-8111-111111111111';
const entrada={inversionista_id:id,fuente_id:id,documento_id:id};
const config={supabaseUrl:'https://banco.example',anonKey:'anon-sintetico',serviceKey:'eyJficticio.payload.firma'};
const json=(x,status=200)=>new Response(JSON.stringify(x),{status,headers:{'Content-Type':'application/json'}});
const req=(body=entrada,headers={})=>new Request('https://banco.example/functions/v1/crm-inversion-documento',{
  method:'POST',headers:{Authorization:'Bearer sesion-sintetica',...headers},body:typeof body==='string'?body:JSON.stringify(body)});
function banco(descriptor={bucket:'f4-comprobantes',ruta:`${id}/archivo.png`,nombre:'Comprobante'},bytes=new Uint8Array([1,2,3])) {
  const llamadas=[];
  return {llamadas,handler:crearHandlerDocumentoInversion({...config,fetchImpl:async(url,init)=>{
    llamadas.push({url,init});
    if(url.endsWith('/auth/v1/user')) return json({id});
    if(url.includes('/rpc/')) return json(descriptor);
    return new Response(bytes);
  }})};
}
test('G5 documento: JSON/UUID/campos/origen/tamaño inválidos no llegan a Auth ni Storage',async()=>{
  const b=banco();
  for(const input of ['{',[],{...entrada,documento_id:'inválido'},{...entrada,documento_id:[id]},
    {...entrada,fuente_id:17},{...entrada,ruta:'archivo-ajeno'},'x'.repeat(1025)]) {
    assert.ok([400,413].includes((await b.handler(req(input))).status));
  }
  assert.equal((await b.handler(req(entrada,{Origin:'https://ajeno.example'}))).status,403);
  assert.equal((await b.handler(req(entrada,{Authorization:''}))).status,401);
  assert.equal(b.llamadas.length,0);
});
test('G5 documento: bucket o ruta inseguros nunca usan la credencial de servicio',async()=>{
  for(const d of [{bucket:'ajeno',ruta:'x'},...['/absoluta','../secreto','a/../b','a//b','a\\b','a\u0000b'].map(ruta=>({bucket:'documentos',ruta}))]) {
    const b=banco(d);assert.equal((await b.handler(req())).status,409);
    assert.equal(b.llamadas.some(x=>x.url.includes('/storage/')),false);
  }
});
test('G5 documento: integridad, archivo vacío y límite de streaming fallan sin devolver bytes',async()=>{
  for(const [d,bytes,status] of [
    [{sha256:'0'.repeat(64)},new Uint8Array([1]),409],
    [{bytes:3},new Uint8Array([1]),409],
    [{},new Uint8Array(),409],
    [{},new Uint8Array(20*1024*1024+1),413],
  ]) {
    const b=banco({bucket:'documentos',ruta:'prueba.pdf',...d},bytes);
    const r=await b.handler(req());assert.equal(r.status,status);assert.equal(r.headers.get('Content-Type'),'application/json');
    assert.equal(b.llamadas.filter(x=>x.url.includes('/rpc/')).length,1);
  }
});
test('G5 documento: sesión vigente y descriptor se revalidan; solo Storage usa service role',async()=>{
  const b=banco();const r=await b.handler(req());assert.equal(r.status,200);
  assert.equal(r.headers.get('Cache-Control'),'private, no-store');assert.equal(b.llamadas.length,4);
  for(const x of b.llamadas) assert.equal(x.init.headers.Authorization,x.url.includes('/storage/')?`Bearer ${config.serviceKey}`:'Bearer sesion-sintetica');
  assert.equal(await r.text(),'\u0001\u0002\u0003');
});
test('G5 documento: Storage admite clave opaca y JWT sin elevar Auth ni las RPC',async()=>{
  for(const serviceKey of ['sb_secret_ficticia_no_es_una_credencial','eyJ.jwt_ficticio.firma_ficticia','otra_clave_opaca_ficticia']) {
    const llamadas=[];
    const handler=crearHandlerDocumentoInversion({...config,serviceKey,fetchImpl:async(url,init)=>{
      llamadas.push(url);
      const headers=new Headers(init.headers);
      if(url.includes('/storage/')) {
        // La pasarela resuelve la clave opaca desde apikey; una clave pública
        // aquí convierte la descarga privada en un falso «bucket ausente».
        assert.equal(headers.get('apikey'),serviceKey);
        assert.equal(headers.get('authorization'),serviceKey.startsWith('eyJ.')?`Bearer ${serviceKey}`:null);
        return new Response(new Uint8Array([1,2,3]));
      }
      assert.equal(headers.get('apikey'),config.anonKey);
      assert.equal(headers.get('authorization'),'Bearer sesion-sintetica');
      return json(url.endsWith('/auth/v1/user')?{id}:{bucket:'documentos',ruta:'ficticio.png'});
    }});
    const r=await handler(req());assert.equal(r.status,200,await r.clone().text());
    assert.equal(llamadas.length,4);assert.deepEqual(new Uint8Array(await r.arrayBuffer()),new Uint8Array([1,2,3]));
  }
});
test('G5 documento: cambio de descriptor con acceso válido descarta los bytes',async()=>{
  let consultas=0;
  const handler=crearHandlerDocumentoInversion({...config,fetchImpl:async url=>{
    if(url.endsWith('/auth/v1/user'))return json({id});
    if(url.includes('/rpc/'))return json({bucket:'documentos',ruta:++consultas===1?'anterior.pdf':'actual.pdf'});
    return new Response(new Uint8Array([1,2,3]));
  }});
  const r=await handler(req());assert.equal(r.status,409);assert.equal(consultas,2);
  assert.equal((await r.json()).error,'El documento cambió. Vuelve a consultarlo.');
});
test('G5 documento: fallo Storage registra solo estado y bucket, sin ruta ni credenciales',async t=>{
  const aviso=t.mock.method(console,'warn',()=>{});
  const handler=crearHandlerDocumentoInversion({...config,fetchImpl:async url=>{
    if(url.endsWith('/auth/v1/user'))return json({id});
    if(url.includes('/rpc/'))return json({bucket:'documentos',ruta:'persona/documento-privado.pdf'});
    return json({message:'mensaje interno'},503);
  }});
  const r=await handler(req());assert.equal(r.status,404);
  assert.deepEqual(aviso.mock.calls.map(x=>x.arguments),[['f5_documento_storage_error',{status:503,bucket:'documentos'}]]);
  assert.equal((await r.json()).error,'El archivo no está disponible.');
});
