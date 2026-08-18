import type { ContratoPdfDatos } from './contrato-pdf'
import type { ArchivoContratoPdf } from './contrato-pdf-archivo'

/** Frontera lazy: un build productivo elimina esta rama y no empaqueta pdfmake. */
export async function archivarContratoPdfDemoHabilitado(
  contratoId: string,
  datos: ContratoPdfDatos,
): Promise<ArchivoContratoPdf> {
  if (!(import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true')) {
    throw new Error('El archivo PDF demo no está disponible en este build.')
  }
  const { archivarContratoPdfDemo } = await import('./contrato-pdf-demo')
  return archivarContratoPdfDemo(contratoId, datos)
}
