import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { sql, literal as q, leer, guardar, sesion, rpc, http } from './banco-local.mjs';

const f = leer('fixtures.json');
const base = leer('operaciones-base.json');
const ejecucion = randomUUID();
const pruebas = [];
const bien = (nombre, detalle = {}) => pruebas.push({ nombre, ...detalle, conforme: true });
const tokens = Object.fromEntries(await Promise.all(Object.entries(f.usuarios)
  .map(async ([rol, u]) => [rol, await sesion(u, f.password)])));
const fecha = sql("select (statement_timestamp() at time zone 'America/Lima')::date");
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aT9sAAAAASUVORK5CYII=', 'base64');
const contadores = () => JSON.parse(sql(`select jsonb_build_object(
  'auth',(select count(*) from auth.users),'identidades',(select count(*) from crm.inversionistas),
  'leads',(select count(*) from crm.leads),'contratos',(select count(*) from public.contratos),
  'cierres',(select count(*) from crm.cierres_externos),'inversiones',(select count(*) from crm.inversiones))`));
const conversion = () => JSON.parse(sql(`select coalesce(jsonb_agg(to_jsonb(c) order by to_jsonb(c)::text),'[]')
  from private.conversion_episodios('2026-09-01T00:00:00-05:00','2026-10-01T00:00:00-05:00','2026-09-01',true,'{}',0.15) c`));
const antes = contadores();
const conversionAntes = conversion();
function datos(persona, empresa, monto = 700) {
  const clave = randomUUID();
  return { clave, payload: { inversionista_id: persona, empresa, monto, moneda: 'PEN',
    fecha_comercial: fecha, vence_en: '2027-09-07', numero_transaccion: `F4-${clave}`,
    referencia: `PRUEBA-${ejecucion}`, evidencia: { ruta: `${persona}/${clave}/comprobante.png` } } };
}
async function preparar(caso, rol = 'vendedor') {
  return rpc('preparar_inversion_fn', { p_clave: caso.clave, p_datos: caso.payload }, tokens[rol]);
}
async function confirmar(caso, rol = 'vendedor') {
  return rpc('confirmar_inversion_fn', { p_solicitud: caso.clave }, tokens[rol]);
}
async function subir(caso, rol = 'vendedor', upsert = false) {
  return http(`/storage/v1/object/f4-comprobantes/${caso.payload.evidencia.ruta}`, {
    token: tokens[rol], rawBody: png, headers: { 'Content-Type': 'image/png', 'x-upsert': String(upsert) },
  });
}
function ok(r, nombre) { assert.equal(r.ok, true, `${nombre}: ${JSON.stringify(r.data)}`); return r.data; }
function error(r, codigo, nombre) {
  assert.equal(r.ok, false, `${nombre}: se permitió una operación prohibida`);
  if (codigo) assert.equal(r.data.code, codigo, `${nombre}: ${JSON.stringify(r.data)}`);
}

// El único interruptor que mueve este oráculo pertenece al banco local.
sql("update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura'");
const principal = datos(base.identidades.avance, 'qorilazo');
error(await preparar(principal), 'P0409', 'bandera apagada');
assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(principal.clave)}`), '0');
bien('Apagado impide preparar sin efectos');
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
for (const rol of ['ajeno', 'supervisor_ajeno', 'directorio', 'cliente']) {
  error(await preparar(principal, rol), '42501', `preparar ${rol}`);
  bien(`Ámbito y rol: ${rol} no prepara`);
}
ok(await preparar(principal), 'preparación Avance a Qorilazo');
ok(await preparar(principal), 'repetición de preparación');
assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(principal.clave)}`), '1');
error(await preparar({ ...principal, payload: { ...principal.payload, monto: 701 } }), 'P0409', 'misma clave otro monto');
assert.equal(sql(`select datos->>'monto' from crm.inversion_solicitudes where id=${q(principal.clave)}`), '700');
bien('Misma clave conserva solicitud y rechaza otro contenido');
error(await confirmar(principal), 'P0409', 'sin comprobante');
assert.deepEqual(contadores(), antes);
bien('Sin comprobante no quedan fuente, inversión ni titular finales');
error(await subir(principal, 'ajeno'), null, 'archivo fuera de ámbito');
ok(await subir(principal), 'carga real de comprobante');
for (const rol of ['ajeno', 'directorio', 'cliente']) {
  error(await confirmar(principal, rol), '42501', `confirmar ${rol}`);
  bien(`Permisos se vuelven a comprobar al confirmar: ${rol}`);
}

