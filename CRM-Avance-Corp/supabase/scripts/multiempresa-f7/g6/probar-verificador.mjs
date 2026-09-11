// Mutaciones en memoria de una captura privada: nunca cambian el origen.
import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { verificarPostflight } from './verificar-postflight.mjs';
import { verificarLectura } from './verificar-lectura.mjs';

assert.equal(process.argv.length, 3, 'Uso: probar-verificador.mjs captura-privada.json');
const original = JSON.parse(await readFile(process.argv[2], 'utf8'));
assert.equal(verificarLectura(original).estado, 'PARIDAD_TECNICA_PASS');
const casos = [
  ['un céntimo adicional', e => { e.meses[0].informe.produccion[0].capital += 0.01; }],
  ['grupo empresa/moneda perdido', e => { e.meses[0].informe.produccion.pop(); }],
  ['atribución cambiada con capital total intacto', e => {
    const d = e.meses[0].detalle_operaciones.find(x => x.analista_id !== null);
    assert.ok(d); d.analista_id = null;
  }],
  ['inversión repetida en el detalle', e => {
    e.meses[0].detalle_operaciones.push(structuredClone(e.meses[0].detalle_operaciones[0]));
  }],
  ['capital del reporte oficial cambiado', e => { e.meses[0].capital_publicado[0].capital_colocado += 0.01; }],
  ['bandera F7 encendida', e => { e.bandera_real = true; }],
  ['mes solicitado ausente', e => { e.meses.pop(); }],
  ['estado de mes sellado alterado', e => { e.meses[0].informe.mes_sellado = !e.meses[0].informe.mes_sellado; }],
  ['diferencia de identidad', e => { e.diferencias_identidad = 1; }],
  ['vencimiento alterado', e => { e.vencimientos_referencia[0].capital += 0.01; }],
  ['oportunidad alterada', e => { e.oportunidades_referencia[0].personas++; }],
  ['diferencia NUMERIC que JSON podría redondear', e => { e.meses[0].diferencias_capital_publicado_exactas = 2; }],
  ['propietario distinto al ejecutor', e => { e.custodia.propietario_f7 = 'otro'; }],
];
for (const [nombre, mutar] of casos) {
  const e = structuredClone(original); mutar(e);
  assert.throws(() => verificarLectura(e), { name: 'AssertionError' }, nombre);
  console.log('PASS: se rechaza ' + nombre);
}
const diferente = structuredClone(original);
diferente.meses[0].conversion_publicada.total.numerador += 0.15;
assert.equal(verificarLectura(diferente).estado, 'DIFERENCIAS_PENDIENTES');
console.log('PASS: diferencia de conversión oficial impide declarar paridad');
const decimal = structuredClone(original);
decimal.meses[0].conversion_oficial_exacta.numerador = false;
assert.equal(verificarLectura(decimal).estado, 'DIFERENCIAS_PENDIENTES');
console.log('PASS: desigualdad NUMERIC bloquea paridad aunque Number coincida');
const post = structuredClone(original.custodia);
assert.equal(verificarPostflight(original, post).estado, 'CUSTODIA_PASS');
for (const campo of ['fotos_selladas', 'funciones', 'banderas']) {
  const cambio = structuredClone(post);
  if (campo === 'fotos_selladas') cambio[campo][0].huella_filas = 'alterada';
  else cambio[campo][Object.keys(cambio[campo])[0]] = 'alterado';
  assert.throws(() => verificarPostflight(original, cambio), { name: 'AssertionError' });
  console.log('PASS: postflight rechaza cambio en ' + campo);
}
const temporal = await mkdtemp(join(tmpdir(), 'avancecorp-g6-test-'));
try {
  const entrada = join(temporal, 'invalida.json');
  const salida = join(temporal, 'resultado.json');
  await writeFile(entrada, '{');
  await writeFile(salida, '{"estado":"PARIDAD_TECNICA_PASS"}');
  await chmod(salida, 0o644);
  assert.throws(() => execFileSync(process.execPath,
    [new URL('./verificar-lectura.mjs', import.meta.url).pathname, entrada, salida],
    { stdio: 'pipe' }), error => error.status === 1);
  assert.equal(JSON.parse(await readFile(salida, 'utf8')).estado, 'FAIL');
  assert.equal((await stat(salida)).mode & 0o777, 0o600);
  console.log('PASS: entrada corrupta reemplaza PASS anterior por FAIL privado');
} finally {
  await rm(temporal, { recursive: true, force: true });
}
assert.equal(verificarLectura(original).estado, 'PARIDAD_TECNICA_PASS');
console.log('PASS: captura original conservada; ' + (casos.length + 6) + ' controles negativos');
