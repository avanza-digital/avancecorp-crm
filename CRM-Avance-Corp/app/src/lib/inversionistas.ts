// Frontera neutral F5. Ningún UUID de perfil sustituye a la persona.
import * as v from 'valibot'

export const EMPRESAS_INVERSION = ['avance', 'qorilazo', 'prodelco'] as const
export type EmpresaInversion = (typeof EMPRESAS_INVERSION)[number]
export const EMPRESA_NOMBRE: Record<EmpresaInversion, string> = {
  avance: 'Avance', qorilazo: 'Qorilazo', prodelco: 'Prodelco',
}
const Uuid = v.pipe(v.string(), v.uuid())
const TextoOpcional = v.nullable(v.string())
const IdOpcional = v.nullable(Uuid)
const Entero = v.pipe(v.number(), v.integer(), v.minValue(0))
const Importe = v.pipe(v.number(), v.finite(), v.minValue(0))
const Moneda = v.picklist(['PEN', 'USD'])
const Empresa = v.picklist(EMPRESAS_INVERSION)

export const EstadoCarteraInversionistasSchema = v.object({
  version: v.literal(1), habilitada: v.boolean(), escritura_habilitada: v.boolean(), motivo: TextoOpcional,
})
const Identidad = {
  inversionista_id: Uuid, nombre: v.string(), documento_tipo: TextoOpcional,
  documento: TextoOpcional, documento_verificado: v.boolean(), telefono: TextoOpcional,
  correo: TextoOpcional, estado: v.string(), no_contactar: v.boolean(),
  responsable_id: IdOpcional, responsable_nombre: TextoOpcional, creado_en: v.string(),
}
export const ResumenEmpresaSchema = v.object({
  empresa: Empresa, moneda: Moneda, cantidad: Entero, capital_registrado: Importe,
  capital_activo: v.nullable(Importe),
})
export const FilaInversionistaSchema = v.object({...Identidad, empresas: v.array(Empresa)})
export const CarteraInversionistasSchema = v.object({
  version: v.literal(1), pagina: v.pipe(Entero, v.minValue(1)), tamano: v.picklist([10, 25, 50]),
  total: Entero, filas: v.array(FilaInversionistaSchema), totales: v.array(ResumenEmpresaSchema),
})
export const InversionFuenteSchema = v.object({
  fuente_id: Uuid, inversionista_id: Uuid, inversion_id: IdOpcional, empresa: Empresa,
  perfil_id: IdOpcional, lead_id: IdOpcional, numero: TextoOpcional, capital: Importe,
  moneda: Moneda, estado: v.string(), fecha_comercial: TextoOpcional, fecha_imputacion: TextoOpcional,
  vence_en: TextoOpcional, analista_origen_id: IdOpcional, analista_origen_nombre: TextoOpcional,
  es_inicial: v.boolean(), es_demo: v.boolean(), creado_en: v.string(),
  contrato: v.nullable(v.object({fecha_inicio: v.string(), tasa_anual: Importe,
    modalidad: v.picklist(['mensual', 'trimestral', 'semestral', 'anual']), tipo_interes: v.picklist(['simple', 'compuesto']),
    categoria: TextoOpcional})),
  pdf: v.nullable(v.object({estado: v.string(), reintentable: v.boolean()})),
  documentos: v.array(v.object({id: Uuid, nombre: v.string(), tipo: v.string()})),
  cotitulares: v.array(v.object({orden: Entero, nombre: v.string(), tipo_documento: v.string(), documento: v.string()})),
  proxima_cuota: v.nullable(v.object({fecha: v.string(), moneda: Moneda, monto: Importe, estado: v.string(), tipo: v.string()})),
  numero_transaccion: TextoOpcional,
})
export const FichaInversionistaSchema = v.object({
  version: v.literal(1), persona: v.object({...Identidad, perfil_id: IdOpcional}),
  identidad_fusionada: v.boolean(),
  capacidades: v.object({nueva_inversion: v.boolean(), motivo_no_operable: TextoOpcional,
    contactar: v.boolean(), cuentas_perfil_ids: v.array(Uuid), documentos: v.boolean()}),
  inversiones: v.array(InversionFuenteSchema), inversiones_total: Entero, pagina_inversiones: Entero,
  totales: v.array(ResumenEmpresaSchema),
  historial: v.array(v.object({id: Uuid, origen: v.picklist(['lead', 'cliente']), tipo: v.string(),
    detalle: TextoOpcional, creado_en: v.string()})),
  historial_total: Entero, pagina_historial: Entero,
  tareas: v.array(v.object({id: Uuid, tipo: v.string(), titulo: v.string(), vence_en: v.string(), estado: v.string()})),
  tareas_total: Entero,
})
export type EstadoCarteraInversionistas = v.InferOutput<typeof EstadoCarteraInversionistasSchema>
export type FilaInversionista = v.InferOutput<typeof FilaInversionistaSchema>
export type CarteraInversionistas = v.InferOutput<typeof CarteraInversionistasSchema>
export type FichaInversionista = v.InferOutput<typeof FichaInversionistaSchema>
export type InversionFuente = v.InferOutput<typeof InversionFuenteSchema>
export type ResumenEmpresa = v.InferOutput<typeof ResumenEmpresaSchema>
export interface FiltrosInversionistas {
  pagina: number
  tamano: 10 | 25 | 50
  texto: string
  empresa: EmpresaInversion | ''
  responsable: string
}
export const FILTROS_INVERSIONISTAS_INICIALES: FiltrosInversionistas = {
  pagina: 1, tamano: 25, texto: '', empresa: '', responsable: '',
}

/** La respuesta incompleta se bloquea; nunca se convierte en una cartera vacía. */
export function validarPaginaInversionistas(pagina: CarteraInversionistas): boolean {
  const esperadas = Math.max(0, Math.min(pagina.tamano, pagina.total - (pagina.pagina - 1) * pagina.tamano))
  return pagina.filas.length === esperadas && new Set(pagina.filas.map(p => p.inversionista_id)).size === esperadas
}
