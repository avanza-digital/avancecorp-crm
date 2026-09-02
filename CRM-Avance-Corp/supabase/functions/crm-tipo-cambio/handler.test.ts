import {
  calcularTipoCambio,
  crearHandlerTipoCambio,
  type DependenciasTipoCambio,
} from "./handler.ts";

function igual(actual: unknown, esperado: unknown, mensaje: string) {
  if (actual !== esperado) {
    throw new Error(
      `${mensaje}: esperado=${String(esperado)} actual=${String(actual)}`,
    );
  }
}

function assert(condicion: unknown, mensaje: string): asserts condicion {
  if (!condicion) throw new Error(mensaje);
}

type Periodo = { name: string; values: [string] };

function respuesta(periodos: Periodo[]): Response {
  return Response.json({ periods: periodos });
}

function periodo(name: string, valor: number): Periodo {
  return { name, values: [String(valor)] };
}

function request(fechaCorte?: string): Request {
  return new Request(
    "https://project.supabase.co/functions/v1/crm-tipo-cambio",
    {
      method: "POST",
      headers: {
        Origin: "https://crm.miavance.com",
        "Content-Type": "application/json",
      },
      body: fechaCorte === undefined
        ? undefined
        : JSON.stringify({ fecha_corte: fechaCorte }),
    },
  );
}

function dependencias(
  responder: (url: string) => Response,
  ahora = Date.parse("2026-09-02T17:00:00.000Z"),
): { deps: DependenciasTipoCambio; urls: string[] } {
  const urls: string[] = [];
  const fetchFake = ((input: RequestInfo | URL) => {
    const url = typeof input === "string"
      ? input
      : input instanceof URL
      ? input.toString()
      : input.url;
    urls.push(url);
    return Promise.resolve(responder(url));
  }) as typeof fetch;
  return { deps: { fetch: fetchFake, ahora: () => ahora }, urls };
}

const FECHAS_AGOSTO = [
  "18.Aug.26",
  "19.Aug.26",
  "20.Aug.26",
  "21.Aug.26",
  "24.Aug.26",
  "25.Aug.26",
  "26.Aug.26",
  "27.Aug.26",
  "28.Aug.26",
  "31.Aug.26",
];

Deno.test("calcula los últimos 7 días hábiles hasta el corte, no hasta hoy", async () => {
  const compra = FECHAS_AGOSTO
    .map((fecha, indice) => periodo(fecha, 3 + indice / 100))
    .concat(periodo("01.Sep.26", 9))
    .reverse();
  const venta = FECHAS_AGOSTO
    .map((fecha, indice) => periodo(fecha, 3 + indice / 100))
    .concat(periodo("01.Sep.26", 9));
  const f = dependencias((url) =>
    respuesta(url.includes("PD04639PD") ? compra : venta)
  );

  const resultado = await calcularTipoCambio(f.deps, "2026-08-31");

  igual(resultado.promedio, 3.06, "promedio de índices 3..9");
  igual(resultado.dias, 7, "cantidad de días");
  igual(resultado.desde, "21.Aug.26", "primer día del promedio");
  igual(resultado.hasta, "31.Aug.26", "último día del promedio");
  igual(resultado.fecha_corte, "2026-08-31", "corte declarado");
  igual(resultado.fuente, "SBS · prom. 7d", "fuente");
  igual(f.urls.length, 2, "dos series consultadas");
  assert(
    f.urls.every((url) => url.includes("/2026-08-15/2026-08-31/ing")),
    "ambas series terminan exactamente en el corte",
  );
});

Deno.test("el cache se reutiliza para el mismo corte y se separa entre meses", async () => {
  const f = dependencias((url) => {
    const agosto = url.includes("/2026-08-31/ing");
    return respuesta([
      periodo(agosto ? "31.Aug.26" : "01.Sep.26", agosto ? 3.5 : 3.6),
    ]);
  });
  const handler = crearHandlerTipoCambio(f.deps);

  const agosto1 = await handler(request("2026-08-31"));
  const agosto2 = await handler(request("2026-08-31"));
  const septiembre = await handler(request("2026-09-01"));

  igual(agosto1.status, 200, "primer corte");
  igual(agosto2.status, 200, "mismo corte cacheado");
  igual(septiembre.status, 200, "otro corte");
  igual(f.urls.length, 4, "dos fetches por cada corte único");
  igual((await agosto2.json()).fecha_corte, "2026-08-31", "cache agosto");
  igual(
    (await septiembre.json()).fecha_corte,
    "2026-09-01",
    "cache septiembre",
  );
});

Deno.test("sin fecha conserva el contrato previo y usa hoy en Lima", async () => {
  // 04:59 UTC todavía es 23:59 del 2 de septiembre en Lima.
  const f = dependencias(
    () => respuesta([periodo("02.Sep.26", 3.5)]),
    Date.parse("2026-09-03T04:59:00.000Z"),
  );
  const response = await crearHandlerTipoCambio(f.deps)(request());

  igual(response.status, 200, "status sin corte explícito");
  igual((await response.json()).fecha_corte, "2026-09-02", "hoy Lima");
  assert(
    f.urls.every((url) => url.includes("/2026-08-17/2026-09-02/ing")),
    "la consulta compatible usa hoy Lima",
  );
});

Deno.test("rechaza fechas futuras e inválidas antes de consultar BCRP", async () => {
  const f = dependencias(() => respuesta([]));
  const handler = crearHandlerTipoCambio(f.deps);

  for (const fecha of ["2026-09-03", "2026-02-30", "02/09/2026", ""]) {
    const response = await handler(request(fecha));
    igual(response.status, 400, `status para ${fecha}`);
  }
  igual(f.urls.length, 0, "ninguna fecha inválida llega al proveedor");
});

Deno.test("GET también acepta fecha_corte sin crear otra ruta", async () => {
  const f = dependencias(() => respuesta([periodo("31.Aug.26", 3.5)]));
  const response = await crearHandlerTipoCambio(f.deps)(
    new Request(
      "https://project.supabase.co/functions/v1/crm-tipo-cambio?fecha_corte=2026-08-31",
      { method: "GET" },
    ),
  );

  igual(response.status, 200, "status GET");
  igual((await response.json()).fecha_corte, "2026-08-31", "corte GET");
});
