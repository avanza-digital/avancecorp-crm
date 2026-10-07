import type { ConversionEquipoVendedor } from './conversion-equipo'
import {
  lecturaCobertura,
  type ConversionMensual,
  type ResponsableConversionMensual,
} from './conversion-mensual'
import type {
  DetalleConversionVendedor,
  MetricasConversiones,
} from './metricas-conversiones'
import { sondasNucleoVerificadas } from './sondas-conversion'
import {
  capitalObjetivo,
  capitalReal,
  type CumplimientoVendedor,
  type ObjetivosPorVendedor,
} from './objetivos'
import { tcAplicable, totalEnSoles } from './capital-unificado'

/**
 * Los estados del analista en el ranking. Mapa CERRADO servidor→front (la
 * conversión mensual emite cuatro; el quinto lo produce SOLO el cliente):
 *
 *   medible         → 'comparable'      (tiene divisor: compite por puesto)
 *   solo_arrastre   → 'solo_arrastre'   (divisor 0 pero CERRÓ cartera vieja:
 *                                        entra al ranking, al fondo, sin %)
 *   solo_referidos  → 'solo_referidos'  (divisor 0 pero RECIBIÓ referidos:
 *                                        trabajó; se rotula aparte, jamás como
 *                                        «sin muestra» — leerlo como «no
 *                                        trabajó» es la confusión que este
 *                                        estado existe para impedir)
 *   sin_actividad   → 'sin_muestra'     (ni recibió ni cerró)
 *   (fail-closed)   → 'indisponible'    (colección incompleta: SOLO cliente)
 *
 * Los payloads viejos (metricas_conversiones_fn / _equipo_fn) no traen estado
 * del servidor y siguen derivando comparable/sin_muestra de sus números — sus
 * casos de test NO se invierten (miden otro payload).
 */
export type EstadoConversionVendedor =
  | 'comparable'
  | 'solo_arrastre'
  | 'solo_referidos'
  | 'sin_muestra'
  | 'indisponible'

/**
 * Lo ÚNICO que el ranking de conversión necesita de un analista.
 *
 * Se nombra aparte porque hay dos payloads que lo satisfacen: el de gerencia
 * (`metricas_conversiones_fn`, que trae mucho más) y el del equipo del supervisor
 * (`metricas_conversiones_equipo_fn`, que a propósito trae solo esto — menos
 * superficie que auditar). El clasificador y la tabla usan estos tres campos y
 * nada más: verificado en clasificarRankingConversion y en RankingConversion.
 */
export interface DetalleRankeable {
  leads: number
  clientes: number
  conversion_pct: number | null
  /**
   * Solo el payload de la conversión MENSUAL los trae (los dos viejos no):
   * con numerador ponderado, el entero `clientes` deja de ordenar bien y el
   * desempate baja a numerador y luego divisor. Opcionales para que los
   * payloads viejos sigan satisfaciendo la interfaz sin cambiar.
   */
  numerador?: number
  divisor?: number
}

/**
 * `D` es el detalle que trae cada payload. Por defecto el COMPLETO de gerencia,
 * para que sus pantallas (inteligencia-comercial, resumen-gerencia) sigan viendo
 * capital, contactados y tendencia con el tipo exacto; el ranking del supervisor
 * la instancia con su detalle reducido. Un genérico y no un estrechamiento: lo
 * segundo habría dejado sin tipar a esas dos pantallas.
 */
export interface ConversionVendedorAdaptada<D extends DetalleRankeable = DetalleConversionVendedor> {
  vendedorId: string
  nombre: string
  supervisorId: string | null
  supervisorNombre: string
  detalle: D | null
  estadoConversion: EstadoConversionVendedor
}

/**
 * Punto semanal del EQUIPO: solo los enteros servidos, sumados. Desde F3 el
 * navegador NO deriva un % semanal del equipo — el servidor no lo sirve, y
 * fabricarlo aquí era exactamente la clase de aritmética paralela (H12) que
 * «Conversión única» vino a matar. Si algún día hace falta la curva de %, se
 * sirve desde la tabla-base, no se divide en el cliente.
 */
export interface PuntoTendenciaEquipo {
  semana: number
  desde: string
  hasta: string
  leads: number
  clientes: number
}

export interface ConversionVendedoresAdaptada<D extends DetalleRankeable = DetalleConversionVendedor> {
  /**
   * `true` solo cuando la RPC entregó una fila única para cada analista visible.
   * Una colección ausente, vacía o parcial nunca equivale a métricas en cero ni
   * permite construir un ranking representativo del equipo completo.
   */
  responsablesDisponibles: boolean
  vendedores: ConversionVendedorAdaptada<D>[]
  tendenciaSemanal: PuntoTendenciaEquipo[] | null
}

/**
 * Fuentes que Gerencia puede aislar dentro del índice comercial. Landing,
 * Formulario y Referido son orígenes de prospectos; Renovación y Upgrade son
 * operaciones de cartera. El selector las reúne porque las cinco aportan al
 * mismo numerador, pero mantiene visible la familia para no presentarlas como
 * si compartieran base.
 */
