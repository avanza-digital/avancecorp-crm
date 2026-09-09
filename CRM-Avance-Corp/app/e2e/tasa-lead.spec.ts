import { expect, test, type Page } from '@playwright/test'
import { leadReal, loginReal, montarBackendReal, UID } from './_helpers'

const lead = leadReal({ vendedor_id: UID, nombre_completo: 'QA TASA ANTES DEL ALTA', dni: '70909001', etapa: 'propuesta_enviada', monto_estimado: 20000 })
async function abrir(page: Page) {
  await page.goto('/#/cartera')
  await page.getByRole('row', { name: `Abrir ficha de ${lead.nombre_completo}`, exact: true }).click()
  return page.getByRole('dialog', { name: lead.nombre_completo, exact: true })
}

for (const ancho of [1440, 390]) {
  test(`solicitar y recibir una tasa desde el lead (${ancho}px), sin alta prematura`, async ({ page }, info) => {
    await page.setViewportSize({ width: ancho, height: 940 })
    await montarBackendReal(page, { rolCrm: 'vendedor', leads: [lead] })
    let solicitud: Record<string, unknown> | null = null
    let altas = 0
    await page.route('**/functions/v1/crm-convertir-lead', async (route) => { altas++; await route.fallback() })
    await page.route('**/rest/v1/rpc/solicitudes_tasa_lead_fn', async (route) => {
      expect(route.request().postDataJSON().p_lead_id).toBe(lead.id)
      await route.fulfill({ json: solicitud ? [solicitud] : [] })
    })
    await page.route('**/rest/v1/rpc/solicitar_tasa_fn', async (route) => {
      const i = route.request().postDataJSON().p_solicitud
      expect(i.lead_id).toBe(lead.id)
      expect(i.cliente_id ?? null).toBeNull()
      solicitud = {
        ...i, id: 'd7090000-0000-4000-8000-000000000001', cliente_id: null, cliente_nombre: lead.nombre_completo,
        estado: 'pendiente', estado_efectivo: 'pendiente', vigente: true, contrato_origen_numero: null,
        tasa_base: 15, regla_base: 'primera_inversion', tasa_maxima_autorizada: null, motivo_resolucion: null,
        solicitada_por: UID, solicitante_nombre: 'ANALISTA QA', solicitada_en: new Date().toISOString(),
        vence_en: new Date(Date.now() + 86400000).toISOString(), resuelta_por: null, resuelta_en: null, contrato_id: null,
        es_mia: true, puede_resolver: false, puede_responder: false,
      }
      await route.fulfill({ json: solicitud })
    })
    await loginReal(page, { esperarWorkspace: ancho >= 768 })
    await expect(page.getByRole('heading', { level: 1, name: 'Hoy', exact: true })).toBeVisible()
    let ficha = await abrir(page)
    await expect(ficha.getByRole('button', { name: /Convertir a cliente/ })).toBeEnabled()
    await ficha.getByRole('button', { name: 'Solicitar tasa superior' }).click()
    await ficha.getByLabel('Tasa solicitada (%)').fill('18')
    await ficha.getByLabel('Motivo comercial').fill('Referido con inversión prevista de largo plazo')
    const tasaBox = await ficha.getByLabel('Tasa solicitada (%)').boundingBox()
    const motivoBox = await ficha.getByLabel('Motivo comercial').boundingBox()
    expect(tasaBox && motivoBox && tasaBox.x < motivoBox.x).toBeTruthy()
    await ficha.screenshot({ path: info.outputPath(`solicitud-${ancho}.png`) })
    await ficha.getByRole('button', { name: 'Enviar a Gerencia' }).click()
    await expect(ficha.getByRole('button', { name: /Convertir a cliente/ })).toBeDisabled()
    await expect(ficha.getByText('Pendiente de Gerencia', { exact: true })).toBeVisible()
    expect(altas).toBe(0)
    await ficha.getByRole('button', { name: 'Cerrar ficha' }).click()
    ficha = await abrir(page)
    await expect(ficha.getByRole('button', { name: /Convertir a cliente/ })).toBeDisabled()
    solicitud = { ...solicitud, estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 18,
      resuelta_por: 'd7090000-0000-4000-8000-000000000002', resuelta_en: new Date().toISOString() }
    await page.reload()
    ficha = await abrir(page)
    await expect(ficha.getByLabel('Tasa anual (%)')).toHaveValue('18')
    await expect(ficha.getByRole('button', { name: /Convertir a cliente/ })).toBeEnabled()
    await ficha.screenshot({ path: info.outputPath(`aprobada-${ancho}.png`) })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    expect(altas).toBe(0)
  })
}
