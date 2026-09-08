// Ejecutar con Deno y el deno.json del generador: usa su SDK y adaptador reales.
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { setTimeout as esperar } from 'node:timers/promises';
import { sql, literal as q, leer, guardar, sesion, rpc, http, storageEnBanco } from './banco-local.mjs';
import { contratoPrueba } from './operaciones-fixture.mjs';
import { pdfEnBanco, pedirPdf, descargarFirmado, pdfBucket } from './pdf-fixture.mjs';
import { crearStorageContratoPdfV2, STORAGE_PLAZO_MS } from '../../functions/crm-contrato-pdf-v2/storage.ts';

const f = leer('fixtures.json');
const base = leer('operaciones-base.json');
const token = await sesion(f.usuarios.vendedor, f.password);
const ejecucion = randomUUID();
const pruebas = [];
const contratos = [];
const normal = pdfEnBanco(undefined, storageEnBanco(crearStorageContratoPdfV2));
const flag = sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'") === 't';
const ok = (r, nombre) => { assert.equal(r.ok, true, `${nombre}: ${JSON.stringify(r.data)}`); return r.data; };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const estado = id => JSON.parse(sql(`select jsonb_build_object('id',id,'estado',estado,
  'intentos',intentos,'lease_expira_en',lease_expira_en,'ultimo_error',ultimo_error,'storage_path',storage_path,
  'snapshot_sha',encode(extensions.digest(snapshot::text,'sha256'),'hex'))
  from private.contrato_pdf_jobs where contrato_id=${q(id)}`));
const objetos = c => Number(sql(`select count(*) from storage.objects where bucket_id=${q(pdfBucket)}
  and name=${q(c.inicial.storage_path)}`));
const bien = (nombre, datos = {}) => {
  pruebas.push({ nombre, conforme: true, ...datos });
  console.log(`Bordes PDF F4: ${nombre}`);
};
async function nuevo(etiqueta) {
  const clave = randomUUID();
  const datos = { inversionista_id: base.identidades.avance, empresa: 'avance',
    ...contratoPrueba(f.usuarios.cliente.id, f.usuarios.vendedor.id,
      { inicio: '2026-09-01', capital: 1400 }) };
  ok(await rpc('preparar_inversion_fn', { p_clave: clave, p_datos: datos }, token), 'Preparar');
  const res = ok(await rpc('confirmar_inversion_fn', { p_solicitud: clave }, token), 'Confirmar');
  const c = { etiqueta, id: res.fuente.id, inversionId: res.inversion_id, clave };
  c.inicial = estado(c.id);
  assert.equal(c.inicial.intentos, 0);
  contratos.push(c);
  guardar(`pdf-bordes-${ejecucion}-progreso.json`, { contratos, pruebas });
  return c;
}
async function recuperar(c, respuesta) {
  const r = respuesta ?? await http('/functions/v1/crm-contrato-pdf-v2', {
    token, body: { action: 'ensure', contratoId: c.id },
  });
  const data = ok(r, 'Generar/recuperar por Deno');
  assert.equal(data.pdf.estado, 'sellado');
  const bytes = await descargarFirmado(data.url);
  assert.equal(hash(bytes), data.pdf.sha256);
  assert.equal(bytes.length, data.pdf.bytes);
  const repetida = ok(await pedirPdf(normal, token, c.id, 'status'), 'Releer sellado');
  assert.equal(repetida.pdf.sha256, data.pdf.sha256);
  assert.deepEqual(await descargarFirmado(repetida.url), bytes);
  const final = estado(c.id);
  assert.equal(final.id, c.inicial.id);
  assert.equal(final.snapshot_sha, c.inicial.snapshot_sha);
  assert.equal(objetos(c), 1);
  assert.equal(sql(`select count(*) from private.contrato_pdfs where contrato_id=${q(c.id)}`), '1');
  assert.equal(sql(`select count(*) from crm.inversiones where contrato_id=${q(c.id)}`), '1');
  assert.equal(ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.clave }, token), 'Repetir inversión').inversion_id, c.inversionId);
  return { intentos: final.intentos, sha256: data.pdf.sha256, bytes: bytes.length };
}
const ubicar = (input, init) => ({
  url: new URL(input instanceof Request ? input.url : String(input)),
  method: (init?.method ?? (input instanceof Request ? input.method : 'GET')).toUpperCase(),
});

