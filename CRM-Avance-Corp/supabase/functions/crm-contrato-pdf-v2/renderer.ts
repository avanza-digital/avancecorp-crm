import { Buffer } from "node:buffer";
import type { TDocumentDefinitions } from "pdfmake/interfaces";
import pdfmakeBundle from "./pdfmake-0.2.20-pdfprinter.js";
import robotoVfs from "./vfs-fonts-0.2.20.js";
import {
  CONTRATO_PDF_ASSETS_VERSION,
  FIRMA_DATA_URL,
  FIRMA_SHA256,
  FONDO_DATA_URL,
  FONDO_SHA256,
} from "./assets-v2.ts";
import {
  ANEXO_PDF_TEMPLATE_VERSION,
  CONTRATO_PDF_MAX_BYTES,
  CONTRATO_PDF_TEMPLATE_VERSION,
  type RenderAnexoResult,
  type RenderResult,
} from "./handler.ts";
import {
  ANEXO_TEMPLATE_VERSION,
  type AnexoPdfDatos,
  construirAnexoPdf,
  nombreArchivoAnexo,
} from "./anexo-v1.ts";
import {
  construirContratoPdf,
  type ContratoPdfDatos,
  type TipoDocumento,
} from "./template-v2.ts";

export const CONTRATO_PDF_RENDERER_VERSION = CONTRATO_PDF_TEMPLATE_VERSION;
export const ANEXO_PDF_RENDERER_VERSION = ANEXO_TEMPLATE_VERSION;
export const CONTRATO_PDF_VFS_VERSION = "pdfmake-0.2.20-roboto-vfs-1";
export const PDFMAKE_UPSTREAM_SHA256 =
  "bfd0e78ae7fd12ecf4ab0b4aae4b5eb3f97865b0ed5932f1d9e947fc91f54930";
export const VFS_UPSTREAM_SHA256 =
  "f91db5690400fc851536c3a9322f822619f8e9f681abe42013e572d88d3c1f38";
export const PDFMAKE_VENDOR_SHA256 =
  "0d223658ea3a32d3999916a3bfad06dc4354a5bf444aa8353d4c85814eeb53e4";
export const VFS_VENDOR_SHA256 =
  "3231b43cfdd7efdca80d54be634fc12d28b7dd3fb5ae69efe0fd3eb569e660d1";
export { CONTRATO_PDF_ASSETS_VERSION };

type PdfKitDocument = {
  on(evento: "data", callback: (chunk: Uint8Array) => void): void;
  on(evento: "error", callback: (error: unknown) => void): void;
  on(evento: "end", callback: () => void): void;
  end(): void;
};

type PdfPrinterInstancia = {
  createPdfKitDocument(definicion: TDocumentDefinitions): PdfKitDocument;
};

type PdfPrinterConstructor = new (
  fuentes: Record<string, Record<string, Buffer>>,
) => PdfPrinterInstancia;

// Build oficial 0.2.20, ejecutado server-side. La única modificación del
// vendor expone su módulo interno PdfPrinter (id 81566) para evitar la fachada
// de navegador y para mantener el ESZIP bajo el límite de Supabase.
const PdfPrinter = (pdfmakeBundle as unknown as {
  PdfPrinter: PdfPrinterConstructor;
}).PdfPrinter;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const FECHA_RE = /^\d{4}-\d{2}-\d{2}$/;
const CORREO_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SHA_RE = /^[a-f0-9]{64}$/;
const VFS_HASHES: Record<string, string> = {
  "Roboto-Regular.ttf":
    "a93f6bc56ef0349a4426b717c182482bb878534f31077ae5e1b2b4dae7a089d1",
  "Roboto-Medium.ttf":
    "79a763229b01229cfd921a9a0108e58c162d045d828037e32c6fb85ed6f914be",
  "Roboto-Italic.ttf":
    "d007116129de4b85dfc0fb8bf24e66bcb9d2424fef652027d1c3b3c826a4a6ca",
  "Roboto-MediumItalic.ttf":
    "cdb6c3f0eed7df291ea12270eb7d5fec8e263a762b69c1000653dc5fbb1ecce2",
};

