import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  FechaSchema,
  NumeroRpcSchema,
  TextoNoVacioSchema,
  UuidSchema,
} from './esquemas-rpc'
import { CATEGORIAS_PRODUCTO, MONEDAS_PRODUCTO } from './productos-inversion'

const CombinacionMetaSchema = v.strictObject({
  categoria: v.picklist(CATEGORIAS_PRODUCTO),
  moneda: v.picklist(MONEDAS_PRODUCTO),
  capital_objetivo: v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(100_000_000)),
  contratos_objetivo: v.pipe(EnteroNoNegativoRpcSchema, v.maxValue(1_000)),
})

const CLAVES_DIMENSION = CATEGORIAS_PRODUCTO.flatMap((categoria) =>
  MONEDAS_PRODUCTO.map((moneda) => `${categoria}:${moneda}`),
)

export const DetallesMetaSchema = v.pipe(
  v.array(CombinacionMetaSchema),
  v.length(6),
  v.check(
    (detalles) => {
      const claves = new Set(detalles.map((detalle) => `${detalle.categoria}:${detalle.moneda}`))
      return claves.size === CLAVES_DIMENSION.length
        && CLAVES_DIMENSION.every((clave) => claves.has(clave))
    },
    'Las metas deben contener exactamente categoría × moneda',
  ),
)

export const MetaVendedorConfigSchema = v.strictObject({
  vendedor_id: UuidSchema,
  nombre: TextoNoVacioSchema,
  supervisor_id: UuidSchema,
  supervisor_nombre: TextoNoVacioSchema,
  conversion_objetivo: v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(100)),
  detalles: DetallesMetaSchema,
})

export const ConfiguracionMetasSchema = v.strictObject({
  version: v.literal(1),
  periodo: FechaSchema,
  revision: EnteroNoNegativoRpcSchema,
  publicada_en: v.nullable(FechaHoraSchema),
  publicada_por: v.nullable(UuidSchema),
  publicada_por_nombre: v.nullable(v.string()),
  puede_editar: v.boolean(),
  vendedores: v.array(MetaVendedorConfigSchema),
})

export const ResultadoPublicacionMetasSchema = v.strictObject({
  id: UuidSchema,
  periodo: FechaSchema,
  revision: v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1)),
  revision_anterior_id: v.nullable(UuidSchema),
  publicada_por: UuidSchema,
  publicada_en: FechaHoraSchema,
})

export const RespuestaPublicacionMetasSchema = v.pipe(
  v.array(ResultadoPublicacionMetasSchema),
  v.length(1),
)

export type DetalleMeta = v.InferOutput<typeof CombinacionMetaSchema>
export type MetaVendedorConfig = v.InferOutput<typeof MetaVendedorConfigSchema>
export type ConfiguracionMetas = v.InferOutput<typeof ConfiguracionMetasSchema>
export type ResultadoPublicacionMetas = v.InferOutput<typeof ResultadoPublicacionMetasSchema>

export type PublicacionMetas = Record<string, {
  conversion_objetivo: number
  detalles: DetalleMeta[]
}>

export function payloadPublicacionMetas(configuracion: ConfiguracionMetas): PublicacionMetas {
  return Object.fromEntries(
    configuracion.vendedores.map((vendedor) => [
      vendedor.vendedor_id,
      {
        conversion_objetivo: vendedor.conversion_objetivo,
        detalles: vendedor.detalles.map((detalle) => ({ ...detalle })),
      },
    ]),
  )
}
