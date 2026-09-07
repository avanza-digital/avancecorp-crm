import { expect, test } from '@playwright/test'
import { metricasReunionesDemo } from '../src/lib/demo-inteligencia-comercial'
import { loginReal, metricasReunionesReal, montarBackendReal } from './_helpers'

test('Citas concilia responsables y explica las bases recibidas sin sumar cierres anteriores', async ({ page }, testInfo) => {
  const datos = metricasReunionesDemo('2026-09-01', '2026-09-07')
  // Un responsable histórico deja el desglose vigente, pero sus citas permanecen.
  datos.responsables.pop()
  await montarBackendReal(page, { metricas: { reuniones: datos } })
  await loginReal(page)
  await page.getByRole('button', { name: 'Citas', exact: true }).click()
  const heroe = page.locator('[data-gi-hero]')
  await expect(heroe).toContainText('80.6%')
  await expect(heroe).toContainText('58 de 72 citas computables')
  await expect(heroe).toContainText('6 próximas dentro del período')
  await expect(heroe).toContainText('Vencidas sin resultado3')
  await expect(heroe).not.toContainText('87.9%')
  await expect(page.getByRole('row', { name: 'Fuera del desglose actual 26 15 1 —' })).toBeVisible()
  await expect(page.getByRole('row', { name: 'Total del período 82 58 3 —' })).toBeVisible()
  await page.getByText('23 de 28 computables', { exact: true }).click()
  await expect(page.getByText('28 vencidas. Excluidas: 0 canceladas por sistema, 0 por otro asesor y 0 reprogramadas. 1 próximas dentro del período.')).toBeVisible()
  await page.getByText('Ver bases y asistencia', { exact: true }).click()
  await expect(page.getByText('58 de 66 citas con asistencia o inasistencia registrada. 8 no asistieron.')).toBeVisible()
  await expect(page.getByText('17 de 58 prospectos atendidos')).toBeVisible()
  await expect(page.getByText('Con cierre anterior a la hora programada: 1. Se muestran aparte.')).toBeVisible()
  await page.getByText('Qué cierres y capital incluye', { exact: true }).click()
  await expect(page.getByText(/El seguimiento incluye cierres posteriores al período/)).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Resultado registrado de la cita' })).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('citas-bases-desktop.png'), fullPage: true, animations: 'disabled' })

  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
  for (const nombre of ['Resultados por analista', 'Gráfico de cierres posteriores por origen']) {
    const region = page.getByRole('region', { name: nombre, exact: true })
    await region.focus()
    await page.keyboard.press('ArrowRight')
    await expect.poll(() => region.evaluate((element) => element.scrollLeft)).toBeGreaterThan(0)
  }
  await page.screenshot({ path: testInfo.outputPath('citas-bases-mobile.png'), fullPage: true, animations: 'disabled' })
})

test('Citas identifica la ausencia de bases en respuestas anteriores del servidor', async ({ page }) => {
  await montarBackendReal(page, { metricas: { reuniones: metricasReunionesReal() } })
  await loginReal(page)
  await page.getByRole('button', { name: 'Citas', exact: true }).click()
  await expect(page.locator('[data-gi-hero]')).toContainText('6 realizadas · base no disponible')
  await page.getByText('Qué cierres y capital incluye', { exact: true }).click()
  await expect(page.getByText('El detalle de cierres anteriores no está disponible.')).toBeVisible()
  await expect(page.getByText(/Con cierre anterior a la hora programada:/)).toHaveCount(0)
})
