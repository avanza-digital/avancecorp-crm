import type { MetricasConversiones } from './metricas-conversiones'
import { sondasNucleoVerificadas } from './sondas-conversion'
import {
  metaConversionAplicable,
  type CumplimientoVendedor,
  type ObjetivosPorVendedor,
} from './objetivos'

export type TipoAlertaGerencia =
  | 'bajo_meta_conversion'
  | 'caida_conversion'

export type Severidad = 'critica' | 'atencion'
export type SeveridadAlertaGerencia = Severidad

export type DestinoAlertaGerencia =
  | 'ranking-vendedores'
  | 'conversiones'

export interface AlertaGerencia {
  id: string
  tipo: TipoAlertaGerencia
  severidad: Severidad
  responsableId: string | null
  responsable: string
  equipo: string
  /** Valor que disparó la alerta: conteo o porcentaje actual, según `tipo`. */
  valor: number
  actual?: number
  /** Meta o valor del período anterior que sirve de referencia. */
  objetivo?: number
  brechaPp?: number
  /**
   * Tamaño de la muestra que sostiene la alerta (leads recibidos): la
   * individual exige ≥10 y la global ≥30, y ese corte se DICE en pantalla
   * (H21) — un aviso que calla su umbral parece arbitrario cuando aparece y
   * sospechoso cuando no.
   */
  muestra?: number
  destino: DestinoAlertaGerencia
}

export interface PeriodoAnteriorComparable {
  desde: string
  hasta: string
}

export interface DerivarAlertasGerenciaInput {
  conversiones?: MetricasConversiones | null | undefined
  conversionesAnteriores?: MetricasConversiones | null | undefined
  metasVendedores: ObjetivosPorVendedor
  cumplimientosVendedores: Record<string, CumplimientoVendedor>
  objetivosError?: boolean | undefined
  cumplimientoError?: boolean | undefined
  diaDelMes: number
  /** Días que tiene el mes en curso: febrero mueve el último corte. */
  diasDelMes: number
}

const EQUIPO_NO_DISPONIBLE = 'Equipo no disponible'

/**
 * Cortes de revisión del mes (decisión de Miguel, 2026-08-13). El avance
 * individual se juzga por SEMANAS CUMPLIDAS, no cualquier día: antes del 7 no
 * hay nada que juzgar, y a partir de ahí cada corte vuelve a evaluar.
 *
 * El aviso aparece en su corte y SIGUE VISIBLE hasta el siguiente, para que
 * gerencia no se pierda un corte por no haber entrado ese día exacto.
 *
 * ⚠️ Esto gobierna solo los AVISOS. Consultar la conversión no depende del día:
 * si gerencia mira el día 2 y todos van 0 %, la pantalla enseña 0 %. Ninguna
 * pantalla lee el día del mes — verificado — y así debe seguir.
 */
export const CORTES_ALERTA_CONVERSION_INDIVIDUAL = [7, 15, 21, 30] as const

/**
 * Los cortes REALES de un mes concreto. En febrero (28/29 días) el corte del 30
 * no existe: se corre al último día, y si eso lo hace coincidir con otro, se
 * funden en uno. Sin esto, febrero se quedaría sin su última revisión.
 */
export function cortesDelMes(diasDelMes: number): number[] {
  if (!Number.isInteger(diasDelMes) || diasDelMes < 1) return []
  const cortes = new Set(
    CORTES_ALERTA_CONVERSION_INDIVIDUAL.map((corte) => Math.min(corte, diasDelMes)),
  )
  return [...cortes].sort((a, b) => a - b)
}

/**
 * El último corte YA CUMPLIDO para un día dado, o `null` si todavía no llegó el
 * primero (días 1-6). Es lo que decide si el aviso individual se muestra.
 */
export function corteVigente(diaDelMes: number, diasDelMes: number): number | null {
  if (!Number.isInteger(diaDelMes) || diaDelMes < 1) return null
  const cumplidos = cortesDelMes(diasDelMes).filter((corte) => diaDelMes >= corte)
  return cumplidos.length === 0 ? null : cumplidos[cumplidos.length - 1]!
}

/**
 * Muestra mínima para juzgar la conversión de un analista.
 *
 * ⚠️ La CLAVE del payload se llama `resueltos` y no cambia de nombre, pero lo
 * que cuenta sí cambia con la migración B: hoy son leads TERMINADOS (cerrados o
 * descartados) y tras B son leads RECIBIDOS. Por eso el nombre de esta
 * constante es neutro.
 *
 * Valor 10 por decisión de Miguel (2026-08-13). El plan recomendaba 20, pero con
 * los CORTES ese filtro ya no carga solo: antes del día 7 no hay aviso, así que
 * la muestra no tiene que hacer también de freno por «demasiado pronto».
 */
