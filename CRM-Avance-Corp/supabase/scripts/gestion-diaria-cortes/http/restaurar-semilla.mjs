// Repetir la matriz desde su semilla exacta sin borrar el ensayo anterior.
// Exclusivo del banco sintético aprobado; nunca es una reversa de producción.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { carpeta, proyecto, contenedor, sql, docker, verificarBanco } from './banco.mjs';

assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
verificarBanco();
assert.equal(sql("select to_regclass('crm.politica_gestion_diaria') is null"),'t',
  'Restaurar semilla no ensaya la reversa del candidato; no ejecutarlo con F4 instalada');
const manifest = JSON.parse(readFileSync(`${carpeta}/semilla-base.json`));
const backup = readFileSync(`${carpeta}/semilla-base.dump`);
assert.equal(manifest.proyecto,proyecto);
assert.equal(manifest.candidato,false);
assert.equal(createHash('sha256').update(backup).digest('hex'),manifest.sha256);
const nueva = 'gd_f4_http_repeticion';
const historia = `gd_f4_http_ensayo_${Date.now()}`;
assert.equal(sql(`select count(*) from pg_database where datname in ('${nueva}','${historia}')`),'0');
const socket = 'unix:///Users/usuario/.docker/run/docker.sock';
function ejecutar(args,input) {
  const r = spawnSync('docker',['--host',socket,...args],{input,encoding:'utf8',maxBuffer:16*1024*1024});
  if(r.status!==0) throw new Error((r.stderr??'').split('\n').filter(l=>/ERROR:|FATAL:|pg_restore: error:/.test(l)).join('\n')||'Restauración local falló');
  return r.stdout.trim();
}
const psql = (db,input) => ejecutar(['exec','-i',contenedor,'psql','-XqAt','-U','supabase_admin','-d',db,
  '-v','ON_ERROR_STOP=1','-f','-'],input);
psql('postgres',`create database ${nueva} with template template0 owner postgres;`);
ejecutar(['exec','-i',contenedor,'pg_restore','-U','supabase_admin','-d',nueva,'--exit-on-error','--single-transaction'],backup);
psql(nueva,`comment on database ${nueva} is 'BANCO SINTETICO gestion-diaria-f4-http / sin produccion';
  grant select,update on sequence crm.usuario_eventos_id_seq,private.ayuda_consultas_id_seq,
    private.ayuda_expresiones_id_seq,private.ayuda_intenciones_id_seq,private.ayuda_reglas_aclaracion_id_seq to postgres;`);
assert.equal(psql(nueva,'select count(*) from auth.users'),'13');
assert.equal(psql(nueva,'select count(*) from crm.leads'),'7');
assert.equal(psql(nueva,"select to_regclass('crm.politica_gestion_diaria') is null"),'t');
const servicios = ['auth','rest','kong','storage','inbucket'].map(s=>`supabase_${s}_${proyecto}`);
docker(['stop',...servicios]);
psql('template1',`select pg_terminate_backend(pid) from pg_stat_activity where datname='postgres' and pid<>pg_backend_pid();
  alter database postgres rename to ${historia}; alter database ${nueva} rename to postgres;`);
docker(['start',...servicios]);
// Cada nuevo namespace de red necesita retirar de nuevo su ruta por defecto.
const aislado = spawnSync(process.execPath,[fileURLToPath(new URL('./aislar-egreso.mjs',import.meta.url)),
  '--solo-banco-autorizado'],{encoding:'utf8',timeout:60_000});
assert.equal(aislado.status,0,'Servicios reiniciados: ejecutar aislamiento antes de usar el banco');
verificarBanco();
console.log(`PASS: semilla exacta restaurada y aislada; ensayo previo conservado en ${historia}`);
