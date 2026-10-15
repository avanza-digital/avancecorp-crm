import { expect, test } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { irAModulo } from '../e2e/_navegacion'

const datos = JSON.parse(readFileSync('/f4-privado/e2e.json', 'utf8'))
const origen = 'dctqcbznekcyxhjujuci.supabase.co'
const destino = 'oemmpccapplmiygcpvxr.supabase.co'
if (new URL(datos.url).hostname !== destino) throw new Error('Destino no autorizado')

for (const rol of ['vendedor', 'gerencia']) {
  test(`${rol}: ZIP anterior con base nueva, Cartera, ficha y Pipeline`, async ({ page }, testInfo) => {
    const respuestas: { ruta: string; status: number }[] = []
    let finalizando = false
    // Proxy a la rama: conserva métodos, parámetros y respuestas reales.
    // Solo cambia destino y clave pública. Nunca envía una petición a producción.
    await page.routeWebSocket('**/*', ws => ws.close())
    await page.route('**/*', async route => {
      const request = route.request()
      const url = new URL(request.url())
      if (finalizando) { await route.abort(); return }
      if (url.hostname === '127.0.0.1') { await route.continue(); return }
      if (url.hostname !== origen) { await route.abort('blockedbyclient'); return }
      url.hostname = destino
      const headers: Record<string, string> = { ...request.headers(), apikey: datos.anon }
      const jwt = headers.authorization?.replace(/^Bearer /, '')
      if (jwt) {
        const payload = JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString())
        if (payload.role === 'anon') headers.authorization = 'Bearer ' + datos.anon
        else if (payload.iss !== datos.url + '/auth/v1') throw new Error('Sesión ajena a la rama')
      }
      try {
        const response = await route.fetch({ url: url.toString(), headers, maxRedirects: 0, timeout: 30_000 })
        respuestas.push({ ruta: url.pathname, status: response.status() })
        await route.fulfill({ response })
      } catch {
        if (!finalizando) throw new Error('Falló el proxy de prueba; cabeceras omitidas')
      }
    })
    await page.goto('/')
    await page.getByLabel('Correo', { exact: true }).fill(datos.usuarios[rol].email)
    await page.getByLabel('Contraseña', { exact: true }).fill(datos.usuarios[rol].password)
    await page.getByRole('button', { name: 'Entrar', exact: true }).click()
    await irAModulo(page, 'Leads')
    await page.getByLabel('Buscar en la cartera').fill('PRUEBA F4 Compat')
    const filas = page.getByRole('table', { name: 'Cartera de leads' }).locator('tbody tr')
    await expect(filas).toHaveCount(2)
    await filas.filter({ hasText: 'PRUEBA F4 Compat Campaña' }).click()
    const ficha = page.getByRole('dialog', { name: 'PRUEBA F4 Compat Campaña', exact: true })
    await expect(ficha).toBeVisible()
    await ficha.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
    await irAModulo(page, 'Pipeline')
    for (const etapa of ['Nuevo', 'Contactado', 'Cita agendada', 'Entrevista realizada']) {
      await expect(page.getByText(etapa, { exact: true }).first()).toBeVisible()
    }
    const cartera = respuestas.filter(r => r.ruta === '/rest/v1/rpc/cartera_filtrada_fn')
    expect(cartera.some(r => r.status === 200)).toBe(true)
    expect(cartera.filter(r => r.status >= 400)).toEqual([])
    await testInfo.attach('rutas-reales-sin-secretos', { body: JSON.stringify(respuestas), contentType: 'application/json' })
    finalizando = true
    await page.goto('about:blank', { waitUntil: 'commit' })
    // La aplicación ya no está montada: descarta solo errores de peticiones
    // pendientes al cerrar, después de comprobar las respuestas y la interfaz.
    await page.unrouteAll({ behavior: 'ignoreErrors' })
  })
}
