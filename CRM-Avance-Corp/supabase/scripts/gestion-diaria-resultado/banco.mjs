// Copia sintética propia en el contenedor local del banco: no acepta URLs,
// credenciales ni destinos externos. Mismo patrón que gestion-diaria/banco.mjs.
// La copia nace de `conversion_inversion_base_20260919` (a paridad con
// producción al 19/09: mundo SLA con cerrar_reunion_v3, reabrir_lead_fn,
// marcar_no_contactar y los md5 que pinna el preflight) y recibe antes el
// historial por lead (20260919185718) y la Fase 1 (20260919211958).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
export const db = 'gestion_diaria_f2_20260919', plantilla = 'conversion_inversion_base_20260919', contenedor = 'supabase_db_avancecorp-f5-bank';
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
/** Crea la copia desde la plantilla si no existe (idempotente). Las copias nacen
 *  como supabase_admin (dueño de la plantilla); los ensayos corren como postgres. */
export function asegurarCopia() {
  const existe = ejecutarEn('postgres', `select 1 from pg_database where datname=${q(db)}`).stdout.trim() === '1';
  if (existe) return false;
  const r = ejecutarEn('postgres', `create database ${db} template ${plantilla};`, 'supabase_admin');
  assert.equal(r.status, 0, r.stderr);
  return true;
}
