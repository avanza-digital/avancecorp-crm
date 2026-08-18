import * as v from 'valibot'
import { VISTAS } from '@/lib/router'

const TextoCortoSchema = v.pipe(v.string(), v.minLength(1), v.maxLength(180))
const TextoSchema = v.pipe(v.string(), v.minLength(1), v.maxLength(1_500))
const VistaSchema = v.picklist(VISTAS)

export const PasoAyudaVendedorSchema = v.strictObject({
  titulo: TextoCortoSchema,
  detalle: TextoSchema,
})

export const TraduccionAyudaVendedorSchema = v.strictObject({
  lenguajeVendedor: TextoCortoSchema,
  lenguajeCrm: TextoCortoSchema,
})

export const AccionAyudaVendedorSchema = v.variant('tipo', [
  v.strictObject({
    tipo: v.literal('navegar'),
    vista: VistaSchema,
    etiqueta: TextoCortoSchema,
  }),
  v.strictObject({
    tipo: v.literal('nuevo_lead'),
    etiqueta: TextoCortoSchema,
  }),
])

export const RespuestaAyudaVendedorSchema = v.strictObject({
  id: v.pipe(v.string(), v.regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)),
  titulo: TextoCortoSchema,
  resumen: TextoSchema,
  duracion: TextoCortoSchema,
  pasos: v.pipe(v.array(PasoAyudaVendedorSchema), v.minLength(1), v.maxLength(8)),
  traduccion: v.optional(TraduccionAyudaVendedorSchema),
  advertencia: v.optional(TextoSchema),
  accion: AccionAyudaVendedorSchema,
  fuente: TextoCortoSchema,
})

export const OpcionAclaracionAyudaVendedorSchema = v.strictObject({
  etiqueta: TextoCortoSchema,
  detalle: TextoSchema,
  consulta: TextoCortoSchema,
})

export const AclaracionAyudaVendedorSchema = v.strictObject({
  titulo: TextoCortoSchema,
  detalle: TextoSchema,
  opciones: v.pipe(v.array(OpcionAclaracionAyudaVendedorSchema), v.minLength(2), v.maxLength(3)),
})

/**
 * Contrato público y cerrado de crm.consultar_ayuda_vendedor().
 * `strictObject` impide que puntuaciones o motivos internos terminen por
 * accidente en el navegador.
 */
export const ResultadoConsultaAyudaVendedorSchema = v.variant('tipo', [
  v.strictObject({
    version: v.literal(1),
    tipo: v.literal('respuesta'),
    respuesta: RespuestaAyudaVendedorSchema,
  }),
  v.strictObject({
    version: v.literal(1),
    tipo: v.literal('aclaracion'),
    aclaracion: AclaracionAyudaVendedorSchema,
  }),
  v.strictObject({
    version: v.literal(1),
    tipo: v.literal('sin_resultado'),
    consulta: v.pipe(v.string(), v.maxLength(240)),
  }),
])

export const InicioAyudaVendedorSchema = v.strictObject({
  version: v.literal(1),
  preguntas: v.pipe(v.array(TextoCortoSchema), v.maxLength(6)),
})

export type PasoAyudaVendedor = v.InferOutput<typeof PasoAyudaVendedorSchema>
export type TraduccionAyudaVendedor = v.InferOutput<typeof TraduccionAyudaVendedorSchema>
export type AccionAyudaVendedor = v.InferOutput<typeof AccionAyudaVendedorSchema>
export type RespuestaAyudaVendedor = v.InferOutput<typeof RespuestaAyudaVendedorSchema>
export type OpcionAclaracionAyudaVendedor = v.InferOutput<typeof OpcionAclaracionAyudaVendedorSchema>
export type AclaracionAyudaVendedor = v.InferOutput<typeof AclaracionAyudaVendedorSchema>
export type ResultadoConsultaAyudaVendedor = v.InferOutput<typeof ResultadoConsultaAyudaVendedorSchema>
export type InicioAyudaVendedor = v.InferOutput<typeof InicioAyudaVendedorSchema>
