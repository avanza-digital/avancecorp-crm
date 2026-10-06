import { expect, test } from '@playwright/test'
import { bloquearSupabase, entrarDemo } from './_helpers'
import { irAModulo } from './_navegacion'

test.use({ viewport: { width: 390, height: 844 }, hasTouch: true })

test('Gerencia móvil: destinos reales, Más accesible y contenido sin tapar', async ({ page }, info) => {
  const solicitudes = await bloquearSupabase(page)
  await entrarDemo(page, 'Gerencia')
  const nav = page.getByRole('navigation', { name: 'Navegación principal de Gerencia' })
  await expect(nav.getByRole('button')).toHaveText(['Resumen', 'Citas', 'Metas', 'Más'])
  await expect(page.locator('aside')).toHaveCount(0)
  await expect(nav.getByRole('button', { name: 'Resumen' })).toHaveAttribute('aria-current', 'page')
  const cajaNav = await nav.boundingBox()
  const cajaMain = await page.locator('main').boundingBox()
  expect(cajaMain?.x).toBe(0)
  expect(cajaNav!.y + cajaNav!.height).toBe(844)
  expect(cajaMain!.y + cajaMain!.height).toBeLessThanOrEqual(cajaNav!.y)
  await page.getByRole('button', { name: 'Abrir el resumen completo' }).scrollIntoViewIfNeeded()
  expect((await page.getByRole('button', { name: 'Abrir el resumen completo' }).boundingBox())!.y).toBeLessThan(cajaNav!.y)
  await nav.getByRole('button', { name: 'Citas', exact: true }).tap()
  await expect(page).toHaveURL(/#\/reuniones$/)
  await expect(page.getByRole('heading', { name: 'Citas del equipo' })).toBeVisible()
  await expect(nav.getByRole('button', { name: 'Citas', exact: true })).toHaveAttribute('aria-current', 'page')
  await nav.getByRole('button', { name: 'Metas', exact: true }).tap()
  await expect(page.getByRole('heading', { name: 'Metas mensuales' })).toBeVisible()
  await nav.getByRole('button', { name: 'Más', exact: true }).tap()
  const panel = page.getByRole('dialog', { name: 'Más opciones' })
  await expect(panel).toBeVisible()
  await expect(panel.getByRole('button', { name: 'Cerrar más opciones' })).toBeFocused()
  await page.screenshot({ path: info.outputPath('mas-opciones.png') })
  await page.keyboard.press('Shift+Tab')
  await expect(panel.getByRole('button', { name: 'Cerrar sesión' })).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(panel).toHaveCount(0)
  await expect(nav.getByRole('button', { name: 'Más', exact: true })).toBeFocused()
  await nav.getByRole('button', { name: 'Resumen', exact: true }).tap()
  await expect(page.getByTestId('resumen-gerencia-movil')).toBeVisible()
  await page.screenshot({ path: info.outputPath('barra-inferior.png') })
  expect(solicitudes()).toBe(0)
})

test('Más conserva los módulos autorizados, selecciona la subruta y responde a Atrás', async ({ page }) => {
  await bloquearSupabase(page)
  await entrarDemo(page, 'Gerencia')
  const nav = page.getByRole('navigation', { name: 'Navegación principal de Gerencia' })
  const mas = nav.getByRole('button', { name: 'Más', exact: true })
  await mas.tap()
  const panel = page.getByRole('dialog', { name: 'Más opciones' })
  await expect(panel.getByRole('button', { name: 'Facturación', exact: true })).toBeVisible()
  await expect(panel.getByRole('button', { name: 'Ranking', exact: true })).toBeVisible()
  await expect(panel.getByRole('button', { name: 'Gestión Diaria', exact: true })).toBeVisible()
  await expect(panel.getByRole('button', { name: 'Cartera', exact: true })).toBeVisible()
  await panel.getByText('Análisis', { exact: true }).tap()
  await panel.getByRole('button', { name: 'Conversiones', exact: true }).tap()
  await expect(page).toHaveURL(/#\/conversiones$/)
  await expect(panel).toHaveCount(0)
  await expect(page.locator('main')).toBeFocused()
  await expect(mas).toHaveAttribute('data-activo', '')
  await expect(mas).toHaveAttribute('aria-current', 'true')
  await mas.tap()
  await expect(panel.getByRole('button', { name: 'Conversiones', exact: true })).toHaveAttribute('aria-current', 'page')
  await panel.getByText('Operación', { exact: true }).tap()
  await expect(panel.getByRole('button', { name: 'Pipeline', exact: true })).toBeVisible()
  await panel.getByText('Administración', { exact: true }).tap()
  await expect(panel.getByRole('button', { name: 'Configuración', exact: true })).toBeVisible()
  await page.goBack()
  await expect(page).toHaveURL(/#\/hoy$/)
  await expect(panel).toHaveCount(0)
  await expect(nav.getByRole('button', { name: 'Resumen' })).toHaveAttribute('aria-current', 'page')
})

test('solo teléfono: 360/430 sin desborde; cambiar a tablet cierra Más y recupera el lateral', async ({ page }) => {
  await bloquearSupabase(page)
  await entrarDemo(page, 'Gerencia')
  for (const width of [360, 430]) {
    await page.setViewportSize({ width, height: 844 })
    await expect(page.getByRole('navigation', { name: 'Navegación principal de Gerencia' })).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await page.getByRole('button', { name: 'Más', exact: true }).tap()
    await expect(page.getByRole('dialog', { name: 'Más opciones' })).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await page.getByRole('button', { name: 'Cerrar más opciones' }).tap()
  }
  await page.getByRole('button', { name: 'Más', exact: true }).tap()
  await page.setViewportSize({ width: 820, height: 1180 })
  await expect(page.getByRole('dialog', { name: 'Más opciones' })).toHaveCount(0)
  await expect(page.getByRole('navigation', { name: 'Navegación principal de Gerencia' })).toHaveCount(0)
  await expect(page.locator('aside')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Resultados por semana de ingreso' })).toBeVisible()
  await expect(page.locator('body')).not.toHaveCSS('pointer-events', 'none')
  await expect(page.locator('main')).toBeFocused()
})

for (const rol of ['Analista', 'Supervisor', 'Directorio'] as const) test(`${rol} mantiene su navegación habitual en móvil`, async ({ page }) => {
  await bloquearSupabase(page)
  await entrarDemo(page, rol)
  await expect(page.locator('aside')).toBeVisible()
  await expect(page.getByRole('navigation', { name: 'Navegación principal de Gerencia' })).toHaveCount(0)
})

test('los 18 módulos conservan su ruta y dejan espacio para la barra', async ({ page }) => {
  test.setTimeout(90_000)
  const solicitudes = await bloquearSupabase(page)
  await entrarDemo(page, 'Gerencia')
  const destinos = [
    ['Resumen', 'hoy'], ['Citas', 'reuniones'], ['Metas y cumplimiento', 'metas'],
    ['Facturación', 'facturacion'], ['Ranking', 'ranking-vendedores'],
    ['Gestión Diaria', 'gestion-diaria'], ['Cartera', 'mi-cartera'],
    ['Rendimiento', 'rendimiento'], ['Conversiones', 'conversiones'], ['Empresas', 'informes-empresas'],
    ['Leads', 'cartera'], ['Pipeline', 'pipeline'], ['Agenda', 'agenda'],
    ['Repartir leads', 'repartir'], ['Base para gestión', 'rescate'], ['Seguimiento', 'seguimiento'],
    ['Gestión de equipo', 'equipo'], ['Configuración', 'config'],
  ] as const
  const nav = page.getByRole('navigation', { name: 'Navegación principal de Gerencia' })
  for (const [nombre, ruta] of destinos) await test.step(nombre, async () => {
    await irAModulo(page, nombre)
    await expect(page).toHaveURL(new RegExp(`#/${ruta}$`))
    await expect(page.getByRole('dialog', { name: 'Más opciones' })).toHaveCount(0)
    await expect(page.locator('main').getByRole('heading', { level: 1 }).first()).toBeVisible()
    const cajaNav = (await nav.boundingBox())!
    const cajaMain = (await page.locator('main').boundingBox())!
    expect(cajaMain.x).toBe(0)
    expect(cajaMain.y + cajaMain.height).toBeLessThanOrEqual(cajaNav.y)
    expect(cajaNav.y + cajaNav.height).toBe(844)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  })
  expect(solicitudes()).toBe(0)
})

test('subruta de Configuración conserva selección al recargar y permite cerrar sesión', async ({ page }) => {
  await bloquearSupabase(page)
  await entrarDemo(page, 'Gerencia')
  // Control de Citas exige superadmin; Gerencia demo conserva la redirección.
  await page.goto('/#/config-citas')
  await expect(page).toHaveURL(/#\/hoy$/)
  await page.goto('/#/config-metas')
  await page.reload()
  await expect(page).toHaveURL(/#\/config-metas$/)
  const mas = page.getByRole('navigation', { name: 'Navegación principal de Gerencia' }).getByRole('button', { name: 'Más', exact: true })
  await expect(mas).toHaveAttribute('aria-current', 'true')
  await mas.tap()
  const panel = page.getByRole('dialog', { name: 'Más opciones' })
  await expect(panel.getByRole('button', { name: 'Configuración', exact: true })).toHaveAttribute('aria-current', 'page')
  await panel.getByRole('button', { name: 'Cerrar sesión' }).tap()
  await expect(panel).toHaveCount(0)
  await expect(page.getByRole('button', { name: /explorar en modo demo/i })).toBeVisible()
})

test('Más en horizontal: cabecera y cuenta visibles, lista desplazable y navegación operable', async ({ page }, info) => {
  await page.setViewportSize({ width: 667, height: 375 })
  await bloquearSupabase(page)
  await entrarDemo(page, 'Gerencia')
  await page.getByRole('button', { name: 'Más', exact: true }).tap()
  const panel = page.getByRole('dialog', { name: 'Más opciones' })
  await panel.getByText('Administración', { exact: true }).tap()
  await panel.getByRole('button', { name: 'Configuración', exact: true }).scrollIntoViewIfNeeded()
  const cajaPanel = (await panel.boundingBox())!
  const cerrar = (await panel.getByRole('button', { name: 'Cerrar más opciones' }).boundingBox())!
  const salir = (await panel.getByRole('button', { name: 'Cerrar sesión' }).boundingBox())!
  expect(cajaPanel.y).toBeGreaterThanOrEqual(0)
  expect(cerrar.y).toBeGreaterThanOrEqual(cajaPanel.y)
  expect(salir.y + salir.height).toBeLessThanOrEqual(375)
  await page.screenshot({ path: info.outputPath('mas-horizontal.png') })
  await panel.getByRole('button', { name: 'Configuración', exact: true }).tap()
  await expect(page).toHaveURL(/#\/config$/)
})
