import { readFile } from 'node:fs/promises'
import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'
import sellado from '../test-fixtures/capital-valorado/citas-sellado.json' with { type: 'json' }
import pendiente from '../test-fixtures/capital-valorado/citas-pendiente.json' with { type: 'json' }
import sinCorte from '../test-fixtures/capital-valorado/citas-sin-corte.json' with { type: 'json' }

const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }

test('Citas y CSV conservan el capital sellado con otra cotización en escritorio y móvil', async ({ page }, info) => {
  await page.clock.setFixedTime(new Date('2026-10-16T17:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  let tasa = 3.1
  await page.route('**/rest/v1/rpc/citas_gerencia_consulta_v2_fn', route => route.fulfill({ headers: CORS, json: sellado }))
  await page.route('**/functions/v1/crm-tipo-cambio', route => route.fulfill({ headers: CORS, json: { promedio: tasa, fuente: 'BCRP' } }))
  await loginReal(page)
  await page.getByRole('button', { name: 'Citas', exact: true }).click()
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 900 })
    const fila = page.getByRole('table', { name: /Leads, citas, entrevistas, depósito/ }).getByRole('row', { name: /Persona sintética 2/ })
    await expect(fila.getByRole('cell').nth(5)).toHaveText('S/ 76,000')
    await expect(page.getByText(/Capital en soles con TC fijado por venta/)).toContainText('Mes sellado')
    await expect(page.getByRole('button', { name: 'Reintentar tipo de cambio' })).toHaveCount(0)
    await fila.getByRole('button', { name: /Persona sintética 2/ }).click()
    const detalle = page.getByRole('dialog')
    await expect(detalle).toContainText('US$ 20,000')
    await expect(detalle).toContainText('S/ 76,000')
    await page.getByRole('button', { name: 'Cerrar detalle del analista' }).click()
    const descarga = page.waitForEvent('download')
    await page.getByRole('button', { name: 'Exportar avance' }).click()
    const archivo = await descarga
    expect(archivo.suggestedFilename()).toBe('citas-avance-2026-10-PEN.csv')
    const csv = await readFile((await archivo.path())!, 'utf8')
    expect(csv).toContain('Capital confirmado en soles')
    expect(csv).toContain('"76000"')
    expect(csv).toContain(sellado.gestion.valoracion.corte_id)
    expect(csv).toContain('TC fijado por venta')
    expect(csv).not.toContain('"3.1"')
    if (width===390) await page.screenshot({ path: info.outputPath('citas-capital-corte-movil.png'), fullPage: true })
    tasa = 3.8
    await page.reload()
    await expect(fila.getByRole('cell').nth(5)).toHaveText('S/ 76,000')
  }
})

test('Citas distingue el último corte pendiente de la ausencia del primer corte', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-10-16T17:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  let primera = false
  await page.route('**/rest/v1/rpc/citas_gerencia_consulta_v2_fn', route => route.fulfill({ headers: CORS, json: primera ? sinCorte : pendiente }))
  await loginReal(page)
  await page.getByRole('button', { name: 'Citas', exact: true }).click()
  const fila = page.getByRole('table', { name: /Leads, citas, entrevistas, depósito/ }).getByRole('row', { name: /Persona sintética 2/ })
  await expect(fila.getByRole('cell').nth(5)).toHaveText('S/ 70,000')
  await expect(page.getByText(/2 operaciones por incorporar/)).toBeVisible()
  primera = true
  await page.reload()
  await expect(page.getByText('El ticket y la proyección están pendientes del primer corte completo de valoración.')).toBeVisible()
  await expect(page.getByText(/Aún no hay un corte completo/)).toBeVisible()
  await expect(page.getByRole('table', { name: /Leads, citas, entrevistas, depósito/ })).not.toContainText('S/ 70,000')
})
