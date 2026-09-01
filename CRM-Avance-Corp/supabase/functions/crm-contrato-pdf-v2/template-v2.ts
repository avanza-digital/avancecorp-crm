import type {
  Content,
  ContentColumns,
  ContentTable,
  ContentText,
  TDocumentDefinitions,
} from "pdfmake/interfaces";
export type TipoDocumento = "DNI" | "CE" | "PASAPORTE";

export interface ContratoPdfDatos {
  contrato: {
    numero: string;
    capital: number;
    moneda: "PEN" | "USD";
    porcentaje: number;
    fechaInicio: string;
    fechaVencimiento: string;
  };
  titular: {
    nombreCompleto: string;
    tipoDocumento: TipoDocumento;
    documento: string;
    domicilio: string;
    correo: string;
  };
  analista: {
    nombreCompleto: string;
    documento: string;
    celular: string;
    correo: string;
  };
  /** Se conservan en el CRM, pero por decisión legal no aparecen en el PDF. */
  cotitulares?: Array<{
    nombreCompleto: string;
    tipoDocumento: TipoDocumento;
    documento: string;
  }>;
}

export interface ContratoPdfAssets {
  fondo: string;
  firmaAsociante: string;
}

const UNIDADES = [
  "CERO",
  "UNO",
  "DOS",
  "TRES",
  "CUATRO",
  "CINCO",
  "SEIS",
  "SIETE",
  "OCHO",
  "NUEVE",
  "DIEZ",
  "ONCE",
  "DOCE",
  "TRECE",
  "CATORCE",
  "QUINCE",
  "DIECISÉIS",
  "DIECISIETE",
  "DIECIOCHO",
  "DIECINUEVE",
  "VEINTE",
  "VEINTIUNO",
  "VEINTIDÓS",
  "VEINTITRÉS",
  "VEINTICUATRO",
  "VEINTICINCO",
  "VEINTISÉIS",
  "VEINTISIETE",
  "VEINTIOCHO",
  "VEINTINUEVE",
] as const;
const DECENAS = [
  "",
  "",
  "",
  "TREINTA",
  "CUARENTA",
  "CINCUENTA",
  "SESENTA",
  "SETENTA",
  "OCHENTA",
  "NOVENTA",
] as const;
const CENTENAS = [
  "",
  "CIENTO",
  "DOSCIENTOS",
  "TRESCIENTOS",
  "CUATROCIENTOS",
  "QUINIENTOS",
  "SEISCIENTOS",
  "SETECIENTOS",
  "OCHOCIENTOS",
  "NOVECIENTOS",
] as const;

function enteroEnLetras(numero: number): string {
  const n = Math.trunc(Math.abs(numero));
  if (n < 30) return UNIDADES[n] ?? "";
  if (n < 100) {
    const decena = Math.trunc(n / 10);
    const unidad = n % 10;
    return `${DECENAS[decena]}${unidad ? ` Y ${UNIDADES[unidad]}` : ""}`;
  }
  if (n === 100) return "CIEN";
  if (n < 1_000) {
    const centena = Math.trunc(n / 100);
    const resto = n % 100;
    return `${CENTENAS[centena]}${resto ? ` ${enteroEnLetras(resto)}` : ""}`;
  }
  if (n < 1_000_000) {
    const miles = Math.trunc(n / 1_000);
    const resto = n % 1_000;
    const prefijo = miles === 1
      ? "MIL"
      : `${enteroEnLetras(miles).replace(/UNO$/, "UN")} MIL`;
    return `${prefijo}${resto ? ` ${enteroEnLetras(resto)}` : ""}`;
  }
  if (n < 1_000_000_000) {
    const millones = Math.trunc(n / 1_000_000);
    const resto = n % 1_000_000;
    const prefijo = millones === 1
      ? "UN MILLÓN"
      : `${enteroEnLetras(millones).replace(/UNO$/, "UN")} MILLONES`;
    return `${prefijo}${resto ? ` ${enteroEnLetras(resto)}` : ""}`;
  }
  throw new RangeError(
    "El capital excede el máximo soportado por el contrato PDF.",
  );
}

function montoEnLetras(capital: number, moneda: "PEN" | "USD"): string {
  const centimos = Math.round((capital - Math.trunc(capital)) * 100);
  const unidad = moneda === "PEN" ? "SOLES" : "DÓLARES AMERICANOS";
  return `${enteroEnLetras(capital).replace(/UNO$/, "UN")} Y ${
    String(centimos).padStart(2, "0")
  }/100 ${unidad}`;
}

function montoVisible(capital: number, moneda: "PEN" | "USD"): string {
  const simbolo = moneda === "PEN" ? "S/" : "US$";
  return `${simbolo} ${
    capital.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  }`;
}

function etiquetaDocumento(tipo: TipoDocumento): string {
  if (tipo === "CE") return "Carné de Extranjería";
  if (tipo === "PASAPORTE") return "Pasaporte";
  return "DNI";
}

function fechaPartes(iso: string): { dia: number; mes: string; anio: number } {
  const [anio = 0, mes = 1, dia = 1] = iso.split("-").map(Number);
  const meses = [
    "enero",
    "febrero",
    "marzo",
    "abril",
    "mayo",
    "junio",
    "julio",
    "agosto",
    "septiembre",
    "octubre",
    "noviembre",
    "diciembre",
  ];
  return { dia, mes: meses[mes - 1] ?? "", anio };
}