export const MUESTRA_MINIMA_ALERTA_CONVERSION_VENDEDOR = 10
/** Brecha material contra la meta individual, expresada en puntos porcentuales. */
export const BRECHA_MINIMA_ALERTA_CONVERSION_PP = 5
export const BRECHA_CRITICA_ALERTA_CONVERSION_PP = 10
/**
 * Muestra mínima en cada período para comparar la conversión global. Desde F3
 * (H11) la muestra es el DIVISOR DEL NÚCLEO — leads no referidos recibidos en
 * el rango —, no los leads de la cohorte: la alerta compara la misma cifra que
 * HOY/Ranking y su muestra debe ser la de esa cifra.
 */
export const LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL = 30
/** Caída material y crítica contra el MTD comparable anterior. */
export const CAIDA_MINIMA_ALERTA_GLOBAL_PP = 3
export const CAIDA_CRITICA_ALERTA_GLOBAL_PP = 5

const ORDEN_SEVERIDAD: Record<Severidad, number> = {
  critica: 0,
  atencion: 1,
}

const ORDEN_TIPO: Record<TipoAlertaGerencia, number> = {
  bajo_meta_conversion: 0,
  caida_conversion: 1,
}

function esBisiesto(anio: number): boolean {
  return anio % 4 === 0 && (anio % 100 !== 0 || anio % 400 === 0)
}

function diasDelMes(anio: number, mes: number): number {
  if (mes === 2) return esBisiesto(anio) ? 29 : 28
  if (mes === 4 || mes === 6 || mes === 9 || mes === 11) return 30
  return 31
}

function fechaValida(fecha: string): { anio: number; mes: number; dia: number } {
  const partes = /^(\d{4})-(\d{2})-(\d{2})$/.exec(fecha)
  if (!partes) throw new RangeError(`Fecha inválida: ${fecha}`)

  const anio = Number(partes[1])
  const mes = Number(partes[2])
  const dia = Number(partes[3])
  if (mes < 1 || mes > 12 || dia < 1 || dia > diasDelMes(anio, mes)) {
    throw new RangeError(`Fecha inválida: ${fecha}`)
  }
  return { anio, mes, dia }
}

function fechaIso(anio: number, mes: number, dia: number): string {
  return `${String(anio).padStart(4, '0')}-${String(mes).padStart(2, '0')}-${String(dia).padStart(2, '0')}`
}

/**
 * Corte comparable del mes anterior: siempre empieza el día 1 y termina en el
 * mismo ordinal de `hasta`, recortado al último día que exista en aquel mes.
 */
export function periodoAnteriorComparable(hasta: string): PeriodoAnteriorComparable {
  const actual = fechaValida(hasta)
  const anio = actual.mes === 1 ? actual.anio - 1 : actual.anio
  const mes = actual.mes === 1 ? 12 : actual.mes - 1
  const dia = Math.min(actual.dia, diasDelMes(anio, mes))

  return {
    desde: fechaIso(anio, mes, 1),
    hasta: fechaIso(anio, mes, dia),
  }
}

function redondearPp(valor: number): number {
  return Math.round(valor * 100) / 100
}

/** Una META se pacta en [0,100]: el techo aquí es correcto y se queda. */
function porcentajeMetaValido(valor: number | null | undefined): valor is number {
  return valor != null && Number.isFinite(valor) && valor >= 0 && valor <= 100
}

/**
 * Un RESULTADO de conversión NO tiene techo (la mensual ponderada supera 100
 * por diseño: referidos que suman arriba y no abajo, cierres de arrastre).
 * Antes ambos compartían un [0,100] y un analista por encima de 100 se saltaba
 * con `continue` — un fail-open sin rastro. OJO: eso NO cambiaba el resultado
 * de hoy (a quien supera su meta no le toca alerta de conversión BAJA), pero
 * dejaba una mina para la primera alerta de sobre-rendimiento o de caída
 * global que reutilizara el helper. Higiene, no bugfix: la razón exacta quedó
 * en el plan (§4bis-C8).
 */
function porcentajeConversionValido(valor: number | null | undefined): valor is number {
  return valor != null && Number.isFinite(valor) && valor >= 0
}

function conteoValido(valor: number | null | undefined): valor is number {
  return valor != null && Number.isInteger(valor) && valor >= 0
}

function ordenarAlertas(alertas: AlertaGerencia[]): AlertaGerencia[] {
  return alertas.sort((a, b) => (
    ORDEN_SEVERIDAD[a.severidad] - ORDEN_SEVERIDAD[b.severidad]
    || ORDEN_TIPO[a.tipo] - ORDEN_TIPO[b.tipo]
    || a.responsable.localeCompare(b.responsable, 'es')
    || (a.responsableId ?? '').localeCompare(b.responsableId ?? '')
    || a.id.localeCompare(b.id)
  ))
}

/**
 * Construye alertas solo a partir de fuentes autoritativas disponibles. Cada
 * rama falla cerrada: una respuesta ausente o parcial jamás se interpreta
 * como un contador en cero ni como cumplimiento.
 */
