import * as v from 'valibot'
import { FunctionsHttpError } from '@supabase/supabase-js'
import { sb } from './supabase'

export const CONTRATO_PDF_BUCKET = 'contratos-generados'
export const CONTRATO_PDF_EDGE = 'crm-contrato-pdf-v2'

export const ESTADOS_CONTRATO_PDF = [
  'sin_reserva',
  'pendiente',
  'procesando',
  'subido_verificado',
  'sellado',
  'error_reintentable',
  'integridad_bloqueada',
] as const

export type EstadoContratoPdf = (typeof ESTADOS_CONTRATO_PDF)[number]

export interface ArchivoContratoPdf {
  contratoId: string
  jobId: string | null
  storagePath: string
  nombreArchivo: string
  templateVersion: string
  sha256: string
  bytes: number
  blob: Blob
}

export interface EstadoContratoPdfServidor {
  contratoId: string
  jobId: string | null
  estado: EstadoContratoPdf
  intentos: number
  leaseExpiraEn: string | null
  reintentable: boolean
  sha256: string | null
  bytes: number | null
  archivo: ArchivoMetadata | null
}

interface ArchivoMetadata {
  contrato_id: string
  job_id?: string | null | undefined
  storage_bucket: string
  storage_path: string
  nombre_archivo: string
  sha256: string
  bytes: number
  template_version: string
  generado_en?: string | undefined
}

const UUID_CANONICO_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

const ArchivoMetadataSchema = v.strictObject({
  contrato_id: v.pipe(v.string(), v.regex(UUID_CANONICO_RE)),
  job_id: v.optional(v.nullable(v.pipe(v.string(), v.regex(UUID_CANONICO_RE)))),
  storage_bucket: v.literal(CONTRATO_PDF_BUCKET),
  storage_path: v.pipe(v.string(), v.minLength(1)),
  nombre_archivo: v.pipe(v.string(), v.minLength(5)),
  sha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
  bytes: v.pipe(v.number(), v.integer(), v.minValue(1)),
  template_version: v.pipe(v.string(), v.minLength(1)),
  generado_en: v.optional(v.string()),
})

const PdfEstadoSchema = v.strictObject({
  contrato_id: v.pipe(v.string(), v.regex(UUID_CANONICO_RE)),
  job_id: v.nullable(v.pipe(v.string(), v.regex(UUID_CANONICO_RE))),
  estado: v.picklist(ESTADOS_CONTRATO_PDF),
  storage_bucket: v.nullable(v.string()),
  storage_path: v.nullable(v.string()),
  nombre_archivo: v.nullable(v.string()),
  template_version: v.nullable(v.string()),
  intentos: v.pipe(v.number(), v.integer(), v.minValue(0)),
  lease_expira_en: v.nullable(v.string()),
  reintentable: v.boolean(),
  sha256: v.nullable(v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/))),
  bytes: v.nullable(v.pipe(v.number(), v.integer(), v.minValue(1))),
  archivo: v.nullable(ArchivoMetadataSchema),
})

const EdgeRespuestaSchema = v.strictObject({
  pdf: PdfEstadoSchema,
  url: v.optional(v.pipe(v.string(), v.url())),
})

const EliminacionRespuestaSchema = v.strictObject({
  ok: v.literal(true),
  contratoId: v.pipe(v.string(), v.regex(UUID_CANONICO_RE)),
  archivosEliminados: v.pipe(v.number(), v.integer(), v.minValue(0)),
})

type PdfEstadoWire = v.InferOutput<typeof PdfEstadoSchema>
type EdgeRespuesta = v.InferOutput<typeof EdgeRespuestaSchema>

export class ContratoPdfNoSelladoError extends Error {
  readonly estado: EstadoContratoPdf
  readonly reintentable: boolean

  constructor(estado: EstadoContratoPdf, reintentable: boolean) {
    const mensaje =
      estado === 'integridad_bloqueada'
        ? 'El documento requiere revisión administrativa antes de estar disponible.'
        : 'El documento sigue en preparación. Intenta nuevamente en unos momentos.'
    super(mensaje)
    this.name = 'ContratoPdfNoSelladoError'
    this.estado = estado
    this.reintentable = reintentable
  }
}

function clienteSupabase() {
  if (!sb) throw new Error('No se puede acceder al documento del contrato en este momento.')
  return sb
}

function exigirContratoIdCanonico(contratoId: string): void {
  if (!UUID_CANONICO_RE.test(contratoId)) {
    throw new Error('No pudimos identificar este contrato. Actualiza la vista e inténtalo nuevamente.')
  }
}

