// E2E de navegación del módulo independiente. El demo no inventa cifras ni
// escribe en Supabase: sirve para comprobar ruta, estructura y separación.
import { expect, test } from '@playwright/test'
import { bloquearSupabase, entrarDemo } from './_helpers'

test('demo supervisor: Derivar leads abre como módulo propio sin tocar Supabase', async ({
  page,
}) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Supervisor')
  await page.getByRole('button', { name: 'Derivar leads' }).click()

  await expect(page.getByRole('heading', { name: 'Derivar leads' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Carga por asesor' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Derivar hoy' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Guardadas hoy' })).toBeVisible()
  await expect(page.getByRole('region', { name: 'Flujo para derivar leads' })).toBeVisible()
  await expect(page.getByRole('searchbox', { name: 'Buscar leads por repartir' })).toBeVisible()
  await expect(page.getByText(/no está disponible en el modo demostración/i)).toBeVisible()
  await expect(page.locator('input[type="checkbox"]')).toHaveCount(0)

  await expect(
    page.getByRole('combobox', { name: /Derivar .* a un asesor/ }).first(),
  ).toBeDisabled()
  expect(requestsSupabase()).toBe(0)
})
