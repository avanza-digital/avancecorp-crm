import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

// F4-e en demo: la gerencia ve la tercera pestaña de «Toda la operación hoy» y el supervisor el bloque «Su celular».
test('Celular (gerencia): la pestaña «Llamadas del celular» lista los equipos y abre la ficha del elegido', async ({ page }) => {
  await entrarDemo(page, 'Gerencia')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await page.getByRole('tab', { name: 'Llamadas del celular' }).click()
  const tabla = page.getByRole('table', { name: 'Llamadas del celular por equipo' })
  await expect(tabla.getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR UNO' })).toBeVisible()
  await expect(tabla.getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR DOS' })).toBeVisible()
  await expect(tabla.getByRole('rowheader', { name: /^Toda la operación/ })).toBeVisible()
  await tabla.getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR UNO' }).click()
  const ficha = page.getByRole('region', { name: 'Detalle del Equipo de SUPERVISOR UNO' })
  await expect(ficha.getByRole('list', { name: 'Analistas que necesitan atención' }).getByRole('listitem')).toHaveCount(2)
  await expect(ficha).toContainText('Llamadas de hoy (por la hora de la llamada)')
  await page.getByRole('button', { name: /^Con celular sin latido/ }).click()
  await expect(tabla.getByRole('button', { name: /^Seleccionar / })).toHaveCount(1)
})

test('Celular (supervisor): la ficha del analista lleva «Su celular» y el pie dice el celular del supervisor', async ({ page }) => {
  await entrarDemo(page, 'Supervisor')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await page.getByRole('button', { name: 'Seleccionar a ANALISTA DOS' }).click()
  const bloque = page.getByRole('region', { name: 'Su celular' })
  await expect(bloque.getByRole('heading', { name: 'Su celular · C2' })).toBeVisible()
  await expect(bloque).toContainText('Sin latido · 9 h')
  await expect(bloque).toContainText('Las 3 llamadas en cola no están en estas cifras')
  await expect(page.getByText(/Tu celular: C4 · al día/)).toBeVisible()
})
