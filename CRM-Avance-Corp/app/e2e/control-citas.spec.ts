import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

test('Superadmin abre Control de Citas, guarda un borrador y lo recupera al recargar', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'coordinador', rolPortal: 'superadmin' })
  let configuracion: unknown = { version_actual: 0, ultimo: null, historial: [] }
  await page.route('**/rest/v1/rpc/control_citas_configuracion_fn', route => route.fulfill({ json: configuracion }))
  await page.route('**/rest/v1/rpc/guardar_control_citas_fn', async route => {
    const body = route.request().postDataJSON()
    expect(body.p_version_esperada).toBe(0)
    expect(body.p_configuracion.citas_por_lead).toBe(1.5)
    expect(body.p_configuracion.mostrar_meta_citas).toBe(false)
    const ultimo = { version: 1, configuracion: body.p_configuracion, guardado_por: '90000000-0000-4000-8000-000000000001', guardado_en: '2026-09-11T21:00:00Z', estado: 'borrador', nota: body.p_nota }
    configuracion = { version_actual: 1, ultimo, historial: [ultimo] }
    await route.fulfill({ json: configuracion })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Control de Citas', exact: true }).click()
  await expect(page.getByLabel('Citas por lead')).toHaveValue('1,25')
  await page.getByLabel('Citas por lead').fill('1,50')
  await page.getByRole('button', { name: 'Guardar borrador' }).click()
  await expect(page.getByRole('status')).toContainText('Todavía no está aplicado')
  await page.reload()
  await expect(page.getByLabel('Citas por lead')).toHaveValue('1,5')
  await page.getByText('Historial de borradores', { exact: true }).click()
  await expect(page.getByRole('list', { name: 'Historial de borradores de Citas' })).toContainText('Versión 1')
})

test('Superadmin recibe un estado honesto cuando falta instalar el guardado', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'coordinador', rolPortal: 'superadmin' })
  await page.route('**/rest/v1/rpc/control_citas_configuracion_fn', route => route.fulfill({ status: 404, json: { code: 'PGRST202', message: 'No function' } }))
  await loginReal(page)
  await page.getByRole('button', { name: 'Control de Citas', exact: true }).click()
  await expect(page.getByRole('alert')).toContainText('aún no está habilitado')
  await expect(page.getByRole('button', { name: 'Guardar borrador' })).toHaveCount(0)
})

test('conflicto: conserva la edición hasta que Superadmin decide descartarla', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'coordinador', rolPortal: 'superadmin' })
  let consulta: unknown = { version_actual: 0, ultimo: null, historial: [] }
  await page.route('**/rest/v1/rpc/control_citas_configuracion_fn', route => route.fulfill({ json: consulta }))
  await page.route('**/rest/v1/rpc/guardar_control_citas_fn', async route => {
    const body = route.request().postDataJSON()
    const ultimo = { version: 1, configuracion: { ...body.p_configuracion, citas_por_lead: 1.75 }, guardado_por: '90000000-0000-4000-8000-000000000001', guardado_en: '2026-09-11T21:00:00Z', estado: 'borrador', nota: null }
    consulta = { version_actual: 1, ultimo, historial: [ultimo] }
    await route.fulfill({ status: 409, json: { code: 'PT409', message: 'Conflicto' } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Control de Citas', exact: true }).click()
  const campo = page.getByLabel('Citas por lead')
  await campo.fill('1,50')
  await page.getByRole('button', { name: 'Guardar borrador' }).click()
  await expect(page.getByText('Hay una versión más reciente.', { exact: false })).toBeVisible()
  await expect(campo).toHaveValue('1,50')
  await page.getByRole('button', { name: 'Cargar último borrador' }).click()
  await page.getByRole('button', { name: 'Conservar mi edición' }).click()
  await expect(campo).toHaveValue('1,50')
  await page.getByRole('button', { name: 'Cargar último borrador' }).click()
  await page.getByRole('button', { name: 'Descartar cambios y cargar' }).click()
  await expect(campo).toHaveValue('1,75')
})

test('vista local: edición, teclado, persistencia y móvil sin desbordamiento', async ({ page }) => {
  await page.goto('/prototypes/control-citas.html')
  await expect(page.getByLabel('Citas por lead')).toHaveValue('1,25')
  await page.getByLabel('Citas por lead').fill('1,40')
  await page.getByText('Reglas de avance', { exact: false }).click()
  await page.getByLabel('Cómo contar las entrevistas').selectOption('personas_unicas')
  await page.getByRole('button', { name: 'Guardar borrador' }).click()
  await expect(page.getByRole('status')).toContainText('esta vista de prueba')
  await page.reload()
  await expect(page.getByLabel('Citas por lead')).toHaveValue('1,4')
  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByText('Reglas de avance', { exact: false }).focus()
  await page.keyboard.press('Enter')
  await expect(page.getByLabel('Cómo contar las entrevistas')).toBeVisible()
  await expect(page.getByLabel('Cómo contar las entrevistas')).toHaveValue('personas_unicas')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
})
