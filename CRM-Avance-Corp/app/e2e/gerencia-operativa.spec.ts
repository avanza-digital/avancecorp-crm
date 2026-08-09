// E2E mínimo de la ampliación 2026-08-07. A diferencia de acciones-real.spec,
// este caso no depende del gate general de la fuerza de ventas: Gerencia ya
// tiene aprobadas las vistas de leads y debe poder operar un lead ajeno.
import { expect, test } from '@playwright/test'
import { abrirLead, irAPipeline, leadReal, loginReal, montarBackendReal } from './_helpers'

test('Gerencia abre un lead asignado a otro analista y puede iniciar su conversión', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    leads: [leadReal({ vendedor_id: 'vend-1' })],
  })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await drawer.getByRole('button', { name: /Convertir a cliente/i }).click()
  await expect(page.getByRole('dialog', { name: 'Convertir a cliente' })).toBeVisible()
})

test('los tiles F1 del tablero sirven los números del RPC resumen_cartera_fn', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    leads: [leadReal({ vendedor_id: 'vend-1', monto_estimado: 10000, moneda: 'PEN' })],
  })
  await loginReal(page)
  await irAPipeline(page)

  const chips = page.locator('[data-slot="card"]')
  await expect(chips.filter({ hasText: 'Leads activos' }).first()).toContainText('1')
  await expect(chips.filter({ hasText: 'Capital en proceso' }).first()).toContainText('S/ 10,000')
})

test('RPC de resumen caída: el tablero degrada a «—» con aviso y sigue operable', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    fallarResumenCartera: true,
    leads: [leadReal({ vendedor_id: 'vend-1' })],
  })
  await loginReal(page)
  await irAPipeline(page)

  // Degradación honesta: aviso visible + «—» en los chips, sin inventar cifras.
  await expect(page.getByText(/No se pudieron cargar los indicadores del tablero/)).toBeVisible()
  await expect(
    page.locator('[data-slot="card"]').filter({ hasText: 'Leads activos' }).first(),
  ).toContainText('—')

  // …y el tablero sigue operable: la card del lead abre su ficha igual.
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)
  await expect(drawer).toBeVisible()
})
