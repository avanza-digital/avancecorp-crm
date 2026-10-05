import { irAModulo } from './_navegacion'
import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

const solicitudId = 'd7100000-0000-4000-8000-000000000001'
const dispositivoId = 'd7100000-0000-4000-8000-000000000002'

test('Gerencia activa avisos, envía prueba y los desactiva con el worker real', async ({ page, context }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  await context.grantPermissions(['notifications'], { origin: 'http://127.0.0.1:5199' })
  await page.addInitScript(() => {
    // Chromium headless informa permission=denied aunque Permissions API devuelve
    // granted. Se simula el permiso junto al proveedor; el SW sí se instala realmente.
    Object.defineProperty(Notification, 'permission', { get: () => 'granted' })
    let actual: object | null = null
    const suscripcion = {
      endpoint: 'https://fcm.googleapis.com/fcm/send/banco-sin-red', options: {},
      toJSON: () => ({ keys: { p256dh: 'B'.repeat(87), auth: 'a'.repeat(22) } }),
      unsubscribe: async () => { actual = null; return true },
    }
    // No se contacta a un proveedor push desde el banco automatizado.
    Object.defineProperty(PushManager.prototype, 'getSubscription', { value: async () => actual })
    Object.defineProperty(PushManager.prototype, 'subscribe', { value: async () => { actual = suscripcion; return actual } })
  })
  let activo = false
  const acciones: string[] = []
  await page.route('**/functions/v1/crm-notificaciones-tasa', async route => {
    const cuerpo = route.request().postDataJSON()
    acciones.push(cuerpo.accion)
    await route.fulfill({ json: cuerpo.accion === 'prueba' ? { enviado: true } : {
      configurado: true, clavePublica: 'B'.repeat(87), dispositivo: activo ? { id: dispositivoId, activo: true } : null,
    } })
  })
  await page.route('**/rest/v1/rpc/registrar_push_tasa_fn', async route => {
    const cuerpo = route.request().postDataJSON()
    expect(cuerpo.p_endpoint).toContain('banco-sin-red')
    activo = true
    await route.fulfill({ json: dispositivoId })
  })
  await page.route('**/rest/v1/rpc/desactivar_push_tasa_fn', async route => {
    expect(route.request().postDataJSON().p_dispositivo_id).toBe(dispositivoId)
    activo = false
    await route.fulfill({ json: null })
  })
  await loginReal(page)
  await irAModulo(page, 'Configuración')
  await page.getByRole('button', { name: 'Activar notificaciones', exact: true }).click()
  await expect(page.getByText('Activados en este dispositivo')).toBeVisible()
  await page.getByRole('region', { name: 'Notificaciones de solicitudes de tasa' }).screenshot({ path: 'test-results/push-tasa-activado.png' })
  expect(await page.evaluate(async () => (await navigator.serviceWorker.getRegistration())?.active?.scriptURL)).toContain('/sw-crm.js')
  await page.getByRole('button', { name: 'Enviar prueba' }).click()
  await expect(page.getByText(/Aviso de prueba enviado/)).toBeVisible()
  expect(acciones).toContain('prueba')
  await page.getByRole('button', { name: 'Resumen', exact: true }).click()
  await expect(page.getByRole('region', { name: 'Notificaciones de solicitudes de tasa' })).toHaveCount(0)
  await irAModulo(page, 'Configuración')
  await expect(page.getByText('Activados en este dispositivo')).toBeVisible()
  await page.getByRole('button', { name: 'Desactivar', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Activar notificaciones' })).toBeVisible()
  expect(activo).toBe(false)
  await page.getByRole('button', { name: 'Resumen', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Activar notificaciones' })).toBeVisible()
})

test('un aviso antiguo conserva la ruta tras recargar y explica que ya no está pendiente', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  await loginReal(page)
  await page.goto(`/#/hoy/solicitud-tasa/${solicitudId}`)
  await expect(page.getByText('La solicitud de este aviso ya no está pendiente o no está disponible para tu cuenta.')).toBeVisible()
  await expect(page).toHaveURL(new RegExp(`/hoy/solicitud-tasa/${solicitudId}$`))
})

test('abrir el aviso sin sesión conserva la solicitud y la enfoca después del login', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  await page.route('**/rest/v1/rpc/solicitudes_tasa_fn', route => route.fulfill({ json: [{
    id: solicitudId, estado: 'pendiente', estado_efectivo: 'pendiente', vigente: true, categoria: 'nuevo',
    cliente_id: null, lead_id: 'd7100000-0000-4000-8000-000000000003', cliente_nombre: 'LEAD QA AVISO',
    contrato_origen_id: null, contrato_origen_numero: null, tasa_maxima_autorizada: null,
    motivo_resolucion: null, resuelta_por: null, resuelta_en: null, contrato_id: null,
    capital: 20000, moneda: 'PEN', modalidad: 'mensual', tipo_interes: 'simple',
    fecha_inicio: '2027-01-01', fecha_vencimiento: '2028-01-01', tasa_base: 15, tasa_solicitada: 18,
    regla_base: 'primera_inversion', motivo: 'Solicitud de prueba de navegación',
    solicitada_por: 'd7100000-0000-4000-8000-000000000004', solicitante_nombre: 'ANALISTA QA',
    solicitada_en: new Date().toISOString(), vence_en: new Date(Date.now() + 86400000).toISOString(),
    es_mia: false, puede_resolver: true, puede_responder: false, prioridad_bandeja: false, contratos_previos: 0,
  }] }))
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto(`/#/hoy/solicitud-tasa/${solicitudId}`)
  await page.locator('#correo').fill('qa-real@avancecorp.pe')
  await page.locator('#clave').fill('cualquier-cosa')
  await page.getByRole('button', { name: /^Entrar$/ }).click()
  await expect(page.locator(`#solicitud-tasa-${solicitudId}`)).toBeFocused({ timeout: 10000 })
  await expect(page.locator(`#solicitud-tasa-${solicitudId}`)).toContainText('LEAD QA AVISO')
  await expect(page).toHaveURL(new RegExp(`/hoy/solicitud-tasa/${solicitudId}$`))
})

test('manifiesto e iconos existen y el móvil mantiene controles visibles', async ({ page, request }) => {
  const manifiesto = await request.get('/manifest.webmanifest')
  expect(manifiesto.ok()).toBe(true)
  const json = await manifiesto.json()
  expect(json.display).toBe('standalone')
  for (const icono of json.icons) expect((await request.get(icono.src)).ok()).toBe(true)
  await page.setViewportSize({ width: 390, height: 844 })
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  await page.addInitScript(() => { Object.defineProperty(Notification, 'permission', { get: () => 'default' }) })
  await page.route('**/functions/v1/crm-notificaciones-tasa', route => route.fulfill({ json: {
    configurado: true, clavePublica: 'B'.repeat(87), dispositivo: null,
  } }))
  await loginReal(page, { esperarWorkspace: false })
  await expect(page.getByRole('heading', { name: 'Resumen', exact: true })).toBeVisible({ timeout: 10000 })
  await page.goto('/#/config')
  await expect(page.getByRole('heading', { name: 'Avisos en tu teléfono' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Activar notificaciones' })).toBeVisible()
  await page.getByRole('region', { name: 'Notificaciones de solicitudes de tasa' }).screenshot({ path: 'test-results/push-tasa-movil.png' })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})
