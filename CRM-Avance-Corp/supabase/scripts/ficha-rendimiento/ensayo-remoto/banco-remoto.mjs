import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
export const base='postgres';
export const ajustes="set local statement_timeout='180s'; set local jit=off; set local work_mem='3500kB'; set local random_page_cost=1.1;";
const dir='/private/tmp/avancecorp-ficha-optim-20260915';
const cfg=JSON.parse(readFileSync(dir+'/rama-privada.json','utf8'));
const ref='tufxjboalbtekbszckcf';
assert.equal(cfg.SUPABASE_URL,`https://${ref}.supabase.co`);
const uri=new URL(cfg.POSTGRES_URL||cfg.POSTGRES_URL_NON_POOLING);
const user=decodeURIComponent(uri.username);
assert.ok(uri.hostname===`db.${ref}.supabase.co`||(uri.hostname.endsWith('.pooler.supabase.com')&&user===`postgres.${ref}`));
assert.equal(uri.pathname,'/postgres');
const env={...process.env,PGHOST:uri.hostname,PGPORT:'5432',PGDATABASE:'postgres',PGUSER:user,PGPASSWORD:decodeURIComponent(uri.password),PGSSLMODE:'require',PGCONNECT_TIMEOUT:'15'};
export function sql(consulta){
 const r=spawnSync('/opt/homebrew/opt/postgresql@17/bin/psql',['-X','-qAt','-v','ON_ERROR_STOP=1','-f','-'],{input:consulta,env,encoding:'utf8',maxBuffer:32*1024*1024});
 if(r.status!==0){writeFileSync(dir+'/error-ensayo-privado.txt',r.stderr||String(r.error),{mode:0o600});throw new Error((r.stderr||'').split('\n').filter(x=>x.includes('ERROR:')).join('\n')||'Ensayo remoto falló; consultar diagnóstico privado saneado');}
 return r.stdout.trim();
}
