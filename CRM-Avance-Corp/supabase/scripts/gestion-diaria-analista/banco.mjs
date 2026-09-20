// Copia sintética propia en el contenedor local del banco: no acepta URLs,
// credenciales ni destinos externos. Mismo patrón que gestion-diaria-resultado/banco.mjs.
// La copia nace, si existe, de la copia del ensayo de F2 (`gestion_diaria_f2_20260919`
// = plantilla `conversion_inversion_base_20260919` + historial por lead + F1 + F2,
// con una llamada confirmada); si no, de la plantilla base. ensayar.mjs instala
// después lo que falte para estar a paridad con producción al 20/09/2026.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
export const db = 'gestion_diaria_f3_20260920';
export const plantillas = ['gestion_diaria_f2_20260919', 'conversion_inversion_base_20260919'];
export const contenedor = 'supabase_db_avancecorp-f5-bank';
export const q = (x) => x === null ? 'null' : "'" + String(x).replaceAll("'", "''") + "'";
const NO_LLEGO_A_PSQL = /500 Internal Server Error for API route|Cannot connect to the Docker daemon|error during connect/;
export function ejecutarEn(base, s, usuario = 'postgres') {
  let r;
  for (let intento = 1; intento <= 4; intento++) {
    r = spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', usuario, '-d', base, '-v', 'ON_ERROR_STOP=1', '-f', '-'],
      { input: '\\set VERBOSITY verbose\n' + s, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
    if (r.status === 0 || !NO_LLEGO_A_PSQL.test(r.stderr ?? '')) return r;
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 3000 * intento);
  }
  return r;
}
export const ejecutar = (s) => ejecutarEn(db, s);
export function sql(s) { const r = ejecutar(s); assert.equal(r.status, 0, r.stderr || r.error?.message); return r.stdout.trim(); }
export const objeto = (s) => JSON.parse(sql(s));
/** Crea la copia desde la primera plantilla existente si no existe (idempotente).
 *  Las copias nacen como supabase_admin (dueño de la plantilla); los ensayos
 *  corren como postgres. Devuelve la plantilla usada o null si ya existía. */
export function asegurarCopia() {
  const existe = (nombre) => ejecutarEn('postgres', `select 1 from pg_database where datname=${q(nombre)}`).stdout.trim() === '1';
  if (existe(db)) return null;
  const plantilla = plantillas.find(existe);
  assert.ok(plantilla, `ninguna plantilla disponible (${plantillas.join(', ')})`);
  const r = ejecutarEn('postgres', `create database ${db} template ${plantilla};`, 'supabase_admin');
  assert.equal(r.status, 0, r.stderr);
  return plantilla;
}
