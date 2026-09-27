// Hoy del supervisor como puesto de mando (27/09/2026), en el MUNDO DE
// PRODUCCIÓN: seguimiento ACTIVO. Se recorre con teclado a 1440×900 y se deja
// una captura para la revisión visual de Miguel.
import { expect, test } from '@playwright/test'
import { loginReal } from './_helpers'
import { montarColaEquipo } from './_sla-cola'

test('supervisor: decide primero, cola filtrada en el servidor y detalle — todo con teclado', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  const { pedidos, analistaUno } = await montarColaEquipo(page, 'supervisor')
  const errores: string[] = []
  page.on('pageerror', (error) => errores.push(error.message))
  await loginReal(page)

  // 1 · Decide primero: la primera gestión vencida la cuenta el servidor.
  await expect(page.getByRole('heading', { name: 'Decide primero', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Hoy: 4 primeras gestiones vencidas' })).toBeVisible()

  // 2 · Cola: vista previa de 7 del seguimiento, conteos del servidor.
  await expect(page.getByRole('heading', { name: 'Pendientes del equipo', exact: true })).toBeVisible()
  const lista = page.getByRole('list', { name: /^Pendientes del equipo/ })
  await expect(lista.locator(':scope > li')).toHaveCount(7)
  expect(pedidos.at(-1)).toMatchObject({ p_limite: 7, p_senal: 'pendientes', p_cursor: null })
  await expect(page.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
  await page.screenshot({ path: test.info().outputPath('hoy-supervisor-1440x900.png'), animations: 'disabled' })

  // Abrir la ficha con teclado y volver con Esc: el foco regresa a la fila
  // (con `disabled` en la fila se perdía a <body>; revisor a11y P1).
  const primeraFila = lista.locator(':scope > li').first().getByRole('button', { name: /^Abrir ficha de / })
  await primeraFila.focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('dialog')).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(primeraFila).toBeFocused()

  // Pestañas con flechas (tabindex itinerante) → la señal va al servidor.
  await page.getByRole('tab', { name: /Para atender ahora/ }).focus()
  await page.keyboard.press('ArrowRight')
  await expect(page.getByRole('tab', { name: 'Primera gestión: 4' })).toBeFocused()
  await expect.poll(() => pedidos.at(-1)?.p_senal).toBe('primera_atencion')
  await expect(lista.locator(':scope > li')).toHaveCount(4)

  // La tarjeta despliega su contexto y deja la cola en esa pestaña.
  const tarjeta = page.getByRole('button', { name: 'Hoy: 4 primeras gestiones vencidas' })
  await tarjeta.focus()
  await page.keyboard.press('Enter')
  await expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
  await expect(page.getByText('Revisa la primera gestión con cada analista: abajo quedan solo esos casos.')).toBeVisible()

  // Chip de analista: el filtro lo hace el SERVIDOR.
  // Dos analistas con el mismo primer nombre: los chips los distinguen.
  const chips = page.getByRole('group', { name: 'Filtrar por analista' })
  await expect(chips.getByRole('button', { name: 'Analista Norte Uno' })).toHaveText('Analista U.')
  await chips.getByRole('button', { name: 'Analista Norte Uno' }).click()
  await expect.poll(() => pedidos.some((p) => p.p_analista_id === analistaUno)).toBe(true)
  await expect(page.getByRole('heading', { name: 'Pendientes de Analista U.', exact: true })).toBeVisible()

  // 3 · Detalle: Enter abre, Esc cierra y el foco vuelve al botón.
  const detalle = page.getByRole('button', { name: 'Detalle', exact: true })
  await detalle.focus()
  await page.keyboard.press('Enter')
  const dialogo = page.getByRole('dialog', { name: 'Detalle del equipo' })
  await expect(dialogo).toBeVisible()
  await expect(dialogo.getByRole('heading', { name: 'Cumplimiento del mes' })).toBeVisible()
  await page.screenshot({ path: test.info().outputPath('hoy-supervisor-detalle.png'), animations: 'disabled' })
  await page.keyboard.press('Escape')
  await expect(dialogo).toHaveCount(0)
  await expect(detalle).toBeFocused()

  // Sin jerga en pantalla.
  await expect(page.locator('main')).not.toContainText(/pipeline|SLA/)
  expect(errores).toEqual([])
})

test('supervisor: en un celular (375 px) la pantalla reacomoda sin cortar lo esencial', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 800 })
  await montarColaEquipo(page, 'supervisor')
  // En el celular no hay menú de escritorio que esperar.
  await loginReal(page, { esperarWorkspace: false })
  await expect(page.getByRole('heading', { name: 'Pendientes del equipo', exact: true })).toBeVisible()
  const lista = page.getByRole('list', { name: /^Pendientes del equipo/ })
  await expect(lista.locator(':scope > li')).toHaveCount(7)
  // Sin columna de analista, el dueño pasa a la segunda línea de cada fila.
  await expect(lista.locator(':scope > li').first()).toContainText('Analista U. ·')
  // Nada desborda en horizontal.
  const desborde = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(desborde).toBeLessThanOrEqual(0)
  await page.screenshot({ path: test.info().outputPath('hoy-supervisor-375.png'), fullPage: true, animations: 'disabled' })
})
