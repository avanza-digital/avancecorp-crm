import { expect, test, type Page } from '@playwright/test'
import { entrarDemo, loginReal, montarBackendReal } from './_helpers'
import { montarColaEquipo, type PedidoCola } from './_sla-cola'

// Prueba el recorrido real de la UI con transporte interceptado. Las filas
// parten del contrato SQL existente; esta suite no acredita RLS del servidor.
async function abrirCola(page: Page) {
  await loginReal(page)
  await page.goto('/#/gestion-diaria/cola')
  await expect(page.getByRole('link', { name: 'Seguimiento completo', exact: true })).toHaveAttribute('aria-current', 'page')
  await expect(page.getByRole('heading', { name: 'Seguimiento comercial', exact: true })).toBeVisible()
}

const listaCola = (page: Page) => page.getByRole('list', { name: 'Oportunidades de esta página' })

test('F6 gerencia: 105 oportunidades, página 50, ficha fuera del lote y enlaces conservados', async ({ page }, info) => {
  const { pedidos } = await montarColaEquipo(page, 'gerencia', 105)
  const id = 'cccccccc-0000-4000-8000-000000000101'
  let lecturasId = 0
  await page.route('**/rest/v1/leads?*', async (route) => {
    if (new URL(route.request().url()).searchParams.get('id') === `eq.${id}`) lecturasId += 1
    await route.fallback()
  })
  await abrirCola(page)
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(10)
  const limite = page.getByRole('combobox', { name: 'Por página', exact: true })
  await limite.selectOption('25')
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(25)
  await limite.selectOption('50')
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(50)
  const siguiente = page.getByRole('button', { name: 'Siguiente', exact: true })
  for (const desde of [51, 101]) {
    await siguiente.click()
    await expect(page.getByText(new RegExp(`^${desde}–.* de 105 oportunidades`))).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Seguimiento comercial', exact: true })).toBeFocused()
  }
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(5)
  await expect(siguiente).toBeDisabled()
  expect(pedidos.at(-1)).toMatchObject({ p_limite: 50, p_cursor: { inicio: 100 } })
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria\/cola$/)
  await expect(page.getByText(/^101–105 de 105 oportunidades/)).toBeVisible()
  await page.screenshot({ path: info.outputPath('f6-cola-105-escritorio.png'), fullPage: true })
  await listaCola(page).getByRole('button', { name: /OPORTUNIDAD SUR 101/ }).click()
  const ficha = page.getByRole('dialog', { name: 'OPORTUNIDAD SUR 101', exact: true })
  await expect(ficha).toBeVisible()
  expect(lecturasId).toBe(1)
  await expect(page).toHaveURL(new RegExp(`/gestion-diaria/cola/lead/${id}$`))
  await page.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria\/cola$/)
  await expect(limite).toHaveValue('50')
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(5)
  await page.goBack()
  await expect(ficha).toBeVisible()
  await page.goForward()
  await expect(ficha).toHaveCount(0)
  await expect(page.getByText(/^101–105 de 105 oportunidades/)).toBeVisible()
  await page.goto(`/#/gestion-diaria/cola/lead/${id}`)
  await page.reload()
  await expect(ficha).toBeVisible()
  await page.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria\/cola$/)
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(10)
  await page.goto(`/#/seguimiento/lead/${id}`)
  await expect(ficha).toBeVisible()
  await page.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
  await expect(page).toHaveURL(/#\/seguimiento$/)
  await expect(page.getByRole('heading', { name: 'Seguimiento comercial', exact: true })).toBeVisible()
})

test('F6 supervisor: filtros de equipo, cursor vencido y recuperación ante revocación', async ({ page }) => {
  const { pedidos, analistaUno, analistaAjeno } = await montarColaEquipo(page, 'supervisor')
  let cursorVencido = false
  let cursoresRechazados = 0
  let revocado = false
  await page.route('**/rest/v1/rpc/cola_accion_v3_fn', async (route) => {
    const args = route.request().postDataJSON() as PedidoCola
    if (revocado) return route.fulfill({ status: 403, json: { code: '42501', message: 'Acceso revocado' } })
    if (cursorVencido && args.p_cursor) {
      cursoresRechazados += 1
      return route.fulfill({ status: 400, json: { code: '22023', message: 'Cursor vencido' } })
    }
    return route.fallback()
  })
  await abrirCola(page)
  const analista = page.getByRole('combobox', { name: 'Analista', exact: true })
  const etapa = page.getByRole('combobox', { name: 'Etapa', exact: true })
  await expect(analista.locator(`option[value="${analistaAjeno}"]`)).toHaveCount(0)
  await page.getByRole('group', { name: 'Prioridades de seguimiento' }).getByRole('button', { name: /Revisión comercial/ }).click()
  await etapa.selectOption('contactado')
  await analista.selectOption(analistaUno)
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(2)
  expect(pedidos.at(-1)).toMatchObject({ p_senal: 'revisiones', p_etapa: 'contactado', p_analista_id: analistaUno, p_cursor: null })
  await listaCola(page).getByRole('button').first().click()
  await expect(page.getByRole('dialog')).toBeVisible()
  await page.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria\/cola$/)
  await expect(analista).toHaveValue(analistaUno)
  await expect(etapa).toHaveValue('contactado')
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(2)
  await page.getByRole('button', { name: 'Limpiar filtros', exact: true }).click()
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(10)
  cursorVencido = true
  await page.getByRole('button', { name: 'Siguiente', exact: true }).click()
  await expect.poll(() => cursoresRechazados).toBeGreaterThan(0)
  await expect(page.getByText(/^1–10 de 12 oportunidades/)).toBeVisible()
  revocado = true
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(page.getByRole('alert')).toContainText('Los pendientes todavía no están confirmados')
  await expect(listaCola(page)).toHaveCount(0)
  await expect(page.getByText(/de 12 oportunidades/)).toHaveCount(0)
  revocado = false
  await page.getByRole('button', { name: 'Reintentar', exact: true }).click()
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(10)
  await page.getByRole('group', { name: 'Prioridades de seguimiento' }).getByRole('button', { name: /Datos incompletos/ }).click()
  await expect(page.getByText('No hay oportunidades con estos filtros.', { exact: true })).toBeVisible()
  await expect(page.getByText(/^0–0 de 0 oportunidades/)).toBeVisible()
})

