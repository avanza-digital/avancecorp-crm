// Ejecuta el gate canónico COMPLETO por Auth/PostgREST, en el banco fijo.
// Un bloque de cortes ausente sólo es legítimo en la baseline ANTERIOR al SQL.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { carpeta, sql, credencialesLocales, verificarBanco } from './banco.mjs';

const [modo, ...otros] = process.argv.slice(2);
assert.ok(['--baseline','--candidato'].includes(modo) && otros.length === 0);
verificarBanco();
const instalado = sql("select to_regclass('crm.politica_gestion_diaria') is not null") === 't';
assert.equal(instalado, modo === '--candidato', 'La matriz no corresponde al estado del servidor');
const c = credencialesLocales();
const { password } = JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`, 'utf8'));
const secretos = [c.ANON_KEY,c.SERVICE_ROLE_KEY,c.DB_URL,password].filter(Boolean);
const sanear = t => secretos.reduce((texto,secreto) => texto.replaceAll(secreto,'[LOCAL_REDACTADO]'),t)
  .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,'[JWT_LOCAL_REDACTADO]');
const env = { PATH: process.env.PATH, TMPDIR: process.env.TMPDIR, LANG: process.env.LANG,
  TZ:'America/Lima', PGTZ:'America/Lima',
  SUPABASE_URL:c.API_URL,SUPABASE_ANON_KEY:c.ANON_KEY,SUPABASE_SERVICE_ROLE_KEY:c.SERVICE_ROLE_KEY,
  CRM_BANCO_PSQL_URL:c.DB_URL,CRM_DEMO_PASSWORD:password,
  ...(instalado ? { CRM_RLS_EXIGE_CORTES:'1' } : {}),
};
const inicio = new Date().toISOString();
const hijo = spawn(process.execPath, ['--import',fileURLToPath(new URL('./fetch-local.mjs',import.meta.url)),
  fileURLToPath(new URL('../../test-rls.mjs',import.meta.url))], { env,stdio:['ignore','pipe','pipe'] });
let salida = '';
for (const stream of [hijo.stdout,hijo.stderr]) stream.on('data',chunk => { salida += chunk; });
const estado = await new Promise(resolve => hijo.on('close',resolve));
const log = sanear(salida);
const etiqueta = modo.slice(2);
const historico = `matriz-${etiqueta}-${inicio.replace(/[^0-9]/g,'')}.log`;
writeFileSync(`${carpeta}/${historico}`,log,{mode:0o600,flag:'wx'});
writeFileSync(`${carpeta}/matriz-${etiqueta}.log`,log,{mode:0o600});
writeFileSync(`${carpeta}/matriz-${etiqueta}.json`,JSON.stringify({inicio,fin:new Date().toISOString(),
  estado:estado===0?'PASS':'FAIL',exit:estado,modo:etiqueta,api:c.API_URL,
  registro:historico},null,2)+'\n',{mode:0o600});
console.log(log.split('\n').filter(l=>/✗|❌|✅|SALTAD|saltado|error fatal/.test(l)).join('\n'));
verificarBanco();
process.exitCode = estado ?? 1;
