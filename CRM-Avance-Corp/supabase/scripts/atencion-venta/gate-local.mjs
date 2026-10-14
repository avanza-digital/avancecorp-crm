// Matriz oficial sobre el banco exclusivo de esta tarea. Nunca acepta una URL.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, existsSync, openSync, closeSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
const carpeta = '/private/tmp/avancecorp-atencion-rls-20261013';
const contenedor = 'supabase_db_avancecorp-atencion-rls-20261013';
const modo = process.argv[2];
assert(['semilla','matriz'].includes(modo));
const cfg = JSON.parse(readFileSync(`${carpeta}/status.json`, 'utf8'));
assert.equal(cfg.API_URL, 'http://127.0.0.1:56561');
assert.equal(cfg.DB_URL, 'postgresql://postgres:postgres@127.0.0.1:56562/postgres');
assert.equal(JSON.parse(Buffer.from(cfg.SERVICE_ROLE_KEY.split('.')[1], 'base64url')).iss, 'supabase-demo');
const clave = `${carpeta}/clave-demo.txt`;
if (!existsSync(clave)) writeFileSync(clave, randomBytes(24).toString('base64url'), {mode:0o600});
const env = {...process.env, SUPABASE_URL:cfg.API_URL, SUPABASE_ANON_KEY:cfg.ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY:cfg.SERVICE_ROLE_KEY, CRM_BANCO_PSQL_URL:cfg.DB_URL,
  CRM_DEMO_PASSWORD:readFileSync(clave,'utf8')};
function sql(input) {
  const r=spawnSync('docker',['exec','-i',contenedor,'psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],
    {input,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);
  return r.stdout.trim();
}
function correr(script, nombre) {
  const fd=openSync(`${carpeta}/${nombre}.log`,'w',0o600);
  const r=spawnSync(process.execPath,[script],{env,stdio:['ignore',fd,fd]});
  closeSync(fd);
  console.log(`${nombre}: ${r.status===0?'PASS':'FAIL'} (exit ${r.status}); ${carpeta}/${nombre}.log`);
  assert.equal(r.status,0,`Consultar ${nombre}.log; no se sustituyen errores por aprobación`);
}
if (modo==='semilla') {
  assert.equal(sql('select count(*) from public.perfiles'), '0', 'La semilla exige banco nuevo; no limpia otro trabajo');
  sql('grant select on crm.periodos_cerrados to service_role;');
  try { correr('supabase/scripts/seed-demo.mjs','semilla'); }
  finally { sql('revoke select on crm.periodos_cerrados from service_role;'); }
  sql(readFileSync(new URL('../banco/baja-historica-vendinactive.sql',import.meta.url),'utf8'));
} else correr('supabase/scripts/test-rls.mjs','matriz');
