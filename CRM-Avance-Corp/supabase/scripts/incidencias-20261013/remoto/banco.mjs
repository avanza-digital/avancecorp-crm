// Único destino de escritura autorizado por Miguel: banco-f7, nunca el padre.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
export const ref='cwkiejoaqadcnaieghnf';
export const carpeta='/private/tmp/incidencias-banco-f7';
mkdirSync(carpeta,{recursive:true,mode:0o700});
export const cfg=JSON.parse(readFileSync('/private/tmp/incidencias-banco-f7-credentials.json','utf8'));
assert.equal(cfg.SUPABASE_URL,`https://${ref}.supabase.co`);
const uri=new URL(cfg.POSTGRES_URL);
assert.equal(decodeURIComponent(uri.username),`postgres.${ref}`);
assert.ok(uri.hostname.endsWith('.pooler.supabase.com'));
assert.equal(uri.pathname,'/postgres');
export const env={...Object.fromEntries(Object.entries(process.env).filter(([k])=>!k.startsWith('PG'))),
 PGHOST:uri.hostname,PGPORT:'5432',PGDATABASE:'postgres',PGUSER:`postgres.${ref}`,
 PGPASSWORD:decodeURIComponent(uri.password),PGSSLMODE:'require',PGCONNECT_TIMEOUT:'15',PGAPPNAME:'incidencias_f7_banco'};
export function sql(consulta){
 const r=spawnSync('/opt/homebrew/opt/postgresql@17/bin/psql',['-X','-qAt','-v','ON_ERROR_STOP=1','-f','-'],
  {input:"set statement_timeout='180s';\n"+consulta,env,encoding:'utf8',maxBuffer:64*1024*1024});
 if(r.status!==0){
  writeFileSync(`${carpeta}/error-sql-privado.txt`,r.stderr||String(r.error),{mode:0o600});
  throw new Error((r.stderr||'').split('\n').filter(x=>/ERROR:|FATAL:/.test(x)).join('\n')||'Fallo de conexión; ver diagnóstico privado');
 }
 return r.stdout.trim();
}
export const objeto=consulta=>JSON.parse(sql(consulta));
