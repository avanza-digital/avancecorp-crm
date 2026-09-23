// Banco temporal autorizado para F4. No acepta una URL o proyecto alternativo.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
export const ref='vqfeicbqhrmiyihpxcsl';
export const branchId='5ff71dc3-f44e-49b1-b648-86867231a984';
export const carpeta='/private/tmp/gd-f4-remoto-20260922';
export const apiUrl=`https://${ref}.supabase.co`;
mkdirSync(carpeta,{recursive:true,mode:0o700});
const autorizacion=JSON.parse(readFileSync('/private/tmp/gd-f4-rama-remota-autorizada-20260922.json','utf8'));
assert.equal(autorizacion.project_ref,ref);assert.equal(autorizacion.branch_id,branchId);
assert.equal(autorizacion.with_data,false);assert.equal(autorizacion.autorizado_por_usuario,true);
export const cfg=JSON.parse(readFileSync('/private/tmp/gd-f4-rama-privada-20260922.json','utf8'));
assert.equal(cfg.SUPABASE_URL,apiUrl);
const uri=new URL(cfg.POSTGRES_URL);
assert.equal(uri.pathname,'/postgres');
assert.equal(decodeURIComponent(uri.username),`postgres.${ref}`);
assert.ok(uri.hostname.endsWith('.pooler.supabase.com'));
export const psql='/opt/homebrew/opt/postgresql@17/bin/psql';
export const env={...Object.fromEntries(Object.entries(process.env).filter(([k])=>!k.startsWith('PG'))),
 PGHOST:uri.hostname,PGPORT:'5432',PGDATABASE:'postgres',PGUSER:`postgres.${ref}`,
 PGPASSWORD:decodeURIComponent(uri.password),PGSSLMODE:'require',PGCONNECT_TIMEOUT:'15',PGAPPNAME:'gestion_diaria_f4'};
export function sql(consulta){
 assert.ok(Date.now()<Date.parse(autorizacion.eliminar_antes_de),'Banco vencido: eliminarlo, no seguir usando');
 const r=spawnSync(psql,['-X','-qAt','-v','ON_ERROR_STOP=1','-f','-'],
  {input:"set statement_timeout='180s';\n"+consulta,env,encoding:'utf8',maxBuffer:32*1024*1024});
 if(r.status!==0){
  writeFileSync(`${carpeta}/error-sql-privado.txt`,r.stderr||String(r.error),{mode:0o600});
  throw new Error((r.stderr||'').split('\n').filter(x=>/ERROR:|FATAL:/.test(x)).join('\n')||'Fallo SQL remoto; diagnóstico privado disponible');
 }
 return r.stdout.trim();
}
export const objeto=consulta=>JSON.parse(sql(consulta));
export function verificarBaseVacia(){
 const d=objeto("select jsonb_build_object('usuarios',(select count(*) from auth.users),'leads',(select count(*) from crm.leads),'cron',(select count(*) from cron.job where active),'f4',to_regclass('crm.gestion_diaria_entregas'))");
 assert.equal(d.usuarios,0);assert.equal(d.leads,0);assert.equal(d.cron,0);assert.equal(d.f4,null);
 return d;
}
export async function http(ruta,{token,body,method='POST',headers={}}={}){
 assert.ok(ruta.startsWith('/')&&!ruta.startsWith('//'));
 const r=await fetch(apiUrl+ruta,{method,redirect:'error',signal:AbortSignal.timeout(30_000),
  headers:{apikey:cfg.SUPABASE_ANON_KEY,Authorization:`Bearer ${token??cfg.SUPABASE_ANON_KEY}`,
   'Content-Type':'application/json','Accept-Profile':'crm','Content-Profile':'crm',...headers},
  ...(body===undefined?{}:{body:JSON.stringify(body)})});
 const texto=await r.text();let data;try{data=JSON.parse(texto);}catch{data=texto;}
 return{status:r.status,ok:r.ok,data};
}
