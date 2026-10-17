import { deepStrictEqual, equal, rejects, throws } from "node:assert/strict";
import {
  obtenerEvidenciaTipoCambio,
  obtenerLoteEvidenciasTipoCambio,
  prepararEvidenciaTipoCambio,
  prepararEvidenciaTipoCambioLegado,
} from "./consolidacion.ts";

const HUELLA = "a".repeat(64);
const dias = [
  "23.Set.26",
  "24.Set.26",
  "25.Set.26",
  "28.Set.26",
  "29.Set.26",
  "30.Set.26",
  "01.Oct.26",
  "02.Oct.26",
];
const serie = (fechas = dias, valor = "3.400") => ({
  periods: fechas.map((name) => ({ name, values: [valor] })),
});
const preparar = (c = serie(), v = serie()) =>
  prepararEvidenciaTipoCambio("2026-10-02", "2026-10-05", c, v, HUELLA);

Deno.test("consolida siete pares exactos y conserva decimales de la fuente", () => {
  const r = preparar();
  equal(r.estado, "consolidado");
  if (r.estado !== "consolidado") throw new Error("Se esperaba consolidación");
  equal(r.evidencia.pares.length, 7);
  deepStrictEqual(r.evidencia.pares[6], {
    fecha: "2026-10-02",
    compra: "3.400",
    venta: "3.400",
  });
  equal(r.evidencia.pares[0].fecha, "2026-09-24");
});

Deno.test("publicar una cotización posterior no revaloriza la venta", () => {
  const antes = preparar();
  const nuevas = serie([...dias, "05.Oct.26"]);
  nuevas.periods[8].values = ["3.100"];
  const despues = preparar(nuevas, nuevas);
  if (antes.estado !== "consolidado" || despues.estado !== "consolidado") {
    throw new Error("Falta evidencia");
  }
  deepStrictEqual(antes.evidencia.pares, despues.evidencia.pares);
});

Deno.test("una compra sin venta del corte no puede congelarse", () => {
  deepStrictEqual(preparar(serie(), serie(dias.slice(0, -1))), {
    estado: "pendiente",
    motivo: "publicacion_pendiente",
  });
});

Deno.test("un par incompleto entre los siete más recientes no se reemplaza por otro viejo", () => {
  deepStrictEqual(
    preparar(serie(), serie(dias.filter((d) => d !== "30.Set.26"))),
    { estado: "pendiente", motivo: "serie_parcial" },
  );
});

Deno.test("fin de semana espera publicación posterior, cuyos valores quedan fuera del corte", () => {
  equal(
    prepararEvidenciaTipoCambio(
      "2026-10-03",
      "2026-10-05",
      serie(),
      serie(),
      HUELLA,
    ).estado,
    "pendiente",
  );
  const conLunes = serie([...dias, "05.Oct.26"]);
  const r = prepararEvidenciaTipoCambio(
    "2026-10-03",
    "2026-10-05",
    conLunes,
    conLunes,
    HUELLA,
  );
  if (r.estado !== "consolidado") throw new Error("No consolidó el sábado");
  equal(r.evidencia.publicacion_confirmada, "2026-10-05");
  equal(r.evidencia.pares.at(-1)?.fecha, "2026-10-02");
});

Deno.test("no acepta publicación del futuro como prueba de consolidación", () => {
  const conFuturo = serie([...dias.slice(0, -1), "05.Oct.26"]);
  equal(
    prepararEvidenciaTipoCambio(
      "2026-10-02",
      "2026-10-02",
      conFuturo,
      conFuturo,
      HUELLA,
    ).estado,
    "pendiente",
  );
});

Deno.test("con menos de siete pares informa historia insuficiente", () => {
  deepStrictEqual(preparar(serie(dias.slice(-6)), serie(dias.slice(-6))), {
    estado: "pendiente",
    motivo: "historia_insuficiente",
  });
});

Deno.test("rechaza período ilegible, día imposible y cotizaciones contradictorias", () => {
  throws(() => preparar(serie(["basura"])), /período no reconocido/);
  throws(() => preparar(serie(["31.Sep.26"])), /fuera del calendario/);
  const duplicada = serie();
  duplicada.periods.push({ name: "02.Oct.26", values: ["3.100"] });
  throws(() => preparar(duplicada), /contradictorias/);
});

