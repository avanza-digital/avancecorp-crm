import { expect, type Page } from '@playwright/test'

/** Recorre el menú visible: Gerencia despliega el grupo del destino cuando
 * hace falta; los demás roles conservan sus accesos directos. */
export async function irAModulo(page: Page, nombre: string): Promise<void> {
  const menu = page.locator('aside').getByRole('navigation')
  const movil = page.getByRole('navigation', { name: 'Navegación principal de Gerencia' })
  await expect(menu.or(movil)).toBeVisible()
  if (await movil.isVisible()) {
    const directo = movil.getByRole('button', { name: nombre === 'Metas y cumplimiento' ? 'Metas' : nombre, exact: true })
    if (await directo.count()) { await directo.click(); return }
    await movil.getByRole('button', { name: 'Más', exact: true }).click()
    const panel = page.getByRole('dialog', { name: 'Más opciones' })
    await expect(panel).toBeVisible()
    const destinoMovil = panel.getByRole('button', { name: nombre, exact: true })
    if (!await destinoMovil.isVisible()) {
      await panel.locator('details').filter({
        has: page.getByRole('button', { name: nombre, exact: true, includeHidden: true }),
      }).locator('summary').click()
    }
    await destinoMovil.click()
    return
  }
  await expect(menu).toBeVisible()
  const destino = menu.getByRole('button', { name: nombre, exact: true })
  if (!await destino.isVisible()) {
    const grupo = menu.getByRole('group').filter({
      has: page.getByRole('button', { name: nombre, exact: true, includeHidden: true }),
    })
    await grupo.getByRole('button', { expanded: false }).click()
  }
  await destino.click()
}
