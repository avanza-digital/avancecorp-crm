import { interpretarCampania } from "./campania.ts";

function igual(actual: unknown, esperado: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(esperado)) {
    throw new Error(
      `${JSON.stringify(actual)} !== ${JSON.stringify(esperado)}`,
    );
  }
}

Deno.test("campaña ausente conserva el contrato anterior", () => {
  for (const v of [undefined, null]) {
    igual(interpretarCampania(v, "landing"), { ok: true, valor: null });
  }
});
Deno.test("Formulario 3 canónico y campañas futuras sin enum", () => {
  igual(interpretarCampania("  FORMULARIO 3  ", "formulario"), {
    ok: true,
    valor: "Formulario 3",
  });
  igual(interpretarCampania("Campaña octubre", "landing"), {
    ok: true,
    valor: "Campaña octubre",
  });
  igual(interpretarCampania("🌱".repeat(80), "formulario"), {
    ok: true,
    valor: "🌱".repeat(80),
  });
});
Deno.test("campaña explícita inválida se rechaza, no se descarta", () => {
  for (
    const v of [
      "",
      "   ",
      3,
      false,
      {},
      [],
      "x".repeat(81),
      "🌱".repeat(81),
      "uno\ndos",
      "\tFormulario 3",
      "x\u007fy",
      "x\u0085y",
    ]
  ) {
    igual(interpretarCampania(v, "formulario").ok, false);
  }
  igual(interpretarCampania("Formulario 3", "landing").ok, false);
});
