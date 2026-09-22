import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request } from 'node:http';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { BANCO, crearServidor } from './banco.mjs';
import { CASOS, CLASES } from './juicio.mjs';
import { OPCIONES, crearRevision, leerRevision, validarRevision, compararRevisiones, resumirRevision } from './banco-core.mjs';

const completa = (espacio, clase = 'compatible') => crearRevision(BANCO, espacio, BANCO.casos.map(({ id }) => ({ id, clase })));
const clonar = valor => structuredClone(valor);

test('el banco público contiene solo los veinte casos ficticios, nunca la solución', () => {
  assert.equal(BANCO.casos.length, 20);
  assert.deepEqual(OPCIONES.slice(0, 3).map(o => o.valor), CLASES);
  assert.match(BANCO.huella, /^[a-f0-9]{64}$/);
  assert.deepEqual(BANCO.casos, CASOS.map(({ id, resultado, nota }) => ({ id, resultado, nota })));
  assert.ok(BANCO.casos.every(c => !Object.hasOwn(c, 'esperado')));
});

test('un borrador no preselecciona respuestas y tiene fecha y espacio explícitos', () => {
  const revision = crearRevision(BANCO, 'equipo-a', [], new Date('2026-09-21T20:00:00.000Z'));
  assert.equal(revision.emitido_en, '2026-09-21T20:00:00.000Z');
  assert.equal(revision.espacio, 'equipo-a');
  assert.deepEqual(resumirRevision(revision), { total: 20, clasificadas: 0, dudas: 0, sin_respuesta: 20 });
  assert.deepEqual(leerRevision(JSON.stringify(revision), BANCO, 'equipo-a'), revision);
});

test('valida borrador/completo sin depender del orden del archivo', () => {
  const revision = completa('equipo-a');
  revision.respuestas.reverse();
  assert.equal(validarRevision(revision, BANCO), revision);
  assert.equal(resumirRevision(revision).clasificadas, 20);
});

test('rechaza otro equipo, versión, huella o fecha inválida', () => {
  const revision = completa('equipo-a');
  assert.throws(() => leerRevision(JSON.stringify(revision), BANCO, 'equipo-b'));
  for (const cambio of [
    { espacio: 'gerencia' }, { version: 'otra' }, { huella: 'a'.repeat(64) },
    { emitido_en: null }, { emitido_en: 'hoy' }, { emitido_en: '2026-02-31T00:00:00.000Z' },
  ]) assert.throws(() => validarRevision({ ...revision, ...cambio }, BANCO));
});

test('rechaza soluciones, notas, nombres y claves extra en cualquier nivel', () => {
  for (const campo of ['nota', 'esperado', 'nombre', '__proto__']) {
    const revision = completa('equipo-a');
    Object.defineProperty(revision, campo, { value: 'texto_no_permitido', enumerable: true });
    assert.throws(() => validarRevision(revision, BANCO));
    const otra = completa('equipo-a');
    Object.defineProperty(otra.respuestas[0], campo, { value: 'texto_no_permitido', enumerable: true });
    assert.throws(() => validarRevision(otra, BANCO));
  }
});

test('rechaza IDs ajenos, duplicados, respuestas omitidas y clases inválidas', () => {
  for (const mutar of [
    r => { r.respuestas[0].id = 'lead-real'; },
    r => { r.respuestas[0].id = r.respuestas[1].id; },
    r => { r.respuestas.pop(); },
    r => { r.respuestas[0].clase = 'fraude'; },
    r => { r.respuestas[0].clase = 1; },
    r => { delete r.respuestas[0].clase; },
    r => { r.respuestas = {}; },
  ]) { const revision = completa('equipo-a'); mutar(revision); assert.throws(() => validarRevision(revision, BANCO)); }
});

test('rechaza JSON roto, primitivas y entradas excesivas sin reproducir el contenido', () => {
  for (const texto of ['secreto ficticio', 'null', '[]', '42', '{', ' '.repeat(16_385)]) {
    assert.throws(() => leerRevision(texto, BANCO), { message: 'revision_invalida' });
  }
});

