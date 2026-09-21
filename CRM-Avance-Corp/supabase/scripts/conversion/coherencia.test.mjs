// Cada regla del gate tiene su MUTANTE: una foto rota a propósito que la regla
// tiene que cazar. Si un mutante sobrevive, esa regla no protege nada.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { comprobarCoherencia, compararFotos } from './coherencia.mjs';

const real = JSON.parse(await readFile(new URL('./foto-2026-09-21.json', import.meta.url), 'utf8'));
const clon = () => structuredClone(real);
const reglas = (r) => [...new Set(r.fallos.map((f) => f.regla))];

test('la foto real de producción del 21/09 está en VERDE', () => {
  const r = comprobarCoherencia(real);
  assert.deepEqual(r.fallos, []);
  assert.ok(r.comprobadas >= 20);
});

test('MUTANTE: el rango publica otro porcentaje que el núcleo → cuatro_caminos', () => {
  const f = clon(); f.caminos.rango.pct = 3.86; f.caminos.rango.numerador = 45.2;
  const r = comprobarCoherencia(f);
  assert.equal(r.ok, false);
  assert.ok(reglas(r).includes('cuatro_caminos'));
  assert.match(r.fallos[0].detalle, /rango/);
});

test('MUTANTE: la distribución ignora la foto y da otro divisor → cuatro_caminos', () => {
  const f = clon(); f.caminos.distribucion.divisor = 1113;
  assert.ok(reglas(comprobarCoherencia(f)).includes('cuatro_caminos'));
});

test('MUTANTE: falta un camino entero → cuatro_caminos', () => {
  const f = clon(); delete f.caminos.mensual;
  assert.ok(reglas(comprobarCoherencia(f)).includes('cuatro_caminos'));
});

test('MUTANTE: el servidor publica un pct que no es su división → pct_es_su_division', () => {
  const f = clon();
  for (const n of Object.keys(f.caminos)) f.caminos[n].pct = 4.5;
  const r = comprobarCoherencia(f);
  assert.ok(reglas(r).includes('pct_es_su_division'));
  assert.ok(!reglas(r).includes('cuatro_caminos'), 'los cuatro siguen coincidiendo entre sí');
});

test('MUTANTE: una fila del desglose desaparece → desglose_suma_el_total', () => {
  const f = clon(); f.desglose = f.desglose.filter((x) => x.origen !== 'landing');
  assert.ok(reglas(comprobarCoherencia(f)).includes('desglose_suma_el_total'));
});

test('MUTANTE: un analista pesa en el total sin fila ni declaración → las_filas_dan_el_total', () => {
  const f = clon(); f.analistas = f.analistas.filter((a) => a.divisor !== 89);
  const r = comprobarCoherencia(f);
  assert.ok(reglas(r).includes('las_filas_dan_el_total'));
});

test('lo declarado fuera del roster SÍ cuadra: la foto real tiene 2 puntos fuera y pasa', () => {
  assert.equal(real.cobertura.fuera_de_roster.numerador, 2);
  assert.equal(comprobarCoherencia(real).ok, true);
});

test('MUTANTE: la cobertura deja de declarar lo de fuera → las_filas_dan_el_total', () => {
  const f = clon(); f.cobertura.fuera_de_roster.numerador = 0;
  assert.ok(reglas(comprobarCoherencia(f)).includes('las_filas_dan_el_total'));
});

test('MUTANTE: un convertido sin fila en el libro → ledger_sin_huerfanos', () => {
  const f = clon(); f.ledger.convertidos_sin_ledger = 1;
  assert.ok(reglas(comprobarCoherencia(f)).includes('ledger_sin_huerfanos'));
});

test('MUTANTE: un analista con divisor 0 publica 0 % → sin_divisor_no_hay_pct', () => {
  const f = clon(); f.analistas.find((a) => a.divisor === 0).pct = 0;
  assert.ok(reglas(comprobarCoherencia(f)).includes('sin_divisor_no_hay_pct'));
});

test('una foto sin caminos no pasa en silencio', () => {
  const r = comprobarCoherencia({});
  assert.equal(r.ok, false);
  assert.equal(r.fallos[0].regla, 'forma');
});

test('diff: la misma foto dos veces no tiene cambios', () => {
  assert.equal(compararFotos(real, clon()).sin_cambios, true);
});

test('diff: un cierre nuevo se ve como movimiento del numerador y de UNA fila', () => {
  const d = clon();
  for (const n of Object.keys(d.caminos)) { d.caminos[n].numerador = 46.35; d.caminos[n].pct = 3.96; }
  d.analistas[1].numerador = 6.3; d.analistas[1].pct = 7.08;
  const r = compararFotos(real, d);
  assert.equal(r.sin_cambios, false);
  assert.ok(r.cambios.some((c) => c.donde === 'caminos.mensual.numerador'));
  assert.ok(r.cambios.some((c) => c.donde.startsWith('analista 1de5eba1')));
  assert.equal(r.cambios.filter((c) => c.donde.startsWith('analista')).length, 2);
});

test('diff: un analista que desaparece se nombra', () => {
  const d = clon(); d.analistas.pop();
  assert.ok(compararFotos(real, d).cambios.some((c) => c.despues === 'desapareció'));
});
