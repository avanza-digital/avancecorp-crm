import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal, rankingAgostoReal } from './_helpers'

test('capital por origen muestra renovación y upgrade dentro de cartera en escritorio y móvil', async ({ page }, testInfo) => {
  await page.clock.setFixedTime(new Date('2026-09-28T15:00:00Z'))
  const foto = rankingAgostoReal()
  const vendedores = foto.cumplimientoMetas.vendedores as Array<{
    vendedor_id: string
    detalles: Array<{ categoria: string; moneda: string; capital_real: number }>
  }>
  for (const d of vendedores[0]!.detalles) {
    if (d.moneda === 'PEN') d.capital_real = d.categoria === 'upgrade' ? 20000 : 10000
  }
  await montarBackendReal(page, {
    rolCrm: 'gerencia', rolPortal: 'comercial',
    configuracionMetas: foto.configuracionMetas,
    cumplimientoMetas: foto.cumplimientoMetas,
    metricas: { conversionMensual: foto.conversionMensual, cosecha: foto.cosecha },
  })
  await page.route('**/rest/v1/rpc/ranking_origen_vendedor_fn', async (route) => {
    const consulta = route.request().postDataJSON()
    await route.fulfill({ json: {
      version: 1, periodo: consulta.p_periodo, vendedor_id: consulta.p_vendedor_id, disponible: true,
      filas: [
        { origen: 'formulario', capital_pen: 10000, capital_usd: 1000, contratos: 1, leads: 12, cierres: 1, conversion_pct: 8.33 },
        { origen: 'cartera', capital_pen: 30000, capital_usd: 0, contratos: 2, leads: 0, cierres: 0, conversion_pct: null },
      ],
    } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Ranking', exact: true }).click()
  await page.getByLabel('Mes calendario').fill('2026-08')
  await page.getByRole('tab', { name: 'Capital total', exact: true }).click()
  await page.getByRole('button', { name: 'Ver detalle de ANA AGOSTO', exact: true }).first().click()
  const ficha = page.getByRole('dialog')
  const cartera = ficha.getByRole('group', { name: 'Desglose de cartera' })
  await expect(cartera).toContainText('RenovaciónS/ 10,000')
  await expect(cartera).toContainText('UpgradeS/ 20,000')
  await expect(ficha.getByRole('region', { name: 'Capital y conversión por origen' })).toContainText('S/ 43,530')
  await page.screenshot({ path: testInfo.outputPath('cartera-desktop.png'), fullPage: true })
  await page.setViewportSize({ width: 390, height: 844 })
  await cartera.scrollIntoViewIfNeeded()
  await expect(cartera).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
  await page.screenshot({ path: testInfo.outputPath('cartera-mobile.png'), fullPage: true })
})