type CotitularSnapshot = {
  id: string;
  orden: number;
  nombreCompleto: string;
  tipoDocumento: TipoDocumento;
  documento: string;
};

type CronogramaSnapshot = {
  id: string;
  numeroCuota: number;
  fechaProgramada: string;
  montoProgramado: number;
  tipo: string;
};

export type SnapshotContratoV2 = {
  snapshotVersion: 2 | 3;
  contrato: {
    id: string;
    numero: string;
    clienteId: string;
    capital: number;
    moneda: "PEN" | "USD";
    porcentaje: number;
    modalidad: "mensual" | "trimestral" | "semestral" | "anual";
    tipoInteres: "simple" | "compuesto";
    categoria: "nuevo" | "renovacion" | "upgrade";
    fechaInicio: string;
    fechaVencimiento: string;
    productoCondicionId: string | null;
    creadoPor: string;
    /** Solo snapshot 3: analista asignado, independiente de quien registró. */
    analistaId?: string;
  };
  titular: {
    id: string;
    nombreCompleto: string;
    tipoDocumento: TipoDocumento;
    documento: string;
    domicilio: string;
    correo: string;
  };
  analista: {
    id: string;
    nombreCompleto: string;
    documento: string;
    celular: string;
    correo: string;
  };
  cotitulares: CotitularSnapshot[];
  cronograma: CronogramaSnapshot[];
  cuentaPago: {
    cuentaId: string;
    moneda: "PEN" | "USD";
    banco: string;
    tipoCuenta: "ahorros" | "corriente";
    numeroCuenta: string;
    cci: string;
    titularDistinto: boolean;
    beneficiarioNombre: string | null;
    beneficiarioDocumento: string | null;
    origen: "perfil" | "contrato" | "portal";
  };
};

function esObjeto(valor: unknown): valor is Record<string, unknown> {
  return typeof valor === "object" && valor !== null && !Array.isArray(valor);
}

function clavesExactas(
  valor: Record<string, unknown>,
  esperadas: readonly string[],
): boolean {
  const actuales = Object.keys(valor).sort();
  const objetivo = [...esperadas].sort();
  return actuales.length === objetivo.length &&
    actuales.every((clave, indice) => clave === objetivo[indice]);
}

function uuid(valor: unknown): valor is string {
  return typeof valor === "string" && UUID_RE.test(valor);
}

function texto(
  valor: unknown,
  minimo: number,
  maximo: number,
): valor is string {
  if (typeof valor !== "string" || valor !== valor.trim()) return false;
  const longitud = [...valor].length;
  return longitud >= minimo && longitud <= maximo && !tieneControl(valor);
}

function tieneControl(valor: string): boolean {
  for (const caracter of valor) {
    const codigo = caracter.codePointAt(0) ?? 0;
    if (codigo <= 0x1f || (codigo >= 0x7f && codigo <= 0x9f)) return true;
  }
  return false;
}

function numero(
  valor: unknown,
  minimo: number,
  maximo: number,
): valor is number {
  return typeof valor === "number" && Number.isFinite(valor) &&
    valor >= minimo && valor <= maximo;
}

function entero(
  valor: unknown,
  minimo: number,
  maximo: number,
): valor is number {
  return numero(valor, minimo, maximo) && Number.isSafeInteger(valor);
}

function fecha(valor: unknown): valor is string {
  if (typeof valor !== "string" || !FECHA_RE.test(valor)) return false;
  const [anio, mes, dia] = valor.split("-").map(Number);
  const utc = new Date(Date.UTC(anio, mes - 1, dia));
  return utc.getUTCFullYear() === anio && utc.getUTCMonth() === mes - 1 &&
    utc.getUTCDate() === dia;
}

function correo(valor: unknown): valor is string {
  return texto(valor, 3, 254) && CORREO_RE.test(valor);
}

function tipoDocumento(valor: unknown): valor is TipoDocumento {
  return valor === "DNI" || valor === "CE" || valor === "PASAPORTE";
}

function fallo(campo: string): never {
  throw new TypeError(`Snapshot PDF v2 inválido: ${campo}`);
}

