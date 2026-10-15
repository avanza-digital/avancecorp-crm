import { expect, test } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { irAModulo } from '../e2e/_navegacion'

const datos = JSON.parse(readFileSync('/f3-privado/e2e.json', 'utf8'))
const anfitrion = 'bxkborlvpmuwttzjrjqn.supabase.co'
if (new URL(datos.url).hostname !== anfitrion) throw new Error('Destino ajeno al ensayo autorizado')

for (const [rol, cantidad] of [['vendedor', 1], ['supervisor', 1], ['gerencia', 2], ['directorio', 2]] as const) {
  test(`${rol}: Auth, filtro, cifras y ficha reales de Formulario 3`, async ({ page }, testInfo) => {
    const llamadas: string[] = []
    // Barrera de destinos, sin fabricar ni sustituir respuestas HTTP.
    await page.route('**/*', async route => {
      const host = new URL(route.request().url()).hostname
      if (host === '127.0.0.1' || host === anfitrion) await route.continue()
      else await route.abort('blockedbyclient')
    })
    page.on('response', response => {
      if (new URL(response.url()).hostname === anfitrion && response.ok()) llamadas.push(new URL(response.url()).pathname)
    })
    await page.goto('/')
    await page.getByLabel('Correo', { exact: true }).fill(datos.usuarios[rol].email)
    await page.getByLabel('Contraseña', { exact: true }).fill(datos.usuarios[rol].password)
    await page.getByRole('button', { name: 'Entrar', exact: true }).click()
    await irAModulo(page, 'Leads')
    await page.getByLabel('Buscar en la cartera').fill('PRUEBA F3 Rol')
    await page.getByLabel('Filtrar por campaña').selectOption('Formulario 3')
    const tabla = page.getByRole('table', { name: 'Cartera de leads' })
    const filas = tabla.locator('tbody tr')
    await expect(filas).toHaveCount(cantidad, { timeout: 30_000 })
    await expect(page.getByRole('button', { name: new RegExp(`^Total leads ${cantidad}\\b`) })).toBeVisible()
    await expect(filas.filter({ hasText: 'PRUEBA F3 Rol Legacy' })).toHaveCount(0)
    const propia = filas.filter({ hasText: 'PRUEBA F3 Rol Campaña' })
    await expect(propia).toContainText('Formulario 3')
    await expect(propia).toContainText('FORMULARIO')
    await tabla.screenshot({ path: testInfo.outputPath(`${rol}-cartera.png`) })
    await propia.click()
    const ficha = page.getByRole('dialog', { name: 'PRUEBA F3 Rol Campaña', exact: true })
    await expect(ficha.getByTitle('Campaña de origen: Formulario 3')).toBeVisible()
    await expect(ficha.getByRole('textbox', { name: /campaña/i })).toHaveCount(0)
    await ficha.screenshot({ path: testInfo.outputPath(`${rol}-ficha.png`) })
    await ficha.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
    await page.reload()
    await irAModulo(page, 'Leads')
    await expect(page.getByLabel('Filtrar por campaña')).toHaveValue('Formulario 3')
    await expect(filas).toHaveCount(cantidad, { timeout: 30_000 })
    await page.getByLabel('Filtrar por campaña').selectOption('todas')
    const legacy = filas.filter({ hasText: 'PRUEBA F3 Rol Legacy' })
    await expect(legacy).toBeVisible()
    await expect(legacy.getByTitle(/Campaña de origen/)).toHaveCount(0)
    expect(llamadas).toContain('/auth/v1/token')
    expect(llamadas).toContain('/rest/v1/rpc/cartera_filtrada_fn')
    await testInfo.attach('rutas-reales-sin-secretos', { body: JSON.stringify([...new Set(llamadas)]), contentType: 'application/json' })
  })
}
