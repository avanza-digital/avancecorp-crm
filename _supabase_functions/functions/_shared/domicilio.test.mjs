import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { DOMICILIO_LEGAL_MAX, validarDomicilioLegal } from "./domicilio.mjs";

test("normaliza solo los bordes y conserva el domicilio legal literal", () => {
  assert.deepEqual(
    validarDomicilioLegal("  Av. Los Olivos 245, Lima  "),
    { ok: true, valor: "Av. Los Olivos 245, Lima" },
  );
});

test("el CRM exige domicilio y el caller legacy puede omitirlo explícitamente", () => {
  assert.deepEqual(validarDomicilioLegal(""), {
    ok: false,
    error: "Completa el domicilio legal del cliente.",
  });
  assert.deepEqual(validarDomicilioLegal(undefined, { requerido: false }), {
    ok: true,
    valor: null,
  });
});

test("rechaza tipos no textuales, tamaños inválidos y controles C0/C1", () => {
  assert.deepEqual(validarDomicilioLegal({ calle: "Av. Lima 123" }), {
    ok: false,
    error: "El domicilio legal debe ser texto.",
  });
  assert.equal(validarDomicilioLegal(123456).ok, false);
  assert.equal(validarDomicilioLegal("Lima").ok, false);
  assert.equal(
    validarDomicilioLegal("x".repeat(DOMICILIO_LEGAL_MAX + 1)).ok,
    false,
  );
  assert.equal(validarDomicilioLegal("Av. Lima 123\nLima").ok, false);
  assert.equal(validarDomicilioLegal("Av. Lima 123\u0085Lima").ok, false);
});

test("las dos edges validan antes de efectos y persisten el valor normalizado", async () => {
  const crear = await readFile(
    new URL("../crear-cliente/index.ts", import.meta.url),
    "utf8",
  );
  const convertir = await readFile(
    new URL("../crm-convertir-lead/index.ts", import.meta.url),
    "utf8",
  );

  assert.ok(crear.includes('from "../_shared/domicilio.mjs"'));
  assert.ok(
    crear.includes("requerido: bancarios !== undefined && bancarios !== null"),
  );
  assert.ok(crear.includes("domicilio: domicilioLegal"));
  assert.ok(
    crear.indexOf("validarDomicilioLegal(") <
      crear.indexOf("auth.admin.createUser("),
  );

  assert.ok(convertir.includes('from "../_shared/domicilio.mjs"'));
  assert.ok(convertir.includes("domicilio: domicilioLegal"));
  assert.ok(convertir.includes('.select("id, activo")'));
  assert.ok(convertir.includes('.rpc("convertir_lead_con_domicilio"'));
  assert.ok(convertir.includes("p_domicilio: domicilioLegal"));
  assert.equal(
    convertir.includes('.update({ domicilio: domicilioLegal })'),
    false,
    "la Edge jamás debe escribir el domicilio del dedup con service_role",
  );
  assert.ok(
    convertir.indexOf("validarDomicilioLegal(") <
      convertir.indexOf('.rpc("reservar_conversion_lead"'),
  );
});
