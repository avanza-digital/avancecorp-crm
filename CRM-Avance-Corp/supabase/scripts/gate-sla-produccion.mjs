#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Consulta el proyecto linked en lectura; no aplica DDL ni activa SLA.
// La transacción read-only sólo emite OK si los siete asserts y el cierre pasan.
const cwd = fileURLToPath(new URL('../..', import.meta.url));
const result = spawnSync('npx', [
  'supabase', 'db', 'query', '--linked', '--file', 'supabase/scripts/trinquete-sla-produccion.sql',
], { cwd, encoding: 'utf8', timeout: 60_000 });
const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
const verdict = /"veredicto":\s*"(OK: SLA completo[^"\n]*)"/.exec(output)?.[1];
if (result.error || result.status !== 0 || !verdict) {
  console.error('Gate SLA completo sin veredicto válido. Requiere prerrequisito, N1/N2/N3 y cierre instalados.');
  console.error(result.error?.message ?? output.trim());
  process.exit(1);
}
console.log(verdict);
