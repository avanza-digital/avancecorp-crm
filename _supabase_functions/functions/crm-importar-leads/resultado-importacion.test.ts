import {
  clasificarErrorInsercion,
  clasificarErrorPuerta,
  clasificarRespuestaPuerta,
  textoRechazoDeVeredicto,
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
  assert(
    r.lead_id === "11111111-1111-1111-1111-111111111111",
    "lleva el lead canónico",
  );
  assert(r.estado.startsWith("YA ES CLIENTE"), "estado legible para la hoja");
  assert(r.estado.includes("ROSA"), "nombra al asesor");
  assert(
    !/registrado/i.test(r.estado),
    "no afirma «registrado» antes de que la RPC ocurra",
  );
});

Deno.test("F2.b: P0481 por otro motivo sigue siendo un rechazo definitivo", () => {
  const r = clasificarErrorInsercion(
    {
      code: "P0481",
      message: "Contacto no disponible",
      details: '{"estado": "en_bolsa"}',
    },
    409,
  );
  assert(r.resultado === "rechazado", "no es reingreso");
  assert(r.lead_id === undefined, "sin lead_id");
  assert(r.estado.includes("en bolsa"), "explica el motivo");
});

Deno.test("F2.b: P0429 (persona con No insistir) es rechazo definitivo", () => {
  const r = clasificarErrorInsercion(
    {
      code: "P0429",
      message: "La persona tiene la restricción",
      details: '{"estado":"no_contactar","via":"identidad"}',
    },
    409,
  );
  assert(r.resultado === "rechazado", "rechazado");
  assert(r.estado.includes("No insistir"), "menciona la restricción");
});

Deno.test("veredictoDeError tolera DETAIL vacío o no JSON", () => {
  assert(veredictoDeError({ code: "P0481", details: "" }) === null, "vacío");
  assert(
    veredictoDeError({ code: "P0481", details: "texto" }) === null,
    "no JSON",
  );
  assert(
    veredictoDeError({ code: "P0481", details: "{malo" }) === null,
    "JSON roto",
  );
});

// ── F2.b [D-4]: la respuesta de la puerta SQL produce los MISMOS textos que antes salían del error ──
Deno.test("D-4: importado por la puerta", () => {
  const r = clasificarRespuestaPuerta({
    resultado: "importado",
    lead_id: "abc",
    veredicto: null,
    reingreso: null,
  });
  assert(
    r.resultado === "importado" && r.estado === "IMPORTADO ✓" &&
      r.lead_id === "abc",
    "importado con lead_id",
  );
});

Deno.test("D-4: duplicado por la puerta = el DUPLICADO de siempre", () => {
  const r = clasificarRespuestaPuerta({
    resultado: "duplicado",
    veredicto: { estado: "duplicado", indice: "uq_leads_dni_vivo" },
  });
  assert(
    r.resultado === "duplicado" &&
      r.estado === "DUPLICADO: ya existe en el CRM",
    "texto de duplicado",
  );
});

Deno.test("D-4: ya_cliente con reingreso registrado (antes: dos pasos en el edge)", () => {
  const r = clasificarRespuestaPuerta({
    resultado: "ya_cliente",
    lead_id: "lead-1",
    veredicto: {
      estado: "ya_es_cliente",
      via: "identidad",
      asesor: "Ana Pérez",
      lead_id: "lead-1",
    },
    reingreso: { ok: true, actividad_id: "act-1" },
  });
  assert(r.resultado === "ya_cliente", "ya_cliente");
  assert(
    r.estado ===
      "YA ES CLIENTE (asesor: Ana Pérez): reingreso registrado en su ficha",
    `texto: ${r.estado}`,
  );
  assert(r.lead_id === "lead-1" && r.asesor === "Ana Pérez", "lead y asesor");
});

Deno.test("D-4: ya_cliente cuyo reingreso no se pudo anotar conserva el aviso", () => {
  const r = clasificarRespuestaPuerta({
    resultado: "ya_cliente",
    lead_id: "lead-1",
    veredicto: {
      estado: "ya_es_cliente",
      via: "identidad",
      asesor: "Ana Pérez",
    },
    reingreso: {
      ok: false,
      error: "P0409: Identidad unificada apagada: el reingreso no se registra",
    },
  });
  assert(
    r.estado.startsWith(
      "YA ES CLIENTE (asesor: Ana Pérez): NO se pudo anotar el reingreso en su ficha (",
    ),
    `texto: ${r.estado}`,
  );
  assert(
    r.estado.length <=
      "YA ES CLIENTE (asesor: Ana Pérez): NO se pudo anotar el reingreso en su ficha ("
          .length + 62,
    "el detalle se recorta a 60",
  );
});

