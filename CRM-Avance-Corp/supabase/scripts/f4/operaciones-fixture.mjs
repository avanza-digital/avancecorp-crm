// Datos económicos ficticios. El cronograma replica las condiciones elegidas
// para el ensayo: interés simple mensual, día 1 o 15, doce meses y retorno +7.
//
// `numero` (OPCIONAL; fase 4 · bloque 2.3, 20261009210100): número de contrato del alta. Desde esa migración el
// servidor exige a todo NO exento (D-17) la serie 2024-01-, 2025-01- o 2026-01- seguida de 6 dígitos: quien da de alta
// como no exento lo pasa. Solo si viene (ni undefined ni null) el contrato lleva `numero_contrato`, y va al FINAL del
// objeto; sin él, el resultado es exactamente el de antes, clave por clave y en el mismo orden.
import assert from 'node:assert/strict';

export function contratoPrueba(clienteId, vendedorId, {
  categoria = 'nuevo', inicio = '2026-08-01', capital = 1000, moneda = 'PEN', numero,
} = {}) {
  const fecha = new Date(`${inicio}T12:00:00Z`);
  assert([1, 2, 15].includes(fecha.getUTCDate()), 'Fixture: día sin ajuste de fin de mes');
  const fin = new Date(fecha);
  fin.setUTCFullYear(fin.getUTCFullYear() + 1);
  const iso = d => d.toISOString().slice(0, 10);
  const cronograma = Array.from({ length: 12 }, (_, i) => {
    const cuota = new Date(fecha);
    cuota.setUTCMonth(cuota.getUTCMonth() + i + 1);
    return { numero_cuota: i + 1, fecha_programada: iso(cuota),
      monto_programado: Math.round(capital * 0.15 / 12 * 100) / 100, tipo: 'cuota' };
  });
  const retorno = new Date(fin);
  retorno.setUTCDate(retorno.getUTCDate() + 7);
  cronograma.push({ numero_cuota: 13, fecha_programada: iso(retorno),
    monto_programado: capital, tipo: 'retorno' });
  return {
    contrato: { cliente_id: clienteId, analista_cierre_id: vendedorId,
      categoria, capital, moneda, tasa_anual: 15, modalidad: 'mensual',
      tipo_interes: 'simple', fecha_inicio: inicio, fecha_vencimiento: iso(fin),
      ...(numero === undefined || numero === null ? {} : { numero_contrato: numero }) },
    cronograma,
    cuenta: { tipo: 'nueva', banco: 'BANCO FICTICIO F4', tipo_cuenta: 'ahorros',
      numero_cuenta: `F4-${moneda}-001`, cci: moneda === 'PEN' ? '99999999999999999991' : '99999999999999999992',
      titular_distinto: false },
  };
}
