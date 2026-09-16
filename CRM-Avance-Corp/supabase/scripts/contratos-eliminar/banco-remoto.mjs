// Adaptador del ensayo autorizado del 15/09/2026. Destino fijo: nunca producción.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';

export const ref='urjpvkbjvpraegrmdnos';
export const cfg=JSON.parse(readFileSync('/private/tmp/contratos-rama-privada.json','utf8'));
assert.equal(cfg.SUPABASE_URL,`https://${ref}.supabase.co`);
const uri=new URL(cfg.POSTGRES_URL);
assert.equal(decodeURIComponent(uri.username),`postgres.${ref}`);
assert(uri.hostname.endsWith('.pooler.supabase.com'));
assert.equal(uri.pathname,'/postgres');
const env={...process.env,PGHOST:uri.hostname,PGPORT:'5432',PGDATABASE:'postgres',
  PGUSER:decodeURIComponent(uri.username),PGPASSWORD:decodeURIComponent(uri.password),
  PGSSLMODE:'require',PGCONNECT_TIMEOUT:'15'};

export function sql(consulta) {
  const r=spawnSync('/opt/homebrew/opt/postgresql@17/bin/psql',
    ['-X','-qAt','-v','ON_ERROR_STOP=1','-f','-'],
    {input:"set statement_timeout='180s';\n"+consulta,env,encoding:'utf8',maxBuffer:32*1024*1024});
  if(r.status!==0) {
    writeFileSync('/private/tmp/contratos-error-sql.txt',r.stderr||String(r.error),{mode:0o600});
    throw new Error((r.stderr||'').split('\n').filter(x=>x.includes('ERROR:')).join('\n')||'Fallo SQL; diagnóstico privado disponible');
  }
  return r.stdout.trim();
}

export async function http(ruta,{token,admin=false,method='POST',body,headers={}}={}) {
  assert(ruta.startsWith('/')&&!ruta.startsWith('//'));
  const r=await fetch(cfg.SUPABASE_URL+ruta,{method,headers:{
    apikey:cfg.SUPABASE_ANON_KEY,
    Authorization:`Bearer ${admin?cfg.SUPABASE_SERVICE_ROLE_KEY:token??cfg.SUPABASE_ANON_KEY}`,
    'Content-Type':'application/json',...headers},
    body:body===undefined?undefined:typeof body==='string'?body:JSON.stringify(body),
    redirect:'error',signal:AbortSignal.timeout(30000)});
  const texto=await r.text();let data;try{data=JSON.parse(texto);}catch{data=texto;}
  return {ok:r.ok,status:r.status,data};
}
export const rpc=(nombre,body,opciones={})=>http('/rest/v1/rpc/'+nombre,
  {body,...opciones,headers:{'Accept-Profile':'crm','Content-Profile':'crm'}});
