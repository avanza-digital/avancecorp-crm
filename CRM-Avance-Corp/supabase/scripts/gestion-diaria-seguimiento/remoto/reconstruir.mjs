// Recuperación de la rama VACÍA cuyo replay histórico falló. Solo fixtures locales.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {carpeta,ref,sql,objeto,verificarBaseVacia} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.equal(existsSync(`${carpeta}/base-reconstruida.json`),false,'La reconstrucción ya terminó; no repetir');
const antes=verificarBaseVacia();
const dump='/private/tmp/gestion-diaria-f4-http.WQNCJc/gd-f4-antes-etapa4-20260922.dump';
const huella=createHash('sha256').update(readFileSync(dump)).digest('hex');
assert.equal(huella,'45d000344a7760dd7ab995f25a7e30fdb47bc35710f9523330e637fdb342067f');
const restore='/opt/homebrew/opt/postgresql@17/bin/pg_restore';
const ejecutar=args=>{
 const r=spawnSync(restore,args,{encoding:'utf8',maxBuffer:32*1024*1024});
 assert.equal(r.status,0,'No se pudo extraer el dump sintético');return r.stdout;
};
const toc=ejecutar(['--list',dump]);
const incluidas=toc.split('\n').filter(l=>{
 const cuerpo=l.replace(/^\d+; \d+ \d+ /,'');
 if(l.startsWith(';')||!l.trim())return false;
 // La rama conserva public y sus privilegios administrados por Supabase.
 // postgres no puede recrear los DEFAULT ACL de supabase_admin.
 if(cuerpo.startsWith('DEFAULT ACL ')&&cuerpo.endsWith(' supabase_admin'))return false;
 // Conserva administración Auth/Storage instalada por Supabase; solo dos tablas
 // Auth de fixtures y las policies del producto se reconstruyen.
 return /^[A-Z ]+ (crm|private|public) /.test(cuerpo)
  || /^SCHEMA - (crm|private) /.test(cuerpo)
  || /^ACL - SCHEMA (crm|private|public) /.test(cuerpo)
  || /^TABLE DATA auth (users|identities) /.test(cuerpo)
  || /^TABLE DATA storage (buckets|objects) /.test(cuerpo)
  || /^POLICY storage /.test(cuerpo);
});
assert.ok(incluidas.length>2000);
// Auth ya tiene sus FK en el servicio administrado: users debe preceder a
// identities, aunque el dump de una base nueva enumere identities primero.
const identidad=incluidas.findIndex(l=>l.includes(' TABLE DATA auth identities '));
assert.ok(identidad>=0);
const [entradaIdentidad]=incluidas.splice(identidad,1);
const usuario=incluidas.findIndex(l=>l.includes(' TABLE DATA auth users '));
assert.ok(usuario>=0);incluidas.splice(usuario+1,0,entradaIdentidad);
const listado=`${carpeta}/restauracion-seleccion.toc`;
writeFileSync(listado,incluidas.join('\n')+'\n',{mode:0o600});
const extraer=seccion=>ejecutar(['--use-list',listado,`--section=${seccion}`,'--file','-',dump]);
const listaAuth=`${carpeta}/restauracion-auth.toc`;
writeFileSync(listaAuth,incluidas.filter(l=>l.includes(' TABLE DATA auth ')).join('\n')+'\n',{mode:0o600});
const auth=ejecutar(['--use-list',listaAuth,'--data-only','--file','-',dump]);
assert.ok(auth.indexOf('COPY auth.users ')<auth.indexOf('COPY auth.identities '));
// Prueba focal previa: no persiste usuarios si otra parte de la carga falla.
// El respaldo inmutable tiene 17 actores: 13 cuentas de la matriz y cuatro
// identidades sintéticas adicionales de sus ensayos; no confundir con la semilla anterior.
sql(`begin;\n${auth}\ndo $a$ begin if (select count(*) from auth.users)<>17 then raise exception 'Fixture Auth inesperado'; end if; end $a$; rollback;`);
const listaStorage=`${carpeta}/restauracion-storage.toc`;
writeFileSync(listaStorage,incluidas.filter(l=>l.includes(' TABLE DATA storage ')).join('\n')+'\n',{mode:0o600});
const storage=ejecutar(['--use-list',listaStorage,'--data-only','--file','-',dump]);
assert.ok(storage.indexOf('COPY storage.buckets ')<storage.indexOf('COPY storage.objects '));
// El único bucket del respaldo es propio del fixture. Se conservan los buckets
// administrados existentes; no se borra Storage ni se desactivan sus guardas.
sql(`begin;\n${auth}\n${storage}\ndo $s$ begin
 if not exists(select 1 from storage.buckets where id='f4-comprobantes') then
 raise exception 'Falta bucket sintético'; end if; end $s$; rollback;`);
