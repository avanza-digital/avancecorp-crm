import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

test('Celular: descartar conserva el foco y aparece en lo resuelto con su motivo', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await page.getByRole('tab', { name: /^Celular/ }).click()
  const pendientes = page.getByRole('list', { name: 'Llamadas pendientes' })
  const total = await pendientes.getByRole('listitem').count()
  await pendientes.getByRole('button', { name: 'Descartar', exact: true }).first().click()
  await page.getByRole('button', { name: 'Llamada personal', exact: true }).click()
  await expect(pendientes.getByRole('listitem')).toHaveCount(total - 1)
  await expect(page.getByRole('heading', { name: 'Llamadas del celular', exact: true })).toBeFocused()
  await page.getByRole('button', { name: /^Qué pasó hoy/ }).click()
  const resueltas = page.getByRole('list', { name: 'Llamadas resueltas hoy' })
  await expect(resueltas.getByRole('listitem').first()).toContainText('Descartada · Llamada personal')
})
