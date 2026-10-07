// Celulares (F4-c) en DEMO: Gerencia asigna, ve la clave una sola vez, rota y cierra sin que una sola lectura salga
// a Supabase (la demo vive en memoria, decisión D2); Directorio no ve la tarjeta. La prueba con el backend real
// llega con los tipos aplicados en producción (F4-d).
import { expect, test } from '@playwright/test'
import { bloquearSupabase, entrarDemo } from './_helpers'
import { irAModulo } from './_navegacion'

test('demo gerencia: la tarjeta «Celulares» asigna, muestra la clave una vez, rota y cierra sin red', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)
  await entrarDemo(page, 'Gerencia')
  await irAModulo(page, 'Configuración')
  const tarjeta = page.getByRole('heading', { name: 'Celulares', exact: true }).locator('xpath=ancestor::div[@data-slot="card"]')
  await tarjeta.getByRole('link', { name: 'Abrir', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Celulares', exact: true })).toBeVisible()

  const vigentes = page.getByRole('table', { name: 'Celulares vigentes y su salud' })
  await expect(vigentes.getByText('ANA TORRES')).toBeVisible()
  await expect(vigentes.getByText('Sin latido · 9 h')).toBeVisible()
  await expect(vigentes.getByText('Analista de baja')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Rotar la clave de C5' })).toBeDisabled()

  // Asignar: la clave se ve una sola vez, empieza por «demo» y Esc no cierra la ventana.
  await page.getByRole('button', { name: 'Asignar celular' }).click()
  const asignar = page.getByRole('dialog', { name: 'Asignar un celular' })
  await asignar.getByLabel('Etiqueta del celular').fill('c7')
  await asignar.getByLabel('Analista que lo usará').selectOption({ label: 'ANA TORRES · Analista' })
  await asignar.getByRole('button', { name: 'Asignar y ver la clave' }).click()
  const clave = page.getByRole('dialog', { name: /Clave de C7/ })
  await expect(clave).toBeVisible()
  await expect(clave.getByLabel('Clave del celular C7')).toHaveValue(/^demo[0-9a-f]{60}$/)
  await page.keyboard.press('Escape')
  await expect(clave).toBeVisible()
  await clave.getByRole('button', { name: 'Ya la copié al celular' }).click()
  await expect(clave).toBeHidden()
  await expect(vigentes.getByText('C7', { exact: true })).toBeVisible()

  // Etiqueta repetida: el texto del servidor (que la demo imita) y el atajo a rotar.
  await page.getByRole('button', { name: 'Asignar celular' }).click()
  await asignar.getByLabel('Etiqueta del celular').fill('C1')
  await asignar.getByLabel('Analista que lo usará').selectOption({ label: 'BRUNO DÍAZ · Analista' })
  await asignar.getByRole('button', { name: 'Asignar y ver la clave' }).click()
  await expect(asignar.getByRole('alert')).toContainText('C1 ya está asignado')
  await asignar.getByRole('button', { name: 'Rotar la clave de C1' }).click()
  await page.getByRole('dialog', { name: 'Rotar la clave de C1' }).getByRole('button', { name: 'Rotar y ver la nueva clave' }).click()
  const claveNueva = page.getByRole('dialog', { name: /Clave de C1/ })
  await expect(claveNueva).toBeVisible()
  await claveNueva.getByRole('button', { name: 'Ya la copié al celular' }).click()
  await expect(claveNueva).toBeHidden()

  // Cerrar C2 con motivo: deja de estar vigente y pasa al historial.
  await page.getByRole('button', { name: 'Cerrar C2' }).click()
  const cerrar = page.getByRole('dialog', { name: 'Cerrar C2' })
  await expect(cerrar.getByText(/3 avisos sin enviar/)).toBeVisible()
  await cerrar.getByLabel(/Extravío del celular/).check()
  await cerrar.getByRole('button', { name: 'Cerrar asignación' }).click()
  await expect(cerrar).toBeHidden()
  await expect(page.getByRole('button', { name: 'Cerrar C2' })).toHaveCount(0)
  await expect(page.getByRole('table', { name: 'Historial de cierres de celulares' }).getByText('Extravío')).toBeVisible()

  expect(requestsSupabase()).toBe(0)
})

test('demo directorio: la tarjeta «Celulares» no se le ofrece', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)
  await entrarDemo(page, 'Directorio')
  await irAModulo(page, 'Configuración')
  await expect(page.getByRole('heading', { name: 'Configuración del CRM' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Usuarios y jerarquía', exact: true })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Celulares', exact: true })).toHaveCount(0)
  expect(requestsSupabase()).toBe(0)
})
