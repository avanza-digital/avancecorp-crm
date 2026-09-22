// Dobles de DOM para ejecutar el controlador sin dependencias ni navegador.
// Comprueban estado/eventos; NO acreditan render, foco real, CSP o descarga a disco.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
import * as contrato from './banco-core.mjs';
import { BANCO } from './banco.mjs';

const fuente = await readFile(new URL('./banco/app.mjs', import.meta.url), 'utf8');
const html = await readFile(new URL('./banco/index.html', import.meta.url), 'utf8');
const importacion = fuente.split('\n')[0];
assert.match(importacion, /^import \{[\w, ]+\} from '\/banco-core.mjs';$/);
const controlador = fuente.replace(importacion, importacion.replace('import ', 'const ').replace(" from '/banco-core.mjs'", ' = contrato'));

async function montar(espacio = 'equipo-a', opciones = {}) {
  const estado = { descargas: [], solicitudes: [], avisos: 0, foco: null, temporizadores: [] };
  class Elemento {
    constructor(nombre) { this.nombre = nombre; this.children = []; this.eventos = new Map(); this.textContent = ''; this.files = []; }
    append(...elementos) { this.children.push(...elementos); }
    replaceChildren(...elementos) { this.children = elementos; }
    addEventListener(tipo, fn) { this.eventos.set(tipo, fn); }
    async emitir(tipo, extras = {}) {
      const evento = { target: this, preventDefault() { this.prevenido = true; }, ...extras };
      await this.eventos.get(tipo)?.(evento);
      return evento;
    }
    click() { if (this.nombre === 'a') estado.ultimoEnlace = this; }
    remove() { this.retirado = true; }
    focus() { estado.foco = this.nombre; }
  }
  const elementos = new Map([...html.matchAll(/id="([^"]+)"/g)].map(([, id]) => [id, new Elemento(id)]));
  const documento = {
    getElementById(id) { assert.ok(elementos.has(id), `ID presente en HTML: ${id}`); return elementos.get(id); },
    createElement: nombre => new Elemento(nombre), body: new Elemento('body'),
  };
  const ventana = new Elemento('window');
  ventana.confirm = () => { estado.avisos += 1; return opciones.confirmar !== false; };
  await runInNewContext(`(async () => { ${controlador}\n})()`, {
    contrato, document: documento, window: ventana, location: { pathname: `/${espacio}` },
    fetch: async (...args) => { estado.solicitudes.push(args); return { ok: opciones.ok !== false, json: async () => structuredClone(BANCO) }; },
    Blob, URL: { createObjectURL: blob => { estado.descargas.push(blob); return 'blob:doble-de-test'; }, revokeObjectURL() {} },
    setTimeout: fn => { estado.temporizadores.push(fn); },
  });
  const el = id => elementos.get(id);
  return {
    estado, el, ventana,
    async elegir(indice = 0) { const radio = el('opciones').children[indice].children[0]; radio.checked = true; await radio.emitir('change'); },
    async avanzar() { await el('formulario').emitir('submit'); },
    async exportar() { await el('descargar').emitir('click'); return JSON.parse(await estado.descargas.at(-1).text()); },
    async importar(revision) {
      const texto = JSON.stringify(revision);
      el('archivo').files = [{ size: Buffer.byteLength(texto), text: async () => texto }];
      await el('archivo').emitir('change');
    },
  };
}

test('el controlador inicia sin respuesta preseleccionada ni peticiones externas', async () => {
  const banco = await montar();
  assert.equal(banco.el('titulo-caso').textContent, 'Caso 1 de 20');
  assert.equal(banco.el('siguiente').disabled, true);
  assert.ok(banco.el('opciones').children.every(opcion => opcion.children[0].checked === false));
  assert.equal(banco.estado.solicitudes.length, 1);
  assert.equal(banco.estado.solicitudes[0][0], '/casos.json');
  assert.equal(banco.estado.solicitudes[0][1].credentials, 'omit');
  await banco.avanzar();
  assert.equal(banco.el('titulo-caso').textContent, 'Caso 1 de 20');
});

test('elección, avance, vuelta y duda conservan decisiones y piden foco sin autoavanzar', async () => {
  const banco = await montar();
  await banco.elegir(3);
  assert.equal(banco.el('titulo-caso').textContent, 'Caso 1 de 20');
  assert.match(banco.el('progreso').textContent, /1 de 20 revisados · 1 con duda/);
  await banco.avanzar();
  assert.equal(banco.estado.foco, 'titulo-caso');
  assert.equal(banco.el('siguiente').disabled, true);
  await banco.el('anterior').emitir('click');
  assert.equal(banco.el('opciones').children[3].children[0].checked, true);
  assert.equal((await banco.exportar()).respuestas[0].clase, 'duda');
});

test('20 respuestas → exportar → contexto nuevo → importar recupera las veinte sin notas', async () => {
  const banco = await montar();
  for (let i = 0; i < 20; i += 1) { await banco.elegir(i % 3); await banco.avanzar(); }
  assert.equal(banco.el('resumen').hidden, false);
  assert.match(banco.el('resumen-texto').textContent, /20 clasificados, 0 con duda y 0 sin respuesta/);
  await banco.avanzar(); // Guard de envío accidental cuando el formulario está oculto.
  const exportada = await banco.exportar();
  contrato.validarRevision(exportada, BANCO, 'equipo-a');
  assert.ok(exportada.respuestas.every(r => Object.keys(r).sort().join(',') === 'clase,id'));
  assert.match(banco.estado.ultimoEnlace.download, /^revision-sintetica-equipo-a-.*\.json$/);
  const nueva = await montar();
  await nueva.importar(exportada);
  assert.equal(nueva.el('resumen').hidden, false);
  assert.match(nueva.el('resumen-texto').textContent, /20 clasificados/);
  assert.deepEqual((await nueva.exportar()).respuestas, exportada.respuestas);
  await nueva.el('volver').emitir('click');
  assert.equal(nueva.el('titulo-caso').textContent, 'Caso 1 de 20');
  assert.equal(nueva.el('opciones').children[0].children[0].checked, true);
});

test('importar borrador retoma el primer caso pendiente aunque el JSON esté desordenado', async () => {
  const revision = contrato.crearRevision(BANCO, 'equipo-b');
  revision.respuestas[0].clase = 'compatible'; revision.respuestas.reverse();
  const banco = await montar('equipo-b');
  await banco.importar(revision);
  assert.equal(banco.el('titulo-caso').textContent, 'Caso 2 de 20');
  assert.equal(banco.el('siguiente').disabled, true);
  assert.match(banco.el('progreso').textContent, /1 de 20/);
});

test('cancelar la sustitución conserva el avance; aceptarla lo reemplaza', async () => {
  for (const confirmar of [false, true]) {
    const banco = await montar('equipo-a', { confirmar });
    await banco.elegir(1);
    await banco.importar(contrato.crearRevision(BANCO, 'equipo-a'));
    assert.equal(banco.estado.avisos, 1);
    assert.equal((await banco.exportar()).respuestas[0].clase, confirmar ? null : 'posible_contradiccion');
  }
});

test('rechazar otro equipo o campos extra no sustituye la respuesta actual', async () => {
  const banco = await montar();
  await banco.elegir(0);
  await banco.importar(contrato.crearRevision(BANCO, 'equipo-b'));
  assert.match(banco.el('estado').textContent, /Archivo rechazado/);
  assert.equal((await banco.exportar()).respuestas[0].clase, 'compatible');
  await banco.importar({ ...contrato.crearRevision(BANCO, 'equipo-a'), nota: 'no aceptada' });
  assert.match(banco.el('estado').textContent, /Archivo rechazado/);
  assert.equal((await banco.exportar()).respuestas[0].clase, 'compatible');
  assert.equal(banco.estado.avisos, 0);
});

test('salir avisa después de modificar, incluso tras solicitar descarga no confirmada', async () => {
  const banco = await montar();
  assert.equal((await banco.ventana.emitir('beforeunload')).prevenido, undefined);
  await banco.elegir();
  assert.equal((await banco.ventana.emitir('beforeunload')).prevenido, true);
  await banco.exportar();
  assert.equal((await banco.ventana.emitir('beforeunload')).prevenido, true);
});

test('inicio sin espacio muestra la elección y un fallo local muestra error legible', async () => {
  const inicio = await montar('');
  assert.equal(inicio.el('eleccion').hidden, false);
  const fallo = await montar('equipo-a', { ok: false });
  assert.match(fallo.el('estado').textContent, /No se pudo cargar/);
  assert.equal(fallo.estado.descargas.length, 0);
});
