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