function ultimoDiaDelMes(anio: number, mes: number): number {
  return new Date(Date.UTC(anio, mes, 0)).getUTCDate();
}

function mesesCompletosContrato(inicioIso: string, finIso: string): number {
  const [ai = 0, mi = 1, di = 1] = inicioIso.split("-").map(Number);
  const [af = 0, mf = 1, df = 1] = finIso.split("-").map(Number);
  const mesesCalendario = (af - ai) * 12 + mf - mi;
  if (mesesCalendario <= 0) return 0;

  // Al sumar meses, el formulario ajusta fechas como 31/08 al último día de
  // febrero. Ese día ajustado sí completa el mes contractual correspondiente.
  const diaAniversarioAjustado = Math.min(di, ultimoDiaDelMes(af, mf));
  return Math.max(
    0,
    mesesCalendario - (df < diaAniversarioAjustado ? 1 : 0),
  );
}

function plazoVisible(inicioIso: string, finIso: string): string {
  const meses = mesesCompletosContrato(inicioIso, finIso);
  if (meses > 0 && meses % 12 === 0) {
    const anios = meses / 12;
    return `${
      anios === 1 ? "un" : enteroEnLetras(anios).toLowerCase()
    } (${anios}) ${anios === 1 ? "año" : "años"}`;
  }
  return `${enteroEnLetras(meses).toLowerCase()} (${meses}) meses`;
}

function parrafo(
  text: ContentText["text"],
  opciones: Record<string, unknown> = {},
): Content {
  return { text, style: "parrafo", ...opciones } as Content;
}

function parrafoConEtiqueta(
  etiqueta: string,
  text: ContentText["text"],
): ContentColumns {
  return {
    columns: [
      { width: 24, text: etiqueta, noWrap: true },
      { width: "*", text, alignment: "justify" },
    ],
    columnGap: 0,
    margin: [0, 0, 0, 4],
  };
}

function parrafoNumerado(
  clausula: number,
  numeral: number,
  text: ContentText["text"],
): ContentColumns {
  return parrafoConEtiqueta(`${clausula}.${numeral}`, text);
}

function tituloClausula(texto: string): ContentText {
  return { text: texto, style: "clausula", margin: [0, 9, 0, 4] };
}

const CLAUSULAS_ESTATICAS: Record<
  number,
  { titulo: string; parrafos: string[] }
