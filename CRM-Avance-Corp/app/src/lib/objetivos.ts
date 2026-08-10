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

const CumplimientoVendedorSchema = v.strictObject({
  vendedor_id: UuidSchema,
  nombre: TextoNoVacioSchema,
  supervisor_id: UuidSchema,
  supervisor_nombre: TextoNoVacioSchema,
  conversion_objetivo: v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(100)),
  conversion_real: v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(100))),
  convertidos: EnteroNoNegativoRpcSchema,
  resueltos: EnteroNoNegativoRpcSchema,
  detalles: DetallesCumplimientoSchema,
})

export const CumplimientoMetasSchema = v.strictObject({
  version: v.literal(1),
  periodo: FechaSchema,
  revision: EnteroNoNegativoRpcSchema,
  publicada_en: v.nullable(FechaHoraSchema),
  fuentes_reales: v.strictObject({
    capital_y_contratos: v.literal('contratos_confirmados'),
    conversion: v.literal('leads_resueltos'),
  }),
  vendedores: v.array(CumplimientoVendedorSchema),
})

export type CumplimientoMetasRpc = v.InferOutput<typeof CumplimientoMetasSchema>

export interface CumplimientoDetalle extends ObjetivoDetalle {
  capitalReal: number
  capitalCumplimientoPct: number | null
  contratosReal: number
  contratosCumplimientoPct: number | null
}

export interface CumplimientoComercial {
  conversionObjetivo: number
  conversionReal: number | null
  convertidos: number
  resueltos: number
  detalles: CumplimientoDetalle[]
}

export interface CumplimientoVendedor extends CumplimientoComercial {
  vendedorId: string
  nombre: string
  supervisorId: string
  supervisorNombre: string
}

export interface FuentesRealesCumplimientoMetas {
  capitalYContratos: 'contratos_confirmados'
  conversion: 'leads_resueltos'
}

export interface CumplimientoMetasJerarquico {
  periodo: string
  revision: number
  publicadaEn: string | null
  fuentesReales: FuentesRealesCumplimientoMetas
  vendedor: CumplimientoComercial | null
  supervisor: CumplimientoComercial | null
  gerencia: CumplimientoComercial | null
  porVendedor: Record<string, CumplimientoVendedor>
}

function cumplimientoDesdeVendedor(
  fila: CumplimientoMetasRpc['vendedores'][number],
): CumplimientoVendedor {
  return {
    vendedorId: fila.vendedor_id,
    nombre: fila.nombre,
    supervisorId: fila.supervisor_id,
    supervisorNombre: fila.supervisor_nombre,
    conversionObjetivo: fila.conversion_objetivo,
    conversionReal: fila.conversion_real,
    convertidos: fila.convertidos,
    resueltos: fila.resueltos,
    detalles: fila.detalles.map((detalle) => ({
      categoria: detalle.categoria,
      moneda: detalle.moneda,
      capitalObjetivo: detalle.capital_objetivo,
      capitalReal: detalle.capital_real,
      capitalCumplimientoPct: detalle.capital_cumplimiento_pct,
      contratosObjetivo: detalle.contratos_objetivo,
      contratosReal: detalle.contratos_real,
      contratosCumplimientoPct: detalle.contratos_cumplimiento_pct,
    })),
  }
}

export function agregarCumplimientos(
  items: Iterable<CumplimientoComercial>,
): CumplimientoComercial | null {
  const filas = Array.from(items)
  if (filas.length === 0) return null

  const metas = agregarObjetivos(filas)
  const convertidos = filas.reduce((total, fila) => total + fila.convertidos, 0)
  const resueltos = filas.reduce((total, fila) => total + fila.resueltos, 0)
  const reales = new Map(CLAVES_DIMENSION.map((clave) => [clave, {
    capitalReal: 0,
    contratosReal: 0,
  }]))
  for (const fila of filas) {
    for (const detalle of fila.detalles) {
      const destino = reales.get(`${detalle.categoria}:${detalle.moneda}`)
      if (!destino) continue
      destino.capitalReal += detalle.capitalReal
      destino.contratosReal += detalle.contratosReal
    }
  }

  return {
    conversionObjetivo: metas.conversionObjetivo,
    conversionReal: resueltos > 0 ? Math.round((10_000 * convertidos) / resueltos) / 100 : null,
    convertidos,
    resueltos,
    detalles: metas.detalles.map((meta) => {
      const real = reales.get(`${meta.categoria}:${meta.moneda}`) ?? { capitalReal: 0, contratosReal: 0 }
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
  cumplimiento: CumplimientoComercial | null,
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
  return {
    periodo: respuesta.periodo,
    revision: respuesta.revision,
    publicadaEn: respuesta.publicada_en,
    fuentesReales: {
      capitalYContratos: respuesta.fuentes_reales.capital_y_contratos,
      conversion: respuesta.fuentes_reales.conversion,
    },
    vendedor: actorId ? (porVendedor[actorId] ?? null) : null,
    supervisor: agregarCumplimientos(filas.filter((fila) => fila.supervisorId === actorId)),
    gerencia: agregarCumplimientos(filas),
    porVendedor,
  }
}

export function capitalReal(
  cumplimiento: CumplimientoComercial,
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
