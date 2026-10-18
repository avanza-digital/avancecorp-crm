// Recuperación autorizada del banco obsoleto. Nunca restaura datos de clientes.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {carpeta,ref,sql,objeto} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.ok(!existsSync(`${carpeta}/reconstruccion.json`),'Reconstrucción ya terminada');
const sha=x=>createHash('sha256').update(x).digest('hex');
assert.equal(sha(readFileSync(`${carpeta}/respaldo-previo.dump`)),
 '3e5ae6e27f3e786c660c813bb00c38bcd6d3183bff6f3c4b170b3f5dd03807a1');
const catalogo=JSON.parse(readFileSync(`${carpeta}/produccion-catalogo.json`)).rows[0].estructura;
let ddl=readFileSync('/private/tmp/incidencias-prod-schema-vigente.sql','utf8');
assert.ok(ddl.includes('schema_migrations_idempotency_key_key'));
assert.ok(ddl.includes('CREATE SCHEMA IF NOT EXISTS "crm";'));
ddl=ddl.replace('CREATE SCHEMA IF NOT EXISTS "crm";',
 'CREATE SCHEMA IF NOT EXISTS "crm"; GRANT CREATE ON SCHEMA crm TO crm_metricas_bridge,crm_gestion_diaria_lector;')
 .replace('CREATE SCHEMA IF NOT EXISTS "private";',
 'CREATE SCHEMA IF NOT EXISTS "private"; GRANT CREATE ON SCHEMA private TO crm_metricas_bridge,crm_gestion_diaria_lector;');
const tag='$banco_'+randomUUID().replaceAll('-','')+'$';assert.ok(!ddl.includes(tag));
const q=x=>'"'+x.replaceAll('"','""')+'"';
const extras=[];
for(const [t,estado] of catalogo.auth_triggers){assert.equal(estado,'O');extras.push(t+';');}
for(const p of catalogo.storage_policies){
 assert.equal(p.schemaname,'storage');
 extras.push(`drop policy if exists ${q(p.policyname)} on storage.${q(p.tablename)};`);
 extras.push(`create policy ${q(p.policyname)} on storage.${q(p.tablename)} as ${p.permissive} for ${p.cmd} to ${p.roles.map(q).join(',')}`
  +(p.qual?` using (${p.qual})`:'')+(p.with_check?` with check (${p.with_check})`:'')+';');
}
const antes=objeto(`select jsonb_build_object('usuarios',(select count(*) from auth.users),'leads',(select count(*) from crm.leads),'cron_activos',(select count(*) from cron.job where active),'storage',(select count(*) from storage.objects))`);
assert.equal(antes.cron_activos,0);assert.equal(antes.storage,0);
sql(`begin;
set local lock_timeout='5s';
do $guard$ begin
 if exists(select 1 from cron.job where active) or exists(select 1 from storage.objects) then
 raise exception 'Banco dejó de estar inactivo'; end if;
end $guard$;
do $roles$ begin
 if not exists(select 1 from pg_roles where rolname='crm_gestion_diaria_lector') then
 create role crm_gestion_diaria_lector nologin nosuperuser nocreatedb nocreaterole inherit nobypassrls;
 end if;
end $roles$;
grant crm_metricas_bridge,crm_gestion_diaria_lector to postgres with set true;
grant authenticated to crm_gestion_diaria_lector;
drop schema crm cascade;
drop schema private cascade;
drop schema supabase_migrations cascade;
do $limpiar$ declare r record; begin
 for r in select c.oid,n.nspname,c.relname,c.relkind from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind in('r','p','v','m','S') and not exists(select 1 from pg_depend d
 where d.classid='pg_class'::regclass and d.objid=c.oid and d.deptype='e') loop
 execute format('drop %s if exists %I.%I cascade',case r.relkind when 'v' then 'view' when 'm' then 'materialized view'
 when 'S' then 'sequence' else 'table' end,r.nspname,r.relname);
 end loop;
 for r in select p.oid::regprocedure::text firma,p.prokind from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prokind in('f','p') and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass
 and d.objid=p.oid and d.deptype='e') loop
 execute format('drop %s if exists %s cascade',case r.prokind when 'p' then 'procedure' else 'function' end,r.firma);
 end loop;
end $limpiar$;
-- Las identidades anteriores también pertenecen al banco autorizado; se crearán nuevas cuentas sintéticas.
truncate auth.users cascade;
delete from vault.secrets;
delete from net.http_request_queue;
do $ddl$ begin execute ${tag}${ddl}${tag}; end $ddl$;
${extras.join('\n')}
alter publication supabase_realtime add table public.novedades,public.novedades_leidas,public.audit_log;
revoke create on schema crm,private from crm_metricas_bridge,crm_gestion_diaria_lector;
grant crm_metricas_bridge to postgres with admin false, inherit true, set false;
notify pgrst,'reload schema';
commit;`);
const despues=objeto(`select jsonb_build_object('usuarios',(select count(*) from auth.users),'leads',(select count(*) from crm.leads),'cron_activos',(select count(*) from cron.job where active),'vault',(select count(*) from vault.secrets),'ledger',(select count(*) from supabase_migrations.schema_migrations))`);
assert.deepEqual(despues,{usuarios:0,leads:0,cron_activos:0,vault:0,ledger:0});
writeFileSync(`${carpeta}/reconstruccion.json`,JSON.stringify({estado:'PASS',ref,fecha:new Date().toISOString(),antes,despues,esquemaSha256:sha(ddl)},null,2),{mode:0o600});
console.log(JSON.stringify({estado:'PASS',ref,...despues}));
