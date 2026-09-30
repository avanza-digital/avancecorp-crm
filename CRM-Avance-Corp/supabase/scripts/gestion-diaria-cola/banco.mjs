// Banco propio de esta tarea. No acepta destinos ni credenciales externos.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

export const db = 'gestion_diaria_cola_20260930';
export const contenedor = 'avancecorp-gd-cola-20260930-pg167';
export const marca = 'BANCO SINTETICO Gestion diaria cola 20260930 / sin produccion';
export const q = (v) => v === null ? 'null' : "'" + String(v).replaceAll("'", "''") + "'";

export function ejecutar(texto) {
  return spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt',
    '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
    input: `do $destino$ begin
      if current_database() <> '${db}' or shobj_description(
        (select oid from pg_database where datname=current_database()), 'pg_database')
        is distinct from '${marca}' then raise exception 'Banco ajeno a Gestion diaria cola'; end if;
      end $destino$;\n${texto}`,
  });
}
export function sql(texto) {
  const r = ejecutar(texto);
  assert.equal(r.status, 0, r.stderr || r.error?.message);
  return r.stdout.trim();
}
export const objeto = (texto) => JSON.parse(sql(texto));
