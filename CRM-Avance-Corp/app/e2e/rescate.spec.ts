import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

test('supervisor: abre Base para gestión, entra a una carpeta nueva y reparte sin red', async ({ page }) => {
  const salidasSupabase: string[] = []
  page.on('request', (request) => {
    if (request.url().startsWith('http://127.0.0.1:59999')) salidasSupabase.push(request.url())
  })

  await entrarDemo(page, 'Supervisor')
  await page.getByRole('button', { name: 'Base para gestión' }).click()
  await expect(page.getByRole('heading', { name: 'Base para gestión' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Abrir carpeta Sin fondos' })).toBeVisible()

  const popupPrometido = page.waitForEvent('popup')
  await page.getByRole('button', { name: 'Abrir carpeta Sin fondos' }).click()
  const carpeta = await popupPrometido
  await expect(carpeta.getByRole('heading', { name: 'Sin fondos' })).toBeVisible()
  await expect(carpeta.getByText('1 resultados')).toBeVisible()

  await carpeta.getByRole('button', { name: 'Seleccionar esta página (1)' }).click()
  await carpeta.getByRole('button', { name: 'Reactivar y repartir' }).click()
  await carpeta.getByLabel('Asesor destino').selectOption('d-v2')
  await carpeta.getByRole('button', { name: 'Reactivar 1 y repartir' }).click()

  await expect(carpeta.getByText('1 lead reactivado y repartido (demo)')).toBeVisible()
  await expect(carpeta.getByText('Ya reactivado')).toBeVisible()
  expect(salidasSupabase).toEqual([])
})
