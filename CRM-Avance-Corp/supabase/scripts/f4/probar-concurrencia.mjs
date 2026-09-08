import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { sql, literal as q, leer, sesion, rpc, http } from './banco-local.mjs';
import { retener, esperarActividad, sqlEnProceso } from './candados-prueba.mjs';

const f = leer('fixtures.json');
const base = leer('operaciones-base.json');
const token = await sesion(f.usuarios.vendedor, f.password);
const ejecucion = randomUUID();
const pruebas = [];
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aT9sAAAAASUVORK5CYII=', 'base64');
const fecha = sql("select (statement_timestamp() at time zone 'America/Lima')::date");
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
function datos(persona, empresa, deposito = null) {
  const clave = randomUUID();
  return { clave, payload: { inversionista_id: persona, empresa, monto: 123, moneda: 'PEN',
    numero_transaccion: deposito ?? `F4-${clave}`, referencia: `CARRERA-${ejecucion}`,
    fecha_comercial: fecha, vence_en: '2027-09-07', evidencia: { ruta: `${persona}/${clave}/comprobante.png` } } };
}
function ok(r) { assert.equal(r.ok, true, JSON.stringify(r.data)); return r.data; }
const preparar = c => rpc('preparar_inversion_fn', { p_clave: c.clave, p_datos: c.payload }, token);
const confirmar = c => rpc('confirmar_inversion_fn', { p_solicitud: c.clave }, token);
async function dejarLista(c) {
  ok(await preparar(c));
  ok(await http(`/storage/v1/object/f4-comprobantes/${c.payload.evidencia.ruta}`, {
    token, rawBody: png, headers: { 'Content-Type': 'image/png', 'x-upsert': 'false' },
  }));
}
async function carrera(nombreRpc, llamadas) {
  const soltar = await retener("select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'))");
  const pendientes = llamadas.map(fn => fn());
  let observados;
  try {
    observados = await esperarActividad(`a.query like '%${nombreRpc}%' and a.wait_event='advisory'`, llamadas.length);
  } finally { await soltar(); }
  const respuestas = await Promise.all(pendientes);
  return { respuestas, observados };
}

const deposito = `F4-CARRERA-${randomUUID()}`;
const izquierda = datos(base.identidades.avance, 'qorilazo', deposito);
const derecha = datos(base.identidades.qorilazo, 'prodelco', deposito);
await dejarLista(izquierda);
await dejarLista(derecha);
const duplicado = await carrera('confirmar_inversion_fn', [() => confirmar(izquierda), () => confirmar(derecha)]);
assert.equal(duplicado.respuestas.filter(x => x.ok).length, 1);
assert.equal(duplicado.respuestas.find(x => !x.ok).data.code, 'P0409');
assert.equal(sql(`select count(*) from crm.cierres_externos where numero_transaccion=${q(deposito.toUpperCase())}`), '1');
assert.equal(sql(`select count(*) from crm.depositos_reclamados where numero_norm=${q(deposito.toUpperCase())}`), '1');
assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id in (${q(izquierda.clave)},${q(derecha.clave)}) and estado='confirmada'`), '1');
assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id in (${q(izquierda.clave)},${q(derecha.clave)}) and estado='preparada' and inversion_id is null`), '1');
pruebas.push({ nombre: 'Depósito simultáneo en Qorilazo y Prodelco, personas distintas', procesosCoincidentes: duplicado.observados,
  fuentes: 1, reclamaciones: 1, inversionesConfirmadas: 1, perdedoraSinEfectosFinales: true });

const repetida = datos(base.identidades.prodelco, 'qorilazo');
await dejarLista(repetida);
const misma = await carrera('confirmar_inversion_fn', [() => confirmar(repetida), () => confirmar(repetida)]);
const respuestas = misma.respuestas.map(ok);
assert.equal(respuestas[0].inversion_id, respuestas[1].inversion_id);
assert.equal(respuestas.filter(x => x.reintento).length, 1);
assert.equal(sql(`select count(*) from crm.cierres_externos where numero_transaccion=${q(repetida.payload.numero_transaccion.toUpperCase())}`), '1');
pruebas.push({ nombre: 'Misma confirmación simultánea', procesosCoincidentes: misma.observados, mismoResultado: true, fuentes: 1 });

const otra = datos(base.identidades.prodelco, 'prodelco');
const conflicto = await carrera('preparar_inversion_fn', [() => preparar(otra),
  () => preparar({ ...otra, payload: { ...otra.payload, monto: 124 } })]);
assert.equal(conflicto.respuestas.filter(x => x.ok).length, 1);
assert.equal(conflicto.respuestas.find(x => !x.ok).data.code, 'P0409');
assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(otra.clave)}`), '1');
pruebas.push({ nombre: 'Misma clave con contenido distinto simultáneamente', procesosCoincidentes: conflicto.observados,
  solicitudes: 1, conflictoSinSobrescritura: true });

const enVuelo = datos(base.identidades.avance, 'prodelco');
await dejarLista(enVuelo);
const soltarPersona = await retener(`select id from crm.inversionistas where id=${q(base.identidades.avance)} for update`);
const confirmacion = confirmar(enVuelo);
let apagado;
let confirmacionObservada;
let apagadoObservado;
try {
  confirmacionObservada = await esperarActividad("a.query like '%confirmar_inversion_fn%' and a.wait_event='transactionid'", 1);
  apagado = sqlEnProceso("update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura'; select activo from crm.multiempresa_flags where nombre='inversiones_escritura';");
  apagadoObservado = await esperarActividad("a.query like '%update crm.multiempresa_flags set activo=false%' and a.wait_event='advisory'", 1);
} finally { await soltarPersona(); }
const confirmada = ok(await confirmacion);
assert( confirmada.inversion_id );
assert.equal(await apagado, 'f');
const cerrada = await preparar(datos(base.identidades.avance, 'qorilazo'));
assert.equal(cerrada.ok, false);
assert.equal(cerrada.data.code, 'P0409');
pruebas.push({ nombre: 'Apagado espera a la confirmación en vuelo y detiene nuevas operaciones',
  confirmacionesObservadas: confirmacionObservada, apagadosObservados: apagadoObservado,
  operacionEnVueloCompleta: true, banderaFinal: false });

writeFileSync(new URL(`../evidencia-f4/concurrencia-${ejecucion}.json`, import.meta.url), JSON.stringify({
  entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(), pruebas,
  criterio: 'La coincidencia se comprobó en pg_stat_activity antes de soltar cada candado; no se infiere solo de Promise.all.',
}, null, 2) + '\n');
console.log('Concurrencia F4: 4 carreras observadas dentro de PostgreSQL, depósito único, idempotencia y apagado con operación en vuelo conformes.');
