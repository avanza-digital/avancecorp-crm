import { beforeEach, describe, expect, it, vi } from 'vitest'
import { AUTH_CLEARED_EVENT } from './seguridad'
import { DATOS_PDF_DEMO } from './demo-clientes'

const generarContratoPdfBlob = vi.hoisted(() => vi.fn())

vi.mock('./contrato-pdf', async (importActual) => {
  const actual = await importActual<typeof import('./contrato-pdf')>()
  return { ...actual, generarContratoPdfBlob }
})

import {
  archivarContratoPdfDemo,
  limpiarArchivoPdfDemoParaPruebas,
  obtenerContratoPdfDemo,
} from './contrato-pdf-demo'

describe('archivo PDF aislado del demo', () => {
  beforeEach(() => {
    limpiarArchivoPdfDemoParaPruebas()
    generarContratoPdfBlob.mockReset()
  })

  it('coalesce dos generaciones concurrentes y la primera versión gana', async () => {
    let resolver!: (blob: Blob) => void
    generarContratoPdfBlob.mockReturnValue(new Promise<Blob>((resolve) => { resolver = resolve }))
    const datos = DATOS_PDF_DEMO['dc-ct-a']!

    const primero = archivarContratoPdfDemo('demo-mismo-id', datos)
    const segundo = archivarContratoPdfDemo('demo-mismo-id', datos)
    resolver(new Blob(['%PDF-1.7\núnico'], { type: 'application/pdf' }))

    const [a, b] = await Promise.all([primero, segundo])
    expect(generarContratoPdfBlob).toHaveBeenCalledOnce()
    expect(a).toBe(b)
    expect(obtenerContratoPdfDemo('demo-mismo-id')).toBe(a)
  })

  it('una generación vieja no repuebla la caché después de cambiar de sesión', async () => {
    const resoluciones: Array<(blob: Blob) => void> = []
    generarContratoPdfBlob.mockImplementation(() => new Promise<Blob>((resolve) => {
      resoluciones.push(resolve)
    }))
    const datos = DATOS_PDF_DEMO['dc-ct-a']!

    const sesionA = archivarContratoPdfDemo('demo-colision', datos)
    limpiarArchivoPdfDemoParaPruebas()
    const sesionB = archivarContratoPdfDemo('demo-colision', datos)

    await vi.waitUntil(() => resoluciones.length === 2)
    resoluciones[0]!(new Blob(['%PDF-1.7\nsesión A'], { type: 'application/pdf' }))
    resoluciones[1]!(new Blob(['%PDF-1.7\nsesión B'], { type: 'application/pdf' }))
    const [archivoA, archivoB] = await Promise.all([sesionA, sesionB])

    expect(await archivoA.blob.text()).toContain('sesión A')
    expect(await archivoB.blob.text()).toContain('sesión B')
    expect(obtenerContratoPdfDemo('demo-colision')).toBe(archivoB)
    expect(generarContratoPdfBlob).toHaveBeenCalledTimes(2)
  })

  it('el evento de logout elimina los bytes de la sesión demo terminada', async () => {
    generarContratoPdfBlob.mockResolvedValue(
      new Blob(['%PDF-1.7\nsesión terminada'], { type: 'application/pdf' }),
    )
    await archivarContratoPdfDemo('demo-logout', DATOS_PDF_DEMO['dc-ct-a']!)
    expect(obtenerContratoPdfDemo('demo-logout')).not.toBeNull()

    window.dispatchEvent(new Event(AUTH_CLEARED_EVENT))

    expect(obtenerContratoPdfDemo('demo-logout')).toBeNull()
  })

  it('rechaza bytes demo que no sean PDF antes de congelarlos', async () => {
    generarContratoPdfBlob.mockResolvedValue(new Blob(['no es pdf'], { type: 'text/plain' }))

    await expect(
      archivarContratoPdfDemo('demo-invalido', DATOS_PDF_DEMO['dc-ct-a']!),
    ).rejects.toThrow(/PDF válido/i)
    expect(obtenerContratoPdfDemo('demo-invalido')).toBeNull()
  })
})
