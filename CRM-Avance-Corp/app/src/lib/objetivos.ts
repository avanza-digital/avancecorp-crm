import * as v from 'valibot'
import { fechaLima } from './agenda-derivada'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  FechaSchema,
  NumeroRpcSchema,
  TextoNoVacioSchema,
  UuidSchema,
} from './esquemas-rpc'
import type { ConfiguracionMetas, DetalleMeta, MetaVendedorConfig } from './metas-versionadas'
import { CATEGORIAS_PRODUCTO, MONEDAS_PRODUCTO } from './productos-inversion'

export type CategoriaMeta = DetalleMeta['categoria']
export type MonedaMeta = DetalleMeta['moneda']

export interface ObjetivoDetalle {
  categoria: CategoriaMeta
  moneda: MonedaMeta
  capitalObjetivo: number
  contratosObjetivo: number
}

/** Meta mensual. La moneda y la categoría nunca se pierden al agregar. */
export interface ObjetivoComercial {
  conversionObjetivo: number
  detalles: ObjetivoDetalle[]
}

export interface ObjetivoVendedor extends ObjetivoComercial {
  vendedorId: string
  nombre: string
  supervisorId: string
  supervisorNombre: string
}

export type ObjetivosPorVendedor = Record<string, ObjetivoVendedor>

/** Supervisor y empresa siempre son derivados de las metas individuales. */
export interface ObjetivosJerarquicos {
  periodo: string
  revision: number
  publicadaEn: string | null
  vendedor: ObjetivoComercial
  supervisor: ObjetivoComercial
  gerencia: ObjetivoComercial
  porVendedor: ObjetivosPorVendedor
}

/** Nombre histórico conservado para consumidores de lectura del store. */
export type ObjetivosPorRol = ObjetivosJerarquicos

const CLAVES_DIMENSION = CATEGORIAS_PRODUCTO.flatMap((categoria) =>
  MONEDAS_PRODUCTO.map((moneda) => `${categoria}:${moneda}` as const),
)

function detallesCero(): ObjetivoDetalle[] {
  return CATEGORIAS_PRODUCTO.flatMap((categoria) =>
    MONEDAS_PRODUCTO.map((moneda) => ({
      categoria,
      moneda,
      capitalObjetivo: 0,
      contratosObjetivo: 0,
    })),
  )
}

function objetivoCero(): ObjetivoComercial {
  return { conversionObjetivo: 0, detalles: detallesCero() }
}

export function objetivosCero(periodo = periodoLima(Date.now())): ObjetivosJerarquicos {
  return {
    periodo,
    revision: 0,
    publicadaEn: null,
    vendedor: objetivoCero(),
    supervisor: objetivoCero(),
    gerencia: objetivoCero(),
    porVendedor: {},
  }
}

function objetivoDesdeVendedor(meta: MetaVendedorConfig): ObjetivoVendedor {
  return {
    vendedorId: meta.vendedor_id,
    nombre: meta.nombre,
    supervisorId: meta.supervisor_id,
    supervisorNombre: meta.supervisor_nombre,
    conversionObjetivo: meta.conversion_objetivo,
    detalles: meta.detalles.map((detalle) => ({
      categoria: detalle.categoria,
      moneda: detalle.moneda,
      capitalObjetivo: detalle.capital_objetivo,
      contratosObjetivo: detalle.contratos_objetivo,
    })),
  }
}

