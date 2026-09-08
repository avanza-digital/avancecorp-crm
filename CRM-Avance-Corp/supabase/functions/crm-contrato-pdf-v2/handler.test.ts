import {
  type BackendResult,
  CONTRATO_PDF_MAX_BYTES,
  CONTRATO_PDF_TEMPLATE_VERSION,
  crearHandlerContratoPdfV2,
  type DependenciasContratoPdfV2,
  normalizarUrlFirmadaV2,
  type RenderResult,
} from "./handler.ts";

function assert(condicion: unknown, mensaje: string): asserts condicion {
  if (!condicion) throw new Error(mensaje);
}

function igual(actual: unknown, esperado: unknown, mensaje: string) {
  if (actual !== esperado) {
    throw new Error(
      `${mensaje}: esperado=${String(esperado)} actual=${String(actual)}`,
    );
  }
}

const CONTRATO_ID = "8fffe71c-0abc-4c36-90fa-79fcbf4c3941";
const JOB_ID = "22222222-2222-4222-8222-222222222222";
const LEASE_TOKEN = "33333333-3333-4333-8333-333333333333";
const ACTOR_ID = "11111111-1111-4111-8111-111111111111";
const PATH = `${CONTRATO_ID}/v2/${JOB_ID}/contrato.pdf`;
const ORIGIN = "https://crm.miavance.com";

const SNAPSHOT = {
  snapshotVersion: 2,
  contrato: {
    id: CONTRATO_ID,
    numero: "2026-01-000777",
    clienteId: "44444444-4444-4444-8444-444444444444",
    capital: 15000,
    moneda: "PEN",
    porcentaje: 18,
    modalidad: "vencimiento",
    tipoInteres: "simple",
    categoria: "A",
    fechaInicio: "2026-08-17",
    fechaVencimiento: "2027-08-17",
    productoCondicionId: null,
    creadoPor: ACTOR_ID,
  },
  titular: {
    id: "44444444-4444-4444-8444-444444444444",
    nombreCompleto: "CLIENTE PRUEBA",
    tipoDocumento: "DNI",
    documento: "45781234",
    domicilio: "Av. Los Inversionistas 245, Lima",
    correo: "cliente@example.test",
  },
  analista: {
    id: ACTOR_ID,
    nombreCompleto: "ANALISTA PRUEBA",
    documento: "12345678",
    celular: "999111222",
    correo: "analista@example.test",
  },
  cotitulares: [],
  cronograma: [{
    id: "55555555-5555-4555-8555-555555555555",
    numeroCuota: 1,
    fechaProgramada: "2027-08-17",
    montoProgramado: 17700,
    tipo: "capital_interes",
  }],
  cuentaPago: {
    cuentaId: "66666666-6666-4666-8666-666666666666",
    moneda: "PEN",
    banco: "BCP",
    tipoCuenta: "ahorros",
    numeroCuenta: "19100000000000",
    cci: "00219100000000000000",
    titularDistinto: false,
    beneficiarioNombre: null,
    beneficiarioDocumento: null,
    origen: "crm",
  },
};

function estado(
  estadoPdf: string,
  extras: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    contrato_id: CONTRATO_ID,
    job_id: JOB_ID,
    estado: estadoPdf,
    storage_bucket: "contratos-generados",
    storage_path: PATH,
    nombre_archivo: "Contrato-2026-01-000777.pdf",
    template_version: CONTRATO_PDF_TEMPLATE_VERSION,
    intentos: 1,
    lease_expira_en: "2026-08-17T20:02:00Z",
    reintentable: false,
    sha256: null,
    bytes: null,
    archivo: null,
    ...extras,
  };
}

async function sha256(blob: Blob): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    await blob.arrayBuffer(),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

type FakeOptions = {
  sesion?: string | null;
  actor?: BackendResult[];
  admin?: BackendResult[];
  uploadError?: { code?: string; message?: string; statusCode?: number } | null;
  deleteError?: { code?: string; message?: string; statusCode?: number } | null;
  downloadError?: { code?: string; message?: string; statusCode?: number };
  downloads?: Array<Blob | null>;
  render?: RenderResult | Error;
};

