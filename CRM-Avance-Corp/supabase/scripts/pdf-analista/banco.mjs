// Destino fijo y marcador obligatorio: nunca admite producción ni una URL.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
const carpeta = new URL('./', import.meta.url);
const leer = (ruta) => readFileSync(new URL(ruta, carpeta), 'utf8');
const migracion = leer('../../migrations/20260930235814_crm_pdf_analista_asignado.sql');
const seguridad = `do $$ begin
 if current_database()<>'pdf_analista_20260930' or shobj_description(
 (select oid from pg_database where datname=current_database()),'pg_database')
 is distinct from 'BANCO SINTETICO PDF analista 20260930 / sin produccion'
 then raise exception 'Banco no autorizado'; end if; end $$;`;
const sql = seguridad + leer('fixture.sql') + '\n' + leer('antes.sql') + '\n'
  + migracion + '\n' + leer('despues.sql') + '\n' + leer('reversa.sql') + '\n'
  + migracion + '\nrollback;';
const r = spawnSync('docker', ['exec','-i','supabase_db_crm-avance-corp-local',
  'psql','-X','-qAt','-U','postgres','-d','pdf_analista_20260930',
  '-v','ON_ERROR_STOP=1','-f','-'], {input:sql,encoding:'utf8',maxBuffer:8*1024*1024});
assert.equal(r.status, 0, r.stderr || r.error?.message);
for (const linea of r.stdout.split('\n')) {
  if (linea.startsWith('SNAPSHOT:')) {
    writeFileSync('/private/tmp/crm-pdf-analista-snapshot.json', linea.slice(9)+'\n');
  } else if (linea.startsWith('PASS')) console.log(linea);
}
console.log('PASS: reversa y reaplicación, todo revertido con ROLLBACK');