export const FUENTES_CONVERSION = [
  { id: 'landing', etiqueta: 'Landing', familia: 'prospectos' },
  { id: 'formulario', etiqueta: 'Formulario', familia: 'prospectos' },
  { id: 'upgrade', etiqueta: 'Upgrade', familia: 'cartera' },
  { id: 'referido', etiqueta: 'Referido', familia: 'prospectos' },
  { id: 'renovacion', etiqueta: 'Renovación', familia: 'cartera' },
] as const

export type FuenteConversion = (typeof FUENTES_CONVERSION)[number]['id']
export type FiltroFuentesConversion = FuenteConversion | readonly FuenteConversion[] | null

export function etiquetaFuentesConversion(fuente: FiltroFuentesConversion): string {
  if (fuente == null) return 'Todas las fuentes'
  const elegidas = typeof fuente === 'string' ? [fuente] : fuente
  return FUENTES_CONVERSION.filter((opcion) => elegidas.includes(opcion.id))
    .map((opcion) => opcion.etiqueta).join(' + ') || 'las fuentes elegidas'
}

export interface AporteConversionVendedor {
  divisor: number
  numerador: number
  porcentaje: number | null
  resultados: number
  cierres: number
  operaciones: number
}

export interface AporteConversionRango {
  fuente: FiltroFuentesConversion
  periodo: { desde: string; hasta: string }
  etiqueta: string
  familia: 'todos' | 'prospectos' | 'cartera'
  divisor: number
  numerador: number
  porcentaje: number | null
  resultados: number
  cierres: number
  operaciones: number
  peso: number | null
  /** Tope de referidos del mes (0–100) o null/ausente si no hay: solo rotula, el aporte ya viene recortado. */
  topeReferidosPct?: number | null
  porVendedor: ReadonlyMap<string, AporteConversionVendedor>
}

/**
 * Proyección de lectura del filtro de Gerencia sobre el payload ya servido.
 * No decide elegibilidad ni ponderaciones: cierres_por_semana y
 * conversion_operaciones traen aporte_numerador listo desde el núcleo. El
 * cliente únicamente agrupa la fuente elegida contra el divisor publicado.
 */
