// Navegación autenticada interceptada; permisos reales en el banco PostgreSQL del mismo kit.
import { expect, test, type Page } from '@playwright/test'
import { loginReal, montarBackendReal, rankingAgostoReal } from './_helpers'

const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
const ANA = 'b0000000-0000-4000-8000-000000000001'
const SIN_VENTAS = 'b0000000-0000-4000-8000-000000000002'
const SUP = 'a0000000-0000-4000-8000-000000000001'
const equipo = [
  { perfil_id: SUP, nombre_completo: 'SUPERVISORA PRUEBA', rol_crm: 'supervisor', supervisor_id: null, activo: true },
  { perfil_id: ANA, nombre_completo: 'ANA PRUEBA', rol_crm: 'vendedor', supervisor_id: SUP, activo: true },
  { perfil_id: SIN_VENTAS, nombre_completo: 'ANALISTA SIN VENTAS', rol_crm: 'vendedor', supervisor_id: SUP, activo: true },
]

async function preparar(page: Page, roster: 'normal' | 'error' = 'normal') {
  const pedidos: string[] = []
  page.on('request', (r) => {
    const p = new URL(r.url()).pathname
    if (r.method() === 'POST' && p.includes('/rest/v1/rpc/')) pedidos.push(p.split('/').at(-1)!)
  })
  await page.clock.setFixedTime(new Date('2026-10-09T15:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'coordinador', rolPortal: 'comercial' })
  await page.route('**/rest/v1/rpc/equipo_reportes_fn', (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    return route.fulfill(roster === 'error'
      ? { status: 500, headers: CORS, json: { code: 'XX000', message: 'No disponible' } }
      : { headers: CORS, json: equipo })
  })
  await page.route('**/rest/v1/rpc/facturacion_diaria_fn', (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    return route.fulfill({ headers: CORS, json: route.request().postDataJSON().p_mes === '2026-10-01' ? [{
      dia: '2026-10-05', tipo: 'contrato_nuevo', moneda: 'PEN', capital: 27000, operaciones: 1,
      analista_id: ANA, analista_nombre: 'ANA PRUEBA', supervisor_id: SUP, supervisor_nombre: 'SUPERVISORA PRUEBA',
    }] : [] })
  })
  await page.route('**/rest/v1/rpc/listar_operaciones_facturacion_v2_fn', (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    return route.fulfill({ headers: CORS, json: { version: 2, pagina: 1, tamano: 25, total: 1,
      totales: [{ moneda: 'PEN', operaciones: 1, monto: 27000 }], filas: [{
        n: 1, fecha: '2026-10-05', tipo: 'contrato_nuevo', moneda: 'PEN', monto: 27000, anulado: false,
        analista_id: ANA, analista_nombre: 'ANA PRUEBA', supervisor_id: SUP, supervisor_nombre: 'SUPERVISORA PRUEBA',
        visible: false, nombre_visible: true, cliente_nombre: 'CLIENTE DEL REPORTE',
      }] } })
  })
  await loginReal(page)
  return pedidos
}

test('Coordinación consulta nombres en Facturación y conserva el reporte sin ficha de clientes', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  const pedidos = await preparar(page)
  await expect(page).toHaveURL(/#\/repartir$/)
  expect(pedidos).not.toContain('equipo_reportes_fn')
  expect(pedidos).not.toContain('cumplimiento_metas_fn')
  await page.getByRole('button', { name: 'Facturación', exact: true }).click()
  const malla = page.getByRole('region', { name: /Facturación diaria/ })
  await expect(malla.getByText('ANALISTA SIN VENTAS', { exact: true })).toBeVisible()
  await malla.getByRole('button', { name: /^ANA PRUEBA, lunes, 5 de octubre: S\/ 27,000, ver 1 operación$/ }).click()
  const panel = page.locator('.lista-operaciones')
  await expect(panel).toContainText('CLIENTE DEL REPORTE')
  await expect(panel).not.toContainText('Cliente de otro equipo')
  await expect(panel.getByRole('link')).toHaveCount(0)
  await expect(panel.getByRole('button', { name: /Abrir|Ver ficha|Editar|Anular/ })).toHaveCount(0)
  await page.keyboard.press('Escape')
  for (const nombre of ['Mi cartera', 'Equipo', 'Configuración', 'Pipeline', 'Metas']) {
    await expect(page.getByRole('button', { name: nombre, exact: true })).toHaveCount(0)
  }
  await page.evaluate(() => { window.location.hash = '#/configuracion' })
  await expect(page).toHaveURL(/#\/repartir$/)
  expect(pedidos).toContain('equipo_reportes_fn')
  expect(pedidos).toContain('equipo_visible_fn')
  await expect(page.getByRole('button', { name: 'Cartera', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Leads', exact: true })).toBeVisible()
})

test('Ranking de Coordinación consulta el mes completo y permite cambiar la lectura', async ({ page }) => {
  const foto = rankingAgostoReal()
  await page.clock.setFixedTime(new Date('2026-09-02T15:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'coordinador', rolPortal: 'comercial',
    configuracionMetas: foto.configuracionMetas, cumplimientoMetas: foto.cumplimientoMetas,
    metricas: { conversionMensual: foto.conversionMensual, cosecha: foto.cosecha } })
  await page.route('**/rest/v1/rpc/equipo_reportes_fn', (route) => route.request().method() !== 'POST'
    ? route.fallback() : route.fulfill({ headers: CORS, json: equipo }))
  await loginReal(page)
  await page.getByRole('button', { name: 'Ranking', exact: true }).click()
  await page.getByLabel('Mes calendario').fill('2026-08')
  const tabla = page.getByRole('table', { name: 'Ranking de conversión general' })
  // La identidad histórica viene de la foto: ANA AGOSTO no está en equipo_reportes_fn.
  await expect(tabla.getByRole('row', { name: /ANA AGOSTO/ })).toContainText('8.33%')
  await page.getByRole('tab', { name: 'Capital total' }).click()
  await expect(page.getByRole('table', { name: 'Ranking de capital total en soles' })
    .getByRole('row', { name: /ANA AGOSTO/ })).toContainText('S/ 43,530')
  await page.getByRole('tab', { name: 'Resultados de los leads del mes' }).click()
  await expect(page.getByRole('list', { name: 'Resultados de los leads del mes por analista' })
    .getByText('ANA AGOSTO')).toBeVisible()
  await page.getByRole('button', { name: 'Repartir leads', exact: true }).click()
  await expect(page).toHaveURL(/#\/repartir$/)
})

test('una caída del roster de reportes deja Repartir disponible y no muestra cifras falsas', async ({ page }) => {
  await preparar(page, 'error')
  await page.getByRole('button', { name: 'Facturación', exact: true }).click()
  await expect(page.getByText('No se pudo cargar la facturación de este mes.')).toBeVisible({ timeout: 15000 })
  await expect(page.getByRole('region', { name: /Facturación diaria/ })).toHaveCount(0)
  await page.getByRole('button', { name: 'Repartir leads', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Repartir leads', exact: true })).toBeVisible()
})
