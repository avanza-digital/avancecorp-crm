import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal, UID } from './_helpers'
import { irAModulo } from './_navegacion'
import pendiente from '../test-fixtures/capital-pendientes/pendiente.json' with { type: 'json' }
import activo from '../test-fixtures/capital-pendientes/activo.json' with { type: 'json' }
import detallePendiente from '../test-fixtures/capital-pendientes/detalle-pendiente.json' with { type: 'json' }
import detalleActivo from '../test-fixtures/capital-pendientes/detalle-activo.json' with { type: 'json' }
import facturacion from '../test-fixtures/capital-pendientes/facturacion-pendiente.json' with { type: 'json' }
import lista from '../test-fixtures/capital-pendientes/lista-pendiente.json' with { type: 'json' }

const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
const aviso = /US\$ 20,000 pendiente de tipo de cambio\. No incluido/

test('Facturación mantiene ambos PEN y concilia su lista mientras el USD espera TC', async ({ page }, testInfo) => {
  await page.clock.setFixedTime(new Date('2026-10-23T18:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial', cumplimientoMetas: pendiente })
  await page.route('**/rest/v1/rpc/facturacion_diaria_v2_fn', (route) => route.fulfill({ headers: CORS,
    json: route.request().postDataJSON().p_mes === '2026-10-01' ? facturacion : { version: 2, valoracion_activa: false, filas: [] } }))
  await page.route('**/rest/v1/rpc/listar_operaciones_facturacion_v3_fn', (route) => {
    expect(route.request().postDataJSON().p_cortes).toEqual(lista.cortes)
    return route.fulfill({ headers: CORS, json: lista })
  })
  await loginReal(page)
  await irAModulo(page, 'Facturación')
  await expect(page.getByText(aviso)).toBeVisible()
  await expect(page.getByText('Pendientes del mes completo, antes de aplicar los filtros del cuadro.')).toBeVisible()
  await page.getByRole('button', { name: 'Total de lo que estás viendo: S/ 6,000, ver 2 operaciones', exact: true }).click()
  const detalle = page.locator('.lista-operaciones')
  await expect(detalle).toContainText('Cuadra. Pulsaste S/ 6,000')
  // La fixture nativa preserva la privacidad del cliente y oculta el número de contrato.
  const filas = detalle.getByRole('row')
  await expect(filas).toHaveCount(3)
  await expect(filas.filter({ hasText: 'S/ 1,000' })).toHaveCount(1)
  await expect(filas.filter({ hasText: 'S/ 5,000' })).toHaveCount(1)
  await expect(detalle).not.toContainText('US$')
  await page.screenshot({ path: testInfo.outputPath('facturacion-pendiente.png'), fullPage: true })
})

test('metas y detalle del analista incorporan el USD cuando llega el tipo de cambio', async ({ page }, testInfo) => {
  await page.clock.setFixedTime(new Date('2026-10-23T18:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial', cumplimientoMetas: pendiente })
  let conTipoCambio = false
  await page.route('**/rest/v1/rpc/cumplimiento_metas_v2_fn', (route) => route.fulfill({ headers: CORS, json: conTipoCambio ? activo : pendiente }))
  await page.route('**/rest/v1/rpc/capital_operaciones_valoradas_v2_fn', (route) => {
    const respuesta = conTipoCambio ? detalleActivo : detallePendiente
    expect(route.request().postDataJSON().p_corte_id).toBe(respuesta.corte_id)
    return route.fulfill({ headers: CORS, json: respuesta })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Ranking', exact: true }).click()
  await page.getByRole('tab', { name: 'Capital total', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Ranking de capital total en soles' })).toContainText('S/ 6,000')
  await expect(page.getByText(aviso)).toBeVisible()
  await page.getByRole('button', { name: 'Ver detalle de Persona sintética 2', exact: true }).first().click()
  const ventas = page.getByRole('region', { name: 'Ventas con tipo de cambio fijado' })
  await expect(ventas).toContainText('PENDIENTES-PEN-12')
  await ventas.getByText(/1 venta pendiente de valoración/).click()
  await expect(ventas.getByText('US$ 20,000 pendiente de tipo de cambio · Contrato · 23/10/2026', { exact: true })).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('analista-pendiente.png'), fullPage: true })
  conTipoCambio = true
  await page.reload()
  await page.getByRole('button', { name: 'Ranking', exact: true }).click()
  await page.getByRole('tab', { name: 'Capital total', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Ranking de capital total en soles' })).toContainText('S/ 74,000')
  await expect(page.getByText(aviso)).toHaveCount(0)
  await page.getByRole('button', { name: 'Ver detalle de Persona sintética 2', exact: true }).first().click()
  await expect(ventas).toContainText('PENDIENTES-USD-11')
  await expect(ventas).toContainText('S/ 68,000')
})

test('el propio analista ve capital PEN actualizado y USD pendiente en su cumplimiento', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-10-23T18:00:00Z'))
  const propio = JSON.parse(JSON.stringify(pendiente).replaceAll('f3000000-0000-4000-8000-000000000002', UID))
  const configuracionMetas = {
    version: 1, periodo: propio.periodo, revision: propio.revision, publicada_en: propio.publicada_en,
    publicada_por: null, publicada_por_nombre: null, puede_editar: false,
    vendedores: propio.vendedores.map((vendedor: typeof pendiente.vendedores[number]) => ({
      vendedor_id: vendedor.vendedor_id, nombre: vendedor.nombre,
      supervisor_id: vendedor.supervisor_id, supervisor_nombre: vendedor.supervisor_nombre,
      conversion_objetivo: vendedor.conversion_objetivo,
      detalles: vendedor.detalles.map(({ categoria, moneda, capital_objetivo, contratos_objetivo }) =>
        ({ categoria, moneda, capital_objetivo, contratos_objetivo })),
    })),
  }
  await montarBackendReal(page, { rolCrm: 'vendedor', rolPortal: 'comercial', cumplimientoMetas: propio, configuracionMetas })
  await page.route('**/rest/v1/rpc/cumplimiento_metas_v2_fn', (route) => route.fulfill({ headers: CORS, json: propio }))
  await loginReal(page)
  await page.getByText('Tu cumplimiento del mes').scrollIntoViewIfNeeded()
  await expect(page.getByText('S/ 6k', { exact: true }).first()).toBeVisible()
  await expect(page.getByText(aviso)).toBeVisible()
})
