import { expect, test } from '@playwright/test'
import { abrirLead, entrarDemo, irAPipeline, leadReal, loginReal, montarBackendReal, montarConversionCompartida, UID } from './_helpers'

for (const documento of ['001234567', 'AB12345678']) {
  test(`el alta rechaza ${documento} sin convertirlo en un DNI recortado`, async ({ page }) => {
    await entrarDemo(page, 'Analista')
    await page.getByRole('button', { name: /nuevo lead/i }).click()
    const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
    await modal.getByLabel('Nombre completo *').fill('DOCUMENTO PRUEBA E2E')
    await modal.getByLabel('Teléfono *', { exact: true }).fill('987111444')
    await modal.getByLabel('Capital estimado *').fill('5000')
    await modal.getByLabel('Origen *').selectOption('referido')
    await modal.getByLabel('DNI').fill(documento)
    await expect(modal.getByLabel('DNI')).toHaveValue(documento)
    await modal.getByRole('button', { name: /crear lead/i }).click()
    await expect(modal.getByText('El DNI debe tener exactamente 8 dígitos')).toBeVisible()
    await expect(modal.getByLabel('DNI')).toHaveAttribute('aria-invalid', 'true')
    await expect(page.getByText(/Lead creado/)).toHaveCount(0)
  })

  test(`la ficha rechaza ${documento} sin guardar un DNI distinto`, async ({ page }) => {
    await entrarDemo(page, 'Analista')
    await irAPipeline(page)
    const ficha = await abrirLead(page, /JUAN PÉREZ ROJAS/)
    await ficha.getByRole('button', { name: 'Editar', exact: true }).click()
    await ficha.getByLabel('DNI').fill(documento)
    await expect(ficha.getByLabel('DNI')).toHaveValue(documento)
    await ficha.getByRole('button', { name: 'Guardar', exact: true }).click()
    await expect(ficha.getByRole('alert')).toHaveText('El DNI debe tener exactamente 8 dígitos')
    await expect(ficha.getByLabel('DNI')).toHaveAttribute('aria-invalid', 'true')
    await expect(page.getByText(/Cambios guardados/)).toHaveCount(0)
  })
}

for (const [tipo, numero] of [['CE', '001234567'], ['PASAPORTE', 'AB12345678']] as const) {
  test(`alta y conversión conservan ${tipo} completo`, async ({ page }) => {
    const estado = await montarBackendReal(page, { rolCrm: 'vendedor', leads: [] })
    await loginReal(page)
    await page.getByRole('button', { name: /nuevo lead/i }).click()
    const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
    await modal.getByLabel('Nombre completo *').fill('DOCUMENTO COMPLETO E2E')
    await modal.getByLabel('Teléfono *', { exact: true }).fill('987111444')
    await modal.getByLabel('Capital estimado *').fill('5000')
    await modal.getByLabel('Origen *').selectOption('referido')
    await modal.getByLabel('Tipo de documento').selectOption(tipo)
    await modal.getByLabel('Documento', { exact: true }).fill(numero)
    await modal.getByRole('button', { name: /crear lead/i }).click()
    await expect(page.getByText(/Lead creado —/)).toBeVisible()
    expect(estado.leads[0].documento).toEqual({ tipo, numero })
    expect(estado.leads[0].dni).toBeNull()
    // El alta abre automáticamente su ficha.
    const ficha = page.getByRole('dialog', { name: 'DOCUMENTO COMPLETO E2E', exact: true })
    await expect(ficha.getByText(numero, { exact: true })).toBeVisible()
    await montarConversionCompartida(page)
    await ficha.getByRole('button', { name: 'Convertir a cliente' }).click()
    const conversion = page.getByRole('dialog', { name: 'Registrar la inversión del lead' })
    await expect(conversion.getByLabel('Tipo de documento')).toHaveValue(tipo)
    await expect(conversion.getByLabel('Documento', { exact: true })).toHaveValue(numero)
    const peticion = page.waitForRequest('**/rpc/preparar_persona_lead_inversion_fn')
    await conversion.getByRole('button', { name: 'Continuar a Nueva inversión' }).click()
    expect((await peticion).postDataJSON()).toMatchObject({ p_tipo_documento: tipo, p_documento: numero })
    await expect(page.getByRole('button', { name: 'Avance', exact: true })).toBeVisible()
  })
}

test('editar añade un CE completo y muestra el tipo al volver a abrir', async ({ page }) => {
  const estado = await montarBackendReal(page, { leads: [leadReal({ vendedor_id: UID, dni: null })] })
  await loginReal(page)
  await irAPipeline(page)
  const ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await ficha.getByRole('button', { name: 'Editar', exact: true }).click()
  await ficha.getByLabel('Tipo de documento').selectOption('CE')
  await ficha.getByLabel('Documento', { exact: true }).fill('001234567')
  await ficha.getByRole('button', { name: 'Guardar', exact: true }).click()
  await expect(page.getByText('Cambios guardados', { exact: true })).toBeVisible()
  expect(estado.leads[0].documento).toEqual({ tipo: 'CE', numero: '001234567' })
  await ficha.getByRole('button', { name: 'Editar', exact: true }).click()
  await expect(ficha.getByLabel('Tipo de documento')).toHaveValue('CE')
  await expect(ficha.getByLabel('Documento', { exact: true })).toHaveValue('001234567')
  await expect(ficha.getByLabel('Documento', { exact: true })).toBeDisabled()
})

test('Administración corrige DNI reconocido a CE con motivo', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolPortal: 'admin', leads: [leadReal({
    vendedor_id: UID, dni: '12345678', documento: { tipo: 'DNI', numero: '12345678' },
  })] })
  await loginReal(page)
  await irAPipeline(page)
  const ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await ficha.getByRole('button', { name: 'Editar', exact: true }).click()
  await ficha.getByLabel('Tipo de documento').selectOption('CE')
  await ficha.getByLabel('Documento', { exact: true }).fill('001234567')
  await ficha.getByRole('button', { name: 'Guardar', exact: true }).click()
  await expect(ficha.getByRole('alert')).toContainText('Indica el motivo')
  expect(estado.llamadas.rpcEditarLead).toBe(0)
  await ficha.getByLabel('Motivo de la corrección del documento').fill('El documento presentado es CE')
  const peticion = page.waitForRequest('**/rpc/editar_lead_documento_fn')
  await ficha.getByRole('button', { name: 'Guardar', exact: true }).click()
  expect((await peticion).postDataJSON()).toMatchObject({ p_tipo: 'CE', p_documento: '001234567',
    p_identificador_anterior: estado.leads[0].id, p_motivo: 'El documento presentado es CE' })
  await expect(page.getByText('Cambios guardados', { exact: true })).toBeVisible()
  expect(estado.leads[0].dni).toBeNull()
})
