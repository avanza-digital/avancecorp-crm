import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  FechaSchema,
  NumeroRpcSchema,
  TextoNoVacioSchema,
  UuidSchema,
} from './esquemas-rpc'

export const CATEGORIAS_PRODUCTO = ['nuevo', 'renovacion', 'upgrade'] as const
export const MONEDAS_PRODUCTO = ['PEN', 'USD'] as const
export const MODALIDADES_PRODUCTO = ['mensual', 'trimestral', 'semestral', 'anual'] as const
export const TIPOS_INTERES_PRODUCTO = ['simple', 'compuesto'] as const

const RevisionSchema = v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1))
// Reflejan exactamente los CHECK del catálogo. Mantenerlos alineados evita que
// el formulario prometa valores que el servidor necesariamente rechazará.
const PorcentajeSchema = v.pipe(NumeroRpcSchema, v.minValue(0.0001), v.maxValue(50))
const CapitalSchema = v.pipe(NumeroRpcSchema, v.minValue(100), v.maxValue(100_000_000))

export const ProductoCondicionSchema = v.pipe(
  v.strictObject({
    id: UuidSchema,
    orden: v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1)),
    categoria: v.picklist(CATEGORIAS_PRODUCTO),
    moneda: v.picklist(MONEDAS_PRODUCTO),
    plazo_meses: v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1), v.maxValue(600)),
    modalidad: v.picklist(MODALIDADES_PRODUCTO),
    tipo_interes: v.picklist(TIPOS_INTERES_PRODUCTO),
    capital_minimo: CapitalSchema,
    capital_maximo: CapitalSchema,
    tasa_referencia: PorcentajeSchema,
    tasa_minima: PorcentajeSchema,
    tasa_maxima: PorcentajeSchema,
    activa: v.boolean(),
    creado_en: FechaHoraSchema,
    retirada_en: v.nullable(FechaHoraSchema),
  }),
  v.check(
    (condicion) =>
      condicion.capital_minimo <= condicion.capital_maximo
      && condicion.tasa_minima <= condicion.tasa_referencia
      && condicion.tasa_referencia <= condicion.tasa_maxima
      && (condicion.tipo_interes === 'simple'
        || (condicion.modalidad === 'anual'
          && condicion.plazo_meses >= 12
          && condicion.plazo_meses % 12 === 0)),
    'Rangos o cronograma de la condición incoherentes',
  ),
)

export const ProductoVersionSchema = v.strictObject({
  id: UuidSchema,
  numero_version: RevisionSchema,
  estado: v.picklist(['borrador', 'publicada', 'retirada']),
  revision: RevisionSchema,
  nombre: TextoNoVacioSchema,
  descripcion: v.nullable(v.string()),
  vigente_desde: FechaSchema,
  vigente_hasta: v.nullable(FechaSchema),
  creado_por: v.nullable(UuidSchema),
  creado_en: FechaHoraSchema,
  actualizado_por: v.nullable(UuidSchema),
  actualizado_en: FechaHoraSchema,
  publicada_por: v.nullable(UuidSchema),
  publicada_por_nombre: v.nullable(v.string()),
  publicada_en: v.nullable(FechaHoraSchema),
  retirada_por: v.nullable(UuidSchema),
  retirada_en: v.nullable(FechaHoraSchema),
  condiciones: v.array(ProductoCondicionSchema),
})

export const ProductoInversionSchema = v.strictObject({
  id: UuidSchema,
  codigo: TextoNoVacioSchema,
  estado: v.picklist(['activo', 'archivado']),
  revision: RevisionSchema,
  creado_por: v.nullable(UuidSchema),
  creado_en: FechaHoraSchema,
  actualizado_por: v.nullable(UuidSchema),
  actualizado_en: FechaHoraSchema,
  archivado_por: v.nullable(UuidSchema),
  archivado_en: v.nullable(FechaHoraSchema),
  versiones: v.array(ProductoVersionSchema),
})

