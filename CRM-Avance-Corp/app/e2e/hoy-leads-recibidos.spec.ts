import { expect, test, type Page } from '@playwright/test'
import { leadReal, loginReal, montarBackendReal, UID } from './_helpers'

// En Tokio ya es 6 de octubre; el dashboard debe seguir mostrando el 5 de Lima.
test.use({ timezoneId: 'Asia/Tokyo' })
const AHORA = '2026-10-06T04:30:00Z'
const HOY = '2026-10-05'

async function montarHoy(page: Page, cantidad: number, caido = false) {
  await page.clock.setFixedTime(new Date(AHORA))
  const recibidos = Array.from({ length: cantidad }, (_, i) => leadReal({
    id: `cccccccc-0000-4000-8000-${String(i).padStart(12, '0')}`,
    nombre_completo: `RECIBIDO HOY ${String(i + 1).padStart(2, '0')}`,
    vendedor_id: UID, etapa: 'contactado',
    creado_en: '2026-09-01T15:00:00Z',
    actualizado_en: new Date(Date.parse(AHORA) - i * 60000).toISOString(),
  }))
  await montarBackendReal(page, { rolCrm: 'vendedor', leads: recibidos,
    tareas: recibidos[0] ? [{
      id: 'dddddddd-0000-4000-8000-000000000001', lead_id: recibidos[0].id, perfil_id: null,
      vendedor_id: UID, asignado_supervisor_id: null, tipo: 'reunion', titulo: 'Cita de hoy', nota: null,
      vence_en: '2026-10-06T04:45:00Z', estado: 'pendiente', activo: true, reprogramaciones: 0,
      creado_en: '2026-10-05T15:00:00Z', duracion_min: 30, modalidad_reunion: 'virtual',
      ubicacion_reunion: null, enlace_reunion: 'https://meet.google.com/abc-defg-hij', resultado_reunion: null,
      motivo_no_realizada: null, detalle_cierre_reunion: null, confirmada_en: null, reagendada_de: null,
    }] : [],
  })
  // Activo es el modo usado en producción, con agenda y citas siempre visibles.
  await page.route('**/rest/v1/rpc/estado_sla_leads_v2_fn', route => route.fulfill({ json: {
    version: 2, modo: 'activo', control_revision: 1, calculado_en: AHORA, filas: [],
  } }))
  const consultas: Record<string, unknown>[] = []
  let fallar = caido
  await page.route('**/rest/v1/rpc/cartera_filtrada_fn', async route => {
    const pedido = route.request().postDataJSON() as Record<string, unknown>
    if (!pedido.p_desde) return route.fallback()
    consultas.push(pedido)
    expect(pedido.p_desde).toBe(HOY)
    expect(pedido.p_hasta).toBe(HOY)
    expect(pedido.p_vendedor_id).toBe(UID)
    expect(pedido.p_etapa).toBeUndefined()
    expect(pedido.p_gestion).toBeUndefined()
    if (fallar) return route.fulfill({ status: 500, json: { message: 'sin conexión', code: 'PGRST000' } })
    const inicio = pedido.p_antes_id ? recibidos.findIndex(l => l.id === pedido.p_antes_id) + 1 : 0
    await route.fulfill({ json: {
      version: 1, generado_en: AHORA, desde: HOY, hasta: HOY,
      items: recibidos.slice(inicio, inicio + Number(pedido.p_limite)).map(l => ({
        ...l, ultimo_contacto_en: null, recibido_en: '2026-10-05T14:30:00Z', recepcion_aproximada: false,
      })),
      resumen: {
        totales: { vivos: cantidad, abiertos: cantidad, asignados: cantidad, parkeados: 0, convertidos: 0,
          descartados: 0, asignados_pen: cantidad, asignados_usd: 0 },
        capital: { asignado: { pen: cantidad * 1000, usd: 0 }, parkeado: { pen: 0, usd: 0 }, ganado: { pen: 0, usd: 0 } },
        embudo: [{ etapa: 'contactado', n: cantidad }],
      },
    } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Hoy', exact: true }).click()
  return { consultas, recuperar: () => { fallar = false } }
}

test('Hoy lista los recibidos en Lima, pagina y abre la ficha; cabe en escritorio y móvil', async ({ page }) => {
  await page.setViewportSize({ width: 1512, height: 900 })
  const { consultas } = await montarHoy(page, 55)
  const panel = page.getByRole('region', { name: 'Leads recibidos hoy' })
  await expect(panel.getByText('55 leads recibidos hoy')).toBeVisible()
  await expect(panel.getByRole('listitem')).toHaveCount(50)
  await expect(page.getByRole('heading', { name: 'Tu agenda de hoy', exact: true })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Tus citas', exact: true })).toBeVisible()
  const citas = page.getByRole('heading', { name: 'Tus citas', exact: true }).locator('..').locator('..')
  const anchoPanel = await panel.evaluate(el => el.getBoundingClientRect().width)
  expect(await citas.evaluate(el => el.getBoundingClientRect().width)).toBeCloseTo(anchoPanel, 0)
  await expect(citas.getByRole('button', { name: 'Cerrar tarea — Cita de hoy', exact: true })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Tu cumplimiento del mes', exact: true })).toBeVisible()
  await page.screenshot({ path: test.info().outputPath('hoy-recibidos-desktop.png'), fullPage: true })
  const alto = await page.evaluate(() => ({ total: document.documentElement.scrollHeight, visible: innerHeight }))
  expect(alto.total).toBeLessThanOrEqual(alto.visible)
  await page.setViewportSize({ width: 1280, height: 800 })
  const listaCitas = citas.locator('.overflow-y-auto')
  expect(await listaCitas.evaluate(el => el.clientHeight)).toBeGreaterThanOrEqual(48)
  await page.screenshot({ path: test.info().outputPath('hoy-recibidos-portatil.png'), fullPage: true })
  await panel.getByRole('button', { name: 'Cargar más leads de hoy' }).click()
  await expect(panel.getByRole('listitem')).toHaveCount(55)
  await expect(panel.getByRole('button', { name: 'Abrir lead RECIBIDO HOY 51' })).toBeFocused()
  expect(consultas.at(-1)?.p_antes_id).toBe('cccccccc-0000-4000-8000-000000000049')
  await panel.getByRole('button', { name: 'Abrir lead RECIBIDO HOY 55' }).click()
  await expect(page.getByRole('dialog', { name: 'RECIBIDO HOY 55', exact: true })).toBeVisible()
  await page.keyboard.press('Escape')
  await page.setViewportSize({ width: 390, height: 844 })
  const menu = page.getByRole('button', { name: 'Ocultar menú', exact: true })
  if (await menu.isVisible()) await menu.click()
  await panel.scrollIntoViewIfNeeded()
  await expect(panel.getByRole('heading', { name: 'Leads recibidos hoy' })).toBeVisible()
  await page.screenshot({ path: test.info().outputPath('hoy-recibidos-mobile.png'), fullPage: true })
  const ancho = await page.evaluate(() => ({ total: document.documentElement.scrollWidth, visible: innerWidth }))
  expect(ancho.total).toBeLessThanOrEqual(ancho.visible)
})

test('un fallo no se presenta como cero recibidos; se puede reintentar hasta el vacío real', async ({ page }) => {
  const { recuperar } = await montarHoy(page, 0, true)
  const panel = page.getByRole('region', { name: 'Leads recibidos hoy' })
  await expect(panel.getByRole('alert')).toContainText('No se pudieron cargar')
  await expect(panel.getByText('Todavía no has recibido leads hoy.')).toHaveCount(0)
  recuperar()
  await panel.getByRole('button', { name: 'Reintentar' }).click()
  await expect(panel.getByText('Todavía no has recibido leads hoy.')).toBeVisible()
  await expect(panel.getByText('0 leads recibidos hoy')).toBeVisible()
  const citas = page.getByRole('heading', { name: 'Tus citas', exact: true }).locator('..').locator('..')
  expect(await citas.evaluate(el => el.getBoundingClientRect().width)).toBeCloseTo(await panel.evaluate(el => el.getBoundingClientRect().width), 0)
})
