import { crearStorageContratoPdfV2, errorBackend } from "./storage.ts";

function assert(valor: unknown, mensaje: string): asserts valor {
  if (!valor) throw new Error(mensaje);
}
const opciones = {
  supabaseUrl: "https://banco.example.test",
  secretKey: "credencial-ficticia-sin-acceso",
  basePublica: () => "https://banco.example.test",
  plazoMs: 30,
};
const req = new Request("https://banco.example.test/functions/v1/pdf");

for (const paso of ["subir", "descargar", "firmar", "eliminar"] as const) {
  for (const corte of ["cabeceras", "cuerpo"] as const) {
    Deno.test(`Storage ${paso}: limita espera de ${corte} y aborta transporte`, async () => {
      let signal: AbortSignal | null | undefined;
      let cuerpo: ReadableStreamDefaultController<Uint8Array> | undefined;
      const storage = crearStorageContratoPdfV2({
        ...opciones,
        fetchImpl: (_input, init) => {
          signal = init?.signal;
          if (corte === "cabeceras") return new Promise<Response>(() => {});
          const stream = new ReadableStream<Uint8Array>({
            start(controller) {
              cuerpo = controller;
            },
          });
          return Promise.resolve(
            new Response(stream, {
              status: 200,
              headers: {
                "Content-Type": paso === "descargar"
                  ? "application/pdf"
                  : "application/json",
              },
            }),
          );
        },
      });
      try {
        const inicio = performance.now();
        const r = paso === "subir"
          ? await storage.subir("prueba.pdf", new Blob(["%PDF-1.7\nficticio"]))
          : paso === "descargar"
          ? await storage.descargar("prueba.pdf")
          : paso === "firmar"
          ? await storage.firmar("prueba.pdf", 300, req)
          : await storage.eliminar("contratos-generados", ["prueba.pdf"]);
        assert(
          r.error?.code === "STORAGE_TIMEOUT",
          "Debe devolver un error recuperable de timeout",
        );
        assert(
          r.error.statusCode === 504,
          "El timeout debe conservar su clasificación",
        );
        assert(signal?.aborted, "El transporte debe recibir la cancelación");
        assert(
          performance.now() - inicio < 2000,
          "La operación no terminó dentro de su límite",
        );
      } finally {
        cuerpo?.error(new Error("Fin del cuerpo ficticio bloqueado"));
      }
    });
  }
}

Deno.test("Storage conserva ausencia, conflicto y errores del SDK", async () => {
  for (
    const [statusCode, code] of [["404", "NoSuchKey"], ["409", "Duplicate"], [
      "503",
      "Unavailable",
    ]]
  ) {
    const storage = crearStorageContratoPdfV2({
      ...opciones,
      fetchImpl: () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ statusCode, code, message: "Error ficticio" }),
            {
              status: 400,
              headers: { "Content-Type": "application/json" },
            },
          ),
        ),
    });
    const r = await storage.descargar("prueba.pdf");
    assert(r.data === null, "Un error no devuelve bytes");
    assert(
      r.error?.statusCode === Number(statusCode),
      "Debe normalizar el código textual del SDK",
    );
    // Cuando statusCode ya es numérico, este SDK no conserva `code` aparte;
    // la decisión de ausencia/conflicto queda respaldada por 404/409.
  }
  const simbolico = crearStorageContratoPdfV2({
    ...opciones,
    fetchImpl: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({ code: "NoSuchKey", message: "Ausente" }),
          {
            status: 400,
            headers: { "Content-Type": "application/json" },
          },
        ),
      ),
  });
  const ausente = await simbolico.descargar("prueba.pdf");
  assert(
    ausente.error?.code === "NoSuchKey" && ausente.error.statusCode === 400,
    "Debe reconocer también el código simbólico transportado por el SDK",
  );
  assert(
    errorBackend("error no estructurado") === null,
    "Los errores ajenos se normalizan de forma conservadora",
  );
});

Deno.test("Storage descarga los mismos bytes y una operación lenta no cancela otra", async () => {
  const bytes = new TextEncoder().encode(
    "%PDF-1.7\ncontenido ficticio idéntico",
  );
  const storage = crearStorageContratoPdfV2({
    ...opciones,
    fetchImpl: (input) =>
      String(input).endsWith("lento.pdf")
        ? new Promise<Response>(() => {})
        : Promise.resolve(
          new Response(bytes, {
            headers: { "Content-Type": "application/pdf" },
          }),
        ),
  });
  const lento = storage.descargar("lento.pdf");
  const rapido = await storage.descargar("rapido.pdf");
  assert(
    rapido.error === null && rapido.data,
    "La descarga independiente debe terminar",
  );
  assert(
    await rapido.data.text() === new TextDecoder().decode(bytes),
    "No debe modificar el archivo",
  );
  assert(
    (await lento).error?.code === "STORAGE_TIMEOUT",
    "Solo se cancela la operación que vence",
  );
});

Deno.test("Storage subida mantiene no sobrescritura y devuelve fallo si el transporte lanza", async () => {
  let upsert: string | null = null;
  const storage = crearStorageContratoPdfV2({
    ...opciones,
    fetchImpl: (_input, init) => {
      upsert = new Headers(init?.headers).get("x-upsert");
      return Promise.reject(new TypeError("Red ficticia no disponible"));
    },
  });
  const r = await storage.subir("prueba.pdf", new Blob(["%PDF-1.7\nficticio"]));
  assert(upsert === "false", "Nunca habilita sobrescritura");
  assert(
    r.error !== null,
    "Una excepción del transporte nunca se convierte en éxito",
  );
});
