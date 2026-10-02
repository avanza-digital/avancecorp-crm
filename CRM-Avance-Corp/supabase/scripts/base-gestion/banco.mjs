// Banco sintético exclusivo de «Base para gestión»; no recibe URL, credenciales ni destino externo.
// Uso: node supabase/scripts/base-gestion/banco.mjs crear | aplicar | test | reversa-y-reaplicar
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
export const db = 'base_gestion_20261002';
export const plantilla = 'conversion_tipos_v3_20260927';
export const contenedor = 'supabase_db_crm-avance-corp-local';
export const sello = 'BANCO SINTETICO base gestion 20261002 / sin produccion';
const migracion = new URL('../../migrations/20261002054402_crm_base_gestion_esquema.sql', import.meta.url);
function psql(base, texto, { candado = true } = {}) {
  const guardia = candado ? `do $$ begin if current_database()<>'${db}' or shobj_description(
      (select oid from pg_database where datname=current_database()),'pg_database')
      is distinct from '${sello}' then raise exception 'Banco de base gestion no autorizado'; end if; end $$;\n` : '';
  const r = spawnSync('docker', ['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres',
    '-d',base,'-v','ON_ERROR_STOP=1','-f','-'], {encoding:'utf8',maxBuffer:8*1024*1024, input: guardia + texto});
  assert.equal(r.status,0,(r.stderr || r.error?.message || '') + '\n' + (r.stdout || ''));
  if (process.argv[2]==='test' || process.argv[2]==='aplicar') process.stderr.write(r.stderr);
  return r.stdout.trim();
}
export const sql = (texto) => psql(db, texto);
const orden = process.argv[2];
if (orden==='crear') {
  const existe = psql('postgres', `select 1 from pg_database where datname='${db}'`, {candado:false});
  assert.equal(existe, '', `La base ${db} ya existe; usa test o reversa-y-reaplicar`);
  psql('postgres', `create database ${db} template ${plantilla};`, {candado:false});
  psql('postgres', `comment on database ${db} is '${sello}';`, {candado:false});
  console.log(`PASS: ${db} creada desde ${plantilla} y sellada`);
}
if (orden==='aplicar') { sql(readFileSync(migracion,'utf8')); console.log('PASS: migración aplicada en el banco'); }
if (orden==='test') console.log(sql(readFileSync(new URL('./test.sql',import.meta.url),'utf8')));
if (orden==='reversa-y-reaplicar') {
  sql(readFileSync(new URL('./reversa-esquema.sql',import.meta.url),'utf8'));
  assert.equal(sql("select to_regprocedure('private.base_gestion_constantes()') is null"),'t');
  sql(readFileSync(migracion,'utf8'));
  console.log('PASS: reversa y reaplicación con preflight en banco sintético');
}
if (!['crear','aplicar','test','reversa-y-reaplicar'].includes(orden)) {
  console.error('Uso: banco.mjs crear | aplicar | test | reversa-y-reaplicar'); process.exit(2);
}