Deno.test("n.d. es ausencia y un valor mal formado es fallo, nunca cero", () => {
  equal(preparar(serie(dias, "n.d.")).estado, "pendiente");
  throws(() => preparar(serie(dias, "0")), /decimal inválida/);
  throws(() => preparar(serie(dias, "basura")), /decimal inválida/);
});

Deno.test("rechaza fechas futuras o inválidas antes de usar red", async () => {
  let llamadas = 0;
  const deps = {
    ahora: () => Date.parse("2026-10-05T12:00:00Z"),
    fetch: (() => {
      llamadas++;
      throw new Error("red");
    }) as typeof fetch,
  };
  await rejects(() => obtenerEvidenciaTipoCambio("2026-10-06", deps), /futura/);
  await rejects(
    () => obtenerEvidenciaTipoCambio("2026-02-30", deps),
    /inválida/,
  );
  equal(llamadas, 0);
});

Deno.test("amplía la ventana para conseguir siete pares completos", async () => {
  const urls: string[] = [];
  const r = await obtenerEvidenciaTipoCambio("2026-10-02", {
    ahora: () => Date.parse("2026-10-05T12:00:00Z"),
    fetch: ((url: string | URL | Request) => {
      urls.push(String(url));
      return Promise.resolve(
        Response.json(serie(urls.length <= 2 ? dias.slice(-6) : dias)),
      );
    }) as typeof fetch,
  });
  equal(r.estado, "consolidado");
  equal(urls.length, 4);
  equal(urls.some((u) => u.includes("2026-08-31")), true);
});

Deno.test("un error HTTP del proveedor no fabrica una tasa", async () => {
  await rejects(() =>
    obtenerEvidenciaTipoCambio("2026-10-02", {
      ahora: () => Date.parse("2026-10-05T12:00:00Z"),
      fetch: (() =>
        Promise.resolve(
          new Response("caído", { status: 503 }),
        )) as typeof fetch,
    }), /503/);
});

Deno.test("un lote de fechas comparte exactamente dos descargas", async () => {
  let llamadas = 0;
  const r = await obtenerLoteEvidenciasTipoCambio([
    "2026-10-01",
    "2026-10-02",
    "2026-10-01",
  ], {
    ahora: () => Date.parse("2026-10-05T12:00:00Z"),
    fetch: (() => {
      llamadas++;
      return Promise.resolve(Response.json(serie()));
    }) as typeof fetch,
  });
  equal(llamadas, 2);
  equal(r.porCorte.size, 2);
  equal(r.porCorte.get("2026-10-02")?.estado, "consolidado");
});

Deno.test("HTML del proveedor con HTTP 200 es un fallo explícito", async () => {
  await rejects(() =>
    obtenerLoteEvidenciasTipoCambio(["2026-10-02"], {
      ahora: () => Date.parse("2026-10-05T12:00:00Z"),
      fetch: (() =>
        Promise.resolve(new Response("<!DOCTYPE html>"))) as typeof fetch,
    }), /respuesta no JSON/);
});

Deno.test("reconstrucción legada conserva ventana de 16 días y lado único publicado", () => {
  const r = prepararEvidenciaTipoCambioLegado(
    "2026-09-30",
    "2026-10-05",
    serie(["01.Set.26", "29.Set.26", "30.Set.26"], "3.400"),
    serie(["30.Set.26"], "3.600"),
    HUELLA,
  );
  if (r.estado !== "consolidado") {
    throw new Error("Falta reconstrucción legada");
  }
  equal(r.evidencia.politica, "sbs_punto_medio_hasta7_legado_v1");
  deepStrictEqual(r.evidencia.pares, [
    { fecha: "2026-09-29", compra: "3.400", venta: null },
    { fecha: "2026-09-30", compra: "3.400", venta: "3.600" },
  ]);
  throws(
    () =>
      prepararEvidenciaTipoCambioLegado(
        "2026-10-02",
        "2026-10-05",
        serie(),
        serie(),
        HUELLA,
      ),
    /anterior a octubre/,
  );
});
