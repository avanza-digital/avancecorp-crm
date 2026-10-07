import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  FechaSchema,
  NumeroRpcSchema,
  TextoNoVacioSchema,
  UuidSchema,
} from './esquemas-rpc'

/**
 * Conversión por analista de TODA la empresa, tal como la sirve
 * `crm.conversion_divisor_coordinacion_fn`: el divisor es el del NÚCLEO (una
 * llegada por lead, por su alta original en Lima, en el primer analista que la
 * recibió), no el reporte de entregas; y el numerador se abre en sus partes
 * (cierres por origen y operaciones de cartera) con los mismos episodios que lo
 * suman. El navegador solo pinta: cualquier aritmética que no reconcilie se
 * rechaza antes de mostrarse.
 */
const CierresSchema = v.object({
  formulario: EnteroNoNegativoRpcSchema,
  landing: EnteroNoNegativoRpcSchema,
  referido: EnteroNoNegativoRpcSchema,
  /** Cuánto suman los referidos al numerador (cantidad × peso del referido; con tope, solo los que cuentan). */
  referido_aporte: NumeroRpcSchema,
  /** Oficina (walking) no pesa en el numerador; se enseña para no ocultarla. */
  oficina: EnteroNoNegativoRpcSchema,
  /** Otros orígenes admitidos (web, campaña, whatsapp…): tampoco pesan; se cuentan para no esconderlos. */
  otros: EnteroNoNegativoRpcSchema,
  /**
   * Contactos de una base cargada por archivo (B11): cada cierre pesa 1 y no entra al divisor. Un servidor
   * anterior a B11 no la manda (y entonces esos cierres pesan 0 y van en «otros»): ausente = 0. Null solo en un
   * mes sellado, porque la foto del cierre no la guarda.
   */
  base_cargada: v.optional(v.nullable(EnteroNoNegativoRpcSchema)),
})

const CarteraSchema = v.object({
  /** Upgrade pesa 1 por operación. */
  upgrade: EnteroNoNegativoRpcSchema,
  renovacion: EnteroNoNegativoRpcSchema,
  /** Cuánto suman las renovaciones al numerador (cantidad × peso de renovación). */
  renovacion_aporte: NumeroRpcSchema,
})

const AnalistaConversionCoordinacionSchema = v.object({
  analista_id: UuidSchema,
  nombre: v.nullable(v.string()),
  supervisor_id: v.nullable(UuidSchema),
  supervisor_nombre: v.nullable(v.string()),
  en_nucleo: v.boolean(),
  divisor: EnteroNoNegativoRpcSchema,
  /** Null solo en un mes sellado: la foto no guarda el desglose por origen. */
  divisor_formulario: v.nullable(EnteroNoNegativoRpcSchema),
  divisor_landing: v.nullable(EnteroNoNegativoRpcSchema),
  numerador: v.nullable(NumeroRpcSchema),
  conversion_pct: v.nullable(NumeroRpcSchema),
  /** Bruto y ajuste de meses ya pagados: null en un mes sellado (la foto guarda el neto). */
  numerador_bruto: v.nullable(NumeroRpcSchema),
  ajuste_pendiente: v.nullable(NumeroRpcSchema),
  /** False solo en un mes sellado cuya foto no trae el desglose. */
  desglose_disponible: v.boolean(),
  cierres: v.nullable(CierresSchema),
  cartera: v.nullable(CarteraSchema),
})

const EmpresaConversionCoordinacionSchema = v.object({
  divisor: EnteroNoNegativoRpcSchema,
  numerador: NumeroRpcSchema,
  conversion_pct: v.nullable(NumeroRpcSchema),
  divisor_formulario: v.nullable(EnteroNoNegativoRpcSchema),
  divisor_landing: v.nullable(EnteroNoNegativoRpcSchema),
  numerador_bruto: v.nullable(NumeroRpcSchema),
  ajuste_pendiente: v.nullable(NumeroRpcSchema),
  desglose_disponible: v.boolean(),
  cierres: v.nullable(CierresSchema),
  cartera: v.nullable(CarteraSchema),
})

