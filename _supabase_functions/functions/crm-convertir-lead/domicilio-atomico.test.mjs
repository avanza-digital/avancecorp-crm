import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const fuente = await readFile(new URL("./index.ts", import.meta.url), "utf8");

test("el dedup no modifica perfiles con service_role antes de autorizar", () => {
  const inicioDedup = fuente.indexOf("// DEDUP:");
  const inicioConversion = fuente.indexOf('.rpc("convertir_lead_con_domicilio"');
  assert.ok(inicioDedup >= 0 && inicioConversion > inicioDedup);
  const tramo = fuente.slice(inicioDedup, inicioConversion);
  assert.equal(tramo.includes('.update({ domicilio: domicilioLegal })'), false);
});

test("la única frontera de persistencia recibe lead, perfil y domicilio juntos", () => {
  assert.ok(fuente.includes('.rpc("convertir_lead_con_domicilio"'));
  assert.ok(fuente.includes("p_lead_id: lead_id"));
  assert.ok(fuente.includes("p_perfil_id: perfilId"));
  assert.ok(fuente.includes("p_domicilio: domicilioLegal"));
  assert.equal(
    fuente.includes('.rpc("convertir_lead", { p_lead_id: lead_id, p_perfil_id: perfilId })'),
    false,
  );
});
