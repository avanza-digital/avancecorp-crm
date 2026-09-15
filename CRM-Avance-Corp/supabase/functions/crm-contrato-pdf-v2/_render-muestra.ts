// Uso puntual: renderiza un contrato de muestra con el renderer REAL de la edge
// (la plantilla vigente, la de CONTRATO_PDF_TEMPLATE_VERSION, con fondo y firma
// verificados por SHA-256). No toca producción.
//
//   deno run -A _render-muestra.ts [destino.pdf] [fechaISO] [--cotitulares=N]
//
// --cotitulares=N (0 por defecto, máximo 20) añade N co-titulares ficticios al
// snapshot para ver cómo los nombra la comparecencia y cómo firman al final.
import { renderizarContratoPdfV2 } from "./renderer.ts";

const NOMBRES_COTITULARES = [
  "COTITULAR PRUEBA UNO",
  "COTITULAR PRUEBA DOS",
  "COTITULAR PRUEBA TRES",
  "COTITULAR PRUEBA CUATRO",
  "COTITULAR PRUEBA CINCO",
];

function cotitularesDeMuestra(cantidad: number) {
  return Array.from({ length: cantidad }, (_, indice) => ({
    id: `77777777-7777-4777-8777-7777777777${
      String(indice + 1).padStart(2, "0")
    }`,
    orden: indice + 1,
    nombreCompleto: NOMBRES_COTITULARES[indice] ??
      `COTITULAR PRUEBA ${indice + 1}`,
    tipoDocumento: "DNI",
    documento: String(40000000 + indice + 1),
  }));
}

const posicionales = Deno.args.filter((arg) => !arg.startsWith("--"));
const flagCotitulares = Deno.args.find((arg) =>
  arg.startsWith("--cotitulares=")
);
const cantidadCotitulares = Number(flagCotitulares?.split("=")[1] ?? "0");
if (
  !Number.isInteger(cantidadCotitulares) || cantidadCotitulares < 0 ||
  cantidadCotitulares > 20
) {
  throw new Error("--cotitulares debe ser un entero entre 0 y 20");
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
  cotitulares: cotitularesDeMuestra(cantidadCotitulares),
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

const destino = posicionales[0] ?? "contrato-muestra.pdf";
const resultado = await renderizarContratoPdfV2(
  SNAPSHOT,
  posicionales[1] ?? "2026-09-01T12:00:00Z",
);
await Deno.writeFile(
  destino,
  new Uint8Array(await resultado.blob.arrayBuffer()),
);
console.log(
  JSON.stringify({
    destino,
    cotitulares: cantidadCotitulares,
    bytes: resultado.bytes,
    sha256: resultado.sha256,
  }),
);
