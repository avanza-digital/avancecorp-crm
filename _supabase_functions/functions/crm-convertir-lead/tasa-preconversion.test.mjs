import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';
import { contextoContratacionDesdeAcceso } from '../_shared/acceso-crm.mjs';
import { errorResponsabilidadConversion } from './preflight.mjs';
import { validarBancarios } from '../_shared/bancarios.mjs';
import { validarDomicilioLegal } from '../_shared/domicilio.mjs';
import * as saga from '../_shared/saga-auth.mjs';

const fuente = await readFile(new URL('./index.ts', import.meta.url), 'utf8');
const ejecutable = stripTypeScriptTypes(fuente.replace(/^import\s[\s\S]*?;\s*$/gm, ''));
const actor = 'd7090000-0000-4000-8000-000000000001';
const condiciones = { categoria: 'nuevo', capital: 20000, moneda: 'PEN', modalidad: 'mensual', tipo_interes: 'simple', fecha_inicio: '2026-09-15', fecha_vencimiento: '2027-09-15', tasa_anual: 17 };
const vacia = { banco: '', tipo_cuenta: '', numero_cuenta: '', cci: '', titular_distinto: false, beneficiario_nombre: '', beneficiario_dni: '' };
const cuerpo = {
  lead_id: actor, correo: 'qa@example.invalid', tipo_documento: 'DNI', documento: '70909001',
  nombre_completo: 'PRUEBA LOCAL UNO', nombres: 'PRUEBA', apellidos: 'LOCAL UNO', domicilio: 'Calle de prueba 123',
  bancarios: { pen: { ...vacia, banco: 'BCP', tipo_cuenta: 'ahorros', numero_cuenta: '12345678901234', cci: '00400000000000000001' }, usd: vacia },
  condiciones_tasa: condiciones,
};

async function ejecutar(bandera, errorReserva, omitirCondiciones = false, documento = cuerpo.documento) {
  const llamadas = [];
  let handler;
  const cliente = {
    auth: { getUser: async () => ({ data: { user: { id: actor } } }), admin: new Proxy({}, { get: (_, accion) => async () => { llamadas.push(`auth:${String(accion)}`); throw new Error('Efecto inesperado'); } }) },
    schema: () => cliente,
    from: (tabla) => {
      assert.equal(tabla, 'leads', 'no debe escribir ni consultar perfiles antes de la validación');
      const consulta = { select: () => consulta, eq: () => consulta, maybeSingle: async () => ({ data: { id: actor, activo: true, etapa: 'negociacion', dni: '70909001', telefono: '+51999009001', vendedor_id: actor, perfil_id: null } }) };
      return consulta;
    },
    rpc: async (nombre, args) => {
      llamadas.push({ nombre, args });
      if (nombre === 'mi_acceso_fn') return { data: { estado: 'miembro', perfil_id: actor, rol_crm: 'vendedor', puede_contratar: true } };
      if (nombre === 'bandera_activa') return { data: bandera };
      if (nombre === (bandera ? 'reservar_conversion_lead' : 'reservar_conversion_lead_tasa_fn')) return { error: errorReserva };
      throw new Error(`RPC inesperada: ${nombre}`);
    },
  };
  vm.runInNewContext(ejecutable, {
    Deno: { serve: (fn) => { handler = fn; }, env: { get: () => 'valor-local-de-prueba' } },
    createClient: () => cliente, contextoContratacionDesdeAcceso, errorResponsabilidadConversion, validarBancarios, validarDomicilioLegal, ...saga,
    Request, Response, Headers, console,
    fetch: async () => { llamadas.push('correo'); throw new Error('Correo inesperado'); },
  });
  const body = { ...cuerpo, documento };
  if (omitirCondiciones) delete body.condiciones_tasa;
  const respuesta = await handler(new Request('https://local.invalid', { method: 'POST', headers: { Authorization: 'Bearer prueba', 'Content-Type': 'application/json' }, body: JSON.stringify(body) }));
  return { respuesta, llamadas };
}

for (const bandera of [false, true]) {
  for (const codigo of ['P0411', 'P0410', 'PGRST202']) {
    test(`identidad ${bandera}: ${codigo} impide Auth, perfiles y correo antes de convertir`, async () => {
      const { respuesta, llamadas } = await ejecutar(bandera, { code: codigo, message: 'Validación de tasa bloqueada' });
      assert.ok(respuesta.status >= 400);
      assert.equal((await respuesta.json()).error, codigo === 'PGRST202'
        ? 'No se pudo verificar la tasa. Intenta nuevamente en unos minutos.' : 'Validación de tasa bloqueada');
      assert.equal(llamadas.length, 3);
      const reserva = llamadas[2];
      const enviada = bandera ? reserva.args.p_payload.condiciones_tasa : reserva.args.p_condiciones;
      assert.equal(JSON.stringify(enviada), JSON.stringify(condiciones));
    });
  }
  test(`identidad ${bandera}: omitir la propuesta no evita preguntar al servidor`, async () => {
    const { respuesta, llamadas } = await ejecutar(bandera, { code: 'P0411', message: 'Pendiente' }, true);
    assert.ok(respuesta.status >= 400);
    assert.equal(llamadas.length, 3);
    assert.equal((await respuesta.json()).error, 'Pendiente');
  });
  test(`identidad ${bandera}: cambiar documento de la propuesta se rechaza antes de reservar o crear Auth`, async () => {
    const { respuesta, llamadas } = await ejecutar(bandera, null, false, '70909009');
    assert.equal(respuesta.status, 409);
    assert.match((await respuesta.json()).error, /documento no coincide con el lead/);
    assert.equal(llamadas.length, 2);
  });
}
