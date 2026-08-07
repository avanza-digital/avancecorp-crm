import * as v from 'valibot'

const NUMERO_RPC_RE = /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/

/** Numeric/bigint puede llegar como número o texto según PostgREST. */
export const NumeroRpcSchema = v.pipe(
  v.union([v.number(), v.string()]),
  v.check(
    (valor) => typeof valor === 'number' || NUMERO_RPC_RE.test(valor.trim()),
    'Número RPC inválido',
  ),
  v.transform(Number),
  v.number(),
  v.finite(),
)

export const EnteroNoNegativoRpcSchema = v.pipe(
  NumeroRpcSchema,
  v.integer(),
  v.minValue(0),
)

export const UuidSchema = v.pipe(v.string(), v.uuid())
export const FechaSchema = v.pipe(v.string(), v.isoDate())
export const FechaHoraSchema = v.pipe(
  v.string(),
  v.check((valor) => Number.isFinite(Date.parse(valor)), 'Fecha/hora inválida'),
)
export const TextoNoVacioSchema = v.pipe(v.string(), v.trim(), v.minLength(1))