export const ConversionCoordinacionSchema = v.object({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  alcance: v.literal('global'),
  /** Mes calendario exacto (`modo: 'mes'`, con nombre) o rango libre inclusivo (`modo: 'rango'`). */
  periodo: v.object({
    modo: v.picklist(['mes', 'rango']),
    mes: v.nullable(v.pipe(v.string(), v.regex(/^\d{4}-\d{2}$/))),
    mes_nombre: v.nullable(TextoNoVacioSchema),
    anio: v.nullable(v.pipe(NumeroRpcSchema, v.integer())),
    zona: v.literal('America/Lima'),
    desde: FechaSchema,
    /** Inclusivo: el último día del mes o la fecha final del rango. */
    hasta: FechaSchema,
    dias: v.pipe(NumeroRpcSchema, v.integer(), v.minValue(1)),
    /** Solo en rango: el tramo toca meses ya sellados y se calculó en vivo (puede diferir de la foto). */
    cruza_meses_sellados: v.boolean(),
  }),
  sellado: v.boolean(),
  peso_referido: NumeroRpcSchema,
  /** Tope de referidos (octubre 2026 en adelante): máximo 0–100 % de los cierres del mes del analista.
   * null o ausente = sin tope. Con tope, `referido_aporte` puede ser MENOR que `referido × peso_referido`. */
  tope_referidos_pct: v.optional(v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(100)))),
  peso_renovacion: NumeroRpcSchema,
  fuente: v.object({
    divisor: TextoNoVacioSchema,
    origen: TextoNoVacioSchema,
    regla: TextoNoVacioSchema,
    /** 'foto' (mes sellado), 'mensual' (mes abierto, pieza de Metas) o 'rango_vivo' (tramo libre). */
    modo: v.picklist(['foto', 'mensual', 'rango_vivo']),
  }),
  empresa: EmpresaConversionCoordinacionSchema,
  /** Llegadas sin analista atribuible: cuentan en la empresa, sin responsable inventado. */
  sin_analista: v.nullable(v.object({
    divisor: EnteroNoNegativoRpcSchema,
    numerador: v.nullable(NumeroRpcSchema),
  })),
  analistas: v.array(AnalistaConversionCoordinacionSchema),
})

export type ConversionCoordinacion = v.InferOutput<typeof ConversionCoordinacionSchema>
export type AnalistaConversionCoordinacion = v.InferOutput<typeof AnalistaConversionCoordinacionSchema>
export type CierresConversion = v.InferOutput<typeof CierresSchema>
export type CarteraConversion = v.InferOutput<typeof CarteraSchema>

/** 'YYYY-MM' del mes vigente en Lima. */
export function mesActualLima(ahora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima',
    year: 'numeric',
    month: '2-digit',
  }).format(ahora).slice(0, 7)
}

/** Primer día del mes ('YYYY-MM' → 'YYYY-MM-01'); null si el mes no es válido. */
export function periodoDesdeMes(mes: string): string | null {
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(mes) ? `${mes}-01` : null
}

/** Último día del mes ('YYYY-MM' → 'YYYY-MM-DD'); null si el mes no es válido. */
export function finDeMes(mes: string): string | null {
  if (!periodoDesdeMes(mes)) return null
  const [anio, numero] = mes.split('-').map(Number) as [number, number]
  return new Date(Date.UTC(anio, numero, 0)).toISOString().slice(0, 10)
}

/** 'YYYY-MM-DD' de hoy en Lima. */
export function hoyLima(ahora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' }).format(ahora)
}

/** Lo que la pestaña pide a la puerta: un mes calendario o un rango inclusivo. */
export type ConsultaConversion =
  | { modo: 'mes'; mes: string }
  | { modo: 'rango'; desde: string; hasta: string }

export const RANGO_MAXIMO_DIAS = 366

/** Días inclusivos entre dos fechas 'YYYY-MM-DD' (1 cuando son iguales). */
export function diasInclusivos(desde: string, hasta: string): number {
  return Math.round((Date.parse(`${hasta}T12:00:00Z`) - Date.parse(`${desde}T12:00:00Z`)) / 86_400_000) + 1
}

/**
 * Valida la consulta como estado del formulario, ANTES de tocar la red: la
 * puerta rechazaría lo mismo (22023), pero el error tiene que quedar pegado al
 * campo, no disfrazado de fallo de carga. Devuelve el motivo o null si es válida.
 */
