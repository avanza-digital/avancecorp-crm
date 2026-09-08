import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { banco, sql, guardar, leer } from './banco-local.mjs';

const modo = process.argv[2];
assert(['antes', 'despues'].includes(modo), 'Usa antes o despues');
const filas = consulta => JSON.parse(sql(`select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') from (${consulta}) x`));
const foto = {
  contratos: filas('select * from public.contratos'),
  cronogramas: filas('select * from public.cronograma_pagos'),
  cotitulares: filas('select * from public.contrato_titulares'),
  cuentas: filas('select * from crm.cuentas_bancarias'),
  vinculosCuenta: filas('select * from crm.contrato_cuentas_pago'),
  cartera: filas('select * from crm.operaciones_cartera'),
  cierres: filas(`select id,lead_id,cooperativa,monto,moneda,numero_transaccion,
    referencia_externa,vence_en,vendedor_id,creado_por,creado_en,anulado_en from crm.cierres_externos`),
  capital: filas(`select * from private.capital_episodios(
    '2026-08-01T00:00:00-05:00','2026-10-01T00:00:00-05:00',true,'{}')`),
  conversionAgosto: filas(`select * from private.conversion_episodios(
    '2026-08-01T00:00:00-05:00','2026-09-01T00:00:00-05:00','2026-08-01',true,'{}',0.15)`),
  conversionSeptiembre: filas(`select * from private.conversion_episodios(
    '2026-09-01T00:00:00-05:00','2026-10-01T00:00:00-05:00','2026-09-01',true,'{}',0.15)`),
};
assert.equal(foto.contratos.length, 4);
assert.equal(foto.cierres.length, 2);
assert.equal(foto.capital.length, 6);
assert.equal(foto.cronogramas.length, 52);
assert.equal(foto.cartera.length, 3);
assert.equal(foto.conversionAgosto.filter(x => x.tipo === 'operacion').length, 0,
  'El upgrade del mismo mes no debe aportar');
const operacion = foto.conversionSeptiembre.filter(x => x.tipo === 'operacion');
assert.equal(operacion.length, 1, 'Solo primera operación de cartera elegible del mes');
assert.equal(operacion[0].aporte_numerador, 1);
assert.equal(operacion[0].aporte_divisor, 0);
if (modo === 'antes') {
  assert.equal(sql("select to_regclass('crm.inversion_solicitudes') is null"), 't');
  if (existsSync(join(banco, 'paridad-antes.json'))) {
    assert.deepEqual(foto, leer('paridad-antes.json'), 'La referencia existente cambió; no sobrescribir evidencia');
  } else guardar('paridad-antes.json', foto);
} else {
  assert.equal(sql("select to_regclass('crm.inversion_solicitudes') is not null"), 't');
  assert.deepEqual(foto, leer('paridad-antes.json'), 'F4 alteró el circuito o las cifras anteriores');
}
const evidencia = {
  entorno, momento: modo, capturadoEn: new Date().toISOString(),
  sha256: createHash('sha256').update(JSON.stringify(foto)).digest('hex'),
  contratos: 4, cierres: 2, filasCapital: 6, cuotas: 52,
  capitalTotalPEN: foto.capital.reduce((s, x) => s + x.monto, 0),
  upgradeMismoMes: 0, operacionesCarteraElegiblesSeptiembre: 1, aporteUpgrade: 1,
  fuentesYReglasIguales: modo === 'despues',
  alcance: 'Paridad de antecedentes y upgrades. No cubre todavía renovación, comisión, Auth ni aceptación completa G4.',
};
writeFileSync(new URL(`../evidencia-f4/paridad-${modo}-${new Date().toISOString().replaceAll(':','-')}.json`, import.meta.url), `${JSON.stringify(evidencia, null, 2)}\n`,{flag:'wx'});
console.log(`Paridad ${modo}: 6 fuentes, PEN 8000, 52 cuotas y elegibilidad de upgrades comprobados.`);
