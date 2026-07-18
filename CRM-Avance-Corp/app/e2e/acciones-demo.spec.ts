// E2E de las ACCIONES del CRM en modo DEMO (sin backend). Recorre crear/editar/
// mover/descartar+nota/reabrir/actividad/reasignar/convertir de punta a punta.
// En demo los toasts SÍ deben decir "(demo)" (espejo del guard yo?.demo).
import { expect, test } from '@playwright/test'
import { abrirLead, entrarDemo, irAPipeline } from './_helpers'

test('crear lead: alta rápida, toast "(demo)" y abre la ficha del nuevo lead', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await page.getByRole('button', { name: /nuevo lead/i }).click()

  const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
  await expect(modal).toBeVisible()
  for (const origen of ['referido', 'landing', 'formulario', 'oficina', 'otro']) {
    await expect(modal.locator(`#nl-origen option[value="${origen}"]`)).toHaveCount(1)
  }
  for (const origenRetirado of ['web', 'campania', 'whatsapp']) {
    await expect(modal.locator(`#nl-origen option[value="${origenRetirado}"]`)).toHaveCount(0)
  }
  await modal.locator('#nl-nombre').fill('LEAD PRUEBA E2E')
  await modal.locator('#nl-telefono').fill('987111222')
  await modal.locator('#nl-monto').fill('5000')
  await modal.locator('#nl-origen').selectOption('landing')
  await modal.getByRole('button', { name: /crear lead/i }).click()

  await expect(page.getByText(/Lead creado \(demo\)/i)).toBeVisible()
  // Abre la ficha del nuevo lead (el drawer queda etiquetado por su nombre).
  await expect(page.getByRole('dialog', { name: 'LEAD PRUEBA E2E' })).toBeVisible()
})

test('editar lead: cambia el monto y confirma con toast "(demo)"', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  await drawer.getByRole('button', { name: /editar/i }).click()
  await drawer.locator('#ld-monto').fill('99999')
  await drawer.getByRole('button', { name: /^Guardar$/ }).click()

  await expect(page.getByText(/Cambios guardados \(demo\)/i)).toBeVisible()
  // La fila Monto refleja el nuevo valor.
  await expect(drawer.getByText(/99[.,]?999/)).toBeVisible()
})

test('mover etapa: el stepper avanza a Contactado (aria-current)', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  await drawer.getByRole('button', { name: 'Contactado' }).click()
  await expect(drawer.getByRole('button', { name: 'Contactado' })).toHaveAttribute('aria-current', 'step')
})

test('descartar con nota: toast "(demo)" y banner de lead descartado', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /MARÍA LÓPEZ CASTRO/)

  await drawer.getByRole('button', { name: /descartar/i }).click()
  const dialogo = page.getByRole('dialog', { name: 'Descartar lead' })
  await expect(dialogo).toBeVisible()
  await dialogo.locator('#ld-nota-descarte').fill('No tiene fondos ahora; retomar en Q4')
  await dialogo.getByRole('button', { name: /descartar/i }).click()

  await expect(page.getByText(/Lead descartado \(demo\)/i)).toBeVisible()
  await expect(drawer.getByText('Lead descartado')).toBeVisible()
  // La nota del descarte queda en el timeline (no se pierde).
  await expect(drawer.getByText(/No tiene fondos ahora; retomar en Q4/)).toBeVisible()
})

test('reabrir: un lead descartado vuelve a Nuevo con toast "(demo)"', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  // Descartar primero para tener un lead terminal en el drawer…
  await drawer.getByRole('button', { name: /descartar/i }).click()
  const dialogo = page.getByRole('dialog', { name: 'Descartar lead' })
  await dialogo.getByRole('button', { name: /descartar/i }).click()
  await expect(drawer.getByText('Lead descartado')).toBeVisible()

  // …y reabrir.
  await drawer.getByRole('button', { name: /reabrir/i }).click()
  await expect(page.getByText(/Lead reabierto \(demo\)/i)).toBeVisible()
})

test('registrar actividad: entra al timeline con toast "(demo)"', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  await drawer.getByLabel('Detalle de la actividad').fill('Llamada de prueba E2E')
  await drawer.getByRole('button', { name: /^Registrar$/ }).click()

  await expect(page.getByText(/Actividad registrada \(demo\)/i)).toBeVisible()
  await expect(drawer.getByText('Llamada de prueba E2E')).toBeVisible()
})

test('reasignar (gerencia): cambia el vendedor con toast "(demo)"', async ({ page }) => {
  await entrarDemo(page, 'Gerencia')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  await drawer.getByLabel('Reasignar vendedor').selectOption({ label: 'VENDEDOR DOS' })
  await expect(page.getByText(/Lead reasignado \(demo\)/i)).toBeVisible()
})

// Como Vendedor sobre SU lead: el único caso que existe de verdad. (Gerencia no
// da de alta, y un supervisor sobre el lead de su vendedor tampoco — el cliente
// quedaría en la cartera del vendedor y el contrato le sería negado.)
test('convertir (demo): abre el diálogo y marca el lead como convertido', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  await drawer.getByRole('button', { name: /Convertir a cliente/i }).click()
  const dialogo = page.getByRole('dialog', { name: 'Convertir a cliente' })
  await expect(dialogo).toBeVisible()
  await dialogo.getByRole('button', { name: /^Convertir/i }).click()

  await expect(page.getByText(/ahora es cliente \(demo\)/i)).toBeVisible()
  await expect(drawer.getByText(/Convertido a cliente \(demo\)/i)).toBeVisible()
})