> = {
  1: {
    titulo: "PRIMERA: ANTECEDENTES",
    parrafos: [
      "EL ASOCIANTE es una persona jurídica dedicada, conforme a su objeto social, a realizar operaciones e inversiones en diferentes campos de la actividad económica, prestación de servicios de consultoría, asesoría, asistencia técnica, operación, puesta en marcha, administración, management y/o servicios vinculados al sector de inversiones a nivel nacional e internacional; así como a realizar inversiones, constituir, adquirir y/o integrar sociedades, instituciones, fundaciones, corporaciones o asociaciones, y efectuar inversiones de capital en bienes muebles incorporales, acciones, bonos, debentures, participaciones sociales, cuotas, derechos en sociedades y otros títulos valores mobiliarios, así como administrar dichas inversiones propias.",
      "EL ASOCIADO declara que, de forma libre y voluntaria, desea participar en los resultados económicos de las actividades, unidades de negocio y/o proyectos empresariales desarrollados por EL ASOCIANTE, mediante una contribución económica, sin adquirir derechos societarios sobre la empresa ni intervenir en su administración.",
      "El presente contrato se celebra en el marco de la Ley N° 26887, Ley General de Sociedades, bajo la modalidad de asociación en participación. En virtud de este contrato, EL ASOCIANTE concede a EL ASOCIADO el derecho a participar en los resultados o utilidades que generen las actividades, unidades de negocio o proyectos empresariales materia del presente contrato, a cambio de la contribución económica que este último se obliga a efectuar.",
      "La contribución de EL ASOCIADO será destinada exclusivamente a las actividades, unidades de negocio o proyectos empresariales materia del presente contrato, los cuales deberán encontrarse debidamente identificados o ser determinables conforme a la información y documentación proporcionada por EL ASOCIANTE.",
    ],
  },
  2: {
    titulo: "SEGUNDA: NATURALEZA, OBJETO Y ACTIVIDAD EMPRESARIAL",
    parrafos: [
      "Por el presente contrato, EL ASOCIADO participa, mediante la contribución prevista en la cláusula tercera, en los resultados económicos que generen las actividades empresariales desarrolladas por EL ASOCIANTE, quien asume de manera exclusiva la responsabilidad, dirección, administración, ejecución y gestión de las actividades empresariales materia del presente contrato.",
      "Las actividades empresariales materia del presente contrato deberán ser reales, lícitas, determinadas o determinables, verificables y desarrolladas directamente por EL ASOCIANTE o a través de sociedades, proyectos o unidades de negocio en las que este participe legítimamente.",
      "EL ASOCIANTE conserva la dirección, gestión, administración, representación y responsabilidad frente a terceros respecto de las actividades empresariales materia del presente contrato. EL ASOCIADO no interviene frente a terceros ni participa en la administración o representación de dichas actividades, y tampoco adquiere la condición de socio, accionista, gerente, administrador ni representante de EL ASOCIANTE.",
      "Toda referencia económica contenida en este contrato deberá interpretarse como participación contractual en resultados o utilidades de las actividades empresariales desarrolladas por EL ASOCIANTE, y no como una obligación propia de un producto o servicio financiero.",
    ],
  },
  4: {
    titulo:
      "CUARTA: GESTIÓN DE LAS ACTIVIDADES EMPRESARIALES, REPRESENTACIÓN FRENTE A TERCEROS Y CONTROL DOCUMENTARIO",
    parrafos: [
      "La gestión de las actividades empresariales corresponde única y exclusivamente a EL ASOCIANTE, quien actúa en nombre propio frente a terceros, conserva su administración y asume la responsabilidad que corresponda por sus actos de gestión. En el desarrollo de dichas actividades, EL ASOCIANTE actuará con la diligencia ordinaria exigible a un operador empresarial, procurando una gestión profesional, diligente, eficiente y prudente, orientada a la adecuada administración de los recursos, la identificación de oportunidades empresariales, a la gestión razonable de riesgos y la generación y optimización de los resultados económicos. Las decisiones de gestión serán adoptadas considerando amplios criterios técnicos, económicos y de mercado.",
      "La administración, representación, dirección, contratación y negociación con terceros corresponde a EL ASOCIANTE. EL ASOCIADO, sin intervenir en dichas funciones de gestión, tendrá derecho a recibir información razonable sobre el desarrollo de las actividades empresariales y a participar en las utilidades netas distribuibles conforme al presente contrato.",
      "Todos los actos, contratos, declaraciones, obligaciones y relaciones jurídicas que EL ASOCIANTE celebre con terceros serán exigibles únicamente frente a EL ASOCIANTE, sin comprometer a EL ASOCIADO frente a dichos terceros.",
      "EL ASOCIANTE deberá conservar la documentación que permita identificar la aplicación de la contribución a las actividades empresariales materia del presente contrato, así como los ingresos, costos, gastos, tributos y resultados derivados de dichas actividades.",
      "En el desarrollo de las actividades empresariales, EL ASOCIANTE aplicará criterios de diversificación, prudencia y sostenibilidad empresarial, evaluando las oportunidades y riesgos propios de las distintas actividades, unidades de negocio o proyectos comprendidos en su gestión. La aplicación de estos criterios constituye una obligación de gestión.",
    ],
  },
  6: {
    titulo: "SEXTA: PROTECCIÓN DE DATOS PERSONALES",
    parrafos: [
      "En cumplimiento de la Ley N° 29733, Ley de Protección de Datos Personales, EL ASOCIANTE y EL ASOCIADO declaran que se someten a las disposiciones previstas en esta ley, su reglamento, directivas y demás normas conexas, complementarias, modificatorias y/o sustitutorias.",
      "EL ASOCIANTE y EL ASOCIADO declaran que los datos personales que se proporcionen entre sí, así como los generados o recopilados en el marco del presente contrato, son reales y serán tratados en forma confidencial y sujetos a estrictas medidas de seguridad.",
      "EL ASOCIANTE, en caso corresponda, reconoce la responsabilidad de sus trabajadores y cualquier persona a su cargo de mantener permanente reserva y confidencialidad respecto de los datos personales a los que tengan acceso en el marco del presente contrato, obligación que subsistirá incluso después de concluido el contrato.",
    ],
  },
  7: {
    titulo: "SÉTIMA: PRINCIPIO DE BUENA FE CONTRACTUAL",
    parrafos: [
      "Con la suscripción del presente contrato, EL ASOCIANTE y EL ASOCIADO declaran su voluntad de sujetarse al principio de buena fe, comprometiéndose a respetar y cumplir de manera leal, transparente y conforme a lo pactado todas las estipulaciones contenidas en el presente instrumento.",
      "Las partes se obligan a actuar con honestidad, cooperación y corrección durante la ejecución, interpretación, liquidación y eventual extinción del presente contrato.",
    ],
  },
  8: {
    titulo:
      "OCTAVA: RETIRO ANTICIPADO, LIQUIDACIÓN ANTICIPADA Y RESOLUCIÓN POR INCUMPLIMIENTO",
    parrafos: [
      "Si EL ASOCIADO desea retirarse antes del vencimiento del plazo contractual, deberá comunicarlo a EL ASOCIANTE mediante una solicitud escrita y debidamente firmada, remitida al correo electrónico: atencionalcliente@mascapitalgroup.com. En dicha comunicación deberá consignar el nombre del Analista Comercial encargado de su atención, identificado en el numeral 14.2 del presente contrato, a fin de facilitar la correcta identificación y tramitación de la solicitud.",
      "La solicitud de retiro anticipado no genera derecho a exigir utilidades futuras. La liquidación anticipada se efectuará sobre los resultados reales generados por las actividades empresariales hasta la fecha de corte que EL ASOCIANTE comunique razonablemente.",
      "Si EL ASOCIADO solicita el retiro anticipado antes de cumplidos seis (6) meses desde la suscripción del presente contrato, no tendrá derecho a percibir participación alguna en las utilidades netas distribuibles. En consecuencia, la liquidación anticipada tendrá por finalidad determinar únicamente la restitución de la contribución efectuada.",
      "Si el retiro se solicita después de cumplidos seis (6) meses, la participación de EL ASOCIADO se reducirá excepcionalmente al diez por ciento (10.00 %) de las utilidades netas distribuibles generadas hasta la fecha de corte. En ningún caso EL ASOCIADO tendrá derecho a participar en utilidades que se generen con posterioridad a dicha fecha.",
      "Las condiciones especiales de participación previstas en los numerales 8.3 y 8.4 anteriores son aplicables exclusivamente a los supuestos de retiro anticipado y responden a la necesidad de preservar la estabilidad y planificación de las actividades empresariales materia del presente contrato. Estas condiciones forman parte de las reglas económicas del retiro anticipado acordadas por las partes desde la celebración del presente contrato.",
      "Comunicada la solicitud de retiro anticipado, EL ASOCIANTE practicará la liquidación anticipada y, de corresponder, determinará la participación en utilidades conforme a las reglas previstas en la presente cláusula. Asimismo, EL ASOCIANTE restituirá a EL ASOCIADO el saldo de la contribución que resulte procedente conforme a dicha liquidación, todo ello dentro de un plazo máximo de treinta (30) días hábiles contados desde la fecha de comunicación de la solicitud de retiro anticipado, independientemente de que el retiro se produzca antes o después de cumplidos seis (6) meses desde la suscripción del presente contrato.",
    ],
  },
  9: {
    titulo: "NOVENA: RESOLUCIÓN DEL CONTRATO",
    parrafos: [
      "Cualquiera de las partes podrá resolver el contrato conforme a las causales y procedimiento establecidos en la cláusula octava, previa comunicación formal con una anticipación no menor de siete (7) días hábiles, salvo supuesto de incumplimiento grave que habilite resolución inmediata conforme a ley.",
      "La resolución del contrato dará lugar a la liquidación de los resultados de las actividades empresariales hasta la fecha de corte correspondiente. Los derechos económicos de las partes y la restitución de la contribución serán determinados conforme a dicha liquidación y a las disposiciones del presente contrato.",
    ],
  },
  10: {
    titulo:
      "DÉCIMA: DECLARACIÓN DE CUMPLIMIENTO NORMATIVO Y EXCLUSIÓN REGULATORIA",
    parrafos: [
      "EL ASOCIANTE declara y garantiza que, en el rol que desempeña, ni sus socios, administradores, funcionarios, agentes o empleados con funciones directivas se encuentran orientados a la comisión de ilícitos o infracciones de naturaleza económica, administrativa, penal, de lavado de activos, financiamiento del terrorismo, corrupción de funcionarios, soborno, delitos financieros o delitos conexos.",
      "EL ASOCIANTE declara que el presente contrato no será utilizado para realizar ninguna de las operaciones previstas en el artículo 11 de la Ley N° 26702.",
      "EL ASOCIANTE manifiesta que ha implementado o implementará durante la vigencia del presente contrato medidas de integridad, verificación, auditoría, prevención del lavado de activos, prevención del financiamiento del terrorismo y control documentario razonable sobre la contribución recibida y su aplicación a las actividades empresariales materia del presente contrato.",
      "EL ASOCIANTE se compromete a comunicar a las autoridades competentes, de manera directa y oportuna, cualquier acto o conducta ilícita o corrupta de la que tuviera conocimiento, así como a adoptar medidas técnicas, organizativas y/o de personal apropiadas para evitar dichos actos o prácticas.",
      "Las partes reconocen que el artículo 11 de la Ley N° 26702 prohíbe realizar, sin autorización de la Superintendencia, actividades propias de empresas del sistema financiero o de seguros. En consecuencia, acuerdan que ninguna cláusula del presente contrato podrá interpretarse como habilitación para realizar tales actividades.",
    ],
  },
  11: {
    titulo: "DÉCIMA PRIMERA: PRINCIPIOS DEL CONTRATO",
    parrafos: [
      "Transparencia: Las partes acuerdan actuar con transparencia en las comunicaciones relacionadas con las actividades empresariales y con la liquidación de sus resultados, proporcionando información razonable, precisa y verificable.",
      "Cumplimiento legal: La ejecución del contrato se realizará en estricto cumplimiento de la legislación peruana aplicable, especialmente la Ley General de Sociedades, el Código Civil, la normativa tributaria y las normas de prevención de lavado de activos que correspondan.",
      "Confidencialidad: Las partes mantendrán reserva respecto de la información económica, comercial, operativa, documentaria y personal intercambiada durante la ejecución del contrato.",
      "Buena fe contractual: Las partes ejecutarán el contrato conforme a la confianza legítima, cooperación, lealtad, corrección y respeto de su finalidad asociativa.",
      "Primacía de la naturaleza asociativa: En caso de duda, el contrato deberá interpretarse como asociación en participación y no como operación financiera, préstamo, depósito, captación de fondos, producto de ahorro o inversión financiera supervisada.",
    ],
  },
  12: {
    titulo:
      "DÉCIMA SEGUNDA: LEY APLICABLE, SOLUCIÓN DE CONTROVERSIAS Y JURISDICCIÓN",
    parrafos: [
      "Las partes acuerdan que todos aquellos aspectos que no se encuentren regulados en el presente contrato se regirán por las disposiciones legales de la República del Perú.",
      "Cualquier controversia o conflicto derivado de la celebración, interpretación, ejecución, cumplimiento, incumplimiento, resolución o terminación del presente contrato será sometido, en primera instancia, a un procedimiento de conciliación extrajudicial, conforme a la legislación vigente.",
      "De no alcanzarse un acuerdo conciliatorio o de no ser posible la conciliación por las causales previstas en la ley, las partes acuerdan someter cualquier controversia a la competencia de los Jueces y Tribunales del Distrito Judicial de Lima, renunciando expresamente al fuero que pudiera corresponderles por razón de su domicilio.",
    ],
  },
  13: {
    titulo: "DÉCIMA TERCERA: MANDATO EXPRESO, LIMITADO Y ACCESORIO",
    parrafos: [
      "Con la finalidad de facilitar las gestiones instrumentales, documentarias, administrativas y de liquidación necesarias para la adecuada ejecución del presente contrato, EL ASOCIADO otorga mandato sin representación, de conformidad con los artículos 1790 y siguientes del Código Civil, a favor de AVANCE CORP S.A.C., con RUC N° 20611392088, para los fines establecidos en la presente cláusula. EL ASOCIANTE ejercerá el mandato en nombre propio, pero por cuenta e interés de EL ASOCIADO, y únicamente dentro de las facultades expresamente otorgadas. El mandato tiene carácter accesorio y limitado, y comprende exclusivamente las gestiones instrumentales, documentarias, administrativas y de liquidación necesarias para la ejecución del presente contrato y la determinación de los resultados derivados de las actividades empresariales",
      "El mandatario queda expresamente facultado, dentro de los límites del presente contrato, para:",
      "• Recibir y revisar comunicaciones, reportes y liquidaciones vinculadas con las actividades empresariales materia del presente contrato.",
      "• Suscribir cargos, constancias de recepción, actas de liquidación y documentos de conformidad, siempre que correspondan a resultados efectivamente liquidados.",
      "• Gestionar ante entidades bancarias únicamente actos documentarios o de validación necesarios para recibir pagos derivados de la liquidación.",
      "• Suscribir formularios de cumplimiento, origen de fondos o regularización documentaria que sean requeridos para ejecutar pagos válidamente liquidados.",
      "• Suscribir constancias de cancelación o finiquito únicamente luego de verificado el ingreso efectivo de los montos que correspondan a EL ASOCIADO.",
      "Cualquier acto realizado fuera de los límites del presente mandato será inoponible a EL ASOCIADO, sin perjuicio de la responsabilidad civil, penal, administrativa o de cualquier otra naturaleza que pudiera corresponder.",
    ],
  },
  15: {
    titulo: "DÉCIMA QUINTA: AUTORIZACIÓN PARA EL USO DE FIRMA IMPRESA",
    parrafos: [
      "Para la suscripción del presente contrato, EL ASOCIANTE podrá sustituir la firma autógrafa de su representante por su firma impresa, digitalizada o por cualquier otro medio de seguridad gráfico, mecánico o electrónico que permita identificar razonablemente al representante autorizado, a lo cual EL ASOCIADO presta su autorización y plena conformidad.",
      "EL ASOCIADO reconoce que la utilización de la firma impresa, digitalizada o reproducida mediante cualquiera de los medios antes señalados tendrá la misma validez y eficacia que la firma autógrafa del representante de EL ASOCIANTE, siempre que haya sido incorporada al presente contrato con autorización de EL ASOCIANTE.",
      "La autorización prevista en esta cláusula no impide que EL ASOCIANTE emplee firma autógrafa, firma digital u otro mecanismo válido de manifestación de voluntad, conforme a la legislación aplicable.",
    ],
  },
  16: {
    titulo: "DÉCIMA SEXTA: CLÁUSULA DE PREVALENCIA E INTERPRETACIÓN",
    parrafos: [
      "En caso de contradicción, duda o vacío interpretativo, prevalecerá la naturaleza de contrato asociativo de asociación en participación regulado por la Ley General de Sociedades.",
      "Ninguna cláusula podrá interpretarse como interés, renta fija, rendimiento garantizado, depósito, mutuo, préstamo, crédito, captación de dinero del público, intermediación financiera, administración de fondos de terceros, producto financiero supervisado, seguro o intermediación de seguros.",
      "Si alguna autoridad, entidad financiera, árbitro o juez considera que una estipulación puede ser interpretada como actividad regulada o financiera, dicha estipulación deberá interpretarse restrictivamente o, de ser necesario, tenerse por no puesta, conservándose la validez del contrato en todo aquello que sea compatible con su naturaleza asociativa.",
    ],
  },
};

