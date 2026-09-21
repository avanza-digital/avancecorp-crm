// Frontera HTTP con TypeSafe. Lo único de este toolkit que sale a la red.
//
// La clave NUNCA se imprime, ni en un error: `codigoDeError` reduce cualquier
// fallo a un código corto, igual que hace la edge de temperatura. Tampoco se
// pasa por argumento ni por el prompt: se lee de `TYPESAFE_API_KEY` o del
// archivo `~/.config/typesafe/key` (modo 600).
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

const URL_API = 'https://api.typesafe.ai/v1/systemone';
const MODELO = process.env.TYPESAFE_MODELO || 'jev-latest';

export async function leerClave() {
  const env = process.env.TYPESAFE_API_KEY;
  if (env && env.trim().length > 20) return env.trim();
  const ruta = process.env.TYPESAFE_KEY_FILE || join(homedir(), '.config', 'typesafe', 'key');
  try {
    const k = (await readFile(ruta, 'utf8')).trim();
    if (k.length > 20) return k;
    throw new Error('clave_corta');
  } catch {
    throw new Error(`sin_clave: pon la clave en TYPESAFE_API_KEY o en ${ruta}`);
  }
}

export class RespuestaHttp extends Error {
  constructor(codigo, reintentable) {
    super(`http_${codigo}`);
    this.name = 'RespuestaHttp';
    this.codigo = codigo;
    this.reintentable = reintentable;
  }
}

const espera = (ms) => new Promise((r) => setTimeout(r, ms));

/** Una consulta = un `state` y todas las preguntas independientes juntas.
 *  429 y 529 se reintentan con espera creciente; el resto se rinde enseguida. */
export async function preguntar({ state, questions }, { clave, modelo = MODELO, intentos = 4, tope = 30000 } = {}) {
  let ultimo;
  for (let i = 0; i < intentos; i += 1) {
    try {
      const r = await fetch(URL_API, {
        method: 'POST',
        headers: { Authorization: `Bearer ${clave}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ state, model: modelo, questions }),
        signal: AbortSignal.timeout(tope),
      });
      if (r.ok) {
        const cuerpo = await r.json();
        if (!cuerpo || typeof cuerpo.answers !== 'object' || cuerpo.answers === null) {
          throw new Error('respuesta_invalida');
        }
        return { respuestas: cuerpo.answers, modelo: cuerpo.model ?? null, uso: cuerpo.usage ?? null };
      }
      throw new RespuestaHttp(r.status, r.status === 429 || r.status === 529 || r.status >= 500);
    } catch (e) {
      ultimo = e;
      const reintentable = e instanceof RespuestaHttp ? e.reintentable : e?.name === 'TimeoutError';
      if (!reintentable || i === intentos - 1) break;
      await espera(700 * 2 ** i + Math.floor(Math.random() * 300));
    }
  }
  throw ultimo;
}

export function codigoDeError(e) {
  if (e instanceof RespuestaHttp) return `http_${e.codigo}`;
  if (e?.name === 'TimeoutError') return 'timeout';
  if (e?.message === 'respuesta_invalida') return 'respuesta_invalida';
  if (typeof e?.message === 'string' && e.message.startsWith('sin_clave')) return 'sin_clave';
  return 'error_desconocido';
}

/** Ejecuta `tarea` sobre cada elemento con como mucho `n` en vuelo. El orden
 *  de salida es el de entrada; un fallo no tumba el lote. */
export async function enParalelo(elementos, n, tarea) {
  const salida = new Array(elementos.length);
  let siguiente = 0;
  const obrero = async () => {
    for (;;) {
      const i = siguiente;
      siguiente += 1;
      if (i >= elementos.length) return;
      try {
        salida[i] = { ok: true, valor: await tarea(elementos[i], i) };
      } catch (e) {
        salida[i] = { ok: false, error: codigoDeError(e) };
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(n, elementos.length) }, obrero));
  return salida;
}
