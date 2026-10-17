import { deepStrictEqual, equal, throws } from "node:assert/strict";
import {
  POLITICA_TC_LEGADA,
  POLITICA_TC_VENTA,
  prepararEvidenciaTipoCambioLegado,
} from "../../functions/crm-tipo-cambio/consolidacion.ts";
import { corteDeVenta, tasaOrientativa } from "./simulacion.ts";

Deno.test("venta comercial de septiembre imputada en octubre usa fin del mes original", () => {
  deepStrictEqual(corteDeVenta("2026-09-15"), {
    fecha: "2026-09-30",
    politica: POLITICA_TC_LEGADA,
  });
  deepStrictEqual(corteDeVenta("2026-10-02"), {
    fecha: "2026-10-02",
    politica: POLITICA_TC_VENTA,
  });
  equal(corteDeVenta(null), null);
  throws(() => corteDeVenta("2026-09-31"));
});

Deno.test("la simulación legada admite menos de siete observaciones y un solo lado sin dividir por siete", () => {
  const evidencia = prepararEvidenciaTipoCambioLegado(
    "2026-09-30",
    "2026-10-02",
    {
      periods: [{ name: "30.Set.26", values: ["3.4"] }, {
        name: "02.Oct.26",
        values: ["3.1"],
      }],
    },
    {
      periods: [{ name: "29.Set.26", values: ["3.6"] }, {
        name: "02.Oct.26",
        values: ["3.1"],
      }],
    },
    "a".repeat(64),
  );
  if (evidencia.estado !== "consolidado") throw new Error("No consolidó");
  equal(evidencia.evidencia.pares.length, 2);
  equal(tasaOrientativa(evidencia.evidencia), 3.5);
});
