// Una conexión TLS/IPv4 distinta por solicitud, sin pool compartido de fetch.
import assert from 'node:assert/strict';
import {request} from 'node:https';
import {apiUrl,cfg} from './banco.mjs';
export function httpIndependiente(ruta,{token,body,method='POST'}={}){
 assert.ok(ruta.startsWith('/')&&!ruta.startsWith('//'));
 const datos=body===undefined?undefined:JSON.stringify(body);
 return new Promise((resolve,reject)=>{
  const r=request(new URL(ruta,apiUrl),{method,agent:false,family:4,timeout:15_000,
   headers:{apikey:cfg.SUPABASE_ANON_KEY,Authorization:`Bearer ${token??cfg.SUPABASE_ANON_KEY}`,
    'Content-Type':'application/json','Accept-Profile':'crm','Content-Profile':'crm',
    ...(datos?{'Content-Length':Buffer.byteLength(datos)}:{})}},res=>{
    let salida='';res.setEncoding('utf8');res.on('data',s=>salida+=s);
    res.on('error',reject);res.on('end',()=>{let data;try{data=JSON.parse(salida);}catch{data=salida;}
     resolve({status:res.statusCode,ok:res.statusCode>=200&&res.statusCode<300,data});});
   });
  r.on('error',reject);r.on('timeout',()=>r.destroy(new Error('Tiempo agotado en TLS independiente')));
  r.end(datos);
 });
}
