import { expect, test } from '@playwright/test'
import { bloquearSupabase, entrarDemo } from './_helpers'

test('Gerencia: accesos prioritarios, grupos por teclado y regreso por historial', async ({ page }, testInfo) => {
  const solicitudes = await bloquearSupabase(page)
  await entrarDemo(page, 'Gerencia')
  await expect(page.getByRole('heading', { name: 'Resumen', exact: true })).toBeVisible()
  const menu = page.locator('aside').getByRole('navigation')
  await expect(menu.getByRole('button')).toHaveText([
    'Resumen', 'Facturación', 'Ranking', 'Citas', 'Gestión Diaria',
    'Metas y cumplimiento', 'Cartera', 'Análisis', 'Operación', 'Administración',
  ])
  await expect(page.getByRole('heading', { name: 'Resultados por semana de ingreso' })).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('gerencia-menu-desktop.png'), animations: 'disabled' })
  await menu.getByRole('button', { name: 'Metas y cumplimiento' }).press('Enter')
  await expect(page).toHaveURL(/#\/metas$/)

  const analisis = menu.getByRole('button', { name: 'Análisis' })
  await analisis.press('Enter')
  await menu.getByRole('button', { name: 'Conversiones', exact: true }).press('Enter')
  await expect(page.getByRole('heading', { name: 'Conversión del equipo' })).toBeVisible()
  await analisis.press('Space')
  await expect(analisis).toHaveAttribute('aria-expanded', 'false')
  await menu.getByRole('button', { name: 'Resumen', exact: true }).click()
  await page.goBack()
  await expect(page).toHaveURL(/#\/conversiones$/)
  await expect(analisis).toHaveAttribute('aria-expanded', 'true')
  await expect(menu.getByRole('button', { name: 'Conversiones', exact: true })).toHaveAttribute('aria-current', 'page')

  await menu.getByRole('button', { name: 'Operación' }).press('Enter')
  await menu.getByRole('button', { name: 'Pipeline', exact: true }).click()
  await expect(page.getByText('Nuevo', { exact: true }).first()).toBeVisible()
  await menu.getByRole('button', { name: 'Administración' }).press('Enter')
  await menu.getByRole('button', { name: 'Configuración', exact: true }).click()
  await expect(page).toHaveURL(/#\/config$/)
  expect(solicitudes()).toBe(0)
})

test.describe('menú de Gerencia en tablet táctil', () => {
  test.use({ viewport: { width: 820, height: 1180 }, hasTouch: true })

  test('abre desde el riel y se repliega al elegir un destino', async ({ page }, testInfo) => {
    await bloquearSupabase(page)
    await entrarDemo(page, 'Gerencia')
    const menu = page.locator('aside').getByRole('navigation')
    await expect(page.getByRole('button', { name: 'Fijar menú abierto' })).toBeVisible()
    await menu.getByRole('button', { name: 'Operación' }).tap()
    await expect(menu.getByRole('button', { name: 'Pipeline', exact: true })).toBeVisible()
    await menu.getByRole('button', { name: 'Pipeline', exact: true }).tap()
    await expect(page).toHaveURL(/#\/pipeline$/)
    await expect(menu.getByRole('button', { name: 'Pipeline', exact: true })).not.toBeVisible()
    await expect(page.getByRole('button', { name: 'Fijar menú abierto' })).toBeVisible()
    await page.getByRole('button', { name: 'Fijar menú abierto' }).tap()
    await expect(menu.getByRole('button', { name: 'Operación' })).toHaveAttribute('aria-expanded', 'true')
    await expect(menu.getByRole('button', { name: 'Pipeline', exact: true })).toHaveAttribute('aria-current', 'page')
    await expect(page.getByText('Nuevo', { exact: true }).first()).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await page.screenshot({ path: testInfo.outputPath('gerencia-menu-tablet.png'), animations: 'disabled' })
  })
})
