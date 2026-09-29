// Anexo de cronograma de liquidaciones parciales: documento APARTE del contrato.
//
// Decisión de Miguel (28/09/2026): «todo sigue igual, solo que el añadido es que
// el analista ahora puede imprimir este anexo». El contrato PDF (template-v2,
// contrato-aep-17-v9) no cambia ni un byte; este módulo dibuja, a demanda y
// desde el snapshot SELLADO del contrato, el anexo del modelo «Propuesta de
// Anexo para contrato de AEP» (septiembre 2026): datos del contrato, tabla de
// liquidaciones parciales, liquidación final, naturaleza, prevalencia y firmas.
//
// El anexo no se guarda: con los datos congelados del contrato y esta versión
// de plantilla, cada impresión produce los mismos bytes.
import type {
  Content,
  ContentTable,
  ContentText,
  TDocumentDefinitions,
} from "pdfmake/interfaces";
import {
  bloqueFirmas,
  type ContratoPdfAssets,
  type ContratoPdfDatos,
  type Cotitular,
  documentoDe,
  fechaPartes,
  montoVisible,
  parrafo,
  TIPOGRAFIA,
  tituloClausula,
} from "./template-v2.ts";

export const ANEXO_TEMPLATE_VERSION = "anexo-cronograma-v1";

export type ModalidadContrato =
  | "mensual"
  | "trimestral"
  | "semestral"
  | "anual";

export interface AnexoPdfDatos {
  contrato: {
    numero: string;
    capital: number;
    moneda: "PEN" | "USD";
    modalidad: ModalidadContrato;
    tipoInteres: "simple" | "compuesto";
    fechaInicio: string;
    fechaVencimiento: string;
  };
  titular: ContratoPdfDatos["titular"];
  analista: { nombreCompleto: string };
  cotitulares: Cotitular[];
  /** Cronograma contractual congelado con el PDF sellado. */
  cronograma: Array<{
    numeroCuota: number;
    fechaProgramada: string;
    montoProgramado: number;
    tipo: string;
  }>;
}

export function nombreArchivoAnexo(datos: AnexoPdfDatos): string {
  const nombre = datos.titular.nombreCompleto
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .toUpperCase();
  return `Anexo-${datos.contrato.numero}-${nombre}.pdf`;
}

function fechaLarga(iso: string): string {
  const { dia, mes, anio } = fechaPartes(iso);
  return `${dia} de ${mes} de ${anio}`;
}

function etiquetaModalidad(contrato: AnexoPdfDatos["contrato"]): string {
  if (contrato.tipoInteres === "compuesto") {
    return "Única, al vencimiento del contrato";
  }
  const etiquetas: Record<ModalidadContrato, string> = {
    mensual: "Mensual",
    trimestral: "Trimestral",
    semestral: "Semestral",
    anual: "Anual",
  };
  return etiquetas[contrato.modalidad];
}

type CeldaAnexo = {
  text: string;
  bold?: boolean;
  alignment?: "left" | "center" | "right";
};

function tablaAnexo(
  cabecera: string[],
  filas: CeldaAnexo[][],
  widths: Array<string | number>,
): ContentTable {
  const cuerpo: CeldaAnexo[][] = [
    cabecera.map((text) => ({ text })),
    ...filas,
  ];
  return {
    table: {
      headerRows: 1,
      dontBreakRows: true,
      widths,
      body: cuerpo.map((fila, indice) =>
        fila.map((celda) => ({
          ...celda,
          bold: indice === 0 || celda.bold === true,
          color: indice === 0 ? "#ffffff" : "#15264d",
          fillColor: indice === 0
            ? "#183969"
            : indice % 2 === 0
            ? "#f2f5f8"
            : "#ffffff",
          margin: [4, 3, 4, 3],
        }))
      ),
    },
    layout: {
      hLineColor: () => "#cbd5e1",
      vLineColor: () => "#cbd5e1",
      hLineWidth: () => 0.5,
      vLineWidth: () => 0.5,
    },
    fontSize: TIPOGRAFIA.cuerpo,
    margin: [0, 5, 0, 8],
  };
}

function nombresAsociado(
  titular: AnexoPdfDatos["titular"],
  cotitulares: Cotitular[],
): ContentText[] {
  const fragmentos: ContentText[] = [
    { text: titular.nombreCompleto, bold: true },
  ];
  cotitulares.forEach((cotitular, indice) => {
    fragmentos.push(
      { text: indice === cotitulares.length - 1 ? " y " : ", " },
      { text: cotitular.nombreCompleto, bold: true },
    );
  });
  return fragmentos;
}

