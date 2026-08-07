import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

test('Superadmin con membresía Coordinador aterriza solo en Usuarios y no precarga operación CRM', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    rolCrm: 'coordinador',
    rolPortal: 'superadmin',
  })

  await loginReal(page)

  await expect(page.getByRole('heading', { level: 1, name: 'Usuarios y jerarquía' })).toBeVisible()
  await expect(page.getByText('No hay usuarios que coincidan con la búsqueda.')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Usuarios y roles' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Pipeline' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Configuración' })).toHaveCount(0)
  await expect(page.getByRole('heading', { name: 'Productos de inversión' })).toHaveCount(0)
  await expect(page.getByRole('heading', { name: 'Metas mensuales' })).toHaveCount(0)
  await expect(page.getByRole('heading', { name: 'Tiempos de atención' })).toHaveCount(0)

  await page.evaluate(() => { window.location.hash = '#/repartir' })
  await expect(page.getByRole('heading', { level: 1, name: 'Usuarios y jerarquía' })).toBeVisible()
  await expect(page).toHaveURL(/#\/config-usuarios$/)
  expect(estado.llamadas.getLeads).toBe(0)
  expect(estado.llamadas.rpcMetricasDistribucion).toBe(0)
})
