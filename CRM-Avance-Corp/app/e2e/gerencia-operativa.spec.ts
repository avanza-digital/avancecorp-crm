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

test('Equipo (gerencia real): comparativa y chips cargan desde metricas_vendedores_fn', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    leads: [leadReal({ vendedor_id: 'vend-1', monto_estimado: 12000, moneda: 'PEN' })],
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Equipo' }).click()

  // El payload parsea y la pantalla pinta: chips con números (no «—») y la
  // tabla en su estado honesto (el ROSTER del mock no tiene supervisores).
  await expect(page.getByText('Comparativa de equipos')).toBeVisible()
  await expect(page.getByText(/Aún no hay supervisores activos/)).toBeVisible()
  const chipEquipos = page.locator('[data-slot="card"]').filter({ hasText: 'Equipos' }).first()
  await expect(chipEquipos).toContainText('0')
  await expect(chipEquipos).not.toContainText('—')
})

test('métricas de equipo caídas: Equipo degrada a «—» con aviso y reintento', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    fallarMetricasEquipo: true,
    leads: [leadReal({ vendedor_id: 'vend-1' })],
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Equipo' }).click()

  await expect(page.getByText(/No se pudieron cargar las métricas por equipo/)).toBeVisible()
  await expect(page.getByText('La comparativa no está disponible en este momento.')).toBeVisible()
  await expect(
    page.locator('[data-slot="card"]').filter({ hasText: 'Equipos' }).first(),
  ).toContainText('—')
})