export function validarSnapshotContratoV2(valor: unknown): SnapshotContratoV2 {
  if (
    !esObjeto(valor) ||
    !clavesExactas(valor, [
      "snapshotVersion",
      "contrato",
      "titular",
      "analista",
      "cotitulares",
      "cronograma",
      "cuentaPago",
    ]) || (valor.snapshotVersion !== 2 && valor.snapshotVersion !== 3)
  ) fallo("raíz");

  const contrato = valor.contrato;
  if (
    !esObjeto(contrato) ||
    !clavesExactas(contrato, [
      "id",
      "numero",
      "clienteId",
      "capital",
      "moneda",
      "porcentaje",
      "modalidad",
      "tipoInteres",
      "categoria",
      "fechaInicio",
      "fechaVencimiento",
      "productoCondicionId",
      "creadoPor",
      ...(valor.snapshotVersion === 3 ? ["analistaId"] : []),
    ]) || !uuid(contrato.id) || !texto(contrato.numero, 1, 200) ||
    !uuid(contrato.clienteId) ||
    !numero(contrato.capital, 0.01, 999999999.99) ||
    (contrato.moneda !== "PEN" && contrato.moneda !== "USD") ||
    !numero(contrato.porcentaje, 0, 100) ||
    !["mensual", "trimestral", "semestral", "anual"].includes(
      String(contrato.modalidad),
    ) ||
    (contrato.tipoInteres !== "simple" &&
      contrato.tipoInteres !== "compuesto") ||
    !["nuevo", "renovacion", "upgrade"].includes(String(contrato.categoria)) ||
    !fecha(contrato.fechaInicio) || !fecha(contrato.fechaVencimiento) ||
    contrato.fechaVencimiento < contrato.fechaInicio ||
    (contrato.productoCondicionId !== null &&
      !uuid(contrato.productoCondicionId)) ||
    !uuid(contrato.creadoPor) ||
    (valor.snapshotVersion === 3 && !uuid(contrato.analistaId))
  ) fallo("contrato");

  const titular = valor.titular;
  if (
    !esObjeto(titular) ||
    !clavesExactas(titular, [
      "id",
      "nombreCompleto",
      "tipoDocumento",
      "documento",
      "domicilio",
      "correo",
    ]) || !uuid(titular.id) || !texto(titular.nombreCompleto, 1, 200) ||
    !tipoDocumento(titular.tipoDocumento) || !texto(titular.documento, 5, 20) ||
    !texto(titular.domicilio, 5, 240) || !correo(titular.correo) ||
    titular.id !== contrato.clienteId
  ) fallo("titular");

  const analista = valor.analista;
  if (
    !esObjeto(analista) ||
    !clavesExactas(analista, [
      "id",
      "nombreCompleto",
      "documento",
      "celular",
      "correo",
    ]) || !uuid(analista.id) || !texto(analista.nombreCompleto, 1, 200) ||
    !texto(analista.documento, 5, 20) || !texto(analista.celular, 5, 30) ||
    !correo(analista.correo) || analista.id !==
      (valor.snapshotVersion === 3 ? contrato.analistaId : contrato.creadoPor)
  ) fallo("analista");

  if (!Array.isArray(valor.cotitulares) || valor.cotitulares.length > 20) {
    fallo("cotitulares");
  }
  const cotitulares = valor.cotitulares.map((item, indice) => {
    if (
      !esObjeto(item) ||
      !clavesExactas(item, [
        "id",
        "orden",
        "nombreCompleto",
        "tipoDocumento",
        "documento",
      ]) || !uuid(item.id) || !entero(item.orden, 1, 20) ||
      !texto(item.nombreCompleto, 1, 200) ||
      !tipoDocumento(item.tipoDocumento) || !texto(item.documento, 5, 20)
    ) fallo(`cotitulares[${indice}]`);
    return item as CotitularSnapshot;
  });

  if (
    !Array.isArray(valor.cronograma) || valor.cronograma.length < 1 ||
    valor.cronograma.length > 600
  ) fallo("cronograma");
  const cronograma = valor.cronograma.map((item, indice) => {
    if (
      !esObjeto(item) ||
      !clavesExactas(item, [
        "id",
        "numeroCuota",
        "fechaProgramada",
        "montoProgramado",
        "tipo",
      ]) || !uuid(item.id) || !entero(item.numeroCuota, 1, 600) ||
      !fecha(item.fechaProgramada) ||
      !numero(item.montoProgramado, 0, 999999999.99) ||
      !texto(item.tipo, 1, 80)
    ) fallo(`cronograma[${indice}]`);
    return item as CronogramaSnapshot;
  });

  const cuenta = valor.cuentaPago;
  if (
    !esObjeto(cuenta) ||
    !clavesExactas(cuenta, [
      "cuentaId",
      "moneda",
      "banco",
      "tipoCuenta",
      "numeroCuenta",
      "cci",
      "titularDistinto",
      "beneficiarioNombre",
      "beneficiarioDocumento",
      "origen",
    ]) || !uuid(cuenta.cuentaId) ||
    (cuenta.moneda !== "PEN" && cuenta.moneda !== "USD") ||
    !texto(cuenta.banco, 1, 100) ||
    (cuenta.tipoCuenta !== "ahorros" && cuenta.tipoCuenta !== "corriente") ||
    !texto(cuenta.numeroCuenta, 1, 30) ||
    !/^\d{20}$/.test(String(cuenta.cci)) ||
    typeof cuenta.titularDistinto !== "boolean" ||
    (cuenta.beneficiarioNombre !== null &&
      !texto(cuenta.beneficiarioNombre, 1, 200)) ||
    (cuenta.beneficiarioDocumento !== null &&
      !/^\d{8,12}$/.test(String(cuenta.beneficiarioDocumento))) ||
    // Espejo del CHECK `cuentas_bancarias_origen_valido` (perfil, contrato,
    // portal). Una cuenta registrada desde el portal es tan contractual como
    // las otras dos; el origen no cambia un byte del PDF. Comparación estricta:
    // `String(["portal"])` también daría "portal" y colaría un arreglo.
    (cuenta.origen !== "perfil" && cuenta.origen !== "contrato" &&
      cuenta.origen !== "portal") ||
    cuenta.moneda !== contrato.moneda ||
    (!cuenta.titularDistinto &&
      (cuenta.beneficiarioNombre !== null ||
        cuenta.beneficiarioDocumento !== null)) ||
    (cuenta.titularDistinto &&
      (cuenta.beneficiarioNombre === null ||
        cuenta.beneficiarioDocumento === null))
  ) fallo("cuentaPago");

  return {
    snapshotVersion: valor.snapshotVersion,
    contrato: contrato as SnapshotContratoV2["contrato"],
    titular: titular as SnapshotContratoV2["titular"],
    analista: analista as SnapshotContratoV2["analista"],
    cotitulares,
    cronograma,
    cuentaPago: cuenta as SnapshotContratoV2["cuentaPago"],
  };
}

