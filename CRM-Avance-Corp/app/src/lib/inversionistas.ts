// Frontera neutral F5. Ningún UUID de perfil sustituye a la persona.
import * as v from 'valibot'
import { COOPERATIVAS } from './cierres-externos'

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
export const FilaInversionistaSchema = v.object({...Identidad, empresas: v.array(Empresa),
  ultima_fecha_comercial: TextoOpcional, resumen: v.array(ResumenEmpresaSchema),
})
export const CarteraInversionistasSchema = v.object({
  version: v.literal(2), pagina: v.pipe(Entero, v.minValue(1)), tamano: v.picklist([10, 25, 50]),
  total: Entero, filas: v.array(FilaInversionistaSchema), totales: v.array(ResumenEmpresaSchema),
  sin_inversiones_total: Entero, solo_avance: v.boolean(),
  opciones_meses: v.array(v.pipe(v.string(), v.regex(/^\d{4}-(0[1-9]|1[0-2])$/))),
  opciones_responsables: v.array(v.object({id: Uuid, nombre: TextoOpcional})),
})
export const InversionFuenteSchema = v.object({
  fuente_id: Uuid, inversionista_id: Uuid, inversion_id: IdOpcional, empresa: Empresa,
  perfil_id: IdOpcional, lead_id: IdOpcional, numero: TextoOpcional, capital: Importe,
  moneda: Moneda, estado: v.string(), fecha_comercial: TextoOpcional, fecha_imputacion: TextoOpcional,
  vence_en: TextoOpcional, analista_origen_id: IdOpcional, analista_origen_nombre: TextoOpcional,
  // Quién VENDIÓ (fase 6 de Facturación, 10/10/2026); analista_origen_* es a quién CUENTA hoy. Opcionales: un
  // servidor anterior no los envía.
  analista_venta_id: v.optional(IdOpcional), analista_venta_nombre: v.optional(TextoOpcional),
  es_inicial: v.nullable(v.boolean()), es_demo: v.boolean(), creado_en: v.string(),
  contrato: v.nullable(v.object({fecha_inicio: v.string(), tasa_anual: Importe,
    modalidad: v.picklist(['mensual', 'trimestral', 'semestral', 'anual']), tipo_interes: v.picklist(['simple', 'compuesto']),
    categoria: TextoOpcional})),
  pdf: v.nullable(v.object({estado: v.string(), reintentable: v.boolean()})),
  documentos: v.array(v.object({id: Uuid, nombre: v.string(), tipo: v.string()})),
  cotitulares: v.array(v.object({orden: Entero, nombre: v.string(), tipo_documento: v.string(), documento: v.string()})),
  proxima_cuota: v.nullable(v.object({fecha: v.string(), moneda: Moneda, monto: Importe, estado: v.string(), tipo: v.string()})),
  numero_transaccion: TextoOpcional,
  condiciones_coopac: v.optional(v.nullable(v.object({
    plazo_meses: v.pipe(Entero, v.minValue(1)), tasa_anual: Importe,
  }))),
})
export const FichaInversionistaSchema = v.object({
  version: v.literal(1), persona: v.object({...Identidad, perfil_id: IdOpcional}),
  identidad_fusionada: v.boolean(),
  capacidades: v.object({postventa: v.optional(v.boolean()), nueva_inversion: v.boolean(), motivo_no_operable: TextoOpcional,
    contactar: v.boolean(), cuentas_perfil_ids: v.array(Uuid), documentos: v.boolean()}),
  inversiones: v.array(InversionFuenteSchema), inversiones_total: Entero, pagina_inversiones: Entero,
  totales: v.array(ResumenEmpresaSchema),
  continuidad: v.optional(v.object({proximo_vencimiento: TextoOpcional})),
  historial: v.array(v.object({id: Uuid, origen: v.picklist(['lead', 'cliente', 'postventa']), tipo: v.string(),
    empresa: v.optional(v.nullable(Empresa)),
    detalle: TextoOpcional, creado_en: v.string()})),
  historial_total: Entero, pagina_historial: Entero,
  tareas: v.array(v.object({id: Uuid, tipo: v.string(), titulo: v.string(), vence_en: v.string(), estado: v.string()})),
  tareas_total: Entero,
})
/** Acuse de crm.eliminar_inversion_fn. Estricto: una clave de más o un tipo distinto es otra respuesta. */
export const InversionEliminadaSchema = v.strictObject({
  ok: v.literal(true), fuente_id: Uuid, empresa: Empresa, auditoria_id: Uuid,
  conversion_anulada: v.boolean(), mes_cerrado: v.boolean(),
})
// ─── Reemplazar inversión (Fase 2, 17/10/2026) ─────────────────────────────────────────────────────────────
const FechaIso = v.pipe(v.string(), v.regex(/^\d{4}-\d{2}-\d{2}$/))
/** Vista previa del mes (crm.reemplazar_inversion_vista_previa_fn). Estricta: la forma es nuestra. */
export const VistaPreviaReemplazoSchema = v.strictObject({
  fuente_id: Uuid, fecha_inicio: FechaIso,
  fecha_comercial_actual: FechaIso, mes_actual: FechaIso,
  fecha_comercial_resultante: FechaIso, mes_resultante: FechaIso,
  cambia_mes: v.boolean(), fecha_corregida: v.boolean(),
  /** El reemplazo se negaría: el contrato ya tiene cuotas pagadas (se perderían). */
  cuotas_pagadas: v.boolean(),
})
/**
 * Acuse del reemplazo (crm.reemplazar_inversion_fn y crm.reemplazar_inversion_por_existente_fn). Lo que PRUEBA la
 * escritura es `contrato_id`; lo demás (el bloque del alta, la conversión) se lee con tolerancia: tras un 2xx el
 * reemplazo ya ocurrió y la pantalla no puede decir «error» (lección del alta confirmada).
 */
