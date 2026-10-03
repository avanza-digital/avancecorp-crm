import { strict as assert } from 'node:assert';
import { crearHandler, eventoValido, latidoValido, segundosDeEspera, urlAbrir, type Dependencias } from './handler.ts';

// Todo sintético: ni claves, ni números ni URLs reales.
const CLAVE = 'a'.repeat(64);
const EVENTO = {
  v: 1, evento_origen_id: 'C1-1759300000000', numero: '+51900000001', direccion: 'saliente',
  estado_tecnico: 'conectada', duracion_seg: 42, ocurrio_en: '2026-10-01T15:00:00Z',
};
const LATIDO = { v: 1, version_macro: 'macro 1.0', en_cola: 0, ocurrio_en: '2026-10-01T15:00:00Z' };
const BASE = 'https://crm.ejemplo.invalid';

function banco(cambios: Partial<Dependencias> = {}) {
  const llamadas: unknown[][] = [];
  const deps: Dependencias = {
    urlCrm: BASE,
    ingerir: async (...args) => {
      llamadas.push(['ingerir', ...args]);
      return { evento_id: '00000000-0000-4000-8000-000000000001', repetido: false, ignorado: false, motivo: null };
    },
    registrarSalud: async (...args) => { llamadas.push(['registrarSalud', ...args]); return { registrado: true }; },
    ...cambios,
  };
  const llamar = (cuerpo: unknown, cabeceras: Record<string, string | undefined> = {}, metodo = 'POST') => {
    const headers = Object.fromEntries(Object.entries({
      'content-type': 'application/json', 'x-celular-credencial': CLAVE, ...cabeceras,
    }).filter(([, v]) => v !== undefined)) as Record<string, string>;
    const conCuerpo = metodo !== 'GET' && metodo !== 'HEAD';
    return crearHandler(deps)(new Request('https://ejemplo.invalid/crm-llamadas-ingesta', {
      method: metodo, headers,
      body: conCuerpo ? (typeof cuerpo === 'string' ? cuerpo : JSON.stringify(cuerpo)) : undefined,
    }));
  };
  return { llamar, llamadas };
}
const llamada = (evento: unknown = EVENTO) => ({ accion: 'llamada', evento });

Deno.test('solo POST y sin CORS: no la llama un navegador', async () => {
  for (const metodo of ['GET', 'OPTIONS', 'PUT', 'DELETE']) {
    const b = banco();
    const r = await b.llamar(llamada(), {}, metodo);
    assert.equal(r.status, 405);
    assert.equal(r.headers.get('allow'), 'POST');
    assert.equal(r.headers.get('access-control-allow-origin'), null);
    assert.equal(b.llamadas.length, 0);
  }
  const r = await banco().llamar(llamada(), { origin: 'https://otro.invalid' });
  assert.equal(r.headers.get('access-control-allow-origin'), null);
});

Deno.test('el cuerpo tiene que declararse JSON', async () => {
  const b = banco();
  assert.equal((await b.llamar(llamada(), { 'content-type': 'text/plain' })).status, 415);
  assert.equal((await b.llamar(llamada(), { 'content-type': undefined })).status, 415);
  assert.equal(b.llamadas.length, 0);
  assert.equal((await banco().llamar(llamada(), { 'content-type': 'application/json; charset=utf-8' })).status, 202);
});

Deno.test('clave ausente, mal formada o en mayúsculas: el mismo 401, sin tocar la base', async () => {
  for (const clave of [undefined, '', 'A'.repeat(64), 'a'.repeat(63), 'a'.repeat(65), 'g'.repeat(64), `${'a'.repeat(63)} `]) {
    const b = banco();
    const r = await b.llamar(llamada(), { 'x-celular-credencial': clave });
    assert.equal(r.status, 401);
    assert.deepEqual(await r.json(), { error: 'No autorizado' });
    assert.equal(b.llamadas.length, 0);
  }
});

Deno.test('la base dice 42501 (desconocida, revocada, analista de baja): el MISMO 401 y el mismo cuerpo', async () => {
  const sinForma = await (await banco().llamar(llamada(), { 'x-celular-credencial': '' })).json();
  for (const accion of ['llamada', 'latido']) {
    const b = banco({
      ingerir: async () => { throw { code: '42501', message: 'Celular sin asignación vigente o analista inactivo' }; },
      registrarSalud: async () => { throw { code: '42501', message: 'No autorizado' }; },
    });
    const r = await b.llamar(accion === 'llamada' ? llamada() : { accion, latido: LATIDO });
    assert.equal(r.status, 401);
    assert.deepEqual(await r.json(), sinForma);
  }
});

