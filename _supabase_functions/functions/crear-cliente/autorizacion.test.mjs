import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { resolverAutorizacionAltaCliente } from './autorizacion.mjs';

const fuenteEdge = await readFile(new URL('./index.ts', import.meta.url), 'utf8');

test('autoriza y autoasigna al nuevo Comercial/Vendedor del CRM', () => {
  assert.deepEqual(
    resolverAutorizacionAltaCliente(
      { activo: true, rol: 'comercial' },
      {
        estado: 'miembro',
        perfil_id: 'vendedor-nuevo',
        rol_crm: 'vendedor',
        puede_contratar: true,
      },
      'vendedor-nuevo',
    ),
    { asesorId: 'vendedor-nuevo', via: 'crm' },
  );
});

test('conserva los roles históricos del Portal y su autoasignación', () => {
  assert.deepEqual(
    resolverAutorizacionAltaCliente(
      { activo: true, rol: 'analista' },
      { estado: 'no_enrolado', perfil_id: 'analista-1', puede_contratar: false },
      'analista-1',
    ),
    { asesorId: 'analista-1', via: 'portal' },
  );
  assert.deepEqual(
    resolverAutorizacionAltaCliente(
      { activo: true, rol: 'operaciones' },
      { estado: 'no_enrolado', perfil_id: 'ops-1', puede_contratar: false },
      'ops-1',
    ),
    { asesorId: null, via: 'portal' },
  );
});

test('supervisión y Gerencia CRM crean sin apropiarse de la cartera', () => {
  for (const rolCrm of ['supervisor', 'gerencia']) {
    assert.deepEqual(
      resolverAutorizacionAltaCliente(
        { activo: true, rol: 'comercial' },
        {
          estado: 'miembro',
          perfil_id: `${rolCrm}-1`,
          rol_crm: rolCrm,
          puede_contratar: true,
        },
        `${rolCrm}-1`,
      ),
      { asesorId: null, via: 'crm' },
    );
  }
});

test('una revocación CRM explícita gana incluso sobre un rol Portal legacy', () => {
  assert.equal(
    resolverAutorizacionAltaCliente(
      { activo: true, rol: 'analista' },
      { estado: 'revocado', perfil_id: 'analista-off', puede_contratar: false },
      'analista-off',
    ),
    null,
  );
});

test('falla cerrado para perfil inactivo, capacidad ausente o identidad distinta', () => {
  assert.equal(resolverAutorizacionAltaCliente(
    { activo: false, rol: 'analista' },
    { estado: 'no_enrolado', perfil_id: 'u-1', puede_contratar: false },
    'u-1',
  ), null);
  assert.equal(resolverAutorizacionAltaCliente(
    { activo: true, rol: 'comercial' },
    { estado: 'miembro', perfil_id: 'u-1', rol_crm: 'vendedor' },
    'u-1',
  ), null);
  assert.equal(resolverAutorizacionAltaCliente(
    { activo: true, rol: 'comercial' },
    { estado: 'miembro', perfil_id: 'u-2', rol_crm: 'vendedor', puede_contratar: true },
    'u-1',
  ), null);
});

test('el fallback Portal también exige un contrato canónico ligado al JWT', () => {
  for (const acceso of [
    null,
    {},
    { estado: 'no_enrolado', perfil_id: 'otro', puede_contratar: false },
    { estado: 'desconocido', perfil_id: 'analista-1', puede_contratar: false },
    { estado: 'no_enrolado', perfil_id: 'analista-1' },
  ]) {
    assert.equal(
      resolverAutorizacionAltaCliente(
        { activo: true, rol: 'analista' },
        acceso,
        'analista-1',
      ),
      null,
    );
  }
});

test('la edge usa la RPC con JWT y no vuelve a leer crm.equipo con service_role', () => {
  assert.ok(fuenteEdge.includes('await userClient\n      .schema("crm").rpc("mi_acceso_fn")'));
  assert.ok(fuenteEdge.includes('resolverAutorizacionAltaCliente(perfil, acceso, callerId)'));
  assert.equal(fuenteEdge.includes('.schema("crm")\n        .from("equipo")'), false);
  assert.ok(fuenteEdge.includes('asesor_perfil_id: autorizacion.asesorId'));
});
