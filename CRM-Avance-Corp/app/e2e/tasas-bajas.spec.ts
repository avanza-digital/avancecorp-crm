import { expect, test, type Page } from '@playwright/test'
import { abrirConversionAvance, irAMiCartera, leadReal, loginReal, montarBackendReal, UID } from './_helpers'

async function politicaNueva(page: Page) {
  for (const rpc of ['resolver_tasa_fn', 'resolver_tasa_lead_fn']) {
    await page.route(`**/rest/v1/rpc/${rpc}`, (ruta) => ruta.fulfill({ json: {
      cliente_id: ruta.request().postDataJSON().p_cliente_id ?? null, categoria: 'nuevo',
      tasa_base: 15, tasa_minima_sin_autorizacion: 0.01, regla: 'primera_inversion', contrato_origen: null,
      contratos_previos: 0, contratos_activos: 0, prioridad_bandeja: false,
      politica: { id: 'politica-baja', version: 13, modo: 'enforcement', tasa_base_nueva: 15, tope_tecnico: 28, vigencia_solicitud_dias: 1 },
    } }))
  }
}

for (const ancho of [1440, 390]) {
  test(`tasa menor viaja desde lead hasta el contrato sin solicitud (${ancho}px)`, async ({ page }, info) => {
    await page.setViewportSize({ width: ancho, height: 940 })
    const lead = leadReal({ vendedor_id: UID, nombre_completo: 'QA TASA INFERIOR', dni: '71309001', etapa: 'propuesta_enviada', monto_estimado: 20000 })
    await montarBackendReal(page, { rolCrm: 'vendedor', leads: [lead] })
    await politicaNueva(page)
    let solicitudes = 0
    let tasaConvertida: number | undefined
    await page.route('**/rest/v1/rpc/solicitar_tasa_fn', async (ruta) => { solicitudes++; await ruta.fallback() })
    await page.route('**/functions/v1/crm-convertir-lead', async (ruta) => {
      tasaConvertida = ruta.request().postDataJSON().condiciones_tasa.tasa_anual
      await ruta.fallback()
    })
    await loginReal(page, { esperarWorkspace: ancho >= 768 })
    await page.goto('/#/cartera')
    await page.getByRole('row', { name: `Abrir ficha de ${lead.nombre_completo}`, exact: true }).click()
    const ficha = page.getByRole('dialog', { name: lead.nombre_completo, exact: true })
    const tasa = ficha.getByLabel('Tasa anual (%)')
    await expect(tasa).toBeEditable()
    await tasa.fill('16')
    await expect(ficha.getByRole('button', { name: 'Convertir a cliente', exact: true })).toBeDisabled()
    await tasa.fill('12,5')
    await expect(ficha.getByRole('button', { name: 'Convertir a cliente', exact: true })).toBeEnabled()
    await ficha.getByTestId('condiciones-tasa-lead').screenshot({ path: info.outputPath(`tasa-menor-${ancho}.png`) })
    const convertir = await abrirConversionAvance(page, ficha)
    await expect(convertir.getByRole('region', { name: 'Condiciones confirmadas de inversión' })).toContainText('12.5% anual')
    await convertir.locator('#cv-correo').fill('qa-tasa@example.invalid')
    await convertir.locator('#cv-domicilio').fill('Calle de prueba 123, Miraflores, Lima, Lima')
    await convertir.locator('#cv-pen-banco').selectOption('BCP')
    await convertir.locator('#cv-pen-tipo').selectOption('ahorros')
    await convertir.locator('#cv-pen-numero').fill('19112345678901')
    await convertir.locator('#cv-pen-cci').fill('00219112345678901234')
    await convertir.getByRole('button', { name: 'Convertir a cliente', exact: true }).click()
    const contrato = page.getByRole('dialog', { name: /Crear contrato de/ })
    await expect(contrato).toBeVisible()
    await expect(contrato.getByLabel('Tasa anual (%)')).toHaveValue('12.5')
    expect(tasaConvertida).toBe(12.5)
    expect(solicitudes).toBe(0)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  })
}

test('nueva inversión de cliente existente guarda 13.5 y calcula su cronograma', async ({ page }) => {
  const backend = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await politicaNueva(page)
  let tasaGuardada: number | undefined
  let primeraCuota: number | undefined
  await page.route('**/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2', async (ruta) => {
    const body = ruta.request().postDataJSON()
    tasaGuardada = body.p_contrato.tasa_anual
    primeraCuota = body.p_cronograma.find((cuota: { tipo: string }) => cuota.tipo === 'cuota')?.monto_programado
    await ruta.fallback()
  })
  await loginReal(page)
  await irAMiCartera(page)
  await page.getByRole('row', { name: /CLIENTE PORTAL UNO/ }).getByRole('button', { name: /Registrar (primera|nueva) inversión/ }).click()
  const contrato = page.getByRole('dialog', { name: /Crear contrato de/ })
  await contrato.getByLabel('Categoría', { exact: true }).selectOption('nuevo')
  await contrato.getByLabel('Capital', { exact: true }).fill('20000')
  await contrato.getByLabel('Tasa anual (%)').fill('13.5')
  await contrato.getByLabel('N° de contrato', { exact: true }).fill('000713')
  await contrato.getByRole('radio', { name: /BCP.*8901/i }).check()
  await contrato.getByRole('button', { name: 'Crear contrato', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Contrato 2026-01-000713 creado' })).toBeVisible()
  expect(tasaGuardada).toBe(13.5)
  expect(primeraCuota).toBeGreaterThan(0)
  expect(backend.contratos[0]?.tasa_anual).toBe(13.5)
})
