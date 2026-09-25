import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { resolverAutorizacionAltaCliente } from './autorizacion.mjs';

const fuenteEdge = await readFile(new URL('./index.ts', import.meta.url), 'utf8');

test('rechaza al analista del CRM (vendedor) aunque pueda contratar, con rol Portal nuevo o legacy', () => {
  // 15/09/2026: el alta directa (sin lead) ya no es del analista. Su cliente
  // nuevo nace convirtiendo un lead. Ni el `comercial` nuevo ni el `analista`
  // legacy del Portal (que hasta hoy autorizaba por la vía Portal) lo reabren.
  for (const rolPortal of ['comercial', 'analista']) {
    assert.equal(
      resolverAutorizacionAltaCliente(
        { activo: true, rol: rolPortal },
        {
          estado: 'miembro',
          perfil_id: 'vendedor-1',
          rol_crm: 'vendedor',
          puede_contratar: true,
        },
        'vendedor-1',
      ),
      null,
    );
  }
  // Fail-closed: basta con que el contrato lo identifique como vendedor, aunque
  // el estado no sea el esperado.
  assert.equal(
    resolverAutorizacionAltaCliente(
      { activo: true, rol: 'analista' },
      { estado: 'no_enrolado', perfil_id: 'vendedor-2', rol_crm: 'vendedor', puede_contratar: false },
      'vendedor-2',
    ),
    null,
  );
  // Ni un rol Portal ADMINISTRATIVO reabre la puerta a un vendedor del CRM: el
  // veto va antes de la compatibilidad del Portal (revisión Codex 15/09/2026).
  for (const rolPortal of ['admin', 'superadmin', 'operaciones']) {
    assert.equal(
      resolverAutorizacionAltaCliente(
        { activo: true, rol: rolPortal },
        { estado: 'miembro', perfil_id: 'vendedor-3', rol_crm: 'vendedor', puede_contratar: true },
        'vendedor-3',
      ),
      null,
      `rol Portal ${rolPortal} no debe autorizar a un vendedor`,
    );
  }
  // El veto no depende del literal exacto que entregue la RPC.
  for (const variante of ['Vendedor', 'VENDEDOR', ' vendedor ', 'vendedor\n']) {
    assert.equal(
      resolverAutorizacionAltaCliente(
        { activo: true, rol: 'admin' },
        { estado: 'miembro', perfil_id: 'vendedor-4', rol_crm: variante, puede_contratar: true },
        'vendedor-4',
      ),
      null,
      `variante ${JSON.stringify(variante)} debe quedar vetada`,
    );
  }
});

test('los roles administrativos del Portal conservan el alta directa, con o sin membresía CRM', () => {
  // Sin membresía (los dos admin no enrolados del censo): vía Portal, sin
  // apropiarse de la cartera.
  for (const rolPortal of ['admin', 'superadmin', 'operaciones']) {
    assert.deepEqual(
      resolverAutorizacionAltaCliente(
        { activo: true, rol: rolPortal },
        { estado: 'no_enrolado', perfil_id: `${rolPortal}-1`, puede_contratar: false },
        `${rolPortal}-1`,
      ),
      { asesorId: null, via: 'portal' },
    );
  }
  // Gerencia CRM con rol Portal admin/superadmin (los dos gerentes del censo):
  // resuelve por la vía Portal, también sin apropiarse de la cartera.
  for (const rolPortal of ['admin', 'superadmin']) {
    assert.deepEqual(
      resolverAutorizacionAltaCliente(
        { activo: true, rol: rolPortal },
        { estado: 'miembro', perfil_id: `ger-${rolPortal}`, rol_crm: 'gerencia', puede_contratar: true },
        `ger-${rolPortal}`,
      ),
      { asesorId: null, via: 'portal' },
    );
  }
  // Superadmin que solo administra roles (sin membresía operativa).
  assert.deepEqual(
    resolverAutorizacionAltaCliente(
      { activo: true, rol: 'superadmin' },
      { estado: 'administrador_roles', perfil_id: 'sa-1', puede_contratar: false },
      'sa-1',
    ),
    { asesorId: null, via: 'portal' },
  );
});

test('un supervisor o gerente comercial SIN capacidad de contratar no da de alta (la rama CRM exige puede_contratar)', () => {
  for (const rolCrm of ['supervisor', 'gerencia']) {
    assert.equal(
      resolverAutorizacionAltaCliente(
        { activo: true, rol: 'comercial' },
        { estado: 'miembro', perfil_id: `${rolCrm}-sin`, rol_crm: rolCrm, puede_contratar: false },
        `${rolCrm}-sin`,
      ),
      null,
    );
  }
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

test('un supervisor con el rol Portal legacy `analista` conserva exactamente la vía de hoy', () => {
  // Dos supervisores reales tienen todavía rol Portal `analista`: el veto del
  // analista no los toca, y su comportamiento (vía Portal, autoasignado) no
  // cambia con esta entrega.
  assert.deepEqual(
    resolverAutorizacionAltaCliente(
      { activo: true, rol: 'analista' },
      { estado: 'miembro', perfil_id: 'sup-legacy', rol_crm: 'supervisor', puede_contratar: true },
      'sup-legacy',
    ),
    { asesorId: 'sup-legacy', via: 'portal' },
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
  assert.ok(fuenteEdge.includes('let asesorIdAlta = autorizacion.asesorId'));
  assert.ok(fuenteEdge.includes('asesor_perfil_id: asesorIdAlta'));
});
