import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const dir='/private/tmp/avancecorp-ficha-optim-20260915/';
const cfg=JSON.parse(readFileSync(dir+'rama-privada.json','utf8'));
const url='https://tufxjboalbtekbszckcf.supabase.co';assert.equal(cfg.SUPABASE_URL,url);
const grupo=JSON.parse(readFileSync(dir+'http-miembros.json','utf8'));
const sesiones=JSON.parse(readFileSync(dir+'http-sesiones.json','utf8'));
const antes=JSON.parse(readFileSync(dir+'http-general-antes.json','utf8')).casos;
const despues=JSON.parse(readFileSync(dir+'http-general-despues.json','utf8')).casos;
const roles=[grupo.gerencia,grupo.analistas[0],grupo.supervisor];
const keys=Object.keys(antes).filter(k=>k.startsWith('ficha/'+roles[1].id+'/'));
const persona=keys.map(k=>k.split('/')[2]).find(id=>roles.every(a=>antes['ficha/'+a.id+'/'+id]?.body?.persona));
assert.ok(persona,'No hay persona común visible en los tres roles');
const resultados=[];
for(const cantidad of [1,2,3]){
 const muestras=await Promise.all(roles.slice(0,cantidad).map(async a=>{
  const inicio=Date.now();
  const response=await fetch(url+'/rest/v1/rpc/inversionista_ficha_fn',{method:'POST',headers:{apikey:cfg.SUPABASE_ANON_KEY,Authorization:'Bearer '+sesiones[a.id],'Content-Type':'application/json','Content-Profile':'crm'},body:JSON.stringify({p_inversionista:persona}),signal:AbortSignal.timeout(20000)});
  const body=await response.json();const fin=Date.now();
  assert.equal(response.status,200);assert.deepEqual(body,antes['ficha/'+a.id+'/'+persona].body);assert.deepEqual(body,despues['ficha/'+a.id+'/'+persona].body);
  return {rol:a.rol_crm,inicio,fin,ms:fin-inicio,status:response.status,huella:createHash('sha256').update(JSON.stringify(body)).digest('hex')};
 }));
 resultados.push({cantidad,solapamiento_solicitudes_ms:Math.max(0,Math.min(...muestras.map(m=>m.fin))-Math.max(...muestras.map(m=>m.inicio))),muestras});
}
writeFileSync(dir+'http-concurrencia.json',JSON.stringify({resultado:'PASS',banco:'tufxjboalbtekbszckcf',alcance:'6 solicitudes HTTP en oleadas de 1/2/3; intervalos cliente superpuestos. No acredita solapamiento SQL interno.',resultados},null,2));
console.log('PASS: concurrencia HTTP 1/2/3, 6 respuestas completas iguales');
