// E2E del filtro por MES DE CIERRE de Mi cartera (pedido de Miguel,
// 2026-08-14): la pantalla arranca en el mes en curso y el resto se pide con el
// desplegable. Va por la ruta REAL con el backend interceptado porque ahí las
// FECHAS de los contratos las pone el fixture; con los datos de demo, anclados
// a "hoy", el mes viejo cambiaría de nombre cada día.
import { expect, test } from '@playwright/test'
import { clienteReal, contratoReal, loginReal, montarBackendReal, UID } from './_helpers'

const CLIENTE_B = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2'

/** ISO del día 10 del mes en curso a las 11:00 de Lima. */
function esteMes(): string {
  const hoy = new Date()
  return new Date(Date.UTC(hoy.getFullYear(), hoy.getMonth(), 10, 16, 0, 0)).toISOString()
}
/** ISO del día 10, tres meses atrás — seguro fuera del mes en curso. */
function haceTresMeses(): string {
  const hoy = new Date()
  return new Date(Date.UTC(hoy.getFullYear(), hoy.getMonth() - 3, 10, 16, 0, 0)).toISOString()
}

test('la cartera arranca en el mes en curso y el desplegable trae el resto', async ({ page }) => {
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
        creado_en: esteMes(),
      }),
      contratoReal({
        id: 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2',
        numero_contrato: '2026-05-000222',
        cliente_id: CLIENTE_B,
        cliente_nombre: 'CLIENTE PORTAL DOS',
        capital: 5000,
        creado_en: haceTresMeses(),
      }),
    ],
  })
  await loginReal(page)

  // Solo el mes en curso, con su resumen.
  await expect(page.getByText('CLIENTE PORTAL UNO')).toBeVisible()
  await expect(page.getByText('CLIENTE PORTAL DOS')).toHaveCount(0)
  await expect(page.getByText(/1 contrato cerrado en/)).toBeVisible()

  // La cartera entera se pide con el desplegable.
  const filtroMes = page.getByRole('combobox', { name: /Filtrar por mes/ })
  await filtroMes.selectOption('todos')
  await expect(page.getByText('CLIENTE PORTAL UNO')).toBeVisible()
  await expect(page.getByText('CLIENTE PORTAL DOS')).toBeVisible()
  // Sin mes elegido no hay resumen de mes que enseñar.
  await expect(page.getByText(/contrato.? cerrado.? en/)).toHaveCount(0)
})

test('el resumen avisa cuando el mes incluye un contrato que registró otra persona', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor',
    clientes: [clienteReal()],
    contratos: [
      contratoReal({
        id: 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
        numero_contrato: '2026-08-000111',
        capital: 20000,
        creado_por: UID, // lo registró el propio asesor
        creado_en: esteMes(),
      }),
      contratoReal({
        id: 'dddddddd-dddd-4ddd-8ddd-ddddddddddd3',
        numero_contrato: '2026-08-000333',
        capital: 5000,
        creado_por: '99999999-9999-4999-8999-999999999999', // lo registró gerencia
        creado_en: esteMes(),
      }),
    ],
  })
  await loginReal(page)

  // El total cuenta los DOS (son contratos de un cliente suyo), y el aviso
  // explica por qué ese número puede no cuadrar con su cuota.
  // Acotado al resumen: la fila del cliente repite el importe, y son dos cifras
  // distintas por definición (lo CERRADO en el mes vs lo que sigue VIVO).
  const resumen = page.locator('p', { hasText: /2 contratos cerrados en/ })
  await expect(resumen).toBeVisible()
  await expect(resumen.getByText('S/ 25,000')).toBeVisible()
  await expect(resumen.getByText('incluye 1 registrado por otra persona')).toBeVisible()
})

test('sin cierres este mes, la pantalla lo dice y ofrece la salida', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor',
    clientes: [clienteReal()],
    contratos: [
      contratoReal({
        id: 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2',
        numero_contrato: '2026-05-000222',
        capital: 5000,
        creado_en: haceTresMeses(),
      }),
    ],
  })
  await loginReal(page)

  await expect(page.getByText(/Sin cierres en/)).toBeVisible()
  await expect(page.getByText('CLIENTE PORTAL UNO')).toHaveCount(0)

  await page.getByRole('button', { name: 'Ver toda la cartera' }).click()
  await expect(page.getByText('CLIENTE PORTAL UNO')).toBeVisible()
})
