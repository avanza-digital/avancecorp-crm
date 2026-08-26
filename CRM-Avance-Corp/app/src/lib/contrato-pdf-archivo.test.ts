import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { FunctionsHttpError } from '@supabase/supabase-js'

const supabase = vi.hoisted(() => ({ invoke: vi.fn() }))

vi.mock('./supabase', () => ({
  sb: { functions: { invoke: supabase.invoke } },
}))

import {
  asegurarContratoPdfActualizado,
  archivarContratoPdfConfirmado,
  consultarEstadoContratoPdf,
  ContratoPdfNoSelladoError,
  eliminarContratoConPdf,
  obtenerContratoPdfArchivado,
} from './contrato-pdf-archivo'

const CONTRATO_ID = '8fffe71c-0abc-4c36-90fa-79fcbf4c3941'
const JOB_ID = '11111111-1111-4111-8111-111111111111'

async function sha256(blob: Blob): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function sellado(blob: Blob, overrides: Record<string, unknown> = {}) {
  const hash = await sha256(blob)
  const storagePath = `${CONTRATO_ID}/v2/${JOB_ID}/contrato.pdf`
  const metadata = {
    contrato_id: CONTRATO_ID,
    job_id: JOB_ID,
    storage_bucket: 'contratos-generados',
    storage_path: storagePath,
    nombre_archivo: 'Contrato-2026-01-000777.pdf',
    sha256: hash,
    bytes: blob.size,
    template_version: 'contrato-aep-17-v2',
  }
  return {
    pdf: {
      contrato_id: CONTRATO_ID,
      job_id: JOB_ID,
      estado: 'sellado',
      storage_bucket: 'contratos-generados',
      storage_path: storagePath,
      nombre_archivo: metadata.nombre_archivo,
      template_version: metadata.template_version,
      intentos: 1,
      lease_expira_en: null,
      reintentable: false,
      sha256: hash,
      bytes: blob.size,
      archivo: metadata,
      ...overrides,
    },
    url: 'https://local.invalid/storage/sign/contrato.pdf',
  }
}

function pendiente(estado: 'pendiente' | 'procesando' | 'error_reintentable' | 'integridad_bloqueada' = 'pendiente') {
  return {
    pdf: {
      contrato_id: CONTRATO_ID,
      job_id: JOB_ID,
      estado,
      storage_bucket: 'contratos-generados',
      storage_path: `${CONTRATO_ID}/v2/${JOB_ID}/contrato.pdf`,
      nombre_archivo: 'Contrato-2026-01-000777.pdf',
      template_version: 'contrato-aep-17-v2',
      intentos: estado === 'pendiente' ? 0 : 1,
      lease_expira_en: estado === 'procesando' ? '2026-08-17T23:59:59Z' : null,
      reintentable: estado !== 'procesando',
      sha256: null,
      bytes: null,
      archivo: null,
    },
  }
}

