import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {carpeta,cfg,apiUrl,sql} from './banco.mjs';
const [modo,...resto]=process.argv.slice(2);
assert.ok(['--baseline','--candidato'].includes(modo)&&resto.length===0);
assert.equal(sql("select to_regclass('crm.gestion_diaria_entregas') is not null"),modo==='--candidato'?'t':'f');
assert.equal(sql('select count(*) from crm.leads where activo'),'7','La matriz necesita la semilla limpia');
const {password}=JSON.parse(readFileSync('/private/tmp/gestion-diaria-f4-http.WQNCJc/credenciales-fixtures.json','utf8'));
const secretos=[cfg.SUPABASE_ANON_KEY,cfg.SUPABASE_SERVICE_ROLE_KEY,cfg.POSTGRES_URL,password];
const sanear=t=>secretos.reduce((s,k)=>s.replaceAll(k,'[REDACTADO]'),t)
 .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,'[JWT_REDACTADO]');
const entorno={PATH:'/opt/homebrew/opt/postgresql@17/bin:'+process.env.PATH,TMPDIR:process.env.TMPDIR,LANG:process.env.LANG,
 TZ:'America/Lima',PGTZ:'America/Lima',SUPABASE_URL:apiUrl,SUPABASE_ANON_KEY:cfg.SUPABASE_ANON_KEY,
 SUPABASE_SERVICE_ROLE_KEY:cfg.SUPABASE_SERVICE_ROLE_KEY,CRM_DEMO_PASSWORD:password,
 CRM_BANCO_PSQL_URL:cfg.POSTGRES_URL,CRM_RLS_EXIGE_CORTES:'1'};
const inicio=new Date().toISOString();
const etiqueta=modo.slice(2),nombre=`matriz-${etiqueta}-${inicio.replace(/[^0-9]/g,'')}.log`;
const hijo=spawn(process.execPath,['--import',fileURLToPath(new URL('./fetch-propio.mjs',import.meta.url)),
 fileURLToPath(new URL('../../test-rls.mjs',import.meta.url))],{env:entorno,stdio:['ignore','pipe','pipe']});
let salida='';
for(const stream of [hijo.stdout,hijo.stderr])stream.on('data',c=>{
 salida+=c;
 writeFileSync(`${carpeta}/${nombre}`,sanear(salida),{mode:0o600});
 for(const linea of c.toString().split('\n'))if(linea.startsWith('— '))console.log(linea);
});
const exit=await new Promise(r=>hijo.on('close',r));
const log=sanear(salida);
writeFileSync(`${carpeta}/${nombre}`,log,{mode:0o600});
writeFileSync(`${carpeta}/matriz-${etiqueta}.json`,JSON.stringify({inicio,fin:new Date().toISOString(),
 estado:exit===0?'PASS':'FAIL',exit,log:nombre,api:apiUrl},null,2)+'\n',{mode:0o600});
console.log(log.split('\n').filter(l=>/✗|❌|✅|SALTAD|saltado|error fatal/.test(l)).join('\n'));
process.exitCode=exit??1;
