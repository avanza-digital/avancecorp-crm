// Gestión Diaria · Fase 3 en demo: el analista abre «Mi día» y encuentra DOS
// paneles hermanos —«Ahora» (a quién llama y con qué botón) y «Cola de hoy»
// (los grupos en pestañas, el de «Sin primer intento» delante)—, su marcador en
// una línea arriba y su seguimiento debajo. En demo el día sale del espejo puro
// sobre el ámbito, así que aquí se comprueba la estructura y el orden, no las
// cifras.
import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

test('Analista: «Mi día» abre con el panel «Ahora» y la cola en pestañas', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria$/)

  await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toBeVisible()
  // El marcador vive en la cabecera, en una línea, y lleva a su detalle.
  await expect(page.getByRole('button', { name: /Mi actividad/ })).toBeVisible()
  // El registro crudo de la Fase 1 sigue debajo, plegado, sin filtro de analista.
  await expect(page.getByRole('heading', { name: /¿Qué hice hoy\?/ })).toBeVisible()
  await expect(page.getByRole('combobox', { name: 'Analista' })).toHaveCount(0)

  // El panel «Ahora»: UN lead, con su acción primaria a la vista.
  const ahora = page.getByRole('region', { name: 'Ahora' })
  await expect(ahora).toBeVisible()
  // En la laptop «Llamar» es un botón que copia el número (no hay radio); en el
  // celular es un enlace `tel:`. Los dos caminos valen aquí.
  await expect(ahora.getByRole('link', { name: /Llamar a/ })
    .or(ahora.getByRole('button', { name: /Copiar el número de/ }))).toBeVisible()

  // La primera pestaña de la cola es «Sin primer intento»: el lead nuevo manda
  // (decisión #2 de Miguel), y arranca seleccionada.
  const pestanas = page.getByRole('tablist', { name: 'Grupos de la cola' })
  await expect(pestanas).toBeVisible()
  await expect(pestanas.getByRole('tab').first()).toHaveText(/^Sin primer intento/)
  await expect(pestanas.getByRole('tab').first()).toHaveAttribute('aria-selected', 'true')
  const primerGrupo = page.getByRole('list', { name: /^Sin primer intento/ })
  await expect(primerGrupo).toBeVisible()

  // La fila es el SELECTOR: al elegirla, el panel «Ahora» pasa a ese lead.
  const fila = primerGrupo.getByRole('button').first()
  // El nombre es el primer tramo de la fila; el segundo es el chip de tiempo.
  const nombre = (await fila.locator('span').first().innerText()).trim()
  await fila.click()
  await expect(fila).toHaveAttribute('aria-current', 'true')
  // `exact`: el nombre del lead también está DENTRO del aria-label de «Llamar»
  // y del de «···», y por defecto Playwright busca subcadena.
  await expect(ahora.getByRole('button', { name: nombre, exact: true })).toBeVisible()

  // Registrar el resultado vive detrás de «···»; el panel de la Fase 2 se abre.
  await ahora.getByRole('button', { name: /Más acciones para/ }).click()
  await page.getByRole('menuitem', { name: 'Registrar resultado' }).click()
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