export function adaptarAporteConversionRango(
  datos: MetricasConversiones | null | undefined,
  fuente: FiltroFuentesConversion,
  datosPorOrigen: Partial<Record<FuenteConversion, MetricasConversiones | null | undefined>> = {},
): AporteConversionRango | null {
  if (datos?.nucleo == null) return null
  // 🔴 LA SONDA YA NO VERIFICA LA CIFRA DELEGADA. `sondas.cuadra` compara el
  // recálculo vivo contra `conversion_mensual_por_vendedor`; desde la Ola 1b,
  // cuando `fuente === 'mensual'` lo publicado NO es ese recálculo sino la foto
  // oficial. Seguir usándola como interruptor dejaría la pantalla en blanco por
  // un descuadre que no afecta a lo que se está enseñando. La sonda sigue
  // gobernando todo lo que sí verifica: los desgloses CON filtro, que se
  // calculan en vivo.
  if (!sondasNucleoVerificadas(datos.sondas)
    && !(fuente == null && datos.nucleo.fuente === 'mensual')) return null

  const nucleo = datos.nucleo
  // 🔴 EL DIVISOR CONTRA EL QUE SE COMPARAN LOS DESGLOSES ES EL VIVO, NO EL
  // OFICIAL. Desde la Ola 1b, el paquete SIN filtro de fuente delega su cifra
  // en `crm.conversion_mensual_fn`, pero los paquetes CON filtro nunca delegan
  // (el núcleo no se filtra). Comparar el divisor de unos contra el de otros
  // funcionaba sólo mientras ambos coincidían; el día que la foto sellada de un
  // mes cerrado traiga otro divisor, esa igualdad se rompe y este adaptador
  // devolvía `null` — panel multi-fuente EN BLANCO, justo el día que importa.
  // `recalculo_vivo` es lo que esta misma puerta habría calculado; cuando no
  // hubo delegación, no existe y el vivo ES el publicado.
  const vivo = nucleo.recalculo_vivo ?? nucleo
  if (fuente != null && typeof fuente !== 'string') {
    const elegidas = FUENTES_CONVERSION.filter((opcion) => fuente.includes(opcion.id))
    if (elegidas.length === 0) return null
    const aportes = elegidas.map((opcion) => adaptarAporteConversionRango(
      opcion.familia === 'cartera' ? datos : datosPorOrigen[opcion.id], opcion.id,
    ))
    if (aportes.some((aporte) => aporte == null
      || aporte.periodo.desde !== datos.periodo.desde
      || aporte.periodo.hasta !== datos.periodo.hasta
      || aporte.divisor !== vivo.divisor)) return null
    const validos = aportes.filter((aporte) => aporte != null)
    const primero = validos[0]!
    const porVendedor = new Map<string, AporteConversionVendedor>()
    for (const [id, base] of primero.porVendedor) {
      const filas = validos.map((aporte) => aporte.porVendedor.get(id))
      if (filas.some((fila) => fila == null || fila.divisor !== base.divisor)) continue
      const numerador = filas.reduce((total, fila) => total + fila!.numerador, 0)
      const cierres = filas.reduce((total, fila) => total + fila!.cierres, 0)
      const operaciones = filas.reduce((total, fila) => total + fila!.operaciones, 0)
      porVendedor.set(id, {
        divisor: base.divisor, numerador, cierres, operaciones,
        resultados: cierres + operaciones,
        porcentaje: base.divisor > 0 ? Math.round((100 * numerador / base.divisor + Number.EPSILON) * 100) / 100 : null,
      })
    }
    const numerador = validos.reduce((total, aporte) => total + aporte.numerador, 0)
    const cierres = validos.reduce((total, aporte) => total + aporte.cierres, 0)
    const operaciones = validos.reduce((total, aporte) => total + aporte.operaciones, 0)
    return {
      fuente, periodo: { desde: datos.periodo.desde, hasta: datos.periodo.hasta },
      etiqueta: etiquetaFuentesConversion(fuente),
      familia: elegidas.every((opcion) => opcion.familia === 'cartera') ? 'cartera'
        : elegidas.every((opcion) => opcion.familia === 'prospectos') ? 'prospectos' : 'todos',
      divisor: vivo.divisor, numerador, cierres, operaciones, resultados: cierres + operaciones,
      porcentaje: vivo.divisor > 0 ? Math.round((100 * numerador / vivo.divisor + Number.EPSILON) * 100) / 100 : null,
      peso: null, topeReferidosPct: nucleo.tope_referidos_pct ?? null, porVendedor,
    }
  }
  const definicion = fuente == null
    ? null
    : FUENTES_CONVERSION.find((opcion) => opcion.id === fuente) ?? null
  const esOrigenProspecto = definicion?.familia === 'prospectos'
  const esOperacionCartera = definicion?.familia === 'cartera'

  if (esOrigenProspecto && (datos.origen_filtrado ?? null) !== fuente) return null
  if ((fuente == null || esOperacionCartera) && (datos.origen_filtrado ?? null) !== null) return null

  let numerador: number
  let porcentaje: number | null
  let resultados: number
  let peso: number | null

  if (fuente == null) {
    numerador = nucleo.numerador
    porcentaje = nucleo.conversion_pct
    resultados = nucleo.cierres_no_referidos + nucleo.cierres_referidos + nucleo.operaciones_cartera
    peso = null
  } else if (esOrigenProspecto) {
    const cierres = datos.cierres_por_semana
    if (cierres == null
      || cierres.desde !== datos.periodo.desde
      || cierres.hasta !== datos.periodo.hasta
      || cierres.origen_filtrado !== fuente) return null
    numerador = cierres.aporte_cierres
    resultados = cierres.cierres
    // `nucleo.peso_*` es el peso VIVO y así se queda: rotula este desglose,
    // que se recalcula siempre —también cuando el total de arriba viene
    // sellado—. El peso con el que se selló la foto viaja aparte, en
    // `nucleo.ponderacion_oficial`, para no romper a los bundles antiguos.
    peso = fuente === 'referido' ? nucleo.peso_referido : 1
    porcentaje = vivo.divisor > 0
      ? Math.round((100 * numerador / vivo.divisor + Number.EPSILON) * 100) / 100
      : null
  } else {
    const operaciones = datos.conversion_operaciones
    if (operaciones == null
      || !operaciones.completo
      || operaciones.desde !== datos.periodo.desde
      || operaciones.hasta !== datos.periodo.hasta
      || operaciones.origen_filtrado !== null) return null
    const elegidas = operaciones.detalle.filter((operacion) => operacion.categoria === fuente)
    numerador = elegidas.reduce((total, operacion) => total + operacion.aporte_numerador, 0)
    resultados = elegidas.length
    peso = fuente === 'renovacion' ? (nucleo.peso_renovacion ?? nucleo.peso_referido) : 1
    porcentaje = vivo.divisor > 0
      ? Math.round((100 * numerador / vivo.divisor + Number.EPSILON) * 100) / 100
      : null
  }

  const operacionesPorVendedor = new Map<string, { cantidad: number, aporte: number }>()
  if (datos.conversion_operaciones?.completo) {
    for (const operacion of datos.conversion_operaciones.detalle) {
      if (operacion.analista_id == null || (esOperacionCartera && operacion.categoria !== fuente)) continue
      const actual = operacionesPorVendedor.get(operacion.analista_id) ?? { cantidad: 0, aporte: 0 }
      actual.cantidad += 1
      actual.aporte += operacion.aporte_numerador
      operacionesPorVendedor.set(operacion.analista_id, actual)
    }
  }

  const porVendedor = new Map<string, AporteConversionVendedor>()
  for (const responsable of datos.responsables ?? []) {
    const divisor = responsable.nucleo_divisor
    if (divisor == null) continue
    const operaciones = operacionesPorVendedor.get(responsable.vendedor_id) ?? { cantidad: 0, aporte: 0 }
    let aporte = 0
    let cantidad = 0
    let pct: number | null = null

    if (fuente == null) {
      if (responsable.nucleo_numerador == null) continue
      aporte = responsable.nucleo_numerador
      cantidad = (responsable.cierres_por_semana ?? []).reduce((total, semana) => total + semana.cierres, 0)
        + operaciones.cantidad
      pct = responsable.nucleo_conversion_pct ?? null
    } else if (esOrigenProspecto) {
      if (responsable.cierres_por_semana == null) continue
      aporte = responsable.cierres_por_semana.reduce((total, semana) => total + semana.aporte_cierres, 0)
      cantidad = responsable.cierres_por_semana.reduce((total, semana) => total + semana.cierres, 0)
      pct = divisor > 0
        ? Math.round((100 * aporte / divisor + Number.EPSILON) * 100) / 100
        : null
    } else {
      aporte = operaciones.aporte
      cantidad = operaciones.cantidad
      pct = divisor > 0
        ? Math.round((100 * aporte / divisor + Number.EPSILON) * 100) / 100
        : null
    }

    porVendedor.set(responsable.vendedor_id, {
      divisor,
      numerador: aporte,
      porcentaje: pct,
      resultados: cantidad,
      cierres: esOperacionCartera ? 0 : fuente == null ? cantidad - operaciones.cantidad : cantidad,
      operaciones: esOrigenProspecto ? 0 : operaciones.cantidad,
    })
  }

  return {
    fuente,
    periodo: { desde: datos.periodo.desde, hasta: datos.periodo.hasta },
    etiqueta: definicion?.etiqueta ?? 'Todos los aportes',
    familia: definicion?.familia ?? 'todos',
    // La base publicada es la MISMA con la que se dividió: sin filtro, el % es
    // el oficial (`nucleo`); con fuente, se calculó sobre el recálculo vivo.
    // Devolver la oficial con un % vivo mezclaba bases el día que difieren
    // (mes sellado) y tumbaba la multiselección con cartera en la l.202.
    divisor: fuente == null ? nucleo.divisor : vivo.divisor,
    numerador,
    porcentaje,
    resultados,
    cierres: esOperacionCartera ? 0 : fuente == null ? resultados - nucleo.operaciones_cartera : resultados,
    operaciones: esOrigenProspecto ? 0 : fuente == null ? nucleo.operaciones_cartera : resultados,
    peso,
    topeReferidosPct: nucleo.tope_referidos_pct ?? null,
    porVendedor,
  }
}