function clausulaEstatica(numero: number): Content[] {
  const clausula = CLAUSULAS_ESTATICAS[numero];
  if (!clausula) return [];

  const parrafos = clausula.parrafos.map((texto, indice) => {
    if (numero === 11) {
      return parrafoConEtiqueta(`${String.fromCharCode(97 + indice)})`, texto);
    }
    if (numero === 13 && indice >= 2 && indice <= 6) {
      return parrafoConEtiqueta(
        `${String.fromCharCode(97 + indice - 2)})`,
        texto.replace(/^•\s*/, ""),
      );
    }
    const numeral = numero === 13 && indice === 7 ? 3 : indice + 1;
    return parrafoNumerado(numero, numeral, texto);
  });

  return [
    tituloClausula(clausula.titulo),
    ...parrafos,
  ];
}

function tablaLiquidacion(): ContentTable {
  const filas = [
    [
      "Hito",
      "Periodicidad / fecha",
      "Naturaleza jurídica",
      "Efecto contractual",
    ],
    [
      "Contribución",
      "A la firma o fecha acordada",
      "Contribución asociativa",
      "No es depósito, préstamo, ahorro, crédito ni captación.",
    ],
    [
      "Liquidación ordinaria",
      "Al vencimiento del contrato",
      "Determinación final del resultado",
      "Permite determinar las utilidades netas distribuibles",
    ],
    [
      "Liquidaciones parciales",
      "Cuando EL ASOCIANTE las practique durante la vigencia del contrato",
      "Determinación parcial de resultados",
      "Permite distribución parcial de utilidades, de ser el caso",
    ],
    [
      "Pago de participación",
      "Luego de la liquidación aprobada o comunicada",
      "Distribución de utilidades",
      "Procede respecto de las utilidades netas distribuibles",
    ],
    [
      "Restitución de la contribución",
      "Conforme a la cláusula quinta u octava",
      "Restitución del saldo resultante de la liquidación",
      "Procede respecto del saldo que resulte a favor de EL ASOCIADO luego de la liquidación correspondiente.",
    ],
  ];
  return {
    table: {
      headerRows: 1,
      dontBreakRows: true,
      widths: ["20%", "25%", "24%", "31%"],
      body: filas.map((fila, indice) =>
        fila.map((texto) => ({
          text: texto,
          bold: indice === 0,
          color: indice === 0 ? "#ffffff" : "#15264d",
          fillColor: indice === 0
            ? "#183969"
            : indice % 2 === 0
            ? "#f2f5f8"
            : "#ffffff",
          margin: [3, 3, 3, 3],
        }))
      ),
    },
    layout: {
      hLineColor: () => "#cbd5e1",
      vLineColor: () => "#cbd5e1",
      hLineWidth: () => 0.5,
      vLineWidth: () => 0.5,
    },
    fontSize: 7,
    margin: [0, 5, 0, 8],
  };
}

