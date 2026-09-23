// Prepara la semilla exacta que exige la matriz general, ANTES de instalar F4.
// El primer respaldo incluía residuos de ensayos locales (16 leads activos).
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync,mkdirSync,renameSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {carpeta,sql,objeto,env} from './banco.mjs';
const candidato=process.argv[3]==='--antes-candidato';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada',...(candidato?['--antes-candidato']:[])]);
const sufijo=candidato?'-candidato':'';
if(candidato)assert.equal(JSON.parse(readFileSync(`${carpeta}/matriz-baseline.json`,'utf8')).estado,'PASS');
assert.equal(existsSync(`${carpeta}/semilla-limpia${sufijo}.json`),false);
assert.equal(sql("select to_regclass('crm.gestion_diaria_entregas') is null"),'t');
const origen='/private/tmp/gestion-diaria-f4-http.WQNCJc';
const manifest=JSON.parse(readFileSync(`${origen}/semilla-base.json`,'utf8'));
assert.equal(manifest.proyecto,'gestion-diaria-f4-http');assert.equal(manifest.candidato,false);
assert.equal(createHash('sha256').update(readFileSync(`${origen}/semilla-base.dump`)).digest('hex'),manifest.sha256);
const archivoRespaldo=`${carpeta}/antes-semilla-limpia${sufijo}.dump`;
if(!existsSync(archivoRespaldo)){
 const respaldo=spawnSync('/opt/homebrew/opt/postgresql@17/bin/pg_dump',
  ['-Fc','--schema=crm','--schema=private','--schema=public'],{env,maxBuffer:64*1024*1024});
 assert.equal(respaldo.status,0,'No se pudo respaldar el banco');
 writeFileSync(archivoRespaldo,respaldo.stdout,{mode:0o600,flag:'wx'});
}
assert.ok(readFileSync(archivoRespaldo).length>1_000_000,'Respaldo incompleto');
const restore='/opt/homebrew/opt/postgresql@17/bin/pg_restore';
const extraer=(args,dump)=>{const r=spawnSync(restore,[...args,dump],{encoding:'utf8',maxBuffer:32*1024*1024});
 assert.equal(r.status,0,'No se pudo extraer semilla');return r.stdout;};
const dump=`${origen}/gd-f4-antes-etapa4-20260922.dump`;
const seleccion=['--use-list',`${carpeta}/restauracion-seleccion.toc`,'--file','-'];
let previo=extraer([...seleccion,'--section=pre-data'],dump);
previo=previo.replace('CREATE SCHEMA crm;','CREATE SCHEMA crm; grant create on schema crm to crm_metricas_bridge;')
 .replace('CREATE SCHEMA private;','CREATE SCHEMA private; grant create on schema private to crm_metricas_bridge;');
const posterior=extraer([...seleccion,'--section=post-data'],dump);
const datos=extraer(['--data-only','--schema=crm','--schema=private','--schema=public','--file','-'],`${origen}/semilla-base.dump`);
// pg_restore -t acepta el nombre SIN esquema, a diferencia de pg_dump -t.
const politica=extraer(['--data-only','--schema=crm','--table=politica_gestion_diaria','--file','-'],dump);
assert.match(politica,/COPY crm\.politica_gestion_diaria /,'Extracción vacía de política');
assert.equal(politica.match(/FROM stdin;\n([\s\S]*?)\n\\\./)[1].split('\n').length,1);
const lote=ddl=>{const marca='$gd_'+randomUUID().replaceAll('-','')+'$';
 const limpio=ddl.split('\n').filter(l=>!/^\\(?:un)?restrict\b/.test(l)).join('\n');
 return `do $bloque$ begin execute ${marca}${limpio}${marca}; end $bloque$;\n`;};
const preparar=`begin;
do $guarda$ begin
 if (select count(*) from auth.users)<>${candidato?21:17} or exists(select 1 from cron.job where active)
  or to_regclass('crm.gestion_diaria_entregas') is not null then raise exception 'Banco cambió'; end if;
end $guarda$;
grant crm_metricas_bridge to postgres with set true;
-- Las fronteras que solo mencionan bucket_id no dependen del esquema CRM,
-- por lo que DROP SCHEMA CASCADE no las retira. Se recrean del mismo dump.
drop policy f4_comprobante_delete_frontera on storage.objects;
drop policy f4_comprobante_update_frontera on storage.objects;
drop schema crm cascade; drop schema private cascade;
do $limpiar$ declare r record; begin
 for r in select c.oid,n.nspname,c.relname,c.relkind from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind in('r','p','v','m','S') loop
 execute format('drop %s if exists %I.%I cascade',case r.relkind when 'v' then 'view' when 'm' then 'materialized view'
 when 'S' then 'sequence' else 'table' end,r.nspname,r.relname); end loop;
 for r in select p.oid::regprocedure::text firma,p.prokind from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prokind in('f','p') and not exists(select 1 from pg_depend d
 where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e') loop
 execute format('drop %s if exists %s cascade',case r.prokind when 'p' then 'procedure' else 'function' end,r.firma); end loop;
end $limpiar$;
`;
sql(preparar+lote(previo)+datos+politica+lote(posterior)+`
revoke create on schema crm,private from crm_metricas_bridge;
grant crm_metricas_bridge to postgres with set false;
do $final$ begin
 if (select count(*) from crm.leads)<>7 or (select count(*) from crm.tareas)<>5
  or (select count(*) from crm.politica_gestion_diaria)<>1
  or exists(select 1 from crm.politica_gestion_diaria where cortes_activos) then
  raise exception 'Semilla inesperada: leads %, tareas %, políticas %',
    (select count(*) from crm.leads),(select count(*) from crm.tareas),(select count(*) from crm.politica_gestion_diaria);
 end if;
end $final$;
select private.assert_gestion_diaria(); commit;`);
const archivo=`${carpeta}/antes-semilla-limpia${sufijo}`;
mkdirSync(archivo,{mode:0o700});
for(const nombre of ['base-alineada','catalogo-base-alineada','permisos-alineados','estructura-paridad','ledger-alineado'])
 renameSync(`${carpeta}/${nombre}.json`,`${archivo}/${nombre}.json`);
writeFileSync(`${carpeta}/semilla-limpia${sufijo}.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),
 respaldo:archivoRespaldo,semillaSha256:manifest.sha256,
 resumen:objeto("select jsonb_build_object('leads',(select count(*) from crm.leads),'tareas',(select count(*) from crm.tareas),'cortes',(select bool_or(cortes_activos) from crm.politica_gestion_diaria))")},null,2)+'\n',{mode:0o600});
console.log('PASS: semilla de siete leads y cinco tareas restaurada; Auth, Storage e historial SQL conservados. Repetir alineación y cotejo antes del candidato.');
