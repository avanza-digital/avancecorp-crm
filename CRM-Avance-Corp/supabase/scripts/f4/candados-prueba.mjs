import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { contenedor, sql } from './banco-local.mjs';

export function sqlEnProceso(texto) {
  const p = spawn('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'supabase_admin',
    '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', '-'], { stdio: ['pipe', 'pipe', 'pipe'] });
  let salida = '';
  let error = '';
  p.stdout.setEncoding('utf8');
  p.stderr.setEncoding('utf8');
  p.stdout.on('data', s => { salida += s; });
  p.stderr.on('data', s => { error += s; });
  const fin = new Promise((resolve, reject) => {
    p.on('error', reject);
    p.on('exit', codigo => codigo === 0 ? resolve(salida.trim()) : reject(new Error(`SQL concurrente F4: ${error}`)));
  });
  p.stdin.end(`set timezone='America/Lima';\n${texto}\n`);
  return fin;
}

export async function retener(texto) {
  const p = spawn('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'supabase_admin',
    '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', '-'], { stdio: ['pipe', 'pipe', 'pipe'] });
  let error = '';
  let salida = '';
  p.stderr.setEncoding('utf8');
  p.stdout.setEncoding('utf8');
  p.stderr.on('data', s => { error += s; });
  const fin = new Promise((resolve, reject) => {
    p.on('error', reject);
    p.on('exit', codigo => codigo === 0 ? resolve() : reject(new Error(error)));
  });
  const listo = new Promise((resolve, reject) => {
    const limite = setTimeout(() => { p.stdin.end('rollback;\n'); reject(new Error('No se obtuvo el candado de ensayo')); }, 5000);
    p.stdout.on('data', s => {
      salida += s;
      if (salida.includes('F4_CANDADO_LISTO')) { clearTimeout(limite); resolve(); }
    });
    p.on('error', e => { clearTimeout(limite); reject(e); });
    p.on('exit', codigo => { clearTimeout(limite); if (!salida.includes('F4_CANDADO_LISTO')) reject(new Error(error || `Candado terminó ${codigo}`)); });
  });
  p.stdin.write(`begin;\nset local lock_timeout='3s';\n${texto};\nselect 'F4_CANDADO_LISTO';\n`);
  await listo;
  return async () => { p.stdin.end('commit;\n'); await fin; };
}

export async function esperarActividad(predicado, minimo) {
  const hasta = Date.now() + 5000;
  let vistos = 0;
  while (Date.now() < hasta) {
    vistos = Number(sql(`select count(*) from pg_stat_activity a where a.pid<>pg_backend_pid() and (${predicado})`, { admin: true }));
    if (vistos >= minimo) return vistos;
    await new Promise(resolve => setTimeout(resolve, 40));
  }
  assert.fail(`No se demostró coincidencia de procesos: se esperaban ${minimo}, se observaron ${vistos}`);
}
