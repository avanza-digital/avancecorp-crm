import { irAModulo } from './_navegacion'
import { expect, test } from '@playwright/test'
import { entrarDemo, loginReal, montarBackendReal } from './_helpers'
import { metricasMultiempresaDemo } from '../src/lib/demo-metricas-multiempresa'

test.use({ locale: 'es-PE' })

test('F7: Gerencia consulta empresas, moneda y tipo de capital en demo', async ({ page }) => {
  await entrarDemo(page, 'Gerencia')
  await irAModulo(page, 'Empresas')
  await expect(page.getByRole('heading', { name: 'Empresas', exact: true })).toBeVisible()
  await expect(page.getByText(/todas estas cifras son ficticias/)).toBeVisible()
  const capital = page.getByRole('table', { name: 'Capital por empresa y moneda' })
  await expect(capital.getByRole('row')).toHaveCount(5)
  await page.getByLabel('Moneda', { exact: true }).selectOption('USD')
  await expect(capital.getByRole('row')).toHaveCount(2)
  await expect(capital).toContainText('Avance')
  await expect(capital).not.toContainText('Qorilazo')
  await page.getByText('Ver contratos nuevos, renovaciones y upgrades', { exact: true }).click()
  await expect(page.getByRole('table', { name: 'Tipos de capital' })).toBeVisible()
})

test('F7: a 320 px las tablas desplazan dentro del panel', async ({ page }) => {
  await entrarDemo(page, 'Gerencia')
  await irAModulo(page, 'Empresas')
  await page.setViewportSize({ width: 320, height: 780 })
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByLabel('Mes de producción', { exact: true }).click()
  await expect(page.getByRole('table', { name: 'Capital por empresa y moneda' })).toBeVisible()
  const exceso = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
  expect(exceso).toBeLessThanOrEqual(1)
  await page.screenshot({ path: test.info().outputPath('f7-320.png'), fullPage: true })
  await page.getByRole('heading', { name: 'Inversionistas en el grupo', exact: true }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: test.info().outputPath('f7-320-personas.png'), fullPage: true })
})

test('F7: permiso de interfaz deniega el informe a Directorio', async ({ page }) => {
  await entrarDemo(page, 'Directorio')
  await expect(page.getByRole('button', { name: 'Empresas', exact: true })).toHaveCount(0)
  await page.goto('/#/informes-empresas')
  await expect(page.getByRole('table', { name: 'Capital por empresa y moneda' })).toHaveCount(0)
})

test('F7: ruta real OFF nunca pide datos; ON valida el contrato del servidor', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  let habilitada = false, solicitudes = 0, diferencia = false
  await page.route('**/rest/v1/rpc/metricas_multiempresa_estado_fn', route => route.fulfill({
    status: 200, contentType: 'application/json', body: JSON.stringify({ version: 1, habilitada }),
  }))
  await page.route('**/rest/v1/rpc/metricas_multiempresa_fn', route => {
    solicitudes++
    const { p_mes } = route.request().postDataJSON() as { p_mes: string }
    const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' }).format(new Date())
    const informe = metricasMultiempresaDemo(p_mes, hoy)
    if (diferencia) informe.conciliacion.push({
      empresa: 'prodelco', moneda: 'USD', capital_nucleo: 99.01, capital_informe: 0,
      operaciones_nucleo: 1, operaciones_informe: 0, diferencia_capital: -99.01,
      diferencia_operaciones: -1, diferencia_atribucion: -99.01,
    })
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(informe) })
  })
  await loginReal(page)
  await irAModulo(page, 'Empresas')
  await expect(page.getByText('Informe en preparación')).toBeVisible()
  expect(solicitudes).toBe(0)
  habilitada = true
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Capital por empresa y moneda' })).toBeVisible()
  await expect(page.getByText(/todas estas cifras son ficticias/)).toHaveCount(0)
  await page.screenshot({ path: test.info().outputPath('f7-escritorio.png'), fullPage: true })
  await page.getByRole('heading', { name: 'Inversionistas en el grupo', exact: true }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: test.info().outputPath('f7-escritorio-personas.png'), fullPage: true })
  // Un grupo ausente del informe debe llegar hasta la comparación; no se
  // descarta como respuesta inválida ni se presenta como conciliación correcta.
  diferencia = true
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(page.getByText('Hay diferencias que requieren revisión antes de aceptar el informe.')).toBeVisible()
  await page.getByText('Ver detalle de la comparación', { exact: true }).click()
  const comparacion = page.getByRole('table', { name: 'Comparación de cifras' })
  await expect(comparacion.getByRole('row', { name: /Prodelco USD/ })).toContainText('-99.01')
  await comparacion.scrollIntoViewIfNeeded()
  await page.screenshot({ path: test.info().outputPath('f7-comparacion.png'), fullPage: true })
  await page.route('**/rest/v1/rpc/metricas_multiempresa_fn', route => route.fulfill({
    status: 403, contentType: 'application/json', body: JSON.stringify({ code: '42501', message: 'No autorizado' }),
  }))
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(page.getByText('Informe no disponible')).toBeVisible()
  await expect(page.getByRole('table')).toHaveCount(0)
})
