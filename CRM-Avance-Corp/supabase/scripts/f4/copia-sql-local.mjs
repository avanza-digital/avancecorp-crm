// Copia exclusivamente la base sintética F4 para ensayos SQL entre sesiones.
// No copia archivos de Storage ni representa un ensayo HTTP/Auth independiente.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, openSync, closeSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { banco, contenedor, literal } from './banco-local.mjs';

export function crearCopiaSql(etiqueta, {baseOrigen='postgres'} = {}) {
  assert(baseOrigen==='postgres'||/^f4_pre_fcuatro_[a-f0-9]{12}$/.test(baseOrigen), 'Origen de copia no permitido');
  assert(/^[a-z_]{1,24}$/.test(etiqueta));
  const id = randomUUID();
  const nombre = `f4_${etiqueta}_${id.replaceAll('-', '').slice(0,12)}`;
  const carpeta = join(banco, 'copias-sql', nombre);
  mkdirSync(carpeta, { recursive: true, mode: 0o700 });
  function ejecutar(args, opciones = {}) {
    const r = spawnSync('docker', ['exec', '-i', contenedor, ...args],
      { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, ...opciones });
    assert.equal(r.status, 0, r.stderr || r.error?.message || `Falló ${args[0]}`);
    return r.stdout?.trim();
  }
  const archivo = join(carpeta, 'base-sintetica.dump');
  const fd = openSync(archivo, 'wx', 0o600);
  try {
    // pg_cron solo puede instalarse en la base del planificador; sus tareas y
    // replicación no forman parte de este ensayo y no deben arrancar duplicadas.
    ejecutar(['pg_dump','-U','supabase_admin','-d',baseOrigen,'-Fc',
      '--exclude-extension=pg_cron','--exclude-schema=cron','--no-publications','--no-subscriptions'],
    { stdio: ['ignore',fd,'pipe'] });
  } finally { closeSync(fd); }
  ejecutar(['createdb','-U','supabase_admin',nombre]);
  const entrada = openSync(archivo, 'r');
  try {
    ejecutar(['pg_restore','-U','supabase_admin','-d',nombre,'--exit-on-error'],
      { stdio: [entrada,'pipe','pipe'] });
  } finally { closeSync(entrada); }

  function sql(texto, {admin=false} = {}) {
    return ejecutar(['psql','-X','-qAt','-U',admin?'supabase_admin':'postgres','-d',nombre,
      '-v','ON_ERROR_STOP=1','-f','-'], { input: `set timezone='America/Lima';\n${texto}\n` });
  }
  function abrirSesion(aplicacion) {
    assert(/^[a-z0-9_-]{1,60}$/.test(aplicacion));
    const p = spawn('docker', ['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres',
      '-d',nombre,'-v','ON_ERROR_STOP=1','-f','-'], { stdio: ['pipe','pipe','pipe'] });
    let salida = '', error = '';
    p.stdout.setEncoding('utf8'); p.stderr.setEncoding('utf8');
    p.stdout.on('data', s => { salida += s; });
    p.stderr.on('data', s => { error += s; });
    // El resultado nunca rechaza antes de que el controlador pueda observarlo.
    const terminado = new Promise(resolve => {
      p.on('error', e => resolve({ codigo: -1, salida, error: e.message }));
      p.on('close', codigo => resolve({ codigo, salida: salida.trim(), error }));
    });
    p.stdin.on('error', () => {});
    p.stdin.write(`set application_name=${literal(aplicacion)}; set timezone='America/Lima';\n`);
    return { enviar: texto => p.stdin.write(`${texto}\n`),
      cerrar: (texto = 'rollback;') => { p.stdin.end(`${texto}\n`); return terminado; },
      terminado, salida: () => salida };
  }
  async function esperar(predicado, mensaje, plazo = 2500) {
    const hasta = Date.now() + plazo;
    while (Date.now() < hasta) {
      if (predicado()) return;
      await new Promise(resolve => setTimeout(resolve, 40));
    }
    assert.fail(mensaje);
  }
  return { id, nombre, carpeta, archivo, sql, abrirSesion, esperar };
}
