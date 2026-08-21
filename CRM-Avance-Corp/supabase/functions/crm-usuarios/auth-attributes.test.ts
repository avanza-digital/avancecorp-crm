import { atributosCreacionAuthCrm } from "./auth-attributes.ts";

function igual(actual: unknown, esperado: unknown, mensaje: string) {
  if (actual !== esperado) {
    throw new Error(
      `${mensaje}: esperado=${String(esperado)} actual=${String(actual)}`,
    );
  }
}

Deno.test("la identidad CRM usa el documento exacto y queda confirmada sin flujo de correo", () => {
  const atributos = atributosCreacionAuthCrm({
    correo: "persona@avance.test",
    nombreCompleto: "Persona CRM",
    documento: "001237707",
  });

  igual(atributos.password, "001237707", "preserva ceros iniciales");
  igual(atributos.email_confirm, true, "correo confirmado por Admin");
  igual(atributos.app_metadata.origen_app, "crm", "origen administrado");
  igual(
    "origen" in atributos.user_metadata,
    false,
    "user_metadata no decide el origen",
  );
});

Deno.test("un pasaporte normalizado no recibe relleno", () => {
  const atributos = atributosCreacionAuthCrm({
    correo: "pasaporte@avance.test",
    nombreCompleto: "Pasaporte CRM",
    documento: "AB1234",
  });

  igual(atributos.password, "AB1234", "clave exacta de seis caracteres");
});