/** Suma capital/contratos por dimensión; los porcentajes definidos se promedian. */
export function agregarObjetivos(items: Iterable<ObjetivoComercial>): ObjetivoComercial {
  const metas = Array.from(items)
  if (metas.length === 0) return objetivoCero()

  const acumulado = new Map(CLAVES_DIMENSION.map((clave) => [clave, {
    capitalObjetivo: 0,
    contratosObjetivo: 0,
  }]))
  for (const meta of metas) {
    for (const detalle of meta.detalles) {
      const clave = `${detalle.categoria}:${detalle.moneda}` as const
      const destino = acumulado.get(clave)
      if (!destino) continue
      destino.capitalObjetivo += detalle.capitalObjetivo
      destino.contratosObjetivo += detalle.contratosObjetivo
    }
  }

  const conversiones = metas
    .map((meta) => meta.conversionObjetivo)
    .filter((valor) => valor > 0)
  const conversionObjetivo = conversiones.length === 0
    ? 0
    : Math.round((conversiones.reduce((total, valor) => total + valor, 0) / conversiones.length) * 100) / 100

  return {
    conversionObjetivo,
    detalles: detallesCero().map((detalle) => {
      const valor = acumulado.get(`${detalle.categoria}:${detalle.moneda}`)
      return { ...detalle, ...(valor ?? {}) }
    }),
  }
}

export function objetivosDesdeConfiguracion(
  configuracion: ConfiguracionMetas,
  actorId?: string | null,
): ObjetivosJerarquicos {
  const porVendedor: ObjetivosPorVendedor = Object.fromEntries(
    configuracion.vendedores.map((meta) => [meta.vendedor_id, objetivoDesdeVendedor(meta)]),
  )
  const filas = Object.values(porVendedor)
  const propia = actorId ? porVendedor[actorId] : undefined
  return {
    periodo: configuracion.periodo,
    revision: configuracion.revision,
    publicadaEn: configuracion.publicada_en,
    vendedor: propia ?? objetivoCero(),
    supervisor: agregarObjetivos(filas.filter((meta) => meta.supervisorId === actorId)),
    gerencia: agregarObjetivos(filas),
    porVendedor,
  }
}

export function capitalObjetivo(
  meta: ObjetivoComercial,
  moneda: MonedaMeta,
  categoria?: CategoriaMeta,
): number {
  return meta.detalles.reduce((total, detalle) => (
    detalle.moneda === moneda && (categoria == null || detalle.categoria === categoria)
      ? total + detalle.capitalObjetivo
      : total
  ), 0)
}

export function contratosObjetivo(
  meta: ObjetivoComercial,
  moneda: MonedaMeta,
  categoria?: CategoriaMeta,
): number {
  return meta.detalles.reduce((total, detalle) => (
    detalle.moneda === moneda && (categoria == null || detalle.categoria === categoria)
      ? total + detalle.contratosObjetivo
      : total
  ), 0)
}

/** Cero significa «sin meta publicada»; nunca inventamos un porcentaje. */
export function metaConversionAplicable(
  conversionGuardada: number,
  errorCarga = false,
): number | null {
  if (errorCarga || conversionGuardada <= 0) return null
  return conversionGuardada
}

// ── Cumplimiento autoritativo: contratos confirmados + leads resueltos ──

const DetalleCumplimientoSchema = v.strictObject({
  categoria: v.picklist(CATEGORIAS_PRODUCTO),
  moneda: v.picklist(MONEDAS_PRODUCTO),
  capital_objetivo: v.pipe(NumeroRpcSchema, v.minValue(0)),
  capital_real: v.pipe(NumeroRpcSchema, v.minValue(0)),
  capital_cumplimiento_pct: v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0))),
  contratos_objetivo: EnteroNoNegativoRpcSchema,
  contratos_real: EnteroNoNegativoRpcSchema,
  contratos_cumplimiento_pct: v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0))),
  // Lo descontado en ESTA casilla (categoría × moneda) al sellar el mes. Solo
  // viaja en la FOTO de un mes cerrado, y existe para que la foto pueda explicar
  // por qué `capital_real` no es el bruto: sumando las dos se recupera.
  //
  // ⚠️ Estas dos son las que NO encontré leyendo la migración —las encontró el
  // fixture generado ejecutando (`cumplimiento-cierre-de-mes.test.ts`)—, y solo
  // aparecen en una rama que ningún usuario ejercerá hasta el 10/09/2026. Sin
  // ellas, la pantalla de metas se habría vuelto a apagar ese día.
  capital_ajuste: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0))),
  contratos_ajuste: v.optional(EnteroNoNegativoRpcSchema),
})