Deno.test('más de 4 KB: 413 sin tocar la base', async () => {
  const b = banco();
  const r = await b.llamar(`{"accion":"llamada","evento":{"v":1,"relleno":"${'x'.repeat(5000)}"}}`);
  assert.equal(r.status, 413);
  assert.equal(b.llamadas.length, 0);
});

Deno.test('cuerpo que no es un objeto, acción desconocida o claves de más: 400 sin tocar la base', async () => {
  for (const cuerpo of ['{', '[]', '"grande"', 'null', '42', JSON.stringify({ ...llamada(), extra: 1 }),
    JSON.stringify({ accion: 'otra', evento: EVENTO }), JSON.stringify({ accion: 'llamada' }),
    JSON.stringify({ accion: 'latido', evento: EVENTO }), JSON.stringify({ accion: 'llamada', latido: LATIDO })]) {
    const b = banco();
    assert.equal((await b.llamar(cuerpo)).status, 400, cuerpo);
    assert.equal(b.llamadas.length, 0);
  }
});

Deno.test('evento fuera del contrato v1: 400 sin tocar la base', async () => {
  const malos: unknown[] = [
    { ...EVENTO, v: 2 }, { ...EVENTO, v: '1' }, (({ v: _v, ...resto }) => resto)(EVENTO),
    { ...EVENTO, evento_origen_id: 'C1' }, { ...EVENTO, evento_origen_id: 'C1 con espacios' },
    { ...EVENTO, evento_origen_id: 'x'.repeat(121) }, { ...EVENTO, numero: '9'.repeat(41) },
    { ...EVENTO, numero: 900000001 }, { ...EVENTO, direccion: 'otra' }, { ...EVENTO, estado_tecnico: 'otra' },
    { ...EVENTO, duracion_seg: -1 }, { ...EVENTO, duracion_seg: 1.5 }, { ...EVENTO, duracion_seg: '30' },
    { ...EVENTO, duracion_seg: 86401 }, { ...EVENTO, ocurrio_en: 'ayer' }, { ...EVENTO, extra: true }, [], 'evento',
  ];
  for (const evento of malos) {
    assert.equal(eventoValido(evento), false, JSON.stringify(evento));
    const b = banco();
    assert.equal((await b.llamar(llamada(evento))).status, 400, JSON.stringify(evento));
    assert.equal(b.llamadas.length, 0);
  }
  assert.equal(eventoValido({ v: 1, evento_origen_id: 'C1-1' + '0'.repeat(3) }), true);
  assert.equal(eventoValido({ ...EVENTO, numero: null, duracion_seg: null, ocurrio_en: null }), true);
});

Deno.test('llamada válida: la base recibe la clave y el evento tal cual', async () => {
  const b = banco();
  const r = await b.llamar(llamada());
  assert.equal(r.status, 202);
  assert.deepEqual(b.llamadas, [['ingerir', CLAVE, EVENTO]]);
  assert.equal(r.headers.get('cache-control'), 'no-store');
});

Deno.test('guardada, repetida o ignorada: la MISMA respuesta (propuesta #12)', async () => {
  const respuestas = [
    { evento_id: '00000000-0000-4000-8000-000000000001', repetido: false, ignorado: false, motivo: null },
    { evento_id: '00000000-0000-4000-8000-000000000001', repetido: true, ignorado: false, motivo: null },
    { evento_id: null, repetido: false, ignorado: true, motivo: 'sin_lead' },
    { evento_id: null, repetido: false, ignorado: true, motivo: 'entrante_apagada' },
  ];
  const cuerpos: unknown[] = [];
  for (const dato of respuestas) {
    const r = await banco({ ingerir: async () => dato }).llamar(llamada());
    assert.equal(r.status, 202);
    cuerpos.push(await r.json());
  }
  for (const c of cuerpos) assert.deepEqual(c, cuerpos[0]);
  assert.deepEqual(Object.keys(cuerpos[0] as object).sort(), ['abrir', 'recibido']);
});

