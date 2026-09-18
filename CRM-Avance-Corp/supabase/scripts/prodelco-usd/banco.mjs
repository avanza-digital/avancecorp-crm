// Copia sintética propia en el contenedor local: no acepta URLs, credenciales
// ni destinos externos. Mismo patrón que cartera-origen/banco.mjs.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
export const db = 'prodelco_usd_20260917';
export const plantilla = 'cartera_origen_20260916';
export const contenedor = 'supabase_db_avancecorp-f5-bank';
export const q = (x) => (x === null ? 'null' : "'" + String(x).replaceAll("'", "''") + "'");
/** psql como `postgres` (el dueño de los objetos del CRM), sobre la copia. */
export function ejecutar(s, { usuario = 'postgres', base = db } = {}) {
  return spawnSync(
    'docker',
    ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', usuario, '-d', base, '-v', 'ON_ERROR_STOP=1', '-f', '-'],
    { input: '\\set VERBOSITY verbose\n' + s, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 },
  );
}
export function sql(s, opciones = {}) {
  const r = ejecutar(s, opciones);
  assert.equal(r.status, 0, r.stderr || r.error?.message);
  return r.stdout.trim();
}
export const objeto = (s, opciones = {}) => JSON.parse(sql(s, opciones));
/** Ejecuta y EXIGE fallo con un mensaje concreto, dentro de una tx deshecha. */
export function debeFallar(script, patron, motivo) {
  const r = ejecutar(`begin;\n${script}\nrollback;`);
  assert.notEqual(r.status, 0, `Debió fallar: ${motivo}`);
  assert.match(r.stderr, patron, `Falló por otra causa (${motivo}): ${r.stderr.slice(0, 400)}`);
}