export async function sha256PdfHex(blob: Blob): Promise<string> {
  const digest = await globalThis.crypto.subtle.digest('SHA-256', await blob.arrayBuffer())
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

export async function validarPdfBlob(blob: Blob): Promise<void> {
  if (blob.type !== 'application/pdf') throw new Error('No se recibió un documento válido.')
  const cabecera = new TextDecoder().decode(await blob.slice(0, 5).arrayBuffer())
  if (cabecera !== '%PDF-') throw new Error('El archivo recibido no es un documento válido.')
}

function mensajeEstado(estado: EstadoContratoPdf): string {
  switch (estado) {
    case 'pendiente':
      return 'Pendiente'
    case 'procesando':
      return 'En preparación'
    case 'subido_verificado':
      return 'Preparado para validación final'
    case 'error_reintentable':
      return 'No se pudo preparar; puedes reintentar'
    case 'integridad_bloqueada':
      return 'Requiere revisión administrativa'
    case 'sellado':
      return 'Listo'
    case 'sin_reserva':
      return 'Documento anterior sin copia archivada'
  }
}

export function etiquetaEstadoContratoPdf(estado: EstadoContratoPdf): string {
  return mensajeEstado(estado)
}

async function invocarEdge(action: 'ensure' | 'status', contratoId: string): Promise<EdgeRespuesta> {
  exigirContratoIdCanonico(contratoId)
  const { data, error } = await clienteSupabase().functions.invoke(CONTRATO_PDF_EDGE, {
    body: { action, contratoId },
  })
  if (error) {
    let mensaje = error.message || 'No se pudo acceder al archivo contractual privado.'
    if (error instanceof FunctionsHttpError) {
      try {
        const cuerpo = (await error.context.clone().json()) as unknown
        const durable = v.safeParse(EdgeRespuestaSchema, cuerpo)
        if (durable.success && durable.output.pdf.contrato_id === contratoId) {
          return durable.output
        }
        if (
          cuerpo != null &&
          typeof cuerpo === 'object' &&
          'error' in cuerpo &&
          typeof cuerpo.error === 'string' &&
          cuerpo.error.trim()
        ) {
          mensaje = cuerpo.error
        }
      } catch {
        // La respuesta HTTP puede no ser JSON; conservamos el diagnóstico SDK.
      }
    }
    throw new Error(mensaje)
  }
  const resultado = v.safeParse(EdgeRespuestaSchema, data)
  if (!resultado.success) {
    throw new Error('La respuesta del archivo contractual no tiene el formato esperado.')
  }
  if (resultado.output.pdf.contrato_id !== contratoId) {
    throw new Error('No pudimos confirmar el documento de este contrato. Intenta nuevamente.')
  }
  return resultado.output
}

function estadoPublico(pdf: PdfEstadoWire): EstadoContratoPdfServidor {
  return {
    contratoId: pdf.contrato_id,
    jobId: pdf.job_id,
    estado: pdf.estado,
    intentos: pdf.intentos,
    leaseExpiraEn: pdf.lease_expira_en,
    reintentable: pdf.reintentable,
    sha256: pdf.sha256,
    bytes: pdf.bytes,
    archivo: pdf.archivo,
  }
}

async function descargarUrlFirmada(url: string): Promise<Blob> {
  const respuesta = await fetch(url, { credentials: 'omit', cache: 'no-store' })
  if (!respuesta.ok) throw new Error('No se pudo descargar el documento del contrato.')
  return respuesta.blob()
}

function rutaMetadataValida(contratoId: string, jobId: string | null, storagePath: string): boolean {
  if (jobId) return storagePath === `${contratoId}/v2/${jobId}/contrato.pdf`
  // Compatibilidad de solo lectura para ledgers v1 ya sellados.
  return storagePath === `${contratoId}/contrato.pdf`
}

async function archivoValidado(
  contratoId: string,
  pdf: PdfEstadoWire,
  url: string | undefined,
): Promise<ArchivoContratoPdf> {
  const metadata = pdf.archivo
  if (pdf.estado !== 'sellado' || !metadata || !url) {
    throw new ContratoPdfNoSelladoError(pdf.estado, pdf.reintentable)
  }
  const jobId = metadata.job_id ?? pdf.job_id
  if (
    metadata.contrato_id !== contratoId ||
    jobId !== pdf.job_id ||
    metadata.storage_bucket !== CONTRATO_PDF_BUCKET ||
    !rutaMetadataValida(contratoId, jobId, metadata.storage_path) ||
    pdf.storage_bucket !== CONTRATO_PDF_BUCKET ||
    pdf.storage_path !== metadata.storage_path ||
    pdf.nombre_archivo !== metadata.nombre_archivo ||
    pdf.template_version !== metadata.template_version ||
    pdf.sha256 !== metadata.sha256 ||
    pdf.bytes !== metadata.bytes
  ) {
    throw new Error('No pudimos confirmar el archivo de este contrato. Intenta nuevamente.')
  }

  const blob = await descargarUrlFirmada(url)
  await validarPdfBlob(blob)
  if (blob.size !== metadata.bytes) {
    throw new Error('No pudimos confirmar el documento descargado. Intenta nuevamente.')
  }
  if ((await sha256PdfHex(blob)) !== metadata.sha256) {
    throw new Error('No pudimos confirmar el documento descargado. Intenta nuevamente.')
  }
  return {
    contratoId,
    jobId,
    storagePath: metadata.storage_path,
    nombreArchivo: metadata.nombre_archivo,
    templateVersion: metadata.template_version,
    sha256: metadata.sha256,
    bytes: metadata.bytes,
    blob,
  }
}

export async function consultarEstadoContratoPdf(contratoId: string): Promise<EstadoContratoPdfServidor> {
  const respuesta = await invocarEdge('status', contratoId)
  return estadoPublico(respuesta.pdf)
}

export async function obtenerContratoPdfArchivado(contratoId: string): Promise<ArchivoContratoPdf | null> {
  const respuesta = await invocarEdge('status', contratoId)
  if (respuesta.pdf.estado !== 'sellado') return null
  return archivoValidado(contratoId, respuesta.pdf, respuesta.url)
}

/** Solicita al servidor asegurar el job; el navegador nunca genera ni aporta bytes. */
export async function archivarContratoPdfConfirmado(contratoId: string): Promise<ArchivoContratoPdf> {
  const respuesta = await invocarEdge('ensure', contratoId)
  return archivoValidado(contratoId, respuesta.pdf, respuesta.url)
}

/** Dispara la generación server-side de la revisión vigente sin descargarla. */
export async function asegurarContratoPdfActualizado(contratoId: string): Promise<EstadoContratoPdfServidor> {
  const respuesta = await invocarEdge('ensure', contratoId)
  return estadoPublico(respuesta.pdf)
}

/**
 * Hard-delete administrado: la Edge revalida Admin/Superadmin, elimina primero
 * los objetos privados y recién entonces confirma el borrado en la base.
 */
export async function eliminarContratoConPdf(
  contratoId: string,
): Promise<{ contratoId: string; archivosEliminados: number }> {
  exigirContratoIdCanonico(contratoId)
  const { data, error } = await clienteSupabase().functions.invoke(CONTRATO_PDF_EDGE, {
    body: { action: 'delete', contratoId },
  })
  if (error) {
    let mensaje = error.message || 'No se pudo eliminar el contrato y sus archivos.'
    if (error instanceof FunctionsHttpError) {
      try {
        const cuerpo = (await error.context.clone().json()) as unknown
        if (
          cuerpo != null &&
          typeof cuerpo === 'object' &&
          'error' in cuerpo &&
          typeof cuerpo.error === 'string' &&
          cuerpo.error.trim()
        )
          mensaje = cuerpo.error
      } catch {
        // Conservamos el diagnóstico del SDK si el cuerpo no es JSON.
      }
    }
    throw new Error(mensaje)
  }
  const resultado = v.safeParse(EliminacionRespuestaSchema, data)
  if (!resultado.success || resultado.output.contratoId !== contratoId) {
    throw new Error('La confirmación de eliminación no tiene el formato esperado.')
  }
  return {
    contratoId: resultado.output.contratoId,
    archivosEliminados: resultado.output.archivosEliminados,
  }
}

export function descargarArchivoContratoPdf(archivo: ArchivoContratoPdf): void {
  const url = URL.createObjectURL(archivo.blob)
  const enlace = document.createElement('a')
  enlace.href = url
  enlace.download = archivo.nombreArchivo
  enlace.rel = 'noopener'
  document.body.appendChild(enlace)
  enlace.click()
  enlace.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 30_000)
}

/** Debe llamarse sincrónicamente desde el click para conservar user activation. */
export function abrirVentanaContratoPdf(): Window {
  const ventana = window.open('about:blank', '_blank')
  if (!ventana) throw new Error('El navegador bloqueó la ventana del contrato PDF.')
  ventana.opener = null
  ventana.document.title = 'Preparando contrato PDF…'
  ventana.document.body.textContent = 'Verificando el archivo contractual privado…'
  return ventana
}

export function verArchivoContratoPdf(archivo: ArchivoContratoPdf, ventana: Window = abrirVentanaContratoPdf()): void {
  const url = URL.createObjectURL(archivo.blob)
  ventana.opener = null
  ventana.location.replace(url)
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000)
}
