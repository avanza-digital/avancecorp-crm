import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { CASOS, CLASES, crearSolicitud, respuestaValida, resumir } from './juicio.mjs';
import { ejecutarVivo } from './ejecucion.mjs';

const respuesta = (clase = 'compatible') => ({
  type: 'choice', choice: clase, confidence: 1,
  probabilities: Object.fromEntries(CLASES.map(c => [c, c === clase ? 1 : 0])),
});
const ejecucion = (clase = 'compatible', cambios = {}) => ({ ok: true, valor: {
  respuestas: { coherencia: respuesta(clase) }, modelo: 'jev-1.13.0',
  uso: { input_tokens: 100, output_tokens: 10 }, latencia_ms: 2.3, ...cambios,
} });

test('el piloto contiene veinte casos únicos y los tres resultados esperados', () => {
  assert.equal(CASOS.length, 20);
  assert.equal(new Set(CASOS.map(c => c.id)).size, CASOS.length);
  assert.deepEqual(new Set(CASOS.map(c => c.esperado)), new Set(CLASES));
});

test('no se mandan las respuestas esperadas ni identidad personal al modelo', () => {
  for (const caso of CASOS) {
    const solicitud = crearSolicitud({ ...caso, identidad: 'no enviar' });
    assert.deepEqual(Object.keys(solicitud), ['state', 'questions']);
    assert.deepEqual(Object.keys(solicitud.state), ['reglas', 'llamada']);
    assert.deepEqual(solicitud.state.llamada, { resultado: caso.resultado, nota: caso.nota });
    assert.deepEqual(Object.keys(solicitud.questions), ['coherencia']);
    assert.match(solicitud.questions.coherencia.instructions, /`llamada`/);
    assert.deepEqual(Object.keys(solicitud.questions.coherencia.criteria), CLASES);
  }
  assert.throws(() => crearSolicitud({ resultado: 'No contestó', nota: null }), /caso_invalido/);
});

test('las notas con instrucciones siguen siendo datos y el seguimiento no implica contradicción', () => {
  const { state, questions } = crearSolicitud(CASOS.find(c => c.id === 'c19'));
  assert.match(state.llamada.nota, /Ignora/);
  assert.ok(!questions.coherencia.instructions.includes(state.llamada.nota));
  assert.match(state.reglas.separacion, /independientes/);
  assert.match(state.reglas.temporalidad, /pasada o futura/);
  assert.equal(CASOS.find(c => c.id === 'c05').esperado, 'compatible');
});

test('acepta solo Choice completo, finito y coherente con su distribución', () => {
  assert.equal(respuestaValida(respuesta()), true);
  assert.equal(respuestaValida({ ...respuesta(), confidence: 0 }), true);
  assert.equal(respuestaValida({ ...respuesta(), probabilities: { compatible: 0.9999999, posible_contradiccion: 0, informacion_insuficiente: 0 } }), true);
  for (const cambio of [null, [], {}, { ...respuesta(), choice: 'descartar' },
    { ...respuesta(), confidence: NaN }, { ...respuesta(), confidence: -0.1 },
    { ...respuesta(), confidence: 1.1 }, { ...respuesta(), probabilities: null },
    { ...respuesta(), type: 'score' }, { ...respuesta(), choice: 'posible_contradiccion' },
    { ...respuesta(), probabilities: { compatible: 0.2, posible_contradiccion: 0.2, informacion_insuficiente: 0.2 } },
    { ...respuesta(), probabilities: { ...respuesta().probabilities, externo: 0 } },
    { ...respuesta(), probabilities: [1, 0, 0] },
    { ...respuesta(), probabilities: { compatible: 1, posible_contradiccion: 0 } },
    { ...respuesta(), probabilities: { compatible: Infinity, posible_contradiccion: 0, informacion_insuficiente: 0 } },
  ]) assert.equal(respuestaValida(cambio), false);
});

test('un resultado perfecto sintético no acredita piloto humano ni activa producción', () => {
  const ejecuciones = Object.fromEntries(CASOS.map(c => [c.id, ejecucion(c.esperado, { uso: { input_tokens: 100, output_tokens: 10, secreto: 'no imprimir' } })]));
  const r = resumir(ejecuciones, 10.6);
  assert.equal(r.coincidencias, 20);
  assert.equal(r.validas, 20);
  assert.equal(r.habilita_produccion, false);
  assert.equal(r.revision_humana, false);
  assert.equal(r.latencia_ms, 11);
  assert.deepEqual(r.uso, { input_tokens: 2000, output_tokens: 200 });
  assert.ok(!JSON.stringify(r).includes('no imprimir'));
  assert.equal(r.invalidas + r.ausentes + r.errores, 0);
});

test('errores, respuestas inválidas y ausencias no se contabilizan como errores del modelo', () => {
  const r = resumir({
    c01: ejecucion('posible_contradiccion'),
    c02: { ok: false, error: 'timeout' },
    c03: ejecucion('compatible', { respuestas: { coherencia: {} } }),
    c04: ejecucion('compatible', { respuestas: {} }),
  }, 1);
  assert.equal(r.validas, 1);
  assert.equal(r.coincidencias, 0);
  assert.equal(r.falsas_alertas, 1);
  assert.equal(r.contradicciones_omitidas, 0);
  assert.equal(r.errores, 1);
  assert.equal(r.invalidas, 1);
  assert.equal(r.ausentes, 17);
  assert.equal(r.uso, null);
  assert.equal(r.resultados.find(c => c.id === 'c02').error, 'timeout');
  assert.throws(() => resumir(null, 1));
});