Deno.test("D-4: ya_cliente sin lead ni reingreso queda como YA ES CLIENTE a secas", () => {
  const r = clasificarRespuestaPuerta({
    resultado: "ya_cliente",
    lead_id: null,
    veredicto: { estado: "ya_es_cliente", via: "identidad", asesor: "" },
    reingreso: null,
  });
  assert(
    r.estado === "YA ES CLIENTE" && r.lead_id === undefined,
    `texto: ${r.estado}`,
  );
});

Deno.test("D-4: rechazado por la persona «No insistir» (P0429 de hoy) conserva su texto", () => {
  const r = clasificarRespuestaPuerta({
    resultado: "rechazado",
    veredicto: { estado: "no_contactar", via: "identidad" },
  });
  assert(
    r.resultado === "rechazado" &&
      r.estado === "RECHAZADO: la persona tiene la restricción «No insistir»",
    `texto: ${r.estado}`,
  );
});

Deno.test("D-4: rechazado por otro veredicto conserva el texto de P0481", () => {
  const a = clasificarRespuestaPuerta({
    resultado: "rechazado",
    veredicto: { estado: "en_conversion" },
  });
  assert(
    a.estado === "RECHAZADO: contacto en conversion",
    `texto: ${a.estado}`,
  );
  assert(
    textoRechazoDeVeredicto(null) === "RECHAZADO: contacto no disponible",
    "sin veredicto",
  );
  assert(
    textoRechazoDeVeredicto({ estado: "no_contactar" }) ===
      "RECHAZADO: contacto no contactar",
    "no_contactar sin via = veto del lead",
  );
});

Deno.test("D-4: una respuesta inesperada de la puerta es temporal (se reintenta), nunca un rechazo", () => {
  for (const r of [null, undefined, {}, { resultado: 7 }] as unknown[]) {
    const c = clasificarRespuestaPuerta(r as never);
    assert(
      c.resultado === "error_temporal",
      `debe ser temporal: ${JSON.stringify(r)}`,
    );
  }
});

// ── F2.b [D-4] v3 (auditor A1): la puerta ausente o vedada NO es un rechazo de la fila ──────────────────────────────

Deno.test("D-4 v3: la RPC de la puerta no existe (PGRST202 + 404: reversa o caché rancia) → TEMPORAL, se reintenta", () => {
  const r = clasificarErrorPuerta(
    {
      code: "PGRST202",
      message:
        "Could not find the function crm.importar_lead_fn(p_fila) in the schema cache",
    },
    404,
  );
  assert(r.resultado === "error_temporal", "PGRST202 debe ser temporal");
  assert(r.estado.startsWith("ERROR temporal"), "texto temporal");
});

Deno.test("D-4 v3: 42883 (función inexistente) y 42501 (EXECUTE perdido) → TEMPORAL, nunca RECHAZADO", () => {
  for (const code of ["42883", "42501"]) {
    const r = clasificarErrorPuerta({ code, message: "x" }, 400);
    assert(r.resultado === "error_temporal", `${code} debe ser temporal`);
  }
});

Deno.test("D-4 v3: los demás errores de la puerta conservan la clasificación de siempre", () => {
  assert(
    clasificarErrorPuerta({ code: "23505", message: "dup" }, 409).resultado ===
      "duplicado",
    "23505 sigue siendo duplicado",
  );
  assert(
    clasificarErrorPuerta({ code: "22023", message: "DNI invalido" }, 400)
      .resultado === "rechazado",
    "22023 sigue siendo rechazo definitivo",
  );
  assert(
    clasificarErrorPuerta({ code: "55P03", message: "lock" }, 400).resultado ===
      "error_temporal",
    "55P03 sigue siendo temporal",
  );
  assert(
    clasificarErrorPuerta({ code: "40001", message: "serialization" }, 400)
      .resultado === "error_temporal",
    "40001 sigue siendo temporal",
  );
});

Deno.test("D-4 v4: una categoría que este edge no conoce es TEMPORAL, nunca un rechazo", () => {
  const r = clasificarRespuestaPuerta(
    { resultado: "otro", veredicto: { estado: "x" } } as unknown as Parameters<
      typeof clasificarRespuestaPuerta
    >[0],
  );
  assert(r.resultado === "error_temporal", "categoría desconocida → temporal");
});

Deno.test("D-4 v5: la misma fila reenviada → reingreso ya anotado (idempotente), sigue siendo YA ES CLIENTE", () => {
  const r = clasificarRespuestaPuerta({
    resultado: "ya_cliente",
    lead_id: "11111111-1111-4111-8111-111111111111",
    veredicto: { estado: "ya_es_cliente", via: "identidad", asesor: "Ana" },
    reingreso: { ok: true, actividad_id: "x", repetido: true },
  });
  assert(r.resultado === "ya_cliente", "sigue siendo ya_cliente");
  assert(
    r.estado ===
      "YA ES CLIENTE (asesor: Ana): reingreso ya anotado en su ficha",
    `texto: ${r.estado}`,
  );
});