type Cuota = AnexoPdfDatos["cronograma"][number];

/**
 * El anexo no puede contradecir el cronograma sellado (revisión de Codex,
 * 28/09/2026): exige exactamente una fila `retorno`, con el capital del
 * contrato y fechada en el vencimiento o después. Las demás filas son las
 * liquidaciones parciales (interés simple: una `cuota` por periodo; compuesto:
 * una `devolucion` al vencimiento). Cualquier otra forma aborta la emisión.
 */
export function clasificarCronograma(
  datos: AnexoPdfDatos,
): { parciales: Cuota[]; retorno: Cuota } {
  const retornos = datos.cronograma.filter((cuota) => cuota.tipo === "retorno");
  if (retornos.length !== 1) {
    throw new TypeError(
      "Cronograma incoherente para el anexo: se esperaba una única fila de retorno",
    );
  }
  const retorno = retornos[0]!;
  if (Math.abs(retorno.montoProgramado - datos.contrato.capital) > 0.005) {
    throw new TypeError(
      "Cronograma incoherente para el anexo: el retorno no coincide con la contribución",
    );
  }
  if (retorno.fechaProgramada < datos.contrato.fechaVencimiento) {
    throw new TypeError(
      "Cronograma incoherente para el anexo: el retorno es anterior al vencimiento",
    );
  }
  const parciales = datos.cronograma
    .filter((cuota) => cuota.tipo !== "retorno")
    .sort((a, b) =>
      a.numeroCuota - b.numeroCuota ||
      a.fechaProgramada.localeCompare(b.fechaProgramada)
    );
  return { parciales, retorno };
}

