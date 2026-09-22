#!/usr/bin/env node
// Seis herramientas de Jev para conducir una auditoría. Jev opina sobre el
// TEXTO de los hallazgos; las cifras del negocio no pasan por aquí.
//
//   triaje    <hallazgos.json>            evidencia + duplicado + lente + hipótesis
//   contexto  <consulta> <extractos.json> ordena extractos por lo que aportan
//   estancada <hilo.json>                 ¿la revisión ya solo repite?
//   resuelto  <hallazgo.json> <cambio.json>  ¿el arreglo cierra el hallazgo?
//   calibrar  <hallazgos.json> <veredictos.tsv>  contrasta con lo ya juzgado
//
// Salida: JSON por stdout (`--salida f.json` para archivo) y un resumen legible
// por stderr. Ningún comando escribe en la base ni en producción.
import { readFile, writeFile } from 'node:fs/promises';
import { preguntar, leerClave, enParalelo, codigoDeError } from './cliente.mjs';
import {
  triaje, relevancia, estancada, resuelto, clasificarContador,
  decidir, veredictoResuelto, veredictoEstancada, UMBRALES,
} from './preguntas.mjs';

const args = process.argv.slice(2);
const comando = args[0];
const opcion = (nombre, pordefecto) => {
  const i = args.indexOf(`--${nombre}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : pordefecto;
};
const posicionales = args.slice(1).filter((a, i, l) => !a.startsWith('--') && !(i > 0 && l[i - 1].startsWith('--')));
const leerJson = async (r) => JSON.parse(await readFile(r, 'utf8'));
const aviso = (...m) => process.stderr.write(`${m.join(' ')}\n`);

async function emitir(datos) {
  const ruta = opcion('salida', null);
  const texto = JSON.stringify(datos, null, 2);
  if (ruta) { await writeFile(ruta, `${texto}\n`); aviso(`→ ${ruta}`); }
  else process.stdout.write(`${texto}\n`);
}

async function cmdTriaje() {
  const hallazgos = await leerJson(posicionales[0]);
  const limite = Number(opcion('limite', hallazgos.length));
  const lote = hallazgos.slice(0, limite);
  const clave = await leerClave();
  const n = Number(opcion('paralelo', 6));
  aviso(`triaje de ${lote.length} hallazgos, ${n} en paralelo…`);
  const crudo = await enParalelo(lote, n, (h) => preguntar(triaje(h), { clave }));
  const filas = lote.map((h, i) => {
    const r = crudo[i];
    if (!r.ok) return { titulo: h.titulo, severidad: h.severidad, error: r.error };
    return {
      titulo: h.titulo,
      severidad: h.severidad,
      archivo: (h.archivo ?? '').split('/').slice(-1)[0],
      lineas: h.lineas,
      ...decidir(r.valor.respuestas),
      modelo: r.valor.modelo,
    };
  });
  const cuenta = (f) => filas.reduce((a, x) => { const k = f(x) ?? 'error'; a[k] = (a[k] ?? 0) + 1; return a; }, {});
  const resumen = { total: filas.length, por_accion: cuenta((x) => x.accion), por_grupo: cuenta((x) => x.grupo), por_lente: cuenta((x) => x.lente) };
  aviso(JSON.stringify(resumen, null, 1));
  await emitir({ generado: new Date().toISOString(), umbrales: UMBRALES, resumen, hallazgos: filas });
}

async function cmdContexto() {
  const consulta = posicionales[0];
  const extractos = await leerJson(posicionales[1]);
  const clave = await leerClave();
  const n = Number(opcion('paralelo', 6));
  aviso(`ordenando ${extractos.length} extractos…`);
  const crudo = await enParalelo(extractos, n, (e) => preguntar(relevancia(consulta, e), { clave }));
  const filas = extractos.map((e, i) => {
    const r = crudo[i];
    const a = r.ok ? r.valor.respuestas.relevancia : null;
    return { de: e.de, puntos: a?.score ?? null, confianza: a?.confidence ?? null, error: r.ok ? undefined : r.error };
  }).sort((a, b) => (b.puntos ?? -1) - (a.puntos ?? -1));
  const corte = Number(opcion('corte', 2));
  aviso(`${filas.filter((f) => (f.puntos ?? -1) >= corte).length} de ${filas.length} llegan al corte ${corte}`);
  await emitir({ consulta, corte, extractos: filas });
}

async function cmdEstancada() {
  const hilo = await leerJson(posicionales[0]);
  const clave = await leerClave();
  const { respuestas, modelo } = await preguntar(estancada(hilo), { clave });
  const v = { asunto: hilo.asunto, rondas: (hilo.rondas ?? []).length, ...veredictoEstancada(respuestas), modelo };
  aviso(v.estancada ? `ESTANCADA → ${v.accion}` : 'sigue viva');
  await emitir(v);
}

async function cmdResuelto() {
  const hallazgo = await leerJson(posicionales[0]);
  const cambio = posicionales[1].endsWith('.json')
    ? await leerJson(posicionales[1])
    : { descripcion: opcion('descripcion', ''), diff: await readFile(posicionales[1], 'utf8') };
  const clave = await leerClave();
  const { respuestas, modelo } = await preguntar(resuelto(hallazgo, cambio), { clave });
  const v = { titulo: hallazgo.titulo, ...veredictoResuelto(respuestas), modelo };
  aviso(`${v.cierra ? 'CIERRA' : 'NO CIERRA'} → ${v.motivo}`);
  await emitir(v);
}

/** Contrasta el triaje contra los 41 hallazgos que ya tienen veredicto humano.
 *  Sin esto los umbrales son los del manual, no los de esta casa. */
async function cmdCalibrar() {
  const triados = await leerJson(posicionales[0]);
  const tsv = await readFile(posicionales[1], 'utf8');
  const humano = new Map();
  for (const linea of tsv.split('\n').slice(1)) {
    const c = linea.split('\t');
    if (c.length < 3) continue;
    const [titulo, , veredicto] = c;
    const clave = titulo.trim().slice(0, 60);
    const sostenido = /sosten|confirm/i.test(veredicto);
    humano.set(clave, (humano.get(clave) ?? 0) + (sostenido ? 1 : 0));
  }
  const filas = (triados.hallazgos ?? triados).map((h) => {
    const k = (h.titulo ?? '').trim().slice(0, 60);
    return humano.has(k) ? { titulo: h.titulo, jev: h.evidencia, jev_veredicto: h.veredicto, humano_sostenido: humano.get(k) > 0 } : null;
  }).filter(Boolean);
  const acierta = filas.filter((f) => (f.jev_veredicto === 'sostenido') === f.humano_sostenido).length;
  aviso(`${filas.length} hallazgos con veredicto humano; coincide en ${acierta}`);
  await emitir({ comparados: filas.length, coinciden: acierta, filas });
}

async function cmdClasificar() {
  const contadores = await leerJson(posicionales[0]);
  const clave = await leerClave();
  const n = Number(opcion('paralelo', 8));
  aviso(`clasificando ${contadores.length} contadores…`);
  const crudo = await enParalelo(contadores, n, (c) => preguntar(clasificarContador(c), { clave }));
  const filas = contadores.map((c, i) => {
    const r = crudo[i];
    if (!r.ok) return { nombre: c.titulo, error: r.error };
    const a = r.valor.respuestas;
    const conf = a.clase?.confidence ?? 0;
    return {
      nombre: c.titulo,
      // Umbral MEDIDO el 21/09 para las elecciones de Jev: por debajo de 0.80
      // aparecieron errores. Lo dudoso va a una persona, no se adivina.
      clase: conf >= UMBRALES.confianza ? a.clase?.choice : 'revisar',
      confianza: Number(conf.toFixed(2)),
      contradice_al_nucleo: a.contradice_al_nucleo?.noul ?? null,
      razon_declarada: (c.evidencia ?? '').slice(0, 110),
    };
  });
  const cuenta = filas.reduce((m, f) => { m[f.clase ?? 'error'] = (m[f.clase ?? 'error'] ?? 0) + 1; return m; }, {});
  aviso(JSON.stringify(cuenta, null, 1));
  await emitir({ generado: new Date().toISOString(), umbral: UMBRALES.confianza, resumen: cuenta, contadores: filas });
}

const comandos = { clasificar: cmdClasificar, triaje: cmdTriaje, contexto: cmdContexto, estancada: cmdEstancada, resuelto: cmdResuelto, calibrar: cmdCalibrar };

if (!comandos[comando]) {
  aviso('uso: auditor.mjs <triaje|contexto|estancada|resuelto|calibrar> … [--salida f.json] [--paralelo 6] [--limite n]');
  process.exit(2);
}
try {
  await comandos[comando]();
} catch (e) {
  aviso(`FALLO: ${codigoDeError(e)}${e?.message?.startsWith('sin_clave') ? ` — ${e.message}` : ''}`);
  process.exit(1);
}