/** Lo IMPRESCINDIBLE del acuse: qué quedó. Lo accesorio se lee aparte, campo a campo, y si viene mal no tumba el acuse. */
export const InversionReemplazadaSchema = v.looseObject({
  ok: v.literal(true), fuente_id: Uuid, contrato_id: Uuid, modo: v.picklist(['nueva', 'existente']),
})
export const AcuseReemplazoAccesorios = {
  numero_contrato: v.nullable(v.string()),
  idempotente: v.boolean(),
  // El mes REAL en que quedó la venta (puede diferir de la vista previa si algo cambió entre medias: auditor-rls, P3-7).
  periodo_despues: v.nullable(FechaIso),
}
const MESES_LARGOS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'] as const
/** '2026-09-01' → 'Septiembre 2026'. */
export function mesLargo(iso: string): string {
  const [anio, mes] = iso.split('-')
  const nombre = MESES_LARGOS[Number(mes) - 1]
  return nombre && anio ? `${nombre[0]!.toUpperCase()}${nombre.slice(1)} ${anio}` : iso
}
/** Hoy el reemplazo es de Avance, de una inversión «nuevo» real; lo demás ni se ofrece (el servidor decide igual). */
export function inversionReemplazable(i: InversionFuente): boolean {
  return i.empresa === 'avance' && i.contrato !== null && i.contrato.categoria === 'nuevo' && !i.es_demo
    && (i.estado === 'activo' || i.estado === 'vencido')
}
/** Es la venta de un lead: su reemplazo exige además Gerencia. */
export function esVentaDeLead(i: Pick<InversionFuente, 'lead_id' | 'es_inicial'>): boolean {
  return i.lead_id !== null || i.es_inicial === true
}
const claveTitulares = (i: InversionFuente) =>
  i.cotitulares.map(c => `${c.tipo_documento}:${c.documento.trim().toUpperCase()}`).sort().join('|')
/** Pista para «quedarme con la otra»: los mismos datos que exige el servidor para una carga doble. Solo orienta. */
export function diferenciasDeCarga(original: InversionFuente, otra: InversionFuente): string[] {
  const d: string[] = []
  if (otra.capital !== original.capital || otra.moneda !== original.moneda) d.push('capital')
  if (otra.contrato?.tasa_anual !== original.contrato?.tasa_anual) d.push('tasa')
  if (otra.contrato?.fecha_inicio !== original.contrato?.fecha_inicio || otra.vence_en !== original.vence_en) d.push('fechas')
  if (otra.contrato?.modalidad !== original.contrato?.modalidad || otra.contrato?.tipo_interes !== original.contrato?.tipo_interes) d.push('pago de intereses')
  if (claveTitulares(otra) !== claveTitulares(original)) d.push('cotitulares')
  return d
}
export type VistaPreviaReemplazo = v.InferOutput<typeof VistaPreviaReemplazoSchema>

