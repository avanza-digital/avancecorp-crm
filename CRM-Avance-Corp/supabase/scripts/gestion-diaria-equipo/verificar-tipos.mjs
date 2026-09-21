// Generar desde LA COPIA donde está instalada F4. El comando gen:types del app
// apunta a producción, que todavía no tiene la nueva función: no reemplazar
// todas las declaraciones con una foto que omite esta entrega.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { db } from './banco.mjs';
const resultado = spawnSync('supabase', ['gen', 'types', 'typescript', '--db-url',
  `postgresql://postgres:postgres@127.0.0.1:58322/${db}`, '--schema', 'crm', '--query-timeout', '60s'],
{ encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
assert.equal(resultado.status, 0, resultado.stderr);
const firma = resultado.stdout.match(/gestion_diaria_equipo_fn: \{[\s\S]*?Returns: Json\s*\}/)?.[0];
assert.ok(firma, 'RPC presente en tipos generados de la base instalada');
assert.match(firma, /p_dia\?: string/);
assert.match(firma, /p_supervisor_id\?: string/);
const local = readFileSync(new URL('../../../app/src/lib/database.types.ts', import.meta.url), 'utf8');
assert.match(local, /gestion_diaria_equipo_fn: \{ Args: \{ p_dia\?: string \| null; p_supervisor_id\?: string \| null \}; Returns: Json \}/);
console.log('PASS: firma de F4 cotejada con Supabase gen types sobre la copia local; null explícito admite los defaults SQL.');
console.log(firma);
