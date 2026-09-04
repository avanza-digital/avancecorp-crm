import test from 'node:test';
import assert from 'node:assert/strict';
import { interpretarReclamo, authTieneMarca, correoYaRegistrado, decidirTrasFalloPerfil, statusDeErrorSaga } from './saga-auth.mjs';

test('interpretarReclamo: cada estado manda su paso', () => {
  assert.equal(interpretarReclamo({ estado: 'reclamado', claim_id: 'c', token: 't', version: 1 }).paso, 'crear_auth');
  assert.equal(interpretarReclamo({ estado: 'auth_creado', auth_user_id: 'u', reanudar: true }).paso, 'crear_perfil');
  assert.equal(interpretarReclamo({ estado: 'perfil_creado', perfil_id: 'p' }).paso, 'enlazar');
  assert.equal(interpretarReclamo({ estado: 'enlazado', perfil_id: 'p' }).paso, 'listo');
  assert.equal(interpretarReclamo({ estado: 'ya_existia', perfil_id: 'p' }).paso, 'ya_existia');
  assert.equal(interpretarReclamo(null).paso, 'desconocido');
  assert.equal(interpretarReclamo({ estado: 'otro' }).paso, 'desconocido');
});

test('authTieneMarca: solo con app_metadata.claim_id igual; un correo sin marca no se adopta', () => {
  assert.equal(authTieneMarca({ app_metadata: { claim_id: 'c1' } }, 'c1'), true);
  assert.equal(authTieneMarca({ app_metadata: { claim_id: 'c2' } }, 'c1'), false);
  assert.equal(authTieneMarca({ app_metadata: {} }, 'c1'), false);
  assert.equal(authTieneMarca({ id: 'u', claim_id: 'c1' }, 'c1'), true);   // forma de crm.auth_usuario_por_correo_fn
  assert.equal(authTieneMarca({ id: 'u', claim_id: null }, 'c1'), false);
  assert.equal(authTieneMarca(null, 'c1'), false);
  assert.equal(authTieneMarca({ app_metadata: { claim_id: 'c1' } }, ''), false);
});

test('correoYaRegistrado reconoce los mensajes de Auth', () => {
  assert.equal(correoYaRegistrado('A user with this email address has already been registered'), true);
  assert.equal(correoYaRegistrado('Database error'), false);
});

test('decidirTrasFalloPerfil: compensar SOLO por datos inválidos', () => {
  assert.equal(decidirTrasFalloPerfil({ code: '23514', message: 'check' }), 'compensar');
  assert.equal(decidirTrasFalloPerfil({ code: '23505', message: 'duplicate key value violates unique constraint "perfiles_pkey"' }), 'perfil_ya_existia');
  assert.equal(decidirTrasFalloPerfil({ code: '23505', message: 'duplicate key value violates unique constraint "perfiles_dni_cliente_key"' }), 'revision');
  assert.equal(decidirTrasFalloPerfil({ code: '08006', message: 'conn' }), 'error');
});

test('statusDeErrorSaga: PGRST202 con la bandera encendida NO degrada (503)', () => {
  assert.equal(statusDeErrorSaga({ code: 'PGRST202' }), 503);
  assert.equal(statusDeErrorSaga({ code: 'P0409' }), 409);
  assert.equal(statusDeErrorSaga({ code: '42501' }), 403);
  assert.equal(statusDeErrorSaga({ code: '22023' }), 400);
});
