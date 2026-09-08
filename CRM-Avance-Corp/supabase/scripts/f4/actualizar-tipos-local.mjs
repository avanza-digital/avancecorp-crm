// Genera antes/después con el mismo postgres-meta e integra exclusivamente F4.
// El dump previo no contiene RPC de otras tareas ya tipados en esta rama.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,openSync,closeSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {entorno,banco,leer} from './banco-local.mjs';
assert.equal(entorno,'avancecorp-f4-reconstruccion');
const previo=leer('respaldo-pre-f4.json').nombre;
assert.match(previo,/^f4_pre_fcuatro_[a-f0-9]{12}$/);
const id=randomUUID();
function generar(db){const p=`${banco}/tipos-${db}-${id}.ts`,fd=openSync(p,'wx',0o600);
 try {const r=spawnSync('docker',['run','--rm','--network','avancecorp-f4-reconstruccion-red',
 '-e','PG_META_DB_HOST=db','-e',`PG_META_DB_NAME=${db}`,'-e','PG_META_GENERATE_TYPES=typescript',
 '-e','PG_META_GENERATE_TYPES_INCLUDED_SCHEMAS=public,crm','-e','PG_META_GENERATE_TYPES_DETECT_ONE_TO_ONE_RELATIONSHIPS=true',
 'public.ecr.aws/supabase/postgres-meta:v0.99.0'],{stdio:['ignore',fd,'pipe'],encoding:'utf8'});
 assert.equal(r.status,0,r.stderr);}finally{closeSync(fd);}return readFileSync(p,'utf8');}
function nodos(src){const out=new Map();
 for(const schema of ['crm','public']){
  const a=src.indexOf(`  ${schema}: {\n`);assert(a>=0);
  const fin=/^  }\n/m.exec(src.slice(a));assert(fin);const b=a+fin.index+fin[0].length,body=src.slice(a,b);
  for(const sec of ['Tables','Views','Functions','Enums','CompositeTypes']){
   const m=new RegExp(`^    ${sec}:[^\\n]*\\n`,'m').exec(body);if(!m)continue;
   const start=a+m.index+m[0].length,n=/^    [A-Z][a-zA-Z]+:/m.exec(src.slice(start,b));
   let text=src.slice(start,n?start+n.index:b);const cierre=/^    }\n/m.exec(text);if(cierre)text=text.slice(0,cierre.index);
   const miembros=[...text.matchAll(/^      ([a-zA-Z_][a-zA-Z_0-9]*):/gm)];
   for(const [i,x] of miembros.entries()){const e=miembros[i+1]?.index??text.length;
    out.set(`${schema}.${sec}.${x[1]}`,{s:start+x.index,e:start+e,text:text.slice(x.index,e)});}
  }
 }return out;
}
const antes=generar(previo),despues=generar('postgres');
const path=new URL('../../../app/src/lib/database.types.ts',import.meta.url);
const original=readFileSync(path,'utf8'),b=nodos(antes),a=nodos(despues),c=nodos(original),ediciones=[],cambios=[];
for(const key of [...new Set([...b.keys(),...a.keys()])].sort()){
 const old=b.get(key)?.text??'',nuevo=a.get(key)?.text??'';if(old===nuevo)continue;
 assert(nuevo,`F4 no retira nodos: ${key}`);cambios.push(key);
 if(c.has(key)){const actual=c.get(key);assert(actual.text===old||actual.text===nuevo,`Conflicto con otra tarea: ${key}`);ediciones.push({...actual,text:nuevo});}
 else {const pref=key.slice(0,key.lastIndexOf('.')+1),vecinos=[...c].filter(([k])=>k.startsWith(pref));assert(vecinos.length);
  const siguiente=vecinos.find(([k])=>k>key);const s=siguiente?siguiente[1].s:vecinos.at(-1)[1].e;ediciones.push({s,e:s,text:nuevo,key});}
}
assert.equal(cambios.length,17,'El cambio de tipos debe corresponder al schema F4 revisado');
// Insertar primero el nombre mayor cuando varios nodos comparten posición.
ediciones.sort((a,b)=>b.s-a.s||(b.key??'').localeCompare(a.key??''));
let integrado=original;for(const x of ediciones)integrado=integrado.slice(0,x.s)+x.text+integrado.slice(x.e);
for(const key of cambios)assert.equal(nodos(integrado).get(key)?.text,a.get(key).text);
writeFileSync(path,integrado);
const hash=x=>createHash('sha256').update(x).digest('hex');
writeFileSync(new URL(`../evidencia-f4/tipos-${id}.json`,import.meta.url),JSON.stringify({entorno,terminadoEn:new Date().toISOString(),
 generador:'postgres-meta v0.99.0, imagen del CLI Supabase 2.117.0',antes:hash(antes),despues:hash(despues),integrado:hash(integrado),nodos:cambios,
 limite:'Delta exacto entre dos introspecciones locales; preserva tipos de otras migraciones de la rama ausentes del dump previo.'},null,2)+'\n',{flag:'wx'});
console.log(`Tipos F4: ${cambios.length} nodos cotejados; otros contratos TypeScript conservados.`);