const DetallesCumplimientoSchema = v.pipe(
  v.array(DetalleCumplimientoSchema),
  v.length(6),
  v.check((detalles) => {
    const claves = new Set(detalles.map((detalle) => `${detalle.categoria}:${detalle.moneda}`))
    return claves.size === CLAVES_DIMENSION.length
      && CLAVES_DIMENSION.every((clave) => claves.has(clave))
  }, 'El cumplimiento debe contener exactamente categoría × moneda'),
)

// ── El cierre de mes (migración 20260815003742) ───────────────────────────────
//
// 🔴 ESTAS DOS CLAVES APAGARON LA PANTALLA DE METAS EN PRODUCCIÓN (2026-08-15).
// El servidor se desplegó primero y empezó a mandar `cierre` (arriba) y `ajuste`
// (por analista); `CumplimientoMetasSchema` es fail-closed, así que rechazó el
// payload ENTERO y los tres roles se quedaron sin cumplimiento a la vez, con un
// «Reintentar» que no podía funcionar. La regla que lo habría evitado ya estaba
// escrita: **clave nueva en la RESPUESTA de una RPC → el FRONT va primero**.
// Aquí fuimos al revés. La lección no es «faltaba una clave»: es que nada
// comparaba este contrato contra lo que la función devuelve de verdad, y por eso
// los fixtures de `cumplimiento-post-migracion-b.test.ts` salen ahora de EJECUTAR
// la función, nunca de escribirlos a mano.

/**
 * ¿El mes ya está sellado? Viaja en las DOS ramas del servidor: `{cerrado:false}`
 * en el mes vivo y, en la foto de un mes sellado, con la fecha y si lo cerró el
 * reloj o una persona.
 *
 * `cerrado_en`/`automatico` van `optional` y NO se exige que aparezcan cuando
 * `cerrado` es true, a propósito: un invariante de más aquí vuelve a ser una
 * pantalla apagada, y lo único que se pierde si faltaran es la fecha del rótulo.
 */
export const CierreDelMesSchema = v.strictObject({
  cerrado: v.boolean(),
  cerrado_en: v.optional(FechaHoraSchema),
  automatico: v.optional(v.boolean()),
})

export type CierreDelMes = v.InferOutput<typeof CierreDelMesSchema>

/**
 * Lo que se le descuenta al analista por anulaciones de meses ya pagados.
 *
 * En el mes VIVO solo viaja `pendiente` (lo que se le va a descontar). En la
 * FOTO de un mes sellado, `pendiente` es siempre 0 —lo que cabía se descontó al
 * sellar— y llegan además los tres `aplicado*`, que son lo que hace auditable la
 * foto: sumándolos al numerador se recupera el bruto.
 */
const AjusteVendedorSchema = v.strictObject({
  pendiente: v.pipe(NumeroRpcSchema, v.minValue(0)),
  aplicado: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0))),
  aplicado_pen: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0))),
  aplicado_usd: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0))),
})

const CumplimientoVendedorSchema = v.strictObject({
  vendedor_id: UuidSchema,
  nombre: TextoNoVacioSchema,
  supervisor_id: UuidSchema,
  supervisor_nombre: TextoNoVacioSchema,
  conversion_objetivo: v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(100)),
  // SIN maxValue(100), a propósito y con historia: la conversión mensual
  // ponderada supera el 100 % POR DISEÑO (cierres de arrastre + referidos que
  // suman arriba y no abajo). Este cap vivía dentro de un strictObject
  // fail-closed: el primer analista por encima de 100 tras la migración B habría
  // dejado SIN METAS a los tres roles a la vez. La META (arriba) sí conserva su
  // techo: un objetivo se pacta ≤ 100; un resultado no tiene techo.
  conversion_real: v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0))),
  convertidos: EnteroNoNegativoRpcSchema,
  resueltos: EnteroNoNegativoRpcSchema,
  // Las tres llegan con la migración B (cumplimiento sobre la definición
  // ponderada). `v.optional` es OBLIGATORIO mientras el servidor viejo viva:
  // un strictObject también falla por clave FALTANTE, y entre este release y la
  // B el payload no las trae.
  numerador: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0))),
  cierres_no_referidos: v.optional(EnteroNoNegativoRpcSchema),
  cierres_referidos: v.optional(EnteroNoNegativoRpcSchema),
  // Llega con el cierre de mes. `optional` por la misma razón que las tres de
  // arriba —y por la VUELTA ATRÁS de la migración: si el servidor volviera a la
  // versión anterior, la clave desaparece y un strictObject falla también por
  // clave de MENOS.
  ajuste: v.optional(AjusteVendedorSchema),
  detalles: DetallesCumplimientoSchema,
})