const casos = [principal, datos(base.identidades.qorilazo, 'prodelco', 800),
  datos(base.identidades.qorilazo, 'qorilazo', 900)];
const resultados = [];
for (const [indice, caso] of casos.entries()) {
  if (indice > 0) { ok(await preparar(caso), 'preparar cooperativa'); ok(await subir(caso), 'subir comprobante'); }
  const res = ok(await confirmar(caso), 'confirmar inversión');
  resultados.push({ caso, res });
  const filas = JSON.parse(sql(`select jsonb_build_object('persona',i.inversionista_id,'empresa',e.clave,
    'lead',ce.lead_id,'monto',ce.monto,'moneda',ce.moneda,'fecha',ce.fecha_comercial,
    'imputacion',ce.fecha_imputacion,'vence',ce.vence_en,'inicial',ce.es_cierre_inicial,
    'deposito',ce.numero_transaccion,'referencia',ce.referencia_externa,'autor',ce.creado_por,
    'analista',ce.vendedor_id,'principal',it.inversionista_id,'objeto',o.name,
    'solicitud',s.estado) from crm.inversiones i join crm.empresas e on e.id=i.empresa_id
    join crm.cierres_externos ce on ce.id=i.cierre_externo_id
    join crm.inversion_titulares it on it.inversion_id=i.id and it.rol='principal'
    join storage.objects o on o.id=ce.comprobante_objeto_id
    join crm.inversion_solicitudes s on s.inversion_id=i.id where i.id=${q(res.inversion_id)}`));
  assert.deepEqual(filas, { persona: caso.payload.inversionista_id, empresa: caso.payload.empresa,
    lead: indice === 0 ? base.leads.avance : base.leads.qorilazo,
    monto: caso.payload.monto, moneda: 'PEN', fecha, imputacion: fecha, vence: '2027-09-07', inicial: false,
    deposito: caso.payload.numero_transaccion.toUpperCase(), referencia: caso.payload.referencia,
    autor: f.usuarios.vendedor.id, analista: f.usuarios.vendedor.id, principal: caso.payload.inversionista_id,
    objeto: caso.payload.evidencia.ruta, solicitud: 'confirmada' });
  const repetido = ok(await confirmar(caso), 'reintento confirmado');
  assert.equal(repetido.inversion_id, res.inversion_id);
  assert.equal(repetido.reintento, true);
  const archivo = ok(await http(`/storage/v1/object/authenticated/f4-comprobantes/${caso.payload.evidencia.ruta}`, {
    method: 'GET', token: tokens.vendedor, binary: true,
  }), 'descarga autorizada');
  assert.deepEqual(archivo, png);
  bien(['Avance a Qorilazo', 'Qorilazo a Prodelco', 'Segunda inversión Qorilazo'][indice],
    { monto: caso.payload.monto, moneda: 'PEN', fuenteTitularHistoriaYComprobante: true, reintentoSinDuplicado: true });
}
error(await subir(principal, 'vendedor', true), null, 'sustitución de comprobante');
for (const rol of ['ajeno', 'directorio', 'cliente']) {
  error(await http(`/storage/v1/object/authenticated/f4-comprobantes/${principal.payload.evidencia.ruta}`, {
    method: 'GET', token: tokens[rol], binary: true,
  }), null, `lectura de comprobante ${rol}`);
}
bien('Comprobante conservado y lectura limitada al ámbito comercial');
const despues = contadores();
assert.deepEqual(despues, { ...antes, cierres: antes.cierres + 3, inversiones: antes.inversiones + 3 });
assert.deepEqual(conversion(), conversionAntes, 'Las inversiones adicionales no alteran la elegibilidad vigente');
bien('Mismas personas, leads, Auth y contratos; tres nuevas fuentes e inversiones');
bien('Conversión existente conservada sin nuevos aportes por inversión cooperativa adicional');
guardar(`cooperativas-${ejecucion}.json`, { resultados });
const informe = { entorno, ejecucion, terminadoEn: new Date().toISOString(), pruebas,
  sha256ComprobanteSintetico: createHash('sha256').update(png).digest('hex'),
  alcance: 'Circuito cooperativo y permisos por HTTP/Auth/Storage reales. Concurrencia, Auth Avance, historia, comisión y recuperación completa pendientes.',
};
writeFileSync(new URL(`../evidencia-f4/cooperativas-${ejecucion}.json`, import.meta.url), JSON.stringify(informe, null, 2) + '\n');
console.log(`Cooperativas F4: ${pruebas.length} comprobaciones conformes; 3 recorridos confirmados con evidencia real y sin duplicar identidad ni lead.`);
