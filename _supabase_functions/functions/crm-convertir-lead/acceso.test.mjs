import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { contextoContratacionDesdeAcceso } from '../_shared/acceso-crm.mjs';

const fuenteEdge = await readFile(new URL('./index.ts', import.meta.url), 'utf8');

test('acepta al Comercial nuevo con membresía CRM Vendedor habilitada', () => {
  assert.deepEqual(
    contextoContratacionDesdeAcceso({
      estado: 'miembro',
      perfil_id: 'analista-nuevo',
      rol_crm: 'vendedor',
      rol_portal: 'comercial',
      puede_contratar: true,
    }, 'analista-nuevo'),
    { rolCrm: 'vendedor' },
  );
});

test('no interpreta por su cuenta el rol del Portal', () => {
  assert.equal(
    contextoContratacionDesdeAcceso({
      estado: 'miembro',
      perfil_id: 'usuario-1',
      rol_crm: 'vendedor',
      rol_portal: 'analista',
      puede_contratar: false,
    }, 'usuario-1'),
    null,
  );
});

test('falla cerrado si la respuesta pertenece a otra sesión', () => {
  assert.equal(
    contextoContratacionDesdeAcceso({
      estado: 'miembro',
      perfil_id: 'usuario-b',
      rol_crm: 'vendedor',
      puede_contratar: true,
    }, 'usuario-a'),
    null,
  );
});

for (const valor of [
  null,
  [],
  {},
  { estado: 'revocado', perfil_id: 'usuario-1', puede_contratar: false },
  { estado: 'global', perfil_id: 'usuario-1', rol_crm: 'directorio', puede_contratar: false },
  { estado: 'miembro', perfil_id: 'usuario-1', rol_crm: 'vendedor' },
  { estado: 'miembro', perfil_id: 'usuario-1', rol_crm: '', puede_contratar: true },
]) {
  test(`rechaza un contrato de acceso no operativo: ${JSON.stringify(valor)}`, () => {
    assert.equal(contextoContratacionDesdeAcceso(valor, 'usuario-1'), null);
  });
}

test('la edge consulta la capacidad con el JWT del caller antes de cualquier efecto', () => {
  const llamadaCanonica = 'await userClient\n      .schema("crm").rpc("mi_acceso_fn")';
  const inicioAcceso = fuenteEdge.indexOf(llamadaCanonica);
  const inicioBody = fuenteEdge.indexOf('const body = await req.json()');

  assert.ok(inicioAcceso >= 0);
  assert.ok(inicioBody > inicioAcceso);
  assert.ok(fuenteEdge.includes('contextoContratacionDesdeAcceso(acceso, callerId)'));
});

test('la edge no conserva una segunda allowlist de roles Portal', () => {
  assert.equal(fuenteEdge.includes('["analista", "admin", "superadmin"]'), false);
  assert.equal(fuenteEdge.includes('perfilCaller'), false);
});
