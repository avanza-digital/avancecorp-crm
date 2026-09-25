import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { sql } from './banco.mjs';
import { sql as sqlH3 } from '../gestion-diaria-horizontal/banco.mjs';

const firma = 'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])';
// H3 conserva el núcleo publicado. Si cambia, no inventar otra referencia.
assert.equal(sqlH3(`select md5(pg_get_functiondef('${firma}'::regprocedure))`), '45e6e7a82c54b2f15110b828ba70761d');
const base = sqlH3(`select pg_get_functiondef('${firma}'::regprocedure)`)
  .replace('FUNCTION private.gestion_diaria_llamadas(', 'FUNCTION pg_temp.llamadas_base(');
assert.ok(base.includes('FUNCTION pg_temp.llamadas_base('));
sql(readFileSync(new URL('../../migrations/20260924201358_crm_gestion_diaria_pulso_habitos.sql', import.meta.url), 'utf8'));
const ensayo = readFileSync(new URL('./test-pulso-habitos.sql', import.meta.url), 'utf8')
  .replace('-- NUCLEO_BASE', `${base};\ngrant execute on function pg_temp.llamadas_base(timestamptz,timestamptz,uuid[]) to authenticated;`);
console.log(sql(ensayo).split('\n').filter((linea) => linea.startsWith('PASS:')).join('\n'));
