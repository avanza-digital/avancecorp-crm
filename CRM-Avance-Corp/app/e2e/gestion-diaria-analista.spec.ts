// Gestión Diaria · Fase 3 en demo: el analista abre «Mi día» y encuentra su
// cola agrupada en el orden que manda (sin primer intento arriba), su marcador
// y su seguimiento; puede abrir el panel del resultado desde una fila. En demo
// el día sale del espejo puro sobre el ámbito, así que aquí se comprueba la
// estructura y el orden, no las cifras.
import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

test('Analista: «Mi día» abre con la cola agrupada y su marcador', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria$/)

  await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toBeVisible()
  await expect(page.getByRole('heading', { level: 3, name: /Mi marcador de hoy/ })).toBeVisible()
  // El registro crudo de la Fase 1 sigue debajo, sin filtro de analista.
  await expect(page.getByRole('heading', { level: 2, name: '¿Qué hice hoy?' })).toBeVisible()
  await expect(page.getByRole('combobox', { name: 'Analista' })).toHaveCount(0)

  // El primer grupo de la cola es «Sin primer intento»: el lead nuevo manda
  // (decisión #2 de Miguel). Los grupos son <ol> con nombre; el gráfico de
  // llamadas por hora es un <ul> y no cuenta.
  const primerGrupo = page.getByRole('list', { name: /^Sin primer intento/ })
  await expect(primerGrupo).toBeVisible()
  await expect(page.locator('ol[aria-label]').first()).toHaveAttribute('aria-label', /^Sin primer intento/)

  // Cada fila ofrece registrar el resultado; el panel de la Fase 2 se abre.
  await primerGrupo.getByRole('button', { name: 'Registrar resultado' }).first().click()
  const panel = page.getByRole('dialog', { name: /Cómo salió la llamada/ })
  await expect(panel).toBeVisible({ timeout: 10_000 })
  // Los radios llevan su detalle en el nombre accesible: se busca por regex.
  await expect(panel.getByRole('radio', { name: /No contest/ })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(panel).toHaveCount(0)

  // Y el seguimiento (compromisos a partir de mañana) tiene su sección propia.
  await expect(page.getByRole('heading', { level: 3, name: /Mi seguimiento/ })).toBeVisible()
})

for (const rol of ['Supervisor', 'Gerencia'] as const) {
  test(`${rol} no ve «Mi día» todavía (llega en la Fase 4)`, async ({ page }) => {
    await entrarDemo(page, rol)
    await page.getByRole('button', { name: 'Gestión Diaria' }).click()
    await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toHaveCount(0)
    await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).toBeVisible()
  })
}
