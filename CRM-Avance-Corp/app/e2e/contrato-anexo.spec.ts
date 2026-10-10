import { expect, test, type Page } from '@playwright/test'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { contratoReal, irAMiCartera, loginReal, montarBackendReal, UID, verTodaLaCartera } from './_helpers'

// Anexo de cronograma: documento APARTE que el analista imprime desde la ficha
// del contrato (Miguel, 28/09/2026). El contrato PDF no cambia. La Edge dibuja
// el anexo desde el snapshot sellado y lo entrega en JSON (base64 + hash); el
// navegador lo verifica y lo abre en una pestaña reservada en el clic.

/** La cuenta real cae en #/mi-cartera; el contrato cuelga del cliente y se
 *  expande CLIENTE PORTAL UNO para revelar su sub-fila (como contrato-detalle.spec). */
async function abrirDetalle(page: Page) {
  await loginReal(page)
  await irAMiCartera(page)
  await verTodaLaCartera(page)
  await page.getByRole('button', { name: /Expandir los contratos de CLIENTE PORTAL UNO/ }).click()
  await page.getByRole('row', { name: /Abrir detalle del contrato 2026-01-000777/ }).getByText('2026-01-000777').click()
  const detalle = page.getByRole('dialog', { name: /Contrato 2026-01-000777/ })
  await expect(detalle).toBeVisible()
  return detalle
}

const CONTRATO_ID = 'e0000000-0000-4000-8000-000000000777'
// Generados con el renderer de la Edge dentro de Docker; datos ficticios.
// Reproducir: supabase/scripts/banco-pdf-v10/generar-fixtures.ts.
const fixture = (nombre: string) => readFileSync(new URL(`./fixtures/contrato-correcciones/${nombre}`, import.meta.url))
const PDF = fixture('anexo-v2.pdf')
const sha256Hex = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex')

test('«Imprimir anexo de cronograma» pide solo la acción anexo y abre el PDF verificado en una pestaña', async ({ page }) => {
  await page.addInitScript(() => {
    const original = URL.createObjectURL.bind(URL)
    URL.createObjectURL = (objeto) => {
      if (objeto instanceof Blob && objeto.type === 'application/pdf') {
        (window as unknown as { pdfVerificado: Blob }).pdfVerificado = objeto
      }
      return original(objeto)
    }
  })
  await montarBackendReal(page, {
    rolCrm: 'vendedor',
    contratos: [
      // Régimen documental NUEVO (firmado tras el 19/08): la ficha ofrece el PDF
      // y, con él, el anexo. Un contrato anterior no ofrece ninguno de los dos.
      contratoReal({
        id: CONTRATO_ID,
        numero_contrato: '2026-01-000777',
        fecha_inicio: '2026-09-01',
        fecha_vencimiento: '2027-09-01',
        creado_por: UID,
        creado_en: new Date().toISOString(),
      }),
    ],
  })
  const solicitudes: unknown[] = []
  await page.route('**/functions/v1/crm-contrato-pdf-v2', async (route) => {
    const cuerpo = route.request().postDataJSON() as { action?: string }
    if (cuerpo.action !== 'anexo') return route.fallback()
    solicitudes.push(cuerpo)
    return route.fulfill({
      json: {
        anexo: {
          contrato_id: CONTRATO_ID,
          contrato_revision: 1,
          contrato_template_version: 'contrato-aep-17-v10',
          template: 'anexo-cronograma-v2',
          nombre_archivo: 'Anexo-2026-01-000777-CLIENTE-PORTAL-UNO.pdf',
          sha256: sha256Hex(PDF),
          bytes: PDF.length,
          pdf_base64: PDF.toString('base64'),
        },
      },
    })
  })
  const detalle = await abrirDetalle(page)
  await expect(detalle.getByRole('button', { name: 'Ver contrato PDF' })).toBeVisible()

  const boton = detalle.getByRole('button', { name: 'Imprimir anexo de cronograma' })
  const pestana = page.waitForEvent('popup')
  await boton.click()
  const nueva = await pestana
  // La pestaña se reserva EN el clic, antes de pedir nada al servidor.
  await expect.poll(() => nueva.title()).toBe('Preparando anexo de cronograma…')
  await expect.poll(() => solicitudes.length).toBe(1)
  await expect(boton).toBeEnabled()
  // Chromium sin visor de PDF (Docker) no navega a un blob application/pdf,
  // así que el éxito se mide por lo observable: la pestaña sigue abierta (el
  // error la cerraría) y no hay aviso de fallo.
  expect(nueva.isClosed()).toBe(false)
  expect(solicitudes).toEqual([{ action: 'anexo', contratoId: CONTRATO_ID }])
  // Ni «Ver» ni «Descargar» se dispararon: el anexo no toca el contrato.
  await expect(page.getByText(/No se pudo/)).toHaveCount(0)
  const hashRecibido = await page.evaluate(async () => {
    const blob = (window as unknown as { pdfVerificado: Blob }).pdfVerificado
    const digest = await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())
    return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
  })
  expect(hashRecibido).toBe(sha256Hex(PDF))
})