export type ConversionVendedorConDetalle<D extends DetalleRankeable = DetalleConversionVendedor> =
  ConversionVendedorAdaptada<D> & { detalle: D }

export interface RankingConversionVendedores<D extends DetalleRankeable = DetalleConversionVendedor> {
  conPuesto: ConversionVendedorConDetalle<D>[]
  sinMuestra: ConversionVendedorConDetalle<D>[]
  indisponibles: ConversionVendedorAdaptada<D>[]
}

export type EstadoCapitalVendedor = 'comparable' | 'sin_meta' | 'indisponible'

/**
 * Identidad mínima que necesita el ranking de capital.
 *
 * Vive separada de `ConversionVendedorAdaptada` a propósito: el capital sale
 * de `cumplimiento_metas_fn` y no debe depender de que haya cargado ninguna
 * RPC de conversión. Antes el componente fabricaba estas identidades pasando
 * por `adaptarConversionVendedores(metricas_conversiones_fn, ...)`; una caída
 * de aquella lectura lateral podía dejar sin ranking a un capital sano.
 */
interface IdentidadVendedorRanking {
  vendedorId: string
  nombre: string
  supervisorNombre: string
}

function porNombre(
  a: Pick<ConversionVendedorAdaptada, 'nombre' | 'vendedorId'>,
  b: Pick<ConversionVendedorAdaptada, 'nombre' | 'vendedorId'>,
): number {
  return a.nombre.localeCompare(b.nombre, 'es') || a.vendedorId.localeCompare(b.vendedorId)
}

export function estadoConversion(
  detalle: DetalleRankeable | null,
  estadoServidor?: 'medible' | 'solo_referidos' | 'solo_arrastre' | 'sin_actividad',
): EstadoConversionVendedor {
  if (!detalle) return 'indisponible'
  // El payload de la conversión mensual DECLARA el estado y el servidor es la
  // única fuente que puede distinguir «solo recibió referidos» de «no recibió
  // nada» (los dos tienen divisor 0). Derivarlo aquí sería inventar.
  if (estadoServidor !== undefined) {
    if (estadoServidor === 'medible') {
      // Con divisor > 0 el % es obligatorio; si falta, la fila está enferma y
      // se declara indisponible en vez de competir con un dato a medias.
      return detalle.conversion_pct == null ? 'indisponible' : 'comparable'
    }
    if (estadoServidor === 'sin_actividad') return 'sin_muestra'
    return estadoServidor
  }
  // Payloads viejos (sin estado del servidor): la derivación de siempre.
  if (detalle.leads > 0 && detalle.conversion_pct == null) return 'indisponible'
  return detalle.leads === 0 ? 'sin_muestra' : 'comparable'
}

