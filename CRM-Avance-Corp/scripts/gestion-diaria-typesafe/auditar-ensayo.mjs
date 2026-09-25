// Recalcula la evidencia conservada; no usa red, claves ni datos del CRM.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const origen = '../../docs/gestion-diaria/typesafe/ensayo-aislado-2026-09-21.json';
const contenido = readFileSync(new URL(origen, import.meta.url));
const ensayo = JSON.parse(contenido);
const clases = ['compatible', 'posible_contradiccion', 'informacion_insuficiente'];
const resultados = ensayo.resultados;
assert.equal(resultados.length, ensayo.total);
assert.equal(new Set(resultados.map((r) => r.id)).size, resultados.length);
assert.ok(resultados.every((r) => r.valida && clases.includes(r.clase) && clases.includes(r.esperado)));
assert.equal(ensayo.revision_humana, false);
assert.equal(ensayo.datos_CRM_enviados, false);

const contar = (predicado) => resultados.filter(predicado).length;
const positiva = (clase) => clase === 'posible_contradiccion';
const verdaderas = contar((r) => positiva(r.clase) && positiva(r.esperado));
const falsas = contar((r) => positiva(r.clase) && !positiva(r.esperado));
const omitidas = contar((r) => !positiva(r.clase) && positiva(r.esperado));
const negativas = contar((r) => !positiva(r.esperado));
function proporcion(aciertos, total) {
  if (total === 0) return { numerador: aciertos, denominador: total, valor: null, wilson_95: null };
  const z = 1.959963984540054;
  const p = aciertos / total;
  const divisor = 1 + z * z / total;
  const centro = (p + z * z / (2 * total)) / divisor;
  const margen = z * Math.sqrt(p * (1 - p) / total + z * z / (4 * total * total)) / divisor;
  return { numerador: aciertos, denominador: total, valor: p,
    wilson_95: [Math.max(0, centro - margen), Math.min(1, centro + margen)] };
}
const latencias = resultados.map((r) => r.latencia_ms).sort((a, b) => a - b);
assert.ok(latencias.every((n) => Number.isFinite(n) && n >= 0));
const tokensEntrada = resultados.reduce((s, r) => s + r.uso.input_tokens, 0);
assert.equal(tokensEntrada, ensayo.uso.input_tokens);
assert.equal(falsas, ensayo.falsas_alertas);
assert.equal(omitidas, ensayo.contradicciones_omitidas);
const tarifa = 0.042;
console.log(JSON.stringify({
  fecha_evaluacion: '2026-09-24',
  origen: 'ensayo-aislado-2026-09-21.json',
  origen_sha256: createHash('sha256').update(contenido).digest('hex'),
  fecha_ensayo: ensayo.fecha_utc,
  modelo: ensayo.modelo,
  alcance: 'Reanálisis sin nuevas inferencias; 20 casos sintéticos, sin etiquetas humanas independientes ni estratificación por equipo.',
  resultados_validos: resultados.length,
  coincidencia: proporcion(contar((r) => r.clase === r.esperado), resultados.length),
  precision_alerta: proporcion(verdaderas, verdaderas + falsas),
  sensibilidad: proporcion(verdaderas, verdaderas + omitidas),
  tasa_falsas_alertas: proporcion(falsas, negativas),
  contradicciones_omitidas: omitidas,
  matriz: Object.fromEntries(clases.map((esperado) => [esperado,
    Object.fromEntries(clases.map((clase) => [clase, contar((r) => r.esperado === esperado && r.clase === clase)]))])),
  discrepancias: resultados.filter((r) => r.clase !== r.esperado).map(({ id, esperado, clase, confianza }) => ({ id, esperado, clase, confianza })),
  latencia_ms: { metodo: 'Rango más próximo: ordenadas[ceil(p × n) − 1]',
    p50: latencias[Math.ceil(0.50 * latencias.length) - 1],
    p95: latencias[Math.ceil(0.95 * latencias.length) - 1],
    maximo: latencias.at(-1), lote: ensayo.latencia_ms },
  coste_referencial_usd: { entrada_por_millon: tarifa, salida_por_millon: 0,
    fuente: 'https://docs.typesafe.ai/models', fecha_tarifa_consultada: '2026-09-24',
    tokens_entrada: tokensEntrada, tokens_salida: ensayo.uso.output_tokens,
    total: tokensEntrada * tarifa / 1_000_000,
    por_caso: tokensEntrada * tarifa / 1_000_000 / resultados.length,
    alcance: 'Estimación con tarifa consultada; no acredita factura ni precio histórico. Este reanálisis no consume API.' },
  decision: 'NO_ACTIVAR',
  motivos: [
    'No hay referencia real independiente por equipo; el ensayo técnico no prueba utilidad comercial.',
    'Una falsa alerta entre 11 negativos (9,09 %) supera el criterio provisional de 5 %; muestra insuficiente para calibración.',
    'No está acreditada la rotación de la credencial previamente expuesta ni resueltas conservación y condiciones de transferencia de notas reales.',
  ],
  condiciones_para_reabrir: 'Referencia válida por equipo, credencial vigente segura, minimización/conservación resueltas y evaluación independiente sin ajustar umbrales sobre el conjunto de validación.',
  habilita_produccion: false,
}, null, 2));
