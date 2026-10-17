import {
  type EvidenciaTipoCambio,
  POLITICA_TC_LEGADA,
  POLITICA_TC_VENTA,
} from "../../functions/crm-tipo-cambio/consolidacion.ts";

/** La imputación no cambia la fecha con que una venta se valora. */
export function corteDeVenta(fecha: string | null) {
  if (fecha == null) return null;
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(fecha) ||
    !Number.isFinite(Date.parse(fecha)) ||
    new Date(fecha).toISOString().slice(0, 10) !== fecha
  ) throw new Error("Fecha comercial inválida");
  return fecha >= "2026-10-01" ? { fecha, politica: POLITICA_TC_VENTA } : {
    fecha: new Date(Date.UTC(
      Number(fecha.slice(0, 4)),
      Number(fecha.slice(5, 7)),
      0,
    )).toISOString().slice(0, 10),
    politica: POLITICA_TC_LEGADA,
  };
}

/** Solo simulación: el oráculo monetario definitivo es Postgres numeric. */
export function tasaOrientativa(evidencia: EvidenciaTipoCambio): number {
  if (!evidencia.pares.length) throw new Error("Falta evidencia de cotización");
  const puntos = evidencia.pares.map(({ compra, venta }) => {
    if (compra == null && venta == null) throw new Error("Par sin cotización");
    return compra != null && venta != null
      ? (Number(compra) + Number(venta)) / 2
      : Number(compra ?? venta);
  });
  return Math.round(
    puntos.reduce((s, p) => s + p, 0) / puntos.length * 10000,
  ) / 10000;
}
