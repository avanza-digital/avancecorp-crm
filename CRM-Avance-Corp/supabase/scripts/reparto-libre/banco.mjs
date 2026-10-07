// Banco sintético exclusivo. No acepta URL ni destinos externos.
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

export const db = 'reparto_libre_20261007'
export const contenedor = 'supabase_db_crm-avance-corp-local'
export const marca = 'BANCO SINTETICO reparto libre Rosa 20261007 / sin produccion'
export const migracion = '../../migrations/20261007143121_crm_reparto_libre_coordinacion_configurable.sql'

export function sql(texto) {
  const r = spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt',
    '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
    input: `do $$ begin
      if current_database() <> '${db}' or shobj_description(
        (select oid from pg_database where datname=current_database()), 'pg_database')
        is distinct from '${marca}' then raise exception 'Banco de reparto incorrecto'; end if;
      end $$;\n${texto}`,
  })
  assert.equal(r.status, 0, (r.stderr || r.error?.message || '') + '\n' + r.stdout)
  return r.stdout.trim()
}

if (process.argv[2] === 'instalar') {
  console.log(sql(readFileSync(new URL(migracion, import.meta.url), 'utf8')))
  console.log('PASS: migración instalada solo en el banco de reparto')
} else if (process.argv[2] === 'probar') {
  console.log(sql(readFileSync(new URL('./test.sql', import.meta.url), 'utf8')))
} else if (process.argv[2] === 'consulta') {
  console.log(sql(readFileSync(0, 'utf8')))
}
