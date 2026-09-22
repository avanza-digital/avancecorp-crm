import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { carpeta, contenedor, sql, verificarBanco } from './banco.mjs';

assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
verificarBanco();
assert.equal(sql('select count(*) from auth.users'),'13');
assert.equal(sql('select count(*) from crm.leads'),'7');
assert.equal(sql("select to_regclass('crm.politica_gestion_diaria') is null"),'t');
const r = spawnSync('docker',['--host','unix:///Users/usuario/.docker/run/docker.sock','exec',contenedor,
  'pg_dump','-U','supabase_admin','-d','postgres','-Fc'],{maxBuffer:96*1024*1024});
assert.equal(r.status,0,'No se pudo guardar la semilla local');
writeFileSync(`${carpeta}/semilla-base.dump`,r.stdout,{mode:0o600,flag:'wx'});
writeFileSync(`${carpeta}/semilla-base.json`,JSON.stringify({proyecto:'gestion-diaria-f4-http',
  fecha:new Date().toISOString(),sha256:createHash('sha256').update(r.stdout).digest('hex'),
  auth:13,leads:7,candidato:false},null,2)+'\n',{mode:0o600,flag:'wx'});
console.log('PASS: semilla limpia conservada en respaldo privado; no se imprimen credenciales');
