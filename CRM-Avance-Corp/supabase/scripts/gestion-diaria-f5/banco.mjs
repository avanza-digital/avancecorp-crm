// Banco F5 local, separado de H3 y de las pruebas de otras tareas.
// Destino cerrado: no admite URL, base o credenciales desde argumentos/entorno.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

export const db = 'gestion_diaria_f5_20260924';
export const contenedor = 'supabase_db_avancecorp-f5-bank';
export const socket = 'unix:///Users/usuario/.docker/run/docker.sock';
export const marca = 'BANCO SINTETICO F5 20260924 / sin produccion';

export function ejecutar(texto) {
  return spawnSync('docker', ['--host', socket, 'exec', '-i', contenedor, 'psql',
    '-X', '-qAt', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
    input: `do $destino$ begin
      if current_database() <> '${db}' or shobj_description(
        (select oid from pg_database where datname=current_database()), 'pg_database')
        is distinct from '${marca}' then
        raise exception 'Destino ajeno al banco F5';
      end if;
    end $destino$;\n${texto}`,
  });
}

export function sql(texto) {
  const resultado = ejecutar(texto);
  assert.equal(resultado.status, 0, resultado.stderr || resultado.error?.message);
  return resultado.stdout.trim();
}
