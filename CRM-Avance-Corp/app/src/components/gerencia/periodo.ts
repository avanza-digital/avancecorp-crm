import { fechaLima } from '@/lib/agenda-derivada'

export interface PeriodoGerencia {
  desde: string
  hasta: string
}

export interface MetaMensualGerencia {
  etiqueta: string
  comparable: boolean
  errorCarga?: boolean
}

export type CodigoErrorPeriodoGerencia =
  | 'fechas_requeridas'
  | 'fecha_invalida'
  | 'orden_invalido'
  | 'fecha_futura'
  | 'rango_demasiado_amplio'

export type ValidacionPeriodoGerencia =
  | { valido: true }
  | { valido: false; codigo: CodigoErrorPeriodoGerencia; mensaje: string }

const MILISEGUNDOS_POR_DIA = 24 * 60 * 60 * 1000
const MAXIMA_DIFERENCIA_DIAS = 365

function instanteFechaIso(fecha: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(fecha)) return null
  const instante = Date.parse(`${fecha}T00:00:00.000Z`)
  if (!Number.isFinite(instante)) return null
  return new Date(instante).toISOString().slice(0, 10) === fecha ? instante : null
}

/** Mes calendario vigente en Lima, cortado al día de hoy. */
export function periodoInicialGerencia(ahora = Date.now()): PeriodoGerencia {
  const hasta = fechaLima(ahora)
  return { desde: `${hasta.slice(0, 7)}-01`, hasta }
}

/**
 * Convierte un mes YYYY-MM en su corte comercial mensual.
 * Los meses cerrados abarcan todo el calendario; el vigente termina hoy en
 * Lima para no consultar días futuros. Esta es la frontera única que alinea
 * conversión, capital y cosecha dentro de los rankings.
 */
export function periodoMesCalendario(mes: string, ahora = Date.now()): PeriodoGerencia {
  const vigente = periodoInicialGerencia(ahora)
  const mesVigente = vigente.desde.slice(0, 7)
  const desde = `${mes}-01`
  if (mes === mesVigente) return { desde, hasta: vigente.hasta }

  const anio = Number(mes.slice(0, 4))
  const numeroMes = Number(mes.slice(5, 7))
  const hasta = new Date(Date.UTC(anio, numeroMes, 0)).toISOString().slice(0, 10)
  return { desde, hasta }
}

/** Replica las restricciones de fecha de los RPC antes de consultar. */
export function validarPeriodoGerencia(
  periodo: PeriodoGerencia,
  ahora = Date.now(),
): ValidacionPeriodoGerencia {
  if (!periodo.desde || !periodo.hasta) {
    return { valido: false, codigo: 'fechas_requeridas', mensaje: 'Selecciona las fechas desde y hasta.' }
  }

  const desde = instanteFechaIso(periodo.desde)
  const hasta = instanteFechaIso(periodo.hasta)
  if (desde == null || hasta == null) {
    return { valido: false, codigo: 'fecha_invalida', mensaje: 'Ingresa fechas válidas.' }
  }
  if (desde > hasta) {
    return { valido: false, codigo: 'orden_invalido', mensaje: 'La fecha desde no puede ser posterior a la fecha hasta.' }
  }

  const hoyLima = instanteFechaIso(fechaLima(ahora))
  if (hoyLima == null || hasta > hoyLima) {
    return { valido: false, codigo: 'fecha_futura', mensaje: 'La fecha hasta no puede ser posterior a hoy en Lima.' }
  }
  if ((hasta - desde) / MILISEGUNDOS_POR_DIA > MAXIMA_DIFERENCIA_DIAS) {
    return { valido: false, codigo: 'rango_demasiado_amplio', mensaje: 'El rango no puede superar 365 días de diferencia.' }
  }

  return { valido: true }
}

/**
 * Describe la meta mensual disponible y comprueba que el rango aplicado sea
 * exactamente el corte de esa meta. Por defecto conserva el contrato histórico
 * del store (mes vigente); los rankings le pasan su mes calendario normalizado.
 */
export function semanticaMetaMensual(
  periodo: PeriodoGerencia,
  ahora = Date.now(),
  periodoMeta: PeriodoGerencia = periodoInicialGerencia(ahora),
): MetaMensualGerencia {
  const fecha = new Date(`${periodoMeta.desde}T12:00:00Z`)
  const etiqueta = new Intl.DateTimeFormat('es-PE', {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(fecha).replace(' de ', ' ')

  return {
    etiqueta,
    comparable: periodo.desde === periodoMeta.desde && periodo.hasta === periodoMeta.hasta,
  }
}

export function mensajeMetaNoComparable(meta: MetaMensualGerencia): string {
  if (meta.errorCarga) return `No pudimos cargar las metas mensuales de ${meta.etiqueta}.`
  return `La meta mensual de ${meta.etiqueta} no es comparable con el rango aplicado.`
}
