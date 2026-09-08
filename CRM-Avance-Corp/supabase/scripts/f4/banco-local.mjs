// Herramientas del oráculo F4. Deliberadamente no acepta proyectos remotos.
import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import assert from 'node:assert/strict';

export const banco = '/private/tmp/avancecorp-f4-bank';
export const contenedor = 'supabase_db_avancecorp-f4-bank';
const inicio = readFileSync(join(banco, 'start.log'), 'utf8').split('\n')
  .filter(linea => linea.startsWith('{')).map(linea => JSON.parse(linea))
  .find(dato => dato.API_URL && dato.SERVICE_ROLE_KEY);
assert(inicio, 'Primero debe arrancarse el banco local F4');
assert.equal(inicio.API_URL, 'http://127.0.0.1:56321');
assert.equal(inicio.DB_URL, 'postgresql://postgres:postgres@127.0.0.1:56322/postgres');
assert.equal(JSON.parse(Buffer.from(inicio.SERVICE_ROLE_KEY.split('.')[1], 'base64url')).iss,
  'supabase-demo', 'El oráculo solo acepta las claves locales de Supabase');

export const literal = valor => valor === null ? 'null' : `'${String(valor).replaceAll("'", "''")}'`;
export const jsonSql = valor => `${literal(JSON.stringify(valor))}::jsonb`;

export function sql(texto, { admin = false } = {}) {
  const r = spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt',
    '-U', admin ? 'supabase_admin' : 'postgres', '-d', 'postgres',
    '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { input: `set timezone='America/Lima';\n${texto}\n`, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`SQL local F4: ${r.stderr || r.error || r.stdout}`);
  return r.stdout.trim();
}

export async function http(ruta, { token, admin = false, body, rawBody, binary = false, method = 'POST', headers = {} } = {}) {
  assert(ruta.startsWith('/') && !ruta.startsWith('//'), 'Ruta relativa obligatoria');
  assert(body === undefined || rawBody === undefined, 'El cuerpo solo puede ser JSON o binario');
  const r = await fetch(`${inicio.API_URL}${ruta}`, {
    method,
    headers: {
      apikey: inicio.ANON_KEY,
      Authorization: `Bearer ${admin ? inicio.SERVICE_ROLE_KEY : token ?? inicio.ANON_KEY}`,
      'Content-Type': 'application/json', ...headers,
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    ...(rawBody !== undefined ? { body: rawBody } : {}),
    signal: AbortSignal.timeout(30_000),
  });
  if (binary && r.ok) return { status: r.status, ok: true, data: Buffer.from(await r.arrayBuffer()) };
  const texto = await r.text();
  let data;
  try { data = JSON.parse(texto); } catch { data = texto; }
  return { status: r.status, ok: r.ok, data };
}

export async function rpc(nombre, payload, token, schema = 'crm') {
  assert(/^[a-z_][a-z0-9_]*$/.test(nombre));
  return http(`/rest/v1/rpc/${nombre}`, {
    token, body: payload, headers: { 'Content-Profile': schema, 'Accept-Profile': schema },
  });
}

export async function usuarioAuth(etiqueta, password) {
  const email = `f4.${etiqueta}@pruebas.example`;
  const r = await http('/auth/v1/admin/users', {
    admin: true, body: { email, password, email_confirm: true,
      app_metadata: { entorno: 'f4-sintetico' } },
  });
  assert.equal(r.ok, true, `Auth local: ${JSON.stringify(r.data)}`);
  return { id: r.data.id, email };
}

export async function sesion(usuario, password) {
  const r = await http('/auth/v1/token?grant_type=password', {
    body: { email: usuario.email, password },
  });
  assert.equal(r.ok, true, `Login local: ${JSON.stringify(r.data)}`);
  assert.equal(r.data.user.id, usuario.id);
  return r.data.access_token;
}

export function guardar(nombre, valor) {
  writeFileSync(join(banco, nombre), `${JSON.stringify(valor, null, 2)}\n`, { mode: 0o600 });
}

export function leer(nombre) {
  return JSON.parse(readFileSync(join(banco, nombre), 'utf8'));
}

// Configura el adaptador real sin sacar las credenciales del banco ni permitir
// que un interceptor de prueba desvíe la petición a otro proyecto.
export function storageEnBanco(crearStorage, { fetchImpl = fetch, plazoMs } = {}) {
  return crearStorage({ supabaseUrl: inicio.API_URL, secretKey: inicio.SERVICE_ROLE_KEY,
    basePublica: () => inicio.API_URL,
    ...(plazoMs === undefined ? {} : { plazoMs }),
    fetchImpl: (input, opciones) => {
      const url = input instanceof Request ? input.url : String(input);
      assert.equal(new URL(url).origin, inicio.API_URL, 'Storage no puede salir del banco local');
      return fetchImpl(input, opciones);
    },
  });
}

// Mantiene las claves dentro del banco: el oráculo recibe el handler configurado,
// nunca imprime ni incorpora credenciales en la evidencia versionable.
export function handlerEnBanco(crearHandler, fetchImpl = fetch) {
  return crearHandler({ supabaseUrl: inicio.API_URL, anonKey: inicio.ANON_KEY,
    serviceKey: inicio.SERVICE_ROLE_KEY, fetchImpl: (url, opciones) => {
      assert.equal(new URL(url).origin, inicio.API_URL, 'El ensayo no puede salir del banco local');
      return fetchImpl(url, opciones);
    } });
}