export const ConfiguracionProductosSchema = v.strictObject({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  puede_administrar: v.boolean(),
  compatibilidad_altas_legacy: v.boolean(),
  compatibilidad_revision: RevisionSchema,
  productos: v.array(ProductoInversionSchema),
})

export const ProductoCondicionSeleccionSchema = v.pipe(
  v.strictObject({
    condicion_id: UuidSchema,
    producto_id: UuidSchema,
    producto_codigo: TextoNoVacioSchema,
    producto_revision: RevisionSchema,
    version_id: UuidSchema,
    numero_version: RevisionSchema,
    version_nombre: TextoNoVacioSchema,
    vigente_desde: FechaSchema,
    vigente_hasta: v.nullable(FechaSchema),
    categoria: v.picklist(CATEGORIAS_PRODUCTO),
    moneda: v.picklist(MONEDAS_PRODUCTO),
    plazo_meses: v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1), v.maxValue(600)),
    modalidad: v.picklist(MODALIDADES_PRODUCTO),
    tipo_interes: v.picklist(TIPOS_INTERES_PRODUCTO),
    capital_minimo: CapitalSchema,
    capital_maximo: CapitalSchema,
    tasa_referencia: PorcentajeSchema,
    tasa_minima: PorcentajeSchema,
    tasa_maxima: PorcentajeSchema,
  }),
  v.check(
    (condicion) =>
      condicion.capital_minimo <= condicion.capital_maximo
      && condicion.tasa_minima <= condicion.tasa_referencia
      && condicion.tasa_referencia <= condicion.tasa_maxima
      && (condicion.tipo_interes === 'simple'
        || (condicion.modalidad === 'anual'
          && condicion.plazo_meses >= 12
          && condicion.plazo_meses % 12 === 0)),
    'Rangos o cronograma de la condición seleccionable incoherentes',
  ),
)

export type ConfiguracionProductos = v.InferOutput<typeof ConfiguracionProductosSchema>
export type ProductoInversion = v.InferOutput<typeof ProductoInversionSchema>
export type ProductoVersion = v.InferOutput<typeof ProductoVersionSchema>
export type ProductoCondicion = v.InferOutput<typeof ProductoCondicionSchema>
export type ProductoCondicionSeleccion = v.InferOutput<typeof ProductoCondicionSeleccionSchema>

export const ResultadoVersionProductoSchema = v.strictObject({
  producto_id: UuidSchema,
  producto_revision: RevisionSchema,
  version_id: UuidSchema,
  version_revision: RevisionSchema,
  numero_version: RevisionSchema,
  estado: v.picklist(['borrador', 'publicada']),
})

export const ResultadoArchivoProductoSchema = v.strictObject({
  producto_id: UuidSchema,
  producto_revision: RevisionSchema,
  estado: v.literal('archivado'),
})

export const ResultadoCierreLegacyProductosSchema = v.strictObject({
  compatibilidad_altas_legacy: v.literal(false),
  compatibilidad_revision: RevisionSchema,
})

export type ResultadoVersionProducto = v.InferOutput<typeof ResultadoVersionProductoSchema>
export type ResultadoArchivoProducto = v.InferOutput<typeof ResultadoArchivoProductoSchema>

export interface CondicionProductoInput {
  categoria: (typeof CATEGORIAS_PRODUCTO)[number]
  moneda: (typeof MONEDAS_PRODUCTO)[number]
  plazo_meses: number
  modalidad: (typeof MODALIDADES_PRODUCTO)[number]
  tipo_interes: (typeof TIPOS_INTERES_PRODUCTO)[number]
  capital_minimo: number
  capital_maximo: number
  tasa_referencia: number
  tasa_minima?: number
  tasa_maxima?: number
}

export function etiquetaCondicionProducto(condicion: ProductoCondicionSeleccion): string {
  const categoria = {
    nuevo: 'Nuevo',
    renovacion: 'Renovación',
    upgrade: 'Upgrade',
  }[condicion.categoria]
  return `${condicion.producto_codigo} · ${categoria} · ${condicion.moneda} · ${condicion.plazo_meses} meses`
}
