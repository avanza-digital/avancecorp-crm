import assert from 'node:assert/strict';
import{readFileSync,writeFileSync}from'node:fs';
import{isDeepStrictEqual as eq}from'node:util';
import{carpeta,sql,objeto}from'./banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
const e=JSON.parse(readFileSync(`${carpeta}/produccion-catalogo.json`)).rows[0].estructura;
const extras=JSON.parse(readFileSync(`${carpeta}/produccion-extras.json`)).rows[0].extras;
// Supabase db dump omite comentarios de estos dos cuerpos SQL. Restituir el
// texto literal del padre para que los controles comparen también sus huellas.
for(const d of extras.funciones)assert.match(d,/^CREATE OR REPLACE FUNCTION private\.(conversion_episodios|metricas_distribucion_leads_core)\(/);
sql(`begin; ${extras.funciones.join(';\n')}; commit;`);
const a=objeto(readFileSync(new URL('./catalogo.sql',import.meta.url),'utf8'));
for(const x of [a,e])for(const f of x.funciones)if(f.acl)f.acl=f.acl.slice(1,-1).split(',').sort();
const conocidos=['crm.alertas_reconocimientos','crm.empresas','crm.producto_condiciones'];
const normalizaciones=[];
for(const t of e.tablas){const b=a.tablas.find(v=>v.nombre===t.nombre);assert.ok(b,t.nombre);
 if(eq(t,b))continue;
 const campos=Object.keys(t).filter(k=>!eq(t[k],b[k]));
 assert.ok(conocidos.includes(t.nombre),t.nombre+': '+campos);assert.deepEqual(campos,['restricciones']);
 for(let i=0;i<t.restricciones.length;i++){
  const r=t.restricciones[i],s=b.restricciones[i];
  if(eq(r,s))continue;
  // Solo normalización de asociación AND por el deparser, sin OR/NOT.
  assert.equal(r[0],s[0]);assert.equal(r[2],s[2]);
  assert.ok(!/\b(OR|NOT)\b/.test(r[1]),r[0]);
  assert.equal(r[1].replace(/[()]/g,''),s[1].replace(/[()]/g,''));
  normalizaciones.push({tabla:t.nombre,restriccion:r[0],antes:r[1],despues:s[1]});
 }
 b.restricciones=t.restricciones;
}
assert.deepEqual(a,e,'Esquema/funciones/permisos/roles divergentes');
const fks=sql(`do $fk$ declare r record; k text; existe boolean; begin
 for r in select c.*,c.conrelid::regclass::text tabla,c.confrelid::regclass::text destino from pg_constraint c
 join pg_namespace n on n.oid=c.connamespace where c.contype='f' and n.nspname in('crm','private','public') loop
 select string_agg(format('a.%I = b.%I',x.attname,y.attname),' and ') into k
 from unnest(r.conkey,r.confkey) z(a,b) join pg_attribute x on x.attrelid=r.conrelid and x.attnum=z.a
 join pg_attribute y on y.attrelid=r.confrelid and y.attnum=z.b;
 execute format('select exists(select 1 from %s a where %s and not exists(select 1 from %s b where %s))',
 r.tabla,(select string_agg(format('a.%I is not null',attname),' and ') from pg_attribute where attrelid=r.conrelid and attnum=any(r.conkey)),r.destino,k) into existe;
 if existe then raise exception 'FK huérfana: %.%',r.tabla,r.conname; end if;
 end loop;
end $fk$;
select jsonb_build_object('fk_huerfanas',0,'cron_activos',(select count(*) from cron.job where active),'vault',(select count(*) from vault.secrets),'replicacion',current_setting('session_replication_role'));`);
writeFileSync(`${carpeta}/paridad-esquema.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),tablas:a.tablas.length,funciones:a.funciones.length,normalizaciones,integridad:JSON.parse(fks)},null,2),{mode:0o600});
console.log(`PASS: ${a.tablas.length} tablas, ${a.funciones.length} funciones, ACL/roles/RLS y FK; cron detenido.`);
