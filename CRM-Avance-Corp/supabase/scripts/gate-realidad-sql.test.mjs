import test from 'node:test';
import assert from 'node:assert/strict';
import { codigoSalida, medirSQL, proyectoSQL } from './gate-realidad-sql.mjs';

const ref = 'abcdefghijklmnopqrst';
const url = `https://${ref}.supabase.co`;
const devolver = valor => async () => ({ stdout: JSON.stringify({ rows: [{ valor }] }) });

test('la medición administrativa exige selección explícita de la misma base', () => {
  assert.equal(proyectoSQL([], url), null);
  assert.equal(proyectoSQL(['--sql-project-ref', ref], url), ref);
  for (const args of [['--sql-project-ref'], ['--sql-project-ref', '--json'],
    ['--sql-project-ref', ref, '--sql-project-ref', ref]]) {
    assert.throws(() => proyectoSQL(args, url));
  }
  for (const otro of ['http://'+ref+'.supabase.co', url+'.otro.test', url+'/rest/v1', 'https://otro.supabase.co']) {
    assert.throws(() => proyectoSQL(['--sql-project-ref', ref], otro));
  }
});

test('SQL solo lectura, rollback, timeout acotado y destino explícito sin shell', async () => {
  for (const clave of ['metas_bajo_el_sello', 'conversion_un_solo_nucleo']) {
    await medirSQL(clave, ref, async (cmd, args, opciones) => {
      assert.equal(cmd, 'supabase');
      assert.deepEqual(args.slice(0, 7), ['db', 'query', '--linked', '--project-ref', ref, '--output', 'json']);
      assert.match(args[7], /^begin read only;/);
      assert.match(args[7], /statement_timeout = '80s'/);
      assert.match(args[7], /rollback;$/);
      assert.equal(opciones.shell, undefined);
      assert.equal(opciones.timeout, 90_000);
      return { stdout: JSON.stringify({ rows: [{ valor: clave === 'metas_bajo_el_sello' ? 0 : { cuadra: true } }] }) };
    });
  }
  await assert.rejects(medirSQL('select 1; delete from crm.leads', ref));
});

test('respuesta vacía, truncada o mal tipada no equivale a un control aprobado', async () => {
  for (const stdout of ['', '{}', '{"rows":[]}', '{"rows":[{},{}]}', '{"rows":[{}]}']) {
    await assert.rejects(medirSQL('metas_bajo_el_sello', ref, async () => ({ stdout })));
  }
  for (const valor of [null, -1, '0', 0.5]) {
    await assert.rejects(medirSQL('metas_bajo_el_sello', ref, devolver(valor)));
  }
  for (const valor of [null, {}, [], { cuadra: 'true' }]) {
    await assert.rejects(medirSQL('conversion_un_solo_nucleo', ref, devolver(valor)));
  }
});

test('conserva las divergencias y el estado sin veredicto de la base', async () => {
  assert.equal(await medirSQL('metas_bajo_el_sello', ref, devolver(2)), 2);
  for (const cuadra of [true, false, null]) {
    assert.deepEqual(await medirSQL('conversion_un_solo_nucleo', ref, devolver({ cuadra })), { cuadra });
  }
});

test('un fallo de la CLI no divulga su salida ni queda oculto como cero', async () => {
  await assert.rejects(medirSQL('metas_bajo_el_sello', ref, async () => {
    throw new Error('secreto-simulado-en-stderr');
  }), error => !error.message.includes('secreto-simulado') && /No se pudo medir/.test(error.message));
});

test('errores bloquean en ambos modos; divergencias solo son fatales en estricto', () => {
  assert.equal(codigoSalida([{ error: null, diverge: false }], false), 0);
  assert.equal(codigoSalida([{ error: null, diverge: true }], false), 0);
  assert.equal(codigoSalida([{ error: null, diverge: true }], true), 1);
  for (const estricto of [true, false]) {
    assert.equal(codigoSalida([{ error: 'timeout', diverge: false }], estricto), 2);
    assert.equal(codigoSalida([{ error: 'permiso', diverge: true }], estricto), 2);
  }
});
