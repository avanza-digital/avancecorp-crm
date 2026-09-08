import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { setTimeout as esperar } from 'node:timers/promises';
import { banco, sql, literal as q, leer, guardar, sesion, rpc, http } from './banco-local.mjs';
import { contratoPrueba } from './operaciones-fixture.mjs';
import { pdfEnBanco, pedirPdf, descargarFirmado, pdfBucket } from './pdf-fixture.mjs';

const f = leer('fixtures.json');
const base = leer('operaciones-base.json');
const ejecucion = randomUUID();
const pruebas = [];
const contratos = [];
const privados = [];
const t = await sesion(f.usuarios.vendedor, f.password);
const ajeno = await sesion(f.usuarios.ajeno, f.password);
const disponible = await http('/functions/v1/crm-contrato-pdf-v2', { token: t, method: 'OPTIONS' });
assert.equal(disponible.ok, true, 'Esperar a que termine el reinicio del runtime antes de crear fixtures PDF');
const normal = pdfEnBanco();
async function pedirPdfDeno(contratoId, action = 'ensure') {
  const inicio = performance.now();
  const respuesta = await http('/functions/v1/crm-contrato-pdf-v2', {
    token: t, body: { action, contratoId },
  });
  return { ...respuesta, duracionMs: Math.round(performance.now() - inicio) };
}
const flag = sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'") === 't';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const ok = (r, nombre) => {
  assert.equal(r.ok, true, `${nombre}: ${JSON.stringify(r.data)}`);
  return r.data;
};
const contadores = () => JSON.parse(sql(`select jsonb_build_object(
  'auth',(select count(*) from auth.users),'personas',(select count(*) from crm.inversionistas),
  'leads',(select count(*) from crm.leads),'contratos',(select count(*) from public.contratos),
  'inversiones',(select count(*) from crm.inversiones),'cuotas',(select count(*) from public.cronograma_pagos),
  'jobs',(select count(*) from private.contrato_pdf_jobs),'pdfs',(select count(*) from private.contrato_pdfs))`));
const estado = id => JSON.parse(sql(`select jsonb_build_object('id',id,'estado',estado,
  'intentos',intentos,'lease_expira_en',lease_expira_en,'storage_path',storage_path,
  'snapshot_sha',encode(extensions.digest(snapshot::text,'sha256'),'hex'))
  from private.contrato_pdf_jobs where contrato_id=${q(id)}`));