/** Suma por semana los enteros SERVIDOS por responsable. Sin divisiones (F3). */
function tendenciaSemanalEquipo(
  responsables: NonNullable<MetricasConversiones['responsables']>,
): PuntoTendenciaEquipo[] {
  const semanas = new Map<string, PuntoTendenciaEquipo>()

  for (const responsable of responsables) {
    for (const punto of responsable.tendencia_semanal) {
      const clave = `${punto.semana}|${punto.desde}|${punto.hasta}`
      const existente = semanas.get(clave)
      if (existente) {
        existente.leads += punto.leads
        existente.clientes += punto.clientes
      } else {
        semanas.set(clave, {
          semana: punto.semana,
          desde: punto.desde,
          hasta: punto.hasta,
          leads: punto.leads,
          clientes: punto.clientes,
        })
      }
    }
  }

  return [...semanas.values()]
    .sort((a, b) => a.desde.localeCompare(b.desde) || a.semana - b.semana)
}

/**
 * Une identidad visible del equipo con métricas autoritativas de la RPC.
 * Ninguna métrica operativa de `equipo` se usa como fallback: sus contadores
 * pueden pertenecer a otro corte y una ausencia de la RPC no representa cero.
 */
export function adaptarConversionVendedores(
  datos: MetricasConversiones | null | undefined,
  equipo: readonly ConversionEquipoVendedor[],
): ConversionVendedoresAdaptada {
  const responsables = datos?.responsables
  const detallePorId = new Map(
    (responsables ?? []).map((detalle) => [detalle.vendedor_id, detalle]),
  )
  const identidadPorId = new Map<string, {
    nombre: string
    supervisorId: string | null
    supervisorNombre: string
  }>()

  for (const integrante of equipo) {
    if (!integrante.vendedorId || identidadPorId.has(integrante.vendedorId)) continue
    identidadPorId.set(integrante.vendedorId, {
      nombre: integrante.nombre,
      supervisorId: integrante.supervisorId ?? null,
      supervisorNombre: integrante.supervisorNombre,
    })
  }

  // Una fila válida de la RPC no debe desaparecer si todavía no llegó su
  // identidad al store. La etiqueta genérica evita exponer el UUID en pantalla.
  for (const detalle of responsables ?? []) {
    if (identidadPorId.has(detalle.vendedor_id)) continue
    identidadPorId.set(detalle.vendedor_id, {
      nombre: 'Analista no identificado',
      supervisorId: null,
      supervisorNombre: 'Equipo no disponible',
    })
  }

  const responsablesCompletos = responsables !== undefined
    && detallePorId.size === responsables.length
    && [...identidadPorId.keys()].every((vendedorId) => detallePorId.has(vendedorId))

  const vendedores = [...identidadPorId.entries()].map(([vendedorId, identidad]) => {
    // Una respuesta parcial no puede otorgar puestos solo al subconjunto que
    // llegó: todo el bloque se marca como no disponible hasta recuperar el
    // contrato completo de la RPC.
    const detalle = responsablesCompletos ? (detallePorId.get(vendedorId) ?? null) : null
    return {
      vendedorId,
      ...identidad,
      detalle,
      estadoConversion: estadoConversion(detalle),
    }
  })

  return {
    responsablesDisponibles: responsablesCompletos,
    vendedores,
    tendenciaSemanal: responsablesCompletos ? tendenciaSemanalEquipo(responsables) : null,
  }
}

/**
 * El detalle del ranking cuando la fuente es la conversión MENSUAL ponderada.
 * `leads`/`clientes` se rellenan con divisor/cierres para satisfacer
 * DetalleRankeable (las columnas se re-rotulan «Recibidos»/«Cierres» en
 * pantalla); el resto viaja para el sheet: procedencia, referidos y el
 * arrastre que explica un % por encima de 100.
 */
export interface DetalleConversionMensual extends DetalleRankeable {
  numerador: number
  divisor: number
  estado: ResponsableConversionMensual['estado']
  cierres_de_arrastre: number
  procedencia: ResponsableConversionMensual['procedencia']
  referidos: ResponsableConversionMensual['referidos']
  /** El descuento por anulaciones de meses cerrados que su numerador ya trae restado. */
  ajuste: ResponsableConversionMensual['ajuste']
  /**
   * Operaciones de cartera del mes (renovaciones/upgrades acreditados): el
   * sumando del numerador que no viene de leads. Sin esto, «0 cierres» junto
   * a un % positivo se lee como contradicción (hallazgo de Grecia, 27/08).
   */
  operacionesCartera: number
  supervisorId: string | null
}

/**
 * Adapta el payload de `crm.conversion_mensual_fn` al ranking. MISMO
 * fail-closed que `adaptarConversionVendedores`: una colección ausente o
 * parcial marca TODO como indisponible — jamás ceros, jamás puestos con un
 * subconjunto.
 */
