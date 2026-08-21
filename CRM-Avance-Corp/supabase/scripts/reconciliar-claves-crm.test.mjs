import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import {
  clasificarCuentasCrm,
  normalizarDocumentoCrm,
} from './reconciliar-claves-crm-core.mjs';

const SCRIPT = fileURLToPath(new URL('./reconciliar-claves-crm.mjs', import.meta.url));
const ENTORNO = Object.freeze({
  SUPABASE_URL: 'https://crm-safe-test.invalid',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-ficticia',
  CRM_PASSWORD_RECONCILE_CONFIRM: '',
  CRM_PASSWORD_RECONCILE_EXPECTED_COUNT: '',
});

function ejecutar(args, overrides = {}) {
  const env = { ...process.env, ...ENTORNO, ...overrides };
  for (const [clave, valor] of Object.entries(env)) {
    if (valor === undefined) delete env[clave];
  }
  return spawnSync(process.execPath, [SCRIPT, ...args], {
    encoding: 'utf8',
    env,
    timeout: 5_000,
  });
}

test('normaliza sin perder ceros ni rellenar pasaportes', () => {
  assert.deepEqual(normalizarDocumentoCrm('CE', '001237707'), {
    tipo: 'CE',
    documento: '001237707',
  });
  assert.deepEqual(normalizarDocumentoCrm('pasaporte', 'ab1234'), {
    tipo: 'PASAPORTE',
    documento: 'AB1234',
  });
  assert.equal(normalizarDocumentoCrm('PASAPORTE', 'A123'), null);
});

test('selecciona solo comercial con marca CRM y excluye identidad Portal compartida', () => {
  const usuarios = [
    { id: 'crm-app', app_metadata: { origen_app: 'crm', provider: 'email' }, user_metadata: {} },
    { id: 'crm-legacy', app_metadata: {}, user_metadata: { origen: 'crm' } },
    { id: 'portal', app_metadata: {}, user_metadata: {} },
    { id: 'analista-marcado', app_metadata: { origen_app: 'crm' }, user_metadata: {} },
  ];
  const comerciales = [
    { id: 'crm-app', rol: 'comercial', tipo_documento: 'DNI', dni: '01234567' },
    { id: 'crm-legacy', rol: 'comercial', tipo_documento: 'PASAPORTE', dni: 'ab1234' },
    { id: 'portal', rol: 'comercial', tipo_documento: 'DNI', dni: '12345678' },
  ];

  const resultado = clasificarCuentasCrm(
    usuarios,
    comerciales,
    new Set(['crm-legacy']),
  );
  assert.deepEqual(
    resultado.candidatas.map(({ id, documento }) => ({ id, documento })),
    [
      { id: 'crm-app', documento: '01234567' },
      { id: 'crm-legacy', documento: 'AB1234' },
    ],
  );
  assert.equal(resultado.resumen.comerciales_sin_marca_origen, 1);
  assert.equal(resultado.resumen.marcas_crm_fuera_de_comercial, 1);
  assert.deepEqual(resultado.candidatas[0].appMetadata, {
    origen_app: 'crm',
    provider: 'email',
  });
});

test('user_metadata legacy nunca autoriza por si sola una mutacion', () => {
  const resultado = clasificarCuentasCrm(
    [{ id: 'legacy', app_metadata: {}, user_metadata: { origen: 'crm' } }],
    [{ id: 'legacy', rol: 'comercial', tipo_documento: 'DNI', dni: '12345678' }],
  );
  assert.equal(resultado.candidatas.length, 0);
  assert.equal(resultado.resumen.marcas_legacy_sin_auditoria, 1);
});

test('help y preflight no abren conexion', () => {
  const help = ejecutar(['--help'], {
    SUPABASE_URL: undefined,
    SUPABASE_SERVICE_ROLE_KEY: undefined,
  });
  assert.equal(help.status, 0);
  assert.match(help.stdout, /identidades exclusivas del CRM/);

  const preflight = ejecutar(['--preflight']);
  assert.equal(preflight.status, 0);
  assert.match(preflight.stdout, /sin crear cliente ni abrir conexion/);
});

test('apply exige doble confirmacion y conteo exacto', () => {
  const sinConfirmacion = ejecutar(['--apply']);
  assert.equal(sinConfirmacion.status, 1);
  assert.match(sinConfirmacion.stderr, /CRM_PASSWORD_RECONCILE_CONFIRM/);

  const sinConteo = ejecutar(['--apply'], {
    CRM_PASSWORD_RECONCILE_CONFIRM: 'SOLO_CRM_CLAVE_DOCUMENTO',
  });
  assert.equal(sinConteo.status, 1);
  assert.match(sinConteo.stderr, /CRM_PASSWORD_RECONCILE_EXPECTED_COUNT/);
});

test('rechaza modos ambiguos y opciones desconocidas', () => {
  assert.equal(ejecutar([]).status, 2);
  assert.equal(ejecutar(['--dry-run', '--apply']).status, 2);
  assert.equal(ejecutar(['--portal']).status, 2);
});