function dataUrlBytes(dataUrl: string): Uint8Array {
  const separador = dataUrl.indexOf(",");
  if (separador < 0) throw new Error("Asset PDF v2 inválido");
  return new Uint8Array(Buffer.from(dataUrl.slice(separador + 1), "base64"));
}

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

let recursosVerificados: Promise<void> | null = null;

async function verificarRecursos(): Promise<void> {
  recursosVerificados ??= (async () => {
    const fondo = dataUrlBytes(FONDO_DATA_URL);
    const firma = dataUrlBytes(FIRMA_DATA_URL);
    if (await sha256Bytes(fondo) !== FONDO_SHA256) {
      throw new TypeError("Assets PDF v2 no corresponden a su versión");
    }
    if (await sha256Bytes(firma) !== FIRMA_SHA256) {
      throw new TypeError("Firma PDF v2 no corresponde a su versión");
    }
    for (const [nombre, hash] of Object.entries(VFS_HASHES)) {
      const base64 = (robotoVfs as unknown as Record<string, string>)[nombre];
      if (!base64 || !SHA_RE.test(hash)) {
        throw new TypeError("VFS PDF v2 incompleto");
      }
      if (
        await sha256Bytes(new Uint8Array(Buffer.from(base64, "base64"))) !==
          hash
      ) {
        throw new TypeError("VFS PDF v2 no corresponde a su versión");
      }
    }
  })();
  return await recursosVerificados;
}

