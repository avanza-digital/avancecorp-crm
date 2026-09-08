// Datos económicos ficticios. El cronograma replica las condiciones elegidas
// para el ensayo: interés simple mensual, día 1 o 15, doce meses y retorno +7.
import assert from 'node:assert/strict';

export function contratoPrueba(clienteId, vendedorId, {
  categoria = 'nuevo', inicio = '2026-08-01', capital = 1000, moneda = 'PEN',
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
      tipo_interes: 'simple', fecha_inicio: inicio, fecha_vencimiento: iso(fin) },
    cronograma,
    cuenta: { tipo: 'nueva', banco: 'BANCO FICTICIO F4', tipo_cuenta: 'ahorros',
      numero_cuenta: `F4-${moneda}-001`, cci: moneda === 'PEN' ? '99999999999999999991' : '99999999999999999992',
      titular_distinto: false },
  };
}