export function construirAnexoPdf(
  datos: AnexoPdfDatos,
  assets: ContratoPdfAssets,
): TDocumentDefinitions {
  const { contrato, titular, analista } = datos;
  const cotitulares = datos.cotitulares ?? [];
  const documento = documentoDe(titular);
  const { parciales, retorno } = clasificarCronograma(datos);

  const filasDatos: CeldaAnexo[][] = [
    [{ text: "Número de contrato" }, { text: contrato.numero, bold: true }],
    [{ text: "Fecha de inicio" }, {
      text: fechaLarga(contrato.fechaInicio),
      bold: true,
    }],
    [{ text: "Fecha de vencimiento" }, {
      text: fechaLarga(contrato.fechaVencimiento),
      bold: true,
    }],
    [{ text: "Monto de la contribución" }, {
      text: montoVisible(contrato.capital, contrato.moneda),
      bold: true,
    }],
    [{ text: "Modalidad de liquidaciones parciales" }, {
      text: etiquetaModalidad(contrato),
      bold: true,
    }],
    [{ text: "Analista Comercial" }, {
      text: analista.nombreCompleto,
      bold: true,
    }],
  ];

  const filasParciales: CeldaAnexo[][] = parciales.length === 0
    ? [[
      { text: "—", alignment: "center" },
      { text: "No se programan liquidaciones parciales" },
      { text: "—", alignment: "center" },
    ]]
    : parciales.map((cuota, indice) => [
      { text: String(indice + 1), alignment: "center" },
      { text: fechaLarga(cuota.fechaProgramada) },
      {
        text: montoVisible(cuota.montoProgramado, contrato.moneda),
        alignment: "right",
      },
    ]);

  const contenido: Content[] = [
    { text: "ANEXO", style: "titulo", margin: [0, 5, 0, 12] },
    parrafo([
      {
        text:
          "El presente Anexo forma parte integrante del Contrato de Asociación en Participación celebrado entre ",
      },
      { text: "AVANCE CORP S.A.C.", bold: true },
      { text: ", en calidad de EL ASOCIANTE, y " },
      ...nombresAsociado(titular, cotitulares),
      {
        text:
          ", en calidad de EL ASOCIADO, y deberá ser interpretado y ejecutado conjuntamente con las disposiciones del referido contrato.",
      },
    ]),
    tituloClausula("DATOS DEL CONTRATO"),
    tablaAnexo(["Dato", "Detalle"], filasDatos, ["42%", "58%"]),
    tituloClausula("CRONOGRAMA DE LIQUIDACIONES PARCIALES"),
    parrafo(
      "Durante la vigencia del contrato, EL ASOCIANTE efectuará liquidaciones parciales de resultados en las fechas que se indican a continuación:",
    ),
    tablaAnexo(
      ["#", "Fecha de la liquidación", "Participación"],
      filasParciales,
      ["10%", "52%", "38%"],
    ),
    tituloClausula("LIQUIDACIÓN FINAL Y RESTITUCIÓN DE LA CONTRIBUCIÓN"),
    parrafo(
      "Al vencimiento del contrato, EL ASOCIANTE practicará la liquidación final correspondiente, considerando las participaciones que hubieran sido distribuidas durante la vigencia del contrato.",
    ),
    parrafo(
      "Conforme a lo establecido en el numeral 5.3 del contrato, EL ASOCIANTE restituirá a EL ASOCIADO el saldo de la contribución determinado conforme a la liquidación final dentro de un plazo máximo de siete (7) días hábiles contados desde el vencimiento contractual.",
    ),
    tablaAnexo(
      ["Concepto", "Fecha", "Monto"],
      [[
        { text: "Liquidación final y restitución de la contribución" },
        { text: fechaLarga(retorno.fechaProgramada) },
        {
          text: montoVisible(retorno.montoProgramado, contrato.moneda),
          alignment: "right",
        },
      ]],
      ["46%", "32%", "22%"],
    ),
    tituloClausula("NATURALEZA DEL CRONOGRAMA"),
    parrafo(
      "El presente Anexo tiene por finalidad facilitar a EL ASOCIADO el seguimiento de las fechas en las que se practicarán liquidaciones parciales durante la vigencia del contrato, sin modificar la naturaleza asociativa del mismo ni sustituir las reglas de determinación de utilidades previstas en sus disposiciones.",
    ),
    tituloClausula("PREVALENCIA DEL CONTRATO"),
    parrafo(
      "En todo aquello que no se encuentre expresamente regulado en el presente Anexo, serán aplicables las disposiciones del Contrato de Asociación en Participación.",
    ),
    parrafo(
      "En caso de discrepancia entre el presente Anexo y el contrato principal, prevalecerán las disposiciones de este último, especialmente aquellas referidas a la naturaleza asociativa de la relación, determinación de utilidades, liquidaciones parciales, liquidación final y restitución de la contribución.",
    ),
    parrafo(
      "Las partes suscriben el presente Anexo en señal de conformidad, en la misma fecha de celebración del Contrato de Asociación en Participación.",
      { margin: [0, 6, 0, 4] },
    ),
    bloqueFirmas(titular, documento, cotitulares),
  ];

  // Lienzo, membrete, cabecera, pie y estilos: espejo exacto del contrato
  // (template-v2), para que el anexo se vea como una hoja más del mismo
  // documento.
  return {
    info: {
      title: `Anexo ${contrato.numero}`,
      author: "Avance Corp S.A.C.",
      subject: "Anexo de cronograma de liquidaciones parciales",
      keywords: `anexo,cronograma,${contrato.numero},avance corp`,
    },
    pageSize: "A4",
    pageMargins: [66, 126, 58, 94],
    images: {
      fondoContrato: assets.fondo,
      firmaAsociante: assets.firmaAsociante,
    },
    background: () => ({
      image: "fondoContrato",
      width: 595.28,
      height: 841.89,
      absolutePosition: { x: 0, y: 0 },
    }),
    header: () => ({
      text: contrato.numero,
      alignment: "right",
      color: "#183969",
      bold: true,
      fontSize: TIPOGRAFIA.cabecera,
      margin: [0, 82, 58, 0],
    }),
    footer: (pagina, total) => ({
      text: `${pagina} / ${total}`,
      alignment: "right",
      color: "#64748b",
      fontSize: TIPOGRAFIA.pie,
      margin: [0, 0, 58, 52],
    }),
    content: contenido,
    defaultStyle: {
      font: "Roboto",
      fontSize: TIPOGRAFIA.cuerpo,
      color: "#17233b",
      lineHeight: 1.16,
    },
    styles: {
      titulo: {
        fontSize: TIPOGRAFIA.titulo,
        bold: true,
        alignment: "center",
        color: "#183969",
      },
      clausula: {
        fontSize: TIPOGRAFIA.clausula,
        bold: true,
        color: "#183969",
      },
      parrafo: {
        alignment: "justify",
        margin: [0, 0, 0, 4],
      },
    },
  };
}
