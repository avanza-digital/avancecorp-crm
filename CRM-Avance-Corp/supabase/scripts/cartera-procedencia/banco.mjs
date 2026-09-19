// Copia sintética propia en el contenedor local: no acepta URLs, credenciales
// ni destinos externos. Mismo patrón que cartera-origen/banco.mjs, con un
// reintento acotado cuando el DAEMON de Docker responde 500 antes de llegar a
// psql (visto el 19/09): en ese caso no se ejecutó nada, así que repetir es seguro.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
export const db = 'cartera_procedencia_20260919', contenedor = 'supabase_db_avancecorp-f5-bank';
export const q = (x) => x === null ? 'null' : "'" + String(x).replaceAll("'", "''") + "'";
const NO_LLEGO_A_PSQL = /500 Internal Server Error for API route|Cannot connect to the Docker daemon|error during connect/;
export function ejecutar(s) {
  let r;
  for (let intento = 1; intento <= 4; intento++) {
    r = spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'],
      { input: '\\set VERBOSITY verbose\n' + s, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
    if (r.status === 0 || !NO_LLEGO_A_PSQL.test(r.stderr ?? '')) return r;
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 3000 * intento);
  }
  return r;
}
export function sql(s) { const r = ejecutar(s); assert.equal(r.status, 0, r.stderr || r.error?.message); return r.stdout.trim(); }
export const objeto = (s) => JSON.parse(sql(s));
export const claims = (actor) => `set local request.jwt.claim.sub=${q(actor)};set local role authenticated;`;
/** Una lectura como `actor`, dentro de una transacción deshecha. */
export function consulta(s, actor, antes = '') {
  return objeto(`begin;set local statement_timeout='15s';${antes}${claims(actor)}select ${s};rollback;`);
}
