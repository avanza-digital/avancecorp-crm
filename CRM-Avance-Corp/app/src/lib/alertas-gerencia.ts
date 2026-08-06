import type { ConversionEquipoVendedor } from './conversion-equipo'
import { adaptarConversionVendedores } from './conversion-vendedores'
import type { MetricasAgenda } from './metricas-agenda'
import type { MetricasConversiones } from './metricas-conversiones'
import type { MetricasReuniones } from './metricas-reuniones'
import {
  metaConversionAplicable,
  type ObjetivosPorVendedor,
} from './objetivos'

export type TipoAlertaGerencia =
  | 'tarea_vencida'
  | 'sin_proxima_accion'
  | 'no_show'
  | 'bajo_meta_conversion'
  | 'caida_conversion'

export type Severidad = 'critica' | 'atencion'
export type SeveridadAlertaGerencia = Severidad

export type DestinoAlertaGerencia =
  | 'rendimiento'
  | 'reuniones'
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
  agenda?: MetricasAgenda | null | undefined
  reuniones?: MetricasReuniones | null | undefined
  equipoConversion: readonly ConversionEquipoVendedor[]
  metasVendedores: ObjetivosPorVendedor
  objetivosError?: boolean | undefined
}

const EQUIPO_NO_DISPONIBLE = 'Equipo no disponible'

const ORDEN_SEVERIDAD: Record<Severidad, number> = {
  critica: 0,
  atencion: 1,
}

const ORDEN_TIPO: Record<TipoAlertaGerencia, number> = {
  tarea_vencida: 0,
  sin_proxima_accion: 1,
  no_show: 2,
  bajo_meta_conversion: 3,
  caida_conversion: 4,
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
  agenda,
  reuniones,
  equipoConversion,
  metasVendedores,
  objetivosError = false,
}: DerivarAlertasGerenciaInput): AlertaGerencia[] {
  const alertas: AlertaGerencia[] = []
  const identidadPorId = new Map<string, Pick<ConversionEquipoVendedor, 'nombre' | 'supervisorNombre'>>()

  for (const integrante of equipoConversion) {
    if (!integrante.vendedorId || identidadPorId.has(integrante.vendedorId)) continue
    identidadPorId.set(integrante.vendedorId, {
      nombre: integrante.nombre,
      supervisorNombre: integrante.supervisorNombre,
    })
  }

  for (const vendedor of agenda?.vendedores ?? []) {
    if (!vendedor.activo || vendedor.rol !== 'vendedor') continue
    const equipo = identidadPorId.get(vendedor.vendedor_id)?.supervisorNombre
      || EQUIPO_NO_DISPONIBLE

    if (vendedor.vencidas > 0) {
      alertas.push({
        id: `tarea_vencida:${vendedor.vendedor_id}`,
        tipo: 'tarea_vencida',
        severidad: 'atencion',
        responsableId: vendedor.vendedor_id,
        responsable: vendedor.nombre,
        equipo,
        valor: vendedor.vencidas,
        destino: 'rendimiento',
      })
    }

    if (vendedor.leads_sin_accion > 0) {
      alertas.push({
        id: `sin_proxima_accion:${vendedor.vendedor_id}`,
        tipo: 'sin_proxima_accion',
        severidad: 'atencion',
        responsableId: vendedor.vendedor_id,
        responsable: vendedor.nombre,
        equipo,
        valor: vendedor.leads_sin_accion,
        destino: 'rendimiento',
      })
    }
  }

  for (const responsable of reuniones?.responsables ?? []) {
    if (responsable.responsable_id == null || responsable.no_show <= 0) continue
    const identidad = identidadPorId.get(responsable.responsable_id)
    const nombre = responsable.nombre || identidad?.nombre || 'Responsable no identificado'
    const equipo = responsable.supervisor_nombre
      || identidad?.supervisorNombre
      || EQUIPO_NO_DISPONIBLE

    alertas.push({
      id: `no_show:${responsable.responsable_id}`,
      tipo: 'no_show',
      severidad: responsable.no_show >= 2 ? 'critica' : 'atencion',
      responsableId: responsable.responsable_id,
      responsable: nombre,
      equipo,
      valor: responsable.no_show,
      destino: 'reuniones',
    })
  }

  const conversionAdaptada = adaptarConversionVendedores(conversiones, equipoConversion)
  if (conversionAdaptada.responsablesDisponibles) {
    for (const vendedor of conversionAdaptada.vendedores) {
      const detalle = vendedor.detalle
      if (
        vendedor.estadoConversion !== 'comparable'
        || detalle == null
        || detalle.leads <= 0
        || detalle.conversion_pct == null
      ) continue

      const metaGuardada = metasVendedores[vendedor.vendedorId]?.conversionObjetivo ?? 0
      const objetivo = metaConversionAplicable(metaGuardada, objetivosError)
      const actual = detalle.conversion_pct
      if (objetivo == null || actual >= objetivo) continue

      alertas.push({
        id: `bajo_meta_conversion:${vendedor.vendedorId}`,
        tipo: 'bajo_meta_conversion',
        severidad: 'atencion',
        responsableId: vendedor.vendedorId,
        responsable: vendedor.nombre,
        equipo: vendedor.supervisorNombre || EQUIPO_NO_DISPONIBLE,
        valor: actual,
        actual,
        objetivo,
        brechaPp: redondearPp(objetivo - actual),
        destino: 'ranking-vendedores',
      })
    }
  }

  const conversionActual = conversiones?.cohorte.conversion_contratos_pct
  const conversionAnterior = conversionesAnteriores?.cohorte.conversion_contratos_pct
  if (
    conversionActual != null
    && conversionAnterior != null
    && conversionActual < conversionAnterior
  ) {
    alertas.push({
      id: 'caida_conversion:global',
      tipo: 'caida_conversion',
      severidad: 'atencion',
      responsableId: null,
      responsable: 'Equipo comercial',
      equipo: 'Todos los equipos',
      valor: conversionActual,
      actual: conversionActual,
      objetivo: conversionAnterior,
      brechaPp: redondearPp(conversionAnterior - conversionActual),
      destino: 'conversiones',
    })
  }

  return ordenarAlertas(alertas)
}
