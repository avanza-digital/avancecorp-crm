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
  igual(resultado.firmaBytes, 26588, "tamaño firma del ASOCIANTE");
});

Deno.test("template v7 reproduce la firma y numeración del modelo", () => {
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
  }, {
    fondo: "data:image/png;base64,fondo",
    firmaAsociante: "data:image/png;base64,firma-kirk",
  });
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
      "DIECIOCHO POR CIENTO (18.00 %)",
      "UN (1) AÑO",
    ]
  ) {
    assert(contenido.includes(fragmento), `contenido v3 ausente: ${fragmento}`);
  }

  assert(!contenido.includes("trece por ciento"), "retira la regla anterior");
  assert(
    !contenido.includes("identificado con DNI N.°"),
    "el contrato actualizado no publica el DNI del analista",
  );
  assert(
    contenido.includes('"image":"data:image/png;base64,firma-kirk"'),
    "incrusta la firma original de Kirk en el cuerpo",
  );
  assert(
    contenido.includes(
      '"cover":{"width":93,"height":65,"align":"center","valign":"center"}',
    ),
    "recorta proporcionalmente la firma como el modelo Word",
  );
  for (
    const linea of [
      "AVANCE CORP SAC",
      "RUC N° 20611392088",
      "EL ASOCIANTE",
    ]
  ) {
    assert(
      contenido.includes(
        `"text":${
          JSON.stringify(linea)
        },"bold":true,"alignment":"center","fontSize":10.5`,
      ),
      `línea corporativa ausente en la firma de Kirk: ${linea}`,
    );
  }
  for (
    const [clausula, cantidad] of [
      [1, 4],
      [2, 4],
      [3, 11],
      [4, 5],
      [5, 3],
      [6, 3],
      [7, 2],
      [8, 6],
      [9, 2],
      [10, 5],
      [12, 3],
      [13, 3],
      [14, 3],
      [15, 3],
      [16, 3],
      [17, 2],
    ] as const
  ) {
    for (let numeral = 1; numeral <= cantidad; numeral += 1) {
      assert(
        contenido.includes(
          `"text":"${clausula}.${numeral}","noWrap":true`,
        ),
        `numeral contractual ausente: ${clausula}.${numeral}`,
      );
    }
  }
  for (const inciso of ["a)", "b)", "c)", "d)", "e)"]) {
    igual(
      contenido.split(`"text":"${inciso}","noWrap":true`).length - 1,
      2,
      `los incisos ${inciso} aparecen en las cláusulas 11 y 13`,
    );
  }
  for (
    const dato of [
      "Kirk Edilberto Sánchez Ríos",
      "DNI N° 44232474",
      SNAPSHOT.titular.nombreCompleto,
      "DNI N° 45781234",
      SNAPSHOT.titular.domicilio.toUpperCase(),
      SNAPSHOT.titular.correo,
      SNAPSHOT.analista.nombreCompleto,
      SNAPSHOT.analista.celular,
      SNAPSHOT.analista.correo,
      "S/ 15,000.00 (QUINCE MIL Y 00/100 SOLES)",
      "DIECIOCHO POR CIENTO (18.00 %)",
      "UN (1) AÑO",
    ]
  ) {
    assert(
      contenido.includes(`\"text\":${JSON.stringify(dato)},\"bold\":true`),
      `dato personal sin negrita: ${dato}`,
    );
  }
  assert(
    contenido.includes('"margin":[0,24,0,5]'),
    "separa el último párrafo del bloque de firmas",
  );
});

Deno.test("template v7 respeta vencimientos ajustados al fin de mes", () => {
  const construirConFechas = (
    fechaInicio: string,
    fechaVencimiento: string,
  ) => {
    const definicion = construirContratoPdf({
      contrato: {
        numero: SNAPSHOT.contrato.numero,
        capital: SNAPSHOT.contrato.capital,
        moneda: "PEN",
        porcentaje: SNAPSHOT.contrato.porcentaje,
        fechaInicio,
        fechaVencimiento,
      },
      titular: {
        nombreCompleto: SNAPSHOT.titular.nombreCompleto,
        tipoDocumento: "DNI",
        documento: SNAPSHOT.titular.documento,
        domicilio: SNAPSHOT.titular.domicilio,
        correo: SNAPSHOT.titular.correo,
      },
      analista: SNAPSHOT.analista,
    }, {
      fondo: "data:image/png;base64,fondo",
      firmaAsociante: "data:image/png;base64,firma-kirk",
    });
    return JSON.stringify(definicion.content);
  };

  const finDeMes = construirConFechas("2026-08-31", "2027-02-28");
  assert(finDeMes.includes("SEIS (6) MESES"), "31/08 + 6 meses es 28/02");
  assert(!finDeMes.includes("CINCO (5) MESES"), "no descuenta el mes ajustado");

  const febreroBisiesto = construirConFechas("2027-08-31", "2028-02-29");
  assert(
    febreroBisiesto.includes("SEIS (6) MESES"),
    "31/08 + 6 meses es 29/02 en año bisiesto",
  );

  const incompleto = construirConFechas("2026-08-31", "2027-02-27");
  assert(
    incompleto.includes("CINCO (5) MESES"),
    "no redondea un plazo incompleto",
  );

  const bisiesto = construirConFechas("2024-02-29", "2025-02-28");
  assert(bisiesto.includes("UN (1) AÑO"), "ajusta el aniversario bisiesto");
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

Deno.test("PdfPrinter produce dos PDFs v7 byte-idénticos con fecha fija", async () => {
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
    "88665f229db49280603d4d0ed7c0e260360e605dfc3d9acc4b0f4a0e092a58b2",
    "golden byte a byte del template v7",
  );
  igual(primero.bytes, 871757, "tamaño golden del template v7");
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
