import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CASOS } from './juicio.mjs';
import { VERSION_RUBRICA, OPCIONES, REGLAS } from './banco-core.mjs';

// Proyección explícita: la clave de respuestas nunca se entrega al navegador.
const casos = CASOS.map(({ id, resultado, nota }) => ({ id, resultado, nota }));
const huella = createHash('sha256').update(JSON.stringify({ version: VERSION_RUBRICA, casos, opciones: OPCIONES, reglas: REGLAS })).digest('hex');
export const BANCO = Object.freeze({ version: VERSION_RUBRICA, huella, casos });
const rutas = new Map([
  ['/', ['banco/index.html', 'text/html; charset=utf-8']],
  ['/equipo-a', ['banco/index.html', 'text/html; charset=utf-8']],
  ['/equipo-b', ['banco/index.html', 'text/html; charset=utf-8']],
  ['/app.mjs', ['banco/app.mjs', 'text/javascript; charset=utf-8']],
  ['/styles.css', ['banco/styles.css', 'text/css; charset=utf-8']],
  ['/banco-core.mjs', ['banco-core.mjs', 'text/javascript; charset=utf-8']],
  ['/fuente-400.woff2', ['../../app/node_modules/@fontsource/plus-jakarta-sans/files/plus-jakarta-sans-latin-400-normal.woff2', 'font/woff2']],
  ['/fuente-600.woff2', ['../../app/node_modules/@fontsource/plus-jakarta-sans/files/plus-jakarta-sans-latin-600-normal.woff2', 'font/woff2']],
]);
const cabeceras = {
  'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY', 'Referrer-Policy': 'no-referrer',
  'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
};

export function crearServidor() {
  let host = null;
  const servidor = createServer(async (peticion, respuesta) => {
    const enviar = (estado, tipo, cuerpo) => {
      respuesta.writeHead(estado, { ...cabeceras, 'Content-Type': tipo });
      respuesta.end(peticion.method === 'HEAD' ? undefined : cuerpo);
    };
    // Sin escucha LAN ni Host arbitrario (DNS rebinding). No hay API de escritura.
    if (peticion.headers.host !== host || (peticion.headers.origin && peticion.headers.origin !== `http://${host}`)) {
      enviar(403, 'text/plain; charset=utf-8', `Origen no permitido. Usa http://${host}/ en esta máquina.`); return;
    }
    if (!['GET', 'HEAD'].includes(peticion.method)) {
      enviar(405, 'text/plain; charset=utf-8', 'Solo lectura'); return;
    }
    if (peticion.url === '/casos.json') {
      enviar(200, 'application/json; charset=utf-8', JSON.stringify(BANCO)); return;
    }
    const ruta = rutas.get(peticion.url);
    if (!ruta) { enviar(404, 'text/plain; charset=utf-8', 'No encontrado'); return; }
    try { enviar(200, ruta[1], await readFile(new URL(ruta[0], import.meta.url))); }
    catch { enviar(500, 'text/plain; charset=utf-8', 'Recurso local no disponible'); }
  });
  servidor.on('listening', () => { host = `127.0.0.1:${servidor.address().port}`; });
  return servidor;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const argumentos = process.argv.slice(2);
  const puerto = argumentos.length === 0 ? 5274 : Number(argumentos[0]);
  if (argumentos.length > 1 || !Number.isInteger(puerto) || puerto < 1024 || puerto > 65535) {
    console.error('Uso: node banco.mjs [puerto entre 1024 y 65535]'); process.exitCode = 1;
  } else {
    const servidor = crearServidor();
    servidor.on('error', () => { console.error('No se pudo abrir el puerto local.'); process.exitCode = 1; });
    servidor.listen(puerto, '127.0.0.1', () => console.log(`Banco sintético: http://127.0.0.1:${puerto}/ — sin CRM ni TypeSafe`));
  }
}