const original=extraer('pre-data');
const previo=original.replace('CREATE SCHEMA crm;','CREATE SCHEMA crm;\nGRANT CREATE ON SCHEMA crm TO crm_metricas_bridge;')
 .replace('CREATE SCHEMA private;','CREATE SCHEMA private;\nGRANT CREATE ON SCHEMA private TO crm_metricas_bridge;');
// Agrupa DDL en el servidor: evita miles de viajes de red de psql. COPY sigue
// su protocolo nativo y todo conserva una única transacción exterior.
function lote(ddl){
 const limpio=ddl.split('\n').filter(l=>!/^\\(?:un)?restrict\b/.test(l)).join('\n');
 const etiqueta='$gd_'+randomUUID().replaceAll('-','')+'$';
 assert.ok(!limpio.includes(etiqueta));
 return `do $lote$ begin execute ${etiqueta}${limpio}${etiqueta}; end $lote$;\n`;
}
// La retoma usa desde el inicio los siete leads canónicos de la matriz, sin
// los residuos de las pruebas locales que contenía el primer respaldo.
const semilla='/private/tmp/gestion-diaria-f4-http.WQNCJc/semilla-base.dump';
assert.equal(createHash('sha256').update(readFileSync(semilla)).digest('hex'),
 '571b82179c858748a6b66f181b9102d01e57234da0d375e554a646af7aaaf26b');
const datos=ejecutar(['--data-only','--schema=crm','--schema=private','--schema=public','--file','-',semilla]);
const politica=ejecutar(['--data-only','--schema=crm','--table=politica_gestion_diaria','--file','-',dump]);
assert.match(politica,/COPY crm\.politica_gestion_diaria /);
const contenido=lote(previo)+auth+storage+datos+politica+lote(extraer('post-data'));
writeFileSync(`${carpeta}/restauracion-seleccion.sql`,contenido,{mode:0o600});
// Los checks previos fallan si dejó de ser un banco vacío. Todo se confirma
// junto: un error conserva la rama fallida original sin media restauración.
const preparacion=`begin;
set local lock_timeout='5s';
do $guarda$ begin
 if exists(select 1 from auth.users) or exists(select 1 from crm.leads)
   or exists(select 1 from storage.objects)
   or exists(select 1 from cron.job where active)
   or to_regclass('crm.gestion_diaria_entregas') is not null then
   raise exception 'La rama ya no está vacía/inactiva'; end if;
end $guarda$;
-- El grant productivo del puente tiene SET=false. Se añade uno propio temporal
-- para restaurar dueños, sin modificar el grant original de supabase_admin.
grant crm_metricas_bridge to postgres with set true;
alter extension pg_trgm set schema extensions;
drop schema crm cascade;
drop schema private cascade;
-- Conserva OID del esquema public y DEFAULT ACL del administrador de Supabase.
do $limpiar$ declare r record; begin
 for r in select c.oid,n.nspname,c.relname,c.relkind from pg_class c
 join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
 and c.relkind in('r','p','v','m','S') loop
  execute format('drop %s if exists %I.%I cascade',case r.relkind
   when 'v' then 'view' when 'm' then 'materialized view' when 'S' then 'sequence' else 'table' end,r.nspname,r.relname);
 end loop;
 for r in select p.oid::regprocedure::text firma,p.prokind from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
 and p.prokind in('f','p') and not exists(select 1 from pg_depend d
  where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e') loop
  execute format('drop %s if exists %s cascade',case r.prokind when 'p' then 'procedure' else 'function' end,r.firma);
 end loop;
end $limpiar$;
-- Conserva las referencias de los comprobantes SINTÉTICOS del respaldo. No
-- se descargan blobs ni objetos productivos; la rama comienza sin objetos.
`;
const despues=`
revoke create on schema crm, private from crm_metricas_bridge;
revoke crm_metricas_bridge from postgres granted by postgres;
select private.assert_gestion_diaria();
select private.assert_analitica_leads_citas();
do $final$ begin
 if (select count(*) from auth.users)<>17 then raise exception 'Fixture Auth inesperado'; end if;
 if (select count(*) from crm.leads)<>7 or (select count(*) from crm.tareas)<>5 then
   raise exception 'Semilla de matriz inesperada'; end if;
 if (select count(*) from crm.politica_gestion_diaria)<>1
   or exists(select 1 from crm.politica_gestion_diaria where version<>1 or cortes_activos) then
   raise exception 'Política no es v1 OFF'; end if;
end $final$;
commit;`;
sql(preparacion+contenido+despues);
const estado=objeto("select jsonb_build_object('usuarios',(select count(*) from auth.users),'leads',(select count(*) from crm.leads),'cron',(select count(*) from cron.job where active),'gate',private.assert_gestion_diaria())");
writeFileSync(`${carpeta}/base-reconstruida.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),ref,
 respaldoSha256:huella,objetos:incluidas.length,antes,despues:estado},null,2)+'\n',{mode:0o600});
console.log(JSON.stringify({estado:'PASS',ref,objetos:incluidas.length,usuarios:estado.usuarios,leads:estado.leads,cronActivos:estado.cron}));
