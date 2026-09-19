import { expect, test, type Page } from '@playwright/test'
import { abrirConversionAvance, irAMiCartera, loginReal, montarBackendReal, leadReal, UID } from './_helpers'

async function montarModo(page: Page, modo: () => string) {
  const politica = () => ({ id: 'politica-modo', version: 14, modo: modo(), tasa_base_nueva: 15, tope_tecnico: 28, vigencia_solicitud_dias: 1 })
  for (const rpc of ['resolver_tasa_fn', 'resolver_tasa_lead_fn']) {
    await page.route('**/rest/v1/rpc/' + rpc, (ruta) => ruta.fulfill({ json: {
      observacion_sin_aprobacion: true, cliente_id: ruta.request().postDataJSON().p_cliente_id ?? null, categoria: 'nuevo',
      tasa_base: 15, tasa_minima_sin_autorizacion: 0.01, regla: 'primera_inversion', contrato_origen: null,
      contratos_previos: 0, contratos_activos: 0, prioridad_bandeja: false, politica: politica(),
    } }))
  }
  await page.route('**/rest/v1/rpc/politica_rentabilidad_fn', (ruta) => ruta.fulfill({ json: {
    version: 1, observacion_sin_aprobacion: true, expected_version: 14, historial: [], observacion_activa_desde: null, puede_publicar: false,
    vigente: { ...politica(), vigente_desde: '2026-09-18T17:05:47Z', publicada_en: '2026-09-18T17:05:47Z',
      regla_renovacion: 'heredar', regla_upgrade: 'heredar', nota: null },
  } }))
}

for (const ancho of [1440, 390]) {
  test('observación registra 20% sin solicitud (' + ancho + 'px)', async ({ page }, info) => {
    await page.setViewportSize({ width: ancho, height: 940 })
    const backend = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
    await montarModo(page, () => 'observacion')
    let solicitudes = 0
    await page.route('**/rest/v1/rpc/solicitar_tasa_fn', async (ruta) => { solicitudes++; await ruta.fallback() })
    await loginReal(page, { esperarWorkspace: ancho >= 768 })
    if (ancho < 768) await page.goto('/#/mi-cartera')
    else await irAMiCartera(page)
    const cliente = ancho < 768
      ? page.getByRole('listitem').filter({ hasText: 'CLIENTE PORTAL UNO' })
      : page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })
    await cliente.getByRole('button', { name: /Registrar (primera|nueva) inversión/ }).click()
    const contrato = page.getByRole('dialog', { name: /Crear contrato de/ })
    await contrato.getByLabel('Categoría', { exact: true }).selectOption('nuevo')
    await contrato.getByLabel('Capital', { exact: true }).fill('20000')
    await expect(contrato.getByText('Observación · sin aprobación')).toBeVisible()
    await contrato.getByLabel('Tasa anual (%)').fill('20')
    await expect(contrato.getByRole('button', { name: 'Solicitar tasa superior' })).toHaveCount(0)
    await contrato.getByLabel('N° de contrato', { exact: true }).fill('000718')
    await contrato.getByRole('radio', { name: /BCP.*8901/i }).check()
    await contrato.getByLabel('Tasa anual (%)').scrollIntoViewIfNeeded()
    await contrato.screenshot({ path: info.outputPath('observacion-' + ancho + '.png') })
    await contrato.getByRole('button', { name: 'Crear contrato', exact: true }).click()
    await expect(page.getByRole('heading', { name: 'Contrato 2026-01-000718 creado' })).toBeVisible()
    expect(backend.contratos[0]?.tasa_anual).toBe(20)
    expect(solicitudes).toBe(0)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  })
}

test('el interruptor cambia un lead abierto sin cerrar sesión ni sustituir la tasa', async ({ page }) => {
  const lead = leadReal({ vendedor_id: UID, nombre_completo: 'QA INTERRUPTOR', dni: '71809001', etapa: 'propuesta_enviada', monto_estimado: 20000 })
  await montarBackendReal(page, { rolCrm: 'vendedor', leads: [lead] })
  let modo = 'enforcement'
  await montarModo(page, () => modo)
  await loginReal(page)
  await page.goto('/#/cartera')
  await page.getByRole('row', { name: 'Abrir ficha de ' + lead.nombre_completo, exact: true }).click()
  const ficha = page.getByRole('dialog', { name: lead.nombre_completo, exact: true })
  await expect(ficha.getByRole('button', { name: 'Solicitar tasa superior' })).toBeVisible()
  modo = 'observacion'
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange', { bubbles: true })))
  await expect(ficha.getByRole('button', { name: 'Solicitar tasa superior' })).toHaveCount(0)
  await ficha.getByLabel('Tasa anual (%)').fill('20')
  await expect(ficha.getByLabel('Tasa anual (%)')).not.toHaveAttribute('aria-invalid', 'true')
  modo = 'enforcement'
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange', { bubbles: true })))
  await expect(ficha.getByRole('button', { name: 'Solicitar tasa superior' })).toBeVisible()
  await expect(ficha.getByLabel('Tasa anual (%)')).toHaveValue('20')
  await expect(ficha.getByLabel('Tasa anual (%)')).toHaveAttribute('aria-invalid', 'true')
  // La entrada compartida permite elegir empresa. Avance comprueba la tasa
  // dentro de su contrato, sin impedir por esa tasa una inversión cooperativa.
  await expect(ficha.getByRole('button', { name: 'Convertir a cliente', exact: true })).toBeEnabled()
  const acceso = await abrirConversionAvance(page, ficha)
  await acceso.getByLabel('Correo de acceso Avance').fill('qa-interruptor@example.invalid')
  await acceso.getByLabel('Nombres', { exact: true }).fill('QA')
  await acceso.getByLabel('Apellidos', { exact: true }).fill('INTERRUPTOR')
  await acceso.getByLabel('Domicilio legal').fill('Calle de prueba 123, Miraflores, Lima, Lima')
  await acceso.getByRole('button', { name: 'Revisar acceso Avance' }).click()
  await acceso.getByRole('button', { name: 'Completar acceso Avance' }).click()
  const contrato = page.getByRole('dialog', { name: /Crear contrato de/ })
  await contrato.getByLabel('N° de contrato', { exact: true }).fill('000719')
  await contrato.getByRole('radio', { name: /BCP.*8901/i }).check()
  await expect(contrato.getByLabel('Capital', { exact: true })).toHaveValue('20000')
  await expect(contrato.getByLabel('Tasa anual (%)')).toHaveValue('20')
  await expect(contrato.getByLabel('Tasa anual (%)')).toHaveAttribute('aria-invalid', 'true')
  await expect(contrato.getByRole('button', { name: 'Revisar inversión' })).toBeDisabled()
  modo = 'observacion'
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange', { bubbles: true })))
  await expect(contrato.getByText('Observación · sin aprobación')).toBeVisible()
  await expect(contrato.getByLabel('Tasa anual (%)')).toHaveValue('20')
  await expect(contrato.getByLabel('Tasa anual (%)')).not.toHaveAttribute('aria-invalid', 'true')
  await expect(contrato.getByRole('button', { name: 'Revisar inversión' })).toBeEnabled()
})