export function derivarAlertasGerencia({
  conversiones,
  conversionesAnteriores,
  metasVendedores,
  cumplimientosVendedores,
  objetivosError = false,
  cumplimientoError = false,
  diaDelMes,
  diasDelMes,
}: DerivarAlertasGerenciaInput): AlertaGerencia[] {
  const alertas: AlertaGerencia[] = []

  // El aviso individual vive por CORTES (7 · 15 · 21 · 30): aparece en el suyo
  // y sigue visible hasta el siguiente. Antes del primero no hay nada que
  // juzgar, por muchos leads que se hayan repartido.
  const diaIndividualValido = diaDelMes <= diasDelMes
    && corteVigente(diaDelMes, diasDelMes) != null
  const cumplimientoCompleto = !objetivosError
    && !cumplimientoError
    && Object.keys(metasVendedores).length > 0
    && Object.keys(metasVendedores).every((vendedorId) => cumplimientosVendedores[vendedorId] != null)
  if (diaIndividualValido && cumplimientoCompleto) {
    for (const vendedor of Object.values(cumplimientosVendedores)) {
      if (
        !conteoValido(vendedor.resueltos)
        || vendedor.resueltos < MUESTRA_MINIMA_ALERTA_CONVERSION_VENDEDOR
        || !porcentajeConversionValido(vendedor.conversionReal)
      ) continue

      const metaVendedor = metasVendedores[vendedor.vendedorId]
      if (
        metaVendedor != null
        && !porcentajeMetaValido(metaVendedor.conversionObjetivo)
      ) continue
      const metaGuardada = metaVendedor?.conversionObjetivo ?? 0
      const objetivo = metaConversionAplicable(metaGuardada, objetivosError)
      const actual = vendedor.conversionReal
      if (!porcentajeMetaValido(objetivo) || actual >= objetivo) continue

      const brechaPp = redondearPp(objetivo - actual)
      if (brechaPp < BRECHA_MINIMA_ALERTA_CONVERSION_PP) continue

      alertas.push({
        id: `bajo_meta_conversion:${vendedor.vendedorId}`,
        tipo: 'bajo_meta_conversion',
        severidad: brechaPp >= BRECHA_CRITICA_ALERTA_CONVERSION_PP
          ? 'critica'
          : 'atencion',
        responsableId: vendedor.vendedorId,
        responsable: vendedor.nombre,
        equipo: vendedor.supervisorNombre || EQUIPO_NO_DISPONIBLE,
        valor: actual,
        actual,
        objetivo,
        brechaPp,
        muestra: vendedor.resueltos,
        destino: 'ranking-vendedores',
      })
    }
  }

  // H11 (F3 de «Conversión única»): la caída global compara la MISMA
  // aritmética que la alerta individual y que HOY/Ranking — el bloque `nucleo`
  // servido (flujo del rango, ponderado, mismo peso de referidos) — y no la
  // cohorte de contratos, que madura con retraso y contradecía a su vecina de
  // bandeja. Un payload SIN bloque `nucleo` o sin las DOS sondas verificadas
  // no se interpreta: sin fuente confiable no hay alerta, jamás una con otra
  // fórmula. Hoy el servidor suele dejar NULL la sonda de un MTD anterior;
  // en ese caso esta alerta queda deliberadamente inactiva hasta que exista
  // una comparación verificada, en vez de afirmar una caída no certificada.
  const nucleoActualVerificado = sondasNucleoVerificadas(conversiones?.sondas)
  const nucleoAnteriorVerificado = sondasNucleoVerificadas(conversionesAnteriores?.sondas)
  const conversionActual = conversiones?.nucleo?.conversion_pct
  const conversionAnterior = conversionesAnteriores?.nucleo?.conversion_pct
  const leadsActuales = conversiones?.nucleo?.divisor
  const leadsAnteriores = conversionesAnteriores?.nucleo?.divisor
  if (
    nucleoActualVerificado
    && nucleoAnteriorVerificado
    && porcentajeConversionValido(conversionActual)
    && porcentajeConversionValido(conversionAnterior)
    && conteoValido(leadsActuales)
    && conteoValido(leadsAnteriores)
    && leadsActuales >= LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL
    && leadsAnteriores >= LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL
  ) {
    const brechaPp = redondearPp(conversionAnterior - conversionActual)
    if (brechaPp >= CAIDA_MINIMA_ALERTA_GLOBAL_PP) {
      alertas.push({
        id: 'caida_conversion:global',
        tipo: 'caida_conversion',
        severidad: brechaPp >= CAIDA_CRITICA_ALERTA_GLOBAL_PP
          ? 'critica'
          : 'atencion',
        responsableId: null,
        responsable: 'Equipo comercial',
        equipo: 'Todos los equipos',
        valor: conversionActual,
        actual: conversionActual,
        objetivo: conversionAnterior,
        brechaPp,
        muestra: leadsActuales,
        destino: 'conversiones',
      })
    }
  }

  return ordenarAlertas(alertas)
}