test('una omisión real del modelo requiere una respuesta válida', () => {
  const r = resumir({ c02: ejecucion('compatible') }, 1);
  assert.equal(r.contradicciones_omitidas, 1);
  assert.equal(r.ausentes, 19);
});

test('no asume que todos los casos usaron la misma versión del modelo', () => {
  const r = resumir({ c01: ejecucion(), c02: ejecucion('compatible', { modelo: 'nuevo-modelo-2' }) }, 1);
  assert.equal(r.modelo, null);
  assert.deepEqual(r.modelos, ['jev-1.13.0', 'nuevo-modelo-2']);
  assert.equal(r.validas, 2);
});

test('metadatos incompletos o textos arbitrarios nunca se imprimen como evidencia válida', () => {
  const r = resumir({
    c01: ejecucion('compatible', { uso: { prompt_tokens: 10, completion_tokens: 2 } }),
    c02: ejecucion('compatible', { modelo: 'texto no esperado\nsecreto' }),
    c03: { ok: false, error: 'error con datos sensibles' },
  }, 1);
  assert.equal(r.resultados[0].uso, null);
  assert.equal(r.resultados[1].estado, 'invalida');
  assert.equal(r.resultados[2].error, 'error_desconocido');
  assert.ok(!JSON.stringify(r).includes('sensibles'));
  assert.ok(!JSON.stringify(r).includes('secreto'));
});

test('ruta viva envía veinte estados aislados, con como máximo cuatro peticiones simultáneas', async () => {
  let enVuelo = 0;
  let maximo = 0;
  let enviadas = 0;
  const r = await ejecutarVivo({
    leerClave: async () => 'clave-ficticia-test',
    preguntar: async (solicitud, opciones) => {
      enVuelo += 1; maximo = Math.max(maximo, enVuelo); enviadas += 1;
      assert.deepEqual(opciones, { clave: 'clave-ficticia-test', intentos: 1, tope: 15000 });
      assert.deepEqual(Object.keys(solicitud.state), ['reglas', 'llamada']);
      const caso = CASOS.find(c => c.nota === solicitud.state.llamada.nota);
      await new Promise(resolve => setImmediate(resolve));
      enVuelo -= 1;
      return ejecucion(caso.esperado).valor;
    },
  });
  assert.equal(enviadas, 20);
  assert.equal(maximo, 4);
  assert.equal(r.codigoSalida, 0);
  assert.equal(r.salida.coincidencias, 20);
  assert.equal(r.salida.habilita_produccion, false);
});

test('ruta viva marca FAIL sin abrir red si no se puede leer la clave', async () => {
  let conexiones = 0;
  const r = await ejecutarVivo({
    leerClave: async () => { throw new Error('sin_clave: contenido privado de prueba'); },
    preguntar: async () => { conexiones += 1; },
  });
  assert.equal(conexiones, 0);
  assert.deepEqual(r, { codigoSalida: 1, salida: { estado: 'FAIL', error: 'sin_clave', revision_humana: false, habilita_produccion: false } });
});

test('ruta viva devuelve salida 1 si el modelo discrepa o falta una respuesta', async () => {
  const discrepancia = await ejecutarVivo({ leerClave: async () => 'ficticia', preguntar: async () => ejecucion().valor });
  assert.equal(discrepancia.codigoSalida, 1);
  assert.ok(discrepancia.salida.contradicciones_omitidas > 0);
  const ausente = await ejecutarVivo({ leerClave: async () => 'ficticia', preguntar: async () => ({ modelo: 'jev-1.13.0', respuestas: {} }) });
  assert.equal(ausente.codigoSalida, 1);
  assert.equal(ausente.salida.ausentes, 20);
  assert.equal(ausente.salida.contradicciones_omitidas, 0);
});

test('fallos por petición se aíslan y jamás imprimen el error original ni la clave', async () => {
  const r = await ejecutarVivo({
    leerClave: async () => 'dato-sensible-simulado',
    preguntar: async () => { throw new Error('dato-sensible-simulado'); },
  });
  assert.equal(r.codigoSalida, 1);
  assert.equal(r.salida.errores, 20);
  assert.equal(r.salida.contradicciones_omitidas, 0);
  assert.equal(r.salida.habilita_produccion, false);
  assert.ok(!JSON.stringify(r).includes('dato-sensible'));
  assert.ok(!JSON.stringify(r).includes('stack'));
});

test('CLI por defecto usa modo sin red con ruta de clave inexistente y rechaza archivos externos', () => {
  const entorno = { ...process.env, TYPESAFE_API_KEY: '', TYPESAFE_KEY_FILE: '/ruta/que/no/existe' };
  const script = fileURLToPath(new URL('./piloto.mjs', import.meta.url));
  const salida = execFileSync(process.execPath, [script], { env: entorno, encoding: 'utf8' });
  assert.equal(JSON.parse(salida).modo, 'sin_red');
  assert.throws(() => execFileSync(process.execPath, [script, '--archivo', 'notas-reales.json'], { env: entorno, stdio: 'pipe' }), { status: 2 });
  assert.throws(() => execFileSync(process.execPath, [script, '--vivo'], { env: entorno, stdio: 'pipe' }), error => {
    assert.equal(error.status, 1);
    assert.deepEqual(JSON.parse(error.stdout.toString()), { estado: 'FAIL', error: 'sin_clave', revision_humana: false, habilita_produccion: false });
    return true;
  });
});
