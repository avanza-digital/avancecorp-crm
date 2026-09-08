import type { Content, ContentColumns, ContentTable, ContentText, TDocumentDefinitions } from 'pdfmake/interfaces'
import type { TipoDocumento } from './documento'

export interface ContratoPdfDatos {
  contrato: {
    numero: string
    capital: number
    moneda: 'PEN' | 'USD'
    porcentaje: number
    fechaInicio: string
    fechaVencimiento: string
  }
  titular: {
    nombreCompleto: string
    tipoDocumento: TipoDocumento
    documento: string
    domicilio: string
    correo: string
  }
  analista: {
    nombreCompleto: string
    documento: string
    celular: string
    correo: string
  }
  /** Se conservan en el CRM, pero por decisión legal no aparecen en el PDF. */
  cotitulares?: Array<{
    nombreCompleto: string
    tipoDocumento: TipoDocumento
    documento: string
  }>
}

export interface ContratoPdfAssets {
  fondo: string
  firmaAsociante?: string
}

const UNIDADES = [
  'CERO', 'UNO', 'DOS', 'TRES', 'CUATRO', 'CINCO', 'SEIS', 'SIETE', 'OCHO', 'NUEVE',
  'DIEZ', 'ONCE', 'DOCE', 'TRECE', 'CATORCE', 'QUINCE', 'DIECISÉIS', 'DIECISIETE',
  'DIECIOCHO', 'DIECINUEVE', 'VEINTE', 'VEINTIUNO', 'VEINTIDÓS', 'VEINTITRÉS',
  'VEINTICUATRO', 'VEINTICINCO', 'VEINTISÉIS', 'VEINTISIETE', 'VEINTIOCHO', 'VEINTINUEVE',
] as const
const DECENAS = ['', '', '', 'TREINTA', 'CUARENTA', 'CINCUENTA', 'SESENTA', 'SETENTA', 'OCHENTA', 'NOVENTA'] as const
const CENTENAS = ['', 'CIENTO', 'DOSCIENTOS', 'TRESCIENTOS', 'CUATROCIENTOS', 'QUINIENTOS', 'SEISCIENTOS', 'SETECIENTOS', 'OCHOCIENTOS', 'NOVECIENTOS'] as const

function enteroEnLetras(numero: number): string {
  const n = Math.trunc(Math.abs(numero))
  if (n < 30) return UNIDADES[n] ?? ''
  if (n < 100) {
    const decena = Math.trunc(n / 10)
    const unidad = n % 10
    return `${DECENAS[decena]}${unidad ? ` Y ${UNIDADES[unidad]}` : ''}`
  }
  if (n === 100) return 'CIEN'
  if (n < 1_000) {
    const centena = Math.trunc(n / 100)
    const resto = n % 100
    return `${CENTENAS[centena]}${resto ? ` ${enteroEnLetras(resto)}` : ''}`
  }
  if (n < 1_000_000) {
    const miles = Math.trunc(n / 1_000)
    const resto = n % 1_000
    const prefijo = miles === 1 ? 'MIL' : `${enteroEnLetras(miles).replace(/UNO$/, 'UN')} MIL`
    return `${prefijo}${resto ? ` ${enteroEnLetras(resto)}` : ''}`
  }
  if (n < 1_000_000_000) {
    const millones = Math.trunc(n / 1_000_000)
    const resto = n % 1_000_000
    const prefijo = millones === 1
      ? 'UN MILLÓN'
      : `${enteroEnLetras(millones).replace(/UNO$/, 'UN')} MILLONES`
    return `${prefijo}${resto ? ` ${enteroEnLetras(resto)}` : ''}`
  }
  throw new RangeError('El capital excede el máximo soportado por el contrato PDF.')
}

function montoEnLetras(capital: number, moneda: 'PEN' | 'USD'): string {
  const centimos = Math.round((capital - Math.trunc(capital)) * 100)
  const unidad = moneda === 'PEN' ? 'SOLES' : 'DÓLARES AMERICANOS'
  return `${enteroEnLetras(capital).replace(/UNO$/, 'UN')} Y ${String(centimos).padStart(2, '0')}/100 ${unidad}`
}