// Produccion empresarial que existe y debe cuadrar en Gerencia, pero cuyo
// responsable no puede competir como analista (p. ej. un supervisor). Es una
// clave opcional para que este bundle pueda salir antes que la migracion.
const ConversionFueraRankingSchema = v.strictObject({
  divisor: EnteroNoNegativoRpcSchema,
  divisor_aproximado: EnteroNoNegativoRpcSchema,
  divisor_por_motivo: v.record(v.string(), EnteroNoNegativoRpcSchema),
  cierres_no_referidos: EnteroNoNegativoRpcSchema,
  cierres_referidos: EnteroNoNegativoRpcSchema,
  cierres_de_arrastre: EnteroNoNegativoRpcSchema,
  referidos_recibidos: EnteroNoNegativoRpcSchema,
  numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
})

const CarteraFueraRankingSchema = v.strictObject({
  conversiones_clientes: EnteroNoNegativoRpcSchema,
  conversiones_renovacion: EnteroNoNegativoRpcSchema,
  conversiones_upgrade: EnteroNoNegativoRpcSchema,
  operaciones_renovacion: EnteroNoNegativoRpcSchema,
  operaciones_upgrade: EnteroNoNegativoRpcSchema,
  capital_renovado_pen: v.pipe(NumeroRpcSchema, v.minValue(0)),
  capital_renovado_usd: v.pipe(NumeroRpcSchema, v.minValue(0)),
  capital_adicional_pen: v.pipe(NumeroRpcSchema, v.minValue(0)),
  capital_adicional_usd: v.pipe(NumeroRpcSchema, v.minValue(0)),
  renovaciones_sin_desglose: EnteroNoNegativoRpcSchema,
})

const ProduccionFueraRankingSchema = v.strictObject({
  persona_id: UuidSchema,
  nombre: TextoNoVacioSchema,
  rol_crm: v.picklist([
    'vendedor',
    'supervisor',
    'gerencia',
    'coordinador',
    'directorio',
    'fuera_equipo',
  ]),
  motivo: v.picklist([
    'analista_sin_meta',
    'analista_sin_supervisor',
    'supervisor',
    'gerencia',
    'fuera_estructura',
  ]),
  conversion: v.nullable(ConversionFueraRankingSchema),
  detalles: DetallesCumplimientoSchema,
  cartera: CarteraFueraRankingSchema,
})

export const CumplimientoMetasSchema = v.strictObject({
  version: v.literal(1),
  periodo: FechaSchema,
  revision: EnteroNoNegativoRpcSchema,
  publicada_en: v.nullable(FechaHoraSchema),
  fuentes_reales: v.strictObject({
    capital_y_contratos: v.literal('contratos_confirmados'),
    // Tolerar los DOS literales es lo que hace barata la reversión de la
    // migración B: el bundle acepta el servidor viejo (`leads_resueltos`) y el
    // nuevo (`leads_recibidos_ponderado`) sin redeploy.
    conversion: v.picklist(['leads_resueltos', 'leads_recibidos_ponderado']),
  }),
  // Llega con la migración B; optional por la misma ventana que arriba.
  ponderacion_referido: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(1))),
  // Llega con el cierre de mes (20260815003742), en las dos ramas.
  cierre: v.optional(CierreDelMesSchema),
  vendedores: v.array(CumplimientoVendedorSchema),
  fuera_ranking: v.optional(v.array(ProduccionFueraRankingSchema)),
})

export type CumplimientoMetasRpc = v.InferOutput<typeof CumplimientoMetasSchema>

