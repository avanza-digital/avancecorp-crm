import type { MetricasConversiones } from './metricas-conversiones'
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
}

const EQUIPO_NO_DISPONIBLE = 'Equipo no disponible'

/** El avance individual todavía es demasiado volátil durante los primeros días. */
export const DIA_MINIMO_ALERTA_CONVERSION_INDIVIDUAL = 10
/** Casos resueltos mínimos en el cumplimiento confirmado para juzgar conversión. */
export const CASOS_RESUELTOS_MINIMOS_ALERTA_CONVERSION_VENDEDOR = 10
/** Brecha material contra la meta individual, expresada en puntos porcentuales. */
export const BRECHA_MINIMA_ALERTA_CONVERSION_PP = 5
export const BRECHA_CRITICA_ALERTA_CONVERSION_PP = 10
/** Muestra mínima en cada cohorte para comparar la conversión global. */
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

function porcentajeValido(valor: number | null | undefined): valor is number {
  return valor != null && Number.isFinite(valor) && valor >= 0 && valor <= 100
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
}: DerivarAlertasGerenciaInput): AlertaGerencia[] {
  const alertas: AlertaGerencia[] = []

  const diaIndividualValido = Number.isInteger(diaDelMes)
    && diaDelMes >= DIA_MINIMO_ALERTA_CONVERSION_INDIVIDUAL
    && diaDelMes <= 31
  const cumplimientoCompleto = !objetivosError
    && !cumplimientoError
    && Object.keys(metasVendedores).length > 0
    && Object.keys(metasVendedores).every((vendedorId) => cumplimientosVendedores[vendedorId] != null)
  if (diaIndividualValido && cumplimientoCompleto) {
    for (const vendedor of Object.values(cumplimientosVendedores)) {
      if (
        !conteoValido(vendedor.resueltos)
        || vendedor.resueltos < CASOS_RESUELTOS_MINIMOS_ALERTA_CONVERSION_VENDEDOR
        || !porcentajeValido(vendedor.conversionReal)
      ) continue

      const metaVendedor = metasVendedores[vendedor.vendedorId]
      if (
        metaVendedor != null
        && !porcentajeValido(metaVendedor.conversionObjetivo)
      ) continue
      const metaGuardada = metaVendedor?.conversionObjetivo ?? 0
      const objetivo = metaConversionAplicable(metaGuardada, objetivosError)
      const actual = vendedor.conversionReal
      if (!porcentajeValido(objetivo) || actual >= objetivo) continue

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
        destino: 'ranking-vendedores',
      })
    }
  }

  const conversionActual = conversiones?.cohorte.conversion_contratos_pct
  const conversionAnterior = conversionesAnteriores?.cohorte.conversion_contratos_pct
  const leadsActuales = conversiones?.cohorte.leads
  const leadsAnteriores = conversionesAnteriores?.cohorte.leads
  if (
    porcentajeValido(conversionActual)
    && porcentajeValido(conversionAnterior)
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
        destino: 'conversiones',
      })
    }
  }

  return ordenarAlertas(alertas)
}
