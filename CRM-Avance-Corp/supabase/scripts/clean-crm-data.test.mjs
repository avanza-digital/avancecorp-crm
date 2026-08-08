import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import { PRODUCTION_PROJECT_REF } from './fixtures.mjs';

const SCRIPT = fileURLToPath(new URL('./clean-crm-data.mjs', import.meta.url));
const SAFE_ENV = Object.freeze({
  SUPABASE_URL: 'https://staging-clean-test.invalid',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-ficticia-para-preflight',
  CRM_CLEAN_CONFIRM: '',
});

function runCli(args = [], overrides = {}) {
  const env = { ...process.env, ...SAFE_ENV, ...overrides };
  for (const [key, value] of Object.entries(env)) {
    if (value === undefined) delete env[key];
  }

  const result = spawnSync(process.execPath, [SCRIPT, ...args], {
    encoding: 'utf8',
    env,
    timeout: 5_000,
  });

  assert.equal(result.error, undefined, result.error?.message);
  return result;
}

function outputOf(result) {
  return `${result.stdout}${result.stderr}`;
}

function assertTarget(output, table) {
  assert.match(output, new RegExp(`  - crm\\.${table}(?:\\n|$)`));
}

function assertNoTarget(output, table) {
  assert.doesNotMatch(output, new RegExp(`  - crm\\.${table}(?:\\n|$)`));
}

test('help funciona sin variables ni conexiones', () => {
  const result = runCli(['--help'], {
    SUPABASE_URL: undefined,
    SUPABASE_SERVICE_ROLE_KEY: undefined,
  });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /Limpieza controlada de datos del CRM/);
});

test('rechaza opciones desconocidas, incluidos flags que empiezan por --', () => {
  for (const option of ['--borra-produccion', 'posicional']) {
    const result = runCli([option]);
    assert.equal(result.status, 2, option);
    assert.match(result.stderr, new RegExp(`Opciones desconocidas: ${option}`));
  }
});

test('rechaza combinar preflight y dry-run para no anunciar un modo ambiguo', () => {
  const result = runCli(['--preflight', '--dry-run']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /mutuamente excluyentes/);
});

test('preflight exige las variables declaradas por el script', () => {
  const withoutUrl = runCli(['--preflight'], { SUPABASE_URL: undefined });
  assert.equal(withoutUrl.status, 1);
  assert.match(withoutUrl.stderr, /Falta SUPABASE_URL/);

  const withoutKey = runCli(['--preflight'], { SUPABASE_SERVICE_ROLE_KEY: undefined });
  assert.equal(withoutKey.status, 1);
  assert.match(withoutKey.stderr, /Falta SUPABASE_SERVICE_ROLE_KEY/);
});

test('preflight predeterminado enumera todo el dataset sin abrir un cliente', () => {
  const result = runCli(['--preflight']);
  const output = outputOf(result);

  assert.equal(result.status, 0);
  assert.match(output, /modo: PREFLIGHT SIN RED/);
  assert.match(output, /no se creó ningún cliente ni se abrió una conexión/);
  for (const table of [
    'tareas',
    'lead_asignaciones',
    'actividades',
    'contrato_cuentas_pago',
    'cuentas_bancarias',
    'agenda_ics',
    'objetivos_vendedores',
    'objetivos',
    'enfriamiento_politica',
    'leads',
    'equipo',
  ]) {
    assertTarget(output, table);
  }
});

test('--preserve-reference conserva enfriamiento y la relación bancaria completa', () => {
  const result = runCli(['--preflight', '--preserve-reference']);
  const output = outputOf(result);

  assert.equal(result.status, 0);
  for (const table of [
    'enfriamiento_politica',
    'cuentas_bancarias',
    'contrato_cuentas_pago',
  ]) {
    assertNoTarget(output, table);
  }
  assertTarget(output, 'objetivos_vendedores');
  assertTarget(output, 'leads');
  assertTarget(output, 'equipo');
});

test('--preserve-equipo solo excluye la estructura del equipo', () => {
  const result = runCli(['--preflight', '--preserve-equipo']);
  const output = outputOf(result);

  assert.equal(result.status, 0);
  assertNoTarget(output, 'equipo');
  assertTarget(output, 'cuentas_bancarias');
  assertTarget(output, 'enfriamiento_politica');
});

test('los dos modos de preservación se pueden combinar', () => {
  const result = runCli([
    '--preflight',
    '--preserve-equipo',
    '--preserve-reference',
  ]);
  const output = outputOf(result);

  assert.equal(result.status, 0);
  for (const table of [
    'equipo',
    'enfriamiento_politica',
    'cuentas_bancarias',
    'contrato_cuentas_pago',
  ]) {
    assertNoTarget(output, table);
  }
  assertTarget(output, 'leads');
});

test('bloquea producción incluso en preflight', () => {
  const result = runCli(['--preflight'], {
    SUPABASE_URL: `https://${PRODUCTION_PROJECT_REF}.supabase.co`,
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /Destino de PRODUCCION detectado/);
});

test('una ejecución destructiva no pasa sin la frase exacta de confirmación', () => {
  for (const confirmation of ['', 'QUIERO_BORRAR_CASI_TODOS_LOS_DATOS']) {
    const result = runCli([], { CRM_CLEAN_CONFIRM: confirmation });
    const output = outputOf(result);

    assert.equal(result.status, 1, confirmation);
    assert.match(result.stderr, /Falta confirmación explícita/);
    assert.doesNotMatch(output, /Iniciando limpieza|fila\(s\)/);
  }
});

test('incluso con confirmación exacta, el WIP aborta antes de abrir red', () => {
  const result = runCli([], {
    CRM_CLEAN_CONFIRM: 'QUIERO_BORRAR_TODOS_LOS_DATOS',
  });
  const output = outputOf(result);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /Ejecución deshabilitada/);
  assert.match(result.stderr, /lead_asignaciones veta DELETE/);
  assert.doesNotMatch(output, /Iniciando limpieza|fila\(s\)/);
});

test('dry-run también queda cerrado mientras no exista limpieza transaccional', () => {
  const result = runCli(['--dry-run']);
  const output = outputOf(result);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /Ejecución deshabilitada/);
  assert.doesNotMatch(output, /DRY-RUN activo|fila\(s\)/);
});

test('rechaza destinos inseguros antes de crear un cliente', () => {
  const httpRemote = runCli(['--preflight'], {
    SUPABASE_URL: 'http://staging.example.test',
  });
  assert.equal(httpRemote.status, 1);
  assert.match(httpRemote.stderr, /debe usar HTTPS/);

  const credentialsInUrl = runCli(['--preflight'], {
    SUPABASE_URL: 'https://usuario:secreto@staging.example.test',
  });
  assert.equal(credentialsInUrl.status, 1);
  assert.match(credentialsInUrl.stderr, /no debe incluir credenciales/);
});