export interface CumplimientoDetalle extends ObjetivoDetalle {
  capitalReal: number
  capitalCumplimientoPct: number | null
  contratosReal: number
  contratosCumplimientoPct: number | null
  /** Descuento ya aplicado al sellar el mes; `capitalReal` ya llega neto. */
  capitalAjuste?: number
  /** Contratos ya descontados al sellar el mes; `contratosReal` ya llega neto. */
  contratosAjuste?: number
}

export interface AjusteCumplimiento {
  /** Deuda de conversión aún pendiente; no se descuenta del mes abierto. */
  pendiente: number
  /** Numerador de conversión descontado al cerrar la foto. */
  aplicado: number
  /** Capital PEN descontado; permite recuperar el bruto desde la cifra neta. */
  aplicadoPen: number
  /** Capital USD descontado; permite recuperar el bruto desde la cifra neta. */
  aplicadoUsd: number
  /** Contratos descontados, consolidados desde las seis casillas del detalle. */
  contratosAplicados: number
}

export interface CumplimientoComercial {
  conversionObjetivo: number
  conversionReal: number | null
  convertidos: number
  resueltos: number
  /**
   * Cierres PONDERADOS (no referidos al 100 % + referidos al peso vigente).
   * Hasta la migración B el servidor no lo manda y vale `convertidos` (el
   * fallback de cumplimientoDesdeVendedor): con eso los agregados de hoy salen
   * idénticos a los de siempre, y el día que B entre, cambian solos de fórmula.
   */
  numerador: number
  /**
   * Ajustes del cierre que explican por qué los reales son netos. Es opcional
   * durante la compatibilidad con payloads anteriores al cierre de mes.
   */
  ajuste?: AjusteCumplimiento
  detalles: CumplimientoDetalle[]
}

export interface CumplimientoVendedor extends CumplimientoComercial {
  vendedorId: string
  nombre: string
  supervisorId: string
  supervisorNombre: string
}

export interface ProduccionFueraRanking {
  personaId: string
  nombre: string
  rolCrm:
    | 'vendedor'
    | 'supervisor'
    | 'gerencia'
    | 'coordinador'
    | 'directorio'
    | 'fuera_equipo'
  motivo:
    | 'analista_sin_meta'
    | 'analista_sin_supervisor'
    | 'supervisor'
    | 'gerencia'
    | 'fuera_estructura'
  conversion: {
    divisor: number
    divisorAproximado: number
    divisorPorMotivo: Record<string, number>
    cierresNoReferidos: number
    cierresReferidos: number
    cierresDeArrastre: number
    referidosRecibidos: number
    numerador: number
  } | null
  detalles: CumplimientoDetalle[]
  cartera: {
    conversionesClientes: number
    conversionesRenovacion: number
    conversionesUpgrade: number
    operacionesRenovacion: number
    operacionesUpgrade: number
    capitalRenovadoPen: number
    capitalRenovadoUsd: number
    capitalAdicionalPen: number
    capitalAdicionalUsd: number
    renovacionesSinDesglose: number
  }
}

export interface FuentesRealesCumplimientoMetas {
  capitalYContratos: 'contratos_confirmados'
  /** Los dos mundos de la ventana de despliegue (ver el picklist del esquema). */
  conversion: 'leads_resueltos' | 'leads_recibidos_ponderado'
}

export interface CumplimientoMetasJerarquico {
  periodo: string
  revision: number
  publicadaEn: string | null
  fuentesReales: FuentesRealesCumplimientoMetas
  /**
   * El sello del mes mirado: si `cerrado`, estas cifras son la FOTO definitiva
   * y ya no cambian. `null` solo con un servidor anterior al cierre de mes.
   */
  cierre: CierreDelMes | null
  vendedor: CumplimientoComercial | null
  // Los agregados NO llevan conversión (F3.3): la del supervisor/gerencia la
  // sirve el servidor; aquí solo viajan metas y reales de capital/contratos.
  supervisor: CumplimientoAgregado | null
  gerencia: CumplimientoAgregado | null
  porVendedor: Record<string, CumplimientoVendedor>
  /** Produccion identificada que cuadra en empresa sin generar un puesto. */
  fueraRanking: ProduccionFueraRanking[]
}

