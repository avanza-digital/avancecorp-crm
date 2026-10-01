// Banco Docker PROPIO de este kit. No acepta URLs, credenciales ni destinos externos: solo
// `docker exec` contra un contenedor local `avancecorp-gestionado-AAAAMMDD`. Producción no
// se toca de ninguna forma desde aquí.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

export const contenedor = process.env.BANCO_CONTENEDOR ?? 'avancecorp-gestionado-20261001';
assert.match(contenedor, /^avancecorp-gestionado-[0-9]{8}$/,
  'Este kit solo habla con su propio banco Docker (avancecorp-gestionado-AAAAMMDD)');

const NO_LLEGO_A_PSQL = /500 Internal Server Error for API route|Cannot connect to the Docker daemon|error during connect/;

/**
 * Ejecuta SQL en el banco.
 *  - usuario: `postgres` (el rol que aplica migraciones en producción; por defecto) o
 *    `supabase_admin` (superusuario; solo para medir con auto_explain).
 *  - unMensaje: manda todo en UN mensaje (`psql -c`), como `supabase db query --file` en
 *    producción; si no, sentencia a sentencia por stdin (`statement_timestamp()` avanza).
 */
export function ejecutar(sql, { usuario = 'postgres', unMensaje = false } = {}) {
  assert.ok(['postgres', 'supabase_admin'].includes(usuario));
  const base = ['exec', '-i', '-e', 'PGPASSWORD=postgres', contenedor, 'psql', '-X', '-qAt',
    '-U', usuario, '-h', '127.0.0.1', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'];
  let r;
  for (let intento = 1; intento <= 3; intento++) {
    r = unMensaje
      ? spawnSync('docker', [...base, '-c', sql], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
      : spawnSync('docker', [...base, '-f', '-'], { input: sql, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    // Si el daemon de Docker falló antes de llegar a psql no se ejecutó nada: repetir es seguro.
    if (r.status === 0 || !NO_LLEGO_A_PSQL.test(r.stderr ?? '')) return r;
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2000 * intento);
  }
  return r;
}

/** Ejecuta y exige éxito; devuelve stdout sin líneas vacías. */
export function sql(texto, opciones) {
  const r = ejecutar(texto, opciones);
  assert.equal(r.status, 0, `psql falló:\n${(r.stderr || r.error?.message || '').slice(0, 2000)}`);
  return r.stdout.split('\n').filter((l) => l.trim() !== '').join('\n');
}

/** Un único valor de texto TAL CUAL (con sus líneas vacías): para copiar una definición sin tocarla. */
export function crudo(texto, opciones) {
  const r = ejecutar(texto, opciones);
  assert.equal(r.status, 0, `psql falló:\n${(r.stderr || r.error?.message || '').slice(0, 2000)}`);
  return r.stdout.replace(/\n$/, '');
}

/** Ejecuta y EXIGE que falle con un mensaje concreto. Devuelve la línea del error. */
export function debeFallar(texto, patron, motivo, opciones) {
  const r = ejecutar(texto, opciones);
  assert.notEqual(r.status, 0, `Debió fallar y pasó: ${motivo}`);
  const error = (r.stderr ?? '').split('\n').find((l) => /ERROR:/.test(l)) ?? (r.stderr ?? '').slice(0, 300);
  assert.match(error, patron, `Falló por OTRA causa (${motivo}): ${error}`);
  return error.replace(/^.*ERROR:\s*/, '').trim();
}

/** Quita el `begin;` / `commit;` / `rollback;` de un guion para componerlo dentro de otra transacción. */
export const sinTx = (texto) => texto.replace(/^(begin|commit|rollback);[ \t]*$/gm, '');

/** Compone piezas dentro de UNA transacción que siempre se deshace. */
export const deshecho = (...piezas) => `begin;\n${piezas.join('\n')}\nrollback;\n`;
