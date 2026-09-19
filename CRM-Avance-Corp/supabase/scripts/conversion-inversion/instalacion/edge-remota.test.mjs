// Frontera de la Edge realmente desplegada; no reclama ni envía correos.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {apiUrl,inicio,como} from './banco-remoto.mjs';

test('Edge remota: CORS, método, tamaño y autorización antes del servicio',async()=>{
  const url=apiUrl+'/functions/v1/crm-inversion-bienvenida';
  async function llamada(method,body,token){
    return fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(30_000),
      headers:{apikey:inicio.ANON_KEY,Origin:'https://crm.miavance.com',
        'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},
      ...(body===undefined?{}:{body:JSON.stringify(body)})});
  }
  const options=await llamada('OPTIONS');
  assert.equal(options.status,204);
  assert.equal(options.headers.get('Access-Control-Allow-Origin'),'https://crm.miavance.com');
  assert.equal((await llamada('GET')).status,405);
  assert.equal((await llamada('POST',{solicitud_id:randomUUID()})).status,401);
  assert.equal((await llamada('POST',{},inicio.ANON_KEY)).status,400);
  assert.equal((await llamada('POST',{dato:'x'.repeat(300)},inicio.ANON_KEY)).status,413);
  assert.equal((await llamada('POST',{solicitud_id:randomUUID()},inicio.ANON_KEY)).status,401);
  assert.equal((await llamada('POST',{solicitud_id:randomUUID()},await como('cliente'))).status,403);
  assert.equal((await llamada('POST',{solicitud_id:randomUUID()},inicio.SERVICE_ROLE_KEY)).status,403);
});