export function motivoConsultaInvalida(consulta: ConsultaConversion, hoy: string): string | null {
  if (consulta.modo === 'mes') {
    if (!periodoDesdeMes(consulta.mes)) return 'Elige un mes válido (año y mes) para consultar la conversión.'
    // El `min` del control no frena el onChange: un año tecleado a medias (0202-09) llegaría aquí.
    if (consulta.mes < FECHA_MINIMA.slice(0, 7)) return `El mes más antiguo consultable es ${FECHA_MINIMA.slice(0, 7)}.`
    if (consulta.mes > hoy.slice(0, 7)) return `El mes no puede ser futuro: elige ${hoy.slice(0, 7)} o anterior.`
    return null
  }
  const desdeOk = v.safeParse(FechaSchema, consulta.desde).success
  const hastaOk = v.safeParse(FechaSchema, consulta.hasta).success
  if (!desdeOk || !hastaOk) return 'Elige las dos fechas del rango (desde y hasta).'
  if (consulta.desde < FECHA_MINIMA) return `El rango empieza como pronto el ${FECHA_MINIMA}.`
  if (consulta.desde > consulta.hasta) return 'La fecha inicial no puede ser posterior a la final.'
  if (consulta.hasta > hoy) return `El rango no admite fechas futuras: hasta ${hoy} como máximo.`
  if (diasInclusivos(consulta.desde, consulta.hasta) > RANGO_MAXIMO_DIAS) return `El rango máximo es de ${RANGO_MAXIMO_DIAS} días.`
  return null
}

/** Primer día consultable: el CRM no tiene llegadas anteriores y un año tecleado a medias no debe disparar consultas. */
export const FECHA_MINIMA = '2025-01-01'

/** Qué campo del rango está mal, para marcar solo ese con `aria-invalid`. */
export function camposInvalidos(consulta: ConsultaConversion, hoy: string): { desde: boolean; hasta: boolean } {
  if (consulta.modo === 'mes') return { desde: false, hasta: false }
  const desdeOk = v.safeParse(FechaSchema, consulta.desde).success && consulta.desde >= FECHA_MINIMA
  const hastaOk = v.safeParse(FechaSchema, consulta.hasta).success && consulta.hasta <= hoy
  if (!desdeOk || !hastaOk) return { desde: !desdeOk, hasta: !hastaOk }
  const cruzado = consulta.desde > consulta.hasta || diasInclusivos(consulta.desde, consulta.hasta) > RANGO_MAXIMO_DIAS
  return { desde: cruzado, hasta: cruzado }
}

/** Fechas inclusivas que la consulta pide (el mes se convierte a su primer y último día). */
export function fechasDeConsulta(consulta: ConsultaConversion): { desde: string; hasta: string } | null {
  if (consulta.modo === 'mes') {
    const desde = periodoDesdeMes(consulta.mes)
    const hasta = finDeMes(consulta.mes)
    return desde && hasta ? { desde, hasta } : null
  }
  return { desde: consulta.desde, hasta: consulta.hasta }
}

/** Tolerancia para sumas de pesos con decimales (0,15 × n) en coma flotante. */
const EPSILON = 1e-6

/** Cuánto suman las partes del numerador: cierres directos y de base, referidos con peso, upgrade y renovación con peso. */
export function sumaDePartes(cierres: CierresConversion, cartera: CarteraConversion): number {
  return cierres.formulario + cierres.landing + (cierres.base_cargada ?? 0) + cierres.referido_aporte
    + cartera.upgrade + cartera.renovacion_aporte
}

function desgloseConsistente(fila: {
  sellado: boolean
  desglose_disponible: boolean
  cierres: CierresConversion | null
  cartera: CarteraConversion | null
  numerador_bruto: number | null
  ajuste_pendiente: number | null
  numerador: number | null
  esEmpresa?: boolean
}): boolean {
  if (!fila.desglose_disponible) {
    // Solo una foto sellada puede venir sin desglose; y entonces viene sin nada.
    return fila.sellado && fila.cierres === null && fila.cartera === null
  }
  if (fila.cierres === null || fila.cartera === null) return false
  if (fila.sellado) return fila.numerador_bruto === null && fila.ajuste_pendiente === null
  // Mes abierto o rango: el servidor siempre sabe cuántos cierres de base hubo.
  if (fila.cierres.base_cargada === null) return false
  if (fila.numerador_bruto === null || fila.ajuste_pendiente === null || fila.numerador === null) return false
  if (Math.abs(sumaDePartes(fila.cierres, fila.cartera) - fila.numerador_bruto) > EPSILON) return false
  // Por persona: neto = bruto menos lo que arrastra de meses ya pagados, con suelo en cero.
  // La empresa se comprueba aparte (suma de netos), porque el suelo es por persona.
  if (fila.esEmpresa) return fila.numerador <= fila.numerador_bruto + EPSILON
  return Math.abs(Math.max(fila.numerador_bruto - fila.ajuste_pendiente, 0) - fila.numerador) <= EPSILON
}