test('JSON textual con __proto__ se rechaza sin alterar prototipos', () => {
  const texto = JSON.stringify(completa('equipo-a'));
  assert.throws(() => leerRevision(texto.replace('{', '{"__proto__":{"contaminado":true},'), BANCO));
  assert.throws(() => leerRevision(texto.replace('"id":"c01"', '"__proto__":{"contaminado":true},"id":"c01"'), BANCO));
  assert.equal({}.contaminado, undefined);
});

test('el límite de 16 KiB se aplica a bytes incluidos espacios y caracteres multibyte', () => {
  const texto = JSON.stringify(completa('equipo-a'));
  const relleno = ' '.repeat(16_384 - Buffer.byteLength(texto));
  assert.equal(leerRevision(texto + relleno, BANCO).espacio, 'equipo-a');
  assert.throws(() => leerRevision(texto + relleno + ' ', BANCO));
  assert.throws(() => leerRevision('á'.repeat(8193), BANCO));
});

test('no compara dos archivos del mismo espacio ni dos corpus distintos', () => {
  assert.throws(() => compararRevisiones(completa('equipo-a'), completa('equipo-a'), BANCO), { message: 'espacios_repetidos' });
  const b = completa('equipo-b'); b.huella = 'b'.repeat(64);
  assert.throws(() => compararRevisiones(completa('equipo-a'), b, BANCO));
});

test('duda no es información insuficiente ni acuerdo, aunque ambos duden', () => {
  const a = completa('equipo-a'), b = completa('equipo-b');
  a.respuestas[0].clase = 'duda'; b.respuestas[0].clase = 'duda';
  a.respuestas[1].clase = null;
  a.respuestas[2].clase = 'informacion_insuficiente'; b.respuestas[2].clase = 'informacion_insuficiente';
  b.respuestas[3].clase = 'posible_contradiccion';
  const comparacion = compararRevisiones(a, b, BANCO);
  assert.equal(comparacion.comparables, 18);
  assert.equal(comparacion.coincidencias, 17);
  assert.equal(comparacion.proporcion_acuerdo, null);
  assert.equal(comparacion.cobertura_comparacion, 18 / 20);
  assert.equal(comparacion.comparacion_completa, false);
  assert.deepEqual(comparacion.desacuerdos, ['c04']);
  assert.deepEqual(comparacion.pendientes, ['c01', 'c02']);
  assert.equal(comparacion.por_espacio['equipo-a'].dudas, 1);
});

test('una coincidencia parcial no se anuncia como 100 % de acuerdo del banco', () => {
  const a = crearRevision(BANCO, 'equipo-a'), b = crearRevision(BANCO, 'equipo-b');
  a.respuestas[0].clase = 'compatible'; b.respuestas[0].clase = 'compatible';
  const resultado = compararRevisiones(a, b, BANCO);
  assert.equal(resultado.coincidencias, 1);
  assert.equal(resultado.comparables, 1);
  assert.equal(resultado.cobertura_comparacion, 0.05);
  assert.equal(resultado.comparacion_completa, false);
  assert.equal(resultado.proporcion_acuerdo, null);
});

test('sin pares comparables el porcentaje es desconocido, no 0 ni 100', () => {
  const resultado = compararRevisiones(crearRevision(BANCO, 'equipo-a'), crearRevision(BANCO, 'equipo-b'), BANCO);
  assert.equal(resultado.proporcion_acuerdo, null);
  assert.equal(resultado.comparables, 0);
  assert.equal(resultado.pendientes.length, 20);
});

test('el acuerdo perfecto nunca autentica identidades ni habilita datos reales/producto', () => {
  const resultado = compararRevisiones(completa('equipo-a'), completa('equipo-b'), BANCO);
  assert.equal(resultado.proporcion_acuerdo, 1);
  assert.equal(resultado.requiere_conversacion, false);
  assert.equal(resultado.identidad_verificada, false);
  assert.equal(resultado.habilita_muestra_real, false);
  assert.equal(resultado.habilita_produccion, false);
  assert.doesNotMatch(JSON.stringify(resultado), /Sonó hasta|esperado|precision_modelo/);
});