const bien = (nombre, detalle = {}) => {
  pruebas.push({ nombre, conforme: true, ...detalle });
  console.log(`PDF F4: ${nombre}`);
};
async function nuevo(etiqueta, moneda = 'PEN') {
  const clave = randomUUID();
  const payload = { inversionista_id: base.identidades.avance, empresa: 'avance',
    ...contratoPrueba(f.usuarios.cliente.id, f.usuarios.vendedor.id,
      { moneda, inicio: '2026-09-01', capital: 1500 }) };
  payload.contrato.titulares = [{ nombre_completo: 'COTITULAR FICTICIO F4 PDF',
    tipo_documento: 'DNI', documento: '92000002' }];
  ok(await rpc('preparar_inversion_fn', { p_clave: clave, p_datos: payload }, t), 'preparar');
  const res = ok(await rpc('confirmar_inversion_fn', { p_solicitud: clave }, t), 'confirmar');
  const id = res.fuente.id;
  const inicial = estado(id);
  assert.equal(inicial.estado, 'pendiente');
  assert.equal(inicial.intentos, 0);
  const contrato = { etiqueta, moneda, id, clave, inversionId: res.inversion_id, inicial };
  contratos.push(contrato);
  guardar(`pdf-real-${ejecucion}-progreso.json`, { ejecucion, contratos, pruebas, archivos: privados });
  return contrato;
}
async function comprobar(contrato, respuesta, { guardarPdf = false } = {}) {
  const r = respuesta ?? await pedirPdfDeno(contrato.id);
  const data = ok(r, `PDF ${contrato.etiqueta}`);
  assert.equal(r.status, 200);
  assert.equal(data.pdf.estado, 'sellado');
  assert(data.url);
  const bytes = await descargarFirmado(data.url);
  assert.equal(hash(bytes), data.pdf.sha256);
  assert.equal(bytes.length, data.pdf.bytes);
  for (const action of ['ensure', 'status']) {
    const repetido = ok(await pedirPdfDeno(contrato.id, action), `${action} repetido`);
    assert.equal(repetido.pdf.job_id, data.pdf.job_id);
    assert.equal(repetido.pdf.sha256, data.pdf.sha256);
    assert.deepEqual(await descargarFirmado(repetido.url), bytes);
  }
  const final = estado(contrato.id);
  assert.equal(final.id, contrato.inicial.id);
  assert.equal(final.snapshot_sha, contrato.inicial.snapshot_sha);
  assert.equal(sql(`select count(*) from private.contrato_pdfs where contrato_id=${q(contrato.id)}`), '1');
  assert.equal(sql(`select count(*) from storage.objects where bucket_id=${q(pdfBucket)} and name=${q(final.storage_path)}`), '1');
  assert.equal(sql(`select count(*) from crm.inversiones where contrato_id=${q(contrato.id)}`), '1');
  const repetida = ok(await rpc('confirmar_inversion_fn', { p_solicitud: contrato.clave }, t), 'repetir inversión');
  assert.equal(repetida.inversion_id, contrato.inversionId);
  assert.equal(repetida.fuente.id, contrato.id);
  if (guardarPdf) {
    const carpeta = join(banco, 'pdf-real', ejecucion);
    mkdirSync(carpeta, { recursive: true });
    const archivo = join(carpeta, `contrato-ficticio-${contrato.moneda}.pdf`);
    writeFileSync(archivo, bytes, { mode: 0o600 });
    privados.push({ archivo, contratoId: contrato.id, sha256: hash(bytes), bytes: bytes.length });
  }
  return { sha256: hash(bytes), bytes: bytes.length, intentos: final.intentos,
    ...(r.duracionMs !== undefined ? { adaptador: 'Deno real', duracionMs: r.duracionMs } : {}) };
}
function falloAntes(paso) {
  let usado = false;
  return pdfEnBanco(async (nombre, ejecutar) => {
    if (nombre === paso && !usado) {
      usado = true;
      if (paso === 'renderizar') throw new Error('Fallo transitorio de render ficticio F4');
      return { data: null, url: null, error: { code: 'FALLO_TRANSITORIO_F4', statusCode: 503 } };
    }
    return ejecutar();
  });
}
function perderRespuesta(paso) {
  let usado = false;
  return pdfEnBanco(async (nombre, ejecutar) => {
    const r = await ejecutar();
    if (nombre === paso && !usado) {
      usado = true;
      assert.equal(r.error, null, `La respuesta perdida ${paso} debe haber tenido éxito real`);
      throw new Error(`RESPUESTA_PERDIDA_F4:${paso}`);
    }
    return r;
  });
}

