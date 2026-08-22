import { interpretarAutorizacionContacto } from "./autorizacion-contacto.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("SI registra consentimiento sin bloquear el lead", () => {
  for (const valor of ["SI", "Sí", "s", " SÍ "]) {
    const resultado = interpretarAutorizacionContacto(valor);
    assert(resultado.ok, `${valor} debe ser válido`);
    assert(
      resultado.registrarConsentimiento,
      `${valor} debe registrar el consentimiento`,
    );
  }
});

Deno.test("NO deja el lead visible y repartible sin registrar consentimiento", () => {
  for (const valor of ["NO", "n", " NO "]) {
    const resultado = interpretarAutorizacionContacto(valor);
    assert(resultado.ok, `${valor} debe ser válido`);
    assert(
      !resultado.registrarConsentimiento,
      `${valor} no debe registrar consentimiento`,
    );
  }
});

Deno.test("vacío importa sin registrar consentimiento", () => {
  const resultado = interpretarAutorizacionContacto(undefined);
  assert(resultado.ok, "el valor vacío debe ser válido");
  assert(
    !resultado.registrarConsentimiento,
    "el valor vacío no debe registrar consentimiento",
  );
});

Deno.test("un valor desconocido sigue rechazando la fila", () => {
  const resultado = interpretarAutorizacionContacto("FALSE");
  assert(!resultado.ok, "FALSE no debe aceptarse como SI o NO");
  assert(
    resultado.error.includes("debe ser SI o NO"),
    "el rechazo debe explicar los valores válidos",
  );
});
