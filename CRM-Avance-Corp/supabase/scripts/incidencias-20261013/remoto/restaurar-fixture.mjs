// Repite el gate desde la fotografía sintética, conservando el esquema probado.
import assert from 'node:assert/strict';
import{readFileSync,writeFileSync,copyFileSync}from'node:fs';
import{spawnSync}from'node:child_process';
import{createClient}from'@supabase/supabase-js';
import{carpeta,sql,cfg}from'./banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.equal(JSON.parse(readFileSync(`${carpeta}/gate-http-estado.json`)).estado,'FAIL');
const intento=new Date().toISOString().replace(/[:.]/g,'-');
copyFileSync(`${carpeta}/gate-http.log`,`${carpeta}/gate-http-fallido-${intento}.log`);
copyFileSync(`${carpeta}/gate-http-estado.json`,`${carpeta}/gate-http-fallido-${intento}.json`);
const dump=`${carpeta}/banco-sintetico-antes-gate.dump`;
const restaurar=args=>{const r=spawnSync('/opt/homebrew/opt/postgresql@17/bin/pg_restore',args,{encoding:'utf8',maxBuffer:64*1024*1024});assert.equal(r.status,0,r.stderr);return r.stdout;};
const toc=restaurar(['--list',dump]).split('\n').filter(l=>/ TABLE DATA (crm|private|public) /.test(l)||/ TABLE DATA auth (users|identities) /.test(l));
const usuarios=toc.find(l=>/ TABLE DATA auth users /.test(l));const identidades=toc.find(l=>/ TABLE DATA auth identities /.test(l));
assert.ok(usuarios&&identidades);
const orden=[usuarios,identidades,...toc.filter(l=>l!==usuarios&&l!==identidades)];
writeFileSync(`${carpeta}/datos-fixture.toc`,orden.join('\n'),{mode:0o600});
const datos=restaurar(['--use-list',`${carpeta}/datos-fixture.toc`,'--data-only','--file','-',dump]).split('\n').filter(l=>!/^\\(?:un)?restrict\b/.test(l)).join('\n');
sql(`begin; set local session_replication_role=replica;
do $vaciar$ declare tablas text; begin
 if exists(select 1 from cron.job where active) then raise exception 'Cron activo'; end if;
 select string_agg(c.oid::regclass::text,',') into tablas from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('crm','private','public') and c.relkind in('r','p') and not exists(select 1 from pg_depend d
 where d.classid='pg_class'::regclass and d.objid=c.oid and d.deptype='e');
 execute 'truncate '||tablas||',auth.users cascade';
end $vaciar$;
truncate auth.audit_log_entries,auth.flow_state,auth.refresh_tokens,auth.one_time_tokens cascade;
${datos}
set local session_replication_role=origin;
do $validar$ begin
 if (select count(*) from auth.users)<>13 or (select count(*) from crm.leads)<>7
 or (select count(*) from crm.tareas)<>5 then raise exception 'Fixture incoherente'; end if;
 perform private.assert_f7_piezas_cerradas();
end $validar$; commit;`);
const admin=createClient(cfg.SUPABASE_URL,cfg.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const buckets=[['comunicados',true,5242880,['image/*']],['contratos-generados',false,10485760,['application/pdf']],
 ['documentos',false,10485760,['application/pdf']],['f4-comprobantes',false,10485760,['application/pdf','image/jpeg','image/png']],
 ['respaldos-cambio-cuenta',false,10485760,['application/pdf','image/jpeg','image/png']]];
const {data:existentes,error}=await admin.storage.listBuckets();assert.ifError(error);
for(const[id,publico,fileSizeLimit,allowedMimeTypes]of buckets){if(existentes.some(b=>b.id===id))continue;
 const {error:e}=await admin.storage.createBucket(id,{public:publico,fileSizeLimit,allowedMimeTypes});assert.ifError(e);
}
console.log('PASS: fixture 13/7/5 restaurado y cinco buckets técnicos, sin blobs productivos.');
