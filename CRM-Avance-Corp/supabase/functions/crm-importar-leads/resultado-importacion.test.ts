import {
  clasificarErrorInsercion,
  veredictoDeError,
} from "./resultado-importacion.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("una carrera del índice único queda como DUPLICADO", () => {
  const r = clasificarErrorInsercion(
    {
      code: "23505",
      message: "duplicate key value violates unique constraint",
    },
    409,
  );
  assert(r.resultado === "duplicado", "23505 debe ser duplicado");
  assert(r.estado.startsWith("DUPLICADO"), "la hoja debe poder identificarlo");
});

Deno.test("fallos de conexión, concurrencia y capacidad son temporales", () => {
  for (
    const code of [
      "08006",
      "40001",
      "40P01",
      "53300",
      "55P03",
      "57P03",
      "58030",
      "XX000",
    ]
  ) {
    const r = clasificarErrorInsercion(
      { code, message: "fallo transitorio" },
      409,
    );
    assert(r.resultado === "error_temporal", `${code} debe reintentarse`);
    assert(
      r.estado.startsWith("ERROR temporal"),
      `${code} debe quedar visible en la hoja`,
    );
  }
});

Deno.test("HTTP 0, 429 y 5xx son temporales aunque no traigan código SQL", () => {
  for (const status of [0, 429, 500, 503]) {
    const r = clasificarErrorInsercion(
      { message: "servicio no disponible" },
      status,
    );
    assert(
      r.resultado === "error_temporal",
      `HTTP ${status} debe reintentarse`,
    );
  }
});

Deno.test("una restricción de datos queda RECHAZADA para corrección humana", () => {
  const r = clasificarErrorInsercion(
    { code: "23514", message: "capital fuera del rango permitido" },
    400,
  );
  assert(
    r.resultado === "rechazado",
    "23514 no debe reintentarse para siempre",
  );
  assert(
    r.estado === "RECHAZADO: capital fuera del rango permitido",
    "debe conservar el motivo útil",
  );
});

Deno.test("el detalle de rechazo se normaliza y limita antes de escribirlo en Sheets", () => {
  const r = clasificarErrorInsercion(
    { code: "22001", message: `dato\ninválido ${"x".repeat(200)}` },
    400,
  );
  assert(
    !r.estado.includes("\n"),
    "no debe escribir saltos de línea del servidor",
  );
  assert(
    r.estado.length <= "RECHAZADO: ".length + 120,
    "el mensaje debe quedar acotado",
  );
});

Deno.test("F2.b: P0481 ya_es_cliente vía identidad es un REINGRESO con lead_id", () => {
  const r = clasificarErrorInsercion(
    {
      code: "P0481",
      message: "Contacto no disponible",
      details:
        '{"estado": "ya_es_cliente", "asesor": "ROSA", "via": "identidad", "lead_id": "11111111-1111-1111-1111-111111111111"}',
    },
    409,
  );
  assert(r.resultado === "ya_cliente", "debe ser ya_cliente");
  assert(r.lead_id === "11111111-1111-1111-1111-111111111111", "lleva el lead canónico");
  assert(r.estado.startsWith("YA ES CLIENTE"), "estado legible para la hoja");
  assert(r.estado.includes("ROSA"), "nombra al asesor");
});

Deno.test("F2.b: P0481 por otro motivo sigue siendo un rechazo definitivo", () => {
  const r = clasificarErrorInsercion(
    { code: "P0481", message: "Contacto no disponible", details: '{"estado": "en_bolsa"}' },
    409,
  );
  assert(r.resultado === "rechazado", "no es reingreso");
  assert(r.lead_id === undefined, "sin lead_id");
  assert(r.estado.includes("en bolsa"), "explica el motivo");
});

Deno.test("F2.b: P0429 (persona con No insistir) es rechazo definitivo", () => {
  const r = clasificarErrorInsercion(
    { code: "P0429", message: "La persona tiene la restricción", details: '{"estado":"no_contactar","via":"identidad"}' },
    409,
  );
  assert(r.resultado === "rechazado", "rechazado");
  assert(r.estado.includes("No insistir"), "menciona la restricción");
});

Deno.test("veredictoDeError tolera DETAIL vacío o no JSON", () => {
  assert(veredictoDeError({ code: "P0481", details: "" }) === null, "vacío");
  assert(veredictoDeError({ code: "P0481", details: "texto" }) === null, "no JSON");
  assert(veredictoDeError({ code: "P0481", details: "{malo" }) === null, "JSON roto");
});