export async function verificarAssetsContratoPdfV2(): Promise<{
  ok: true;
  fondoBytes: number;
  firmaBytes: number;
}> {
  await verificarRecursos();
  return {
    ok: true,
    fondoBytes: dataUrlBytes(FONDO_DATA_URL).byteLength,
    firmaBytes: dataUrlBytes(FIRMA_DATA_URL).byteLength,
  };
}

function datosDocumento(snapshot: SnapshotContratoV2): ContratoPdfDatos {
  return {
    contrato: {
      numero: snapshot.contrato.numero,
      capital: snapshot.contrato.capital,
      moneda: snapshot.contrato.moneda,
      porcentaje: snapshot.contrato.porcentaje,
      fechaInicio: snapshot.contrato.fechaInicio,
      fechaVencimiento: snapshot.contrato.fechaVencimiento,
    },
    titular: {
      nombreCompleto: snapshot.titular.nombreCompleto,
      tipoDocumento: snapshot.titular.tipoDocumento,
      documento: snapshot.titular.documento,
      domicilio: snapshot.titular.domicilio,
      correo: snapshot.titular.correo,
    },
    analista: {
      nombreCompleto: snapshot.analista.nombreCompleto,
      documento: snapshot.analista.documento,
      celular: snapshot.analista.celular,
      correo: snapshot.analista.correo,
    },
    cotitulares: snapshot.cotitulares.map((cotitular) => ({
      nombreCompleto: cotitular.nombreCompleto,
      tipoDocumento: cotitular.tipoDocumento,
      documento: cotitular.documento,
    })),
  };
}

function fuente(nombre: string): Buffer {
  const base64 = (robotoVfs as unknown as Record<string, string>)[nombre];
  if (!base64) throw new Error(`Fuente PDF v2 ausente: ${nombre}`);
  return Buffer.from(base64, "base64");
}

function printer(): PdfPrinterInstancia {
  return new PdfPrinter({
    Roboto: {
      normal: fuente("Roboto-Regular.ttf"),
      bold: fuente("Roboto-Medium.ttf"),
      italics: fuente("Roboto-Italic.ttf"),
      bolditalics: fuente("Roboto-MediumItalic.ttf"),
    },
  });
}

function fechaRender(valor: string): Date {
  if (
    typeof valor !== "string" || valor.length > 40 ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/
      .test(
        valor,
      )
  ) {
    throw new TypeError("Fecha fija del job PDF v2 inválida");
  }
  const fecha = new Date(valor);
  if (!Number.isFinite(fecha.getTime())) {
    throw new TypeError("Fecha fija del job PDF v2 no es ISO canónica");
  }
  return fecha;
}

async function documentoComoBlob(
  definicion: TDocumentDefinitions,
): Promise<Blob> {
  const documento = printer().createPdfKitDocument(definicion);
  const chunks: Uint8Array[] = [];
  const terminado = new Promise<Blob>((resolve, reject) => {
    documento.on("data", (chunk: Uint8Array) => chunks.push(chunk));
    documento.on("error", reject);
    documento.on("end", () => {
      const total = chunks.reduce((suma, chunk) => suma + chunk.byteLength, 0);
      const bytes = new Uint8Array(total);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.byteLength;
      }
      resolve(new Blob([bytes], { type: "application/pdf" }));
    });
  });
  documento.end();
  return await terminado;
}

export async function renderizarContratoPdfV2(
  snapshotRaw: unknown,
  renderizadoEn: string,
): Promise<RenderResult> {
  const snapshot = validarSnapshotContratoV2(snapshotRaw);
  const fechaFija = fechaRender(renderizadoEn);
  await verificarRecursos();
  const definicion = construirContratoPdf(datosDocumento(snapshot), {
    fondo: FONDO_DATA_URL,
    firmaAsociante: FIRMA_DATA_URL,
  });
  definicion.info = {
    ...definicion.info,
    creator: `crm-contrato-pdf-v2/${CONTRATO_PDF_RENDERER_VERSION}`,
    producer:
      `pdfmake/0.2.20 ${CONTRATO_PDF_VFS_VERSION} ${CONTRATO_PDF_ASSETS_VERSION}`,
    creationDate: fechaFija,
    modDate: fechaFija,
  };
  const blob = await documentoComoBlob(definicion);
  if (blob.size <= 5 || blob.size > CONTRATO_PDF_MAX_BYTES) {
    throw new TypeError("El renderer PDF v2 produjo un tamaño inválido");
  }
  const bytes = new Uint8Array(await blob.arrayBuffer());
  if (new TextDecoder().decode(bytes.slice(0, 5)) !== "%PDF-") {
    throw new TypeError("El renderer PDF v2 no produjo un PDF");
  }
  return {
    blob,
    sha256: await sha256Bytes(bytes),
    bytes: blob.size,
  };
}

