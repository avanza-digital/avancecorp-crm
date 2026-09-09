// Construye solo desde el commit que comparten HEAD, Main local y avancecorp/main.
// No instala SQL, publica archivos ni cambia banderas.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,readdirSync,copyFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join,resolve} from 'node:path';
const crm=fileURLToPath(new URL('../../../',import.meta.url));
const root=resolve(crm,'..');
const run=(cmd,args,cwd=root,env=process.env)=>{
 const r=spawnSync(cmd,args,{cwd,env,encoding:'utf8',maxBuffer:16*1024*1024});
 assert.equal(r.status,0,r.stderr||r.stdout);return r.stdout.trim();
};
const commit=run('git',['rev-parse','HEAD']);
const verificar=()=>{for(const ref of ['main','avancecorp/main']) assert.equal(run('git',['rev-parse',ref]),commit,`Sincronizar ${ref} antes de construir`);};
verificar();
const rutas=['CRM-Avance-Corp/app','CRM-Avance-Corp/supabase/scripts/f5',
 'CRM-Avance-Corp/supabase/migrations/20260908230249_crm_f5_cartera_ficha_multiempresa.sql',
 '_supabase_functions/functions/crm-inversion-documento'];
const verificarFuentes=()=>{
 assert.equal(run('git',['diff','--name-only','HEAD','--',...rutas]),'','El código debe estar guardado en commits');
 assert.equal(run('git',['ls-files','--others','--exclude-standard','--',...rutas]),'','Hay fuentes sin guardar');
};
verificarFuentes();
const carpeta=`/private/tmp/avancecorp-f5-paquete-${commit.slice(0,12)}`;
mkdirSync(carpeta,{recursive:true});
writeFileSync(join(carpeta,'build.log'),run('npm',['run','build'],join(crm,'app'))+'\n');
writeFileSync(join(carpeta,'bundle.log'),run('npm',['run','verify:bundle'],join(crm,'app'))+'\n');
const hash=b=>createHash('sha256').update(b).digest('hex');
const archivos=[];
function inventariar(dir,prefijo=''){
 for(const e of readdirSync(dir,{withFileTypes:true})) {
  const relativo=prefijo+e.name,p=join(dir,e.name);
  if(e.isDirectory()) inventariar(p,relativo+'/');
  else if(e.isFile()) {const b=readFileSync(p);archivos.push({ruta:relativo,bytes:b.length,sha256:hash(b)});}
  else throw new Error('No empaquetar enlaces simbólicos');
 }
}
inventariar(join(crm,'app/dist'));
// bsdtar en macOS añade AppleDouble (._*) sin esta variable: no son fuentes del build.
run('tar',['-czf',join(carpeta,'frontend.tar.gz'),'-C',join(crm,'app/dist'),'.'],root,{...process.env,COPYFILE_DISABLE:'1'});
const sql='20260908230249_crm_f5_cartera_ficha_multiempresa.sql';
copyFileSync(join(crm,'supabase/migrations',sql),join(carpeta,sql));
const reversa='reversa-operativa.sql';
copyFileSync(join(crm,'supabase/scripts/f5',reversa),join(carpeta,reversa));
for(const n of ['handler.mjs','index.ts'])copyFileSync(join(root,'_supabase_functions/functions/crm-inversion-documento',n),join(carpeta,`documento-${n}`));
verificar();verificarFuentes();assert.equal(run('git',['rev-parse','HEAD']),commit);
const manifiesto={estado:'PREPARADO, SIN PUBLICAR',commit,main:commit,remoto:'avancecorp/main',node:process.version,
 sql:{archivo:sql,sha256:hash(readFileSync(join(carpeta,sql)))},
 reversa:{archivo:reversa,sha256:hash(readFileSync(join(carpeta,reversa)))},
 frontend:{archivo:'frontend.tar.gz',sha256:hash(readFileSync(join(carpeta,'frontend.tar.gz'))),archivos:archivos.sort((a,b)=>a.ruta.localeCompare(b.ruta))},
 funciones:{'crm-inversion-documento':Object.fromEntries(['handler.mjs','index.ts'].map(n=>[n,hash(readFileSync(join(carpeta,`documento-${n}`)))]))},
 banderasProductivasModificadas:false,construidoEn:new Date().toISOString()};
writeFileSync(join(carpeta,'manifiesto.json'),JSON.stringify(manifiesto,null,2)+'\n');
console.log(JSON.stringify({commit,carpeta,estado:manifiesto.estado}));
