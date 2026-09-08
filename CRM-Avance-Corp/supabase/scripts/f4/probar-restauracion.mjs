// Reversa operativa y restauración completa de datos sintéticos + bytes Storage.
// No reemplaza la base activa ni elimina tablas, filas o volúmenes existentes.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {openSync,closeSync,readFileSync,writeFileSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {crearCopiaSql} from './copia-sql-local.mjs';
import {sql,entorno,literal as q,leer} from './banco-local.mjs';
assert.equal(entorno,'avancecorp-f4-reconstruccion');
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"),'f');
const f=leer('fixtures.json'),pruebas=[];
function caso(nombre,fn){fn();pruebas.push({nombre,conforme:true});console.log('PASS: '+nombre);}
const tablas=JSON.parse(sql(`select jsonb_agg(format('%I.%I',n.nspname,c.relname) order by n.nspname,c.relname)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','crm','private','auth','storage')
 and c.relkind='r' and not exists(select 1 from pg_inherits i where i.inhrelid=c.oid)`));
const foto=`select jsonb_object_agg(tabla,jsonb_build_object('filas',filas,'hash',hash)) from (${tablas.map(t=>
 `select ${q(t)} tabla,count(*) filas,private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')) hash from ${t} t`).join(' union all ')}) x`;
const estructura=`select private.idem_hash(jsonb_build_object('funciones',(select jsonb_agg(jsonb_build_object('firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
 'md5',md5(pg_get_functiondef(p.oid)),'acl',p.proacl,'owner',pg_get_userbyid(p.proowner)) order by n.nspname,p.proname,oidvectortypes(p.proargtypes))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','crm','private') and p.prokind='f'),
 'policies',(select jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname) from pg_policies p where schemaname in ('public','crm','private','storage')),
 -- pg_dump representa el ACL del propietario por defecto como NULL. Comparar
 -- los permisos efectivos evita confundirlo con pérdida de grants.
 'tablas',(select jsonb_agg(jsonb_build_object('tabla',format('%I.%I',n.nspname,c.relname),'acl',coalesce(c.relacl,acldefault('r',c.relowner)),'rls',c.relrowsecurity,'owner',pg_get_userbyid(c.relowner)) order by n.nspname,c.relname)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','crm','private') and c.relkind='r'))) `;
const antes=sql(foto),forma=sql(estructura);
caso('Reversa operativa OFF rechaza altas y conserva todo el historial confirmado',()=>{
 const id=randomUUID(),persona=leer('operaciones-base.json').identidades.avance;
 assert.throws(()=>sql(`\\set VERBOSITY verbose
 begin;set local request.jwt.claims=${q(JSON.stringify({sub:f.usuarios.vendedor.id,role:'authenticated'}))};set local role authenticated;
 select crm.preparar_inversion_fn(${q(id)},${q(JSON.stringify({inversionista_id:persona,empresa:'qorilazo'}))});commit;`),/P0409/);
 assert.equal(sql(foto),antes);
});
const copia=crearCopiaSql('restauracion');
caso('Backup/restore SQL conserva todas las tablas de negocio, Auth y metadata Storage',()=>assert.equal(copia.sql(foto),antes));
caso('Restauración conserva cuerpos, propietarios, ACL y RLS de aplicación',()=>assert.equal(copia.sql(estructura),forma));
const storage=`supabase_storage_${entorno}`;
function docker(args,opts={}){const r=spawnSync('docker',args,{encoding:'utf8',maxBuffer:32*1024*1024,...opts});assert.equal(r.status,0,r.stderr||r.error?.message);return r.stdout?.trim();}
const conf=JSON.parse(docker(['inspect',storage,'--format','{{json .Mounts}}']));
assert(conf.some(m=>m.Type==='volume'&&m.Name===storage&&m.Destination==='/mnt'));
const imagen=docker(['inspect',storage,'--format','{{.Image}}']);assert.match(imagen,/^sha256:[a-f0-9]{64}$/);
const tar=`${copia.carpeta}/storage-sintetico.tar`,fd=openSync(tar,'wx',0o600);
try{docker(['exec',storage,'tar','-C','/mnt','-cf','-','.'],{stdio:['ignore',fd,'pipe']});}finally{closeSync(fd);}
const volumen=`f4_restauracion_storage_${copia.id.replaceAll('-','')}`;
docker(['volume','create','--label','entorno=f4-sintetico',volumen]);
const entrada=openSync(tar,'r');
try{docker(['run','--rm','-i','--network','none','--mount',`type=volume,src=${volumen},dst=/recuperado`,
 '--entrypoint','tar',imagen,'-C','/recuperado','-xf','-'],{stdio:[entrada,'pipe','pipe']});}finally{closeSync(entrada);}
// Nombres vienen del Storage sintético; execFile/find no interpola rutas en shell.
const manifestar=(args)=>docker(args).split('\n').filter(Boolean).map(l=>l.replace(/\s+\.?\//,'  /')).sort();
const archivosOriginal=manifestar(['exec','-w','/mnt',storage,'find','.','-type','f','-exec','sha256sum','{}',';']);
const archivosRestaurados=manifestar(['run','--rm','--network','none','--mount',`type=volume,src=${volumen},dst=/mnt,readonly`,
 '-w','/mnt','--entrypoint','find',imagen,'.','-type','f','-exec','sha256sum','{}',';']);
caso('Storage restaurado en volumen nuevo conserva cada archivo con los mismos bytes',()=>{
 assert(archivosOriginal.length>0);assert.deepEqual(archivosRestaurados,archivosOriginal);
});
const objetos=JSON.parse(copia.sql("select jsonb_agg(jsonb_build_object('bucket',bucket_id,'name',name,'version',version)) from storage.objects"));
caso('Metadata restaurada encuentra el comprobante o PDF correspondiente en Storage',()=>{
 for(const o of objetos)assert(archivosRestaurados.some(a=>a.includes('/'+o.bucket+'/'+o.name)),`Falta objeto restaurado del bucket ${o.bucket}`);
 assert(objetos.some(o=>o.bucket==='contratos-generados'));
});
caso('Ensayo no modifica la base original ni enciende F4',()=>assert.equal(sql(foto),antes));
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
writeFileSync(new URL(`../evidencia-f4/restauracion-${copia.id}.json`,import.meta.url),JSON.stringify({entorno,terminadoEn:new Date().toISOString(),
 baseRestaurada:copia.nombre,volumenRestaurado:volumen,pruebas,tablas:JSON.parse(antes),huellaEstructura:forma,
 backupSqlSha256:sha(copia.archivo),backupStorageSha256:sha(tar),archivosStorage:archivosOriginal.length,objetos:objetos.length,
 limites:['Restauración SQL y archivos en destinos nuevos; no es un tercer stack HTTP independiente.',
 'Los jobs cron, publicaciones y suscripciones no se duplican. La recuperación operativa conserva F4 instalado y apagado; no elimina historia ni reinstala F2 global.',
 'Copias privadas contienen únicamente datos sintéticos. La restauración productiva requiere respaldo coherente de DB, Storage y configuración del entorno.']},null,2)+'\n',{flag:'wx'});
console.log(`Restauración: ${pruebas.length} grupos; ${tablas.length} tablas y ${archivosOriginal.length} archivos.`);
