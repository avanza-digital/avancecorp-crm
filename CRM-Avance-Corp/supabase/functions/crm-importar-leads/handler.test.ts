// Contrato HTTP real del handler; solo se sustituye el transporte PostgREST.
// Credenciales ficticias, sin red ni datos de producción.
function exigir(condicion: unknown, mensaje: string): asserts condicion {
  if (!condicion) throw new Error(mensaje);
}

Deno.test("HTTP: campaña llega a la misma RPC, compatibilidad y rechazo por fila", async (t) => {
  const nombres = [
    "CRM_IMPORTAR_SECRET",
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
  ];
  const anteriores = nombres.map((n) => Deno.env.get(n));
  const secreto = "a".repeat(64);
  Deno.env.set(nombres[0], secreto);
  Deno.env.set(nombres[1], "https://prueba-formulario.invalid");
  Deno.env.set(nombres[2], "clave-ficticia-del-banco");
  const fetchAnterior = globalThis.fetch;
  const llamadas: { url: string; cuerpo: Record<string, unknown> }[] = [];
  globalThis.fetch = ((url: string | URL | Request, opciones?: RequestInit) => {
    llamadas.push({
      url: String(url),
      cuerpo: JSON.parse(String(opciones?.body)),
    });
    return Promise.resolve(
      Response.json({
        resultado: "importado",
        lead_id: "f3000000-0000-0000-0000-000000000010",
        veredicto: null,
        reingreso: null,
      }),
    );
  }) as typeof fetch;
  try {
    const { manejarImportacion } = await import("./handler.ts");
    const fila = {
      fila: 2,
      nombre: "Persona de prueba",
      telefono: "987654321",
      capital: "5000",
      moneda: "PEN",
      canal: "FORMULARIO",
      autorizo: "SI",
      fuente_consentimiento: "Formulario de prueba",
    };
    const enviar = (filas: unknown[], clave = secreto) =>
      manejarImportacion(
        new Request("https://prueba.invalid", {
          method: "POST",
          headers: {
            "x-importar-secret": clave,
            "content-type": "application/json",
          },
          body: JSON.stringify({ filas }),
        }),
      );
    await t.step("canonicaliza y usa una sola transacción SQL", async () => {
      llamadas.length = 0;
      const respuesta = await enviar([{
        ...fila,
        campania_origen: " FORMULARIO 3 ",
      }]);
      exigir(respuesta.status === 200, "HTTP 200");
      const cuerpo = await respuesta.json();
      exigir(cuerpo.resultados[0].resultado === "importado", "alta confirmada");
      exigir(
        llamadas.length === 1 &&
          llamadas[0].url.endsWith("/rpc/importar_lead_fn"),
        "solo RPC de alta; no PATCH posterior",
      );
      const payload = llamadas[0].cuerpo.p_fila as Record<string, unknown>;
      exigir(
        payload.campania_origen === "Formulario 3" &&
          payload.origen === "formulario",
        "campaña y canal enviados juntos",
      );
      exigir(
        !("alta_manual" in payload) && payload.vendedor_id === null,
        "procedencia automática y reparto actual",
      );
    });
    await t.step("ausente o nula no cambia el payload anterior", async () => {
      for (const extra of [{}, { campania_origen: null }]) {
        llamadas.length = 0;
        await enviar([{ ...fila, ...extra }]);
        exigir(llamadas.length === 1, "importación antigua permitida");
        exigir(
          !("campania_origen" in (llamadas[0].cuerpo.p_fila as object)),
          "ausente no se convierte en clave nula",
        );
      }
    });
    await t.step("canal nuevo usa la misma puerta con origen propio", async () => {
      for (const canal of ["FORMULARIO_3", "Formulario 3"]) {
        llamadas.length = 0;
        const respuesta = await enviar([{ ...fila, canal }]);
        exigir(respuesta.status === 200 && llamadas.length === 1, "una sola RPC");
        const payload = llamadas[0].cuerpo.p_fila as Record<string, unknown>;
        exigir(payload.origen === "formulario_3" && payload.campania_origen === "Formulario 3", "origen propio y campaña coherentes");
      }
      llamadas.length = 0;
      await enviar([{ ...fila, canal: "FORMULARIO_3", campania_origen: "Otra" }]);
      exigir(llamadas.length === 0, "campaña incompatible no llega a la base");
    });
    await t.step(
      "fila inválida no escribe ni bloquea otra válida",
      async () => {
        llamadas.length = 0;
        const respuesta = await enviar([{ ...fila, campania_origen: {} }, {
          ...fila,
          fila: 3,
          campania_origen: "Formulario 3",
        }]);
        const cuerpo = await respuesta.json();
        exigir(
          cuerpo.resultados[0].resultado === "rechazado" &&
            cuerpo.resultados[1].resultado === "importado",
          "rechazo aislado por fila",
        );
        exigir(llamadas.length === 1, "solo escribe la fila válida");
      },
    );
    await t.step(
      "campaña no evade autorización ni combinación de canal",
      async () => {
        llamadas.length = 0;
        exigir(
          (await enviar(
            [{ ...fila, campania_origen: "Formulario 3" }],
            "incorrecto",
          )).status === 401,
          "se mantiene auth",
        );
        const respuesta = await enviar([{
          ...fila,
          canal: "LANDING",
          campania_origen: "Formulario 3",
        }]);
        exigir(
          (await respuesta.json()).resultados[0].resultado === "rechazado",
          "no reclasifica el canal",
        );
        exigir(llamadas.length === 0, "ninguna escritura rechazada");
      },
    );
  } finally {
    globalThis.fetch = fetchAnterior;
    nombres.forEach((n, i) =>
      anteriores[i] === undefined
        ? Deno.env.delete(n)
        : Deno.env.set(n, anteriores[i]!)
    );
  }
});
