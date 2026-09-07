#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Mismo canal de consulta que los gates del proyecto. Un codigo 0 de CLI
// no basta: exige el veredicto SQL, porque los errores pueden viajar en JSON.
const cwd = fileURLToPath(new URL('../..', import.meta.url));
const result = spawnSync('npx', [
  'supabase', 'db', 'query', '--linked', '--file', 'supabase/scripts/trinquete-sla-nucleo.sql',
], { cwd, encoding: 'utf8', timeout: 60_000 });
const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
const verdict = /"veredicto":\s*"(OK:[^"\n]*)"/.exec(output)?.[1];
if (result.error || result.status !== 0 || !verdict) {
  console.error('Gate SLA sin veredicto valido. Requiere la migracion N1 instalada.');
  console.error(result.error?.message ?? output.trim());
  process.exit(1);
}
console.log(verdict);