async function solicitar(servidor, ruta, opciones = {}) {
  return new Promise((resolver, rechazar) => {
    const peticion = request({ hostname: '127.0.0.1', port: servidor.address().port, path: ruta, ...opciones }, respuesta => {
      const partes = [];
      respuesta.on('data', parte => partes.push(parte));
      respuesta.on('end', () => resolver({ estado: respuesta.statusCode, cabeceras: respuesta.headers, cuerpo: Buffer.concat(partes).toString('utf8') }));
    });
    peticion.on('error', rechazar); peticion.end();
  });
}

test('servidor HTTP de solo lectura: rutas cerradas, CSP, sin notas importadas ni clave', async t => {
  const servidor = crearServidor();
  servidor.listen(0, '127.0.0.1'); await once(servidor, 'listening');
  t.after(() => new Promise((resolver, rechazar) => servidor.close(error => error ? rechazar(error) : resolver())));
  assert.equal(servidor.address().address, '127.0.0.1');
  const publico = await solicitar(servidor, '/casos.json');
  assert.equal(publico.estado, 200);
  assert.deepEqual(JSON.parse(publico.cuerpo), BANCO);
  assert.equal(publico.cabeceras['cache-control'], 'no-store');
  assert.equal(publico.cabeceras['x-frame-options'], 'DENY');
  assert.equal(publico.cabeceras['x-content-type-options'], 'nosniff');
  assert.match(publico.cabeceras['content-security-policy'], /connect-src 'self'/);
  assert.equal(publico.cabeceras['access-control-allow-origin'], undefined);
  for (const ruta of ['/', '/equipo-a', '/equipo-b', '/app.mjs', '/banco-core.mjs', '/styles.css']) {
    const respuesta = await solicitar(servidor, ruta);
    assert.equal(respuesta.estado, 200, ruta);
    assert.doesNotMatch(respuesta.cuerpo, /from ['"].*juicio|TYPESAFE_API_KEY|api\.typesafe\.ai|localStorage|sessionStorage/);
  }
  for (const ruta of ['/juicio.mjs', '/piloto.mjs', '/../juicio.mjs', '/%2e%2e/juicio.mjs', '/.env', '/casos.json?notas=1', '/equipo-c']) {
    assert.equal((await solicitar(servidor, ruta)).estado, 404, ruta);
  }
  assert.equal((await solicitar(servidor, '/casos.json', { method: 'POST' })).estado, 405);
  assert.equal((await solicitar(servidor, '/casos.json', { headers: { Host: 'malicioso.test' } })).estado, 403);
  assert.equal((await solicitar(servidor, '/casos.json', { headers: { Origin: 'https://malicioso.test' } })).estado, 403);
  assert.equal((await solicitar(servidor, '/casos.json', { method: 'HEAD' })).cuerpo, '');
});

test('CLI compara archivos ficticios y rechaza invalidaciones sin imprimir su contenido', async t => {
  const carpeta = await mkdtemp(join(tmpdir(), 'gd-banco-test-'));
  t.after(() => rm(carpeta, { recursive: true, force: true })); // Solo este temporal generado por el test.
  const a = join(carpeta, 'a.json'), b = join(carpeta, 'b.json');
  await writeFile(a, JSON.stringify(completa('equipo-a')));
  await writeFile(b, JSON.stringify(completa('equipo-b')));
  const ejecutar = rutas => spawnSync(process.execPath, [fileURLToPath(new URL('./comparar.mjs', import.meta.url)), ...rutas], { encoding: 'utf8' });
  const resultado = ejecutar([a, b]);
  assert.equal(resultado.status, 0, resultado.stderr);
  assert.equal(JSON.parse(resultado.stdout).coincidencias, 20);
  const repetida = ejecutar([a, a]);
  assert.equal(repetida.status, 1);
  assert.match(repetida.stderr, /mismo equipo/);
  assert.match(ejecutar([]).stderr, /Uso:/);
  assert.match(ejecutar([a, join(carpeta, 'ausente.json')]).stderr, /No se encontró/);
  const invalida = clonar(completa('equipo-b')); invalida.nota = 'dato_ficticio_no_imprimir';
  await writeFile(b, JSON.stringify(invalida));
  const rechazo = ejecutar([a, b]);
  assert.equal(rechazo.status, 1); assert.equal(rechazo.stdout, '');
  assert.doesNotMatch(rechazo.stderr, /dato_ficticio_no_imprimir/);
  assert.notEqual(rechazo.stderr, repetida.stderr);
});
