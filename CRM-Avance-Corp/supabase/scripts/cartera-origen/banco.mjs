// Copia sintética propia en el contenedor local: no acepta URLs, credenciales
// ni destinos externos. Mismo patrón que cartera-filtros/banco.mjs.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
export const db = 'cartera_origen_20260916', contenedor = 'supabase_db_avancecorp-f5-bank';
export const q = (x) => x === null ? 'null' : "'" + String(x).replaceAll("'", "''") + "'";
export function ejecutar(s) {
  return spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'],
    { input: '\\set VERBOSITY verbose\n' + s, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
}
export function sql(s) { const r = ejecutar(s); assert.equal(r.status, 0, r.stderr || r.error?.message); return r.stdout.trim(); }
export const objeto = (s) => JSON.parse(sql(s));
export const claims = (actor) => `set local request.jwt.claim.sub=${q(actor)};set local role authenticated;`;
/** Una lectura como `actor`, dentro de una transacción deshecha. */
export function consulta(s, actor, antes = '') {
  return objeto(`begin;set local statement_timeout='15s';${antes}${claims(actor)}select ${s};rollback;`);
}
