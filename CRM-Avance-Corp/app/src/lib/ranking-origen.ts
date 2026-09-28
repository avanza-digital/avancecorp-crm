import * as v from 'valibot'
import { EnteroNoNegativoRpcSchema, FechaSchema, NumeroRpcSchema, UuidSchema } from './esquemas-rpc'

const FilaOrigenRankingSchema = v.strictObject({
  origen: v.string(),
  // Ajustes de cierre son la única fila negativa; el contrato conserva ambas
  // monedas para conciliar con el capital confirmado del Ranking.
  capital_pen: NumeroRpcSchema,
  capital_usd: NumeroRpcSchema,
  contratos: EnteroNoNegativoRpcSchema,
  leads: EnteroNoNegativoRpcSchema,
  cierres: EnteroNoNegativoRpcSchema,
  conversion_pct: v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0))),
})

export const RankingOrigenVendedorSchema = v.pipe(
  v.strictObject({
    version: v.literal(2),
    periodo: FechaSchema,
    vendedor_id: UuidSchema,
    disponible: v.boolean(),
    filas: v.array(FilaOrigenRankingSchema),
    cartera: v.nullable(v.pipe(v.array(v.strictObject({
      categoria: v.picklist(['renovacion', 'upgrade', 'sin_clasificar']),
      pen: v.pipe(NumeroRpcSchema, v.minValue(0)),
      usd: v.pipe(NumeroRpcSchema, v.minValue(0)),
    })), v.check((filas) => filas.length === 3 && new Set(filas.map((f) => f.categoria)).size === 3,
      'El desglose de cartera debe tener una fila por categoría'))),
  }),
  v.check(
    (dato) => dato.disponible || dato.filas.length === 0,
    'Un desglose no disponible no puede publicar importes parciales',
  ),
  v.check(
    (dato) => new Set(dato.filas.map((fila) => fila.origen)).size === dato.filas.length,
    'El desglose repite un origen',
  ),
)

export type RankingOrigenVendedor = v.InferOutput<typeof RankingOrigenVendedorSchema>
export type FilaOrigenRanking = RankingOrigenVendedor['filas'][number]
