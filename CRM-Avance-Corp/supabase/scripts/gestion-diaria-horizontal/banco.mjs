// Banco H3 local y aislado. No acepta URL, proyecto ni base por entorno.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

export const db = 'gestion_diaria_h3_20260923';
export const contenedor = 'supabase_db_avancecorp-f5-bank';
export const socket = 'unix:///Users/usuario/.docker/run/docker.sock';
export function ejecutar(texto) {
  return spawnSync('docker', ['--host', socket, 'exec', '-i', contenedor, 'psql',
    '-X', '-qAt', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
    input: `do $destino$ begin
      if current_database() <> '${db}' or shobj_description(
        (select oid from pg_database where datname=current_database()), 'pg_database')
        is distinct from 'BANCO SINTETICO H3 20260923 / sin produccion' then
        raise exception 'Destino ajeno al banco H3';
      end if;
    end $destino$;\n${texto}`,
  });
}
export function sql(texto) {
  const r = ejecutar(texto);
  assert.equal(r.status, 0, r.stderr || r.error?.message);
  return r.stdout.trim();
}