Deno.test('abre la encuesta de F1 por número; sin número, Mi día', async () => {
  const r = await (await banco().llamar(llamada())).json();
  assert.equal(r.abrir, `${BASE}/#/gestion-diaria/llamada/%2B51900000001`);
  const sinNumero = await (await banco().llamar(llamada({ ...EVENTO, numero: null }))).json();
  assert.equal(sinNumero.abrir, `${BASE}/#/gestion-diaria`);
  assert.equal(urlAbrir(`${BASE}/`, ' 900 000 001 '), `${BASE}/#/gestion-diaria/llamada/900%20000%20001`);
  assert.equal(urlAbrir(BASE, ''), `${BASE}/#/gestion-diaria`);
});

Deno.test('límite por celular: 429 con la espera que pide la base', async () => {
  const r = await banco({ ingerir: async () => { throw { code: 'P0429', details: 'reintentar_en_seg=37' }; } }).llamar(llamada());
  assert.equal(r.status, 429);
  assert.equal(r.headers.get('retry-after'), '37');
  assert.equal((await r.json()).reintentar_en_seg, 37);
  for (const details of [undefined, null, 'basura', 'reintentar_en_seg=0', 'reintentar_en_seg=-5']) {
    const s = await banco({ ingerir: async () => { throw { code: 'P0429', details }; } }).llamar(llamada());
    assert.equal(s.headers.get('retry-after'), '60', String(details));
  }
  assert.equal(segundosDeEspera('reintentar_en_seg=86400'), 86400);
});

Deno.test('reenvío del mismo origen con otro contenido: 409', async () => {
  const r = await banco({ ingerir: async () => { throw { code: 'P0409', message: 'Esta llamada ya llegó con otro contenido' }; } }).llamar(llamada());
  assert.equal(r.status, 409);
});

Deno.test('la base rechaza el contenido: 400 con su mensaje', async () => {
  const mensaje = 'evento_origen_id inválido (4 a 120 caracteres: letras, dígitos y . _ : + -)';
  const r = await banco({ ingerir: async () => { throw { code: '22023', message: mensaje }; } }).llamar(llamada());
  assert.equal(r.status, 400);
  assert.equal((await r.json()).error, mensaje);
});

Deno.test('cualquier otro fallo: 503 para que el celular reintente, sin detalles internos', async () => {
  for (const fallo of [new Error('red caída'), { code: 'PGRST202', message: 'Could not find the function' }, { code: 'XX000' }, 'texto']) {
    const r = await banco({ ingerir: async () => { throw fallo; } }).llamar(llamada());
    assert.equal(r.status, 503);
    assert.deepEqual(await r.json(), { error: 'No se pudo guardar; vuelve a intentarlo' });
  }
});

Deno.test('latido: 200 con la base; inválido 400; misma autorización y mismo límite', async () => {
  const b = banco();
  const r = await b.llamar({ accion: 'latido', latido: LATIDO });
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { registrado: true });
  assert.deepEqual(b.llamadas, [['registrarSalud', CLAVE, LATIDO]]);
  for (const latido of [{ ...LATIDO, v: 2 }, { ...LATIDO, version_macro: '<script>' }, { ...LATIDO, en_cola: -1 },
    { ...LATIDO, en_cola: 1.5 }, (({ en_cola: _c, ...resto }) => resto)(LATIDO), { ...LATIDO, bateria: 80 }]) {
    assert.equal(latidoValido(latido), false, JSON.stringify(latido));
    const m = banco();
    assert.equal((await m.llamar({ accion: 'latido', latido })).status, 400);
    assert.equal(m.llamadas.length, 0);
  }
  const limite = await banco({ registrarSalud: async () => { throw { code: 'P0429', details: 'reintentar_en_seg=5' }; } })
    .llamar({ accion: 'latido', latido: LATIDO });
  assert.equal(limite.status, 429);
  assert.equal(limite.headers.get('retry-after'), '5');
});

Deno.test('nunca escribe en el registro: ni la clave, ni el número, ni el cuerpo', async () => {
  const metodos = ['log', 'info', 'warn', 'error', 'debug'] as const;
  const originales = metodos.map((m) => console[m]);
  const escritos: unknown[][] = [];
  metodos.forEach((m) => { console[m] = (...args: unknown[]) => { escritos.push(args); }; });
  try {
    await banco().llamar(llamada());
    await banco().llamar(llamada(), { 'x-celular-credencial': 'mal' });
    await banco({ ingerir: async () => { throw new Error(`fallo con ${CLAVE}`); } }).llamar(llamada());
    await banco().llamar({ accion: 'latido', latido: LATIDO });
  } finally {
    metodos.forEach((m, i) => { console[m] = originales[i]; });
  }
  assert.equal(escritos.length, 0);
});