test('F6 analista: móvil y teclado, acciones propias y vuelta al resumen', async ({ page }, info) => {
  await montarColaEquipo(page, 'vendedor', 12)
  await abrirCola(page)
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(page.getByRole('combobox', { name: 'Analista', exact: true })).toHaveCount(0)
  const mostrar = page.getByRole('combobox', { name: 'Mostrar', exact: true })
  await expect(mostrar).toBeVisible()
  await expect(mostrar.locator('option[value="revisiones"], option[value="por_repartir"]')).toHaveCount(0)
  const siguiente = page.getByRole('button', { name: 'Siguiente', exact: true })
  await siguiente.focus()
  await siguiente.press('Enter')
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(2)
  await expect(page.getByRole('heading', { name: 'Seguimiento comercial', exact: true })).toBeFocused()
  await page.getByRole('link', { name: 'Seguimiento completo', exact: true }).scrollIntoViewIfNeeded()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: info.outputPath('f6-cola-analista-movil.png'), fullPage: true })
  await listaCola(page).getByRole('button').first().click()
  await expect(page.getByRole('dialog')).toBeVisible()
  await expect(page).toHaveURL(/#\/gestion-diaria\/cola\/lead\//)
  await page.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(2)
  await page.getByRole('link', { name: 'Resumen del día', exact: true }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria$/)
  // Diseño del 27/09/2026: en su resumen el analista lleva un solo acceso,
  // «Seguimiento completo ›», en la cabecera de «Mi día».
  await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toBeVisible()
  await expect(page.getByRole('link', { name: /Seguimiento completo/ })).toBeVisible()
  await page.goBack()
  await expect(page).toHaveURL(/#\/gestion-diaria\/cola$/)
  await expect(listaCola(page).locator(':scope > li')).toHaveCount(10)
})

for (const rol of ['supervisor', 'vendedor'] as const) {
  test(`F6 ${rol}: normaliza detalles gerenciales sin perder una ficha permitida`, async ({ page }) => {
    await montarColaEquipo(page, rol)
    await loginReal(page)
    const id = 'cccccccc-0000-4000-8000-000000000001'
    for (const tipo of ['equipo', 'analista']) {
      await page.goto(`/#/gestion-diaria/${tipo}/aaaaaaaa-0000-4000-8000-000000000001/lead/${id}`)
      await expect(page).toHaveURL(new RegExp(`#/gestion-diaria/lead/${id}$`))
      await expect(page.getByRole('dialog', { name: 'OPORTUNIDAD NORTE 01', exact: true })).toBeVisible()
      await page.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
      await expect(page).toHaveURL(/#\/gestion-diaria$/)
      await expect(listaCola(page)).toHaveCount(0)
      await page.getByRole('link', { name: 'Seguimiento completo', exact: true }).click()
      await expect(page).toHaveURL(/#\/gestion-diaria\/cola$/)
      await expect(listaCola(page).locator(':scope > li')).toHaveCount(10)
    }
  })
}

for (const rol of ['directorio', 'coordinador'] as const) {
  test(`F6 enlace directo no habilita la cola a ${rol}`, async ({ page }) => {
    await montarBackendReal(page, { rolCrm: rol, rolPortal: rol === 'directorio' ? 'directorio' : 'analista' })
    await loginReal(page)
    await page.goto('/#/gestion-diaria/cola/lead/cccccccc-0000-4000-8000-000000000001')
    await expect(page).not.toHaveURL(/gestion-diaria/)
    await expect(page.getByRole('navigation', { name: 'Secciones de Gestión Diaria' })).toHaveCount(0)
    await expect(listaCola(page)).toHaveCount(0)
    await expect(page.getByRole('dialog')).toHaveCount(0)
  })
}

test('F6 distingue SLA apagado y error de carga sin inferir cero pendientes', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor' })
  await abrirCola(page)
  await expect(page.getByText(/El seguimiento comercial no está activo/)).toBeVisible()
  await expect(page.getByText(/0 oportunidades/)).toHaveCount(0)
  await page.route('**/rest/v1/rpc/estado_sla_leads_v2_fn', (route) => route.fulfill({ status: 500, json: { code: 'XX000', message: 'Fallo controlado' } }))
  await page.reload()
  await expect(page.getByRole('alert')).toContainText('Los pendientes todavía no están confirmados')
  await expect(listaCola(page)).toHaveCount(0)
})

test('F6 demo informa disponibilidad en sesión real', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.goto('/#/gestion-diaria/cola')
  await expect(page.getByText('El seguimiento comercial operativo está disponible en la sesión real.', { exact: true })).toBeVisible()
  await expect(listaCola(page)).toHaveCount(0)
})