export function adaptarConversionMensual(
  datos: ConversionMensual | null | undefined,
  equipo: readonly ConversionEquipoVendedor[],
): ConversionVendedoresAdaptada<DetalleConversionMensual> {
  const responsables = datos?.responsables
  const publicable = lecturaCobertura(datos?.cobertura).mostrar
  const detallePorId = new Map(
    (responsables ?? []).map((fila) => [fila.vendedor_id, fila]),
  )
  const identidadPorId = new Map<string, {
    nombre: string
    supervisorId: string | null
    supervisorNombre: string
  }>()

  for (const integrante of equipo) {
    if (!integrante.vendedorId || identidadPorId.has(integrante.vendedorId)) continue
    identidadPorId.set(integrante.vendedorId, {
      nombre: integrante.nombre,
      supervisorId: integrante.supervisorId ?? null,
      supervisorNombre: integrante.supervisorNombre,
    })
  }
  for (const fila of responsables ?? []) {
    if (identidadPorId.has(fila.vendedor_id)) continue
    identidadPorId.set(fila.vendedor_id, {
      nombre: 'Analista no identificado',
      supervisorId: null,
      supervisorNombre: 'Equipo no disponible',
    })
  }

  const responsablesCompletos = publicable
    && responsables !== undefined
    && detallePorId.size === responsables.length
    && [...identidadPorId.keys()].every((vendedorId) => detallePorId.has(vendedorId))

  const vendedores = [...identidadPorId.entries()].map(([vendedorId, identidad]) => {
    const fila = responsablesCompletos ? (detallePorId.get(vendedorId) ?? null) : null
    const detalle: DetalleConversionMensual | null = fila === null ? null : {
      leads: fila.divisor,
      clientes: fila.cierres_no_referidos + fila.cierres_referidos,
      conversion_pct: fila.conversion_pct,
      numerador: fila.numerador,
      divisor: fila.divisor,
      estado: fila.estado,
      cierres_de_arrastre: fila.cierres_de_arrastre,
      procedencia: fila.procedencia,
      referidos: fila.referidos,
      ajuste: fila.ajuste,
      // `cartera` es obligatorio en el contrato vigente: llegar hasta aquí ya
      // prueba que cero es un dato explícito, no una ausencia maquillada.
      operacionesCartera: fila.cartera.conversiones_clientes,
      supervisorId: fila.supervisor_id,
    }
    return {
      vendedorId,
      ...identidad,
      detalle,
      estadoConversion: estadoConversion(detalle, fila?.estado),
    }
  })

  return {
    responsablesDisponibles: responsablesCompletos,
    vendedores,
    // El payload mensual no trae tendencia semanal: mide OTRA pregunta.
    tendenciaSemanal: null,
  }
}

/**
 * Conserva la identidad y el detalle auxiliar de la foto mensual, pero cambia
 * las columnas de conversión por el aporte de la fuente elegida en el mismo
 * período. La lectura filtrada ya contiene los aportes ponderados del núcleo;
 * aquí solo se prepara el modelo común que consumen Ranking y Rendimiento.
 */
export function adaptarConversionMensualPorFuente(
  datos: ConversionMensual | null | undefined,
  equipo: readonly ConversionEquipoVendedor[],
  fuente: FiltroFuentesConversion,
  lecturaFuente: AporteConversionRango | null | undefined,
  periodoRango?: { desde: string; hasta: string },
): ConversionVendedoresAdaptada<DetalleConversionMensual> {
  const mensual = adaptarConversionMensual(datos, equipo)
  // Un payload de rango que quede en caché nunca sustituye el total mensual.
  if (fuente == null && periodoRango == null) return mensual

  const mismoPeriodo = lecturaFuente != null && (periodoRango != null
    ? lecturaFuente.periodo.desde === periodoRango.desde && lecturaFuente.periodo.hasta === periodoRango.hasta
    : datos != null && !datos.cierre?.cerrado
      && lecturaFuente.periodo.desde === `${datos.periodo.mes}-01`
      && lecturaFuente.periodo.hasta.slice(0, 7) === datos.periodo.mes)
  const lecturaValida = mismoPeriodo && etiquetaFuentesConversion(lecturaFuente?.fuente ?? null) === etiquetaFuentesConversion(fuente)
    ? lecturaFuente : null
  const responsablesCompletos = mensual.responsablesDisponibles
    && lecturaValida != null
    && mensual.vendedores.every((fila) => lecturaValida.porVendedor.has(fila.vendedorId))

  return {
    responsablesDisponibles: responsablesCompletos,
    tendenciaSemanal: null,
    vendedores: mensual.vendedores.map((fila) => {
      const aporte = responsablesCompletos
        ? lecturaValida?.porVendedor.get(fila.vendedorId) ?? null
        : null
      if (fila.detalle == null || aporte == null) {
        return { ...fila, detalle: null, estadoConversion: 'indisponible' }
      }

      const estado = aporte.divisor > 0
        ? 'medible' as const
        : aporte.numerador > 0
          ? fuente === 'referido' ? 'solo_referidos' as const : 'solo_arrastre' as const
          : 'sin_actividad' as const
      const detalle: DetalleConversionMensual = {
        ...fila.detalle,
        leads: aporte.divisor,
        clientes: aporte.cierres,
        conversion_pct: aporte.porcentaje,
        numerador: aporte.numerador,
        divisor: aporte.divisor,
        estado,
        operacionesCartera: aporte.operaciones,
      }

      return {
        ...fila,
        detalle,
        estadoConversion: estadoConversion(detalle, estado),
      }
    }),
  }
}

