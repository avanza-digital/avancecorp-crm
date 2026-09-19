// Banco remoto exclusivo autorizado el 19/09/2026. Nunca acepta producción.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
export const ref='omdgdbsbsabisykekziu';
export const carpeta='/private/tmp/avancecorp-conversion-inversion/remoto';
export const cfg=JSON.parse(readFileSync('/private/tmp/avancecorp-conversion-inversion/rama-privada.json','utf8'));
export const apiUrl=`https://${ref}.supabase.co`;
assert.equal(cfg.SUPABASE_URL,apiUrl);
const uri=new URL(cfg.POSTGRES_URL);
assert.equal(decodeURIComponent(uri.username),`postgres.${ref}`);
assert(uri.hostname.endsWith('.pooler.supabase.com'));
assert.equal(uri.pathname,'/postgres');
export const psql='/opt/homebrew/opt/postgresql@17/bin/psql';
export const env={...process.env,PGHOST:uri.hostname,PGPORT:'5432',PGDATABASE:'postgres',
  PGUSER:decodeURIComponent(uri.username),PGPASSWORD:decodeURIComponent(uri.password),
  PGSSLMODE:'require',PGCONNECT_TIMEOUT:'15'};
export const q=x=>x===null?'null':"'"+String(x).replaceAll("'","''")+"'";
export function sql(input){
  const r=spawnSync(psql,['-X','-qAt','-v','ON_ERROR_STOP=1','-f','-'],
    {input:"set statement_timeout='180s';\n"+input,env,encoding:'utf8',maxBuffer:32*1024*1024});
  if(r.status!==0){
    writeFileSync(carpeta+'/error-sql-privado.txt',r.stderr||String(r.error),{mode:0o600});
    throw new Error((r.stderr||'').split('\n').filter(x=>x.includes('ERROR:')).join('\n')||'Fallo SQL del banco; diagnóstico privado disponible.');
  }
  return r.stdout.trim();
}
export const objeto=s=>JSON.parse(sql(s));
export const inicio={ANON_KEY:cfg.SUPABASE_ANON_KEY,SERVICE_ROLE_KEY:cfg.SUPABASE_SERVICE_ROLE_KEY};
export const fixture=existsSync(carpeta+'/fixture.json')?JSON.parse(readFileSync(carpeta+'/fixture.json','utf8')):null;
export async function http(ruta,{token,admin=false,body,rawBody,method='POST',headers={}}={}){
  assert(ruta.startsWith('/')&&!ruta.startsWith('//'));
  const r=await fetch(apiUrl+ruta,{method,headers:{apikey:inicio.ANON_KEY,
    Authorization:`Bearer ${admin?inicio.SERVICE_ROLE_KEY:token??inicio.ANON_KEY}`,
    'Content-Type':'application/json',...headers},
    ...(body===undefined?{}:{body:JSON.stringify(body)}),...(rawBody===undefined?{}:{body:rawBody}),
    redirect:'error',signal:AbortSignal.timeout(30_000)});
  const texto=await r.text();let data;try{data=JSON.parse(texto);}catch{data=texto;}
  return {ok:r.ok,status:r.status,data};
}
export const rpc=(nombre,body,token)=>http(`/rest/v1/rpc/${nombre}`,{token,body,headers:{'Accept-Profile':'crm','Content-Profile':'crm'}});
export async function como(rol){
  const u=fixture.usuarios[rol];assert(u);
  const r=await http('/auth/v1/token?grant_type=password',{body:{email:u.email,password:fixture.password}});
  assert.equal(r.ok,true,`Login sintético ${rol}: HTTP ${r.status}`);
  assert.equal(r.data.user.id,u.id);return r.data.access_token;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  assert(process.argv[2],'Indica el archivo SQL para el banco fijo.');
  console.log(sql(readFileSync(process.argv[2],'utf8')));
}