for (const version of [9, 10]) {
  test(`descarga los bytes reales del contrato v${version} sin regenerarlo`, async ({ page }) => {
    const bytes = fixture(`contrato-v${version}.pdf`)
    const jobId = '22222222-2222-4222-8222-222222222222'
    const path = `${CONTRATO_ID}/v2/${jobId}/contrato.pdf`
    const url = `http://127.0.0.1:59999/storage/v1/object/sign/contratos-generados/${path}?token=prueba-local`
    const metadata = {
      contrato_id: CONTRATO_ID, job_id: jobId, storage_bucket: 'contratos-generados',
      storage_path: path, nombre_archivo: 'Contrato-2026-01-000777.pdf',
      sha256: sha256Hex(bytes), bytes: bytes.length, template_version: `contrato-aep-17-v${version}`,
    }
    await montarBackendReal(page, {
      rolCrm: 'vendedor',
      contratos: [contratoReal({ id: CONTRATO_ID, numero_contrato: '2026-01-000777',
        fecha_inicio: '2026-09-01', fecha_vencimiento: '2027-09-01', creado_por: UID,
        creado_en: new Date().toISOString() })],
    })
    const solicitudes: string[] = []
    await page.route('**/functions/v1/crm-contrato-pdf-v2', (route) => {
      solicitudes.push((route.request().postDataJSON() as { action: string }).action)
      return route.fulfill({ json: { pdf: { ...metadata, estado: 'sellado', intentos: 1,
        lease_expira_en: null, reintentable: false, archivo: metadata }, url } })
    })
    await page.route('**/storage/v1/object/sign/contratos-generados/**', (route) =>
      route.fulfill({ contentType: 'application/pdf', body: bytes }))
    const detalle = await abrirDetalle(page)
    const descargando = page.waitForEvent('download')
    await detalle.getByRole('button', { name: 'Descargar contrato PDF' }).click()
    const descarga = await descargando
    expect(descarga.suggestedFilename()).toBe(metadata.nombre_archivo)
    const ruta = await descarga.path()
    expect(ruta).not.toBeNull()
    expect(readFileSync(ruta!).equals(bytes)).toBe(true)
    expect(solicitudes.length).toBeGreaterThan(0)
    expect(solicitudes.every((action) => action === 'status')).toBe(true)
  })
}

test('sin PDF sellado, el aviso del servidor se muestra y la pestaña reservada se cierra', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor',
    contratos: [
      contratoReal({
        id: CONTRATO_ID,
        numero_contrato: '2026-01-000777',
        fecha_inicio: '2026-09-01',
        fecha_vencimiento: '2027-09-01',
        creado_por: UID,
        creado_en: new Date().toISOString(),
      }),
    ],
  })
  await page.route('**/functions/v1/crm-contrato-pdf-v2', async (route) => {
    const cuerpo = route.request().postDataJSON() as { action?: string }
    if (cuerpo.action !== 'anexo') return route.fallback()
    return route.fulfill({
      status: 409,
      json: {
        error: 'El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF',
        codigo: 'ANEXO_SIN_PDF_SELLADO',
      },
    })
  })
  const detalle = await abrirDetalle(page)

  const pestana = page.waitForEvent('popup')
  await detalle.getByRole('button', { name: 'Imprimir anexo de cronograma' }).click()
  const nueva = await pestana
  await expect(
    page.getByText('El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF'),
  ).toBeVisible()
  await expect.poll(() => nueva.isClosed()).toBe(true)
  await expect(detalle.getByRole('button', { name: 'Imprimir anexo de cronograma' })).toBeEnabled()
})
