// Lecturas derivadas de la fotografía de distribución (RPC V2) para que la
// pantalla de Gerencia hable en lenguaje comercial: avisos de atención,
// fichas por analista, candidatos de reparto y presets de período.
//
// Reglas congeladas que este módulo respeta (ver vault "Distribución de leads
// por capital y trazabilidad CRM"):
//   * PEN y USD jamás se suman como MONTO; contar leads de ambas monedas sí es
//     válido (la capacidad es TODAS_LAS_MONEDAS por contrato).
//   * Conversión = convertidos / (convertidos + descartados); sin denominador
//     no se inventa un 0% (null = "Sin muestra").
//   * Nada aquí emite órdenes ("Priorizar", "Pausar"): produce evidencia
//     ordenada por criterios declarados; el gerente decide.
import type {
  MetricaDistribucionAnalista,
  MetricasDistribucionLeads,
  RangoCapitalPenId,
} from './metricas-distribucion'

// ── Utilidades de texto ───────────────────────────────────────────────────────

export function plural(n: number, singular: string, plurales: string): string {
  return n === 1 ? singular : plurales
}

/** % entero-ish legible; null cuando no hay denominador (Sin muestra). */
export function porcentajeLegible(numerador: number, denominador: number): string | null {
  if (denominador <= 0) return null
  const valor = (numerador / denominador) * 100
  return `${new Intl.NumberFormat('es-PE', { maximumFractionDigits: 1 }).format(valor)}%`
}

/** Minutos → "45 min" / "3.5 h" / "2 d" para la mediana de primer contacto. */
export function textoMinutos(minutos: number | null): string | null {
  if (minutos == null) return null
  const formato = new Intl.NumberFormat('es-PE', { maximumFractionDigits: 1 })
  if (minutos < 60) return `${new Intl.NumberFormat('es-PE', { maximumFractionDigits: 0 }).format(minutos)} min`
  const horas = minutos / 60
  if (horas < 24) return `${formato.format(horas)} h`
  return `${formato.format(horas / 24)} d`
}

// ── Período: presets en días calendario de Lima ───────────────────────────────

/** Hoy en America/Lima como 'YYYY-MM-DD' (la cohorte del backend usa días Lima). */
export function hoyLimaIso(ahora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(ahora)
}

function aUtc(iso: string): Date {
  return new Date(`${iso}T00:00:00Z`)
}

function aIso(fecha: Date): string {
  return fecha.toISOString().slice(0, 10)
}

export function sumarDiasIso(iso: string, dias: number): string {
  const fecha = aUtc(iso)
  fecha.setUTCDate(fecha.getUTCDate() + dias)
  return aIso(fecha)
}

export interface PresetPeriodo {
  id: 'este_mes' | 'ult_30' | 'ult_90' | 'este_anio'
  etiqueta: string
  desde: string
  hasta: string
}

/** Atajos de período inclusivos que terminan hoy (Lima). */
export function presetsPeriodo(hoyIso: string): PresetPeriodo[] {
  const inicioMes = `${hoyIso.slice(0, 7)}-01`
  const inicioAnio = `${hoyIso.slice(0, 4)}-01-01`
  return [
    { id: 'este_mes', etiqueta: 'Este mes', desde: inicioMes, hasta: hoyIso },
    { id: 'ult_30', etiqueta: 'Últimos 30 días', desde: sumarDiasIso(hoyIso, -29), hasta: hoyIso },
    { id: 'ult_90', etiqueta: 'Últimos 90 días', desde: sumarDiasIso(hoyIso, -89), hasta: hoyIso },
    { id: 'este_anio', etiqueta: 'Este año', desde: inicioAnio, hasta: hoyIso },
  ]
}

// ── Avisos: "Lo que merece tu atención" ──────────────────────────────────────

export interface AvisoAtencion {
  id: string
  severidad: 'critica' | 'media'
  texto: string
}

const RANGOS_ALTOS: readonly RangoCapitalPenId[] = ['pen_50000_100000', 'pen_mas_100000']

/**
 * Frases de evidencia en lenguaje comercial, críticas primero. Devuelve []
 * cuando no hay nada pendiente (la pantalla muestra entonces el estado en paz).
 * Solo usa hechos presentes en la fotografía: jamás inventa antigüedades ni
 * emite órdenes sobre personas.
 */