ok(await http('/functions/v1/crm-contrato-pdf-v2', { token, method: 'OPTIONS' }), 'Runtime disponible');
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
try {
  for (const [paso, corte] of [['subir', 'cabeceras'], ['subir', 'cuerpo'], ['descargar', 'cuerpo'], ['firmar', 'cuerpo']]) {
    const c = await nuevo(`Timeout ${paso} ${corte}`);
    let interceptado = false;
    let aborto = false;
    const storage = storageEnBanco(crearStorageContratoPdfV2, { fetchImpl: async (input, init) => {
      const { url, method } = ubicar(input, init);
      const objetivo = paso === 'firmar' ? url.pathname.startsWith(`/storage/v1/object/sign/${pdfBucket}/`)
        : url.pathname === `/storage/v1/object/${pdfBucket}/${c.inicial.storage_path}`
          && method === (paso === 'subir' ? 'POST' : 'GET');
      if (interceptado || !objetivo) return fetch(input, init);
      interceptado = true;
      if (corte === 'cabeceras') return new Promise((_resuelve, rechaza) => {
        init.signal.addEventListener('abort', () => { aborto = true; rechaza(init.signal.reason); }, { once: true });
      });
      const real = await fetch(input, init);
      assert.equal(real.ok, true, 'El corte de cuerpo debe seguir a una operación real satisfactoria');
      await real.arrayBuffer(); // El servicio confirmó el resultado antes de perder su respuesta.
      const bloqueado = new ReadableStream({ start(controller) {
        init.signal.addEventListener('abort', () => {
          aborto = true;
          controller.error(init.signal.reason);
        }, { once: true });
      } });
      return new Response(bloqueado, { status: real.status, headers: real.headers });
    } });
    console.log(`Bordes PDF F4: ensayo ${paso}/${corte}, límite real ${STORAGE_PLAZO_MS / 1000}s.`);
    const inicio = performance.now();
    const fallido = await pedirPdf(pdfEnBanco(undefined, storage), token, c.id);
    const duracionMs = Math.round(performance.now() - inicio);
    assert.equal(interceptado, true);
    assert.equal(aborto, true);
    assert.equal(fallido.status, 503, JSON.stringify(fallido.data));
    assert(duracionMs >= STORAGE_PLAZO_MS && duracionMs < STORAGE_PLAZO_MS + 5000, 'La espera debe estar acotada por el adaptador');
    const parcial = estado(c.id);
    assert.equal(parcial.estado, paso === 'firmar' ? 'sellado' : 'error_reintentable');
    assert.equal(parcial.lease_expira_en, null);
    assert.equal(objetos(c), corte === 'cabeceras' ? 0 : 1);
    const final = await recuperar(c);
    assert.equal(final.intentos, paso === 'firmar' ? 1 : 2);
    bien(`Timeout ${paso}/${corte} y recuperación Deno`, { duracionMs, ...final });
  }

  for (const [momento, version] of [['reserva', 'contrato-aep-17-v6'], ['reclamo', 'contrato-aep-17-v6'], ['reclamo', 'contrato-aep-17-v8']]) {
    const c = await nuevo(`Incompatibilidad ${momento} ${version}`);
    const paso = momento === 'reserva' ? 'contrato_pdf_reservar' : 'contrato_pdf_reclamar';
    let cambiado = false;
    const incompatible = pdfEnBanco(async (nombre, ejecutar) => {
      const r = await ejecutar();
      if (nombre === paso) {
        assert.equal(r.error, null);
        cambiado = true;
        return { ...r, data: { ...r.data, template_version: version } };
      }
      return r;
    }, storageEnBanco(crearStorageContratoPdfV2));
    const fallido = await pedirPdf(incompatible, token, c.id);
    assert.equal(cambiado, true);
    assert.equal(fallido.status, version.endsWith('v8') ? 502 : 409);
    const parcial = estado(c.id);
    assert.equal(parcial.intentos, momento === 'reserva' ? 0 : 1);
    assert.equal(parcial.estado, momento === 'reserva' ? 'pendiente' : 'error_reintentable');
    assert.equal(parcial.lease_expira_en, null);
    assert.equal(objetos(c), 0);
    assert.equal(parcial.snapshot_sha, c.inicial.snapshot_sha);
    bien(`Versión recibida incompatible en ${momento} ${version}: reserva libre y recuperación`, await recuperar(c));
  }

  const tardio = await nuevo('Worker tardío y colisión de subida');
  let liberar, avisar, avisarSubido;
  const permiso = new Promise(resolve => { liberar = resolve; });
  const retenido = new Promise(resolve => { avisar = resolve; });
  const subido = new Promise(resolve => { avisarSubido = resolve; });
  const viejo = pdfEnBanco(async (nombre, ejecutar) => {
    if (nombre !== 'subir') return ejecutar();
    avisar();
    await permiso;
    const r = await ejecutar();
    assert.equal(r.error, null, 'La subida tardía debe guardar el archivo real');
    avisarSubido();
    return r;
  }, storageEnBanco(crearStorageContratoPdfV2));
  const primero = pedirPdf(viejo, token, tardio.id);
  try {
    await Promise.race([retenido, primero.then(() => { throw new Error('El worker terminó antes de retener su subida'); })]);
    const expira = Date.parse(estado(tardio.id).lease_expira_en);
    assert.equal(objetos(tardio), 0);
    while (Date.now() <= expira + 1000) {
      const falta = expira + 1000 - Date.now();
      console.log(`Bordes PDF F4: worker retenido; espera real de reserva ${Math.ceil(falta / 1000)}s.`);
      await esperar(Math.min(20_000, falta));
    }
    let intercalado = false;
    let primeroFinal;
    const colision = storageEnBanco(crearStorageContratoPdfV2, { fetchImpl: async (input, init) => {
      const r = await fetch(input, init);
      const { url, method } = ubicar(input, init);
      if (!intercalado && method === 'GET' && url.pathname === `/storage/v1/object/${pdfBucket}/${tardio.inicial.storage_path}`) {
        assert.equal(r.ok, false, 'La consulta del nuevo worker aún no debe encontrar objeto');
        assert.equal(Number((await r.clone().json()).statusCode), 404);
        intercalado = true;
        assert.equal(estado(tardio.id).intentos, 2);
        liberar();
        await subido;
        primeroFinal = await primero;
        assert.equal(primeroFinal.status, 409, 'El worker viejo no puede verificar/sellar con su lease vencido');
        assert.equal(objetos(tardio), 1);
      }
      return r; // Mantiene la respuesta de ausencia que precedió a la subida tardía.
    } });
    const inicio = performance.now();
    const segundo = await pedirPdf(pdfEnBanco(undefined, colision), token, tardio.id);
    const duracionMs = Math.round(performance.now() - inicio);
    assert.equal(intercalado, true);
    assert([200, 503].includes(segundo.status), JSON.stringify(segundo.data));
    assert(duracionMs < STORAGE_PLAZO_MS + 5000, 'La colisión no puede dejar el cliente esperando indefinidamente');
    const final = await recuperar(tardio, segundo.status === 200 ? segundo : undefined);
    assert.equal(final.intentos, segundo.status === 200 ? 2 : 3);
    bien('Subida tardía tras ausencia: lease viejo rechazado, colisión acotada y un solo PDF',
      { respuestaColision: segundo.status, duracionMs, ...final });
  } finally {
    liberar();
    await primero;
  }

  for (const numero of ['F4-BASE-INICIAL', 'F4-BASE-UPGRADE-MISMO-MES']) {
    const id = sql(`select id from public.contratos where numero_contrato=${q(numero)}`);
    assert(id, 'Falta el antecedente preparado antes de F4');
    const antes = sql(`select row_to_json(c) from public.contratos c where id=${q(id)}`);
    assert.equal(sql(`select count(*) from private.contrato_pdf_jobs where contrato_id=${q(id)}`), '0');
    for (const action of ['ensure', 'status']) {
      const r = await http('/functions/v1/crm-contrato-pdf-v2', { token, body: { action, contratoId: id } });
      assert.equal(r.status, 202);
      assert.equal(r.data.pdf.estado, 'sin_reserva');
      assert.equal(r.data.pdf.reintentable, false);
    }
    assert.equal(sql(`select row_to_json(c) from public.contratos c where id=${q(id)}`), antes);
    assert.equal(sql(`select count(*) from private.contrato_pdf_jobs where contrato_id=${q(id)}`), '0');
    bien(`Régimen anterior ${numero}: conserva contrato sin generar documento nuevo`);
  }
  for (const c of contratos) assert.equal(estado(c.id).estado, 'sellado');
  guardar(`pdf-bordes-${ejecucion}.json`, { contratos, pruebas });
  writeFileSync(new URL(`../evidencia-f4/pdf-bordes-${ejecucion}.json`, import.meta.url), JSON.stringify({
    entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(), pruebas,
    contratos: contratos.length, plazoStorageMs: STORAGE_PLAZO_MS,
    plantillaModificada: false, estadosSqlFabricados: false,
    limite: 'Las versiones incompatibles se inyectan en la respuesta al worker; no se edita la versión ni el snapshot contractual real. Prueba local, sin cierre de G4.',
  }, null, 2) + '\n', { flag: 'wx' });
  console.log(`Bordes PDF F4: ${pruebas.length} grupos conformes; ${contratos.length} contratos sellados.`);
} catch (error) {
  guardar(`pdf-bordes-${ejecucion}-interrumpido.json`, { contratos, pruebas,
    error: { nombre: error.name, mensaje: error.message } });
  throw error;
} finally {
  sql(`update crm.multiempresa_flags set activo=${flag} where nombre='inversiones_escritura'`);
}