function cumplimientoDesdeVendedor(
  fila: CumplimientoMetasRpc['vendedores'][number],
): CumplimientoVendedor {
  const detalles = fila.detalles.map((detalle) => ({
    categoria: detalle.categoria,
    moneda: detalle.moneda,
    capitalObjetivo: detalle.capital_objetivo,
    capitalReal: detalle.capital_real,
    capitalCumplimientoPct: detalle.capital_cumplimiento_pct,
    contratosObjetivo: detalle.contratos_objetivo,
    contratosReal: detalle.contratos_real,
    contratosCumplimientoPct: detalle.contratos_cumplimiento_pct,
    capitalAjuste: detalle.capital_ajuste ?? 0,
    contratosAjuste: detalle.contratos_ajuste ?? 0,
  }))
  const capitalAjustePen = detalles.reduce((total, detalle) => (
    detalle.moneda === 'PEN' ? total + detalle.capitalAjuste : total
  ), 0)
  const capitalAjusteUsd = detalles.reduce((total, detalle) => (
    detalle.moneda === 'USD' ? total + detalle.capitalAjuste : total
  ), 0)
  const contratosAplicados = detalles.reduce(
    (total, detalle) => total + detalle.contratosAjuste,
    0,
  )

  return {
    vendedorId: fila.vendedor_id,
    nombre: fila.nombre,
    supervisorId: fila.supervisor_id,
    supervisorNombre: fila.supervisor_nombre,
    conversionObjetivo: fila.conversion_objetivo,
    conversionReal: fila.conversion_real,
    convertidos: fila.convertidos,
    resueltos: fila.resueltos,
    // Fallback de transición: el servidor pre-B no manda `numerador`, y con
    // `?? convertidos` la suma de agregados de hoy da EXACTAMENTE lo de siempre
    // (sin él, un solo undefined convertiría el agregado en NaN y el NaN pasa
    // en silencio hasta la pantalla).
    numerador: fila.numerador ?? fila.convertidos,
    ...(fila.ajuste != null || capitalAjustePen > 0 || capitalAjusteUsd > 0 || contratosAplicados > 0
      ? {
          ajuste: {
            pendiente: fila.ajuste?.pendiente ?? 0,
            aplicado: fila.ajuste?.aplicado ?? 0,
            aplicadoPen: fila.ajuste?.aplicado_pen ?? capitalAjustePen,
            aplicadoUsd: fila.ajuste?.aplicado_usd ?? capitalAjusteUsd,
            contratosAplicados,
          },
        }
      : {}),
    detalles,
  }
}

/**
 * Agregado de cumplimientos SIN aritmética de conversión (F3.3 de «Conversión
 * única»): la conversión del supervisor/gerencia la SIRVE el servidor
 * (conversion_mensual_fn y los motores F2) — el agregado del navegador quedó
 * sin pintor desde el 13/08 y recalcularla aquí era otra aritmética paralela.
 * Se conservan metas y `reales` de capital/contratos: alimentan las barras de
 * capital de cinco pantallas.
 */
export type CumplimientoAgregado = Omit<
  CumplimientoComercial,
  'conversionReal' | 'convertidos' | 'resueltos' | 'numerador'
>