export function avisosAtencion(datos: MetricasDistribucionLeads): AvisoAtencion[] {
  const criticas: AvisoAtencion[] = []
  const medias: AvisoAtencion[] = []

  const vencidos = datos.resumen.sla_global_sin_contacto_vencidos_actuales
  if (vencidos > 0) {
    criticas.push({
      id: 'vencidos-24h',
      severidad: 'critica',
      texto: `${vencidos} ${plural(vencidos, 'lead lleva', 'leads llevan')} más de 24 horas sin primera atención.`,
    })
  }

  const altos = datos.por_repartir.total.pen.rangos.filter((rango) =>
    RANGOS_ALTOS.includes(rango.rango_id),
  )
  const altosCantidad = altos.reduce((total, rango) => total + rango.cantidad, 0)
  if (altosCantidad > 0) {
    criticas.push({
      id: 'altos-sin-asignar',
      severidad: 'critica',
      texto: `${altosCantidad} ${plural(altosCantidad, 'lead de más de S/ 50 mil espera', 'leads de más de S/ 50 mil esperan')} asignación.`,
    })
  }

  const sinBandeja = datos.por_repartir.global.carga_total
  if (sinBandeja > 0) {
    medias.push({
      id: 'cola-gerencia',
      severidad: 'media',
      texto: `${sinBandeja} ${plural(sinBandeja, 'lead sin responsable espera', 'leads sin responsable esperan')} directamente a Gerencia.`,
    })
  }

  for (const bandeja of datos.por_repartir.bandejas) {
    if (bandeja.carga_total === 0) continue
    const inactivo = bandeja.supervisor_activo ? '' : ' (supervisor inactivo)'
    medias.push({
      id: `bandeja-${bandeja.supervisor_id}`,
      severidad: 'media',
      texto: `La bandeja de ${bandeja.supervisor_nombre}${inactivo} tiene ${bandeja.carga_total} ${plural(bandeja.carga_total, 'lead por asignar', 'leads por asignar')}.`,
    })
  }

  const llenos = datos.analistas.filter(
    (analista) =>
      analista.disponible_para_recibir
      && analista.capacidad.objetivo != null
      && analista.capacidad.carga_activa >= analista.capacidad.objetivo,
  )
  if (llenos.length === 1) {
    const unico = llenos[0]
    if (unico) {
      medias.push({
        id: 'cartera-llena',
        severidad: 'media',
        texto: `${unico.nombre} está al tope de su cartera (${unico.capacidad.carga_activa} de ${unico.capacidad.objetivo}).`,
      })
    }
  } else if (llenos.length > 1) {
    const nombres = llenos.slice(0, 3).map((analista) => analista.nombre)
    const resto = llenos.length - nombres.length
    medias.push({
      id: 'cartera-llena',
      severidad: 'media',
      texto: `${llenos.length} analistas están al tope de su cartera: ${nombres.join(', ')}${resto > 0 ? ` y ${resto} más` : ''}.`,
    })
  }

  const conSinAtender = datos.analistas
    .filter((analista) => analista.operacion.sin_tocar_actual > 0)
    .sort((a, b) => b.operacion.sin_tocar_actual - a.operacion.sin_tocar_actual)
  const sinAtenderTotal = conSinAtender.reduce(
    (total, analista) => total + analista.operacion.sin_tocar_actual,
    0,
  )
  const top = conSinAtender[0]
  if (top && conSinAtender.length === 1) {
    medias.push({
      id: 'sin-atender',
      severidad: 'media',
      texto: `${top.nombre} tiene ${top.operacion.sin_tocar_actual} ${plural(top.operacion.sin_tocar_actual, 'lead sin atender', 'leads sin atender')}.`,
    })
  } else if (top) {
    medias.push({
      id: 'sin-atender',
      severidad: 'media',
      texto: `${sinAtenderTotal} leads sin atender; el caso mayor es ${top.nombre} con ${top.operacion.sin_tocar_actual}.`,
    })
  }

  const estancados = datos.analistas.reduce(
    (total, analista) => total + analista.operacion.estancados_actual,
    0,
  )
  if (estancados > 0) {
    medias.push({
      id: 'sin-avance',
      severidad: 'media',
      texto: `${estancados} ${plural(estancados, 'lead está', 'leads están')} sin avance según los plazos de su etapa.`,
    })
  }

  return [...criticas, ...medias]
}

