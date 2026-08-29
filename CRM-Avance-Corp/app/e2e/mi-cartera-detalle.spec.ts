// E2E de la ficha completa del cliente dentro de Mi cartera. La ruta REAL usa
// el backend Supabase interceptado (fail-closed) y la DEMO bloquea por completo
// ese host: ambas prueban el flujo de navegador sin tocar producción.
import { expect, test } from '@playwright/test'
import {
  bloquearSupabase,
  clienteReal,
  contratoReal,
  entrarDemo,
  irAMiCartera,
  loginReal,
  montarBackendReal,
  verTodaLaCartera,
} from './_helpers'

test('real: un analista abre la Ficha 360 de su cliente aunque la ventana de 5 h venció', async ({ page }) => {
  const cliente = clienteReal({
    creado_en: '2020-01-01T00:00:00.000Z',
    banco_usd: 'Interbank',
    tipo_cuenta_usd: 'corriente',
    numero_cuenta_usd: '2003001234567',
    cci_usd: '00320030012345678901',
    titular_distinto_usd: true,
    beneficiario_nombre_usd: 'JUANA PÉREZ QA',
    beneficiario_dni_usd: '87654321',
  })
  const backend = await montarBackendReal(page, {
    rolCrm: 'vendedor',
    clientes: [cliente],
    contratos: [],
  })
  await loginReal(page)
  await irAMiCartera(page)

  const fila = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })
  await expect(fila).toBeVisible()
  // Escritura vencida, lectura completa disponible.
  await expect(fila.getByRole('button', { name: 'Corregir' })).toHaveCount(0)
  await fila.getByRole('button', { name: 'Ver detalle' }).click()

  const ficha = page.getByRole('dialog', { name: 'CLIENTE PORTAL UNO' })
  await expect(ficha).toBeVisible()
  await expect(ficha.getByText('cliente1@correo.pe')).toBeVisible()
  await expect(ficha.getByText('00219112345678901234')).toBeVisible()
  await expect(ficha.getByText('00320030012345678901')).toBeVisible()
  await expect(ficha.getByText('JUANA PÉREZ QA')).toBeVisible()
  await expect(ficha.getByText('87654321')).toBeVisible()
  expect(backend.llamadas.patchPerfil).toBe(0)
})

test('real: directorio ve la Ficha 360 mínima sin domicilio, banca ni llamadas a sus RPC', async ({ page }) => {
  const cliente = clienteReal()
  const backend = await montarBackendReal(page, {
    rolCrm: 'directorio',
    rolPortal: 'directorio',
    clientes: [cliente],
    contratos: [],
  })
  await loginReal(page)
  await irAMiCartera(page)

  const fila = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })
  await fila.getByRole('button', { name: 'Ver detalle' }).click()

  const ficha = page.getByRole('dialog', { name: 'CLIENTE PORTAL UNO' })
  await expect(ficha.getByText('cliente1@correo.pe')).toBeVisible()
  await expect(ficha.getByText('Domicilio legal')).toHaveCount(0)
  await expect(ficha.getByText(cliente.domicilio!)).toHaveCount(0)
  await expect(ficha.getByText('Cuentas para recibir pagos')).toHaveCount(0)
  await expect(ficha.getByText('00219112345678901234')).toHaveCount(0)
  await expect(ficha.getByText('19112345678901')).toHaveCount(0)
  expect(backend.llamadas.rpcListarCuentasBancarias).toBe(0)
})

test('real: supervisor gestiona y contrata para su equipo, pero no corrige el perfil ajeno', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'supervisor',
    rolPortal: 'analista',
    clientes: [clienteReal({ asesor_perfil_id: 'vend-1', creado_por: 'vend-1' })],
    contratos: [],
  })
  await loginReal(page)
  await irAMiCartera(page)

  const fila = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })
  await expect(fila.getByRole('button', { name: 'Gestionar' })).toBeVisible()
  await expect(fila.getByRole('button', { name: 'Ver detalle' })).toBeVisible()
  await expect(fila.getByRole('button', { name: '+ Primer contrato' })).toBeVisible()
  await expect(fila.getByRole('button', { name: 'Corregir', exact: true })).toHaveCount(0)
})

test('real: al cerrar un contrato vuelve a la Ficha 360 y al contrato de origen', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor',
    clientes: [clienteReal()],
    contratos: [contratoReal()],
  })
  await loginReal(page)
  await irAMiCartera(page)
  await verTodaLaCartera(page)

  const fila = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })
  await fila.getByRole('button', { name: 'Ver detalle' }).click()
  const ficha = page.getByRole('dialog', { name: 'CLIENTE PORTAL UNO' })
  await ficha.getByRole('button', { name: 'Ver contrato 2026-01-000123' }).click()

  const detalle = page.getByRole('dialog', { name: 'Contrato 2026-01-000123' })
  await detalle.getByRole('button', { name: 'Cerrar' }).click()

  const contratoOrigen = page.getByRole('button', { name: 'Ver contrato 2026-01-000123' })
  await expect(ficha).toBeVisible()
  await expect(contratoOrigen).toBeFocused()
})

test('demo: abre la ficha ficticia completa sin ningún request a Supabase', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Mi cartera' }).click()

  const fila = page.getByRole('row', { name: /ROSA MERCEDES AGUILAR VENTURA/ })
  await expect(fila).toBeVisible()
  await fila.getByRole('button', { name: 'Ver detalle' }).click()

  const ficha = page.getByRole('dialog', { name: 'ROSA MERCEDES AGUILAR VENTURA' })
  await expect(ficha).toBeVisible()
  await expect(ficha.getByText('rosa.aguilar@correo.pe')).toBeVisible()
  await expect(ficha.getByText('19100000001234')).toBeVisible()
  await expect(ficha.getByText('00219100000000123456')).toBeVisible()
  expect(requestsSupabase()).toBe(0)
})

test('demo: directorio ve la ficha comercial sin domicilio ni números bancarios ficticios', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)
  await entrarDemo(page, 'Directorio')
  await page.getByRole('button', { name: 'Cartera', exact: true }).click()

  const fila = page.getByRole('row', { name: /ROSA MERCEDES AGUILAR VENTURA/ })
  await expect(fila).toBeVisible()
  await expect(fila.getByRole('button', { name: 'Ver detalle' })).toBeVisible()
  await expect(fila.getByRole('button', { name: /Corregir|Contrato|Upgrade|Gestionar/ })).toHaveCount(0)
  await fila.getByRole('button', { name: 'Ver detalle' }).click()

  const ficha = page.getByRole('dialog', { name: 'ROSA MERCEDES AGUILAR VENTURA' })
  await expect(ficha.getByText('rosa.aguilar@correo.pe')).toBeVisible()
  await expect(ficha.getByText('Domicilio legal')).toBeVisible()
  await expect(ficha.getByText('Av. Javier Prado Este 123, San Isidro, Lima')).toHaveCount(0)
  await expect(ficha.getByText('Información bancaria restringida')).toBeVisible()
  await expect(ficha.getByText('19100000001234')).toHaveCount(0)
  await expect(ficha.getByText('00219100000000123456')).toHaveCount(0)
  expect(requestsSupabase()).toBe(0)
})