export function agregarCumplimientos(
  items: Iterable<CumplimientoComercial>,
): CumplimientoAgregado | null {
  const filas = Array.from(items)
  if (filas.length === 0) return null

  const metas = agregarObjetivos(filas)
  const reales = new Map(CLAVES_DIMENSION.map((clave) => [clave, {
    capitalReal: 0,
    contratosReal: 0,
    capitalAjuste: 0,
    contratosAjuste: 0,
  }]))
  const tieneAjuste = filas.some((fila) => fila.ajuste != null)
  const ajuste = filas.reduce<AjusteCumplimiento>((total, fila) => ({
    pendiente: total.pendiente + (fila.ajuste?.pendiente ?? 0),
    aplicado: total.aplicado + (fila.ajuste?.aplicado ?? 0),
    aplicadoPen: total.aplicadoPen + (fila.ajuste?.aplicadoPen ?? 0),
    aplicadoUsd: total.aplicadoUsd + (fila.ajuste?.aplicadoUsd ?? 0),
    contratosAplicados: total.contratosAplicados + (fila.ajuste?.contratosAplicados ?? 0),
  }), {
    pendiente: 0,
    aplicado: 0,
    aplicadoPen: 0,
    aplicadoUsd: 0,
    contratosAplicados: 0,
  })
  for (const fila of filas) {
    for (const detalle of fila.detalles) {
      const destino = reales.get(`${detalle.categoria}:${detalle.moneda}`)
      if (!destino) continue
      destino.capitalReal += detalle.capitalReal
      destino.contratosReal += detalle.contratosReal
      destino.capitalAjuste += detalle.capitalAjuste ?? 0
      destino.contratosAjuste += detalle.contratosAjuste ?? 0
    }
  }

  return {
    conversionObjetivo: metas.conversionObjetivo,
    ...(tieneAjuste ? { ajuste } : {}),
    detalles: metas.detalles.map((meta) => {
      const real = reales.get(`${meta.categoria}:${meta.moneda}`) ?? {
        capitalReal: 0,
        contratosReal: 0,
        capitalAjuste: 0,
        contratosAjuste: 0,
      }
      return {
        ...meta,
        ...real,
        capitalCumplimientoPct: meta.capitalObjetivo > 0
          ? Math.round((10_000 * real.capitalReal) / meta.capitalObjetivo) / 100
          : null,
        contratosCumplimientoPct: meta.contratosObjetivo > 0
          ? Math.round((10_000 * real.contratosReal) / meta.contratosObjetivo) / 100
          : null,
      }
    }),
  }
}

/**
 * La meta contra la que se mide el mes.
 *
 * `objetivos` describe el roster VIVO (lo que devuelve `configuracion_metas_fn`,
 * jerarquía de hoy) y sirve para EDITAR. El cumplimiento, en cambio, sale del
 * snapshot `crm.metas_vendedor` congelado al publicar. Mezclarlos descuadra el
 * porcentaje en cuanto alguien se mueve a mitad de mes:
 *
 *   · si un analista se da de baja, su meta desaparece del denominador pero su
 *     producción sigue en el numerador → el avance se INFLA;
 *   · si se reasigna de un supervisor a otro, el que lo recibe hereda la meta
 *     sin la producción → el avance se HUNDE.
 *
 * Decisión de negocio (Miguel, 2026-08-10): «si un analista se va, el progreso
 * hasta la fecha debe quedar ahí plasmado y contar para el supervisor al que
 * pertenecía». Eso es exactamente la FOTO: meta y cierres del mismo snapshot,
 * que además es lo que hace auditable un mes ya cerrado.
 *
 * Funciona porque `CumplimientoDetalle extends ObjetivoDetalle`: el cumplimiento
 * ya lleva dentro su propia meta, construida en `agregarCumplimientos` a partir
 * de las MISMAS filas que su producción.
 */
export function metaVigente(
  objetivo: ObjetivoComercial,
  cumplimiento: CumplimientoAgregado | null,
): ObjetivoComercial {
  return cumplimiento ?? objetivo
}

