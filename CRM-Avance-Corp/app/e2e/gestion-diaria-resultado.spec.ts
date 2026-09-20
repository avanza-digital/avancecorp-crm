// Gestión Diaria (Fase 2) en demo: una llamada se cierra con su resultado
// tipificado desde las acciones de contacto; «volver a llamar» crea la tarea
// siguiente y el toast ofrece «Deshacer», que la cancela. En demo el espejo es
// local; lo que se comprueba es el flujo y la estructura, no el servidor.
import { expect, test } from '@playwright/test'
import { entrarDemo, irAPipeline, abrirLead } from './_helpers'

test('Analista: llamar → resultado «volver a llamar» → tarea creada → deshacer', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /MARÍA LÓPEZ CASTRO/)
  // En escritorio «Llamar» copia el número y abre directo el panel del resultado.
  await drawer.getByRole('button', { name: /Copiar el número de MARÍA LÓPEZ CASTRO y registrar la llamada/ }).click()
  const panel = page.getByRole('dialog', { name: 'Resultado de la llamada' })
  await expect(panel).toBeVisible()
  await expect(panel.getByRole('radio')).toHaveCount(7)
  await panel.getByRole('radio', { name: /volver a llamar/ }).check()
  await expect(panel.getByLabel('Fecha')).toHaveValue(/^\d{4}-\d{2}-\d{2}$/)
  await panel.getByRole('button', { name: 'Guardar' }).click()
  await expect(panel).toHaveCount(0)
  await expect(page.getByText(/Llamada registrada · Volver a llamar/)).toBeVisible()
  await page.getByRole('button', { name: 'Deshacer' }).click()
  await expect(page.getByText(/Deshecho: María vuelve a su etapa/)).toBeVisible()
})

test('Analista: «no le interesa» exige submotivo y avisa del descarte', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /MARÍA LÓPEZ CASTRO/)
  await drawer.getByRole('button', { name: /Copiar el número de MARÍA LÓPEZ CASTRO y registrar la llamada/ }).click()
  const panel = page.getByRole('dialog', { name: 'Resultado de la llamada' })
  await panel.getByRole('radio', { name: /no le interesa/ }).check()
  await expect(panel.getByText(/saldrá de tu cartera/)).toBeVisible()
  await panel.getByRole('button', { name: 'Guardar' }).click()
  await expect(page.getByText('Indica por qué no le interesa')).toBeVisible()
  await panel.getByRole('radio', { name: 'Desconfianza' }).check()
  await panel.getByRole('button', { name: 'Guardar' }).click()
  await expect(panel).toHaveCount(0)
  await expect(page.getByText(/lead descartado \(Centro de rescate\)/)).toBeVisible()
})
