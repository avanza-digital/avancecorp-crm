// Frontera HTTP y binaria: dobles controlados para errores que no deben
// construirse en datos reales. flujo/pdf.test usan Auth/RLS/Storage reales.
import test from 'node:test';
import assert from 'node:assert/strict';
import {crearHandlerDocumentoInversion} from '../../../../_supabase_functions/functions/crm-inversion-documento/handler.mjs';
const id='11111111-1111-4111-8111-111111111111';
const entrada={inversionista_id:id,fuente_id:id,documento_id:id};
const config={supabaseUrl:'https://banco.example',anonKey:'anon-sintetico',serviceKey:'servicio-sintetico'};
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
  for(const input of ['{',[],{...entrada,documento_id:'inválido'},{...entrada,ruta:'archivo-ajeno'},'x'.repeat(1025)]) {
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
  for(const x of b.llamadas) assert.equal(x.init.headers.Authorization,x.url.includes('/storage/')?'Bearer servicio-sintetico':'Bearer sesion-sintetica');
  assert.equal(await r.text(),'\u0001\u0002\u0003');
});
