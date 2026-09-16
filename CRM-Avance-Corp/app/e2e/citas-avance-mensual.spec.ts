import { readFile } from 'node:fs/promises'
import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'
import { montarConsultaCitas } from './_citas'

test('avance mensual: fuentes, filtros, recorrido, monedas y detalle', async ({ page }, info) => {
  await page.clock.setFixedTime(new Date('2026-09-04T15:00:00Z'))
  await montarBackendReal(page)
  await montarConsultaCitas(page, undefined, 'mensual')
  await loginReal(page)
  await page.getByRole('button', { name: 'Citas', exact: true }).click()
  const tabla = page.getByRole('table', { name: /Leads, citas, entrevistas, depósito/ })
  const fila = tabla.getByRole('row', { name: /ANALISTA DE PRUEBA/ })
  await expect(fila).toContainText('60%')
  await expect(fila).toContainText('33.3%')
  await expect(tabla.getByRole('row', { name: /ANALISTA SIN CITAS/ })).toContainText('0%')
  await expect(page.getByRole('region', { name: 'Tabla de personas del flujo' })).toHaveCount(0)
  await page.getByRole('button', { name: 'Se hicieron clientes 1', exact: true }).click()
  await expect(page.getByRole('region', { name: 'Tabla de personas del flujo' })).toContainText('Convertido a cliente')
  await page.getByRole('button', { name: 'Ocultar personas' }).click()
  await page.getByLabel('Semana', { exact: true }).selectOption('4')
  await expect(fila).toContainText('60%')
  await expect(page.getByText('Esta tabla conserva el acumulado mensual', { exact: false })).toBeVisible()
  await expect(page.getByLabel('Moneda de los importes reales')).toHaveCount(0)
  await expect(fila.getByRole('cell').nth(5)).toHaveText('S/ 5,530')
  await expect(fila.getByRole('cell').nth(6)).toContainText('S/ 11,060')
  await expect(page.getByLabel('Capital del mes por moneda')).toContainText('S/ 2,000 · US$ 1,000')
  await expect(page.getByLabel('Capital del mes por moneda')).toContainText('TC S/ 3.53 (SBS · prom. 7d al 04/09/2026)')
  await page.getByRole('button', { name: /ANALISTA SIN CITAS/, exact: false }).click()
  const detalle = page.getByRole('dialog')
  await expect(detalle).toContainText('1 leads de registro manual')
  await detalle.getByRole('button', { name: 'Ver leads y citas' }).click()
  await expect(detalle).toContainText('PERSONA DE PRUEBA 14')
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: /Más filtros/ }).click()
  await page.getByLabel('Tipo de registro').selectOption('manual')
  await expect(tabla.getByRole('row', { name: /ANALISTA DE PRUEBA/ })).toHaveCount(0)
  await expect(tabla.getByRole('row', { name: /ANALISTA SIN CITAS/ })).toBeVisible()
  await page.getByRole('button', { name: 'Restablecer consulta' }).click()
  const descarga = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Exportar avance' }).click()
  const archivo = await descarga
  expect(archivo.suggestedFilename()).toBe('citas-avance-2026-09-PEN.csv')
  const csv = await readFile((await archivo.path())!, 'utf8')
  expect(csv).toContain('"5530","11060","PEN"')
  expect(csv).toContain('"2000","1000","3.53","SBS · prom. 7d al 04/09/2026","2026-09-04"')
  await page.getByRole('button', { name: /Más filtros/ }).click()
  for (const width of [1440, 1280, 768, 390]) {
    await page.setViewportSize({ width, height: 1000 })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    if (width < 768) {
      await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
      await page.mouse.move(width - 5, 200)
      await expect(page.getByRole('button', { name: 'Fijar menú abierto', exact: true })).toBeVisible()
      await page.getByLabel('Capital del mes por moneda').scrollIntoViewIfNeeded()
    }
    await page.screenshot({ path: info.outputPath(`citas-avance-crm-${width}.png`), fullPage: true })
  }
})