/**
 * Candado de PARIDAD del lado del navegador. No recalcula nada: comprueba que
 * lo que el servidor dice de cada analista y de la empresa cuadra consigo mismo
 * (formulario + landing = divisor; analistas + sin analista = empresa; las
 * partes de los cierres suman el numerador bruto y el neto es el bruto con el
 * ajuste). Si alguien vuelve a calcular el divisor o el numerador fuera del
 * núcleo y las sumas dejan de cerrar, la pantalla se niega a pintar en vez de
 * enseñar un número inventado.
 */
export function conversionCoordinacionConsistente(
  datos: ConversionCoordinacion,
  desde: string,
  hasta: string,
): boolean {
  const { periodo } = datos
  if (periodo.desde !== desde || periodo.hasta !== hasta) return false
  if (periodo.dias !== diasInclusivos(desde, hasta)) return false
  if (periodo.modo === 'mes') {
    if (periodo.mes === null || !desde.startsWith(periodo.mes) || periodo.mes_nombre === null || periodo.anio === null) return false
    if (periodo.cruza_meses_sellados) return false
    if (datos.fuente.modo === 'rango_vivo' || datos.fuente.modo === (datos.sellado ? 'mensual' : 'foto')) return false
  } else if (periodo.mes !== null || periodo.mes_nombre !== null || periodo.anio !== null || datos.sellado || datos.fuente.modo !== 'rango_vivo') {
    // Un rango libre nunca es una foto sellada ni lleva nombre de mes, y siempre se declara como vivo.
    return false
  }
  if (periodo.modo === 'rango' && (datos.empresa.ajuste_pendiente !== 0
    || datos.analistas.some((a) => a.ajuste_pendiente !== 0))) return false

  const ids = new Set<string>()
  let divisorAnalistas = 0
  let formulario = 0
  let landing = 0
  for (const analista of datos.analistas) {
    if (ids.has(analista.analista_id)) return false
    ids.add(analista.analista_id)
    divisorAnalistas += analista.divisor
    if (!desgloseConsistente({ ...analista, sellado: datos.sellado })) return false
    if (datos.sellado) {
      if (analista.divisor_formulario !== null || analista.divisor_landing !== null) return false
      continue
    }
    if (analista.divisor_formulario === null || analista.divisor_landing === null) return false
    if (analista.divisor_formulario + analista.divisor_landing !== analista.divisor) return false
    formulario += analista.divisor_formulario
    landing += analista.divisor_landing
  }

  if (!desgloseConsistente({ ...datos.empresa, sellado: datos.sellado, esEmpresa: true })) return false
  if (datos.sellado) {
    if (datos.periodo.cruza_meses_sellados) return false
    return datos.empresa.divisor_formulario === null && datos.empresa.divisor_landing === null
  }
  // La empresa suma los NETOS por persona (cada uno con su suelo en cero), nunca
  // aplica un suelo al agregado: 11,15 + max(9 − 12, 0) = 11,15, no 8,15.
  const netoEsperado = datos.analistas.reduce((acc, a) => acc + (a.numerador ?? 0), 0) + (datos.sin_analista?.numerador ?? 0)
  if (Math.abs(netoEsperado - datos.empresa.numerador) > EPSILON) return false
  if (datos.empresa.divisor_formulario === null || datos.empresa.divisor_landing === null) return false
  if (datos.empresa.divisor_formulario + datos.empresa.divisor_landing !== datos.empresa.divisor) return false
  if (divisorAnalistas + (datos.sin_analista?.divisor ?? 0) !== datos.empresa.divisor) return false
  if (formulario > datos.empresa.divisor_formulario || landing > datos.empresa.divisor_landing) return false
  return true
}