// ── Fichas por analista (nivel 2: tarjetas) ───────────────────────────────────

export interface ConversionLegible {
  pct: string
  convertidos: number
  resueltos: number
}

export interface FichaAnalista {
  analista: MetricaDistribucionAnalista
  /** null = sin límite definido. */
  cuposLibres: number | null
  /** % de uso del límite (0-∞); null sin límite. */
  uso: number | null
  lleno: boolean
  /** Recibidos del período contando leads PEN + USD (conteo, no monto). */
  recibidosPeriodo: number
  conversionPen: ConversionLegible | null
  conversionUsd: ConversionLegible | null
  sla: { pct: string; en24: number; evaluables: number } | null
  sinAtender: number
  sinAvance: number
  transferidos: number
  parqueados: number
  capitalPen: number
  capitalUsd: number
  /** Tiene cartera o historia en dólares (muestra el chip USD). */
  conUsd: boolean
}

function conversionLegible(convertidos: number, descartados: number): ConversionLegible | null {
  const resueltos = convertidos + descartados
  const pct = porcentajeLegible(convertidos, resueltos)
  if (pct == null) return null
  return { pct, convertidos, resueltos }
}

export function fichaAnalista(analista: MetricaDistribucionAnalista): FichaAnalista {
  const objetivo = analista.capacidad.objetivo
  const carga = analista.capacidad.carga_activa
  const usd = analista.usd_no_segmentado
  const sla = porcentajeLegible(
    analista.operacion.sla_asignacion_en_24h,
    analista.operacion.sla_asignacion_evaluables,
  )
  return {
    analista,
    cuposLibres: objetivo == null ? null : Math.max(0, objetivo - carga),
    uso: objetivo == null || objetivo === 0 ? null : Math.round((carga / objetivo) * 100),
    lleno: objetivo != null && carga >= objetivo,
    recibidosPeriodo: analista.pen.cohorte.episodios_recibidos + usd.cohorte_episodios_recibidos,
    conversionPen: conversionLegible(
      analista.pen.cohorte.convertidos,
      analista.pen.cohorte.descartados,
    ),
    conversionUsd: conversionLegible(usd.convertidos, usd.descartados),
    sla: sla == null
      ? null
      : {
          pct: sla,
          en24: analista.operacion.sla_asignacion_en_24h,
          evaluables: analista.operacion.sla_asignacion_evaluables,
        },
    sinAtender: analista.operacion.sin_tocar_actual,
    sinAvance: analista.operacion.estancados_actual,
    transferidos: analista.operacion.transferidos,
    parqueados: analista.operacion.parqueados,
    capitalPen: analista.pen.cartera_actual.capital,
    capitalUsd: usd.cartera_actual_capital,
    conUsd:
      usd.cartera_actual_episodios > 0
      || usd.cohorte_episodios_recibidos > 0
      || usd.convertidos + usd.descartados > 0,
  }
}

export type OrdenFichas = 'cupos' | 'carga' | 'cierres' | 'sin_atender' | 'nombre'

export const ORDEN_FICHAS_ETIQUETAS: Record<OrdenFichas, string> = {
  cupos: 'Cupos libres',
  carga: 'Más carga',
  cierres: 'Mejores cierres en soles',
  sin_atender: 'Más sin atender',
  nombre: 'Nombre',
}

function porNombre(a: FichaAnalista, b: FichaAnalista): number {
  return a.analista.nombre.localeCompare(b.analista.nombre, 'es')
}

function pctNumerico(conversion: ConversionLegible | null): number {
  if (conversion == null || conversion.resueltos === 0) return -1
  return conversion.convertidos / conversion.resueltos
}

/**
 * Orden con criterio declarado. Quien no recibe leads va SIEMPRE al final:
 * conserva su historia visible pero no compite por la siguiente asignación.
 */
