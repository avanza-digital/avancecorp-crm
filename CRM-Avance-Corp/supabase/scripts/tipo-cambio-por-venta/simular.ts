// Solo lectura del BCRP y archivos locales. No tiene cliente ni clave Supabase.
import {
  type EvidenciaTipoCambio,
  obtenerLoteEvidenciasTipoCambio,
  prepararEvidenciaTipoCambioLegado,
} from "../../functions/crm-tipo-cambio/consolidacion.ts";
import { calcularTipoCambio } from "../../functions/crm-tipo-cambio/handler.ts";
import { corteDeVenta, tasaOrientativa } from "./simulacion.ts";

interface Hecho {
  fuente: "contrato" | "cierre_externo";
  fuente_id: string;
  fecha_comercial: string | null;
  fecha_imputacion: string;
  moneda: "PEN" | "USD";
  monto: number | string;
  categoria: string;
  analista_id: string | null;
  tiene_inversion: boolean;
}

const [entrada, salida] = Deno.args;
if (!entrada || !salida) {
  throw new Error("Uso: simular.ts inventario.json salida.json");
}
const raw = JSON.parse(await Deno.readTextFile(entrada));
const inventario =
  raw.rows?.find((r: Record<string, unknown>) => r.inventario)?.inventario ??
    raw.inventario ?? raw;
if (
  inventario.proyecto !== "dctqcbznekcyxhjujuci" ||
  inventario.periodo !== "2026-10-01" || !Array.isArray(inventario.operaciones)
) {
  throw new Error("El archivo no es el inventario de octubre esperado");
}
const hechos = inventario.operaciones as Hecho[];
const deps = { fetch, ahora: () => Date.now() };
const fechas = [
  ...new Set(
    hechos.filter((h) => h.moneda === "USD" && h.fecha_comercial != null)
      .map((h) => corteDeVenta(h.fecha_comercial)!.fecha),
  ),
].sort();
const tasas = new Map<string, EvidenciaTipoCambio>();
const pendientes: { fecha: string; motivo: string }[] = [];
const lote = fechas.length
  ? await obtenerLoteEvidenciasTipoCambio(fechas, deps)
  : null;
for (const fecha of fechas) {
  const r = fecha < "2026-10-01"
    ? prepararEvidenciaTipoCambioLegado(
      fecha,
      lote!.hasta_verificado,
      lote!.respuestas.compra,
      lote!.respuestas.venta,
      lote!.huella_respuestas,
    )
    : lote!.porCorte.get(fecha)!;
  if (r.estado === "consolidado") tasas.set(fecha, r.evidencia);
  else pendientes.push({ fecha, motivo: r.motivo });
  console.log(`${fecha}: ${r.estado}`);
}
const actual = await calcularTipoCambio(
  lote
    ? {
      ...deps,
      fetch: ((url: string | URL | Request) =>
        Promise.resolve(Response.json(
          String(url).includes("PD04639PD")
            ? lote.respuestas.compra
            : lote.respuestas.venta,
        ))) as typeof fetch,
    }
    : deps,
  new Date(Date.now() - 5 * 3600_000).toISOString().slice(0, 10),
);
// La comparación de presentación es orientativa. La valoración definitiva y
// sus redondeos se verifican en SQL numeric con los pares guardados.
const operaciones = hechos.map((h) => {
  const monto = Number(h.monto);
  if (!Number.isFinite(monto) || monto < 0) {
    throw new Error("Monto inválido en inventario");
  }
  const corte = corteDeVenta(h.fecha_comercial);
  const e = corte ? tasas.get(corte.fecha) : undefined;
  const tasa = corte == null
    ? null
    : h.moneda === "PEN"
    ? 1
    : e
    ? tasaOrientativa(e)
    : null;
  return {
    ...h,
    fecha_tc_propuesta: h.moneda === "USD" ? corte?.fecha ?? null : null,
    politica_tc_propuesta: h.moneda === "USD" ? corte?.politica ?? null : null,
    tasa_propuesta: tasa,
    equivalente_propuesto_orientativo: tasa == null
      ? null
      : Math.round(monto * tasa * 100) / 100,
    equivalente_actual_orientativo: h.moneda === "PEN"
      ? monto
      : Math.round(monto * actual.promedio * 100) / 100,
  };
});
const resultado = {
  generado_en: new Date().toISOString(),
  inventario_capturado_en: inventario.capturado_en,
  metodo:
    "Simulación de presentación; el oráculo monetario es Postgres numeric",
  tasa_actual: actual,
  evidencias: [...tasas.values()],
  pendientes,
  operaciones,
  controles: {
    operaciones: operaciones.length,
    usd: operaciones.filter((h) => h.moneda === "USD").length,
    sin_fecha: operaciones.filter((h) => !h.fecha_comercial).length,
    sin_inversion: operaciones.filter((h) => !h.tiene_inversion).length,
    ajustes_usd_pendientes: inventario.ajustes_usd.length,
    meses_cerrados: inventario.cierres,
    huella_fotos: inventario.huella_fotos,
  },
};
await Deno.writeTextFile(salida, JSON.stringify(resultado, null, 2), {
  mode: 0o600,
});
console.log(JSON.stringify(resultado.controles));
