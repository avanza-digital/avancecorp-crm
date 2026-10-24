import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'
import { irAModulo } from './_navegacion'
import abierto from '../src/lib/__fixtures__/capital-valorado/activo.json' with { type: 'json' }
import pendiente from '../src/lib/__fixtures__/capital-valorado/pendiente.json' with { type: 'json' }
import detalle from '../src/lib/__fixtures__/capital-valorado/detalle.json' with { type: 'json' }
import facturacion from '../src/lib/__fixtures__/capital-valorado/facturacion.json' with { type: 'json' }
import listaFacturacion from '../src/lib/__fixtures__/capital-valorado/facturacion-lista.json' with { type: 'json' }

const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }

test('Facturación abre la cifra guardada y explica su tasa por operación en escritorio y móvil', async ({ page }, testInfo) => {
  await page.clock.setFixedTime(new Date('2026-10-16T17:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial', cumplimientoMetas: abierto })
  await page.route('**/rest/v1/rpc/facturacion_diaria_v2_fn', (route) => route.fulfill({ headers: CORS,
    json: route.request().postDataJSON().p_mes === '2026-10-01' ? facturacion : { version: 2, valoracion_activa: false, filas: [] } }))
  await page.route('**/functions/v1/crm-tipo-cambio', (route) => route.fulfill({ headers: CORS, json: { promedio: 3.1, fuente: 'BCRP', fecha_corte: route.request().postDataJSON()?.fecha_corte } }))
  const pedidos: unknown[] = []
  await page.route('**/rest/v1/rpc/listar_operaciones_facturacion_v3_fn', async (route) => {
    const pedido = route.request().postDataJSON()
    expect(pedido.p_cortes).toEqual(listaFacturacion.cortes)
    expect(pedido).not.toHaveProperty('tasasLegadas')
    pedidos.push(pedido)
    await route.fulfill({ headers: CORS, json: listaFacturacion })
  })
  await loginReal(page)
  await irAModulo(page, 'Facturación')
  for (const ancho of [1440, 390]) {
    await page.setViewportSize({ width: ancho, height: 844 })
    const total = page.getByRole('button', { name: /^Total facturado: S\/ 142,400, ver el desglose$/ })
    await expect(total).toBeVisible()
    await total.click()
    const lista = page.locator('.lista-operaciones')
    await expect(lista).toContainText('Cuadra. Pulsaste S/ 142,400')
    await expect(lista).toContainText('S/ 62,000 equivalentes')
    await expect(lista).toContainText('Tipo de cambio S/ 3.1000')
    await expect(lista).toContainText('Cliente de otro equipo')
    await expect(lista).not.toContainText('× 3.1')
    if (ancho === 390) await page.screenshot({ path: testInfo.outputPath('facturacion-corte-movil.png'), fullPage: true })
    await page.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  }
  expect(pedidos.length).toBeGreaterThan(0)
})

test('ranking conserva el corte guardado con otra cotización y muestra su detalle en escritorio y móvil', async ({ page }, testInfo) => {
  await page.clock.setFixedTime(new Date('2026-10-16T17:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial', cumplimientoMetas: abierto })
  let tasa = 3.4
  let mostrarPendiente = false
  await page.route('**/rest/v1/rpc/cumplimiento_metas_v2_fn', (route) => route.fulfill({ headers: CORS, json: mostrarPendiente ? pendiente : abierto }))
  await page.route('**/functions/v1/crm-tipo-cambio', (route) => route.fulfill({ headers: CORS, json: { promedio: tasa, fuente: 'BCRP' } }))
  await page.route('**/rest/v1/rpc/capital_operaciones_valoradas_v2_fn', async (route) => {
    expect(route.request().postDataJSON().p_corte_id).toBe(abierto.capital_valoracion.corte_id)
    await route.fulfill({ headers: CORS, json: detalle })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Ranking', exact: true }).click()
  await page.getByRole('tab', { name: 'Capital total', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Ranking de capital total en soles' })).toContainText('S/ 74,000')
  await expect(page.getByText(/Capital en soles con TC fijado por venta/)).toBeVisible()
  await page.getByRole('button', { name: 'Ver detalle de Persona sintética 2', exact: true }).first().click()
  await expect(page.getByRole('region', { name: 'Ventas con tipo de cambio fijado' })).toContainText('S/ 62,000')
  await page.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()

  tasa = 3.1
  mostrarPendiente = true
  await page.reload()
  await page.getByRole('button', { name: 'Ranking', exact: true }).click()
  await page.getByRole('tab', { name: 'Capital total', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Ranking de capital total en soles' })).toContainText('S/ 74,000')
  await expect(page.getByText(/1 venta pendiente de valoración/)).toBeVisible()
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(page.getByRole('list', { name: 'Ranking de capital total en soles' })).toContainText('S/ 74,000')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
  await page.screenshot({ path: testInfo.outputPath('capital-valorado-movil.png'), fullPage: true })
})
