import {
  CONTRATO_PDF_RENDERER_VERSION,
  PDFMAKE_VENDOR_SHA256,
  renderizarContratoPdfV2,
  validarSnapshotContratoV2,
  verificarAssetsContratoPdfV2,
  VFS_VENDOR_SHA256,
} from "./renderer.ts";
import { CONTRATO_PDF_TEMPLATE_VERSION } from "./handler.ts";
import { construirContratoPdf } from "./template-v2.ts";

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

const SNAPSHOT = {
  snapshotVersion: 2,
  contrato: {
    id: "8fffe71c-0abc-4c36-90fa-79fcbf4c3941",
    numero: "2026-01-000777",
    clienteId: "44444444-4444-4444-8444-444444444444",
    capital: 15000,
    moneda: "PEN",
    porcentaje: 18,
    modalidad: "mensual",
    tipoInteres: "simple",
    categoria: "nuevo",
    fechaInicio: "2026-08-17",
    fechaVencimiento: "2027-08-17",
    productoCondicionId: null,
    creadoPor: "11111111-1111-4111-8111-111111111111",
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
    id: "11111111-1111-4111-8111-111111111111",
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
    origen: "contrato",
  },
};

async function sha256Bytes(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    ) as ArrayBuffer,
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("renderer v2 valida el snapshot SQL exacto y rechaza deriva", () => {
  const validado = validarSnapshotContratoV2(SNAPSHOT);
  igual(validado.snapshotVersion, 2, "versión de snapshot");
  igual(validado.contrato.numero, "2026-01-000777", "número contractual");

  const extra = structuredClone(SNAPSHOT) as Record<string, unknown>;
  extra.pdf = "%PDF-1.7 forjado";
  let rechazo = false;
  try {
    validarSnapshotContratoV2(extra);
  } catch {
    rechazo = true;
  }
  assert(rechazo, "rechaza claves fuera del snapshot SQL");

  const control = structuredClone(SNAPSHOT);
  control.titular.domicilio = "Av. válida\u0000oculto";
  rechazo = false;
  try {
    validarSnapshotContratoV2(control);
  } catch {
    rechazo = true;
  }
  assert(rechazo, "rechaza controles en texto legal");
});

Deno.test("assets legales v2 conservan los SHA versionados", async () => {
  const resultado = await verificarAssetsContratoPdfV2();
  igual(resultado.ok, true, "assets íntegros");
  igual(resultado.fondoBytes, 108685, "tamaño fondo");
});

Deno.test("template v3 contiene el contrato actualizado y no incrusta firma", () => {
  const definicion = construirContratoPdf({
    contrato: {
      numero: SNAPSHOT.contrato.numero,
      capital: SNAPSHOT.contrato.capital,
      moneda: "PEN",
      porcentaje: SNAPSHOT.contrato.porcentaje,
      fechaInicio: SNAPSHOT.contrato.fechaInicio,
      fechaVencimiento: SNAPSHOT.contrato.fechaVencimiento,
    },
    titular: {
      nombreCompleto: SNAPSHOT.titular.nombreCompleto,
      tipoDocumento: "DNI",
      documento: SNAPSHOT.titular.documento,
      domicilio: SNAPSHOT.titular.domicilio,
      correo: SNAPSHOT.titular.correo,
    },
    analista: SNAPSHOT.analista,
  }, { fondo: "data:image/png;base64," });
  const contenido = JSON.stringify(definicion.content);

  for (
    const fragmento of [
      "EL ASOCIADO participa, mediante la contribución prevista en la cláusula tercera",
      "no tendrá derecho a percibir participación alguna",
      "se reducirá excepcionalmente al diez por ciento (10.00 %)",
      "plazo máximo de treinta (30) días hábiles",
      "dentro de un plazo máximo de siete (7) días hábiles contados desde dicho vencimiento",
      "EL ASOCIADO contará con un Analista Comercial encargado de brindarle atención",
      "resultados económicos del presente contrato se encuentran vinculados",
      "AVANCE CORP SAC",
      "RUC N° 20611392088",
      "dieciocho por ciento (18.00 %)",
    ]
  ) {
    assert(contenido.includes(fragmento), `contenido v3 ausente: ${fragmento}`);
  }

  assert(!contenido.includes("trece por ciento"), "retira la regla anterior");
  assert(
    !contenido.includes("identificado con DNI N.°"),
    "el contrato actualizado no publica el DNI del analista",
  );
  assert(!contenido.includes('"image"'), "no incrusta una firma en el cuerpo");
});

Deno.test("PdfPrinter y VFS vendorizados conservan su fingerprint", async () => {
  const pdfmake = await Deno.readFile(
    new URL("./pdfmake-0.2.20-pdfprinter.js", import.meta.url),
  );
  const vfs = await Deno.readFile(
    new URL("./vfs-fonts-0.2.20.js", import.meta.url),
  );
  igual(await sha256Bytes(pdfmake), PDFMAKE_VENDOR_SHA256, "vendor PdfPrinter");
  igual(await sha256Bytes(vfs), VFS_VENDOR_SHA256, "vendor VFS");
});

Deno.test("PdfPrinter produce dos PDFs v3 byte-idénticos con fecha fija", async () => {
  igual(
    CONTRATO_PDF_RENDERER_VERSION,
    CONTRATO_PDF_TEMPLATE_VERSION,
    "renderer y protocolo versionados juntos",
  );
  const fecha = "2026-08-17T20:00:00.000Z";
  const primero = await renderizarContratoPdfV2(SNAPSHOT, fecha);
  const segundo = await renderizarContratoPdfV2(SNAPSHOT, fecha);
  const formatoPostgres = await renderizarContratoPdfV2(
    SNAPSHOT,
    "2026-08-17T20:00:00+00:00",
  );
  igual(primero.bytes, primero.blob.size, "tamaño medido");
  igual(
    primero.sha256,
    "74f134a8b2cd04723cca0c36e237a9863dd782d75e07fc95eb5709dc6b3e0219",
    "golden byte a byte del template v3",
  );
  igual(primero.bytes, 843744, "tamaño golden del template v3");
  igual(primero.sha256, segundo.sha256, "hash determinista");
  igual(
    primero.sha256,
    formatoPostgres.sha256,
    "el timestamptz PostgreSQL fija el mismo instante",
  );
  igual(primero.bytes, segundo.bytes, "tamaño determinista");
  const a = new Uint8Array(await primero.blob.arrayBuffer());
  const b = new Uint8Array(await segundo.blob.arrayBuffer());
  igual(a.length, b.length, "misma longitud");
  assert(a.every((byte, indice) => byte === b[indice]), "igualdad byte a byte");
  igual(new TextDecoder().decode(a.slice(0, 5)), "%PDF-", "cabecera PDF");
});
