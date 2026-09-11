import { strict as assert } from 'node:assert';
import { crearHandler, endpointValido, resultadoHttp, type Dependencias } from './handler.ts';
const id='d7100000-0000-4000-8000-000000000001';
const reserva='d7100000-0000-4000-8000-000000000002';
const suscripcion={endpoint:'https://fcm.googleapis.com/fcm/send/sintetico',p256dh:'B'.repeat(87),auth:'a'.repeat(22),solicitud_id:id,vence_en:'2030-01-02T00:00:00Z'};
function banco(cambios: Partial<Dependencias>={}) {
  const llamadas: unknown[][]=[];
  const deps: Dependencias={
    configurado:true,clavePublica:'B'.repeat(87),ahora:()=>Date.parse('2030-01-01T00:00:00Z'),
    verificarCron:async(firma,instante)=>firma==='a'.repeat(64)&&instante==='1893456000',
    estadoUsuario:async token=>{ if(token!=='jwt-sintetico') throw {code:'42501'}; return {configurado:true,dispositivo:{id,activo:true}}; },
    pruebaUsuario:async()=>suscripcion,
    tomar:async()=>{llamadas.push(['tomar']);return [{id,reserva}];},
    materializar:async()=>suscripcion,
    confirmar:async(...args)=>{llamadas.push(['confirmar',...args]);return true;},
    enviar:async(...args)=>{llamadas.push(['enviar',...args]);return 201;},...cambios,
  };
  const llamar=(body:unknown,headers:HeadersInit={})=>crearHandler(deps)(new Request('https://ejemplo.invalid',{method:'POST',headers,body:JSON.stringify(body)}));
  return {llamar,llamadas,deps};
}
const cron={'x-cron-firma':'a'.repeat(64),'x-cron-instante':'1893456000'};
Deno.test('cron: faltante, falso o JWT de usuario no permiten reclamar la cola',async()=>{
  for(const headers of [{},{'x-cron-secret':'falso'},{...cron,'x-cron-firma':'b'.repeat(64)},{...cron,'x-cron-instante':'0'},{authorization:'Bearer jwt-sintetico'}] as HeadersInit[]) {
    const b=banco();assert.equal((await b.llamar({accion:'procesar'},headers)).status,401);assert.equal(b.llamadas.length,0);
  }
});
Deno.test('configuración exige la sesión y el rol comprobados por la RPC',async()=>{
  for(const token of ['', 'incorrecto']) {const b=banco();assert.ok([401,403].includes((await b.llamar({accion:'configuracion'},{authorization:`Bearer ${token}`})).status));}
  const b=banco();const r=await b.llamar({accion:'configuracion'},{authorization:'Bearer jwt-sintetico'});assert.equal(r.status,200);assert.equal((await r.json()).configurado,true);
});
Deno.test('sin VAPID no reclama ni aparenta estar configurado',async()=>{
  const b=banco({configurado:false});assert.equal((await b.llamar({accion:'procesar'},cron)).status,503);assert.equal(b.llamadas.length,0);
  const r=await b.llamar({accion:'configuracion'},{authorization:'Bearer jwt-sintetico'});assert.equal((await r.json()).configurado,false);
});
Deno.test('envía contenido sin PII, URL o dinero y confirma usando la reserva exacta',async()=>{
  const b=banco();assert.equal((await b.llamar({accion:'procesar'},cron)).status,200);
  const envio=b.llamadas.find(x=>x[0]==='enviar')!;assert.deepEqual(Object.keys(envio[2] as object).sort(),['body','solicitudId','tag','title']);
  assert.equal(envio[3],86400);assert.equal(envio[4],id.replaceAll('-',''));
  assert.deepEqual(b.llamadas.at(-1),['confirmar',id,reserva,'enviado',201]);
});
Deno.test('membresía revocada o solicitud resuelta entre reclamar y enviar cancela el aviso',async()=>{
  const b=banco({materializar:async()=>null});await b.llamar({accion:'procesar'},cron);
  assert.equal(b.llamadas.some(x=>x[0]==='enviar'),false);assert.deepEqual(b.llamadas.at(-1),['confirmar',id,reserva,'cancelado',null]);
});
Deno.test('suscripción caducada se desactiva; errores temporales reintentan; rechazos permanentes terminan',async()=>{
  for(const [codigo,resultado] of [[404,'invalido'],[410,'invalido'],[429,'reintentar'],[503,'reintentar'],[403,'fallido']] as const) {
    const b=banco({enviar:async()=>codigo});await b.llamar({accion:'procesar'},cron);assert.deepEqual(b.llamadas.at(-1),['confirmar',id,reserva,resultado,codigo]);
  }
  const b=banco({enviar:async()=>{throw new Error('endpoint y claves que no deben filtrarse');}});const r=await b.llamar({accion:'procesar'},cron);
  assert.deepEqual(b.llamadas.at(-1),['confirmar',id,reserva,'reintentar',null]);assert.ok(!(await r.text()).includes('claves'));
});
Deno.test('SSRF: rechaza IP privada, puerto, credenciales, dominios falsos y redirección en URL',()=>{
  for(const url of ['http://fcm.googleapis.com/a','https://127.0.0.1/a','https://fcm.googleapis.com.evil.invalid/a','https://fcm.googleapis.com@evil.invalid/a','https://web.push.apple.com:123/a','https://fcm.googleapis.com/a#b','https://fcm.googleapis.com\\@evil.invalid/a']) assert.equal(endpointValido(url),false,url);
  for(const url of ['https://fcm.googleapis.com/fcm/send/abc','https://web.push.apple.com/Q123','https://eu.push.apple.com/Q123','https://updates.push.services.mozilla.com/wpush/v2/abc']) assert.equal(endpointValido(url),true,url);
  assert.equal(endpointValido('https://web.push.apple.com.evil.invalid/Q123'),false);
  assert.equal(resultadoHttp(201),'enviado');
});
Deno.test('una URL alterada en base de datos tampoco sale a la red',async()=>{
  const b=banco({materializar:async()=>({...suscripcion,endpoint:'https://127.0.0.1/secret'})});await b.llamar({accion:'procesar'},cron);
  assert.equal(b.llamadas.some(x=>x[0]==='enviar'),false);assert.deepEqual(b.llamadas.at(-1),['confirmar',id,reserva,'fallido',null]);
});
Deno.test('prueba requiere dispositivo propio, configuración y límite por servidor',async()=>{
  const b=banco({pruebaUsuario:async()=>{throw {code:'P0429'};}});assert.equal((await b.llamar({accion:'prueba',dispositivoId:id},{authorization:'Bearer jwt-sintetico'})).status,429);
  assert.equal((await banco().llamar({accion:'prueba',dispositivoId:'no-uuid'},{authorization:'Bearer jwt-sintetico'})).status,400);
});
Deno.test('origen ajeno se rechaza; local solo está permitido con configuración explícita',async()=>{
  for(const origin of ['https://evil.invalid','http://localhost:5173'])assert.equal((await banco().llamar({accion:'procesar'},{...cron,origin})).status,403);
  assert.equal((await banco({permitirLocal:true}).llamar({accion:'procesar'},{...cron,origin:'http://127.0.0.1:5173'})).status,200);
});
Deno.test('solicitud vencida y fallo de confirmación conservan semántica honesta',async()=>{
  const b=banco({materializar:async()=>({...suscripcion,vence_en:'2029-01-01T00:00:00Z'})});await b.llamar({accion:'procesar'},cron);assert.equal(b.llamadas.some(x=>x[0]==='enviar'),false);
  assert.equal((await banco({confirmar:async()=>{throw new Error('sin base');}}).llamar({accion:'procesar'},cron)).status,503);
});
Deno.test('el fallo de una confirmación no abandona los otros seis envíos del lote',async()=>{
  const procesados: string[]=[];
  const lote=Array.from({length:7},(_,i)=>({id:String(i),reserva}));
  const b=banco({tomar:async()=>lote, confirmar:async(id)=>{procesados.push(id);if(id==='1')throw new Error('sin base');return true;}});
  const r=await b.llamar({accion:'procesar'},cron);
  assert.equal(r.status,503);
  assert.deepEqual(procesados.sort(),lote.map(v=>v.id));
  assert.deepEqual(await r.json(),{procesados:7,enviados:7,sinConfirmar:1});
});
Deno.test('limita el cuerpo antes de cargarlo completamente en memoria',async()=>{
  const b=banco(); const r=await b.llamar({accion:'procesar',relleno:'a'.repeat(5000)},cron);
  assert.equal(r.status,413);assert.equal(b.llamadas.length,0);
});
