import { entorno } from './banco-local.mjs';
// Solo ensaya denegaciones sobre un UUID inexistente: nunca cambia un contrato.
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { sql, literal as q, http, leer, sesion } from './banco-local.mjs';
for(const rol of ['anon','authenticated','service_role']) assert.equal(sql(
 `select has_function_privilege(${q(rol)},'public._sync_contrato_titulares(uuid,jsonb)','EXECUTE')`),'f');
const f=leer('fixtures.json'),token=await sesion(f.usuarios.gerencia,f.password),pruebas=[];
const id=randomUUID();
assert.equal(sql(`select count(*) from public.contratos where id=${q(id)}`),'0');
for(const [rol,opciones] of [['anon',{}],['authenticated',{token}],['service_role',{admin:true}]]){
 const r=await http('/rest/v1/rpc/_sync_contrato_titulares',{
  ...opciones,body:{p_contrato_id:id,p_titulares:[]},headers:{'Content-Profile':'public','Accept-Profile':'public'}});
 assert.equal(r.ok,false);assert([401,403,404].includes(r.status));
 assert(['42501','PGRST202'].includes(r.data?.code),JSON.stringify(r.data));
 pruebas.push({rol,status:r.status,codigo:r.data.code});
}
writeFileSync(new URL(`../evidencia-f4/cotitular-api-${randomUUID()}.json`,import.meta.url),JSON.stringify({
 entorno,terminadoEn:new Date().toISOString(),pruebas,contratoInexistente:true,
 sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
 produccionModificada:false,limite:'Denegación HTTP de tres roles en API local; el login de la cuenta sintética puede actualizar datos de sesión Auth.',
},null,2)+'\n',{flag:'wx'});
console.log('PASS: API local deniega el auxiliar de cotitulares a los tres roles.');
