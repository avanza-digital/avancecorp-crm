// Ruta real con el backend loopback interceptado. El saldo deliberadamente
// distinto del listado prueba que Gerencia usa la RPC, no una suma alternativa.
import { expect, test } from '@playwright/test'
import { clienteReal, contratoReal, irAMiCartera, loginReal, montarBackendReal } from './_helpers'

const resumenServidor = {
  version: 1, generado_en: new Date().toISOString(), zona: 'America/Lima', dias_alarma_renovacion: 30,
  clientes: { en_gestion: 20, de_baja: 0, con_capital: 13, sin_asesor: 4 },
  capital_activo: { pen: 777000, usd: 7000 },
  contratos: { por_estado: { activo: 17 }, por_vencer_30: 0, por_vencer_30_de_baja: 0 },
}

test('Gerencia conserva cierres mensuales y usa el saldo del resumen en Todos los meses', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial',
    clientes: [clienteReal()], contratos: [contratoReal({ capital: 10000, creado_en: new Date().toISOString() })],
  })
  await page.route('**/rest/v1/rpc/resumen_cartera_clientes_fn', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    await route.fulfill({ json: resumenServidor, headers: { 'access-control-allow-origin': '*' } })
  })
  await loginReal(page)
  await irAMiCartera(page)
  await expect(page.getByText('20 clientes', { exact: true })).toBeVisible()
  await expect(page.getByText('S/ 777k', { exact: true })).toHaveCount(0)
  await expect(page.getByText(/^Cerrado en .* · Soles$/)).toBeVisible()
  await page.getByRole('combobox', { name: /Filtrar por mes/ }).selectOption('todos')
  await expect(page.getByText('S/ 777k', { exact: true })).toBeVisible()
  await expect(page.getByText('US$ 7k', { exact: true })).toBeVisible()
  await expect(page.getByText('CLIENTE PORTAL UNO', { exact: true })).toBeVisible()
})

test('un resumen inválido avisa sin inventar cero; reintentar recupera el indicador', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial',
    clientes: [clienteReal()], contratos: [contratoReal({ creado_en: new Date().toISOString() })],
  })
  let disponible = false
  await page.route('**/rest/v1/rpc/resumen_cartera_clientes_fn', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    await route.fulfill({ json: disponible ? resumenServidor : {}, headers: { 'access-control-allow-origin': '*' } })
  })
  await loginReal(page)
  await irAMiCartera(page)
  await expect(page.getByText(/Los indicadores de Cartera no están disponibles/)).toBeVisible()
  await expect(page.getByText('CLIENTE PORTAL UNO', { exact: true })).toBeVisible()
  await expect(page.getByText('0 clientes', { exact: true })).toHaveCount(0)
  await expect(page.getByText('Clientes que cerraron', { exact: true })).toHaveCount(0)
  disponible = true
  await page.getByRole('button', { name: /indicadores de Cartera/i }).click()
  await expect(page.getByText('20 clientes', { exact: true })).toBeVisible()
  await expect(page.getByText(/Los indicadores de Cartera no están disponibles/)).toHaveCount(0)
})

test('un listado sin confirmación de totalidad no se presenta como cartera vacía', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial', clientes: [clienteReal()] })
  await page.route('**/rest/v1/clientes_basicos?**', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback()
    await route.fulfill({ json: [], headers: { 'access-control-allow-origin': '*' } })
  })
  await loginReal(page)
  await irAMiCartera(page)
  await expect(page.getByText(/No se pudo confirmar el listado completo de Cartera/)).toBeVisible()
  await expect(page.getByText('Aún no hay clientes en la cartera.', { exact: true })).toHaveCount(0)
  await expect(page.getByText('Clientes que cerraron', { exact: true })).toHaveCount(0)
})