export function ordenarFichas(fichas: FichaAnalista[], orden: OrdenFichas): FichaAnalista[] {
  const disponibles = fichas.filter((ficha) => ficha.analista.disponible_para_recibir)
  const pausados = fichas.filter((ficha) => !ficha.analista.disponible_para_recibir)

  const comparadores: Record<OrdenFichas, (a: FichaAnalista, b: FichaAnalista) => number> = {
    cupos: (a, b) => {
      // Con cupo primero (más cupos → antes); sin límite después (menor carga
      // primero); llenos al final (menor exceso primero).
      const grupo = (ficha: FichaAnalista): number => {
        if (ficha.cuposLibres != null && ficha.cuposLibres > 0) return 0
        if (ficha.cuposLibres == null) return 1
        return 2
      }
      const diferenciaGrupo = grupo(a) - grupo(b)
      if (diferenciaGrupo !== 0) return diferenciaGrupo
      if (grupo(a) === 0) return (b.cuposLibres ?? 0) - (a.cuposLibres ?? 0) || porNombre(a, b)
      if (grupo(a) === 1) {
        return a.analista.capacidad.carga_activa - b.analista.capacidad.carga_activa || porNombre(a, b)
      }
      const excesoA = a.analista.capacidad.carga_activa - (a.analista.capacidad.objetivo ?? 0)
      const excesoB = b.analista.capacidad.carga_activa - (b.analista.capacidad.objetivo ?? 0)
      return excesoA - excesoB || porNombre(a, b)
    },
    carga: (a, b) =>
      b.analista.capacidad.carga_activa - a.analista.capacidad.carga_activa || porNombre(a, b),
    cierres: (a, b) => pctNumerico(b.conversionPen) - pctNumerico(a.conversionPen) || porNombre(a, b),
    sin_atender: (a, b) =>
      b.sinAtender - a.sinAtender || b.sinAvance - a.sinAvance || porNombre(a, b),
    nombre: porNombre,
  }

  const comparador = comparadores[orden]
  return [...disponibles.sort(comparador), ...pausados.sort(comparador)]
}

// ── Equipos (agrupación por supervisor con su bandeja) ────────────────────────

export interface EquipoDistribucion {
  id: string
  nombre: string
  activo: boolean
  analistas: MetricaDistribucionAnalista[]
  pendientesBandeja: number
}

/** Equipo al que pertenece un analista (un supervisor con cartera es de su propio equipo). */
export function idEquipoDeAnalista(analista: MetricaDistribucionAnalista): string {
  return (
    analista.supervisor_id
    ?? (analista.rol === 'supervisor' ? analista.analista_id : 'sin-supervisor')
  )
}

/**
 * Agrupa por supervisor. Un supervisor con cartera propia integra su propio
 * equipo; una bandeja sin analistas visibles también aparece (sus pendientes
 * no deben desaparecer de la lectura).
 */