function datosAnexo(snapshot: SnapshotContratoV2): AnexoPdfDatos {
  return {
    contrato: {
      numero: snapshot.contrato.numero,
      capital: snapshot.contrato.capital,
      moneda: snapshot.contrato.moneda,
      modalidad: snapshot.contrato.modalidad,
      tipoInteres: snapshot.contrato.tipoInteres,
      fechaInicio: snapshot.contrato.fechaInicio,
      fechaVencimiento: snapshot.contrato.fechaVencimiento,
    },
    titular: {
      nombreCompleto: snapshot.titular.nombreCompleto,
      tipoDocumento: snapshot.titular.tipoDocumento,
      documento: snapshot.titular.documento,
      domicilio: snapshot.titular.domicilio,
      correo: snapshot.titular.correo,
    },
    analista: { nombreCompleto: snapshot.analista.nombreCompleto },
    cuentaPago: { numeroCuenta: snapshot.cuentaPago.numeroCuenta },
    cotitulares: snapshot.cotitulares.map((cotitular) => ({
      nombreCompleto: cotitular.nombreCompleto,
      tipoDocumento: cotitular.tipoDocumento,
      documento: cotitular.documento,
    })),
    cronograma: snapshot.cronograma.map((cuota) => ({
      numeroCuota: cuota.numeroCuota,
      fechaProgramada: cuota.fechaProgramada,
      montoProgramado: cuota.montoProgramado,
      tipo: cuota.tipo,
    })),
  };
}

/**
 * Anexo de cronograma (documento aparte). Mismo snapshot sellado, mismos
 * recursos verificados y misma fecha fija (la del sellado del contrato) ⇒
 * mismos bytes en cada impresión para esta versión desplegada.
 */
export async function renderizarAnexoPdfV1(
  snapshotRaw: unknown,
  generadoEn: string,
): Promise<RenderAnexoResult> {
  if (ANEXO_PDF_RENDERER_VERSION !== ANEXO_PDF_TEMPLATE_VERSION) {
    throw new Error("Versión del anexo desalineada entre handler y plantilla");
  }
  const snapshot = validarSnapshotContratoV2(snapshotRaw);
  const fechaFija = fechaRender(generadoEn);
  await verificarRecursos();
  const datos = datosAnexo(snapshot);
  const definicion = construirAnexoPdf(datos, {
    fondo: FONDO_DATA_URL,
    firmaAsociante: FIRMA_DATA_URL,
  });
  definicion.info = {
    ...definicion.info,
    creator: `crm-contrato-pdf-v2/${ANEXO_PDF_RENDERER_VERSION}`,
    producer:
      `pdfmake/0.2.20 ${CONTRATO_PDF_VFS_VERSION} ${CONTRATO_PDF_ASSETS_VERSION}`,
    creationDate: fechaFija,
    modDate: fechaFija,
  };
  const blob = await documentoComoBlob(definicion);
  if (blob.size <= 5 || blob.size > CONTRATO_PDF_MAX_BYTES) {
    throw new Error("El renderer del anexo produjo un tamaño inválido");
  }
  const bytes = new Uint8Array(await blob.arrayBuffer());
  if (new TextDecoder().decode(bytes.slice(0, 5)) !== "%PDF-") {
    throw new Error("El renderer del anexo no produjo un PDF");
  }
  return {
    blob,
    bytes: blob.size,
    sha256: await sha256Bytes(bytes),
    nombreArchivo: nombreArchivoAnexo(datos),
  };
}
