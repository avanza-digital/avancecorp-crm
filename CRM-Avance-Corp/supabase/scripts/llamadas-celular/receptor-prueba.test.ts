import { strict as assert } from 'node:assert';
import { crearReceptor, enmascarar, RUTA } from './receptor-prueba.ts';

// Todo sintético: ni claves, ni números ni URLs reales.
const CLAVE = 'b'.repeat(64);
const LOCAL = { hostname: '127.0.0.1' };
const CELULAR = { hostname: '192.168.0.50' };
const EVENTO = {
  v: 1, evento_origen_id: 'C1-1790980958', numero: '+51900000123', direccion: 'saliente',
  estado_tecnico: 'conectada', duracion_seg: 30, ocurrio_en: '2026-10-02T15:00:00Z',
};

function banco(t0 = Date.parse('2026-10-02T15:00:10Z')) {
  let t = t0;
  const lineas: string[] = [];
  const r = crearReceptor({ clave: CLAVE, urlCrm: 'https://crm.ejemplo.invalid', ahora: () => t, anotar: (l) => lineas.push(l) });
  const enviar = (cuerpo: unknown, clave: string | null = CLAVE, remoto = CELULAR) =>
    r(new Request(`http://receptor.invalid${RUTA}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(clave === null ? {} : { 'x-celular-credencial': clave }) },
      body: JSON.stringify(cuerpo),
    }), remoto);
  const pedir = (ruta: string, remoto = LOCAL) => r(new Request(`http://receptor.invalid${ruta}`), remoto);
  return { enviar, pedir, lineas, avanzar: (ms: number) => { t += ms; } };
}
const llamada = (evento: object = EVENTO) => ({ accion: 'llamada', evento });

Deno.test('usa el handler real: otra ruta 404, GET 405, clave ausente o ajena 401', async () => {
  const b = banco();
  assert.equal((await b.pedir('/otra', CELULAR)).status, 404);
  assert.equal((await b.pedir(RUTA, CELULAR)).status, 405);
  assert.equal((await b.enviar(llamada(), null)).status, 401);
  assert.equal((await b.enviar(llamada(), 'c'.repeat(64))).status, 401);
  assert.match(b.lineas.at(-1)!, /401 \(clave desconocida\) · clave incorrecta/);
});

Deno.test('guarda, abre la encuesta de F1 y no registra la clave ni el número completo', async () => {
  const b = banco();
  const r = await b.enviar(llamada());
  assert.equal(r.status, 202);
  assert.deepEqual(await r.json(), { recibido: true, abrir: 'https://crm.ejemplo.invalid/#/gestion-diaria/llamada/%2B51900000123' });
  const linea = b.lineas.at(-1)!;
  assert.match(linea, /202 \(guardada\) · clave correcta · llamada id=C1-1790980958 …123 saliente/);
  assert.ok(!linea.includes(CLAVE) && !linea.includes('900000123'));
});

Deno.test('mismo id: el primer envío gana; con cualquier contenido responde lo mismo (sin 409)', async () => {
  const b = banco();
  assert.equal((await b.enviar(llamada())).status, 202);
  assert.equal((await b.enviar(llamada({ ...EVENTO, duracion_seg: 31 }))).status, 202);
  assert.match(b.lineas.at(-1)!, /202 \(repetida \(ya estaba\)\)/);
  const estado = await (await b.pedir('/_estado')).json();
  assert.deepEqual([estado.guardadas, estado.repetidas, estado.en_minuto], [1, 1, 2]);
});

Deno.test('inválido: 400 con el mensaje de la base y el cupo gastado igual', async () => {
  const b = banco();
  for (const cuerpo of [llamada({ ...EVENTO, evento_origen_id: 'C1-1759400000000' }), { accion: 'llamada', evento: 5 }, { accion: 'otra' }]) {
    assert.equal((await b.enviar(cuerpo)).status, 400, JSON.stringify(cuerpo));
  }
  const estado = await (await b.pedir('/_estado')).json();
  assert.deepEqual([estado.invalidos, estado.en_minuto], [3, 3]);
});

Deno.test('entrante o sin dirección: misma respuesta, no se guarda', async () => {
  const b = banco();
  assert.equal((await b.enviar(llamada({ ...EVENTO, direccion: 'entrante' }))).status, 202);
  assert.equal((await b.enviar(llamada({ ...EVENTO, evento_origen_id: 'C1-1790980959', direccion: undefined }))).status, 202);
  const estado = await (await b.pedir('/_estado')).json();
  assert.deepEqual([estado.guardadas, estado.ignoradas, estado.repetidas], [0, 2, 0]);
});

Deno.test('límite de 30 por minuto de reloj, compartido con los latidos, con Retry-After', async () => {
  const b = banco(); // 10 s pasado el minuto
  const latido = { accion: 'latido', latido: { v: 1, version_macro: 'prueba 1', en_cola: 0 } };
  assert.equal((await b.enviar(latido)).status, 200);
  for (let i = 1; i < 30; i++) {
    assert.equal((await b.enviar(llamada({ ...EVENTO, evento_origen_id: `C1-${1790980000 + i}` }))).status, 202);
  }
  const r = await b.enviar(llamada({ ...EVENTO, evento_origen_id: 'C1-1790980031' }));
  assert.equal(r.status, 429);
  assert.equal(r.headers.get('retry-after'), '50');
  b.avanzar(50_000);
  assert.equal((await b.enviar(llamada({ ...EVENTO, evento_origen_id: 'C1-1790980031' }))).status, 202);
});

Deno.test('ocurrio_en fuera de rango: el 400 con el mensaje de la base', async () => {
  const r = await banco().enviar(llamada({ ...EVENTO, ocurrio_en: '2025-12-31T23:59:59Z' }));
  assert.equal(r.status, 400);
  assert.deepEqual(await r.json(), { error: 'ocurrio_en fuera de rango' });
});

Deno.test('control solo desde este PC; la falla simulada dura las veces pedidas', async () => {
  const b = banco();
  assert.equal((await b.pedir('/_control?modo=503&veces=2', CELULAR)).status, 404);
  assert.equal((await b.pedir('/_estado', CELULAR)).status, 404);
  assert.equal((await b.pedir('/_control?modo=raro')).status, 400);
  assert.equal((await b.pedir('/_control?modo=503&veces=2')).status, 200);
  assert.equal((await b.enviar(llamada())).status, 503);
  assert.equal((await b.enviar(llamada())).status, 503);
  assert.equal((await b.enviar(llamada())).status, 202);
  await b.pedir('/_control?modo=429');
  const r = await b.enviar(llamada());
  assert.equal(r.status, 429);
  assert.equal(r.headers.get('retry-after'), '30');
  await b.pedir('/_control?modo=401');
  assert.equal((await b.enviar(llamada())).status, 401);
  assert.equal((await b.enviar(llamada())).status, 202, 'vuelve a normal solo');
});

Deno.test('dos envíos a la vez: cada línea dice lo suyo', async () => {
  const b = banco();
  const [a, c] = await Promise.all([b.enviar(llamada()), b.enviar(llamada())]);
  assert.deepEqual([a.status, c.status], [202, 202]);
  assert.equal(b.lineas.filter((l) => l.includes('(guardada)')).length, 1);
  assert.equal(b.lineas.filter((l) => l.includes('(repetida (ya estaba))')).length, 1);
});

Deno.test('enmascarar deja solo los 3 últimos dígitos', () => {
  assert.equal(enmascarar('+51 900 000 123'), '…123');
  assert.equal(enmascarar('12'), '…');
  assert.equal(enmascarar(''), 'sin número');
  assert.equal(enmascarar(undefined), 'sin número');
});