export function equiposDistribucion(datos: MetricasDistribucionLeads): EquipoDistribucion[] {
  const equipos = new Map<string, EquipoDistribucion>()
  const bandejas = new Map(
    datos.por_repartir.bandejas.map((bandeja) => [bandeja.supervisor_id, bandeja]),
  )

  for (const analista of datos.analistas) {
    const id = idEquipoDeAnalista(analista)
    const nombre = analista.supervisor_nombre
      ?? (analista.rol === 'supervisor' ? analista.nombre : 'Sin supervisor asignado')
    let equipo = equipos.get(id)
    if (!equipo) {
      const bandeja = bandejas.get(id)
      equipo = {
        id,
        nombre,
        activo: bandeja?.supervisor_activo ?? true,
        analistas: [],
        pendientesBandeja: bandeja?.carga_total ?? 0,
      }
      equipos.set(id, equipo)
    }
    equipo.analistas.push(analista)
  }

  for (const bandeja of datos.por_repartir.bandejas) {
    if (equipos.has(bandeja.supervisor_id)) continue
    equipos.set(bandeja.supervisor_id, {
      id: bandeja.supervisor_id,
      nombre: bandeja.supervisor_nombre,
      activo: bandeja.supervisor_activo,
      analistas: [],
      pendientesBandeja: bandeja.carga_total,
    })
  }

  return [...equipos.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'))
}

/** Agregados de un equipo para su tarjeta-filtro (lectura antes de bajar al analista). */
export interface ResumenEquipo {
  cargaActiva: number
  /** Suma de límites definidos; null si nadie del equipo tiene límite. */
  limiteDefinido: number | null
  cuposLibres: number
  sinAtender: number
  /** Analistas disponibles que están al tope de su límite. */
  llenos: number
}

export function resumenEquipo(fichasDelEquipo: FichaAnalista[]): ResumenEquipo {
  let cargaActiva = 0
  let limiteDefinido: number | null = null
  let cuposLibres = 0
  let sinAtender = 0
  let llenos = 0
  for (const ficha of fichasDelEquipo) {
    cargaActiva += ficha.analista.capacidad.carga_activa
    const objetivo = ficha.analista.capacidad.objetivo
    if (objetivo != null) {
      limiteDefinido = (limiteDefinido ?? 0) + objetivo
      cuposLibres += Math.max(0, objetivo - ficha.analista.capacidad.carga_activa)
    }
    sinAtender += ficha.sinAtender
    if (ficha.analista.disponible_para_recibir && ficha.lleno) llenos += 1
  }
  return { cargaActiva, limiteDefinido, cuposLibres, sinAtender, llenos }
}

// ── Asistente de reparto (nivel 3) ────────────────────────────────────────────

export type SeleccionReparto =
  | { moneda: 'PEN'; rangoId: RangoCapitalPenId }
  | { moneda: 'USD' }

export interface CandidatoReparto {
  analista: MetricaDistribucionAnalista
  /** null = sin límite definido. */
  cuposLibres: number | null
  lleno: boolean
  cargaActiva: number
  /** Actividad en el segmento elegido (rango PEN o total USD). */
  segmento: {
    activos: number
    capital: number
    recibidos: number
    conversion: ConversionLegible | null
  }
}

export interface ResultadoReparto {
  candidatos: CandidatoReparto[]
  /** Analistas con historia que hoy no reciben (se informan, no compiten). */
  noReciben: number
}

/**
 * Candidatos para repartir un lead del segmento elegido, ordenados por cupos
 * libres (los "sin límite" después, por menor carga; los llenos al final).
 * El orden es un criterio DECLARADO en la interfaz, no una recomendación.
 */
export function candidatosReparto(
  datos: MetricasDistribucionLeads,
  seleccion: SeleccionReparto,
): ResultadoReparto {
  const disponibles = datos.analistas.filter((analista) => analista.disponible_para_recibir)
  const noReciben = datos.analistas.length - disponibles.length

  const candidatos = disponibles.map((analista): CandidatoReparto => {
    const objetivo = analista.capacidad.objetivo
    const carga = analista.capacidad.carga_activa
    let segmento: CandidatoReparto['segmento']
    if (seleccion.moneda === 'PEN') {
      const rango = analista.pen.rangos.find((r) => r.rango_id === seleccion.rangoId)
      segmento = {
        activos: rango?.cartera_actual.episodios ?? 0,
        capital: rango?.cartera_actual.capital ?? 0,
        recibidos: rango?.cohorte.episodios_recibidos ?? 0,
        conversion: conversionLegible(
          rango?.cohorte.convertidos ?? 0,
          rango?.cohorte.descartados ?? 0,
        ),
      }
    } else {
      const usd = analista.usd_no_segmentado
      segmento = {
        activos: usd.cartera_actual_episodios,
        capital: usd.cartera_actual_capital,
        recibidos: usd.cohorte_episodios_recibidos,
        conversion: conversionLegible(usd.convertidos, usd.descartados),
      }
    }
    return {
      analista,
      cuposLibres: objetivo == null ? null : Math.max(0, objetivo - carga),
      lleno: objetivo != null && carga >= objetivo,
      cargaActiva: carga,
      segmento,
    }
  })

  candidatos.sort((a, b) => {
    const grupo = (candidato: CandidatoReparto): number => {
      if (candidato.cuposLibres != null && candidato.cuposLibres > 0) return 0
      if (candidato.cuposLibres == null) return 1
      return 2
    }
    const diferenciaGrupo = grupo(a) - grupo(b)
    if (diferenciaGrupo !== 0) return diferenciaGrupo
    if (grupo(a) === 0 && a.cuposLibres !== b.cuposLibres) {
      return (b.cuposLibres ?? 0) - (a.cuposLibres ?? 0)
    }
    if (grupo(a) === 1 && a.cargaActiva !== b.cargaActiva) return a.cargaActiva - b.cargaActiva
    // Mismo espacio: primero quien tiene MENOS activos del segmento (equilibra
    // el rango sin declarar a nadie "mejor").
    if (a.segmento.activos !== b.segmento.activos) return a.segmento.activos - b.segmento.activos
    return a.analista.nombre.localeCompare(b.analista.nombre, 'es')
  })

  return { candidatos, noReciben }
}
