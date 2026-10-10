// Uso puntual: renderiza un contrato de muestra con el renderer REAL de la edge
// (la plantilla vigente, la de CONTRATO_PDF_TEMPLATE_VERSION, con fondo y firma
// verificados por SHA-256). No toca producción.
//
//   deno run -A _render-muestra.ts [destino.pdf] [fechaISO] [--cotitulares=N]
//                                  [--modalidad=mensual|trimestral|semestral|anual]
//                                  [--compuesto] [--anios=N] [--anexo]
//                                  [--moneda=PEN|USD] [--snapshot=destino.json]
//
// --cotitulares=N (0 por defecto, máximo 20) añade N co-titulares ficticios al
// snapshot para ver cómo los nombra la comparecencia y cómo firman al final.
// --anexo renderiza el ANEXO de cronograma (documento aparte, versión vigente) en vez
// del contrato, con el mismo snapshot ficticio.
// --modalidad, --compuesto y --anios cambian el cronograma de muestra (espejo
// del generador del CRM: cuotas de interés por periodo + retorno del capital a
// los 7 días del vencimiento; compuesto = interés al vencimiento + retorno).
import { renderizarAnexoPdfV1, renderizarContratoPdfV2 } from "./renderer.ts";

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

const flagModalidad = Deno.args.find((arg) => arg.startsWith("--modalidad="));
const modalidad = (flagModalidad?.split("=")[1] ?? "mensual") as
  | "mensual"
  | "trimestral"
  | "semestral"
  | "anual";
if (!["mensual", "trimestral", "semestral", "anual"].includes(modalidad)) {
  throw new Error(
    "--modalidad debe ser mensual, trimestral, semestral o anual",
  );
}
const compuesto = Deno.args.includes("--compuesto");
const soloAnexo = Deno.args.includes("--anexo");
const flagAnios = Deno.args.find((arg) => arg.startsWith("--anios="));
const anios = Number(flagAnios?.split("=")[1] ?? "1");
if (!Number.isInteger(anios) || anios < 1 || anios > 5) {
  throw new Error("--anios debe ser un entero entre 1 y 5");
}

const moneda =
  Deno.args.find((arg) => arg.startsWith("--moneda="))?.split("=")[1] ?? "PEN";
if (moneda !== "PEN" && moneda !== "USD") {
  throw new Error("--moneda debe ser PEN o USD");
}

const CAPITAL = 15000;
const PORCENTAJE = 18;
const FECHA_INICIO = "2026-08-17";
const FECHA_VENCIMIENTO = `${2026 + anios}-08-17`;

function iso(fecha: Date): string {
  const y = fecha.getFullYear();
  const m = String(fecha.getMonth() + 1).padStart(2, "0");
  const d = String(fecha.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function idCuota(indice: number): string {
  return `55555555-5555-4555-8555-5555555555${String(indice).padStart(2, "0")}`;
}

/** Espejo simplificado de `generarCronograma` del CRM (app/src/lib/cronograma.ts). */
function cronogramaDeMuestra() {
  const [ai, mi, di] = FECHA_INICIO.split("-").map(Number) as [
    number,
    number,
    number,
  ];
  const [af, mf, df] = FECHA_VENCIMIENTO.split("-").map(Number) as [
    number,
    number,
    number,
  ];
  const inicio = new Date(ai, mi - 1, di);
  const fin = new Date(af, mf - 1, df);
  const retorno = new Date(fin);
  retorno.setDate(retorno.getDate() + 7);

  if (compuesto) {
    const montoFinal = CAPITAL * Math.pow(1 + PORCENTAJE / 100, anios);
    const interesTotal = Math.round((montoFinal - CAPITAL) * 100) / 100;
    return [
      {
        id: idCuota(1),
        numeroCuota: 1,
        fechaProgramada: iso(fin),
        montoProgramado: interesTotal,
        tipo: "devolucion",
      },
      {
        id: idCuota(2),
        numeroCuota: 2,
        fechaProgramada: iso(retorno),
        montoProgramado: CAPITAL,
        tipo: "retorno",
      },
    ];
  }

  const cuotasPorAnio =
    { mensual: 12, trimestral: 4, semestral: 2, anual: 1 }[modalidad];
  const mesesIntervalo = 12 / cuotasPorAnio;
  const montoFijo =
    Math.round(((CAPITAL * (PORCENTAJE / 100)) / cuotasPorAnio) * 100) / 100;
  const cuotas = [];
  for (let i = 1; i <= 120; i++) {
    const targetMes = inicio.getMonth() + i * mesesIntervalo;
    let candidato = new Date(inicio.getFullYear(), targetMes, inicio.getDate());
    if (candidato.getMonth() !== ((targetMes % 12) + 12) % 12) {
      candidato = new Date(inicio.getFullYear(), targetMes + 1, 0);
    }
    if (candidato > fin) break;
    cuotas.push({
      id: idCuota(i),
      numeroCuota: i,
      fechaProgramada: iso(candidato),
      montoProgramado: montoFijo,
      tipo: "cuota",
    });
  }
  cuotas.push({
    id: idCuota(cuotas.length + 1),
    numeroCuota: cuotas.length + 1,
    fechaProgramada: iso(retorno),
    montoProgramado: CAPITAL,
    tipo: "retorno",
  });
  return cuotas;
}

const SNAPSHOT = {
  snapshotVersion: 2,
  contrato: {
    id: "8fffe71c-0abc-4c36-90fa-79fcbf4c3941",
    numero: "2026-01-000777",
    clienteId: "44444444-4444-4444-8444-444444444444",
    capital: CAPITAL,
    moneda,
    porcentaje: PORCENTAJE,
    modalidad,
    tipoInteres: compuesto ? "compuesto" : "simple",
    categoria: "nuevo",
    fechaInicio: FECHA_INICIO,
    fechaVencimiento: FECHA_VENCIMIENTO,
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
  cronograma: cronogramaDeMuestra(),
  cuentaPago: {
    cuentaId: "66666666-6666-4666-8666-666666666666",
    moneda,
    banco: "BCP",
    tipoCuenta: "ahorros",
    numeroCuenta: "0019100000000000",
    cci: "00219100000000000000",
    titularDistinto: false,
    beneficiarioNombre: null,
    beneficiarioDocumento: null,
    origen: "contrato",
  },
};

const destino = posicionales[0] ??
  (soloAnexo ? "anexo-muestra.pdf" : "contrato-muestra.pdf");
const fechaFija = posicionales[1] ?? "2026-09-01T12:00:00Z";
const resultado = soloAnexo
  ? await renderizarAnexoPdfV1(SNAPSHOT, fechaFija)
  : await renderizarContratoPdfV2(SNAPSHOT, fechaFija);
const snapshotDestino = Deno.args.find((arg) => arg.startsWith("--snapshot="))
  ?.slice("--snapshot=".length);
if (snapshotDestino) {
  await Deno.writeTextFile(
    snapshotDestino,
    JSON.stringify(SNAPSHOT, null, 2) + "\n",
  );
}
await Deno.writeFile(
  destino,
  new Uint8Array(await resultado.blob.arrayBuffer()),
);
console.log(
  JSON.stringify({
    destino,
    documento: soloAnexo ? "anexo" : "contrato",
    cotitulares: cantidadCotitulares,
    modalidad,
    moneda,
    compuesto,
    anios,
    cuotas: SNAPSHOT.cronograma.length,
    bytes: resultado.bytes,
    sha256: resultado.sha256,
  }),
);
