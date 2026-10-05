import { irAModulo } from './_navegacion'
// Recorrido E2E del gobierno comercial en DEMO. Las cuatro tarjetas deben ser
// navegables por Gerencia y Directorio sin que una sola lectura salga a
// Supabase; toda la fotografía demo es explícitamente de solo lectura.
import { expect, test } from '@playwright/test'
import { bloquearSupabase, entrarDemo, type RolDemo } from './_helpers'

const MODULOS = [
  {
    tarjeta: 'Usuarios y jerarquía',
    pantalla: 'Usuarios y jerarquía',
    evidencia: 'GERENCIA DEMO',
  },
  {
    tarjeta: 'Productos de inversión',
    pantalla: 'Productos de inversión',
    evidencia: 'CRECIMIENTO-12',
  },
  {
    tarjeta: 'Metas',
    pantalla: 'Metas mensuales',
    evidencia: 'ANA TORRES',
  },
  {
    tarjeta: 'Tiempos de atención',
    pantalla: 'Tiempos de atención',
    // 0230929 retiró el literal «Política operativa» (hoy la tarjeta dice
    // «Plazos de atención»). La evidencia ahora es un dato del fixture demo:
    // el ciclo de primera gestión de metricasSlaDemo (48 casos, 44 evaluables,
    // 38 cumplidos) pintado por la tarjeta de cumplimiento histórico.
    evidencia: '38 cumplidos · 6 fuera · 4 pendientes',
  },
] as const

for (const rol of ['Gerencia', 'Directorio'] as const satisfies readonly RolDemo[]) {
  test(`demo ${rol.toLocaleLowerCase('es-PE')}: recorre las cuatro configuraciones sin red`, async ({ page }) => {
    const requestsSupabase = await bloquearSupabase(page)
    await entrarDemo(page, rol)
    await irAModulo(page, 'Configuración')

    await expect(page.getByRole('heading', { name: 'Configuración del CRM' })).toBeVisible()
    await expect(page.getByText(/Demostración de solo lectura/)).toBeVisible()
    const riel = page.getByRole('list', { name: 'Estado operativo de la configuración' })
    await expect(riel.getByRole('listitem')).toHaveCount(4)
    await expect(riel.getByText('8 de 9 habilitadas')).toBeVisible()
    await expect(riel.getByText('2 productos · revisión 6')).toBeVisible()
    await expect(riel.getByText('4 analistas · revisión 5')).toBeVisible()
    await expect(riel.getByText('v3 · gestión 2 horas')).toBeVisible()

    for (const modulo of MODULOS) {
      const tarjeta = page
        .getByRole('heading', { name: modulo.tarjeta, exact: true })
        .locator('xpath=ancestor::div[@data-slot="card"]')
      await tarjeta.getByRole('link', { name: 'Abrir', exact: true }).click()

      await expect(page.getByRole('heading', { name: modulo.pantalla, exact: true })).toBeVisible()
      await expect(page.getByText(modulo.evidencia, { exact: true }).first()).toBeVisible()
      await expect(page.getByText(/Solo lectura: puedes auditar/)).toBeVisible()

      await page.getByRole('link', { name: 'Configuración', exact: true }).click()
      await expect(page.getByRole('heading', { name: 'Configuración del CRM' })).toBeVisible()
    }

    expect(requestsSupabase()).toBe(0)
  })
}
