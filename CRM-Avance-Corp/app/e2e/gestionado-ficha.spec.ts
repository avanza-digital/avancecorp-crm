import { expect, test } from '@playwright/test'
import { irACartera, leadReal, loginReal, montarBackendReal, UID } from './_helpers'

test('Gestionado coincide en lista sin filtro, ficha, tarjeta y búsqueda con historial paginado', async ({ page }) => {
  const lead = leadReal({ vendedor_id: UID, tenencia_desde: '2026-10-01T10:00:00Z' })
  await montarBackendReal(page, { leads: [lead], actividades: [
    { id: 'intento-vigente', lead_id: lead.id, tipo: 'llamada_no_contestada', detalle: 'Intento vigente',
      creado_en: '2026-10-01T11:00:00Z', autor_nombre: 'Analista Real Uno', metadata: {} },
    // El intento queda fuera de la primera página del timeline: no es la
    // fuente para clasificar ni la tabla, ni la ficha, ni el hover.
    ...Array.from({ length: 60 }, (_, i) => ({ id: `nota-${i}`, lead_id: lead.id, tipo: 'nota',
      detalle: 'Nota posterior', creado_en: new Date(Date.UTC(2026, 9, 2, 10, i)).toISOString(),
      autor_nombre: 'Analista Real Uno', metadata: {} })),
  ] })
  await loginReal(page)
  await irACartera(page)
  await expect(page.getByLabel('Filtrar por etapa')).toHaveValue('todas')
  const fila = page.getByRole('row', { name: /CLIENTE REAL UNO/ })
  await expect(fila).toContainText('Gestionado')
  await fila.getByRole('cell').first().hover()
  await expect(page.locator('[data-slot="hover-card-content"]')).toContainText('Gestionado')
  await fila.click()
  const ficha = page.getByRole('dialog', { name: 'CLIENTE REAL UNO' })
  await expect(ficha.getByText('Gestionado', { exact: true })).toHaveCount(2)
  const progreso = ficha.getByRole('group', { name: 'Etapa del lead' })
  await expect(progreso.locator('[aria-current="step"]')).toHaveText('Gestionado')
  // Se identifica pero no se puede marcar a mano, sin registrar contacto.
  await expect(progreso.getByRole('button', { name: 'Gestionado' })).toHaveCount(0)
  await page.keyboard.press('Escape')
  await expect(ficha).toBeHidden()
  const buscar = page.getByLabel('Buscar lead por nombre, teléfono o DNI')
  await buscar.click()
  await buscar.fill('CLIENTE REAL UNO')
  await expect(page.getByRole('listbox', { name: 'Resultados de búsqueda' })).toContainText('Gestionado')
})

test('si no se puede verificar la gestión, la ficha lo indica sin ocultar al lead', async ({ page }) => {
  await montarBackendReal(page, { leads: [leadReal({ vendedor_id: UID })] })
  await page.route('**/rest/v1/rpc/gestion_vigente_fn', async route => {
    await route.fulfill({ status: 403, json: { message: 'lectura no disponible' } })
  })
  await loginReal(page)
  await irACartera(page)
  const fila = page.getByRole('row', { name: /CLIENTE REAL UNO/ })
  await expect(fila).toContainText('Gestión sin verificar')
  await fila.click()
  const ficha = page.getByRole('dialog', { name: 'CLIENTE REAL UNO' })
  await expect(ficha).toContainText('Gestión sin verificar')
  await expect(ficha.getByRole('group', { name: 'Etapa del lead' }).locator('[aria-current]')).toHaveCount(0)
})
