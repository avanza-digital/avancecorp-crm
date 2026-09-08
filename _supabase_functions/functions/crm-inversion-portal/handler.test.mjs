import test from 'node:test';
import assert from 'node:assert/strict';
import { crearHandlerAccesoInversion } from './handler.mjs';
const id='11111111-1111-4111-8111-111111111111';
const crear=(fetchImpl=()=>{throw new Error('No debe llamar al backend');})=>crearHandlerAccesoInversion({
  supabaseUrl:'https://banco.example.test',anonKey:'ANON_FICTICIA',serviceKey:'SERVICIO_FICTICIO',fetchImpl,
});
const request=(body=JSON.stringify({solicitud_id:id}),headers={})=>new Request('https://edge.example.test',{method:'POST',
  headers:{Authorization:'Bearer USUARIO_FICTICIO',...headers},body,...(body instanceof ReadableStream?{duplex:'half'}:{})});
test('CORS solo refleja los orígenes publicados y nunca usa wildcard',async()=>{
  for(const origin of ['https://crm.miavance.com','https://atacante.example.test','null']){
    const r=await crear()(new Request('https://edge.example.test',{method:'OPTIONS',headers:{Origin:origin}}));
    assert.equal(r.status,204);assert.equal(r.headers.get('Vary'),'Origin');
    assert.equal(r.headers.get('Access-Control-Allow-Origin'),'https://crm.miavance.com');
  }
});
test('Cuerpo transmitido sin longitud se corta antes de acumular más de 4096 bytes',async()=>{
  let cancelado=false;
  const body=new ReadableStream({pull(c){c.enqueue(new Uint8Array(3000));},cancel(){cancelado=true;}});
  const r=await crear()(request(body));assert.equal(r.status,400);assert.equal(cancelado,true);
  assert.equal((await r.json()).error,'Solicitud demasiado grande.');
});
test('Límite por bytes multibyte y UTF-8 inválido, sin llamadas privilegiadas',async()=>{
  for(const body of ['ñ'.repeat(2050),new Uint8Array([0xff,0xfe])])assert.equal((await crear()(request(body))).status,400);
});
test('Longitud declarada inválida o excesiva y JSON inválido se rechazan',async()=>{
  for(const length of ['5000','-1','hola'])assert.equal((await crear()(request('{}',{'Content-Length':length}))).status,400);
  assert.equal((await crear()(request('{'))).status,400);
});
test('Errores PostgreSQL no contractuales ocultan mensaje y detalles',async()=>{
  for(const code of ['23505','23514','55P03','P0001','40001','PGRST202']){
    let llamadas=0;
    const r=await crear(async()=>new Response(JSON.stringify(++llamadas===1?{id}:{code,message:'SECRETO tabla columna constraint',details:'FILA PRIVADA'}),{status:llamadas===1?200:400}))(request());
    const texto=await r.text();assert(!texto.includes('SECRETO'));assert(!texto.includes('PRIVADA'));assert(texto.includes(id));
    assert.equal(llamadas,2);assert(r.status>=400);
  }
});
test('Errores contractuales mantienen diagnóstico público y estado autorizado',async()=>{
  for(const [code,status] of [['42501',403],['P0409',409],['22023',400]]){
    let llamadas=0;
    const r=await crear(async()=>new Response(JSON.stringify(++llamadas===1?{id}:{code,message:'Diagnóstico contractual'}),{status:llamadas===1?200:400}))(request());
    assert.equal(r.status,status);assert.equal((await r.json()).error,'Diagnóstico contractual');
  }
});
test('Fallo de Auth externo no expone sus mensajes internos',async()=>{
  const r=await crear(async()=>new Response(JSON.stringify({message:'SECRETO Auth infraestructura'}),{status:500}))(request());
  assert(!(await r.text()).includes('SECRETO'));
});
test('Fallo recuperable conserva el token sin filtrar el mensaje interno',async()=>{
  const token='a'.repeat(48);let llamadas=0;
  const r=await crear(async()=>new Response(JSON.stringify(++llamadas===1?{id}:{code:'23505',message:'SECRETO'}),{status:llamadas===1?200:400}))(request(JSON.stringify({solicitud_id:id,token})));
  const j=await r.json();assert.equal(j.token,token);assert(!j.error.includes('SECRETO'));
});