function fake(opciones: FakeOptions = {}) {
  const actor = [...(opciones.actor ?? [])];
  const admin = [...(opciones.admin ?? [])];
  const downloads = [...(opciones.downloads ?? [])];
  const calls: string[] = [];
  const deps: DependenciasContratoPdfV2 = {
    crearActor: () => ({
      verificarSesion: () => {
        calls.push("auth");
        const id = opciones.sesion === undefined ? ACTOR_ID : opciones.sesion;
        return Promise.resolve(id ? { id } : null);
      },
      rpc: (nombre) => {
        calls.push(`actor:${nombre}`);
        return Promise.resolve(
          actor.shift() ?? { data: null, error: null },
        );
      },
    }),
    rpcAdmin: (nombre) => {
      calls.push(`admin:${nombre}`);
      return Promise.resolve(admin.shift() ?? { data: null, error: null });
    },
    renderizar: () => {
      calls.push("render");
      if (opciones.render instanceof Error) {
        return Promise.reject(opciones.render);
      }
      return Promise.resolve(
        opciones.render ?? {
          blob: new Blob(["%PDF-1.7\nserver"], {
            type: "application/pdf",
          }),
          sha256: "",
          bytes: 0,
        },
      );
    },
    storage: {
      subir: (_path, _blob) => {
        calls.push("upload");
        return Promise.resolve({ error: opciones.uploadError ?? null });
      },
      descargar: () => {
        calls.push("download");
        const data = downloads.length > 1
          ? downloads.shift()!
          : downloads[0] ?? null;
        return Promise.resolve({
          data,
          error: data ? null : opciones.downloadError ?? { message: "missing" },
        });
      },
      firmar: () => {
        calls.push("sign");
        return Promise.resolve({
          url: "https://storage.example.test/firma",
          error: null,
        });
      },
      eliminar: (bucket, paths) => {
        calls.push(`remove:${bucket}:${paths.length}`);
        return Promise.resolve({ error: opciones.deleteError ?? null });
      },
    },
  };
  return { deps, calls };
}

Deno.test("plantilla incompatible se informa antes de tomar el lease", async () => {
  const { deps, calls } = fake({
    admin: [{
      data: estado("pendiente", { template_version: "contrato-aep-17-v6" }),
      error: null,
    }],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 409, "versión incompatible");
  igual(
    (await res.json()).codigo,
    "PDF_VERSION_NO_SOPORTADA",
    "explica la incompatibilidad",
  );
  igual(calls.includes("admin:contrato_pdf_reclamar"), false, "no reclama");
  igual(
    calls.includes("admin:contrato_pdf_marcar_error"),
    false,
    "no altera el job",
  );
  igual(calls.includes("render"), false, "no renderiza con otra plantilla");
});

Deno.test("versión cambiada entre reserva y reclamo libera el lease sin marcar corrupción", async () => {
  const { deps, calls } = fake({
    admin: [
      { data: estado("pendiente"), error: null },
      {
        data: estado("procesando", {
          adquirido: true,
          lease_token: LEASE_TOKEN,
          template_version: "contrato-aep-17-v6",
          snapshot: SNAPSHOT,
          renderizado_en: "2026-08-17T20:00:00Z",
        }),
        error: null,
      },
      {
        data: estado("error_reintentable", {
          template_version: "contrato-aep-17-v6",
          reintentable: true,
          lease_expira_en: null,
        }),
        error: null,
      },
    ],
  });
  const rpc = deps.rpcAdmin;
  let codigo;
  deps.rpcAdmin = (nombre, args) => {
    if (nombre === "contrato_pdf_marcar_error") codigo = args.p_error_codigo;
    return rpc(nombre, args);
  };
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 409, "versión incompatible");
  igual(
    codigo,
    "PLANTILLA_NO_SOPORTADA",
    "la versión desconocida no se declara corrupta",
  );
  igual(calls.includes("render"), false, "no renderiza");
  igual(calls.includes("upload"), false, "no sube");
  igual(calls.includes("admin:contrato_pdf_finalizar"), false, "no sella");
});

Deno.test("respuesta de reclamo futura devuelve el lease identificable sin hacer I/O", async () => {
  const { deps, calls } = fake({
    admin: [
      { data: estado("pendiente"), error: null },
      {
        data: estado("procesando", {
          adquirido: true,
          lease_token: LEASE_TOKEN,
          template_version: "contrato-aep-17-v9",
        }),
        error: null,
      },
      {
        data: estado("error_reintentable", { reintentable: true }),
        error: null,
      },
    ],
  });
  const rpc = deps.rpcAdmin;
  let codigo;
  deps.rpcAdmin = (nombre, args) => {
    if (nombre === "contrato_pdf_marcar_error") codigo = args.p_error_codigo;
    return rpc(nombre, args);
  };
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 502, "la metadata no validada se rechaza");
  igual(
    codigo,
    "RESPUESTA_RECLAMO_INVALIDA",
    "devuelve el lease sin declarar corrupción",
  );
  igual(
    calls.includes("render"),
    false,
    "no interpreta el snapshot de otra versión",
  );
  igual(
    calls.includes("download"),
    false,
    "no lee Storage desde metadata inválida",
  );
});