function montoVisible(capital: number, moneda: 'PEN' | 'USD'): string {
  const simbolo = moneda === 'PEN' ? 'S/' : 'US$'
  return `${simbolo} ${capital.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function etiquetaDocumento(tipo: TipoDocumento): string {
  if (tipo === 'CE') return 'Carné de Extranjería'
  if (tipo === 'PASAPORTE') return 'Pasaporte'
  return 'DNI'
}

function fechaPartes(iso: string): { dia: number; mes: string; anio: number } {
  const [anio = 0, mes = 1, dia = 1] = iso.split('-').map(Number)
  const meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ]
  return { dia, mes: meses[mes - 1] ?? '', anio }
}

function ultimoDiaDelMes(anio: number, mes: number): number {
  return new Date(Date.UTC(anio, mes, 0)).getUTCDate()
}

function mesesCompletosContrato(inicioIso: string, finIso: string): number {
  const [ai = 0, mi = 1, di = 1] = inicioIso.split('-').map(Number)
  const [af = 0, mf = 1, df = 1] = finIso.split('-').map(Number)
  const mesesCalendario = (af - ai) * 12 + mf - mi
  if (mesesCalendario <= 0) return 0

  // Al sumar meses, el formulario ajusta fechas como 31/08 al último día de
  // febrero. Ese día ajustado sí completa el mes contractual correspondiente.
  const diaAniversarioAjustado = Math.min(di, ultimoDiaDelMes(af, mf))
  return Math.max(0, mesesCalendario - (df < diaAniversarioAjustado ? 1 : 0))
}

function plazoVisible(inicioIso: string, finIso: string): string {
  const meses = mesesCompletosContrato(inicioIso, finIso)
  if (meses > 0 && meses % 12 === 0) {
    const anios = meses / 12
    return `${anios === 1 ? 'un' : enteroEnLetras(anios).toLowerCase()} (${anios}) ${anios === 1 ? 'año' : 'años'}`
  }
  return `${enteroEnLetras(meses).toLowerCase()} (${meses}) meses`
}

function parrafo(text: string, opciones: Record<string, unknown> = {}): Content {
  return { text, style: 'parrafo', ...opciones } as Content
}

function tituloClausula(texto: string): ContentText {
  return { text: texto, style: 'clausula', margin: [0, 9, 0, 4] }
}

const CLAUSULAS_ESTATICAS: Record<number, { titulo: string; parrafos: string[] }> = {
  1: {
    titulo: 'PRIMERA: ANTECEDENTES',
    parrafos: [
      'EL ASOCIANTE es una persona jurídica dedicada, conforme a su objeto social, a realizar operaciones e inversiones en diferentes campos de la actividad económica, prestación de servicios de consultoría, asesoría, asistencia técnica, operación, puesta en marcha, administración, management y/o servicios vinculados al sector de inversiones a nivel nacional e internacional; así como a realizar inversiones, constituir, adquirir y/o integrar sociedades, instituciones, fundaciones, corporaciones o asociaciones, y efectuar inversiones de capital en bienes muebles incorporales, acciones, bonos, debentures, participaciones sociales, cuotas, derechos en sociedades y otros títulos valores mobiliarios, así como administrar dichas inversiones propias.',
      'EL ASOCIADO declara que, de forma libre y voluntaria, desea participar en los resultados económicos de las actividades, unidades de negocio y/o proyectos empresariales desarrollados por EL ASOCIANTE, mediante una contribución económica, sin adquirir derechos societarios sobre la empresa ni intervenir en su administración.',
      'El presente contrato se celebra en el marco de la Ley N.° 26887, Ley General de Sociedades, bajo la modalidad de asociación en participación. En virtud de este contrato, EL ASOCIANTE concede a EL ASOCIADO el derecho a participar en los resultados o utilidades que generen las actividades, unidades de negocio o proyectos empresariales materia del presente contrato, a cambio de la contribución económica que este último se obliga a efectuar.',
      'La contribución de EL ASOCIADO será destinada exclusivamente a las actividades, unidades de negocio o proyectos empresariales materia del presente contrato, los cuales deberán encontrarse debidamente identificados o ser determinables conforme a la información y documentación proporcionada por EL ASOCIANTE.',
    ],
  },
  2: {
    titulo: 'SEGUNDA: NATURALEZA, OBJETO Y ACTIVIDAD EMPRESARIAL',
    parrafos: [
      'Por el presente contrato, EL ASOCIANTE concede a EL ASOCIADO una participación en las utilidades netas distribuibles que se generen como resultado de las actividades empresariales de EL ASOCIANTE, a cambio de la contribución descrita en la cláusula tercera. Las partes dejan constancia de que la finalidad del presente contrato es permitir que EL ASOCIADO participe en los resultados económicos derivados de la gestión empresarial desarrollada por EL ASOCIANTE, quien asume de manera exclusiva la responsabilidad, dirección, administración, ejecución y gestión de las actividades empresariales materia del presente contrato.',
      'Las actividades empresariales materia del presente contrato deberán ser reales, lícitas, determinadas o determinables, verificables y desarrolladas directamente por EL ASOCIANTE o a través de sociedades, proyectos o unidades de negocio en las que este participe legítimamente.',
      'EL ASOCIANTE conserva la dirección, gestión, administración, representación y responsabilidad frente a terceros respecto de las actividades empresariales materia del presente contrato. EL ASOCIADO no interviene frente a terceros ni participa en la administración o representación de dichas actividades, y tampoco adquiere la condición de socio, accionista, gerente, administrador ni representante de EL ASOCIANTE.',
      'Toda referencia económica contenida en este contrato deberá interpretarse como participación contractual en resultados o utilidades de las actividades empresariales desarrolladas por EL ASOCIANTE, y no como una obligación propia de un producto o servicio financiero.',
    ],
  },
  4: {
    titulo: 'CUARTA: GESTIÓN DE LAS ACTIVIDADES EMPRESARIALES, REPRESENTACIÓN FRENTE A TERCEROS Y CONTROL DOCUMENTARIO',
    parrafos: [
      'La gestión de las actividades empresariales corresponde única y exclusivamente a EL ASOCIANTE, quien actúa en nombre propio frente a terceros, conserva su administración y asume la responsabilidad que corresponda por sus actos de gestión. En el desarrollo de dichas actividades, EL ASOCIANTE actuará con la diligencia ordinaria exigible a un operador empresarial, procurando una gestión profesional, diligente, eficiente y prudente, orientada a minimizar riesgos y procurar la generación y optimización de los resultados económicos de las actividades empresariales materia del presente contrato. Las decisiones de gestión serán adoptadas considerando amplios criterios técnicos, económicos y de mercado.',
      'EL ASOCIADO no participa en la administración, representación, dirección, contratación ni negociación con terceros. Su derecho se limita a recibir información razonable sobre el desarrollo de las actividades empresariales y a participar en las utilidades netas distribuibles conforme a la liquidación prevista en el presente contrato.',
      'Todos los actos, contratos, declaraciones, obligaciones y relaciones jurídicas que EL ASOCIANTE celebre con terceros serán exigibles únicamente frente a EL ASOCIANTE, sin comprometer a EL ASOCIADO frente a dichos terceros.',
      'EL ASOCIANTE deberá conservar la documentación que permita identificar la aplicación de la contribución a las actividades empresariales materia del presente contrato, así como los ingresos, costos, gastos, tributos y resultados derivados de dichas actividades.',
    ],
  },
  6: {
    titulo: 'SEXTA: PROTECCIÓN DE DATOS PERSONALES',
    parrafos: [
      'En cumplimiento de la Ley N.° 29733, Ley de Protección de Datos Personales, EL ASOCIANTE y EL ASOCIADO declaran que se someten a las disposiciones previstas en esta ley, su reglamento, directivas y demás normas conexas, complementarias, modificatorias y/o sustitutorias.',
      'EL ASOCIANTE y EL ASOCIADO declaran que los datos personales que se proporcionen entre sí, así como los generados o recopilados en el marco del presente contrato, son reales y serán tratados en forma confidencial y sujetos a estrictas medidas de seguridad.',
      'EL ASOCIANTE, en caso corresponda, reconoce la responsabilidad de sus trabajadores y cualquier persona a su cargo de mantener permanente reserva y confidencialidad respecto de los datos personales a los que tengan acceso en el marco del presente contrato, obligación que subsistirá incluso después de concluido el contrato.',
    ],
  },
  7: {
    titulo: 'SÉTIMA: PRINCIPIO DE BUENA FE CONTRACTUAL',
    parrafos: [
      'Con la suscripción del presente contrato, EL ASOCIANTE y EL ASOCIADO declaran su voluntad de sujetarse al principio de buena fe, comprometiéndose a respetar y cumplir de manera leal, transparente y conforme a lo pactado todas las estipulaciones contenidas en el presente instrumento.',
      'Las partes se obligan a actuar con honestidad, cooperación y corrección durante la ejecución, interpretación, liquidación y eventual extinción del presente contrato.',
    ],
  },
  8: {
    titulo: 'OCTAVA: RETIRO ANTICIPADO, LIQUIDACIÓN ANTICIPADA Y RESOLUCIÓN POR INCUMPLIMIENTO',
    parrafos: [
      'Si EL ASOCIADO desea retirarse antes del vencimiento del plazo contractual, deberá comunicarlo a EL ASOCIANTE mediante una solicitud escrita y debidamente firmada, remitida al correo electrónico: atencionalcliente@mascapitalgroup.com. En dicha comunicación deberá consignar el nombre del Analista Comercial encargado de su atención, identificado en el numeral 14.2 del presente contrato, a fin de facilitar la correcta identificación y tramitación de la solicitud.',
      'La solicitud de retiro anticipado no genera derecho a exigir utilidades futuras. La liquidación anticipada se efectuará sobre los resultados reales generados por las actividades empresariales hasta la fecha de corte que EL ASOCIANTE comunique razonablemente.',
      'Si EL ASOCIADO solicita el retiro anticipado antes de cumplidos seis (6) meses desde la suscripción del presente contrato, la participación prevista en el numeral 3.4 se reducirá excepcionalmente al trece por ciento (13.00 %) de las utilidades netas distribuibles que correspondan al período efectivamente transcurrido hasta la fecha de corte. En ningún caso EL ASOCIADO tendrá derecho a participar en utilidades que se generen con posterioridad a dicha fecha.',
      'Si el retiro se solicita después de cumplidos seis (6) meses, EL ASOCIADO tendrá derecho a que se liquide su participación sobre las utilidades netas efectivamente generadas hasta la fecha de corte, descontándose los gastos administrativos directos, necesarios, documentados y razonables vinculados a la liquidación anticipada.',
      'La reducción del porcentaje de participación prevista en el numeral 8.3 anterior constituye una condición especial aplicable al retiro anticipado y responde a la necesidad de preservar la estabilidad y planificación de las actividades empresariales materia del presente contrato.',
      'En consecuencia, no constituye una penalidad, cláusula penal, interés, cargo financiero ni sanción económica de ninguna naturaleza.',
      'Comunicada la solicitud de retiro anticipado, EL ASOCIANTE practicará la liquidación anticipada dentro de los siete (7) días hábiles siguientes. De existir utilidades netas distribuibles, la participación que corresponda a EL ASOCIADO será determinada y puesta a su disposición dentro de dicho plazo. Asimismo, el saldo de la contribución cuya restitución resulte procedente conforme a la liquidación anticipada será pagado dentro de los cinco (5) días hábiles siguientes.',
    ],
  },
  9: {
    titulo: 'NOVENA: RESOLUCIÓN DEL CONTRATO',
    parrafos: [
      'Cualquiera de las partes podrá resolver el contrato conforme a las causales y procedimiento establecidos en la cláusula octava, previa comunicación formal con una anticipación no menor de siete (7) días hábiles, salvo supuesto de incumplimiento grave que habilite resolución inmediata conforme a ley.',
      'La resolución del contrato obligará a practicar la liquidación de los resultados de las actividades empresariales hasta la fecha de corte correspondiente. Ninguna resolución generará, por sí misma, obligación de pago fijo, interés, rendimiento o devolución automática de la contribución que no se encuentre sustentada en la liquidación correspondiente.',
    ],
  },
  10: {
    titulo: 'DÉCIMA: DECLARACIÓN DE CUMPLIMIENTO NORMATIVO Y EXCLUSIÓN REGULATORIA',
    parrafos: [
      'EL ASOCIANTE declara y garantiza que, en el rol que desempeña, ni sus socios, administradores, funcionarios, agentes o empleados con funciones directivas se encuentran orientados a la comisión de ilícitos o infracciones de naturaleza económica, administrativa, penal, de lavado de activos, financiamiento del terrorismo, corrupción de funcionarios, soborno, delitos financieros o delitos conexos.',
      'EL ASOCIANTE declara que el presente contrato no será utilizado para realizar ninguna de las operaciones previstas en el artículo 11 de la Ley N.° 26702.',
      'EL ASOCIANTE manifiesta que ha implementado o implementará durante la vigencia del presente contrato medidas de integridad, verificación, auditoría, prevención del lavado de activos, prevención del financiamiento del terrorismo y control documentario razonable sobre la contribución recibida y su aplicación a las actividades empresariales materia del presente contrato.',
      'EL ASOCIANTE se compromete a comunicar a las autoridades competentes, de manera directa y oportuna, cualquier acto o conducta ilícita o corrupta de la que tuviera conocimiento, así como a adoptar medidas técnicas, organizativas y/o de personal apropiadas para evitar dichos actos o prácticas.',
      'Las partes reconocen que el artículo 11 de la Ley N.° 26702 prohíbe realizar, sin autorización de la Superintendencia, actividades propias de empresas del sistema financiero o de seguros. En consecuencia, acuerdan que ninguna cláusula del presente contrato podrá interpretarse como habilitación para realizar tales actividades.',
    ],
  },
  11: {
    titulo: 'DÉCIMA PRIMERA: PRINCIPIOS DEL CONTRATO',
    parrafos: [
      'Transparencia: Las partes acuerdan actuar con transparencia en las comunicaciones relacionadas con las actividades empresariales y con la liquidación de sus resultados, proporcionando información razonable, precisa y verificable.',
      'Cumplimiento legal: La ejecución del contrato se realizará en estricto cumplimiento de la legislación peruana aplicable, especialmente la Ley General de Sociedades, el Código Civil, la normativa tributaria y las normas de prevención de lavado de activos que correspondan.',
      'Confidencialidad: Las partes mantendrán reserva respecto de la información económica, comercial, operativa, documentaria y personal intercambiada durante la ejecución del contrato.',
      'Buena fe contractual: Las partes ejecutarán el contrato conforme a la confianza legítima, cooperación, lealtad, corrección y respeto de su finalidad asociativa.',
      'Primacía de la naturaleza asociativa: En caso de duda, el contrato deberá interpretarse como asociación en participación y no como operación financiera, préstamo, depósito, captación de fondos, producto de ahorro o inversión financiera supervisada.',
    ],
  },
  12: {
    titulo: 'DÉCIMA SEGUNDA: LEY APLICABLE, SOLUCIÓN DE CONTROVERSIAS Y JURISDICCIÓN',
    parrafos: [
      'Las partes acuerdan que todos aquellos aspectos que no se encuentren regulados en el presente contrato se regirán por las disposiciones legales de la República del Perú.',
      'Cualquier controversia o conflicto derivado de la celebración, interpretación, ejecución, cumplimiento, incumplimiento, resolución o terminación del presente contrato será sometido, en primera instancia, a un procedimiento de conciliación extrajudicial, conforme a la legislación vigente.',
      'De no alcanzarse un acuerdo conciliatorio o de no ser posible la conciliación por las causales previstas en la ley, las partes acuerdan someter cualquier controversia a la competencia de los Jueces y Tribunales del Distrito Judicial de Lima, renunciando expresamente al fuero que pudiera corresponderles por razón de su domicilio.',
    ],
  },
  13: {
    titulo: 'DÉCIMA TERCERA: MANDATO EXPRESO, LIMITADO Y ACCESORIO',
    parrafos: [
      'Por el presente instrumento, EL ASOCIADO otorga mandato sin representación, de conformidad con los artículos 1790 y siguientes del Código Civil, a favor de AVANCE CORP S.A.C., con RUC N.° 20611392088, para los fines establecidos en la presente cláusula. EL ASOCIANTE ejercerá el mandato en nombre propio, pero por cuenta e interés de EL ASOCIADO, y únicamente dentro de las facultades expresamente otorgadas. El mandato tiene carácter accesorio y limitado, y comprende exclusivamente las gestiones instrumentales, documentarias, administrativas y de liquidación necesarias para la ejecución del presente contrato y la determinación de los resultados derivados de las actividades empresariales.',
      'El mandatario queda expresamente facultado, dentro de los límites del presente contrato, para:',
      '• Recibir y revisar comunicaciones, reportes y liquidaciones vinculadas con las actividades empresariales materia del presente contrato.',
      '• Suscribir cargos, constancias de recepción, actas de liquidación y documentos de conformidad, siempre que correspondan a resultados efectivamente liquidados.',
      '• Gestionar ante entidades bancarias únicamente actos documentarios o de validación necesarios para recibir pagos derivados de la liquidación.',
      '• Suscribir formularios de cumplimiento, origen de fondos o regularización documentaria que sean requeridos para ejecutar pagos válidamente liquidados.',
      '• Suscribir constancias de cancelación o finiquito únicamente luego de verificado el ingreso efectivo de los montos que correspondan a EL ASOCIADO.',
      'Cualquier acto realizado fuera de los límites del presente mandato será inoponible a EL ASOCIADO, sin perjuicio de la responsabilidad civil, penal, administrativa o de cualquier otra naturaleza que pudiera corresponder.',
    ],
  },
  15: {
    titulo: 'DÉCIMA QUINTA: AUTORIZACIÓN PARA EL USO DE FIRMA IMPRESA',
    parrafos: [
      'Para la suscripción del presente contrato, EL ASOCIANTE podrá sustituir la firma autógrafa de su representante por su firma impresa, digitalizada o por cualquier otro medio de seguridad gráfico, mecánico o electrónico que permita identificar razonablemente al representante autorizado, a lo cual EL ASOCIADO presta su autorización y plena conformidad.',
      'EL ASOCIADO reconoce que la utilización de la firma impresa, digitalizada o reproducida mediante cualquiera de los medios antes señalados tendrá la misma validez y eficacia que la firma autógrafa del representante de EL ASOCIANTE, siempre que haya sido incorporada al presente contrato con autorización de EL ASOCIANTE.',
      'La autorización prevista en esta cláusula no impide que EL ASOCIANTE emplee firma autógrafa, firma digital u otro mecanismo válido de manifestación de voluntad, conforme a la legislación aplicable.',
    ],
  },
  16: {
    titulo: 'DÉCIMA SEXTA: CLÁUSULA DE PREVALENCIA E INTERPRETACIÓN',
    parrafos: [
      'En caso de contradicción, duda o vacío interpretativo, prevalecerá la naturaleza de contrato asociativo de asociación en participación regulado por la Ley General de Sociedades.',
      'Ninguna cláusula podrá interpretarse como interés, renta fija, rendimiento garantizado, depósito, mutuo, préstamo, crédito, captación de dinero del público, intermediación financiera, administración de fondos de terceros, producto financiero supervisado, seguro o intermediación de seguros.',
      'Si alguna autoridad, entidad financiera, árbitro o juez considera que una estipulación puede ser interpretada como actividad regulada o financiera, dicha estipulación deberá interpretarse restrictivamente o, de ser necesario, tenerse por no puesta, conservándose la validez del contrato en todo aquello que sea compatible con su naturaleza asociativa.',
    ],
  },
}

function clausulaEstatica(numero: number): Content[] {
  const clausula = CLAUSULAS_ESTATICAS[numero]
  if (!clausula) return []
  return [tituloClausula(clausula.titulo), ...clausula.parrafos.map((texto) => parrafo(texto))]
}

function tablaLiquidacion(): ContentTable {
  const filas = [
    ['Hito', 'Periodicidad / fecha', 'Naturaleza jurídica', 'Efecto contractual'],
    ['Contribución', 'A la firma o fecha acordada', 'Contribución asociativa', 'No es depósito, préstamo, ahorro, crédito ni captación.'],
    ['Liquidación ordinaria', 'Al vencimiento del contrato', 'Determinación final del resultado', 'Permite determinar las utilidades netas distribuibles.'],
    ['Liquidaciones parciales', 'Cuando EL ASOCIANTE las practique durante la vigencia del contrato', 'Determinación parcial de resultados', 'Permite distribución parcial de utilidades, de ser el caso.'],
    ['Pago de participación', 'Luego de la liquidación aprobada o comunicada', 'Distribución de utilidades', 'Procede respecto de las utilidades netas distribuibles.'],
    ['Restitución de la contribución', 'Conforme a la cláusula quinta u octava', 'Restitución del saldo resultante de la liquidación', 'Procede respecto del saldo que resulte a favor de EL ASOCIADO luego de la liquidación correspondiente.'],
  ]
  return {
    table: {
      headerRows: 1,
      dontBreakRows: true,
      widths: ['20%', '25%', '24%', '31%'],
      body: filas.map((fila, indice) => fila.map((texto) => ({
        text: texto,
        bold: indice === 0,
        color: indice === 0 ? '#ffffff' : '#15264d',
        fillColor: indice === 0 ? '#183969' : indice % 2 === 0 ? '#f2f5f8' : '#ffffff',
        margin: [3, 3, 3, 3],
      }))),
    },
    layout: {
      hLineColor: () => '#cbd5e1',
      vLineColor: () => '#cbd5e1',
      hLineWidth: () => 0.5,
      vLineWidth: () => 0.5,
    },
    fontSize: TIPOGRAFIA.tabla,
    margin: [0, 5, 0, 8],
  }
}

// Escala tipográfica del contrato. Gemela de TIPOGRAFIA en la plantilla de la
// edge `crm-contrato-pdf-v2`: si una cambia, la otra también, o el PDF de la
// demostración deja de parecerse al que firma el cliente.
const TIPOGRAFIA = {
  cuerpo: 9.6,
  clausula: 10.4,
  titulo: 15,
  tabla: 8.2,
  firma: 10.5,
  cabecera: 9.5,
  pie: 8,
} as const

export function nombreArchivoContrato(datos: ContratoPdfDatos): string {
  const nombre = datos.titular.nombreCompleto
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Za-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .toUpperCase()
  return `Contrato-${datos.contrato.numero}-${nombre}.pdf`
}

export function construirContratoPdf(
  datos: ContratoPdfDatos,
  assets: ContratoPdfAssets,
): TDocumentDefinitions {
  const { contrato, titular, analista } = datos
  const documento = `${etiquetaDocumento(titular.tipoDocumento)} N.° ${titular.documento}`
  const porcentajeLetras = enteroEnLetras(contrato.porcentaje).toLowerCase()
  const fechaFirma = fechaPartes(contrato.fechaInicio)

  const contenido: Content[] = [
    { text: 'CONTRATO DE ASOCIACIÓN EN PARTICIPACIÓN', style: 'titulo', margin: [0, 5, 0, 12] },
    parrafo('Conste por el presente documento, el Contrato de Asociación en Participación que celebran:'),
    parrafo('De una parte, AVANCE CORP S.A.C. con RUC N.° 20611392088, debidamente representada por su Gerente General, Sr. Kirk Edilberto Sánchez Ríos, con DNI N.° 44232474, según poderes inscritos en la partida electrónica N.° 15370250 del Registro de Personas Jurídicas de Lima, con domicilio en Av. República de Panamá N.° 3635, Urb. El Palomar, distrito de San Isidro, provincia y departamento de Lima, a quien se le denominará EL ASOCIANTE y, de la otra parte;'),
    parrafo(`${titular.nombreCompleto}, con ${documento} y con domicilio en ${titular.domicilio}, a quien se le denominará EL ASOCIADO, bajo los términos y condiciones siguientes:`),
    ...clausulaEstatica(1),
    ...clausulaEstatica(2),
    {
      stack: [
        tituloClausula('TERCERA: CONTRIBUCIÓN DEL ASOCIADO, RIESGO EMPRESARIAL Y PARTICIPACIÓN EN UTILIDADES'),
        parrafo(`EL ASOCIADO se obliga a efectuar una contribución dineraria ascendente a ${montoVisible(contrato.capital, contrato.moneda)} (${montoEnLetras(contrato.capital, contrato.moneda)}), mediante la cual adquiere el derecho a participar en los resultados o utilidades que generen las actividades empresariales materia del presente contrato.`),
      ],
      unbreakable: true,
    },
    parrafo('La contribución será entregada a EL ASOCIANTE mediante transferencia o depósito en la cuenta bancaria que este señale para fines operativos internos.'),
    parrafo('La contribución será aplicada al desarrollo de las actividades empresariales materia del presente contrato. EL ASOCIADO reconoce expresamente que participa en actividades sujetas a riesgo empresarial.'),
    parrafo(`EL ASOCIADO tendrá derecho a participar en el ${porcentajeLetras} por ciento (${contrato.porcentaje.toFixed(2)} %) de las utilidades netas distribuibles que generen las actividades empresariales materia del presente contrato, siempre que existan utilidades netas suficientes y liquidadas conforme al presente contrato.`),
    parrafo('En caso corresponda, las pérdidas, gastos, tributos, cargas y contingencias directamente vinculadas con las actividades empresariales deberán ser consideradas en la liquidación. La contribución de EL ASOCIADO quedará expuesta a los resultados económicos de dichas actividades y su restitución solo procederá respecto del saldo que resulte luego de la liquidación. La participación de EL ASOCIADO en las pérdidas se encuentra limitada al monto de su contribución económica; en consecuencia, no quedará obligado a efectuar contribuciones adicionales ni a responder con su propio patrimonio por obligaciones vinculadas con las actividades empresariales o asumidas por EL ASOCIANTE frente a terceros.'),
    parrafo('La utilidad neta distribuible se determinará deduciendo de los ingresos efectivamente percibidos por las actividades empresariales los costos directos, gastos directos, tributos, cargas, provisiones razonables, pérdidas y obligaciones documentadas vinculadas con dichas actividades.'),
    parrafo('EL ASOCIANTE podrá proporcionar a EL ASOCIADO información razonable sobre el desarrollo de las actividades empresariales materia del presente contrato cuando resulte pertinente, sin que ello genere obligación de efectuar reportes periódicos ni implique determinación de utilidades o derecho a pago alguno.'),
    parrafo('La liquidación ordinaria se realizará al vencimiento del plazo contractual, conforme a lo previsto en la cláusula quinta.'),
    parrafo('Sin perjuicio de la liquidación final prevista en el numeral anterior, EL ASOCIANTE podrá practicar durante la vigencia del presente contrato una o más liquidaciones parciales de resultados cuando existan utilidades netas distribuibles efectivamente generadas. Las participaciones que se distribuyan con ocasión de dichas liquidaciones tendrán el carácter de pagos parciales a cuenta de la liquidación final y no constituirán pagos fijos, rendimientos garantizados ni generarán obligación de efectuar distribuciones periódicas. Dichas liquidaciones parciales podrán realizarse con la periodicidad que EL ASOCIANTE determine, atendiendo a la naturaleza y resultados de las actividades empresariales.'),
    parrafo('La participación en utilidades que corresponda a EL ASOCIADO será determinada en la liquidación ordinaria prevista en la cláusula quinta o, de ser el caso, en las liquidaciones parciales. De existir utilidades netas distribuibles, la participación correspondiente será puesta a disposición de EL ASOCIADO dentro de los plazos previstos en el presente contrato. Si el vencimiento coincide con día inhábil, el pago se efectuará el primer día hábil siguiente, sin que ello configure mora.'),
    parrafo('Para efectos de ejecución, las partes reemplazan cualquier cronograma de pagos fijos por el siguiente esquema de información y liquidación:'),
    tablaLiquidacion(),
    ...clausulaEstatica(4),
    tituloClausula('QUINTA: PLAZO DE DURACIÓN DEL CONTRATO'),
    parrafo(`El plazo de duración obligatoria del presente contrato será de ${plazoVisible(contrato.fechaInicio, contrato.fechaVencimiento)}, contado a partir de la fecha de suscripción del presente documento.`),
    parrafo('El contrato podrá renovarse únicamente por acuerdo expreso y escrito de las partes. No habrá renovación automática.'),
    parrafo('Vencido el plazo contractual, EL ASOCIANTE practicará la liquidación final de los resultados correspondientes a las actividades empresariales dentro de los siete (7) días hábiles siguientes. Dicha liquidación determinará los derechos económicos que correspondan a cada una de las partes conforme a lo previsto en el presente contrato.'),
    parrafo('Practicada la liquidación final y efectuado el pago de la participación en utilidades que corresponda, EL ASOCIANTE restituirá a EL ASOCIADO, de ser el caso, el saldo de la contribución que resulte procedente conforme a la liquidación practicada, dentro de los cinco (5) días hábiles siguientes.'),
    ...clausulaEstatica(6),
    ...clausulaEstatica(7),
    ...clausulaEstatica(8),
    ...clausulaEstatica(9),
    ...clausulaEstatica(10),
    ...clausulaEstatica(11),
    ...clausulaEstatica(12),
    ...clausulaEstatica(13),
    tituloClausula('DÉCIMA CUARTA: DOMICILIO, NOTIFICACIONES Y ATENCIÓN COMERCIAL'),
    parrafo('Las partes señalan como sus domicilios para efectos de todas las comunicaciones y notificaciones relacionadas con el presente contrato los indicados en la parte introductoria del presente documento.'),
    parrafo(`Para comunicaciones operativas y coordinaciones vinculadas con la ejecución del presente contrato, EL ASOCIADO señala el correo electrónico ${titular.correo} y EL ASOCIANTE señala el correo electrónico atencionalcliente@mascapitalgroup.com. Asimismo, se deja constancia que el Analista Comercial encargado de la atención de EL ASOCIADO es ${analista.nombreCompleto}, identificado con DNI N.° ${analista.documento}, con número de celular ${analista.celular} y correo electrónico ${analista.correo}. La designación del referido Analista Comercial tiene únicamente fines de atención, orientación y coordinación operativa, y no le otorga facultades de representación, disposición de fondos ni asunción de obligaciones en nombre de EL ASOCIANTE, salvo que cuente con poder expreso y suficiente para ello.`),
    parrafo('Cualquier variación de domicilio, correo electrónico, número telefónico o funcionario encargado deberá ser comunicada por escrito a la otra parte. Mientras no se comunique la variación, serán válidas las notificaciones cursadas a los domicilios, correos electrónicos y datos consignados en este contrato.'),
    ...clausulaEstatica(15),
    ...clausulaEstatica(16),
    {
      ...tituloClausula('DÉCIMA SÉTIMA: DECLARACIÓN FINAL DE LAS PARTES'),
      pageBreak: 'before',
    },
    parrafo('Las partes declaran haber leído íntegramente el presente contrato, comprender su naturaleza asociativa, aceptar el riesgo empresarial inherente a las actividades empresariales materia del presente contrato y reconocer que no existe rendimiento fijo, utilidad garantizada ni devolución automática de la contribución.'),
    parrafo(`Las partes suscriben el presente documento en señal de conformidad a los ${fechaFirma.dia} días del mes de ${fechaFirma.mes} del ${fechaFirma.anio}.`),
    {
      columns: [
        {
          width: '48%',
          stack: [
            { text: '\n____________________________', alignment: 'center' },
            { text: titular.nombreCompleto, bold: true, alignment: 'center', fontSize: TIPOGRAFIA.firma },
            { text: documento, alignment: 'center', fontSize: TIPOGRAFIA.firma },
            { text: 'EL ASOCIADO', bold: true, alignment: 'center', fontSize: TIPOGRAFIA.firma },
          ],
        },
        {
          width: '48%',
          stack: [
            ...(assets.firmaAsociante
              ? [{ image: 'firmaAsociante', width: 92, height: 85, alignment: 'center', margin: [0, 0, 0, -14] }]
              : [{ text: 'FIRMA OMITIDA · DEMOSTRACIÓN', italics: true, alignment: 'center', fontSize: 7, margin: [0, 36, 0, 26] }]),
            { text: 'EL ASOCIANTE', bold: true, alignment: 'center', fontSize: TIPOGRAFIA.firma },
          ],
        },
      ],
      columnGap: 18,
      unbreakable: true,
      margin: [0, 6, 0, 5],
    } as ContentColumns,
  ]

  return {
    info: {
      title: `Contrato ${contrato.numero}`,
      author: 'Avance Corp S.A.C.',
      subject: 'Contrato de Asociación en Participación',
      keywords: `contrato,${contrato.numero},avance corp`,
    },
    pageSize: 'A4',
    pageMargins: [66, 126, 58, 94],
    // Gemelo del arreglo de la edge: el fondo se declara una sola vez y las
    // páginas lo referencian por nombre, en vez de incrustarlo en cada hoja.
    images: {
      fondoContrato: assets.fondo,
      ...(assets.firmaAsociante ? { firmaAsociante: assets.firmaAsociante } : {}),
    },
    background: () => ({
      image: 'fondoContrato',
      width: 595.28,
      height: 841.89,
      absolutePosition: { x: 0, y: 0 },
    }),
    header: () => ({
      text: contrato.numero,
      alignment: 'right',
      color: '#183969',
      bold: true,
      fontSize: TIPOGRAFIA.cabecera,
      margin: [0, 82, 58, 0],
    }),
    footer: (pagina, total) => ({
      text: `${pagina} / ${total}`,
      alignment: 'right',
      color: '#64748b',
      fontSize: TIPOGRAFIA.pie,
      margin: [0, 0, 58, 52],
    }),
    content: contenido,
    defaultStyle: {
      font: 'Roboto',
      fontSize: TIPOGRAFIA.cuerpo,
      color: '#17233b',
      lineHeight: 1.16,
    },
    styles: {
      titulo: {
        fontSize: TIPOGRAFIA.titulo,
        bold: true,
        alignment: 'center',
        color: '#183969',
      },
      clausula: {
        fontSize: TIPOGRAFIA.clausula,
        bold: true,
        color: '#183969',
      },
      parrafo: {
        alignment: 'justify',
        margin: [0, 0, 0, 4],
      },
    },
  }
}

async function recursoComoDataUrl(ruta: string): Promise<string> {
  const respuesta = await fetch(new URL(ruta, document.baseURI))
  if (!respuesta.ok) throw new Error(`No se pudo cargar el recurso del contrato (${respuesta.status}).`)
  const blob = await respuesta.blob()
  return await new Promise<string>((resolve, reject) => {
    const lector = new FileReader()
    lector.onerror = () => reject(new Error('No se pudo leer un recurso gráfico del contrato.'))
    lector.onload = () => resolve(String(lector.result))
    lector.readAsDataURL(blob)
  })
}

async function crearPdf(datos: ContratoPdfDatos) {
  const [pdfModulo, fuentesModulo, fondo] = await Promise.all([
    import('pdfmake/build/pdfmake'),
    import('pdfmake/build/vfs_fonts'),
    recursoComoDataUrl('./contrato/fondo-corporativo.png'),
  ])
  const pdfMake = pdfModulo.default
  // pdfmake publica vfs_fonts como CommonJS. Vite lo expone en `default`,
  // mientras que sus tipos históricos lo declaran como export nombrado.
  const fuentes = fuentesModulo as unknown as {
    default?: Record<string, string>
    vfs?: Record<string, string>
  }
  pdfMake.vfs = fuentes.default ?? fuentes.vfs ?? {}
  return pdfMake.createPdf(construirContratoPdf(datos, { fondo }))
}

/** Generador local exclusivo de la demo; el flujo real renderiza en la Edge. */
export async function generarContratoPdfBlob(datos: ContratoPdfDatos): Promise<Blob> {
  const pdf = await crearPdf(datos)
  return new Promise<Blob>((resolve) => pdf.getBlob(resolve))
}
