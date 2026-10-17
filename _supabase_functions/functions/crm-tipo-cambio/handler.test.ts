import {
  calcularTipoCambio,
  clavePeriodo,
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

// ---------------------------------------------------------------------------
// Regresión 2026-09: el BCRP rotula septiembre en español («Set») aunque se
// pida `/ing`. Los fixtures de abajo son respuestas LITERALES de la API
// (PD04639PD compra, PD04640PD venta) capturadas el 18/09/2026.
// ---------------------------------------------------------------------------

function periodoCrudo(name: string, valor: string): Periodo {
  return { name, values: [valor] };
}

/** GET …/PD04639PD/json/2026-09-02/2026-09-18/ing */
const SEPTIEMBRE_COMPRA: Periodo[] = [
  periodoCrudo("02.Set.26", "3.353"),
  periodoCrudo("03.Set.26", "3.355"),
  periodoCrudo("04.Set.26", "3.36"),
  periodoCrudo("07.Set.26", "3.351"),
  periodoCrudo("08.Set.26", "3.351"),
  periodoCrudo("09.Set.26", "3.355"),
  periodoCrudo("10.Set.26", "3.367"),
  periodoCrudo("11.Set.26", "3.363"),
  periodoCrudo("14.Set.26", "3.373"),
  periodoCrudo("15.Set.26", "3.372"),
  periodoCrudo("16.Set.26", "3.361"),
  periodoCrudo("17.Set.26", "3.36"),
  periodoCrudo("18.Set.26", "n.d."),
];

/** GET …/PD04640PD/json/2026-09-02/2026-09-18/ing */
const SEPTIEMBRE_VENTA: Periodo[] = [
  periodoCrudo("02.Set.26", "3.36"),
  periodoCrudo("03.Set.26", "3.365"),
  periodoCrudo("04.Set.26", "3.369"),
  periodoCrudo("07.Set.26", "3.372"),
  periodoCrudo("08.Set.26", "3.36"),
  periodoCrudo("09.Set.26", "3.362"),
  periodoCrudo("10.Set.26", "3.373"),
  periodoCrudo("11.Set.26", "3.371"),
  periodoCrudo("14.Set.26", "3.383"),
  periodoCrudo("15.Set.26", "3.379"),
  periodoCrudo("16.Set.26", "3.372"),
  periodoCrudo("17.Set.26", "3.368"),
  periodoCrudo("18.Set.26", "n.d."),
];

/** GET …/PD04639PD/json/2026-07-28/2026-08-05/ing (inglés, con «n.d.»). */
const AGOSTO_COMPRA: Periodo[] = [
  periodoCrudo("28.Jul.26", "n.d."),
  periodoCrudo("29.Jul.26", "n.d."),
  periodoCrudo("30.Jul.26", "3.384"),
  periodoCrudo("31.Jul.26", "3.391"),
  periodoCrudo("03.Aug.26", "3.391"),
  periodoCrudo("04.Aug.26", "3.386"),
  periodoCrudo("05.Aug.26", "3.385"),
];

/** GET …/PD04640PD/json/2026-07-28/2026-08-05/ing */
const AGOSTO_VENTA: Periodo[] = [
  periodoCrudo("28.Jul.26", "n.d."),
  periodoCrudo("29.Jul.26", "n.d."),
  periodoCrudo("30.Jul.26", "3.399"),
  periodoCrudo("31.Jul.26", "3.4"),
  periodoCrudo("03.Aug.26", "3.402"),
  periodoCrudo("04.Aug.26", "3.394"),
  periodoCrudo("05.Aug.26", "3.394"),
];

// «Hoy» debe ser posterior al corte: la frontera rechaza cortes futuros (400).
function dependenciasSeries(
  compra: Periodo[],
  venta: Periodo[],
  ahora = Date.parse("2026-09-18T20:00:00.000Z"),
) {
  return dependencias(
    (url) => respuesta(url.includes("PD04639PD") ? compra : venta),
    ahora,
  );
}

Deno.test("septiembre real («Set» en español): 7 días hábiles y el n.d. del 18 se descarta", async () => {
  const f = dependenciasSeries(SEPTIEMBRE_COMPRA, SEPTIEMBRE_VENTA);

  const resultado = await calcularTipoCambio(f.deps, "2026-09-18");

  igual(resultado.dias, 7, "días con dato hasta el corte");
  // Punto medio (compra+venta)/2 del 09 al 17 de septiembre:
  // 3.3585, 3.37, 3.367, 3.378, 3.3755, 3.3665, 3.364 → 23.5795 / 7.
  igual(resultado.promedio, 3.3685, "promedio del punto medio");
  igual(resultado.desde, "09.Set.26", "primer día del promedio");
  igual(
    resultado.hasta,
    "17.Set.26",
    "último día del promedio (el 18 es n.d.)",
  );
  igual(resultado.fecha_corte, "2026-09-18", "corte declarado");
});

Deno.test("septiembre real por la frontera HTTP responde 200 (antes 502)", async () => {
  const f = dependenciasSeries(SEPTIEMBRE_COMPRA, SEPTIEMBRE_VENTA);
  const response = await crearHandlerTipoCambio(f.deps)(request("2026-09-18"));

  igual(response.status, 200, "status septiembre");
  const cuerpo = await response.json();
  igual(cuerpo.dias, 7, "días por HTTP");
  igual(cuerpo.promedio, 3.3685, "promedio por HTTP");
});

Deno.test("agosto real en inglés sigue funcionando y también descarta n.d.", async () => {
  const f = dependenciasSeries(AGOSTO_COMPRA, AGOSTO_VENTA);

  const resultado = await calcularTipoCambio(f.deps, "2026-08-05");

  igual(resultado.dias, 5, "5 fechas con dato en la ventana");
  // 3.3915, 3.3955, 3.3965, 3.39, 3.3895 → 16.963 / 5.
  igual(resultado.promedio, 3.3926, "promedio inglés");
  igual(resultado.desde, "30.Jul.26", "cruza de julio a agosto");
  igual(resultado.hasta, "05.Aug.26", "último día");
});

Deno.test("acepta ambas variantes de todos los meses, sin importar mayúsculas ni espacios", () => {
  const variantes: Array<[string, string, number]> = [
    ["Ene", "Jan", 0],
    ["Feb", "Feb", 1],
    ["Mar", "Mar", 2],
    ["Abr", "Apr", 3],
    ["May", "May", 4],
    ["Jun", "Jun", 5],
    ["Jul", "Jul", 6],
    ["Ago", "Aug", 7],
    ["Set", "Sep", 8],
    ["Oct", "Oct", 9],
    ["Nov", "Nov", 10],
    ["Dic", "Dec", 11],
  ];
  for (const [es, en, mes] of variantes) {
    const esperado = Date.UTC(2026, mes, 3);
    igual(clavePeriodo(`03.${es}.26`), esperado, `español ${es}`);
    igual(clavePeriodo(`03.${en}.26`), esperado, `inglés ${en}`);
    igual(
      clavePeriodo(` 03.${es.toUpperCase()}.26 `),
      esperado,
      `normalizado ${es}`,
    );
  }
  igual(clavePeriodo("03.Sept.26"), Date.UTC(2026, 8, 3), "variante Sept");
  igual(
    clavePeriodo("03.Set.2026"),
    Date.UTC(2026, 8, 3),
    "año de cuatro cifras",
  );
});

Deno.test("un período ilegible NO se disfraza de «sin datos»: 502 nombrando el período", async () => {
  const basura = [
    periodoCrudo("2026-09-18", "3.36"),
    periodoCrudo("18.Setiembre.26", "3.37"),
  ];
  const f = dependenciasSeries(basura, basura);

  const response = await crearHandlerTipoCambio(f.deps)(request("2026-09-18"));

  igual(response.status, 502, "status período ilegible");
  const cuerpo = await response.json();
  igual(
    cuerpo.error,
    "BCRP: formato de período no reconocido: 2026-09-18",
    "el mensaje incluye el período ofensivo literal",
  );
  assert(clavePeriodo("2026-09-18") === null, "clave nula para formato ISO");
  assert(clavePeriodo("18.Setiembre.26") === null, "clave nula para mes largo");
  assert(clavePeriodo("18.Set") === null, "clave nula si faltan partes");
  assert(
    clavePeriodo("x.Set.26") === null,
    "clave nula si el día no es numérico",
  );
});

Deno.test("sin períodos o todos «n.d.» conserva el mensaje de «sin datos»", async () => {
  const todoNd = [
    periodoCrudo("18.Set.26", "n.d."),
    periodoCrudo("19.Set.26", "n.d."),
  ];
  for (
    const [nombre, series] of [["vacío", []], ["todo n.d.", todoNd]] as const
  ) {
    const f = dependenciasSeries([...series], [...series]);
    const response = await crearHandlerTipoCambio(f.deps)(
      request("2026-09-18"),
    );
    igual(response.status, 502, `status ${nombre}`);
    igual(
      (await response.json()).error,
      "BCRP sin datos en la ventana consultada",
      `mensaje ${nombre}`,
    );
  }
});

Deno.test("si solo algunos períodos son ilegibles, los legibles siguen contando", async () => {
  const mezcla = [periodoCrudo("??", "9"), ...SEPTIEMBRE_COMPRA];
  const f = dependenciasSeries(mezcla, SEPTIEMBRE_VENTA);

  const resultado = await calcularTipoCambio(f.deps, "2026-09-18");

  igual(resultado.dias, 7, "los 7 legibles siguen ahí");
  igual(resultado.promedio, 3.3685, "el ilegible no contamina el promedio");
});