Deno.test("render demasiado grande se rechaza antes de materializar su contenido", async () => {
  let materializaciones = 0;
  class BlobInstrumentado extends Blob {
    override get size() {
      return CONTRATO_PDF_MAX_BYTES + 1;
    }
    override arrayBuffer(): Promise<ArrayBuffer> {
      materializaciones++;
      return Promise.reject(
        new Error("No debe materializar un archivo fuera del límite"),
      );
    }
  }
  const blob = new BlobInstrumentado(["%PDF-1.7\nficticio"]);
  const { deps, calls } = fake({
    admin: [
      { data: estado("pendiente"), error: null },
      {
        data: estado("procesando", {
          adquirido: true,
          lease_token: LEASE_TOKEN,
          snapshot: SNAPSHOT,
          renderizado_en: "2026-08-17T20:00:00Z",
        }),
        error: null,
      },
      {
        data: estado("error_reintentable", { reintentable: true }),
        error: null,
      },
    ],
    render: { blob, bytes: blob.size, sha256: "0".repeat(64) },
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 503, "render inválido recuperable");
  igual(materializaciones, 0, "el tamaño se comprueba antes del arrayBuffer");
  igual(calls.includes("upload"), false, "no sube un render fuera del límite");
});

function request(
  body: unknown,
  headers: Record<string, string> = {},
): Request {
  return new Request(
    "https://project.supabase.co/functions/v1/crm-contrato-pdf-v2",
    {
      method: "POST",
      headers: {
        Origin: ORIGIN,
        Authorization: "Bearer jwt-valido",
        "Content-Type": "application/json",
        ...headers,
      },
      body: typeof body === "string" ? body : JSON.stringify(body),
    },
  );
}

Deno.test("CORS permite que el portal invoque la Edge", async () => {
  const { deps, calls } = fake();
  const handler = crearHandlerContratoPdfV2(deps);

  for (const origin of ["https://miavance.com", "https://www.miavance.com"]) {
    const res = await handler(
      new Request(
        "https://project.supabase.co/functions/v1/crm-contrato-pdf-v2",
        {
          method: "OPTIONS",
          headers: {
            Origin: origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers":
              "authorization,apikey,content-type,x-client-info",
          },
        },
      ),
    );

    igual(res.status, 204, `preflight permitido para ${origin}`);
    igual(
      res.headers.get("Access-Control-Allow-Origin"),
      origin,
      `CORS responde con el origen exacto para ${origin}`,
    );
    igual(
      res.headers.get("Access-Control-Allow-Methods"),
      "POST, OPTIONS",
      "autoriza la invocación POST",
    );
  }

  igual(calls.length, 0, "el preflight no autentica ni toca backend");
});

Deno.test("v2 rechaza multipart y no autentica ni toca backend", async () => {
  const { deps, calls } = fake();
  const form = new FormData();
  form.set("contratoId", CONTRATO_ID);
  form.set("pdf", new Blob(["%PDF-1.7\nforjado"]), "contrato.pdf");
  const req = new Request("https://project/functions/v1/crm-contrato-pdf-v2", {
    method: "POST",
    headers: { Authorization: "Bearer jwt-valido" },
    body: form,
  });
  const res = await crearHandlerContratoPdfV2(deps)(req);
  igual(res.status, 415, "multipart no se acepta");
  igual(calls.length, 0, "rechazo ocurre antes de autenticación");
});

Deno.test("URL firmada conserva origen seguro y coincide con el path esperado", () => {
  const interna =
    `http://kong:8000/storage/v1/object/sign/contratos-generados/${PATH}?token=firma&download=false`;
  igual(
    normalizarUrlFirmadaV2(interna, "http://127.0.0.1:55321", PATH),
    `http://127.0.0.1:55321/storage/v1/object/sign/contratos-generados/${PATH}?token=firma&download=false`,
    "reescribe sólo el origen loopback",
  );
  igual(
    normalizarUrlFirmadaV2(
      interna,
      "https://project.supabase.co",
      `${CONTRATO_ID}/v2/${JOB_ID}/otro.pdf`,
    ),
    null,
    "rechaza una URL válida para otro objeto",
  );
});

Deno.test("v2 acepta solo las dos claves JSON y UUID canónico", async () => {
  for (
    const body of [
      { action: "ensure", contratoId: CONTRATO_ID, pdf: "%PDF" },
      { action: "ensure", contratoId: CONTRATO_ID, snapshot: SNAPSHOT },
      { action: "ensure", contratoId: CONTRATO_ID, sha256: "a".repeat(64) },
      { action: "ensure", contratoId: CONTRATO_ID, nombreArchivo: "x.pdf" },
      { action: "ensure", contratoId: CONTRATO_ID.toUpperCase() },
    ]
  ) {
    const { deps, calls } = fake();
    const res = await crearHandlerContratoPdfV2(deps)(request(body));
    igual(res.status, 400, `rechaza ${JSON.stringify(body)}`);
    igual(calls.length, 0, "no autentica una forma inválida");
  }
});

Deno.test("delete exige Admin/Superadmin antes de tocar Storage", async () => {
  const { deps, calls } = fake({
    admin: [{
      data: null,
      error: { code: "42501", message: "Solo Admin o Superadmin" },
    }],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "delete", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 403, "rol insuficiente");
  igual(
    calls.join("|"),
    "auth|admin:contrato_eliminacion_preparar",
    "no elimina objetos sin autorización",
  );
});

Deno.test("delete explica la conservación del historial F4 antes de tocar Storage", async () => {
  const mensaje =
    "El contrato forma parte del historial de inversiones; conserva el registro y utiliza la anulación comercial que corresponda";
  const { deps, calls } = fake({
    admin: [{ data: null, error: { code: "55000", message: mensaje } }],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "delete", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 409, "conflicto de conservación");
  igual((await res.json()).error, mensaje, "explica la alternativa comercial");
  igual(
    calls.join("|"),
    "auth|admin:contrato_eliminacion_preparar",
    "no entrega rutas ni elimina bytes",
  );
});

Deno.test("delete no filtra diagnósticos internos inesperados del backend", async () => {
  const { deps } = fake({
    admin: [{
      data: null,
      error: {
        code: "XX000",
        message: "relation private.secreta columna token_interno falló",
      },
    }],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "delete", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 503, "error inesperado es transitorio y opaco");
  const json = await res.json();
  igual(
    json.error,
    "No se pudo autorizar la eliminación del contrato",
    "usa diagnóstico público estable",
  );
  igual(
    JSON.stringify(json).includes("token_interno"),
    false,
    "no expone detalle privado",
  );
});

Deno.test("delete rechaza un manifiesto que apunte fuera del contrato", async () => {
  const { deps, calls } = fake({
    admin: [{
      data: {
        contrato_id: CONTRATO_ID,
        token: LEASE_TOKEN,
        objetos: [{
          bucket: "documentos",
          path: "otro-contrato/anexo.pdf",
        }],
      },
      error: null,
    }],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "delete", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 409, "manifiesto incoherente");
  igual(calls.some((call) => call.startsWith("remove:")), false, "no borra");
  igual(
    calls.includes("admin:contrato_eliminacion_finalizar"),
    false,
    "no finaliza",
  );
});

Deno.test("delete elimina ambos buckets y después confirma la fila", async () => {
  const documento = `${CONTRATO_ID}/1700000000000_anexo.pdf`;
  const { deps, calls } = fake({
    admin: [
      {
        data: {
          contrato_id: CONTRATO_ID,
          token: LEASE_TOKEN,
          objetos: [
            { bucket: "contratos-generados", path: PATH },
            { bucket: "documentos", path: documento },
          ],
        },
        error: null,
      },
      {
        data: {
          ok: true,
          contrato_id: CONTRATO_ID,
          objetos_eliminados: 2,
        },
        error: null,
      },
    ],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "delete", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 200, "borrado completo");
  igual(
    calls.join("|"),
    "auth|admin:contrato_eliminacion_preparar|remove:contratos-generados:1|remove:documentos:1|admin:contrato_eliminacion_finalizar",
    "Storage precede al hard-delete",
  );
  const json = await res.json();
  igual(json.ok, true, "respuesta confirma");
  igual(json.archivosEliminados, 2, "reporta objetos");
});

Deno.test("delete no finaliza la base si Storage falla", async () => {
  const { deps, calls } = fake({
    admin: [{
      data: {
        contrato_id: CONTRATO_ID,
        token: LEASE_TOKEN,
        objetos: [{ bucket: "contratos-generados", path: PATH }],
      },
      error: null,
    }],
    deleteError: { code: "STORAGE_DOWN", message: "caído" },
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "delete", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 503, "Storage es requisito");
  igual(
    calls.includes("admin:contrato_eliminacion_finalizar"),
    false,
    "contrato queda para reintento",
  );
});

Deno.test("status sellado verifica bytes y hash antes de firmar", async () => {
  const blob = new Blob(["%PDF-1.7\nlegal"], { type: "application/pdf" });
  const hash = await sha256(blob);
  const archivo = {
    contrato_id: CONTRATO_ID,
    job_id: JOB_ID,
    storage_bucket: "contratos-generados",
    storage_path: PATH,
    nombre_archivo: "Contrato-2026-01-000777.pdf",
    sha256: hash,
    bytes: blob.size,
    template_version: CONTRATO_PDF_TEMPLATE_VERSION,
    generado_en: "2026-08-17T20:00:00Z",
  };
  const { deps, calls } = fake({
    actor: [{
      data: estado("sellado", { sha256: hash, bytes: blob.size, archivo }),
      error: null,
    }],
    downloads: [blob],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "status", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 200, "status válido");
  assert(
    calls.indexOf("download") < calls.indexOf("sign"),
    "verifica antes de firmar",
  );
  const json = await res.json();
  igual(json.url, "https://storage.example.test/firma", "entrega URL firmada");
});

Deno.test("status conserva descarga de PDFs v2 históricos ya sellados", async () => {
  const blob = new Blob(["%PDF-1.7\nhistorico-v2"], {
    type: "application/pdf",
  });
  const hash = await sha256(blob);
  const templateVersion = "contrato-aep-17-v2";
  const archivo = {
    contrato_id: CONTRATO_ID,
    job_id: JOB_ID,
    storage_bucket: "contratos-generados",
    storage_path: PATH,
    nombre_archivo: "Contrato-2026-01-000777.pdf",
    sha256: hash,
    bytes: blob.size,
    template_version: templateVersion,
    generado_en: "2026-08-17T20:00:00Z",
  };
  const { deps, calls } = fake({
    actor: [{
      data: estado("sellado", {
        template_version: templateVersion,
        sha256: hash,
        bytes: blob.size,
        archivo,
      }),
      error: null,
    }],
    downloads: [blob],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "status", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 200, "histórico v2 legible");
  assert(
    calls.indexOf("download") < calls.indexOf("sign"),
    "también verifica el histórico antes de firmar",
  );
});

Deno.test("status conserva descarga de PDFs v5 históricos ya sellados", async () => {
  const blob = new Blob(["%PDF-1.7\nhistorico-v5"], {
    type: "application/pdf",
  });
  const hash = await sha256(blob);
  const templateVersion = "contrato-aep-17-v5";
  const archivo = {
    contrato_id: CONTRATO_ID,
    job_id: JOB_ID,
    storage_bucket: "contratos-generados",
    storage_path: PATH,
    nombre_archivo: "Contrato-2026-01-000777.pdf",
    sha256: hash,
    bytes: blob.size,
    template_version: templateVersion,
    generado_en: "2026-08-17T20:00:00Z",
  };
  const { deps, calls } = fake({
    actor: [{
      data: estado("sellado", {
        template_version: templateVersion,
        sha256: hash,
        bytes: blob.size,
        archivo,
      }),
      error: null,
    }],
    downloads: [blob],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "status", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 200, "histórico v5 legible bajo la constante v7");
  assert(
    calls.indexOf("download") < calls.indexOf("sign"),
    "también verifica el histórico antes de firmar",
  );
});

Deno.test("status conserva descarga de PDFs v6 históricos ya sellados", async () => {
  const blob = new Blob(["%PDF-1.7\nhistorico-v6"], {
    type: "application/pdf",
  });
  const hash = await sha256(blob);
  const templateVersion = "contrato-aep-17-v6";
  const archivo = {
    contrato_id: CONTRATO_ID,
    job_id: JOB_ID,
    storage_bucket: "contratos-generados",
    storage_path: PATH,
    nombre_archivo: "Contrato-2026-01-000777.pdf",
    sha256: hash,
    bytes: blob.size,
    template_version: templateVersion,
    generado_en: "2026-08-17T20:00:00Z",
  };
  const { deps, calls } = fake({
    actor: [{
      data: estado("sellado", {
        template_version: templateVersion,
        sha256: hash,
        bytes: blob.size,
        archivo,
      }),
      error: null,
    }],
    downloads: [blob],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "status", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 200, "histórico v6 legible bajo la constante v7");
  assert(
    calls.indexOf("download") < calls.indexOf("sign"),
    "también verifica el histórico antes de firmar",
  );
});

Deno.test("status jamás firma un objeto cuyo fingerprint diverge", async () => {
  const esperado = new Blob(["%PDF-1.7\nesperado"]);
  const corrupto = new Blob(["%PDF-1.7\ncorrupto"]);
  const hash = await sha256(esperado);
  const archivo = {
    contrato_id: CONTRATO_ID,
    job_id: JOB_ID,
    storage_bucket: "contratos-generados",
    storage_path: PATH,
    nombre_archivo: "Contrato-2026-01-000777.pdf",
    sha256: hash,
    bytes: esperado.size,
    template_version: CONTRATO_PDF_TEMPLATE_VERSION,
    generado_en: "2026-08-17T20:00:00Z",
  };
  const { deps, calls } = fake({
    actor: [{
      data: estado("sellado", { sha256: hash, bytes: esperado.size, archivo }),
      error: null,
    }],
    downloads: [corrupto],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "status", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 409, "divergencia es integridad");
  igual(calls.includes("sign"), false, "no firma objeto corrupto");
});

Deno.test("sin_reserva conserva exactamente sus nulls públicos", async () => {
  const sinReserva = {
    contrato_id: CONTRATO_ID,
    job_id: null,
    estado: "sin_reserva",
    storage_bucket: "contratos-generados",
    storage_path: null,
    nombre_archivo: null,
    template_version: null,
    intentos: 0,
    lease_expira_en: null,
    reintentable: true,
    sha256: null,
    bytes: null,
    archivo: null,
  };
  const { deps } = fake({
    actor: [{ data: sinReserva, error: null }],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "status", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 202, "aún no existe reserva");
  const json = await res.json();
  igual(
    JSON.stringify(json),
    JSON.stringify({ pdf: sinReserva }),
    "shape exacto",
  );
});

// ── Régimen documental anterior (2026-08-20) ────────────────────────────────
// Un contrato firmado antes del 19/08 ya tiene su contrato, del formato previo:
// la RPC responde `sin_reserva` con `reintentable: false` y NO crea job. Antes
// esta forma se descartaba entera (parseEstado exigía `reintentable === true`),
// lo que habría devuelto 502 y roto el detalle de todo contrato antiguo.
Deno.test("régimen anterior: sin_reserva no reintentable se acepta y no reclama", async () => {
  const regimenAnterior = {
    contrato_id: CONTRATO_ID,
    job_id: null,
    estado: "sin_reserva",
    storage_bucket: "contratos-generados",
    storage_path: null,
    nombre_archivo: null,
    template_version: null,
    intentos: 0,
    lease_expira_en: null,
    reintentable: false,
    sha256: null,
    bytes: null,
    archivo: null,
  };
  const { deps, calls } = fake({
    admin: [{ data: regimenAnterior, error: null }],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 202, "no hay documento, y no lo va a haber");
  const json = await res.json();
  igual(
    JSON.stringify(json),
    JSON.stringify({ pdf: regimenAnterior }),
    "shape exacto",
  );
  // Reclamar levantaría P0002 y el vendedor vería «No se pudo reclamar el job
  // PDF» en vez de la razón. No debe ni intentarse.
  igual(
    calls.includes("admin:contrato_pdf_reclamar"),
    false,
    "no se reclama un job que no existe",
  );
  igual(calls.includes("render"), false, "no se renderiza nada");
});

Deno.test("ensure renderiza server-side, sube sin reemplazar, verifica y sella", async () => {
  const blob = new Blob(["%PDF-1.7\nserver"], { type: "application/pdf" });
  const hash = await sha256(blob);
  const claim = estado("procesando", {
    adquirido: true,
    lease_token: LEASE_TOKEN,
    snapshot: SNAPSHOT,
    renderizado_en: "2026-08-17T20:00:00Z",
  });
  const archivo = {
    contrato_id: CONTRATO_ID,
    job_id: JOB_ID,
    storage_bucket: "contratos-generados",
    storage_path: PATH,
    nombre_archivo: "Contrato-2026-01-000777.pdf",
    sha256: hash,
    bytes: blob.size,
    template_version: CONTRATO_PDF_TEMPLATE_VERSION,
    generado_en: "2026-08-17T20:00:00Z",
  };
  const { deps, calls } = fake({
    admin: [
      { data: estado("pendiente"), error: null },
      { data: claim, error: null },
      {
        data: estado("subido_verificado", { sha256: hash, bytes: blob.size }),
        error: null,
      },
      {
        data: estado("sellado", { sha256: hash, bytes: blob.size, archivo }),
        error: null,
      },
    ],
    render: { blob, sha256: hash, bytes: blob.size },
    downloads: [blob],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 200, "sellado exitoso");
  igual(
    calls.join("|"),
    "auth|admin:contrato_pdf_reservar|admin:contrato_pdf_reclamar|render|upload|download|admin:contrato_pdf_marcar_subido|admin:contrato_pdf_finalizar|sign",
    "protocolo ordenado sin I/O dentro de RPC",
  );
});

Deno.test("ensure recupera conflicto sólo si los bytes son idénticos", async () => {
  const blob = new Blob(["%PDF-1.7\ndeterminista"]);
  const hash = await sha256(blob);
  const claim = estado("procesando", {
    adquirido: true,
    lease_token: LEASE_TOKEN,
    snapshot: SNAPSHOT,
    renderizado_en: "2026-08-17T20:00:00Z",
  });
  const archivo = {
    contrato_id: CONTRATO_ID,
    job_id: JOB_ID,
    storage_bucket: "contratos-generados",
    storage_path: PATH,
    nombre_archivo: "Contrato-2026-01-000777.pdf",
    sha256: hash,
    bytes: blob.size,
    template_version: CONTRATO_PDF_TEMPLATE_VERSION,
    generado_en: "2026-08-17T20:00:00Z",
  };
  const { deps, calls } = fake({
    admin: [
      { data: estado("pendiente"), error: null },
      { data: claim, error: null },
      {
        data: estado("subido_verificado", { sha256: hash, bytes: blob.size }),
        error: null,
      },
      {
        data: estado("sellado", {
          sha256: hash,
          bytes: blob.size,
          archivo,
        }),
        error: null,
      },
    ],
    render: { blob, sha256: hash, bytes: blob.size },
    uploadError: {
      code: "Duplicate",
      message: "The resource already exists",
      statusCode: 409,
    },
    downloads: [blob, blob],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 200, "recuperación converge");
  assert(
    calls.includes("admin:contrato_pdf_finalizar"),
    "finaliza objeto idéntico",
  );
});

for (const caso of ["identico", "ausente", "no_disponible", "divergente"]) {
  Deno.test(`reintento recupera objeto previo de forma segura: ${caso}`, async () => {
    const blob = new Blob(["%PDF-1.7\noficial"]);
    const hash = await sha256(blob);
    const archivo = {
      contrato_id: CONTRATO_ID,
      job_id: JOB_ID,
      storage_bucket: "contratos-generados",
      storage_path: PATH,
      nombre_archivo: "Contrato-2026-01-000777.pdf",
      sha256: hash,
      bytes: blob.size,
      template_version: CONTRATO_PDF_TEMPLATE_VERSION,
      generado_en: "2026-08-17T20:00:00Z",
    };
    const exito = caso === "identico" || caso === "ausente";
    const { deps, calls } = fake({
      admin: [
        {
          data: estado("error_reintentable", { reintentable: true }),
          error: null,
        },
        {
          data: estado("procesando", {
            intentos: 2,
            adquirido: true,
            lease_token: LEASE_TOKEN,
            snapshot: SNAPSHOT,
            renderizado_en: "2026-08-17T20:00:00Z",
          }),
          error: null,
        },
        ...exito
          ? [
            {
              data: estado("subido_verificado", {
                sha256: hash,
                bytes: blob.size,
              }),
              error: null,
            },
            {
              data: estado("sellado", {
                sha256: hash,
                bytes: blob.size,
                archivo,
              }),
              error: null,
            },
          ]
          : [{
            data: caso === "divergente"
              ? estado("integridad_bloqueada", {
                ok: false,
                codigo: "PDF_INTEGRIDAD_BLOQUEADA",
              })
              : estado("error_reintentable", { reintentable: true }),
            error: null,
          }],
      ],
      render: { blob, sha256: hash, bytes: blob.size },
      downloads: caso === "identico"
        ? [blob]
        : caso === "ausente"
        ? [null, blob]
        : caso === "divergente"
        ? [new Blob(["%PDF-1.7\nalterado"])]
        : [null],
      downloadError: caso === "ausente"
        ? { statusCode: 404, code: "NoSuchKey" }
        : { statusCode: 503, code: "TEMPORAL" },
    });
    const res = await crearHandlerContratoPdfV2(deps)(
      request({ action: "ensure", contratoId: CONTRATO_ID }),
    );
    igual(
      res.status,
      exito ? 200 : caso === "divergente" ? 409 : 503,
      "estado coherente con el objeto recuperado",
    );
    igual(
      calls.includes("upload"),
      caso === "ausente",
      "solo ausencia comprobada permite subir de nuevo",
    );
    igual(
      calls.includes("admin:contrato_pdf_finalizar"),
      exito,
      "no se sella un objeto divergente o no disponible",
    );
  });
}

Deno.test("ensure bloquea integridad si el objeto existente difiere", async () => {
  const render = new Blob(["%PDF-1.7\noficial"]);
  const otro = new Blob(["%PDF-1.7\notro"]);
  const hash = await sha256(render);
  const claim = estado("procesando", {
    adquirido: true,
    lease_token: LEASE_TOKEN,
    snapshot: SNAPSHOT,
    renderizado_en: "2026-08-17T20:00:00Z",
  });
  const { deps, calls } = fake({
    admin: [
      { data: estado("pendiente"), error: null },
      { data: claim, error: null },
      {
        data: estado("integridad_bloqueada", {
          ok: false,
          codigo: "PDF_INTEGRIDAD_BLOQUEADA",
        }),
        error: null,
      },
    ],
    render: { blob: render, sha256: hash, bytes: render.size },
    uploadError: {
      code: "Duplicate",
      message: "already exists",
      statusCode: 409,
    },
    downloads: [otro],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 409, "integridad bloqueada");
  assert(
    calls.includes("admin:contrato_pdf_marcar_error"),
    "registra código de integridad",
  );
  igual(
    calls.includes("admin:contrato_pdf_finalizar"),
    false,
    "no sella bytes distintos",
  );
  igual(calls.includes("sign"), false, "no firma bytes distintos");
  const json = await res.json();
  igual("ok" in json.pdf, false, "no filtra marcador SQL interno");
  igual("codigo" in json.pdf, false, "shape público permanece estricto");
});

Deno.test("ensure sin lease responde pendiente y no hace I/O", async () => {
  const { deps, calls } = fake({
    admin: [
      { data: estado("procesando"), error: null },
      { data: estado("procesando", { adquirido: false }), error: null },
    ],
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 202, "otro worker conserva el lease");
  igual(calls.includes("render"), false, "no renderiza sin lease");
  igual(calls.includes("upload"), false, "no toca Storage sin lease");
});

Deno.test("error de renderer se clasifica reintentable y libera lease", async () => {
  const claim = estado("procesando", {
    adquirido: true,
    lease_token: LEASE_TOKEN,
    snapshot: SNAPSHOT,
    renderizado_en: "2026-08-17T20:00:00Z",
  });
  const { deps, calls } = fake({
    admin: [
      { data: estado("pendiente"), error: null },
      { data: claim, error: null },
      {
        data: estado("error_reintentable", { reintentable: true }),
        error: null,
      },
    ],
    render: new Error("falló pdfmake con detalle privado"),
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 503, "error transitorio");
  assert(calls.includes("admin:contrato_pdf_marcar_error"), "libera lease");
});

Deno.test("snapshot server-side inválido se clasifica como integridad", async () => {
  const claim = estado("procesando", {
    adquirido: true,
    lease_token: LEASE_TOKEN,
    snapshot: SNAPSHOT,
    renderizado_en: "2026-08-17T20:00:00+00:00",
  });
  const bloqueado = estado("integridad_bloqueada", {
    ok: false,
    codigo: "PDF_INTEGRIDAD_BLOQUEADA",
  });
  const { deps } = fake({
    admin: [
      { data: estado("pendiente"), error: null },
      { data: claim, error: null },
      { data: bloqueado, error: null },
    ],
    render: new TypeError("snapshot privado inválido"),
  });
  const res = await crearHandlerContratoPdfV2(deps)(
    request({ action: "ensure", contratoId: CONTRATO_ID }),
  );
  igual(res.status, 409, "no se reintenta un snapshot inmutable inválido");
  const json = await res.json();
  igual("ok" in json.pdf, false, "no expone extras del backend");
  igual("codigo" in json.pdf, false, "contrato público exacto");
});

Deno.test("body sin Content-Length también se limita antes de auth", async () => {
  const { deps, calls } = fake();
  const body = JSON.stringify({
    action: "ensure",
    contratoId: CONTRATO_ID,
    relleno: "x".repeat(4096),
  });
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new TextEncoder().encode(body));
      controller.close();
    },
  });
  const req = new Request(
    "https://project/functions/v1/crm-contrato-pdf-v2",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer jwt-valido",
        "Content-Type": "application/json",
      },
      body: stream,
    },
  );
  const res = await crearHandlerContratoPdfV2(deps)(req);
  igual(res.status, 413, "límite efectivo sin cabecera");
  igual(calls.length, 0, "no autentica ni toca backend");
});