test('sin tipo de cambio conserva totales y actividad, explica la exportación y permite reintentar', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-09-04T15:00:00Z'))
  await montarBackendReal(page)
  await montarConsultaCitas(page, undefined, 'mensual')
  let fallar = true
  let intentos = 0
  let liberar!: () => void
  const espera = new Promise<void>(resolve => { liberar = resolve })
  await page.route('**/functions/v1/crm-tipo-cambio', async route => {
    const req = route.request()
    if (req.method() !== 'POST' || !req.postData()?.includes('fecha_corte')) return route.fallback()
    intentos++
    if (fallar) {
      await espera
      return route.fulfill({ status: 502, json: { message: 'Cotización no disponible' } })
    }
    return route.fallback()
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Citas', exact: true }).click()
  const tabla = page.getByRole('table', { name: /Leads, citas, entrevistas, depósito/ })
  const fila = tabla.getByRole('row', { name: /ANALISTA DE PRUEBA/ })
  await expect(page.getByText('Consultando el tipo de cambio para incluir dólares…')).toBeVisible()
  await expect(fila.getByRole('cell').nth(5)).toHaveText('Pendiente de TC')
  await expect(fila.getByRole('cell').nth(6)).toContainText('Pendiente de TC')
  await expect(fila).toContainText('60%')
  await expect(page.getByLabel('Capital del mes por moneda')).toHaveText('Capital del mes: S/ 2,000 · US$ 1,000')
  liberar()
  await expect(page.getByRole('button', { name: 'Reintentar tipo de cambio' })).toBeVisible()
  const descarga = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Exportar avance' }).click()
  const csv = await readFile((await (await descarga).path())!, 'utf8')
  expect(csv).toContain('"","","PEN"')
  expect(csv).toContain('"Estado del ticket","Estado de proyección"')
  expect(csv).toContain('"Falta el tipo de cambio para incluir dólares","Falta el tipo de cambio para incluir dólares"')
  expect(csv).toContain('"2000","1000","","",""')
  fallar = false
  await page.getByRole('button', { name: 'Reintentar tipo de cambio' }).click()
  await expect(fila.getByRole('cell').nth(5)).toHaveText('S/ 5,530')
  await expect(page.getByRole('button', { name: 'Reintentar tipo de cambio' })).toHaveCount(0)
  expect(intentos).toBeGreaterThanOrEqual(2)
})

test('cambiar de mes retira el TC anterior y recalcula el ticket con la cotización del cierre histórico', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-09-04T15:00:00Z'))
  await montarBackendReal(page)
  await montarConsultaCitas(page, undefined, 'mensual')
  let liberar!: () => void
  const espera = new Promise<void>(resolve => { liberar = resolve })
  await page.route('**/functions/v1/crm-tipo-cambio', async route => {
    if (!route.request().postData()?.includes('2026-08-31')) return route.fallback()
    await espera
    return route.fulfill({ json: { promedio: 4, fuente: 'SBS · prom. 7d', fecha_corte: '2026-08-31' } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Citas', exact: true }).click()
  const tabla = page.getByRole('table', { name: /Leads, citas, entrevistas, depósito/ })
  const fila = tabla.getByRole('row', { name: /ANALISTA DE PRUEBA/ })
  await expect(fila.getByRole('cell').nth(5)).toHaveText('S/ 5,530')
  const solicitud = page.waitForRequest(req => req.url().includes('/functions/v1/crm-tipo-cambio') && req.method() === 'POST' && req.postDataJSON()?.fecha_corte === '2026-08-31')
  await page.getByLabel('Mes', { exact: true }).fill('2026-08')
  await solicitud
  await expect(page.getByText('Consultando el tipo de cambio para incluir dólares…')).toBeVisible()
  await expect(fila.getByRole('cell').nth(5)).toHaveText('Pendiente de TC')
  await expect(page.getByText(/TC S\/ 3.53/)).toHaveCount(0)
  liberar()
  await expect(fila.getByRole('cell').nth(5)).toHaveText('S/ 6,000')
  await expect(fila.getByRole('cell').nth(6)).toContainText('S/ 6,000')
  await expect(fila.getByRole('cell').nth(6)).toContainText('Resultado del mes')
  await expect(page.getByLabel('Capital del mes por moneda')).toContainText('TC S/ 4 (SBS · prom. 7d al 31/08/2026)')
})
