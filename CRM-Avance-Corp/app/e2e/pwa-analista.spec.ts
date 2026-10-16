import { expect, test } from '@playwright/test'
import { abrirLead, bloquearSupabase, entrarDemo, loginReal, montarBackendReal } from './_helpers'
import { irAModulo } from './_navegacion'

test.use({ viewport: { width: 390, height: 844 }, hasTouch: true })

const destinos = [
  ['Hoy', 'hoy'], ['Gestión Diaria', 'gestion-diaria'], ['Agenda', 'agenda'],
  ['Mi cartera', 'mi-cartera'], ['Leads', 'cartera'], ['Pipeline', 'pipeline'],
  ['Seguimiento', 'seguimiento'], ['Base para gestión', 'rescate'],
  ['Configuración', 'config'],
] as const

test('Analista: barra propia, todos sus módulos y permisos conservados', async ({ page }, info) => {
  test.setTimeout(90_000)
  const solicitudes = await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  const nav = page.getByRole('navigation', { name: 'Navegación principal de Analista' })
  await expect(nav.getByRole('button')).toHaveText(['Mi día', 'Gestión Diaria', 'Agenda', 'Más'])
  await expect(page.locator('aside')).toHaveCount(0)
  await expect(page.getByRole('region', { name: 'Pendientes de gestión' })).toBeAttached()
  await page.screenshot({ path: info.outputPath('mi-dia-390.png') })
  for (const [nombre, ruta] of destinos) await test.step(nombre, async () => {
    await irAModulo(page, nombre)
    await expect(page).toHaveURL(new RegExp(`#/${ruta}$`))
    await expect(page.locator('main h1')).toBeVisible()
    await expect(page.locator('[data-vista-scroll] > [aria-busy="true"]')).toHaveCount(0)
    await expect(page.getByText('Algo salió mal en esta sección')).toHaveCount(0)
    const barra = (await nav.boundingBox())!
    const contenido = (await page.locator('main').boundingBox())!
    expect(contenido.x).toBe(0)
    expect(contenido.y + contenido.height).toBeLessThanOrEqual(barra.y)
  })
  await nav.getByRole('button', { name: 'Más', exact: true }).click()
  const panel = page.getByRole('dialog', { name: 'Más opciones' })
  await expect(panel.getByText('Analista · Demo', { exact: true })).toBeVisible()
  for (const nombre of ['Facturación', 'Gestión de equipo', 'Metas y cumplimiento', 'Repartir leads']) {
    await expect(panel.getByRole('button', { name: nombre, exact: true, includeHidden: true })).toHaveCount(0)
  }
  await page.screenshot({ path: info.outputPath('mas-analista.png') })
  await page.keyboard.press('Escape')
  await expect(nav.getByRole('button', { name: 'Más', exact: true })).toBeFocused()
  await page.goto('/#/reuniones')
  await expect(page).toHaveURL(/#\/hoy$/)
  expect(solicitudes()).toBe(0)
})

for (const width of [360, 430, 767, 768]) test(`Analista: pantallas utilizables a ${width}px`, async ({ page }, info) => {
  test.setTimeout(90_000)
  await page.setViewportSize({ width, height: 900 })
  await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  if (width === 768) {
    await expect(page.locator('aside')).toBeVisible()
    await expect(page.locator('.gm-barra')).toHaveCount(0)
  }
  for (const [nombre] of destinos) await test.step(nombre, async () => {
    await irAModulo(page, nombre)
    const area = page.locator('[data-vista-scroll]')
    await expect(area).toBeVisible()
    await expect(page.locator('main h1')).toBeVisible()
    await expect(area.locator(':scope > [aria-busy="true"]')).toHaveCount(0)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    expect(await area.evaluate(e => e.scrollWidth <= e.clientWidth + 1)).toBe(true)
    if (nombre === 'Agenda' && width < 768) {
      const tarea = area.locator('.agenda-tarea').first()
      await expect(tarea).toBeVisible()
      const datos = (await tarea.locator('.agenda-tarea-datos').boundingBox())!
      const acciones = (await tarea.locator('.agenda-tarea-acciones').boundingBox())!
      expect(datos.width).toBeGreaterThan(150)
      expect(acciones.y).toBeGreaterThanOrEqual(datos.y + datos.height)
    }
    if (width === 360) await page.screenshot({ path: info.outputPath(`${nombre.replaceAll(' ', '-')}-360.png`) })
  })
})

test('Analista: pendientes propios conservan filtros al volver; la campana y Mi día coinciden', async ({ page }) => {
  await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  const pendientes = page.getByRole('region', { name: 'Pendientes de gestión' })
  const todos = pendientes.getByRole('link', { name: /Ver todos/ })
  const total = (await todos.textContent())!.match(/\((\d+)\)/)![1]!
  await expect(page.locator('header').getByRole('link', { name: /Abrir pendientes/ })).toContainText(total)
  await expect(pendientes.getByRole('listitem')).toHaveCount(3)
  await todos.click()
  await page.getByRole('button', { name: 'Filtrar', exact: true }).click()
  await page.getByRole('searchbox', { name: 'Buscar pendiente' }).fill('sin coincidencias xyz')
  await expect(page.getByText('Sin coincidencias', { exact: true })).toBeVisible()
  await irAModulo(page, 'Agenda')
  await page.goBack()
  await expect(page.getByRole('searchbox', { name: 'Buscar pendiente' })).toHaveValue('sin coincidencias xyz')
  await page.getByRole('button', { name: 'Limpiar', exact: true }).click()
  await expect(page.getByRole('list', { name: 'Pendientes activos' }).getByRole('listitem')).toHaveCount(Number(total))
})

test('Analista autenticado: barra y límites de acceso con el backend simulado', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor' })
  await loginReal(page, { esperarWorkspace: false })
  const nav = page.getByRole('navigation', { name: 'Navegación principal de Analista' })
  await expect(nav.getByRole('button')).toHaveText(['Mi día', 'Gestión Diaria', 'Agenda', 'Más'])
  await irAModulo(page, 'Configuración')
  await expect(page.getByRole('heading', { name: 'Mi calendario de Google' })).toBeVisible()
  await page.goto('/#/reuniones')
  await expect(page).toHaveURL(/#\/hoy$/)
  await expect(nav.getByRole('button', { name: 'Mi día', exact: true })).toHaveAttribute('aria-current', 'page')
})

test('Analista: Más en horizontal, cambio a tablet, Atrás y cierre de sesión', async ({ page }) => {
  await page.setViewportSize({ width: 667, height: 375 })
  await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  await irAModulo(page, 'Agenda')
  await page.getByRole('button', { name: 'Más', exact: true }).click()
  const panel = page.getByRole('dialog', { name: 'Más opciones' })
  await expect(panel.getByRole('button', { name: 'Cerrar sesión' })).toBeInViewport()
  await expect(panel.getByRole('button', { name: 'Cerrar más opciones' })).toBeInViewport()
  await page.setViewportSize({ width: 820, height: 1180 })
  await expect(panel).toHaveCount(0)
  await expect(page.locator('aside')).toBeVisible()
  await expect(page.locator('main')).toBeFocused()
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goBack()
  await expect(page.getByRole('button', { name: 'Mi día', exact: true })).toHaveAttribute('aria-current', 'page')
  await page.getByRole('button', { name: 'Más', exact: true }).click()
  await panel.getByRole('button', { name: 'Cerrar sesión' }).click()
  await expect(page.getByRole('button', { name: /explorar en modo demo/i })).toBeVisible()
  await expect(page.locator('.gm-barra')).toHaveCount(0)
})

test('Analista: desconexión y actualización aplazable sin tapar Más ni la barra', async ({ page, context }) => {
  await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  await irAModulo(page, 'Agenda')
  await context.setOffline(true)
  await expect(page.locator('.crm-conexion')).toContainText('Sin conexión')
  await context.setOffline(false)
  await expect(page.locator('.crm-conexion')).toHaveCount(0)
  await expect(page).toHaveURL(/#\/agenda$/)
  await page.evaluate(async ruta => {
    const { montarAvisoVersion } = await import(ruta)
    montarAvisoVersion()
  }, '/e2e/_aviso-version.tsx')
  const aviso = page.getByRole('status', { name: 'Nueva versión del CRM disponible' })
  await expect(aviso).toBeVisible()
  const caja = (await aviso.boundingBox())!
  expect(caja.y + caja.height).toBeLessThanOrEqual((await page.locator('.gm-barra').boundingBox())!.y)
  await page.getByRole('button', { name: 'Más', exact: true }).click()
  await expect(aviso).toBeHidden()
  await page.keyboard.press('Escape')
  await expect(aviso).toBeVisible()
  await aviso.getByRole('button', { name: 'Más tarde' }).click()
  const host = page.locator('[data-aviso-version-prueba]')
  await expect(host).not.toHaveAttribute('data-actualizacion-solicitada', 'true')
  await aviso.getByRole('button', { name: 'Ver actualización disponible' }).click()
  await aviso.getByRole('button', { name: 'Ya guardé, actualizar' }).click()
  await expect(host).toHaveAttribute('data-actualizacion-solicitada', 'true')
})

test('Analista: editar y guardar una ficha con teclado simulado deja la acción accesible', async ({ page }, info) => {
  await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  await irAModulo(page, 'Pipeline')
  const ficha = await abrirLead(page, /JUAN PÉREZ ROJAS/)
  await ficha.getByRole('button', { name: 'Editar', exact: true }).click()
  await ficha.locator('#ld-monto').fill('99999')
  // Simula SOLO la altura visual que reporta el navegador al mostrar teclado.
  // No equivale a validar el teclado del sistema en un teléfono físico.
  await page.evaluate(() => {
    Object.defineProperty(window.visualViewport, 'height', { configurable: true, value: 500 })
    window.visualViewport!.dispatchEvent(new Event('resize'))
  })
  await expect(page.locator('[data-teclado-abierto="true"]')).toHaveCount(1)
  await expect(page.locator('.gm-barra')).toBeHidden()
  await expect(ficha).toHaveCSS('height', '500px')
  const guardar = ficha.getByRole('button', { name: 'Guardar', exact: true })
  await guardar.scrollIntoViewIfNeeded()
  const caja = (await guardar.boundingBox())!
  expect(caja.y).toBeGreaterThanOrEqual(0)
  expect(caja.y + caja.height).toBeLessThanOrEqual(500)
  await page.screenshot({ path: info.outputPath('ficha-teclado-simulado.png') })
  await guardar.click()
  await expect(page.getByText(/Cambios guardados \(demo\)/i)).toBeVisible()
  await page.evaluate(() => {
    Object.defineProperty(window.visualViewport, 'height', { configurable: true, value: 844 })
    window.visualViewport!.dispatchEvent(new Event('resize'))
  })
  await expect(page.locator('[data-teclado-abierto="true"]')).toHaveCount(0)
  await ficha.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
  await expect(page.locator('.gm-barra')).toBeVisible()
})
