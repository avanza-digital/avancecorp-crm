import assert from 'node:assert/strict';
import{readFileSync}from'node:fs';
import{isDeepStrictEqual as eq}from'node:util';
import{carpeta,sql,objeto}from'./banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
const e=JSON.parse(readFileSync(`${carpeta}/produccion-catalogo.json`)).rows[0].estructura;
const a=objeto(readFileSync(new URL('./catalogo.sql',import.meta.url),'utf8'));
const cambios=[];
const acl=x=>x===null?null:x.slice(1,-1).split(',').sort();
for(const f of e.funciones){const b=a.funciones.find(t=>t.firma===f.firma);assert.ok(b);
 if(eq(acl(f.acl),acl(b.acl)))continue;
 assert.ok(f.firma.startsWith('public.'));assert.ok(f.acl&&b.acl);
 for(const v of acl(f.acl))assert.ok(acl(b.acl).includes(v));
 for(const v of acl(b.acl).filter(v=>!acl(f.acl).includes(v))){
  const m=/^(anon|authenticated|service_role)=X\/postgres$/.exec(v);assert.ok(m);
  cambios.push(`revoke execute on function ${f.firma} from ${m[1]};`);
 }
}
for(const t of e.tablas){const b=a.tablas.find(v=>v.nombre===t.nombre);assert.ok(b);
 for(const v of t.acl??[])assert.ok((b.acl??[]).some(w=>eq(w,v)));
 for(const v of (b.acl??[]).filter(v=>!(t.acl??[]).some(w=>eq(w,v)))){
  assert.equal(t.nombre,'public.audit_log');assert.equal(v[2],false);
  assert.ok(['anon','authenticated','service_role'].includes(v[0]));
  assert.ok(['DELETE','UPDATE','TRIGGER','TRUNCATE','REFERENCES'].includes(v[1]));
  cambios.push(`revoke ${v[1]} on table ${t.nombre} from ${v[0]};`);
 }
}
if(cambios.length)sql(`begin; ${cambios.join('\n')} commit;`);
console.log(`PASS: ${cambios.length} permisos heredados de la restauración retirados en banco-f7.`);
