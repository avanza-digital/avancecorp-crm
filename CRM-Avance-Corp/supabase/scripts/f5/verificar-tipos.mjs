// Introspección F5 cerrada; comprueba los seis nodos nuevos sin sustituir
// tipos de otras migraciones presentes en Main y ausentes del banco sintético.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,openSync,closeSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {banco} from './banco-local.mjs';
const destino=`${banco}/tipos-f5-actual.ts`,fd=openSync(destino,'w',0o600);
try {
 const r=spawnSync('docker',['run','--rm','--network','avancecorp-f5-bank-red',
  '-e','PG_META_DB_HOST=db','-e','PG_META_DB_NAME=postgres','-e','PG_META_GENERATE_TYPES=typescript',
  '-e','PG_META_GENERATE_TYPES_INCLUDED_SCHEMAS=public,crm','-e','PG_META_GENERATE_TYPES_DETECT_ONE_TO_ONE_RELATIONSHIPS=true',
  'public.ecr.aws/supabase/postgres-meta:v0.99.0'],{stdio:['ignore',fd,'pipe'],encoding:'utf8'});
 assert.equal(r.status,0,r.stderr);
} finally {closeSync(fd);}
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

const nuevo=readFileSync(destino,'utf8'),actual=readFileSync(new URL('../../../app/src/lib/database.types.ts',import.meta.url),'utf8');
const a=nodos(nuevo),b=nodos(actual);
const nombres=['crm.Tables.cartera_lecturas',...['cartera_inversionistas_estado_fn','cartera_inversionistas_fn',
 'inversionista_ficha_fn','inversionista_cuentas_fn','inversionista_documento_fn'].map(n=>`crm.Functions.${n}`)];
for(const nombre of nombres) {assert(a.has(nombre));assert.equal(b.get(nombre)?.text,a.get(nombre)?.text,`Regenerar nodo F5: ${nombre}`);}
const hash=x=>createHash('sha256').update(x).digest('hex');
writeFileSync(`${banco}/evidencia-tipos.json`,JSON.stringify({estado:'PASS',generador:'postgres-meta v0.99.0',
 introspeccion:hash(nuevo),integrado:hash(actual),nodos:nombres},null,2)+'\n',{mode:0o600});
console.log('Tipos F5: seis nodos coinciden con la introspección actual; otros contratos conservados.');
