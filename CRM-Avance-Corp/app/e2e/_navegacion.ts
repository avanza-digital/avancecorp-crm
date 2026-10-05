import { expect, type Page } from '@playwright/test'

/** Recorre el menú visible: Gerencia despliega el grupo del destino cuando
 * hace falta; los demás roles conservan sus accesos directos. */
export async function irAModulo(page: Page, nombre: string): Promise<void> {
  const menu = page.locator('aside').getByRole('navigation')
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
