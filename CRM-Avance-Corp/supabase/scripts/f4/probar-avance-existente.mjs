import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { sql, literal as q, leer, guardar, sesion, rpc, http } from './banco-local.mjs';
import { contratoPrueba } from './operaciones-fixture.mjs';

const f = leer('fixtures.json');
const base = leer('operaciones-base.json');
const ejecucion = randomUUID();
const pruebas = [];
const t = await sesion(f.usuarios.vendedor, f.password);
const cliente = await sesion(f.usuarios.cliente, f.password);
const ajeno = await sesion(f.usuarios.ajeno, f.password);
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
const datos = moneda => ({ inversionista_id: base.identidades.avance, empresa: 'avance',
  ...contratoPrueba(f.usuarios.cliente.id, f.usuarios.vendedor.id, { moneda, categoria: 'nuevo', inicio: '2026-09-01', capital: 1500 }) });
const contadores = () => JSON.parse(sql(`select jsonb_build_object(
  'auth',(select count(*) from auth.users),'personas',(select count(*) from crm.inversionistas),
  'leads',(select count(*) from crm.leads),'contratos',(select count(*) from public.contratos),
  'inversiones',(select count(*) from crm.inversiones),'cuotas',(select count(*) from public.cronograma_pagos),
  'cuentas',(select count(*) from crm.cuentas_bancarias),'jobs',(select count(*) from private.contrato_pdf_jobs))`));
const bien = (nombre, detalle = {}) => pruebas.push({ nombre, ...detalle, conforme: true });
function ok(r, nombre) { assert.equal(r.ok, true, `${nombre}: ${JSON.stringify(r.data)}`); return r.data; }
async function preparar(clave, payload) {
  return ok(await rpc('preparar_inversion_fn', { p_clave: clave, p_datos: payload }, t), 'preparar Avance');
}
const antes = contadores();
// Falla después de pasar contrato/cuenta; las escrituras anidadas deben volver
// atrás junto con el PDF y la inversión, sin tocar las operaciones existentes.
const incorrecta = datos('USD');
incorrecta.contrato.titulares = [{ nombre_completo: 'COTITULAR FICTICIO INVALIDO', tipo_documento: 'DNI', documento: '123' }];
const claveFallida = randomUUID();
await preparar(claveFallida, incorrecta);
const fallo = await rpc('confirmar_inversion_fn', { p_solicitud: claveFallida }, t);
assert.equal(fallo.ok, false);
assert.match(fallo.data.message, /Documento invalido para el co-titular/);
assert.deepEqual(contadores(), antes, 'Un fallo en titularidad dejó parte del contrato confirmado');
assert.equal(sql(`select estado from crm.inversion_solicitudes where id=${q(claveFallida)}`), 'preparada');
bien('Fallo de cotitular revierte contrato, cuenta, cuotas, relación y PDF completos');