const antes = contadores();
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
try {
  // Carga y generación por el entrypoint Deno y SDK de la aplicación real.
  for (const moneda of ['PEN', 'USD']) {
    const contrato = await nuevo(`Deno ${moneda}`, moneda);
    const deno = await pedirPdfDeno(contrato.id);
    bien(`Generación Deno ${moneda} y tres descargas idénticas`,
      await comprobar(contrato, deno, { guardarPdf: true }));
    const fuera = await pedirPdf(normal, ajeno, contrato.id, 'status');
    assert.equal(fuera.status, 403);
    for (const ruta of [
      `/storage/v1/object/${pdfBucket}/${contrato.inicial.storage_path}`,
      `/storage/v1/object/public/${pdfBucket}/${contrato.inicial.storage_path}`,
    ]) {
      const directo = await http(ruta, { token: t, method: 'GET', binary: true });
      assert.equal(directo.ok, false, 'El PDF privado fue legible por ruta directa');
    }
  }
  bien('PDF privado y equipo ajeno rechazado');

  // Cortes después de escrituras reales: se respeta el lease original de 120s.
  const pendientes = [];
  for (const paso of ['subir', 'contrato_pdf_marcar_subido']) {
    const contrato = await nuevo(`Respuesta perdida ${paso}`);
    await assert.rejects(pedirPdf(perderRespuesta(paso), t, contrato.id), /RESPUESTA_PERDIDA_F4/);
    const despues = estado(contrato.id);
    assert.equal(despues.estado, paso === 'subir' ? 'procesando' : 'subido_verificado');
    const ocupado = await pedirPdf(normal, t, contrato.id);
    assert.equal(ocupado.status, 202);
    assert.equal(estado(contrato.id).intentos, 1);
    pendientes.push({ contrato, expira: Date.parse(despues.lease_expira_en) });
  }

  for (const paso of ['renderizar', 'subir', 'descargar', 'firmar']) {
    const contrato = await nuevo(`Fallo transitorio ${paso}`);
    const fallido = await pedirPdf(falloAntes(paso), t, contrato.id);
    assert.equal(fallido.status, 503, JSON.stringify(fallido.data));
    assert.equal(estado(contrato.id).estado, paso === 'firmar' ? 'sellado' : 'error_reintentable');
    const objetosAntes = Number(sql(`select count(*) from storage.objects where bucket_id=${q(pdfBucket)}
      and name=${q(contrato.inicial.storage_path)}`));
    assert.equal(objetosAntes, ['renderizar', 'subir'].includes(paso) ? 0 : 1);
    bien(`Recuperación Deno tras fallo transitorio de ${paso}`,
      { objetosAntes, ...await comprobar(contrato) });
  }

  const sellado = await nuevo('Respuesta de sello perdida');
  await assert.rejects(pedirPdf(perderRespuesta('contrato_pdf_finalizar'), t, sellado.id), /RESPUESTA_PERDIDA_F4/);
  assert.equal(estado(sellado.id).estado, 'sellado');
  bien('Sello confirmado con respuesta perdida se reutiliza', await comprobar(sellado));

  const concurrente = await nuevo('Dos generadores concurrentes');
  let liberar, avisar;
  const retenido = new Promise(resolve => { liberar = resolve; });
  const entrando = new Promise(resolve => { avisar = resolve; });
  const lento = pdfEnBanco(async (nombre, ejecutar) => {
    if (nombre === 'renderizar') { avisar(); await retenido; }
    return ejecutar();
  });
  const primero = pedirPdf(lento, t, concurrente.id);
  try {
    await entrando;
    const segundo = await pedirPdf(normal, t, concurrente.id);
    assert.equal(segundo.status, 202);
    assert.equal(estado(concurrente.id).intentos, 1);
  } finally { liberar(); }
  bien('Dos generadores simultáneos producen un solo PDF', await comprobar(concurrente, await primero));

  for (const { contrato, expira } of pendientes) {
    while (Date.now() <= expira + 1000) {
      const falta = expira + 1000 - Date.now();
      console.log(`PDF F4: esperando lease real (${Math.ceil(falta / 1000)}s), sin alterar reloj ni reserva.`);
      await esperar(Math.min(20_000, falta));
    }
    const resultado = await comprobar(contrato);
    assert.equal(resultado.intentos, 2);
    bien(`Recuperación ${contrato.etiqueta} tras lease real`, resultado);
  }
  const despues = contadores();
  for (const tipo of ['auth', 'personas', 'leads']) assert.equal(despues[tipo], antes[tipo]);
  for (const tipo of ['contratos', 'inversiones', 'jobs', 'pdfs']) assert.equal(despues[tipo], antes[tipo] + contratos.length);
  assert.equal(despues.cuotas, antes.cuotas + contratos.length * 13);
  bien('Todas las operaciones del ensayo terminan con una fuente, un PDF sellado y su inversión');
  guardar(`pdf-real-${ejecucion}.json`, { ejecucion, contratos, archivos: privados });
  writeFileSync(new URL(`../evidencia-f4/pdf-real-${ejecucion}.json`, import.meta.url), JSON.stringify({
    entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(), pruebas,
    contratos: contratos.length, fuentesSinDuplicados: true,
    generador: 'Plantilla y renderer vigentes sin cambios; handler recupera el objeto existente antes de repetir su subida',
    limites: ['Revisión visual de los dos archivos en paso separado', 'La plantilla vigente no imprime cotitulares; cualquier incorporación exige aprobación de Miguel', 'Antecedentes sin reserva y permisos dinámicos se cubren en bloques posteriores', 'Pruebas locales; G4 completo sigue abierto'],
  }, null, 2) + '\n');
  console.log(`PDF F4: ${pruebas.length} grupos conformes; ${contratos.length} contratos sellados.`);
} catch (error) {
  guardar(`pdf-real-${ejecucion}-interrumpido.json`, { ejecucion, contratos, pruebas, archivos: privados,
    error: { nombre: error.name, mensaje: error.message }, terminadoEn: new Date().toISOString() });
  throw error;
} finally {
  sql(`update crm.multiempresa_flags set activo=${flag} where nombre='inversiones_escritura'`);
}
