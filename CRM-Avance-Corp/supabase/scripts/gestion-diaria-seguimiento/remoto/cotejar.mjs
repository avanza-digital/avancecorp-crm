import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {isDeepStrictEqual} from 'node:util';
import {carpeta,objeto} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
const esperado=JSON.parse(readFileSync('/private/tmp/gd-f4-estructura-productiva-20260922.json','utf8')).rows[0].estructura;
const actual=objeto(readFileSync(new URL('./catalogo-estructura.sql',import.meta.url),'utf8'));
writeFileSync(`${carpeta}/estructura-banco.json`,JSON.stringify(actual),{mode:0o600});
const a=new Map(actual.tablas.map(t=>[t.nombre,t]));
const e=new Map(esperado.tablas.map(t=>[t.nombre,t]));
const diferencias={faltan:[...e.keys()].filter(k=>!a.has(k)),sobran:[...a.keys()].filter(k=>!e.has(k)),
 tablas:[...e].filter(([k,v])=>a.has(k)&&!isDeepStrictEqual(v,a.get(k))).map(([k,v])=>({tabla:k,
   campos:Object.keys(v).filter(x=>!isDeepStrictEqual(v[x],a.get(k)[x]))})),
 otras:Object.keys(esperado).filter(k=>k!=='tablas'&&!isDeepStrictEqual(esperado[k],actual[k]))};
writeFileSync(`${carpeta}/estructura-diferencias.json`,JSON.stringify(diferencias,null,2)+'\n',{mode:0o600});
// pg_dump/restore normaliza la asociación de AND de estos tres CHECK; sus
// predicados, nombres y validación permanecen iguales. No tolerar otra deriva.
const conocidos=['crm.alertas_reconocimientos','crm.empresas','crm.producto_condiciones'];
for(const d of diferencias.tablas){
 assert.ok(conocidos.includes(d.tabla));assert.deepEqual(d.campos,['restricciones']);
 const normalizar=rs=>rs.map(([nombre,texto,validada])=>[nombre,texto.replaceAll('(','').replaceAll(')',''),validada]);
 assert.deepEqual(normalizar(e.get(d.tabla).restricciones),normalizar(a.get(d.tabla).restricciones));
}
assert.deepEqual(diferencias.faltan,[]);assert.deepEqual(diferencias.sobran,[]);assert.deepEqual(diferencias.otras,[]);
writeFileSync(`${carpeta}/estructura-paridad.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),
 cantidad:a.size,normalizacion_de_parentesis:diferencias.tablas},null,2)+'\n',{mode:0o600});
console.log(JSON.stringify({estado:'PASS',cantidad:a.size,...diferencias},null,2));