// ─── Reemplazar inversión de COOPERATIVA (Fase 4, 18/10/2026) ──────────────────────────────────────────────
// En una cooperativa el reemplazo cambia SOLO la cooperativa, la fecha comercial (el mes de la venta) y el comprobante;
// lo demás se copia de la original (para eso está «Corregir»). Decisiones de Miguel del 18/10/2026.
/** Vista previa (crm.reemplazar_inversion_cooperativa_vista_previa_fn): el mes de la venta y qué se negaría. Estricta. */
export const VistaPreviaReemplazoCooperativaSchema = v.strictObject({
  fuente_id: Uuid, cooperativa: v.picklist(COOPERATIVAS), es_inicial: v.boolean(), anulada: v.boolean(),
  venta_de_lead: v.boolean(),
  /** La original tiene comprobante (si no suben otro, la nueva se queda con ese). */
  comprobante: v.boolean(),
  // Una fila antigua puede no tener fecha comercial propia; el mes actual sale entonces de su alta.
  fecha_comercial_actual: v.nullable(FechaIso), mes_actual: FechaIso,
  fecha_comercial_resultante: FechaIso, mes_resultante: FechaIso,
  cambia_mes: v.boolean(), fecha_futura: v.boolean(), mes_sellado: v.boolean(), plazo_vencido: v.boolean(),
  /** Por qué la original no se reemplaza con ninguna fecha (anulada, aporte adicional, movimientos…); null si se puede. */
  no_reemplazable: v.nullable(v.string()),
})
export type VistaPreviaReemplazoCooperativa = v.InferOutput<typeof VistaPreviaReemplazoCooperativaSchema>
/** Lo IMPRESCINDIBLE del acuse: qué cierre quedó. Lo demás se lee aparte (ver `AcuseReemplazoAccesorios`). */
export const InversionCooperativaReemplazadaSchema = v.looseObject({
  ok: v.literal(true), fuente_id: Uuid, cierre_id: Uuid,
})
export const AcuseReemplazoCooperativaAccesorios = {
  cooperativa: v.nullable(v.picklist(COOPERATIVAS)),
  fecha_comercial: v.nullable(FechaIso),
}
/** Solo la inversión INICIAL de una cooperativa, real y vigente o vencida; el servidor decide igual. */
export function inversionReemplazableCooperativa(i: InversionFuente): boolean {
  return i.empresa !== 'avance' && i.es_inicial === true && !i.es_demo
    && (i.estado === 'vigente' || i.estado === 'activo' || i.estado === 'vencido')
}

/** Espejo del CHECK de crm.inversiones_eliminadas: length(btrim(motivo)) between 5 and 300. */
export const MOTIVO_ELIMINACION_MIN = 5
export const MOTIVO_ELIMINACION_MAX = 300
/** Caracteres como los cuenta Postgres (`length`): un emoji es uno, no dos unidades UTF-16. */
export function largoMotivoEliminacion(motivo: string): number {
  return Array.from(motivo.trim()).length
}
export function motivoEliminacionValido(motivo: string): boolean {
  const largo = largoMotivoEliminacion(motivo)
  return largo >= MOTIVO_ELIMINACION_MIN && largo <= MOTIVO_ELIMINACION_MAX
}
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
  mes: string
  moneda: '' | 'PEN' | 'USD'
  estado: '' | 'vigente' | 'vencido' | 'renovado' | 'retirado' | 'anulado_comercialmente' | 'sin_inversiones'
  contacto: '' | 'sin_restriccion' | 'no_contactar'
  porVencer: boolean
}
export const FILTROS_INVERSIONISTAS_INICIALES: FiltrosInversionistas = {
  pagina: 1, tamano: 25, texto: '', empresa: '', responsable: '',
  mes: '', moneda: '', estado: '', contacto: '', porVencer: false,
}

/** La respuesta incompleta se bloquea; nunca se convierte en una cartera vacía. */
export function validarPaginaInversionistas(pagina: CarteraInversionistas): boolean {
  const esperadas = Math.max(0, Math.min(pagina.tamano, pagina.total - (pagina.pagina - 1) * pagina.tamano))
  return pagina.filas.length === esperadas && new Set(pagina.filas.map(p => p.inversionista_id)).size === esperadas
}
