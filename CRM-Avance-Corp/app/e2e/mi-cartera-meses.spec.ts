// E2E de la cartera partida por MES DE CIERRE (pedido de Miguel, 2026-08-14):
// el asesor tiene que poder ver qué cerró cada mes y la lista deja de salir
// «todo junto». Va por la ruta REAL con el backend interceptado porque ahí las
// FECHAS de los contratos las pone el fixture: con los datos de demo, que se
// anclan a "hoy", los bloques cambiarían de nombre cada día.
import { expect, test } from '@playwright/test'
import { clienteReal, contratoReal, loginReal, montarBackendReal, UID } from './_helpers'

const CLIENTE_B = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2'

test('la cartera se parte por mes y cada bloque dice lo que se cerró en él', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor',
    clientes: [
      clienteReal(),
      clienteReal({ id: CLIENTE_B, nombre_completo: 'CLIENTE PORTAL DOS', dni: '45781299' }),
    ],
    contratos: [
      contratoReal({
        id: 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
        numero_contrato: '2026-08-000111',
        capital: 20000,
        creado_en: '2026-08-10T16:00:00.000Z', // 11:00 de Lima → AGOSTO
      }),
      contratoReal({
        id: 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2',
        numero_contrato: '2026-07-000222',
        cliente_id: CLIENTE_B,
        cliente_nombre: 'CLIENTE PORTAL DOS',
        capital: 5000,
        creado_en: '2026-07-10T16:00:00.000Z', // JULIO
      }),
    ],
  })
  await loginReal(page)

  const agosto = page.getByRole('button', { name: /^Agosto 2026 · 1 contrato cerrado · S\/ 20,000/ })
  const julio = page.getByRole('button', { name: /^Julio 2026 · 1 contrato cerrado · S\/ 5,000/ })
  await expect(agosto).toBeVisible()
  await expect(julio).toBeVisible()

  // El bloque más reciente arranca abierto; los viejos, plegados.
  await expect(agosto).toHaveAttribute('aria-expanded', 'true')
  await expect(julio).toHaveAttribute('aria-expanded', 'false')
  await expect(page.getByText('CLIENTE PORTAL UNO')).toBeVisible()
  await expect(page.getByText('CLIENTE PORTAL DOS')).toHaveCount(0)

  // Desplegar julio no toca agosto: son bloques independientes.
  await julio.click()
  await expect(julio).toHaveAttribute('aria-expanded', 'true')
  await expect(page.getByText('CLIENTE PORTAL DOS')).toBeVisible()
  await expect(page.getByText('CLIENTE PORTAL UNO')).toBeVisible()

  // Y se puede volver a plegar (el botón es real, no decorativo).
  await agosto.click()
  await expect(agosto).toHaveAttribute('aria-expanded', 'false')
  await expect(page.getByText('CLIENTE PORTAL UNO')).toHaveCount(0)
})

test('el bloque avisa cuando el mes incluye un contrato que registró otra persona', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor',
    clientes: [clienteReal()],
    contratos: [
      contratoReal({
        id: 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
        numero_contrato: '2026-08-000111',
        capital: 20000,
        creado_por: UID, // lo registró el propio asesor
        creado_en: '2026-08-10T16:00:00.000Z',
      }),
      contratoReal({
        id: 'dddddddd-dddd-4ddd-8ddd-ddddddddddd3',
        numero_contrato: '2026-08-000333',
        capital: 5000,
        creado_por: '99999999-9999-4999-8999-999999999999', // lo registró gerencia
        creado_en: '2026-08-12T16:00:00.000Z',
      }),
    ],
  })
  await loginReal(page)

  // El total cuenta los DOS (son contratos de un cliente suyo), y el aviso
  // explica por qué ese número puede no cuadrar con su cuota.
  await expect(
    page.getByRole('button', { name: /^Agosto 2026 · 2 contratos cerrados · S\/ 25,000/ }),
  ).toBeVisible()
  await expect(page.getByText('incluye 1 registrado por otra persona')).toBeVisible()
})