export function clasificarRankingConversion<D extends DetalleRankeable>(
  vendedores: readonly ConversionVendedorAdaptada<D>[],
): RankingConversionVendedores<D> {
  // Tres cubos y CINCO estados: los nuevos viven DENTRO de los cubos de
  // siempre a propósito — un cubo nuevo haría desaparecer a esa gente de toda
  // pantalla que concatene los tres (el modo de fallo que ya costó caro: verde
  // en 1.600 tests y nadie en pantalla). El rótulo distinto lo pone la pantalla
  // leyendo `estadoConversion`, no la estructura.
  //   conPuesto  ← comparable + solo_arrastre (cerró: compite; sin %, al fondo)
  //   sinMuestra ← sin_muestra + solo_referidos (sin divisor; rótulo propio)
  //   indisponibles ← fail-closed del cliente
  const conPuesto = vendedores
    .filter((fila): fila is ConversionVendedorConDetalle<D> => (
      (fila.estadoConversion === 'comparable' || fila.estadoConversion === 'solo_arrastre')
      && fila.detalle != null
    ))
    .sort((a, b) => {
      const detalleA = a.detalle
      const detalleB = b.detalle
      // `?? -1` deja los % en NULL (solo_arrastre) al fondo del ranking: ya no
      // es código muerto, es la regla que impide que un null encabece nada.
      // El desempate baja a numerador y luego divisor (payload mensual); los
      // payloads viejos no los traen y caen a clientes/leads, su orden de
      // siempre.
      return (detalleB?.conversion_pct ?? -1) - (detalleA?.conversion_pct ?? -1)
        || (detalleB?.numerador ?? detalleB?.clientes ?? -1)
          - (detalleA?.numerador ?? detalleA?.clientes ?? -1)
        || (detalleB?.divisor ?? detalleB?.leads ?? -1)
          - (detalleA?.divisor ?? detalleA?.leads ?? -1)
        || porNombre(a, b)
    })
  const sinMuestra = vendedores
    .filter((fila): fila is ConversionVendedorConDetalle<D> => (
      (fila.estadoConversion === 'sin_muestra' || fila.estadoConversion === 'solo_referidos')
      && fila.detalle != null
    ))
    .sort(porNombre)
  const indisponibles = vendedores
    .filter((fila) => fila.estadoConversion === 'indisponible')
    .sort(porNombre)

  return { conPuesto, sinMuestra, indisponibles }
}

export interface CapitalTotalVendedor {
  vendedor: IdentidadVendedorRanking
  capitalPen: number | null
  capitalUsd: number | null
  /** Categorías del mismo cumplimiento; bruto para conciliar con los orígenes. */
  cartera?: { categoria: 'renovacion' | 'upgrade'; pen: number; usd: number }[] | null
  /** Descuentos ya absorbidos por la foto; el capital mostrado arriba es neto. */
  capitalAjustePen: number
  capitalAjusteUsd: number
  contratosAjuste: number
  /** PEN + USD convertido al TC; sin TC, solo PEN (el USD se rotula aparte). */
  capitalTotal: number | null
  /** Split crudo de la meta (0 si no hay meta): permite rotular el recorte sin TC. */
  metaPen: number
  metaUsd: number
  metaCapital: number | null
  avance: number | null
  estadoCapital: EstadoCapitalVendedor
}

export type CapitalTotalConPuesto = CapitalTotalVendedor & {
  capitalPen: number
  capitalUsd: number
  capitalTotal: number
  metaCapital: number
  avance: number
  estadoCapital: 'comparable'
}

export type CapitalTotalSinMeta = CapitalTotalVendedor & {
  capitalPen: number
  capitalUsd: number
  capitalTotal: number
  metaCapital: null
  avance: null
  estadoCapital: 'sin_meta'
}

export interface RankingCapitalTotalVendedores {
  conPuesto: CapitalTotalConPuesto[]
  sinMeta: CapitalTotalSinMeta[]
  indisponibles: CapitalTotalVendedor[]
  /** TC realmente aplicado; null = el USD quedó FUERA del total (jamás se inventa tasa). */
  tc: number | null
}

/**
 * Ranking por capital TOTAL en soles: PEN + USD convertido al TC del BCRP que
 * resuelve el servidor (edge crm-tipo-cambio). Es la única conversión admitida
 * por la regla PEN≠USD (decisión 2026-07-17: la meta se mide en soles y el USD
 * cuenta convertido, no sumado a ciegas). Sin TC el total degrada a solo-PEN y
 * el USD se muestra aparte — mismo fail-closed que la meta del analista.
 * La meta también unifica (objetivo USD legado convertido; hoy las metas están
 * normalizadas a PEN, así que suele ser solo el objetivo en soles).
 */
