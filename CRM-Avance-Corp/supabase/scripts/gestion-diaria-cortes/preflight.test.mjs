// Sólo checks offline de preparación. No acreditar con ellos SQL ni RLS real.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const leer = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');
const migracion = leer('../../migrations/20260921214018_crm_gestion_diaria_cortes.sql');
test('sin opciones sólo muestra candidato y huella, sin SQL', () => {
  const r = spawnSync(process.execPath, [fileURLToPath(new URL('./ensayar.mjs', import.meta.url))], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const p = JSON.parse(r.stdout);
  assert.equal(p.estado, 'PREPARADO_SIN_EJECUTAR_SQL');
  assert.equal(p.baseLocal, 'gestion_diaria_f4_vista_chvrqh');
  assert.match(p.sha256, /^[a-f0-9]{64}$/);
});
test('rechaza destino o modo no autorizado antes de conectarse', () => {
  for (const args of [['--produccion'], ['--ensayar-local', '--db', 'otra'], ['--preflight', 'otra']]) {
    const r = spawnSync(process.execPath, [fileURLToPath(new URL('./ensayar.mjs', import.meta.url)), ...args], { encoding: 'utf8' });
    assert.notEqual(r.status, 0);
    assert.match(r.stderr, /Modo no permitido|No acepta destinos/);
  }
});
test('candidato sellado, transaccional y sin DDL sobre public', () => {
  assert.match(migracion, /\nbegin;\n/);
  assert.match(migracion, /commit;\s*$/);
  assert.doesNotMatch(migracion, /__(?:MD5|SRC|RLS)_\w+__/);
  assert.doesNotMatch(migracion, /\b(?:alter|drop)\s+(?:table|function|policy)\s+public\./i);
});
test('sin contadores nuevos ni copia de la definición canónica', () => {
  assert.doesNotMatch(migracion, /\bcount\s*\(|\bsum\s*\(\s*1\s*\)/i);
  assert.doesNotMatch(migracion, /create(?: or replace)? function private\.gestion_diaria_llamadas/i);
  assert.match(migracion, /private\.gestion_diaria_llamadas\(v_ini, v_corte1/);
  assert.match(migracion, /private\.gestion_diaria_llamadas\(v_ini, coalesce\(v_corte2, v_ini\)/);
});
test('RLS y mínimos privilegios están presentes en el candidato', () => {
  assert.match(migracion, /alter table crm\.politica_gestion_diaria enable row level security/);
  assert.match(migracion, /revoke all on table crm\.politica_gestion_diaria from public, anon, authenticated, service_role/);
  assert.match(migracion, /grant select \(id, version,[\s\S]*?on crm\.politica_gestion_diaria to authenticated/);
  assert.doesNotMatch(migracion, /grant select on table crm\.politica_gestion_diaria/);
  assert.doesNotMatch(migracion, /create policy[^;]+for (insert|update|delete|all)/i);
});
test('oráculos se ejecutan sólo en copia exacta y terminan en rollback', () => {
  const sql = leer('./test-cortes.sql');
  assert.match(sql, /current_database\(\) <> 'gestion_diaria_f4_vista_chvrqh'/);
  assert.match(sql, /set local role authenticated/);
  assert.match(sql, /rollback;\s*$/);
  assert.doesNotMatch(sql, /\bcommit\s*;/i);
});
test('reversa rechaza versiones publicadas y se limita a objetos nuevos', () => {
  const sql = leer('./reversa.sql');
  assert.match(sql, /current_database\(\) <> 'gestion_diaria_f4_vista_chvrqh'/);
  assert.match(sql, /where version <> 1/);
  assert.doesNotMatch(sql, /\bcascade\b|drop table crm\.(?:leads|actividades|tareas)\b/i);
  assert.match(sql, /select private\.assert_gestion_diaria\(\)/);
});
