import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {isDeepStrictEqual} from 'node:util';
import {carpeta,sql,objeto} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.ok(existsSync(`${carpeta}/base-alineada.json`));
assert.equal(existsSync(`${carpeta}/permisos-alineados.json`),false);
const e=JSON.parse(readFileSync('/private/tmp/gd-f4-estructura-productiva-20260922.json','utf8')).rows[0].estructura;
const a=objeto(readFileSync(new URL('./catalogo-estructura.sql',import.meta.url),'utf8'));
const ident=x=>{assert.match(x,/^[a-z_][a-z_0-9]*$/);return '"'+x+'"';};
const sentencia=[];
for(const t of e.tablas){
 const b=a.tablas.find(v=>v.nombre===t.nombre);assert.ok(b);
 const extras=(b.acl??[]).filter(v=>!(t.acl??[]).some(w=>isDeepStrictEqual(v,w)));
 for(const [rol,privilegio,otorgable] of extras){
  assert.match(t.nombre,/^public\.[a-z_]+$/);
  assert.ok(['anon','authenticated'].includes(rol));assert.equal(otorgable,false);
  assert.ok(['TRIGGER','TRUNCATE','REFERENCES','MAINTAIN'].includes(privilegio));
  sentencia.push(`revoke ${privilegio} on table ${t.nombre} from ${ident(rol)};`);
 }
}
for(const p of e.storage_policies){
 const previo=(a.storage_policies??[]).find(v=>v.policyname===p.policyname&&v.tablename===p.tablename);
 if(previo){assert.ok(isDeepStrictEqual(previo,p));continue;}
 assert.equal(p.tablename,'objects');assert.equal(p.schemaname,'storage');
 assert.equal(p.permissive,'PERMISSIVE');assert.deepEqual(p.roles,['authenticated']);
 assert.ok(['SELECT','INSERT','DELETE'].includes(p.cmd));
 sentencia.push(`create policy ${ident(p.policyname)} on storage.objects as permissive for ${p.cmd} to authenticated`
  +(p.qual?` using (${p.qual})`:'')+(p.with_check?` with check (${p.with_check})`:'')+';');
}
assert.equal((a.auth_triggers??[]).length,0);assert.equal(e.auth_triggers.length,1);
assert.equal(e.auth_triggers[0][1],'O');
assert.ok(e.auth_triggers[0][0].startsWith('CREATE CONSTRAINT TRIGGER trg_auth_correo_cliente_atomico AFTER UPDATE ON auth.users '));
assert.ok(e.auth_triggers[0][0].endsWith('EXECUTE FUNCTION private.sincronizar_correo_cliente_auth()'));
sentencia.push(e.auth_triggers[0][0]+';');
const membresia=['crm_metricas_bridge','postgres','postgres',false,true,false];
assert.ok(e.membresias.some(v=>isDeepStrictEqual(v,membresia)));
if(!a.membresias.some(v=>isDeepStrictEqual(v,membresia)))
 sentencia.push('grant crm_metricas_bridge to postgres with admin false, inherit true, set false;');
// Una sola sentencia del protocolo evita viajes de red por cada privilegio.
const lote=sentencia.join('\n');assert.ok(!lote.includes('$permisos$'));
sql(`begin; do $bloque$ begin execute $permisos$${lote}$permisos$; end $bloque$; commit;`);
writeFileSync(`${carpeta}/permisos-alineados.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),sentencias:sentencia.length},null,2)+'\n',{mode:0o600});
console.log('PASS: permisos, policies Storage, trigger Auth y membresía del banco alineados; falta cotejo final');