export function cumplimientoDesdeRpc(
  respuesta: CumplimientoMetasRpc,
  actorId?: string | null,
): CumplimientoMetasJerarquico {
  const porVendedor = Object.fromEntries(
    respuesta.vendedores.map((fila) => [fila.vendedor_id, cumplimientoDesdeVendedor(fila)]),
  )
  const filas = Object.values(porVendedor)
  const fueraRanking: ProduccionFueraRanking[] = (respuesta.fuera_ranking ?? []).map((fila) => ({
    personaId: fila.persona_id,
    nombre: fila.nombre,
    rolCrm: fila.rol_crm,
    motivo: fila.motivo,
    conversion: fila.conversion == null ? null : {
      divisor: fila.conversion.divisor,
      divisorAproximado: fila.conversion.divisor_aproximado,
      divisorPorMotivo: fila.conversion.divisor_por_motivo,
      cierresNoReferidos: fila.conversion.cierres_no_referidos,
      cierresReferidos: fila.conversion.cierres_referidos,
      cierresDeArrastre: fila.conversion.cierres_de_arrastre,
      referidosRecibidos: fila.conversion.referidos_recibidos,
      numerador: fila.conversion.numerador,
    },
    detalles: fila.detalles.map((detalle) => ({
      categoria: detalle.categoria,
      moneda: detalle.moneda,
      capitalObjetivo: detalle.capital_objetivo,
      capitalReal: detalle.capital_real,
      capitalCumplimientoPct: detalle.capital_cumplimiento_pct,
      contratosObjetivo: detalle.contratos_objetivo,
      contratosReal: detalle.contratos_real,
      contratosCumplimientoPct: detalle.contratos_cumplimiento_pct,
      capitalAjuste: detalle.capital_ajuste ?? 0,
      contratosAjuste: detalle.contratos_ajuste ?? 0,
    })),
    cartera: {
      conversionesClientes: fila.cartera.conversiones_clientes,
      conversionesRenovacion: fila.cartera.conversiones_renovacion,
      conversionesUpgrade: fila.cartera.conversiones_upgrade,
      operacionesRenovacion: fila.cartera.operaciones_renovacion,
      operacionesUpgrade: fila.cartera.operaciones_upgrade,
      capitalRenovadoPen: fila.cartera.capital_renovado_pen,
      capitalRenovadoUsd: fila.cartera.capital_renovado_usd,
      capitalAdicionalPen: fila.cartera.capital_adicional_pen,
      capitalAdicionalUsd: fila.cartera.capital_adicional_usd,
      renovacionesSinDesglose: fila.cartera.renovaciones_sin_desglose,
    },
  }))
  const fueraComoCumplimiento: CumplimientoComercial[] = fueraRanking.map((fila) => ({
    conversionObjetivo: 0,
    conversionReal: null,
    convertidos: (fila.conversion?.cierresNoReferidos ?? 0)
      + (fila.conversion?.cierresReferidos ?? 0)
      + fila.cartera.conversionesClientes,
    resueltos: fila.conversion?.divisor ?? 0,
    numerador: fila.conversion?.numerador ?? 0,
    detalles: fila.detalles,
  }))
  return {
    periodo: respuesta.periodo,
    revision: respuesta.revision,
    publicadaEn: respuesta.publicada_en,
    fuentesReales: {
      capitalYContratos: respuesta.fuentes_reales.capital_y_contratos,
      conversion: respuesta.fuentes_reales.conversion,
    },
    cierre: respuesta.cierre ?? null,
    vendedor: actorId ? (porVendedor[actorId] ?? null) : null,
    supervisor: agregarCumplimientos(filas.filter((fila) => fila.supervisorId === actorId)),
    gerencia: agregarCumplimientos([...filas, ...fueraComoCumplimiento]),
    porVendedor,
    fueraRanking,
  }
}

export function capitalReal(
  cumplimiento: CumplimientoAgregado,
  moneda: MonedaMeta,
  categoria?: CategoriaMeta,
): number {
  return cumplimiento.detalles.reduce((total, detalle) => (
    detalle.moneda === moneda && (categoria == null || detalle.categoria === categoria)
      ? total + detalle.capitalReal
      : total
  ), 0)
}

export function contratosReales(
  cumplimiento: CumplimientoComercial,
  moneda: MonedaMeta,
  categoria?: CategoriaMeta,
): number {
  return cumplimiento.detalles.reduce((total, detalle) => (
    detalle.moneda === moneda && (categoria == null || detalle.categoria === categoria)
      ? total + detalle.contratosReal
      : total
  ), 0)
}

export function periodoLima(ahoraMs: number): string {
  return `${fechaLima(ahoraMs).slice(0, 7)}-01`
}
