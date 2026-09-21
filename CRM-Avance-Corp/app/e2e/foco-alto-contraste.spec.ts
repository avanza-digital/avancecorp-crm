// El foco de la casa se pinta con `ring-*/40` (un box-shadow al 40 %) y 81
// controles apagan además el `outline` del navegador. De ahí dos fallos que
// vigilan estas pruebas, los dos arreglados en `index.css` con reglas globales
// en vez de editando 41 archivos:
//   · en alto contraste el navegador BORRA los box-shadow y respeta el
//     `outline: none` → el foco desaparecía del todo (WCAG 2.4.7);
//   · en modo normal el resplandor compone ~1,8:1, y 1.4.11 pide 3:1.
// Y la tercera prueba fija el límite: los modales NO deben pintar un borde
// alrededor de toda la ventana al abrirse.
import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

test('en alto contraste el foco se sigue viendo, aunque el control diga outline-none', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()

  // Un control con `focus-visible:outline-none` en su clase: la fila de la cola.
  const fila = page.getByRole('list', { name: /^Sin primer intento/ }).getByRole('button').first()
  await expect(fila).toHaveClass(/focus-visible:outline-none/)

  await page.emulateMedia({ forcedColors: 'active' })
  // El foco tiene que llegar POR TECLADO: Chromium no considera `:focus-visible`
  // un `element.focus()` programático, y la regla cuelga de ese selector.
  await fila.focus()
  await page.keyboard.press('Tab')
  await page.keyboard.press('Shift+Tab')
  await expect(fila).toBeFocused()
  const outline = await fila.evaluate((el) => {
    const s = getComputedStyle(el)
    return { ancho: s.outlineWidth, estilo: s.outlineStyle, visible: el.matches(':focus-visible') }
  })
  expect(outline.visible).toBe(true)
  expect(outline.estilo).not.toBe('none')
  expect(Number.parseFloat(outline.ancho)).toBeGreaterThanOrEqual(2)
})

test('en modo normal el control enfocado tiene un `outline` de verdad, no solo el resplandor', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()

  const fila = page.getByRole('list', { name: /^Sin primer intento/ }).getByRole('button').first()
  await fila.focus()
  await page.keyboard.press('Tab')
  await page.keyboard.press('Shift+Tab')
  await expect(fila).toBeFocused()
  const outline = await fila.evaluate((el) => {
    const s = getComputedStyle(el)
    return { ancho: s.outlineWidth, estilo: s.outlineStyle }
  })
  expect(outline.estilo).toBe('solid')
  expect(Number.parseFloat(outline.ancho)).toBeGreaterThanOrEqual(2)
})

test('la regla NO alcanza al modal: abrirlo no pinta un borde alrededor de la ventana', async ({ page }) => {
  await entrarDemo(page, 'Analista')

  // «Nuevo lead» de la cabecera: un modal que existe en toda la app, para que
  // esta prueba no dependa de la pantalla que se esté rediseñando.
  await page.getByRole('button', { name: 'Nuevo lead' }).click()
  const modal = page.getByRole('dialog').first()
  await expect(modal).toBeVisible({ timeout: 10_000 })
  // El contenedor del modal usa `outline-none` A SECAS, no `focus-visible:…`:
  // recibe el foco al abrirse y no debe quedar rodeado de un borde.
  const estilo = await modal.evaluate((el) => getComputedStyle(el).outlineStyle)
  expect(estilo).toBe('none')
})