describe('cliente del archivo contractual server-side', () => {
  beforeEach(() => {
    supabase.invoke.mockReset()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('ensure envía únicamente JSON pequeño y nunca FormData, snapshot, hash o bytes', async () => {
    const blob = new Blob(['%PDF-1.7\nbytes legales'], {
      type: 'application/pdf',
    })
    supabase.invoke.mockResolvedValue({
      data: await sellado(blob),
      error: null,
    })
    const bytes = await blob.arrayBuffer()
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementation(
        async () =>
          new Response(bytes.slice(0), {
            status: 200,
            headers: { 'Content-Type': 'application/pdf' },
          }),
      ),
    )

    await archivarContratoPdfConfirmado(CONTRATO_ID)

    expect(supabase.invoke).toHaveBeenCalledOnce()
    const [nombre, opciones] = supabase.invoke.mock.calls[0]!
    expect(nombre).toBe('crm-contrato-pdf-v2')
    expect(opciones.body).toEqual({
      action: 'ensure',
      contratoId: CONTRATO_ID,
    })
    expect(opciones.body).not.toBeInstanceOf(FormData)
    expect(JSON.stringify(opciones.body)).not.toMatch(/snapshot|sha256|pdf|nombreArchivo|template/i)
  })

  it('la corrección puede sellar la revisión vigente sin descargar sus bytes', async () => {
    const blob = new Blob(['%PDF-1.7\nrevisión corregida'], {
      type: 'application/pdf',
    })
    supabase.invoke.mockResolvedValue({
      data: await sellado(blob),
      error: null,
    })
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    const estado = await asegurarContratoPdfActualizado(CONTRATO_ID)

    expect(estado.estado).toBe('sellado')
    expect(estado.jobId).toBe(JOB_ID)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('el hard-delete usa exclusivamente la Edge y valida su confirmación', async () => {
    supabase.invoke.mockResolvedValue({
      data: { ok: true, contratoId: CONTRATO_ID, archivosEliminados: 3 },
      error: null,
    })

    await expect(eliminarContratoConPdf(CONTRATO_ID)).resolves.toEqual({
      contratoId: CONTRATO_ID,
      archivosEliminados: 3,
    })
    expect(supabase.invoke).toHaveBeenCalledWith('crm-contrato-pdf-v2', {
      body: { action: 'delete', contratoId: CONTRATO_ID },
    })
  })

  it('rechaza una confirmación de borrado correspondiente a otro contrato', async () => {
    supabase.invoke.mockResolvedValue({
      data: {
        ok: true,
        contratoId: '99999999-9999-4999-8999-999999999999',
        archivosEliminados: 1,
      },
      error: null,
    })

    await expect(eliminarContratoConPdf(CONTRATO_ID)).rejects.toThrow(/confirmación.*formato/i)
  })

  it('rechaza un identificador alterado antes de solicitar el documento', async () => {
    await expect(archivarContratoPdfConfirmado(CONTRATO_ID.toUpperCase())).rejects.toThrow(
      /No pudimos identificar este contrato/i,
    )
    expect(supabase.invoke).not.toHaveBeenCalled()
  })

  it('expone el estado durable sin intentar descargar mientras no esté sellado', async () => {
    supabase.invoke.mockResolvedValue({
      data: pendiente('procesando'),
      error: null,
    })
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    const estado = await consultarEstadoContratoPdf(CONTRATO_ID)
    const archivo = await obtenerContratoPdfArchivado(CONTRATO_ID)

    expect(estado.estado).toBe('procesando')
    expect(estado.jobId).toBe(JOB_ID)
    expect(archivo).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('ensure no presenta un pendiente como éxito y conserva si es reintentable', async () => {
    supabase.invoke.mockResolvedValue({
      data: pendiente('error_reintentable'),
      error: null,
    })

    const intento = archivarContratoPdfConfirmado(CONTRATO_ID)
    await expect(intento).rejects.toBeInstanceOf(ContratoPdfNoSelladoError)
    await expect(intento).rejects.toMatchObject({
      estado: 'error_reintentable',
      reintentable: true,
    })
  })

  it('recupera por URL firmada y comprueba ruta, tamaño y hash antes de entregar bytes', async () => {
    const blob = new Blob(['%PDF-1.7\nbytes legales'], {
      type: 'application/pdf',
    })
    supabase.invoke.mockResolvedValue({
      data: await sellado(blob),
      error: null,
    })
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(await blob.arrayBuffer(), {
        status: 200,
        headers: { 'Content-Type': 'application/pdf' },
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const archivo = await obtenerContratoPdfArchivado(CONTRATO_ID)

    expect(fetchMock).toHaveBeenCalledWith('https://local.invalid/storage/sign/contrato.pdf', {
      credentials: 'omit',
      cache: 'no-store',
    })
    expect(archivo).toMatchObject({
      contratoId: CONTRATO_ID,
      jobId: JOB_ID,
      templateVersion: 'contrato-aep-17-v2',
      bytes: blob.size,
    })
    expect(await archivo?.blob.text()).toBe(await blob.text())
  })

  it('rechaza metadatos con ruta de otro job aunque el hash coincida', async () => {
    const blob = new Blob(['%PDF-1.7\noriginal'], { type: 'application/pdf' })
    const respuesta = await sellado(blob)
    respuesta.pdf.archivo.storage_path = `${CONTRATO_ID}/v2/22222222-2222-4222-8222-222222222222/contrato.pdf`
    respuesta.pdf.storage_path = respuesta.pdf.archivo.storage_path
    supabase.invoke.mockResolvedValue({ data: respuesta, error: null })

    await expect(obtenerContratoPdfArchivado(CONTRATO_ID)).rejects.toThrow(
      /No pudimos confirmar el archivo de este contrato/i,
    )
  })

  it('rechaza una descarga distinta del documento confirmado', async () => {
    const esperado = new Blob(['%PDF-1.7\noriginal'], {
      type: 'application/pdf',
    })
    const alterado = new Blob(['%PDF-1.7\nalterado'], {
      type: 'application/pdf',
    })
    const respuesta = await sellado(esperado)
    // Mismo tamaño para demostrar que también se verifica SHA-256.
    expect(alterado.size).toBe(esperado.size)
    supabase.invoke.mockResolvedValue({ data: respuesta, error: null })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(await alterado.arrayBuffer(), {
          status: 200,
          headers: { 'Content-Type': 'application/pdf' },
        }),
      ),
    )

    await expect(obtenerContratoPdfArchivado(CONTRATO_ID)).rejects.toThrow(
      /No pudimos confirmar el documento descargado/i,
    )
  })

  it('la descarga inmediata y la posterior son idénticas byte a byte', async () => {
    const blob = new Blob(['%PDF-1.7\nmisma versión legal'], {
      type: 'application/pdf',
    })
    const respuesta = await sellado(blob)
    supabase.invoke.mockResolvedValue({ data: respuesta, error: null })
    const bytes = await blob.arrayBuffer()
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementation(
        async () =>
          new Response(bytes.slice(0), {
            status: 200,
            headers: { 'Content-Type': 'application/pdf' },
          }),
      ),
    )

    const inmediato = await archivarContratoPdfConfirmado(CONTRATO_ID)
    const posterior = await obtenerContratoPdfArchivado(CONTRATO_ID)

    expect(new Uint8Array(await posterior!.blob.arrayBuffer())).toEqual(
      new Uint8Array(await inmediato.blob.arrayBuffer()),
    )
    expect(posterior!.sha256).toBe(inmediato.sha256)
  })

  it('propaga el diagnóstico JSON de una respuesta HTTP de la Edge Function', async () => {
    const respuesta = new Response(JSON.stringify({ error: 'Actor fuera de cartera' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    })
    supabase.invoke.mockResolvedValue({
      data: null,
      error: new FunctionsHttpError(respuesta),
    })

    await expect(obtenerContratoPdfArchivado(CONTRATO_ID)).rejects.toThrow('Actor fuera de cartera')
  })

  it('conserva el estado durable de integridad aunque la Edge responda HTTP 409', async () => {
    const bloqueado = pendiente('integridad_bloqueada')
    bloqueado.pdf.reintentable = false
    const respuesta = new Response(JSON.stringify(bloqueado), {
      status: 409,
      headers: { 'Content-Type': 'application/json' },
    })
    supabase.invoke.mockResolvedValue({
      data: null,
      error: new FunctionsHttpError(respuesta),
    })

    const intento = archivarContratoPdfConfirmado(CONTRATO_ID)
    await expect(intento).rejects.toBeInstanceOf(ContratoPdfNoSelladoError)
    await expect(intento).rejects.toMatchObject({
      estado: 'integridad_bloqueada',
      reintentable: false,
    })
  })
})
