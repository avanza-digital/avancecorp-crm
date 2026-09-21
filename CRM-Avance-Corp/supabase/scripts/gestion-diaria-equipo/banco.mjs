// Destino fijo y exclusivo de F4. Nunca acepta URLs, credenciales ni producción.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
export const db = 'gestion_diaria_f4_vista_chvrqh';
export function ejecutar(texto) {
  return spawnSync('docker', ['exec', '-i', 'supabase_db_avancecorp-f5-bank', 'psql',
    '-X', '-qAt', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { input: texto, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
}
export function sql(texto) {
  const r = ejecutar(texto);
  assert.equal(r.status, 0, r.stderr || r.error?.message);
  return r.stdout.trim();
}
