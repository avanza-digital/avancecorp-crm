import {
  codigoDeError, crearHandler, leerJuicio, NIVELES, RespuestaHttp,
  type Dependencias, type Juicio, type Tomada,
} from './handler.ts';

function igual(actual: unknown, esperado: unknown, mensaje: string) {
  if (actual !== esperado) {
    throw new Error(`${mensaje}: esperado=${String(esperado)} actual=${String(actual)}`);
  }
}
function lanza(fn: () => unknown, mensaje: string) {
  try { fn(); } catch { return; }
  throw new Error(`${mensaje}: no lanzó`);
}

const JUICIO: Juicio = {
  nivel: 2.45,
  probabilidades: { '0': 0, '1': 0, '2': 0.55, '3': 0.45 },
  confianza: 0.55,
  modelo: 'jev-1.13.0',
};

type Confirmacion = {
  leadId: string; reserva: string; juicio: Juicio | null; huella: string | null; error: string | null;
};

function montar(parcial: Partial<Dependencias> & { pendientes?: Tomada[] } = {}) {
  const confirmadas: Confirmacion[] = [];
  const preguntadas: string[] = [];
  const d: Dependencias = {
    configurado: true,
    verificarCron: () => Promise.resolve(true),
    tomar: () => Promise.resolve(parcial.pendientes ?? []),
    confirmar: (leadId, reserva, juicio, huella, error) => {
      confirmadas.push({ leadId, reserva, juicio, huella, error });
      return Promise.resolve(null);
    },
    preguntar: (historial) => { preguntadas.push(historial); return Promise.resolve(JUICIO); },
    huella: () => Promise.resolve('hh'),
    ...parcial,
  };
  return { handler: crearHandler(d), confirmadas, preguntadas };
}

const peticion = (headers: Record<string, string> = { 'x-cron-firma': 'f', 'x-cron-instante': '1' }) =>
  new Request('https://x/', { method: 'POST', headers, body: '{"accion":"procesar"}' });

Deno.test('los cuatro niveles medidos el 20/09 no cambian de forma ni de orden', () => {
  igual(NIVELES.length, 4, 'niveles');
  igual(NIVELES[0].includes('Nunca se logro hablar'), true, 'nivel 0 es el más frío');
  igual(NIVELES[3].includes('Esta por cerrar'), true, 'nivel 3 es el más caliente');
});

Deno.test('solo admite POST', async () => {
  const { handler } = montar();
  igual((await handler(new Request('https://x/', { method: 'GET' }))).status, 405, 'GET');
});

Deno.test('sin firma del cron no se toca la cola', async () => {
  const { handler, confirmadas } = montar({ pendientes: [{ lead_id: 'l1', historial: 'hola', reserva: 'r1' }] });
  igual((await handler(new Request('https://x/', { method: 'POST' }))).status, 401, 'sin cabeceras');
  igual(confirmadas.length, 0, 'no confirmó nada');
});

Deno.test('firma inválida devuelve 401', async () => {
  const { handler } = montar({ verificarCron: () => Promise.resolve(false) });
  igual((await handler(peticion())).status, 401, 'firma mala');
});

Deno.test('sin clave configurada la cola queda intacta', async () => {
  const { handler, confirmadas } = montar({
    configurado: false, pendientes: [{ lead_id: 'l1', historial: 'hola', reserva: 'r1' }],
  });
  const r = await handler(peticion());
  igual(r.status, 200, 'estado');
  igual((await r.json()).motivo, 'sin_configurar', 'motivo');
  igual(confirmadas.length, 0, 'no gastó intentos');
});

Deno.test('camino feliz: guarda el juicio con su huella', async () => {
  const { handler, confirmadas, preguntadas } = montar({
    pendientes: [{ lead_id: 'l1', historial: ' 14/09 llamada_realizada: agendado ', reserva: 'r1' }],
  });
  const r = await handler(peticion());
  igual((await r.json()).listos, 1, 'listos');
  igual(preguntadas[0], '14/09 llamada_realizada: agendado', 'el historial va recortado');
  igual(confirmadas[0].juicio?.nivel, 2.45, 'nivel');
  igual(confirmadas[0].huella, 'hh', 'huella');
  igual(confirmadas[0].error, null, 'sin error');
});

Deno.test('un lead sin historial no se le pregunta al modelo', async () => {
  const { handler, confirmadas, preguntadas } = montar({
    pendientes: [{ lead_id: 'l1', historial: '   ', reserva: 'r1' }],
  });
  await handler(peticion());
  igual(preguntadas.length, 0, 'no preguntó');
  igual(confirmadas[0].error, 'sin_historial', 'motivo');
});

Deno.test('el fallo de un lead no se lleva por delante al resto del lote', async () => {
  const { handler, confirmadas } = montar({
    pendientes: [
      { lead_id: 'l1', historial: 'uno', reserva: 'r1' },
      { lead_id: 'l2', historial: 'dos', reserva: 'r2' },
    ],
    preguntar: (h) => h === 'uno' ? Promise.reject(new RespuestaHttp(429)) : Promise.resolve(JUICIO),
  });
  const cuerpo = await (await handler(peticion())).json();
  igual(cuerpo.listos, 1, 'listos');
  igual(cuerpo.fallidos, 1, 'fallidos');
  igual(confirmadas[0].error, 'http_429', 'el primero reporta el código');
  igual(confirmadas[1].juicio?.nivel, 2.45, 'el segundo sí se guardó');
});

Deno.test('el código de error nunca arrastra el cuerpo de la respuesta', () => {
  igual(codigoDeError(new RespuestaHttp(503)), 'http_503', 'http');
  const t = new Error('lo que sea'); t.name = 'TimeoutError';
  igual(codigoDeError(t), 'timeout', 'timeout');
  igual(codigoDeError(new Error('respuesta_invalida')), 'respuesta_invalida', 'forma');
  igual(codigoDeError({ secreto: 'apikey_x' }), 'error_desconocido', 'desconocido');
});

Deno.test('leerJuicio rechaza lo que ordenaría «Mi día» al revés', () => {
  const ok = leerJuicio({ model: 'jev-1.13.0', answers: { temperatura: { score: 3, confidence: 1, probabilities: {} } } });
  igual(ok.nivel, 3, 'nivel válido');
  igual(ok.modelo, 'jev-1.13.0', 'modelo');
  lanza(() => leerJuicio({ answers: { temperatura: { score: 4, confidence: 1, probabilities: {} } } }), 'nivel > 3');
  lanza(() => leerJuicio({ answers: { temperatura: { score: -1, confidence: 1, probabilities: {} } } }), 'nivel < 0');
  lanza(() => leerJuicio({ answers: { temperatura: { score: '2', confidence: 1, probabilities: {} } } }), 'nivel texto');
  lanza(() => leerJuicio({ answers: { temperatura: { score: NaN, confidence: 1, probabilities: {} } } }), 'NaN');
  lanza(() => leerJuicio({ answers: { temperatura: { score: 2, confidence: 9, probabilities: {} } } }), 'confianza > 1');
  lanza(() => leerJuicio({ answers: { temperatura: { score: 2, confidence: 1 } } }), 'sin distribución');
  lanza(() => leerJuicio({ answers: {} }), 'sin respuesta');
});
