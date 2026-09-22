// Cotejo focal con la generación REAL de la copia autorizada, sin reemplazar
// tipos de otros módulos con una foto local que pudiera estar desactualizada.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { baseLocal, sqlLocal } from './banco.mjs';
assert.equal(sqlLocal("select to_regclass('crm.politica_gestion_diaria') is not null"), 't', 'Instalar candidato antes del cotejo');
const r = spawnSync('supabase', ['gen', 'types', 'typescript', '--db-url',
  `postgresql://postgres:postgres@127.0.0.1:58322/${baseLocal}`, '--schema', 'crm', '--query-timeout', '60s'],
{ encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
assert.equal(r.status, 0, r.stderr);
const extraer = (s) => s.match(/      politica_gestion_diaria: \{[\s\S]*?\n      \}/)?.[0];
const generado = extraer(r.stdout);
assert.ok(generado, 'La generación incluye la nueva política');
const local = readFileSync(new URL('../../../app/src/lib/database.types.ts', import.meta.url), 'utf8');
assert.equal(extraer(local), generado, 'El tipo de la tabla coincide exactamente con PostgreSQL');
const firma = r.stdout.match(/gestion_diaria_equipo_fn: \{[\s\S]*?Returns: Json\s*\}/)?.[0];
assert.match(firma ?? '', /p_dia\?: string/);
assert.match(firma ?? '', /p_supervisor_id\?: string/);
assert.match(local, /gestion_diaria_equipo_fn: \{ Args: \{ p_dia\?: string \| null; p_supervisor_id\?: string \| null \}; Returns: Json \}/);
console.log('PASS: tipos generados locales; tabla exacta y firma RPC compatible');
