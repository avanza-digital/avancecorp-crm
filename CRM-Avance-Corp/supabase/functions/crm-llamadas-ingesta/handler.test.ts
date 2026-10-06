import { strict as assert } from 'node:assert';
import { crearHandler, leerResultado, segundosDeEspera, urlAbrir, type Dependencias } from './handler.ts';

// Todo sintético: ni claves, ni números ni URLs reales.
const CLAVE = 'a'.repeat(64);
const EVENTO = {
  v: 1, evento_origen_id: 'C1-1790980958', numero: '+51900000001', direccion: 'saliente',
  estado_tecnico: 'conectada', duracion_seg: 42, ocurrio_en: '2026-10-01T15:00:00Z',
};
const LATIDO = { v: 1, version_macro: 'macro 1.0', en_cola: 0, ocurrio_en: '2026-10-01T15:00:00Z' };
const BASE = 'https://crm.ejemplo.invalid';
const ACEPTADO = { resultado: 'aceptado' };
const invalido = (mensaje: string) => ({ resultado: 'invalido', mensaje });

function banco(cambios: Partial<Dependencias> = {}) {
  const llamadas: unknown[][] = [];
  const deps: Dependencias = {
    urlCrm: BASE,
    ingerir: async (...args) => { llamadas.push(['ingerir', ...args]); return ACEPTADO; },
    registrarSalud: async (...args) => { llamadas.push(['registrarSalud', ...args]); return ACEPTADO; },
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
      ingerir: async () => { throw { code: '42501', message: 'No autorizado' }; },
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

Deno.test('se corta la lectura del cuerpo: 503 controlado para que el celular reintente, sin tocar la base', async () => {
  // Revisión de Miguel en el #190: un ReadableStream que falla hacía rechazar al handler sin devolver Response.
  const llamadas: unknown[] = [];
  const handler = crearHandler({
    urlCrm: BASE,
    ingerir: async (...args) => { llamadas.push(args); return ACEPTADO; },
    registrarSalud: async (...args) => { llamadas.push(args); return ACEPTADO; },
  });
  let enviado = false;
  const cuerpo = new ReadableStream<Uint8Array>({
    pull(c) {
      if (enviado) c.error(new Error('conexión cortada'));
      else { enviado = true; c.enqueue(new TextEncoder().encode('{"accion":"llamada",')); }
    },
  });
  const r = await handler(new Request('https://ejemplo.invalid/crm-llamadas-ingesta', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-celular-credencial': CLAVE }, body: cuerpo,
    duplex: 'half',
  } as RequestInit));
  assert.equal(r.status, 503);
  assert.deepEqual(await r.json(), { error: 'No se pudo leer la petición; vuelve a intentarlo' });
  assert.equal(llamadas.length, 0);
});

Deno.test('JSON mal formado o sobre inválido: llega a la base con la carga en null (gasta cupo) y su «invalido» es 400', async () => {
  const mensaje = 'El evento debe ser un objeto JSON';
  for (const cuerpo of ['{', '[]', '"grande"', 'null', '42', JSON.stringify({ ...llamada(), extra: 1 }),
    JSON.stringify({ accion: 'otra', evento: EVENTO }), JSON.stringify({ accion: 'llamada' }),
    JSON.stringify({ accion: 'llamada', latido: LATIDO })]) {
    const b = banco({ ingerir: async (...args) => { b.llamadas.push(['ingerir', ...args]); return invalido(mensaje); } });
    const r = await b.llamar(cuerpo);
    assert.equal(r.status, 400, cuerpo);
    assert.deepEqual(await r.json(), { error: mensaje }, cuerpo);
    assert.deepEqual(b.llamadas, [['ingerir', CLAVE, null]], cuerpo);
  }
  // Con accion «latido», la puerta es la de latidos, también si el sobre está mal.
  for (const cuerpo of [{ accion: 'latido', evento: EVENTO }, { accion: 'latido', latido: LATIDO, extra: 1 }]) {
    const b = banco();
    await b.llamar(cuerpo);
    assert.deepEqual(b.llamadas, [['registrarSalud', CLAVE, null]], JSON.stringify(cuerpo));
  }
});

Deno.test('la Edge no juzga el contenido: el evento llega TAL CUAL a la base', async () => {
  const raros: unknown[] = [
    { ...EVENTO, v: 2 }, { ...EVENTO, evento_origen_id: 'C1 con espacios' }, { ...EVENTO, duracion_seg: '30' },
    { ...EVENTO, ocurrio_en: 'ayer' }, { ...EVENTO, extra: true }, [], 'evento', null,
  ];
  for (const evento of raros) {
    const b = banco();
    await b.llamar(llamada(evento));
    assert.deepEqual(b.llamadas, [['ingerir', CLAVE, evento]], JSON.stringify(evento));
  }
});

Deno.test('llamada válida: la base recibe la clave y el evento tal cual; 202', async () => {
  const b = banco();
  const r = await b.llamar(llamada());
  assert.equal(r.status, 202);
  assert.deepEqual(b.llamadas, [['ingerir', CLAVE, EVENTO]]);
  assert.equal(r.headers.get('cache-control'), 'no-store');
});

Deno.test('guardada, repetida o ignorada: la MISMA respuesta (propuesta #12), aunque la base mandara de más', async () => {
  const cuerpos: unknown[] = [];
  for (const dato of [ACEPTADO, { ...ACEPTADO, evento_id: '00000000-0000-4000-8000-000000000001', ignorado: true }]) {
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

Deno.test('la base dice «invalido»: 400 con su mensaje, recortado a 200; sin mensaje, uno genérico', async () => {
  const mensaje = 'evento_origen_id inválido: se espera la etiqueta del celular y los segundos de su reloj (p. ej. C1-1790980958)';
  let r = await banco({ ingerir: async () => invalido(mensaje) }).llamar(llamada());
  assert.equal(r.status, 400);
  assert.equal((await r.json()).error, mensaje);
  r = await banco({ ingerir: async () => invalido('x'.repeat(300)) }).llamar(llamada());
  assert.equal((await r.json()).error.length, 200);
  r = await banco({ ingerir: async () => ({ resultado: 'invalido' }) }).llamar(llamada());
  assert.equal(r.status, 400);
  assert.equal((await r.json()).error, 'Petición inválida');
  assert.deepEqual(leerResultado(invalido('m')), { aceptado: false, mensaje: 'm' });
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

Deno.test('cualquier otro fallo o un resultado sin la forma pactada: 503 para que el celular reintente, sin detalles', async () => {
  // P0409 y 22023 ya no existen en el contrato: si volvieran, son inesperados.
  const fallos: unknown[] = [new Error('red caída'), { code: 'PGRST202', message: 'Could not find the function' },
    { code: 'XX000' }, { code: 'P0409', message: 'otro contenido' }, { code: '22023', message: 'inválido' }, 'texto'];
  for (const fallo of fallos) {
    const r = await banco({ ingerir: async () => { throw fallo; } }).llamar(llamada());
    assert.equal(r.status, 503, JSON.stringify(fallo));
    assert.deepEqual(await r.json(), { error: 'No se pudo guardar; vuelve a intentarlo' });
  }
  for (const dato of [null, undefined, {}, { resultado: 'otro' }, 'aceptado', { evento_id: 'x', repetido: false }]) {
    const r = await banco({ ingerir: async () => dato }).llamar(llamada());
    assert.equal(r.status, 503, JSON.stringify(dato));
  }
});

Deno.test('latido: 200 con «aceptado»; 400 con «invalido»; misma autorización y mismo límite; llega tal cual', async () => {
  const b = banco();
  const r = await b.llamar({ accion: 'latido', latido: LATIDO });
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { registrado: true });
  assert.deepEqual(b.llamadas, [['registrarSalud', CLAVE, LATIDO]]);
  const raro = { ...LATIDO, bateria: 80 };
  const m = banco({ registrarSalud: async (...args) => { m.llamadas.push(['registrarSalud', ...args]); return invalido('El latido trae claves no previstas'); } });
  const s = await m.llamar({ accion: 'latido', latido: raro });
  assert.equal(s.status, 400);
  assert.deepEqual(await s.json(), { error: 'El latido trae claves no previstas' });
  assert.deepEqual(m.llamadas, [['registrarSalud', CLAVE, raro]]);
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
    await banco().llamar('{');
  } finally {
    metodos.forEach((m, i) => { console[m] = originales[i]; });
  }
  assert.equal(escritos.length, 0);
});

Deno.test('JSON imposible para jsonb conserva autenticación y cupo: llega null a la puerta correcta', async () => {
  for (const accion of ['llamada', 'latido']) {
    for (const valor of ['\u0000', '\ud800', '\udfff', { '\u0000': 'valor' }, [1, '\ud800']]) {
      const b = banco({
        ingerir: async (clave, carga) => {
          assert.equal(accion, 'llamada'); assert.equal(clave, CLAVE); assert.equal(carga, null);
          return invalido('Petición inválida');
        },
        registrarSalud: async (clave, carga) => {
          assert.equal(accion, 'latido'); assert.equal(clave, CLAVE); assert.equal(carga, null);
          return invalido('Petición inválida');
        },
      });
      const r = await b.llamar({ accion, [accion === 'latido' ? 'latido' : 'evento']: { v: 1, valor } });
      assert.equal(r.status, 400);
    }
  }
  // No rechazar Unicode válido ni texto que describe un escape literal.
  for (const valor of ['😀', '\\u0000', 'José']) {
    const b = banco();
    assert.equal((await b.llamar({ accion: 'llamada', evento: { ...EVENTO, valor } })).status, 202);
    assert.equal((b.llamadas[0][2] as Record<string, unknown>).valor, valor);
  }
  const sinPermiso = banco({ ingerir: async (_clave, carga) => {
    assert.equal(carga, null); throw { code: '42501' };
  } });
  assert.equal((await sinPermiso.llamar({ accion: 'llamada', evento: { valor: '\u0000' } })).status, 401);
  const agotado = banco({ ingerir: async (_clave, carga) => {
    assert.equal(carga, null); throw { code: 'P0429', details: '9' };
  } });
  assert.equal((await agotado.llamar({ accion: 'llamada', evento: { valor: '\ud800' } })).status, 429);
});