export function clasificarRankingCapitalTotal(
  vendedores: readonly (IdentidadVendedorRanking | ConversionEquipoVendedor)[],
  metas: ObjetivosPorVendedor,
  cumplimientos: Record<string, CumplimientoVendedor>,
  tc: number | null,
): RankingCapitalTotalVendedores {
  // La política de conversión vive en lib/capital-unificado (fuente única): la
  // comparten este ranking y las filas de equipo desde la decisión #10.
  const tcValido = tcAplicable(tc)

  // El mismo clasificador conserva el roster visible como frontera de alcance.
  // Incluso un arreglo vacío es una población autoritativa: metas y
  // cumplimiento aportan MEDIDAS, pero no pueden reintroducir una baja ni
  // inventar una identidad cuando el equipo vigente o la foto histórica están
  // explícitamente vacíos.
  const identidadPorId = new Map<string, IdentidadVendedorRanking>()
  for (const vendedor of vendedores) {
    if (!vendedor.vendedorId || identidadPorId.has(vendedor.vendedorId)) continue
    identidadPorId.set(vendedor.vendedorId, {
      vendedorId: vendedor.vendedorId,
      nombre: vendedor.nombre,
      supervisorNombre: vendedor.supervisorNombre,
    })
  }
  const filas = [...identidadPorId.values()].map<CapitalTotalVendedor>((vendedor) => {
    // Un cumplimiento SIN detalles no es «S/ 0 confirmado»: es un payload que la
    // frontera RPC no debería producir — se degrada a indisponible, no a puesto
    // con cero (hallazgo Codex: el tipo público no garantiza la matriz completa).
    const crudo = cumplimientos[vendedor.vendedorId]
    const cumplimiento = crudo != null && crudo.detalles.length > 0 ? crudo : undefined
    const capitalPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
    const capitalUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
    const cartera = cumplimiento ? (['renovacion', 'upgrade'] as const).map((categoria) => ({
      categoria,
      pen: cumplimiento.detalles.filter((d) => d.categoria === categoria && d.moneda === 'PEN')
        .reduce((suma, d) => suma + d.capitalReal + (d.capitalAjuste ?? 0), 0),
      usd: cumplimiento.detalles.filter((d) => d.categoria === categoria && d.moneda === 'USD')
        .reduce((suma, d) => suma + d.capitalReal + (d.capitalAjuste ?? 0), 0),
    })) : null
    const capitalAjustePen = cumplimiento?.ajuste?.aplicadoPen ?? 0
    const capitalAjusteUsd = cumplimiento?.ajuste?.aplicadoUsd ?? 0
    const contratosAjuste = cumplimiento?.ajuste?.contratosAplicados ?? 0
    const capitalTotal = totalEnSoles(capitalPen, capitalUsd, tcValido).total
    const meta = metas[vendedor.vendedorId]
    const metaPen = meta ? capitalObjetivo(meta, 'PEN') : 0
    const metaUsd = meta ? capitalObjetivo(meta, 'USD') : 0
    const objetivo = meta ? totalEnSoles(metaPen, metaUsd, tcValido).total : null
    const metaCapital = objetivo != null && objetivo > 0 ? objetivo : null
    const estadoCapital: EstadoCapitalVendedor = cumplimiento == null
      ? 'indisponible'
      : metaCapital == null
        ? 'sin_meta'
        : 'comparable'

    return {
      vendedor,
      capitalPen,
      capitalUsd,
      cartera,
      capitalAjustePen,
      capitalAjusteUsd,
      contratosAjuste,
      capitalTotal,
      metaPen,
      metaUsd,
      metaCapital,
      avance: estadoCapital === 'comparable' && capitalTotal != null && metaCapital != null
        ? Math.max(0, (capitalTotal / metaCapital) * 100)
        : null,
      estadoCapital,
    }
  })

  const conPuesto = filas
    .filter((fila): fila is CapitalTotalConPuesto => (
      fila.estadoCapital === 'comparable'
      && fila.capitalTotal != null
      && fila.metaCapital != null
      && fila.avance != null
    ))
    .sort((a, b) => (b.avance ?? -1) - (a.avance ?? -1)
      || (b.capitalTotal ?? -1) - (a.capitalTotal ?? -1)
      || porNombre(a.vendedor, b.vendedor))
  const sinMeta = filas
    .filter((fila): fila is CapitalTotalSinMeta => (
      fila.estadoCapital === 'sin_meta'
      && fila.capitalTotal != null
      && fila.metaCapital == null
      && fila.avance == null
    ))
    .sort((a, b) => (b.capitalTotal ?? -1) - (a.capitalTotal ?? -1)
      || porNombre(a.vendedor, b.vendedor))
  const indisponibles = filas
    .filter((fila) => fila.estadoCapital === 'indisponible')
    .sort((a, b) => porNombre(a.vendedor, b.vendedor))

  return { conPuesto, sinMeta, indisponibles, tc: tcValido }
}
