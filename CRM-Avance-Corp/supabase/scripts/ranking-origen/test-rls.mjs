// Gate focalizado: semilla-rama.sql + permisos reales por Auth/PostgREST.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const endpoint = new URL(process.env.SUPABASE_URL);
const ref = endpoint.hostname.split('.')[0];
assert.notEqual(ref, 'dctqcbznekcyxhjujuci', 'PRODUCCIÓN PROHIBIDA');
assert.equal(ref, process.env.CRM_RANKING_TEST_REF, 'Confirmar ref de banco');
assert.match(ref, /^[a-z]{20}$/);
const db = new URL(process.env.POSTGRES_URL);
assert.equal(db.username, `postgres.${ref}`);
const password = randomBytes(24).toString('base64url');
const key = process.env.SUPABASE_ANON_KEY;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
assert.ok(key && serviceKey);
const id = n => `b0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
async function request(path, body, token, extra = {}) {
  const response = await fetch(new URL(path, endpoint), {
    method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...extra },
    body: JSON.stringify(body), signal: AbortSignal.timeout(30000),
  });
  return { status: response.status, data: await response.json() };
}
async function login(n) {
  const updated = await fetch(new URL(`/auth/v1/admin/users/${id(n)}`, endpoint), {
    method: 'PUT', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ password, email_confirm: true }), signal: AbortSignal.timeout(30000),
  });
  assert.equal(updated.status, 200, `Configurar actor sintético ${n}`);
  const r = await request('/auth/v1/token?grant_type=password', { email: `ranking-${n}@example.test`, password }, key);
  assert.equal(r.status, 200, `Login sintético ${n}`);
  assert.equal(r.data.user.id, id(n));
  return r.data.access_token;
}
const rpc = token => request('/rest/v1/rpc/ranking_origen_vendedor_fn', { p_periodo: '2026-08-01', p_vendedor_id: id(2) }, token, { 'Content-Profile': 'crm' });
for (const [n, allowed] of [[3, true], [1, true], [4, false], [6, false], [7, false]]) {
  const token = await login(n);
  const r = await rpc(token);
  if (allowed) {
    assert.equal(r.status, 200, `RPC actor ${n}: ${JSON.stringify(r.data)}`);
    assert.equal(r.data.disponible, true);
    assert.equal(r.data.filas.find(f => f.origen === 'referido').conversion_pct, 15);
    assert.equal(r.data.filas.reduce((s, f) => s + f.capital_pen, 0), 12000);
  } else {
    assert.equal(r.status, 403, `Denegación actor ${n}`);
    assert.equal(r.data.code, '42501');
  }
  console.log(`PASS HTTP/Auth: actor ${n}, ${allowed ? 'desglose conciliado' : 'denegado'}`);
}
const anonymous = await rpc(key);
assert.ok([401, 403].includes(anonymous.status));
assert.equal(anonymous.data.code, '42501');
console.log('PASS HTTP: anónimo denegado');
const result = spawnSync(process.env.PSQL_BIN || 'psql', ['-Xq', '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
  input: readFileSync(new URL('./prueba-rama.sql', import.meta.url), 'utf8'), encoding: 'utf8', timeout: 180000,
  env: { ...process.env, PGHOST: db.hostname, PGPORT: '5432', PGDATABASE: db.pathname.slice(1), PGUSER: decodeURIComponent(db.username), PGPASSWORD: decodeURIComponent(db.password), PGSSLMODE: 'require' },
});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
assert.equal(result.status, 0, 'Gate SQL de cierre/conciliación/permisos');
console.log('PASS: matriz RLS focalizada de ranking por origen');