export function nombreArchivoContrato(datos: ContratoPdfDatos): string {
  const nombre = datos.titular.nombreCompleto
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Za-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .toUpperCase();
  return `Contrato-${datos.contrato.numero}-${nombre}.pdf`;
}

export function construirContratoPdf(
  datos: ContratoPdfDatos,
  assets: ContratoPdfAssets,
): TDocumentDefinitions {
  const { contrato, titular, analista } = datos;
  const documento = `${
    etiquetaDocumento(titular.tipoDocumento)
  } N° ${titular.documento}`;
  const porcentajeLetras = enteroEnLetras(contrato.porcentaje);
  const fechaFirma = fechaPartes(contrato.fechaInicio);

  const contenido: Content[] = [
    {
      text: "CONTRATO DE ASOCIACIÓN EN PARTICIPACIÓN",
      style: "titulo",
      margin: [0, 5, 0, 12],
    },
    parrafo(
      "Conste por el presente documento, el Contrato de Asociación en Participación que celebran:",
    ),
    parrafo([
      { text: "De una parte, " },
      { text: "AVANCE CORP S.A.C.", bold: true },
      { text: " con RUC N° " },
      { text: "20611392088", bold: true },
      {
        text: ", debidamente representada por su Gerente General, Sr. ",
      },
      { text: "Kirk Edilberto Sánchez Ríos", bold: true },
      { text: ", con " },
      { text: "DNI N° 44232474", bold: true },
      {
        text:
          ", según poderes inscritos en la partida electrónica N° 15370250 del Registro de Personas Jurídicas de Lima, con domicilio en ",
      },
      {
        text:
          "Av. República de Panamá N° 3635, Urb. El Palomar, distrito de San Isidro, provincia y departamento de Lima",
        bold: true,
      },
      {
        text: ", a quien se le denominará EL ASOCIANTE y, de la otra parte;",
      },
    ]),
    parrafo([
      { text: titular.nombreCompleto, bold: true },
      { text: ", con " },
      { text: documento, bold: true },
      { text: " y con domicilio en " },
      { text: titular.domicilio.toUpperCase(), bold: true },
      {
        text:
          ", a quien se le denominará EL ASOCIADO, bajo los términos y condiciones siguientes:",
      },
    ]),
    ...clausulaEstatica(1),
    ...clausulaEstatica(2),
    {
      stack: [
        tituloClausula(
          "TERCERA: CONTRIBUCIÓN DEL ASOCIADO, RIESGO EMPRESARIAL Y PARTICIPACIÓN EN UTILIDADES",
        ),
        parrafoNumerado(3, 1, [
          {
            text:
              "EL ASOCIADO se obliga a efectuar una contribución dineraria ascendente a ",
          },
          {
            text: `${montoVisible(contrato.capital, contrato.moneda)} (${
              montoEnLetras(contrato.capital, contrato.moneda)
            })`,
            bold: true,
          },
          {
            text:
              ", mediante la cual adquiere el derecho a participar en los resultados o utilidades que generen las actividades empresariales materia del presente contrato.",
          },
        ]),
      ],
      unbreakable: true,
    },
    parrafoNumerado(
      3,
      2,
      "La contribución será entregada a EL ASOCIANTE mediante transferencia o depósito en la cuenta bancaria que este señale para fines operativos internos.",
    ),
    parrafoNumerado(
      3,
      3,
      "La contribución será aplicada al desarrollo de las actividades empresariales materia del presente contrato, cuya gestión corresponde a EL ASOCIANTE conforme a los criterios establecidos en la cláusula cuarta. EL ASOCIADO reconoce que los resultados de su participación se encuentran vinculados al desarrollo y resultados de dichas actividades empresariales.",
    ),
    parrafoNumerado(3, 4, [
      { text: "EL ASOCIADO tendrá derecho a participar en el " },
      {
        text: `${porcentajeLetras} POR CIENTO (${
          contrato.porcentaje.toFixed(2)
        } %)`,
        bold: true,
      },
      {
        text:
          " de las utilidades netas distribuibles que generen las actividades empresariales materia del presente contrato, siempre que existan utilidades netas suficientes y liquidadas conforme al presente contrato.",
      },
    ]),
    parrafoNumerado(
      3,
      5,
      "Para determinar los resultados económicos de las actividades empresariales se considerarán los ingresos obtenidos y, cuando corresponda, los gastos, tributos, cargas, contingencias y demás conceptos directamente vinculados con su desarrollo. La contribución de EL ASOCIADO participa de dichos resultados, encontrándose cualquier eventual pérdida limitada exclusivamente al monto de su contribución, sin que EL ASOCIADO se encuentre obligado a realizar contribuciones adicionales ni a responder con su patrimonio por obligaciones asumidas por EL ASOCIANTE frente a terceros.",
    ),
    parrafoNumerado(
      3,
      6,
      "La utilidad neta distribuible se determinará deduciendo de los ingresos efectivamente percibidos por las actividades empresariales los costos directos, gastos directos, tributos, cargas, provisiones razonables, pérdidas y obligaciones documentadas vinculadas con dichas actividades.",
    ),
    parrafoNumerado(
      3,
      7,
      "EL ASOCIADO podrá recibir información razonable sobre el desarrollo de las actividades empresariales materia del presente contrato, de acuerdo con su naturaleza y cuando resulte pertinente, sin que ello implique la obligación de emitir reportes con una periodicidad determinada ni suponga por sí mismo la determinación de utilidades.",
    ),
    parrafoNumerado(
      3,
      8,
      "La liquidación ordinaria se realizará al vencimiento del plazo contractual, conforme a lo previsto en la cláusula quinta.",
    ),
    parrafoNumerado(
      3,
      9,
      "Durante la vigencia del contrato podrán efectuarse una o más liquidaciones parciales cuando existan utilidades netas distribuibles efectivamente generadas. EL ASOCIANTE determinará la oportunidad y periodicidad de dichas liquidaciones atendiendo a la naturaleza y resultados de las actividades empresariales. Las participaciones distribuidas mediante estas liquidaciones serán consideradas pagos parciales a cuenta de la liquidación final, sin constituir pagos fijos ni generar una obligación de distribución periódica.",
    ),
    parrafoNumerado(
      3,
      10,
      "La participación en utilidades que corresponda a EL ASOCIADO será determinada en la liquidación ordinaria prevista en la cláusula quinta o, de ser el caso, en las liquidaciones parciales. De existir utilidades netas distribuibles, la participación correspondiente será puesta a disposición de EL ASOCIADO dentro de los plazos previstos en el presente contrato. Si el vencimiento coincide con día inhábil, el pago se efectuará el primer día hábil siguiente, sin que ello configure mora.",
    ),
    parrafoNumerado(
      3,
      11,
      "Para efectos de ejecución, las partes reemplazan cualquier cronograma de pagos fijos por el siguiente esquema de información y liquidación:",
    ),
    tablaLiquidacion(),
    ...clausulaEstatica(4),
    tituloClausula("QUINTA: PLAZO DE DURACIÓN DEL CONTRATO"),
    parrafoNumerado(5, 1, [
      {
        text: "El plazo de duración obligatoria del presente contrato será de ",
      },
      {
        text: plazoVisible(contrato.fechaInicio, contrato.fechaVencimiento)
          .toUpperCase(),
        bold: true,
      },
      {
        text:
          ", contado a partir de la fecha de suscripción del presente documento.",
      },
    ]),
    parrafoNumerado(
      5,
      2,
      "El contrato podrá renovarse únicamente por acuerdo expreso y escrito de las partes. No habrá renovación automática.",
    ),
    parrafoNumerado(
      5,
      3,
      "Vencido el plazo contractual, EL ASOCIANTE practicará la liquidación final correspondiente y efectuará el pago de la participación en utilidades pendiente de distribución, considerando las participaciones que hubieran sido pagadas durante la vigencia del contrato. Asimismo, dentro de un plazo máximo de siete (7) días hábiles contados desde dicho vencimiento, EL ASOCIANTE restituirá a EL ASOCIADO el saldo de la contribución determinado conforme a la liquidación final.",
    ),
    ...clausulaEstatica(6),
    ...clausulaEstatica(7),
    ...clausulaEstatica(8),
    ...clausulaEstatica(9),
    ...clausulaEstatica(10),
    ...clausulaEstatica(11),
    ...clausulaEstatica(12),
    ...clausulaEstatica(13),
    tituloClausula(
      "DÉCIMA CUARTA: DOMICILIO, NOTIFICACIONES Y ATENCIÓN COMERCIAL",
    ),
    parrafoNumerado(
      14,
      1,
      "Las partes señalan como sus domicilios para efectos de todas las comunicaciones y notificaciones relacionadas con el presente contrato los indicados en la parte introductoria del presente documento.",
    ),
    parrafoNumerado(14, 2, [
      {
        text:
          "Para comunicaciones operativas y coordinaciones vinculadas con la ejecución del presente contrato, EL ASOCIADO señala el correo electrónico ",
      },
      { text: titular.correo, bold: true },
      {
        text: " y EL ASOCIANTE señala el correo electrónico ",
      },
      { text: "atencionalcliente@mascapitalgroup.com", bold: true },
      {
        text:
          ". Asimismo, EL ASOCIADO contará con un Analista Comercial encargado de brindarle atención, orientación y acompañamiento durante la vigencia del contrato, cuyos datos son los siguientes: ",
      },
      { text: analista.nombreCompleto, bold: true },
      { text: ", con número de celular " },
      { text: analista.celular, bold: true },
      { text: " y correo electrónico " },
      { text: analista.correo, bold: true },
      {
        text:
          ". La designación del referido Analista Comercial tiene únicamente fines de atención, orientación y coordinación operativa, y no le otorga facultades de representación, disposición de fondos ni asunción de obligaciones en nombre de EL ASOCIANTE.",
      },
    ]),
    parrafoNumerado(
      14,
      3,
      "Cualquier variación de domicilio, correo electrónico, número telefónico o funcionario encargado deberá ser comunicada por escrito a la otra parte. Mientras no se comunique la variación, serán válidas las notificaciones cursadas a los domicilios, correos electrónicos y datos consignados en este contrato.",
    ),
    ...clausulaEstatica(15),
    ...clausulaEstatica(16),
    tituloClausula("DÉCIMA SÉTIMA: DECLARACIÓN FINAL DE LAS PARTES"),
    parrafoNumerado(
      17,
      1,
      "Las partes declaran haber leído íntegramente el presente contrato, comprender su naturaleza asociativa y conocer los derechos y obligaciones que asumen. Asimismo, reconocen que la finalidad de la relación contractual es permitir que EL ASOCIADO participe en los resultados económicos derivados de las actividades empresariales gestionadas por EL ASOCIANTE, bajo los criterios de diligencia, transparencia y gestión empresarial previstos en el presente contrato.",
    ),
    parrafoNumerado(
      17,
      2,
      "Las partes reconocen que los resultados económicos del presente contrato se encuentran vinculados al desarrollo efectivo de las actividades empresariales gestionadas por EL ASOCIANTE y serán determinados conforme a las reglas de liquidación previstas en este contrato, reconociendo ambas partes la naturaleza empresarial y asociativa de su participación.",
    ),
    parrafo(
      `Las partes suscriben el presente documento en señal de conformidad a los ${fechaFirma.dia} días del mes de ${fechaFirma.mes} del ${fechaFirma.anio}.`,
    ),
    {
      columns: [
        {
          width: "48%",
          stack: [
            {
              text: "____________________________",
              alignment: "center",
              margin: [0, 42, 0, 0],
            },
            {
              text: titular.nombreCompleto,
              bold: true,
              alignment: "center",
              fontSize: 8,
            },
            {
              text: documento,
              bold: true,
              alignment: "center",
              fontSize: 8,
            },
            {
              text: "EL ASOCIADO",
              bold: true,
              alignment: "center",
              fontSize: 8,
            },
          ],
        },
        {
          width: "48%",
          stack: [
            {
              image: assets.firmaAsociante,
              cover: {
                width: 93,
                height: 65,
                align: "center",
                valign: "center",
              },
              alignment: "center",
              margin: [0, 0, 0, -3],
            },
            {
              text: "AVANCE CORP SAC",
              bold: true,
              alignment: "center",
              fontSize: 10.5,
              lineHeight: 1,
            },
            {
              text: "RUC N° 20611392088",
              bold: true,
              alignment: "center",
              fontSize: 10.5,
              lineHeight: 1,
            },
            {
              text: "EL ASOCIANTE",
              bold: true,
              alignment: "center",
              fontSize: 10.5,
              lineHeight: 1,
            },
          ],
        },
      ],
      columnGap: 18,
      unbreakable: true,
      margin: [0, 24, 0, 5],
    } as ContentColumns,
  ];

  return {
    info: {
      title: `Contrato ${contrato.numero}`,
      author: "Avance Corp S.A.C.",
      subject: "Contrato de Asociación en Participación",
      keywords: `contrato,${contrato.numero},avance corp`,
    },
    pageSize: "A4",
    pageMargins: [66, 126, 58, 94],
    // Ancla explícitamente el fondo al lienzo para que el contrato no dependa del
    // posicionamiento implícito de pdfmake en páginas de continuación.
    background: () => ({
      image: assets.fondo,
      width: 595.28,
      height: 841.89,
      absolutePosition: { x: 0, y: 0 },
    }),
    header: () => ({
      text: contrato.numero,
      alignment: "right",
      color: "#183969",
      bold: true,
      fontSize: 9,
      margin: [0, 82, 58, 0],
    }),
    footer: (pagina, total) => ({
      text: `${pagina} / ${total}`,
      alignment: "right",
      color: "#64748b",
      fontSize: 7,
      margin: [0, 0, 58, 52],
    }),
    content: contenido,
    defaultStyle: {
      font: "Roboto",
      fontSize: 8.6,
      color: "#17233b",
      lineHeight: 1.16,
    },
    styles: {
      titulo: {
        fontSize: 14,
        bold: true,
        alignment: "center",
        color: "#183969",
      },
      clausula: {
        fontSize: 9.4,
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
