import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { sql } from './banco-local.mjs';

const scripts = ['probar-cooperativas.mjs', 'probar-portal-nuevo.mjs', 'probar-portal-veto.mjs',
  'probar-revision-responsable.mjs', 'probar-documento.mjs', 'probar-fusion.mjs',
  'probar-identidad-controles.mjs', 'probar-concurrencia.mjs', 'verificar-estructura.mjs'];
const pruebas = [];
const flag = sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'") === 't';
try {
  for (const script of scripts) {
    const inicio = performance.now();
    const r = spawnSync(process.execPath, [fileURLToPath(new URL(script, import.meta.url))], { stdio: 'inherit' });
    assert.equal(r.status, 0, `Regresión no conforme: ${script}`);
    pruebas.push({ script, conforme: true, duracionMs: Math.round(performance.now() - inicio) });
  }
} finally {
  sql(`update crm.multiempresa_flags set activo=${flag} where nombre='inversiones_escritura'`);
}
const terminadoEn = new Date().toISOString();
const candidata = JSON.parse(readFileSync(new URL('./ultima-migracion.json', import.meta.url))).archivo;
writeFileSync(new URL(`../evidencia-f4/regresion-reintento-${terminadoEn.replaceAll(':', '-')}.json`, import.meta.url),
  JSON.stringify({ entorno: 'avancecorp-f4-bank', terminadoEn, pruebas,
    sha256Candidata: createHash('sha256').update(readFileSync(new URL(`../../migrations/${candidata}`, import.meta.url))).digest('hex'),
    limite: 'Regresión de las puertas y candados afectados por la separación de autorización y operación. G4 completo continúa pendiente.',
  }, null, 2) + '\n', { flag: 'wx' });
