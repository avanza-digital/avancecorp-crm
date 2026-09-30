// Banco sintético exclusivo; no recibe URL, credenciales ni destino externo.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
export const db = 'lead_documentos_20260930';
export const contenedor = 'supabase_db_crm-avance-corp-local';
export function sql(texto) {
  const r = spawnSync('docker', ['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres',
    '-d',db,'-v','ON_ERROR_STOP=1','-f','-'], {encoding:'utf8',maxBuffer:8*1024*1024,
    input:`do $$ begin if current_database()<>'${db}' or shobj_description(
      (select oid from pg_database where datname=current_database()),'pg_database')
      is distinct from 'BANCO SINTETICO documentos lead 20260930 / sin produccion'
      then raise exception 'Banco de documentos no autorizado'; end if; end $$;\n${texto}`});
  assert.equal(r.status,0,r.stderr || r.error?.message);
  if (process.argv[2]==='test') process.stderr.write(r.stderr);
  return r.stdout.trim();
}
if (process.argv[2]==='test') console.log(sql(readFileSync(new URL('./test.sql',import.meta.url),'utf8')));
if (process.argv[2]==='reversa-y-reaplicar') {
  sql(readFileSync(new URL('./reversa.sql',import.meta.url),'utf8'));
  assert.equal(sql("select to_regprocedure('crm.documento_lead_fn(uuid)') is null"),'t');
  sql(readFileSync(new URL('../../migrations/20260930193325_crm_documentos_lead.sql',import.meta.url),'utf8'));
  console.log('PASS: reversa y reaplicación con preflight en banco sintético');
}
