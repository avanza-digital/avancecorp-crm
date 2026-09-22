// Sólo SELECT de catálogos en el origen. Jamás copia filas de usuarios/negocio.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { carpeta, sql } from './banco.mjs';

assert.deepEqual(process.argv.slice(2), ['--comparar-origen']);
const origen = 'dctqcbznekcyxhjujuci';
const fuente = readFileSync(new URL('./paridad.sql', import.meta.url), 'utf8');
const consulta = fuente.slice(0, fuente.lastIndexOf('\nselect categoria,count(*)'))
  + '\nselect categoria,linea from todo order by categoria,linea;';
assert.ok(consulta.startsWith('-- Sólo catálogos'));
assert.ok(!/\b(?:insert|update|delete|alter|drop|grant|revoke|create)\s/i.test(consulta), 'La consulta de origen debe ser de sólo lectura');
const r = spawnSync('supabase', ['db', 'query', '--linked', '--project-ref', origen, '-o', 'json',
  consulta.replace(/^--[^\n]*\n/gm, '')], {
  cwd: new URL('../../../../', import.meta.url), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  timeout: 120_000, stdio: ['ignore', 'pipe', 'pipe'],
});
assert.equal(r.status, 0, 'No se pudo leer el catálogo de origen; no se asume paridad');
const remoto = JSON.parse(r.stdout).rows;
assert.ok(Array.isArray(remoto) && remoto.length > 1000);
const local = sql(consulta.replace('select categoria,linea from todo order by categoria,linea;',
  "select jsonb_build_object('categoria',categoria,'linea',linea) from todo order by categoria,linea;"))
  .split('\n').map(l => JSON.parse(l));
const key = r => `${r.categoria}|${r.linea}`;
const remotos = new Set(remoto.map(key));
const locales = new Set(local.map(key));
const faltan = remoto.filter(r => !locales.has(key(r)));
const sobran = local.filter(r => !remotos.has(key(r)));
const evidencia = { capturado_en: new Date().toISOString(), origen, banco: 'gestion-diaria-f4-http',
  comparacion: 'catálogos de public/crm/private; excluye extensiones y registro de replay',
  estado: faltan.length || sobran.length ? 'FAIL' : 'PASS', faltan, sobran };
writeFileSync(`${carpeta}/paridad-origen.json`, JSON.stringify(remoto, null, 2)+'\n', { mode: 0o600 });
writeFileSync(`${carpeta}/paridad-local.json`, JSON.stringify(local, null, 2)+'\n', { mode: 0o600 });
writeFileSync(`${carpeta}/paridad-diferencias.json`, JSON.stringify(evidencia, null, 2)+'\n', { mode: 0o600 });
console.log(JSON.stringify({ estado: evidencia.estado, faltan: faltan.length, sobran: sobran.length,
  categorias: [...new Set([...faltan,...sobran].map(r => r.categoria))] }));
process.exitCode = evidencia.estado === 'PASS' ? 0 : 1;
