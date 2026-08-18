import {
  generarContratoPdfBlob,
  nombreArchivoContrato,
  type ContratoPdfDatos,
} from './contrato-pdf'
import type { ArchivoContratoPdf } from './contrato-pdf-archivo'
import { sha256PdfHex, validarPdfBlob } from './contrato-pdf-archivo'
import { AUTH_CLEARED_EVENT } from './seguridad'

const archivos = new Map<string, ArchivoContratoPdf>()
const enCurso = new Map<string, Promise<ArchivoContratoPdf>>()
let epocaSesion = 0

export function limpiarArchivoPdfDemoParaPruebas(): void {
  epocaSesion++
  archivos.clear()
  enCurso.clear()
}

if (typeof window !== 'undefined') {
  window.addEventListener(AUTH_CLEARED_EVENT, limpiarArchivoPdfDemoParaPruebas)
}

export function obtenerContratoPdfDemo(contratoId: string): ArchivoContratoPdf | null {
  return archivos.get(contratoId) ?? null
}

/** Coalesce concurrencia y evita que una generación vieja repueble otra sesión. */
export async function archivarContratoPdfDemo(
  contratoId: string,
  datos: ContratoPdfDatos,
): Promise<ArchivoContratoPdf> {
  const existente = archivos.get(contratoId)
  if (existente) return existente
  const pendiente = enCurso.get(contratoId)
  if (pendiente) return pendiente

  const epoca = epocaSesion
  const generacion = (async () => {
    const blob = await generarContratoPdfBlob(datos)
    await validarPdfBlob(blob)
    const archivo: ArchivoContratoPdf = {
      contratoId,
      jobId: null,
      storagePath: `demo/${contratoId}/contrato.pdf`,
      nombreArchivo: nombreArchivoContrato(datos),
      templateVersion: 'demo-contrato-aep-17-v1',
      sha256: await sha256PdfHex(blob),
      bytes: blob.size,
      blob,
    }
    if (epoca === epocaSesion) archivos.set(contratoId, archivo)
    return archivo
  })()

  enCurso.set(contratoId, generacion)
  try {
    return await generacion
  } finally {
    if (enCurso.get(contratoId) === generacion) enCurso.delete(contratoId)
  }
}
