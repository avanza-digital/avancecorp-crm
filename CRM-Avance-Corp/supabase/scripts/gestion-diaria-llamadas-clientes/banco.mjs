// Banco PROPIO de esta tarea (regla de Miguel: trabajo aislado): un Postgres de Supabase
// (`public.ecr.aws/supabase/postgres:17.6.1.167`) cargado con el volcado de esquema de producción
// (`supabase db dump --linked --schema public,crm,private`, receta §5 de backfill-conversion-2026-09/LEEME.md),
// los roles de la casa, la configuración copiada (sin datos de personas) y la siembra mínima del banco.
// Nunca toca producción: fija contenedor y base. Huellas de las 22 funciones de Gestión Diaria/postventa
// medidas iguales a producción el 19/10/2026 antes de instalar nada.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
export const db = process.env.CRM_BANCO_DB ?? 'postgres';
export const contenedor = process.env.CRM_BANCO_CONTENEDOR ?? 'crm-banco-llamadas-clientes-20261019';
export const q = (x) => x === null ? 'null' : "'" + String(x).replaceAll("'", "''") + "'";
const NO_LLEGO_A_PSQL = /Cannot connect to the Docker daemon|error during connect|No such container/;
export function ejecutarEn(base, s, usuario = 'postgres') {
  let r;
  for (let intento = 1; intento <= 3; intento++) {
    r = spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', usuario, '-d', base, '-v', 'ON_ERROR_STOP=1', '-f', '-'],
      { input: '\\set VERBOSITY verbose\n' + s, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
    if (r.status === 0 || !NO_LLEGO_A_PSQL.test(r.stderr ?? '')) return r;
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2000 * intento);
  }
  return r;
}
export const ejecutar = (s) => ejecutarEn(db, s);
export function sql(s) { const r = ejecutar(s); assert.equal(r.status, 0, r.stderr || r.error?.message); return r.stdout.trim(); }
export const md5Vivo = (firma) => sql(`select coalesce(md5(pg_get_functiondef(to_regprocedure(${q(firma)}))), 'ausente')`);
export const existe = (firma) => sql(`select (to_regprocedure(${q(firma)}) is not null)::text`) === 'true';
