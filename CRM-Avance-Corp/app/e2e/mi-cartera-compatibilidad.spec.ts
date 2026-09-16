import { expect, test } from '@playwright/test'
import { clienteReal, contratoReal, irAMiCartera, loginReal, montarBackendReal } from './_helpers'
import { carteraF5 } from '../src/test/fixtures/f5'

const RPC_ESTADO = '**/rest/v1/rpc/cartera_inversionistas_estado_fn'
const rpcAusente = { code: 'PGRST202', message: 'Could not find the function crm.cartera_inversionistas_estado_fn in the schema cache' }

test('RPC F5 ausente: el refresco conserva la ficha abierta y los filtros de cartera', async ({ page }) => {
  await page.clock.install()
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: [clienteReal()], contratos: [contratoReal()] })
  let consultas = 0
  let liberar = () => {}
  const respuestaPendiente = new Promise<void>(resolve => { liberar = resolve })
  await page.route(RPC_ESTADO, async route => {
    consultas++
    if (consultas === 2) await respuestaPendiente
    await route.fulfill({ status: 404, json: rpcAusente })
  })
  await loginReal(page)
  await irAMiCartera(page)
  const mes = page.getByRole('combobox', { name: 'Filtrar por mes de cierre', includeHidden: true })
  const buscar = page.getByRole('textbox', { name: 'Buscar en la cartera', includeHidden: true })
  await mes.selectOption('todos')
  await buscar.fill('CLIENTE PORTAL UNO')
  const fila = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })
  await fila.getByRole('button', { name: 'Ver detalle' }).click()
  const ficha = page.getByRole('dialog', { name: 'CLIENTE PORTAL UNO' })
  await expect(ficha).toBeVisible()
  const siguiente = page.waitForRequest('**/rest/v1/rpc/cartera_inversionistas_estado_fn')
  await page.clock.fastForward(15_001)
  await siguiente
  await page.clock.runFor(50)
  try {
    // Reproducir también el intervalo sin respuesta: antes se desmontaba la
    // cartera entera, cerrando la ficha y perdiendo todos los filtros.
    await expect(ficha).toBeVisible()
    await expect(mes).toHaveValue('todos')
    await expect(buscar).toHaveValue('CLIENTE PORTAL UNO')
  } finally {
    const respuesta = page.waitForResponse('**/rest/v1/rpc/cartera_inversionistas_estado_fn')
    liberar()
    await respuesta
  }
  await expect.poll(() => consultas).toBeGreaterThanOrEqual(2)
  await page.clock.runFor(50)
  await expect(ficha).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(mes).toHaveValue('todos')
  await expect(buscar).toHaveValue('CLIENTE PORTAL UNO')
})

test('la compatibilidad no oculta una denegación posterior de acceso', async ({ page }) => {
  await page.clock.install()
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: [clienteReal()], contratos: [] })
  let denegado = false
  await page.route(RPC_ESTADO, route => route.fulfill({
    status: denegado ? 403 : 404,
    json: denegado ? { code: '42501', message: 'Acceso revocado' } : rpcAusente,
  }))
  await loginReal(page)
  await irAMiCartera(page)
  await expect(page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })).toBeVisible()
  denegado = true
  await page.clock.fastForward(15_001)
  await expect(page.getByText('Ya no tienes acceso a esta información.', { exact: true })).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })).toHaveCount(0)
})

test('la comprobación periódica sigue detectando F5 cuando el servidor la habilita', async ({ page }) => {
  await page.clock.install()
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: [clienteReal()], contratos: [] })
  let habilitada = false
  await page.route(RPC_ESTADO, route => route.fulfill({
    status: habilitada ? 200 : 404,
    json: habilitada ? { version: 1, habilitada: true, escritura_habilitada: false, motivo: null } : rpcAusente,
  }))
  await page.route('**/rest/v1/rpc/cartera_inversionistas_filtrada_fn', route => route.fulfill({ json: carteraF5 }))
  await loginReal(page)
  await irAMiCartera(page)
  await expect(page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })).toBeVisible()
  habilitada = true
  await page.clock.fastForward(15_001)
  await expect(page.getByRole('heading', { name: 'Cartera de inversionistas' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Abrir ficha de ANA SINTÉTICA F5' })).toBeVisible()
})
