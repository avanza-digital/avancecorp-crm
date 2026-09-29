import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { FunctionsHttpError } from '@supabase/supabase-js'

const supabase = vi.hoisted(() => ({ invoke: vi.fn() }))

vi.mock('./supabase', () => ({
  sb: { functions: { invoke: supabase.invoke } },
}))

import {
  AnexoCronogramaError,
  asegurarContratoPdfActualizado,
  archivarContratoPdfConfirmado,
  consultarEstadoContratoPdf,
  ContratoPdfNoSelladoError,
  eliminarContratoConPdf,
  imprimirAnexoCronograma,
  obtenerContratoPdfArchivado,
} from './contrato-pdf-archivo'

const CONTRATO_ID = '8fffe71c-0abc-4c36-90fa-79fcbf4c3941'
const JOB_ID = '11111111-1111-4111-8111-111111111111'

async function sha256(blob: Blob): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

async function sellado(
  blob: Blob,
  overrides: Record<string, unknown> = {}) {
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
      data: { ok: true, contratoId: CONTRATO_ID, auditoriaId: JOB_ID, archivosConservados: 3 },
      error: null,
    })

    await expect(eliminarContratoConPdf(CONTRATO_ID)).resolves.toEqual({
      contratoId: CONTRATO_ID,
      auditoriaId: JOB_ID,
      archivosConservados: 3,
    })
    expect(supabase.invoke).toHaveBeenCalledWith('crm-contrato-pdf-v2', {
      body: { action: 'delete-audited', contratoId: CONTRATO_ID },
    })
  })

  it('rechaza una confirmación de borrado correspondiente a otro contrato', async () => {
    supabase.invoke.mockResolvedValue({
      data: {
        ok: true,
        contratoId: '99999999-9999-4999-8999-999999999999',
        archivosConservados: 1,
      },
      error: null,
    })

    await expect(eliminarContratoConPdf(CONTRATO_ID)).rejects.toThrow(/confirmación.*formato/i)
  })

  it('rechaza UUID con mayúsculas antes de invocar la Edge', async () => {
    await expect(archivarContratoPdfConfirmado(CONTRATO_ID.toUpperCase())).rejects.toThrow(/canónico/i)
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

    await expect(obtenerContratoPdfArchivado(CONTRATO_ID)).rejects.toThrow(/metadatos contradictorios/i)
  })

  it('rechaza una descarga cuyos bytes no coinciden con el ledger legal', async () => {
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

    await expect(obtenerContratoPdfArchivado(CONTRATO_ID)).rejects.toThrow(/bytes.*no coinciden/i)
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

// ── Anexo de cronograma (documento aparte, desde el snapshot sellado) ────────

describe('anexo de cronograma imprimible', () => {
  beforeEach(() => {
    supabase.invoke.mockReset()
  })

  async function respuestaAnexo(contenido = '%PDF-1.7\nanexo de cronograma', overrides: Record<string, unknown> = {}) {
    const blob = new Blob([contenido], { type: 'application/pdf' })
    const bytes = new Uint8Array(await blob.arrayBuffer())
    return {
      anexo: {
        contrato_id: CONTRATO_ID,
        contrato_revision: 1,
        contrato_template_version: 'contrato-aep-17-v9',
        template: 'anexo-cronograma-v1',
        nombre_archivo: 'Anexo-2026-01-000777-CLIENTE-PRUEBA.pdf',
        sha256: await sha256(blob),
        bytes: blob.size,
        pdf_base64: btoa(String.fromCharCode(...bytes)),
        ...overrides,
      },
    }
  }

  it('pide la acción «anexo» con JSON mínimo y entrega el PDF verificado por hash y tamaño', async () => {
    supabase.invoke.mockResolvedValue({ data: await respuestaAnexo(), error: null })

    const anexo = await imprimirAnexoCronograma(CONTRATO_ID)

    expect(supabase.invoke).toHaveBeenCalledWith('crm-contrato-pdf-v2', {
      body: { action: 'anexo', contratoId: CONTRATO_ID },
    })
    expect(anexo.nombreArchivo).toBe('Anexo-2026-01-000777-CLIENTE-PRUEBA.pdf')
    expect(anexo.template).toBe('anexo-cronograma-v1')
    expect(anexo.contratoRevision).toBe(1)
    expect(anexo.blob.type).toBe('application/pdf')
    expect(await anexo.blob.text()).toBe('%PDF-1.7\nanexo de cronograma')
  })

  it('rechaza un anexo cuyo hash o tamaño no coincide con lo declarado', async () => {
    supabase.invoke.mockResolvedValue({
      data: await respuestaAnexo(undefined, { sha256: 'f'.repeat(64) }),
      error: null,
    })
    await expect(imprimirAnexoCronograma(CONTRATO_ID)).rejects.toThrow('hash')

    supabase.invoke.mockResolvedValue({
      data: await respuestaAnexo(undefined, { bytes: 9 }),
      error: null,
    })
    await expect(imprimirAnexoCronograma(CONTRATO_ID)).rejects.toThrow('tamaño')
  })

  it('rechaza el anexo de otro contrato y respuestas con claves inesperadas', async () => {
    supabase.invoke.mockResolvedValue({
      data: await respuestaAnexo(undefined, { contrato_id: '11111111-1111-4111-8111-111111111111' }),
      error: null,
    })
    await expect(imprimirAnexoCronograma(CONTRATO_ID)).rejects.toThrow('otro contrato')

    supabase.invoke.mockResolvedValue({
      data: await respuestaAnexo(undefined, { url: 'https://x.invalid' }),
      error: null,
    })
    await expect(imprimirAnexoCronograma(CONTRATO_ID)).rejects.toThrow('formato esperado')
  })

  it('expone el código de negocio de la Edge (sin PDF sellado, sin snapshot, fuera de cartera)', async () => {
    const respuesta = new Response(
      JSON.stringify({
        error: 'El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF',
        codigo: 'ANEXO_SIN_PDF_SELLADO',
      }),
      { status: 409, headers: { 'Content-Type': 'application/json' } },
    )
    supabase.invoke.mockResolvedValue({ data: null, error: new FunctionsHttpError(respuesta) })

    const intento = imprimirAnexoCronograma(CONTRATO_ID)
    await expect(intento).rejects.toBeInstanceOf(AnexoCronogramaError)
    await expect(intento).rejects.toMatchObject({
      codigo: 'ANEXO_SIN_PDF_SELLADO',
      message: 'El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF',
    })
  })

  it('rechaza UUID no canónico antes de invocar la Edge', async () => {
    await expect(imprimirAnexoCronograma(CONTRATO_ID.toUpperCase())).rejects.toThrow('canónico')
    expect(supabase.invoke).not.toHaveBeenCalled()
  })
})
