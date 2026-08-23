// Smoke E2E por ROL sobre la demo (hallazgo Alta de auditoría 2026-07-10:
// no existía ninguna prueba end-to-end). Verifica el recorrido real: login
// demo → panel Hoy → navegación → ficha de lead (incluido el manejo por
// TECLADO y el focus-trap del drawer, arreglos de esta misma auditoría).
import { expect, test, type Page } from '@playwright/test'

const ROLES = ['Vendedor', 'Supervisor', 'Gerencia', 'Directorio'] as const

async function entrarDemo(page: Page, rol: (typeof ROLES)[number]): Promise<void> {
  await page.goto('/')
  await page.getByRole('button', { name: /explorar en modo demo/i }).click()
  await page.getByRole('button', { name: new RegExp(`^${rol}`) }).click()
  // El workspace queda listo cuando aparece la navegación lateral.
  await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible()
}

for (const rol of ROLES) {
  test(`${rol}: entra a la demo, ve su panel principal y navega el pipeline`, async ({ page }) => {
    await entrarDemo(page, rol)

    // Gerencia tiene un riel analítico propio; los demás roles conservan Hoy.
    await expect(
      page.getByRole('button', { name: rol === 'Gerencia' ? 'Resumen' : 'Hoy' }),
    ).toBeVisible()

    // Navegación al pipeline: las 4 etapas activas del embudo están pintadas.
    await page.getByRole('button', { name: 'Pipeline' }).click()
    for (const etapa of ['Nuevo', 'Contactado', 'Reunión agendada', 'Propuesta enviada']) {
      await expect(page.getByText(etapa, { exact: true }).first()).toBeVisible()
    }
  })
}

test('Supervisor: abre Derivar leads desde el KPI compacto de HOY por teclado', async ({ page }) => {
  await entrarDemo(page, 'Supervisor')

  const reparto = page.getByRole('link', { name: 'Repartir 2 leads pendientes' })
  await expect(reparto).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Por repartir — tu bandeja' })).toHaveCount(0)

  await reparto.focus()
  await expect(reparto).toBeFocused()
  await page.keyboard.press('Enter')

  await expect(page).toHaveURL(/#\/derivaciones$/)
  await expect(page.getByRole('heading', { name: 'Derivar hoy' })).toBeVisible()
})

test('Vendedor: abre la ficha de un lead POR TECLADO y el drawer atrapa y devuelve el foco', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await page.getByRole('button', { name: 'Pipeline' }).click()

  // Deliberadamente no esperamos un heading de Pipeline: esta secuencia fija la
  // regresión donde el hash cambiaba antes que la pantalla y Enter accionaba una
  // card homónima de Hoy. La navegación de UI debe ser atómica.
  const card = page.getByRole('button', { name: /JUAN PÉREZ ROJAS/ }).first()
  await card.focus()
  await page.keyboard.press('Enter')

  // El drawer (Radix Dialog) abre con la ficha…
  const drawer = page.getByRole('dialog')
  await expect(drawer).toBeVisible()
  await expect(page).toHaveURL(/#\/pipeline\/lead\/[^/]+$/)
  await expect(drawer.getByText('JUAN PÉREZ ROJAS').first()).toBeVisible()

  // …atrapa el foco (Tab se queda dentro del dialog)…
  await page.keyboard.press('Tab')
  const focoDentro = await page.evaluate(() => {
    const activo = document.activeElement
    return Boolean(activo?.closest('[role="dialog"]'))
  })
  expect(focoDentro).toBe(true)

  // …y Escape lo cierra devolviendo el foco a la página.
  await page.keyboard.press('Escape')
  await expect(drawer).not.toBeVisible()
  await expect(page).toHaveURL(/#\/pipeline$/)
})

test('Directorio: es lector global (ve el pipeline completo sin acciones de alta)', async ({ page }) => {
  await entrarDemo(page, 'Directorio')
  await page.getByRole('button', { name: 'Pipeline' }).click()

  // Ve leads de TODOS los equipos (l1 de d-v1 y l4 de d-v3)…
  await expect(page.getByText('JUAN PÉREZ ROJAS').first()).toBeVisible()
  await expect(page.getByText('ANA TORRES QUISPE').first()).toBeVisible()

  // …pero no tiene el alta rápida de leads (write-gating en la UI).
  await expect(page.getByRole('button', { name: /nuevo lead/i })).toHaveCount(0)
})
