// MCP guardó cada archivo completo como una sentencia. Coteja SHA/bytes antes
// de cambiar exclusivamente sus cuatro versiones administrativas en la rama.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {carpeta,objeto,sql} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.equal(existsSync(`${carpeta}/ledger-candidato.json`),false);
const instalacion=JSON.parse(readFileSync(`${carpeta}/instalacion-candidatos.json`,'utf8'));
const base=JSON.parse(readFileSync('/private/tmp/gd-f4-ledger-productivo-completo-20260922.json','utf8')).rows;
const consulta='select jsonb_agg(to_jsonb(m) order by version) from supabase_migrations.schema_migrations m';
const antes=objeto(consulta);assert.equal(antes.length,base.length+4);
const candidatos=instalacion.archivos.map(f=>{
 const version=f.nombre.slice(0,14),nombre=f.nombre.slice(15,-4);
 const filas=antes.filter(r=>r.name===nombre);assert.equal(filas.length,1);
 const row=filas[0];assert.match(row.version,/^\d{14}$/);
 assert.equal(row.statements.length,1);
 const fuente=readFileSync(new URL('../../../migrations/'+f.nombre,import.meta.url),'utf8');
 assert.equal(row.statements[0],fuente);
 assert.equal(createHash('sha256').update(fuente).digest('hex'),f.sha256);
 assert.ok(!antes.some(r=>r.version===version),'Versión canónica ocupada');
 return {nombre,version,anterior:row.version,sha256:f.sha256,row};
});
const nombres=new Set(candidatos.map(c=>c.nombre));
const previas=filas=>filas.filter(r=>!nombres.has(r.name)).map(({version,name,statements})=>({version,name,statements}));
assert.deepEqual(previas(antes),base.toSorted((a,b)=>a.version.localeCompare(b.version)));
writeFileSync(`${carpeta}/cuatro-ledger-antes.json`,JSON.stringify(candidatos.map(c=>c.row)),{mode:0o600});
const valores=candidatos.map(c=>`('${c.anterior}','${c.version}','${c.nombre}','${c.sha256}')`).join(',');
sql(`begin; lock table supabase_migrations.schema_migrations in access exclusive mode;
create temporary table cambio_f4(anterior text,version text,nombre text,sha256 text) on commit drop;
insert into cambio_f4 values ${valores};
do $guarda$ begin
 if (select count(*) from supabase_migrations.schema_migrations)<>331 or exists(
  select 1 from cambio_f4 c left join supabase_migrations.schema_migrations m on m.version=c.anterior
  where m.name is distinct from c.nombre or cardinality(m.statements) is distinct from 1
   or encode(extensions.digest(convert_to(m.statements[1],'UTF8'),'sha256'),'hex') is distinct from c.sha256
 ) then raise exception 'Ledger cambió'; end if;
end $guarda$;
update supabase_migrations.schema_migrations m set version=c.version from cambio_f4 c where m.version=c.anterior;
commit;`);
const despues=objeto(consulta);
assert.equal(despues.length,331);assert.deepEqual(previas(despues),previas(antes));
for(const c of candidatos){
 const nuevo=despues.find(r=>r.version===c.version);assert.ok(nuevo);
 assert.deepEqual({...nuevo,version:c.anterior},c.row);
}
writeFileSync(`${carpeta}/ledger-candidato.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),
 base:327,total:331,cambios:candidatos.map(({row,...c})=>c),
 prueba:'327 entradas idénticas; cuatro archivos con bytes/SHA exactos; solo cambió version'},null,2)+'\n',{mode:0o600});
console.log('PASS: cuatro versiones canónicas; contenido exacto, 327 migraciones anteriores intactas');
