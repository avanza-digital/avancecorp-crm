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

// ── LOS MUTANTES DE LA CONCILIACIÓN (foto v2, 22/09/2026) ───────────────────
//
// Los de arriba se escribieron cuando el gate exigía que los cuatro caminos
// fuesen IGUALES. Esa regla era correcta mientras no existiera ninguna deuda
// por cierres anulados, y DEJA DE SERLO en cuanto exista: pondría en rojo
// justo el trabajo bien hecho. Lo reprodujo Codex el 22/09.
//
// 🔑 Éstos mueven NÚMEROS DE VERDAD. El mutante que proponía el plan anterior
// —forzar `es_mes_calendario` a false— se ejecutó y salió `sin_cambios: true`:
// ni el gate ni la alarma leían esa clave. Un mutante que no mueve nada no
// prueba nada.

/** Una foto v2 con deuda: el núcleo dice el bruto y los publicados el neto. */
const conDeuda = ({ bruto = 50, deuda = 4, topados = 0, aplicada = null } = {}) => {
  const f = clon();
  const neto = bruto - (aplicada ?? deuda);
  f.version = 2;
  f.conciliacion = {
    bruto_numerador: bruto,
    neto_numerador: neto,
    deuda_pendiente: deuda,
    deuda_aplicada: aplicada ?? deuda,
    vendedores_con_deuda: deuda > 0 ? 1 : 0,
    vendedores_topados: topados,
  };
  const div = f.caminos.nucleo_directo.divisor;
  const pct = (n) => Math.round((10000 * n) / div) / 100;
  f.caminos.nucleo_directo = { divisor: div, numerador: bruto, pct: pct(bruto) };
  for (const n of ['mensual', 'rango', 'distribucion']) {
    f.caminos[n] = { ...f.caminos[n], divisor: div, numerador: neto, pct: pct(neto) };
  }
  return f;
};

test('v2 SANO: el núcleo sirve el bruto y los publicados el neto → ni conciliación ni caminos se quejan', () => {
  // El fixture mueve los TOTALES pero no las filas del desglose, así que las
  // reglas 3 y 4 se quejan con razón. Lo que este test afirma es lo suyo: que
  // servir bruto arriba y neto abajo es CORRECTO y no lo delata nadie.
  const r = comprobarCoherencia(conDeuda({ bruto: 50, deuda: 4 }));
  const suyas = reglas(r).filter((x) => x === 'conciliacion' || x === 'cuatro_caminos');
  assert.deepEqual(suyas, [], `no debería quejarse: ${JSON.stringify(r.fallos)}`);
});

test('MUTANTE: una pantalla sigue sirviendo el BRUTO mientras las otras el neto → cuatro_caminos', () => {
  const f = conDeuda({ bruto: 50, deuda: 4 });
  const div = f.caminos.nucleo_directo.divisor;
  f.caminos.rango = { divisor: div, numerador: 50, pct: Math.round((10000 * 50) / div) / 100 };
  const r = comprobarCoherencia(f);
  assert.equal(r.ok, false);
  assert.ok(reglas(r).includes('cuatro_caminos'));
});

test('MUTANTE: la deuda aplicada no cuadra con bruto − neto → conciliacion', () => {
  const f = conDeuda({ bruto: 50, deuda: 4 });
  f.conciliacion.deuda_aplicada = 1; // pero bruto − neto sigue siendo 4
  const r = comprobarCoherencia(f);
  assert.equal(r.ok, false);
  assert.ok(reglas(r).includes('conciliacion'));
});

test('MUTANTE: se aplica MÁS deuda de la que hay pendiente → conciliacion', () => {
  const f = conDeuda({ bruto: 50, deuda: 2, aplicada: 6 });
  const r = comprobarCoherencia(f);
  assert.equal(r.ok, false);
  assert.ok(reglas(r).includes('conciliacion'));
});

test('MUTANTE: el bruto conciliado mira otra población que el núcleo → conciliacion', () => {
  const f = conDeuda({ bruto: 50, deuda: 4 });
  f.conciliacion.bruto_numerador = 49; // el núcleo sigue diciendo 50
  const r = comprobarCoherencia(f);
  assert.equal(r.ok, false);
  assert.ok(reglas(r).includes('conciliacion'));
  assert.match(r.fallos.find((x) => x.regla === 'conciliacion').detalle, /otra población/);
});

test('DEUDA MAYOR QUE EL BRUTO: con alguien topado, aplicada < pendiente y es VÁLIDO', () => {
  // El tope `greatest(num − pend, 0)` impide aplicar más deuda que bruto tiene
  // esa persona. Entonces aplicada < pendiente SIN que nada esté roto.
  const f = conDeuda({ bruto: 50, deuda: 9, aplicada: 5, topados: 1 });
  const r = comprobarCoherencia(f);
  assert.ok(!reglas(r).includes('conciliacion'),
    `la conciliación no debería quejarse con gente topada: ${JSON.stringify(r.fallos)}`);
});

test('MUTANTE: sin nadie topado, aplicada < pendiente es un agujero → conciliacion', () => {
  const f = conDeuda({ bruto: 50, deuda: 9, aplicada: 5, topados: 0 });
  const r = comprobarCoherencia(f);
  assert.equal(r.ok, false);
  assert.ok(reglas(r).includes('conciliacion'));
});

test('la foto v1 histórica se juzga con la regla de su tiempo, no con la conciliación', () => {
  const r = comprobarCoherencia(real);
  assert.ok(!reglas(r).includes('conciliacion'));
  assert.deepEqual(r.fallos, []);
});
