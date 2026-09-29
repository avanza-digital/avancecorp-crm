import {
  ANEXO_PDF_RENDERER_VERSION,
  CONTRATO_PDF_RENDERER_VERSION,
  PDFMAKE_VENDOR_SHA256,
  renderizarAnexoPdfV1,
  renderizarContratoPdfV2,
  validarSnapshotContratoV2,
  verificarAssetsContratoPdfV2,
  VFS_VENDOR_SHA256,
} from "./renderer.ts";
import {
  ANEXO_PDF_TEMPLATE_VERSION,
  CONTRATO_PDF_TEMPLATE_VERSION,
} from "./handler.ts";
import { construirContratoPdf } from "./template-v2.ts";
import { clasificarCronograma, construirAnexoPdf } from "./anexo-v1.ts";

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

for (const prefijo of ["2024-01-", "2025-01-", "2026-01-"]) {
  Deno.test(`PDF conserva la serie física ${prefijo} y los ceros iniciales`, async () => {
    const snapshot = structuredClone(SNAPSHOT);
    snapshot.contrato.numero = `${prefijo}000123`;
    const validado = validarSnapshotContratoV2(snapshot);
    igual(
      validado.contrato.numero,
      snapshot.contrato.numero,
      "número recibido",
    );
    const definicion = construirContratoPdf({
      contrato: {
        numero: validado.contrato.numero,
        capital: validado.contrato.capital,
        moneda: "PEN",
        porcentaje: validado.contrato.porcentaje,
        fechaInicio: validado.contrato.fechaInicio,
        fechaVencimiento: validado.contrato.fechaVencimiento,
      },
      titular: { ...SNAPSHOT.titular, tipoDocumento: "DNI" },
      analista: SNAPSHOT.analista,
    }, {
      fondo: "data:image/png;base64,fondo",
      firmaAsociante: "data:image/png;base64,firma-kirk",
    });
    assert(typeof definicion.header === "function", "cabecera dinámica");
    const cabecera = definicion.header(1, 1, {
      width: 595.28,
      height: 841.89,
      orientation: "portrait",
    });
    assert(
      JSON.stringify(cabecera).includes(snapshot.contrato.numero),
      "el documento imprime el número completo sin deducir el año de la fecha",
    );
    const pdf = await renderizarContratoPdfV2(snapshot, "2026-09-19T18:00:00Z");
    igual(
      new TextDecoder().decode((await pdf.blob.arrayBuffer()).slice(0, 5)),
      "%PDF-",
      "produce un PDF real con el número seleccionado",
    );
  });
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
  // Las imágenes se declaran UNA vez en el diccionario del documento y tanto el
  // cuerpo como el fondo las referencian por nombre: pasarlas como data URI en
  // cada página incrustaba el membrete tantas veces como hojas (4,5x el peso).
  const imagenes = JSON.stringify(definicion.images);
  assert(
    imagenes.includes('"firmaAsociante":"data:image/png;base64,firma-kirk"'),
    "incrusta la firma original de Kirk, declarada una sola vez",
  );
  assert(
    imagenes.includes('"fondoContrato":"data:image/png;base64,fondo"'),
    "declara el fondo una sola vez",
  );
  assert(
    contenido.includes('"image":"firmaAsociante"'),
    "el cuerpo referencia la firma por nombre",
  );
  const fondoPagina = (definicion.background as () => { image?: string })();
  assert(
    fondoPagina.image === "fondoContrato",
    "cada página referencia el fondo por nombre, no por data URI",
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

Deno.test("PdfPrinter produce dos PDFs v9 byte-idénticos con fecha fija", async () => {
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
    "6ffb935d939e4ba7f4c5822835d81cf6bac0a8b04bb1b011a1b629a9b1ffe1d8",
    "golden byte a byte del template v9 (sin co-titulares)",
  );
  igual(primero.bytes, 218672, "tamaño golden del template v9");
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

// ── Plantilla v9: co-titulares (cuenta mancomunada) ────────────────────────

const ASSETS_PRUEBA = {
  fondo: "data:image/png;base64,fondo",
  firmaAsociante: "data:image/png;base64,firma-kirk",
};

function cotitularesDePrueba(cantidad: number) {
  return Array.from({ length: cantidad }, (_, indice) => ({
    id: `77777777-7777-4777-8777-7777777777${
      String(indice + 1).padStart(2, "0")
    }`,
    orden: indice + 1,
    nombreCompleto: `COTITULAR PRUEBA ${indice + 1}`,
    tipoDocumento: "DNI" as const,
    documento: String(40000000 + indice + 1),
  }));
}

function datosConCotitulares(cantidad: number) {
  return {
    contrato: {
      numero: SNAPSHOT.contrato.numero,
      capital: SNAPSHOT.contrato.capital,
      moneda: "PEN" as const,
      porcentaje: SNAPSHOT.contrato.porcentaje,
      fechaInicio: SNAPSHOT.contrato.fechaInicio,
      fechaVencimiento: SNAPSHOT.contrato.fechaVencimiento,
    },
    titular: {
      nombreCompleto: SNAPSHOT.titular.nombreCompleto,
      tipoDocumento: "DNI" as const,
      documento: SNAPSHOT.titular.documento,
      domicilio: SNAPSHOT.titular.domicilio,
      correo: SNAPSHOT.titular.correo,
    },
    analista: SNAPSHOT.analista,
    cotitulares: cotitularesDePrueba(cantidad).map((cotitular) => ({
      nombreCompleto: cotitular.nombreCompleto,
      tipoDocumento: cotitular.tipoDocumento,
      documento: cotitular.documento,
    })),
  };
}

function contar(texto: string, aguja: string): number {
  return texto.split(aguja).length - 1;
}

/** El bloque de firmas es siempre el último nodo del contenido. */
function bloqueFirmasDe(
  definicion: { content: unknown },
): Record<string, unknown> {
  const contenido = definicion.content as Array<Record<string, unknown>>;
  return contenido[contenido.length - 1];
}

async function paginasDe(resultado: { blob: Blob }): Promise<number> {
  const bytes = new Uint8Array(await resultado.blob.arrayBuffer());
  const texto = new TextDecoder("latin1").decode(bytes).replace(
    /\/Type \/Pages/g,
    "",
  );
  return contar(texto, "/Type /Page");
}

const ROTULO_ASOCIADO =
  '"text":"EL ASOCIADO","bold":true,"alignment":"center","fontSize":10.5';
const RAYA_FIRMA = "____________________________";
const CIERRE_CONJUNTO =
  ", quienes actúan de manera conjunta y a quienes se les denominará EL ASOCIADO, bajo los términos y condiciones siguientes:";
const CIERRE_SINGULAR =
  ", a quien se le denominará EL ASOCIADO, bajo los términos y condiciones siguientes:";

Deno.test("template v9 nombra al co-titular en la comparecencia y lo hace firmar como EL ASOCIADO", () => {
  const con = JSON.stringify(
    construirContratoPdf(datosConCotitulares(1), ASSETS_PRUEBA).content,
  );
  const sin = JSON.stringify(
    construirContratoPdf(datosConCotitulares(0), ASSETS_PRUEBA).content,
  );

  assert(
    con.includes('"text":"COTITULAR PRUEBA 1","bold":true'),
    "nombre del co-titular en negrita",
  );
  assert(
    con.includes('"text":"DNI N° 40000001","bold":true'),
    "documento del co-titular en negrita",
  );
  assert(con.includes('"text":"; y "'), "conjunción antes del último");
  assert(con.includes(CIERRE_CONJUNTO), "cierre conjunto de la comparecencia");
  assert(
    !con.includes(CIERRE_SINGULAR),
    "el cierre singular desaparece con co-titulares",
  );
  igual(contar(con, ROTULO_ASOCIADO), 2, "dos rótulos EL ASOCIADO");
  igual(contar(con, RAYA_FIRMA), 2, "dos rayas de firma");
  igual(contar(con, '"text":"EL ASOCIANTE"'), 1, "Avance Corp firma una vez");
  assert(
    con.includes('"unbreakable":true,"margin":[0,24,0,5]'),
    "bloque de firmas indivisible con el margen de siempre",
  );
  const bloque = bloqueFirmasDe(
    construirContratoPdf(datosConCotitulares(1), ASSETS_PRUEBA),
  );
  igual(
    (bloque.stack as unknown[]).length,
    2,
    "fila del titular + fila del co-titular",
  );

  assert(sin.includes(CIERRE_SINGULAR), "sin co-titulares, cierre singular");
  assert(
    !sin.includes("actúan de manera conjunta"),
    "sin co-titulares no hay texto conjunto",
  );
  igual(contar(sin, ROTULO_ASOCIADO), 1, "un solo EL ASOCIADO");
  igual(contar(sin, RAYA_FIRMA), 1, "una sola raya");
});

Deno.test("template v9 hace caber cinco co-titulares (tope del CRM) en la hoja de firmas", async () => {
  const definicion = construirContratoPdf(
    datosConCotitulares(5),
    ASSETS_PRUEBA,
  );
  const bloque = bloqueFirmasDe(definicion);
  const texto = JSON.stringify(bloque);
  igual(
    (bloque.stack as unknown[]).length,
    4,
    "titular + Avance, y tres filas de pares",
  );
  igual(contar(texto, ROTULO_ASOCIADO), 6, "seis rótulos EL ASOCIADO");
  igual(contar(texto, RAYA_FIRMA), 6, "seis rayas de firma");
  assert(
    texto.includes('"text":"COTITULAR PRUEBA 5"'),
    "el quinto co-titular firma",
  );

  const fecha = "2026-08-17T20:00:00.000Z";
  const sin = await renderizarContratoPdfV2(SNAPSHOT, fecha);
  const con = await renderizarContratoPdfV2(
    { ...SNAPSHOT, cotitulares: cotitularesDePrueba(5) },
    fecha,
  );
  const paginasSin = await paginasDe(sin);
  const paginasCon = await paginasDe(con);
  assert(paginasSin >= 8, `el contrato base ocupa ${paginasSin} hojas`);
  assert(
    paginasCon <= paginasSin + 1,
    `cinco co-titulares añaden a lo sumo una hoja (${paginasSin} → ${paginasCon})`,
  );
});

// ── Anexo de cronograma (documento aparte, anexo-cronograma-v1) ─────────────

function cuota(
  numero: number,
  fecha: string,
  monto: number,
  tipo: string,
) {
  return {
    id: `55555555-5555-4555-8555-5555555555${String(numero).padStart(2, "0")}`,
    numeroCuota: numero,
    fechaProgramada: fecha,
    montoProgramado: monto,
    tipo,
  };
}

/** 12 cuotas mensuales de S/ 225 + retorno del capital 7 días tras el vencimiento. */
const CRONOGRAMA_SIMPLE = [
  ...[
    "2026-09-17",
    "2026-10-17",
    "2026-11-17",
    "2026-12-17",
    "2027-01-17",
    "2027-02-17",
    "2027-03-17",
    "2027-04-17",
    "2027-05-17",
    "2027-06-17",
    "2027-07-17",
    "2027-08-17",
  ].map((fecha, indice) => cuota(indice + 1, fecha, 225, "cuota")),
  cuota(13, "2027-08-24", 15000, "retorno"),
];

const SNAPSHOT_ANEXO = { ...SNAPSHOT, cronograma: CRONOGRAMA_SIMPLE };
const TITULAR_ANEXO = { ...SNAPSHOT.titular, tipoDocumento: "DNI" as const };

const ASSETS_ANEXO = {
  fondo: "data:image/png;base64,fondo",
  firmaAsociante: "data:image/png;base64,firma-kirk",
};

function textos(nodo: unknown, acumulado: string[] = []): string[] {
  if (Array.isArray(nodo)) {
    for (const hijo of nodo) textos(hijo, acumulado);
  } else if (nodo && typeof nodo === "object") {
    const objeto = nodo as Record<string, unknown>;
    if (typeof objeto.text === "string") acumulado.push(objeto.text);
    for (const clave of ["text", "stack", "columns", "table", "body"]) {
      if (clave in objeto) textos(objeto[clave], acumulado);
    }
  }
  return acumulado;
}

Deno.test("anexo v1 produce dos PDFs byte-idénticos con la fecha fija del sellado", async () => {
  igual(
    ANEXO_PDF_RENDERER_VERSION,
    ANEXO_PDF_TEMPLATE_VERSION,
    "renderer del anexo y handler versionados juntos",
  );
  const fecha = "2026-08-17T20:00:00.000Z";
  const primero = await renderizarAnexoPdfV1(SNAPSHOT_ANEXO, fecha);
  const segundo = await renderizarAnexoPdfV1(SNAPSHOT_ANEXO, fecha);
  igual(primero.bytes, primero.blob.size, "tamaño medido");
  igual(primero.sha256, segundo.sha256, "hash determinista");
  igual(primero.bytes, segundo.bytes, "tamaño determinista");
  igual(
    primero.sha256,
    "9639f4a48294c631434db945e2ae60057a8fd753b69389b1392ece00b71bc3dc",
    "golden byte a byte del anexo v1 (12 cuotas, sin co-titulares)",
  );
  igual(primero.bytes, 165463, "tamaño golden del anexo v1");
  igual(
    primero.nombreArchivo,
    "Anexo-2026-01-000777-CLIENTE-PRUEBA.pdf",
    "nombre del archivo del anexo",
  );
  const a = new Uint8Array(await primero.blob.arrayBuffer());
  igual(new TextDecoder().decode(a.slice(0, 5)), "%PDF-", "cabecera PDF");
});

Deno.test("anexo v1 no altera el contrato v9: mismo golden con o sin anexo cargado", async () => {
  const contrato = await renderizarContratoPdfV2(
    SNAPSHOT,
    "2026-08-17T20:00:00.000Z",
  );
  igual(
    contrato.sha256,
    "6ffb935d939e4ba7f4c5822835d81cf6bac0a8b04bb1b011a1b629a9b1ffe1d8",
    "el contrato sigue siendo byte a byte la v9",
  );
  igual(contrato.bytes, 218672, "tamaño golden v9 intacto");
});

Deno.test("anexo v1 imprime las parciales del cronograma sellado y el retorno como liquidación final", () => {
  const definicion = construirAnexoPdf(
    {
      contrato: {
        numero: "2026-01-000777",
        capital: 15000,
        moneda: "PEN",
        modalidad: "mensual",
        tipoInteres: "simple",
        fechaInicio: "2026-08-17",
        fechaVencimiento: "2027-08-17",
      },
      titular: TITULAR_ANEXO,
      analista: { nombreCompleto: "ANALISTA PRUEBA" },
      cotitulares: [{
        nombreCompleto: "COTITULAR PRUEBA UNO",
        tipoDocumento: "DNI",
        documento: "40000001",
      }],
      cronograma: CRONOGRAMA_SIMPLE,
    },
    ASSETS_ANEXO,
  );
  const plano = textos(definicion.content).join("\n");
  assert(plano.startsWith("ANEXO\n"), "título ANEXO");
  assert(
    plano.includes("CLIENTE PRUEBA\n y \nCOTITULAR PRUEBA UNO"),
    "nombra al titular y al co-titular en la introducción",
  );
  assert(
    plano.includes("17 de septiembre de 2026"),
    "primera liquidación parcial",
  );
  assert(
    plano.includes("17 de agosto de 2027"),
    "última parcial (y vencimiento)",
  );
  igual(
    (plano.match(/S\/ 225\.00/g) ?? []).length,
    12,
    "doce participaciones de S/ 225.00",
  );
  assert(
    plano.includes("24 de agosto de 2027"),
    "la liquidación final usa la fila retorno",
  );
  igual(
    (plano.match(/S\/ 15,000\.00/g) ?? []).length,
    2,
    "la contribución aparece en datos y en la restitución",
  );
  assert(plano.includes("Mensual"), "modalidad legible");
  assert(
    plano.includes("numeral 5.3 del contrato"),
    "remite al 5.3 del contrato",
  );
  assert(
    plano.includes("EL ASOCIADO") && plano.includes("EL ASOCIANTE") &&
      plano.includes("RUC N° 20611392088"),
    "bloque de firmas de las dos partes",
  );
  igual(
    (plano.match(/EL ASOCIADO$/gm) ?? []).length,
    2,
    "firman el titular y el co-titular",
  );
});

Deno.test("anexo v1: interés compuesto lista la única liquidación al vencimiento", () => {
  const definicion = construirAnexoPdf(
    {
      contrato: {
        numero: "2026-01-000778",
        capital: 15000,
        moneda: "USD",
        modalidad: "mensual",
        tipoInteres: "compuesto",
        fechaInicio: "2026-08-17",
        fechaVencimiento: "2027-08-17",
      },
      titular: TITULAR_ANEXO,
      analista: { nombreCompleto: "ANALISTA PRUEBA" },
      cotitulares: [],
      cronograma: [
        cuota(1, "2027-08-17", 2700, "devolucion"),
        cuota(2, "2027-08-24", 15000, "retorno"),
      ],
    },
    ASSETS_ANEXO,
  );
  const plano = textos(definicion.content).join("\n");
  assert(
    plano.includes("Única, al vencimiento del contrato"),
    "modalidad del compuesto",
  );
  assert(
    plano.includes("US$ 2,700.00"),
    "participación acumulada al vencimiento",
  );
  assert(!plano.includes("No se programan"), "sí hay una liquidación listada");
});

Deno.test("anexo v1 rechaza cronogramas que contradicen el contrato sellado", () => {
  const base = {
    contrato: {
      numero: "2026-01-000777",
      capital: 15000,
      moneda: "PEN" as const,
      modalidad: "mensual" as const,
      tipoInteres: "simple" as const,
      fechaInicio: "2026-08-17",
      fechaVencimiento: "2027-08-17",
    },
    titular: TITULAR_ANEXO,
    analista: { nombreCompleto: "ANALISTA PRUEBA" },
    cotitulares: [],
  };
  const casos: Array<[string, typeof CRONOGRAMA_SIMPLE]> = [
    ["sin retorno", CRONOGRAMA_SIMPLE.slice(0, 12)],
    ["dos retornos", [
      ...CRONOGRAMA_SIMPLE,
      cuota(14, "2027-08-25", 15000, "retorno"),
    ]],
    ["retorno distinto del capital", [
      ...CRONOGRAMA_SIMPLE.slice(0, 12),
      cuota(13, "2027-08-24", 14999.99, "retorno"),
    ]],
    ["retorno antes del vencimiento", [
      ...CRONOGRAMA_SIMPLE.slice(0, 12),
      cuota(13, "2027-08-16", 15000, "retorno"),
    ]],
    ["la forma vieja del fixture (capital_interes)", SNAPSHOT.cronograma],
  ];
  for (const [nombre, cronograma] of casos) {
    let error: unknown = null;
    try {
      clasificarCronograma({ ...base, cronograma });
    } catch (e) {
      error = e;
    }
    assert(error instanceof TypeError, `${nombre}: aborta con TypeError`);
  }
  const { parciales, retorno } = clasificarCronograma({
    ...base,
    cronograma: CRONOGRAMA_SIMPLE,
  });
  igual(parciales.length, 12, "doce parciales");
  igual(retorno.fechaProgramada, "2027-08-24", "retorno identificado");
});

Deno.test("anexo v1 con 60 cuotas cabe en varias hojas sin romper filas", async () => {
  const cuotas = Array.from({ length: 60 }, (_, indice) => {
    const mes = indice + 1;
    const anio = 2026 + Math.floor((7 + mes) / 12);
    const mesCal = ((7 + mes) % 12) + 1;
    return cuota(
      mes,
      `${anio}-${String(mesCal).padStart(2, "0")}-17`,
      225,
      "cuota",
    );
  });
  const snapshot = {
    ...SNAPSHOT,
    contrato: { ...SNAPSHOT.contrato, fechaVencimiento: "2031-08-17" },
    cronograma: [...cuotas, cuota(61, "2031-08-24", 15000, "retorno")],
  };
  const render = await renderizarAnexoPdfV1(
    snapshot,
    "2026-08-17T20:00:00.000Z",
  );
  assert(render.bytes > 0 && render.bytes < 400_000, "tamaño razonable");
  const texto = new TextDecoder("latin1").decode(
    new Uint8Array(await render.blob.arrayBuffer()),
  );
  igual(
    (texto.match(/\/Type \/Page[^s]/g) ?? []).length,
    4,
    "cuatro hojas (60 cuotas + firmas)",
  );
});
