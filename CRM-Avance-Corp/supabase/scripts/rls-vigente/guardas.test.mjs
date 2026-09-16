// Verifica instalación/reversa en una transacción deshecha del banco local propio.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const destino = new URL(process.env.CRM_BANCO_PSQL_URL);
assert(['127.0.0.1', 'localhost', '::1'].includes(destino.hostname));
assert.match(destino.pathname, /^\/rls_f8_locks_[a-z0-9_]+$/);
const env = {
  ...process.env, PGHOST: destino.hostname, PGPORT: destino.port || '5432',
  PGDATABASE: destino.pathname.slice(1), PGUSER: decodeURIComponent(destino.username),
  PGPASSWORD: decodeURIComponent(destino.password),
};
function sql(texto) {
  try {
    return execFileSync('psql', ['-XqAt', '-v', 'ON_ERROR_STOP=1'], {
      env, input: texto, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
  } catch (error) {
    throw new Error(String(error.stderr));
  }
}
const sinTransaccion = (texto) => texto.replace(/^begin;\s*$/gm, '').replace(/^commit;\s*$/gm, '');
const reversa = sinTransaccion(readFileSync(new URL('./reversa.sql', import.meta.url), 'utf8'));
const candidata = sinTransaccion(readFileSync(new URL('../../migrations/20260916040442_crm_piloto_f8_activacion_serializada.sql', import.meta.url), 'utf8'));
const huella = () => sql("select md5(pg_get_functiondef('private.trg_piloto_f8_control_validar()'::regprocedure))");

test('reversa y reinstalación exactas conservan definición, ACL y trigger', () => {
  const antes = huella();
  sql('begin;\n' + reversa + '\n' + candidata + '\nrollback;');
  assert.equal(huella(), antes);
});

test('la instalación rechaza una configuración inesperada sin perderla', () => {
  const antes = huella();
  assert.throws(() => sql('begin;\n' + reversa
    + "\nalter function private.trg_piloto_f8_control_validar() set lock_timeout='7s';\n"
    + candidata + '\nrollback;'), /El control F8 cambió/);
  assert.equal(huella(), antes, 'La conexión abortada revierte todo el ensayo');
});

test('la instalación rechaza un trigger deshabilitado y lo deja restaurado', () => {
  const antes = huella();
  assert.throws(() => sql('begin;\n' + reversa
    + '\nalter table crm.piloto_f8_control disable trigger trg_piloto_f8_control_00_validar;\n'
    + candidata + '\nrollback;'), /El trigger F8 no coincide/);
  assert.equal(huella(), antes);
  assert.equal(sql("select tgenabled from pg_trigger where tgrelid='crm.piloto_f8_control'::regclass and tgname='trg_piloto_f8_control_00_validar'"), 'O');
});
