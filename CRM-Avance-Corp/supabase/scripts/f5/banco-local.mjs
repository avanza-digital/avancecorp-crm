// Banco cerrado F5: nunca recibe URL, clave, contenedor ni DB del llamador.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

export const banco = '/private/tmp/avancecorp-f5-bank';
export const contenedor = 'supabase_db_avancecorp-f5-bank';
export const apiUrl = 'http://127.0.0.1:58321';
const inicio = JSON.parse(readFileSync(`${banco}/start.log`, 'utf8'));
assert.equal(inicio.API_URL, apiUrl);
assert.equal(inicio.DB_URL, 'postgresql://postgres:postgres@127.0.0.1:58322/postgres');
assert.equal(JSON.parse(Buffer.from(inicio.SERVICE_ROLE_KEY.split('.')[1], 'base64url')).iss, 'supabase-demo');

export const literal = valor => valor === null ? 'null' : `'${String(valor).replaceAll("'", "''")}'`;
export const jsonSql = valor => `${literal(JSON.stringify(valor))}::jsonb`;
export const leer = nombre => {
  assert(/^[a-z0-9-]+\.json$/.test(nombre));
  return JSON.parse(readFileSync(`${banco}/${nombre}`, 'utf8'));
};
export const guardar = (nombre, dato) => {
  assert(/^[a-z0-9-]+\.json$/.test(nombre));
  writeFileSync(`${banco}/${nombre}`, `${JSON.stringify(dato, null, 2)}\n`, {mode: 0o600});
};
export function sql(texto, {admin = false} = {}) {
  const r = spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt',
    '-U', admin ? 'supabase_admin' : 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  {input: `set timezone='America/Lima';\n${texto}\n`, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  assert.equal(r.status, 0, r.stderr || r.error?.message || 'Falló SQL del banco F5');
  return r.stdout.trim();
}
export async function http(ruta, {token, admin=false, body, rawBody, binary=false, method='POST', headers={}} = {}) {
  assert(ruta.startsWith('/') && !ruta.startsWith('//'));
  assert(body === undefined || rawBody === undefined);
  const r = await fetch(`${apiUrl}${ruta}`, {method,
    headers: {apikey: inicio.ANON_KEY, Authorization: `Bearer ${admin ? inicio.SERVICE_ROLE_KEY : token ?? inicio.ANON_KEY}`,
      'Content-Type': 'application/json', ...headers},
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
    ...(rawBody === undefined ? {} : {body: rawBody}),
    redirect: 'error', signal: AbortSignal.timeout(30_000)});
  if (binary && r.ok) return {status: r.status, ok: true, data: Buffer.from(await r.arrayBuffer())};
  const texto = await r.text();
  let data;
  try { data = JSON.parse(texto); } catch { data = texto; }
  return {status: r.status, ok: r.ok, data};
}
export const rpc = (nombre, payload, token) => {
  assert(/^[a-z_][a-z0-9_]*$/.test(nombre));
  return http(`/rest/v1/rpc/${nombre}`, {token, body: payload,
    headers: {'Accept-Profile': 'crm', 'Content-Profile': 'crm'}});
};
export async function sesion(usuario, password) {
  const r = await http('/auth/v1/token?grant_type=password', {body: {email: usuario.email,password}});
  assert.equal(r.ok, true, `Login sintético F5: HTTP ${r.status}`);
  assert.equal(r.data.user.id, usuario.id);
  return r.data.access_token;
}
export async function como(rol) {
  const f = leer('fixtures.json');
  assert(f.usuarios[rol], 'Rol de fixture desconocido');
  return sesion(f.usuarios[rol], f.password);
}
