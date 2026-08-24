import { clasificarErrorInsercion } from "./resultado-importacion.ts";

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
