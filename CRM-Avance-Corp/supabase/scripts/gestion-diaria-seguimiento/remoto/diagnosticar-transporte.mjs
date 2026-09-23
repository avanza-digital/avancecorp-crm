import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {carpeta,http} from './banco.mjs';
import {httpIndependiente} from './http-independiente.mjs';
import {USER_BY_KEY} from '../../fixtures.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
const {password}=JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`));
const sesiones=[];
for(let i=0;i<2;i++){
 const r=await http('/auth/v1/token?grant_type=password',{body:{email:USER_BY_KEY.gerencia.email,password}});
 assert.equal(r.status,200);sesiones.push(r.data.access_token);
}
const inicio=Date.now();
const resultados=await Promise.all(sesiones.map(async token=>{
 const r=await httpIndependiente('/rest/v1/rpc/configuracion_gestion_diaria_fn',{token,body:{}});
 assert.equal(r.status,200);return{ms:Date.now()-inicio,status:r.status,version:r.data.expected_version};
}));
assert.equal(resultados[0].version,resultados[1].version);
writeFileSync(`${carpeta}/diagnostico-transporte.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),resultados},null,2),{mode:0o600});
console.log(JSON.stringify({estado:'PASS',resultados}));