const resultados = [];
for (const moneda of ['PEN', 'USD']) {
  const payload = datos(moneda);
  payload.contrato.titulares = [{ nombre_completo: 'PERSONA FICTICIA F4 QORILAZO', tipo_documento: 'DNI', documento: '92000002' }];
  const clave = randomUUID();
  const preparacion = await preparar(clave, payload);
  assert.equal(preparacion.necesita_portal, false);
  const res = ok(await rpc('confirmar_inversion_fn', { p_solicitud: clave }, t), 'confirmar Avance');
  const cid = res.fuente.id;
  resultados.push({ clave, res });
  assert(cid);
  assert.equal(res.inversionista_id, base.identidades.avance);
  assert.equal(res.lead_id, base.leads.avance);
  const fuente = JSON.parse(sql(`select jsonb_build_object('contrato',i.contrato_id,
    'empresa',e.clave,'persona',i.inversionista_id,'principal',it.inversionista_id,
    'capital',c.capital,'moneda',c.moneda,'cliente',c.cliente_id,
    'analista',c.analista_cierre_id,'autor',c.creado_por,'fecha',c.fecha_cierre_comercial,
    'legacy',pc.es_legacy,'cuotas',(select count(*) from public.cronograma_pagos where contrato_id=c.id),
    'cotitulares',(select count(*) from public.contrato_titulares where contrato_id=c.id))
    from crm.inversiones i join crm.empresas e on e.id=i.empresa_id
    join public.contratos c on c.id=i.contrato_id
    join crm.producto_condiciones pc on pc.id=c.producto_condicion_id
    join crm.inversion_titulares it on it.inversion_id=i.id and it.rol='principal' where i.id=${q(res.inversion_id)}`));
  assert.deepEqual(fuente, { contrato: cid, empresa: 'avance', persona: base.identidades.avance,
    principal: base.identidades.avance, capital: 1500, moneda, cliente: f.usuarios.cliente.id,
    analista: f.usuarios.vendedor.id, autor: f.usuarios.vendedor.id, fecha: '2026-09-01',
    legacy: true, cuotas: 13, cotitulares: 1 });
  const snapshot = JSON.parse(sql(`select private.contrato_pdf_snapshot_v2_base(${q(cid)})`));
  assert.equal(snapshot.contrato.capital, 1500);
  assert.equal(snapshot.contrato.moneda, moneda);
  assert.equal(snapshot.titular.id, f.usuarios.cliente.id);
  assert.equal(snapshot.cotitulares.length, 1);
  assert.equal(snapshot.cotitulares[0].documento, '92000002');
  assert.equal(snapshot.cronograma.length, 13);
  assert.equal(snapshot.cuentaPago.moneda, moneda);
  const repetido = ok(await rpc('confirmar_inversion_fn', { p_solicitud: clave }, t), 'reintento Avance');
  assert.equal(repetido.inversion_id, res.inversion_id);
  assert.equal(repetido.fuente.id, cid);
  assert.equal(repetido.reintento, true);
  assert.deepEqual(repetido.fuente.pdf, res.fuente.pdf);
  const lectura = ok(await http(`/rest/v1/contratos?id=eq.${cid}&select=id,moneda,capital`, { method: 'GET', token: cliente }), 'Portal propio');
  assert.deepEqual(lectura, [{ id: cid, moneda, capital: 1500 }]);
  const lecturaAjena = ok(await http(`/rest/v1/contratos?id=eq.${cid}&select=id`, { method: 'GET', token: ajeno }), 'Portal ámbito ajeno');
  assert.deepEqual(lecturaAjena, []);
  bien(`Nueva inversión Avance ${moneda}`, { sinCatalogoObligatorio: true, principalYCoTitularDocumental: true,
    cronogramaYCuenta: true, portalPropio: true, reintentoUnico: true, pdfReservado: true });
}
const despues = contadores();
assert.equal(despues.auth, antes.auth);
assert.equal(despues.personas, antes.personas);
assert.equal(despues.leads, antes.leads);
assert.equal(despues.contratos, antes.contratos + 2);
assert.equal(despues.inversiones, antes.inversiones + 2);
assert.equal(despues.cuotas, antes.cuotas + 26);
assert.equal(despues.jobs, antes.jobs + 2);
bien('Dos fuentes Avance adicionales sin recrear identidad, lead ni Auth');
guardar(`avance-existente-${ejecucion}.json`, resultados);
writeFileSync(new URL(`../evidencia-f4/avance-existente-${ejecucion}.json`, import.meta.url), JSON.stringify({
  entorno, ejecucion, terminadoEn: new Date().toISOString(), pruebas,
  alcance: 'Escritor Avance para perfil existente, cuenta/cronograma/titularidad documental/Portal. El job PDF se reserva; falta probar su generación y recuperación real y el alta Auth desde cooperativa.',
}, null, 2) + '\n');
console.log(`Avance existente F4: ${pruebas.length} comprobaciones, contratos PEN/USD, Portal autorizado y recuperación transaccional conformes.`);
