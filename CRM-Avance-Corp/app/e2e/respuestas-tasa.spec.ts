import { expect, test, type Page } from '@playwright/test'
import { loginReal, montarBackendReal, UID } from './_helpers'

test.setTimeout(75000)

const id = 'e7100000-0000-4000-8000-000000000001'
const claveRegistro = `ac-crm-respuestas-tasa-v1:${UID}`

function solicitud(cambios: Record<string, unknown> = {}) {
  return {
    id, estado: 'pendiente', estado_efectivo: 'pendiente', vigente: true, categoria: 'nuevo',
    cliente_id: null, lead_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', cliente_nombre: 'LEAD QA RESPUESTA',
    contrato_origen_id: null, contrato_origen_numero: null, tasa_maxima_autorizada: null,
    motivo_resolucion: null, resuelta_por: null, resuelta_en: null, contrato_id: null,
    capital: 20000, moneda: 'PEN', modalidad: 'mensual', tipo_interes: 'simple',
    fecha_inicio: '2027-01-01', fecha_vencimiento: '2028-01-01', tasa_base: 15, tasa_solicitada: 18,
    regla_base: 'primera_inversion', motivo: 'Solicitud del banco local',
    solicitada_por: UID, solicitante_nombre: 'ANALISTA QA',
    solicitada_en: new Date().toISOString(), vence_en: new Date(Date.now() + 86400000).toISOString(),
    es_mia: true, puede_resolver: false, puede_responder: false, prioridad_bandeja: false, contratos_previos: 0,
    ...cambios,
  }
}

type PruebaPC = {
  tonos: number
  permiso: NotificationPermission
  avisos: { titulo: string; opciones: NotificationOptions; cerrado: boolean; pulsar: () => void }[]
}

async function instrumentarPC(page: Page, permiso: NotificationPermission = 'granted') {
  await page.addInitScript((permisoInicial) => {
    const pruebas: PruebaPC = { tonos: 0, permiso: permisoInicial, avisos: [] }
    ;(window as unknown as { pruebaPC: PruebaPC }).pruebaPC = pruebas
    // Audio real del navegador, instrumentado para contar cada timbre de dos notas.
    const crear = AudioContext.prototype.createOscillator
    AudioContext.prototype.createOscillator = function () { pruebas.tonos++; return crear.call(this) }
    class NotificacionLocal {
      static get permission() { return pruebas.permiso }
      static requestPermission = async () => pruebas.permiso
      onclick: (() => void) | null = null
      registro: PruebaPC['avisos'][number]
      constructor(titulo: string, opciones: NotificationOptions) {
        this.registro = { titulo, opciones, cerrado: false, pulsar: () => this.onclick?.() }
        pruebas.avisos.push(this.registro)
      }
      close() { this.registro.cerrado = true }
    }
    Object.defineProperty(window, 'Notification', { value: NotificacionLocal, configurable: true })
  }, permiso)
}

async function contarTonos(page: Page) { return page.evaluate(() => (window as unknown as { pruebaPC: PruebaPC }).pruebaPC.tonos) }
async function esperarRegistro(page: Page) {
  await expect.poll(() => page.evaluate(clave => JSON.parse(localStorage.getItem(clave) ?? '{}').iniciado, claveRegistro)).toBe(true)
}

test('aprobación: sonido, aviso sobre otra ventana, detalle y lectura persistente', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', rolPortal: 'analista' })
  await instrumentarPC(page)
  let filas = [solicitud()]
  const peticiones: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/solicitudes_tasa_fn', route => {
    peticiones.push(route.request().postDataJSON())
    return route.fulfill({ json: filas })
  })
  await loginReal(page)
  await esperarRegistro(page)
  await page.getByRole('button', { name: 'Activar alertas y sonido' }).click()
  await expect(page.getByRole('region', { name: 'Alertas de respuestas de tasa' })).toHaveCount(0)
  const tonosAntes = await contarTonos(page)
  expect(tonosAntes).toBe(2)
  await page.evaluate(() => Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }))
  filas = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 18, resuelta_por: 'gerencia-qa', resuelta_en: new Date().toISOString(), motivo_resolucion: 'Tasa aprobada por permanencia.' })]
  await expect(page.getByRole('button', { name: /Abrir notificaciones: 1 respuesta de tasa/ })).toBeVisible({ timeout: 20000 })
  await expect.poll(() => contarTonos(page)).toBe(tonosAntes + 2)
  const avisos = await page.evaluate(() => (window as unknown as { pruebaPC: PruebaPC }).pruebaPC.avisos)
  expect(avisos).toHaveLength(1)
  expect(avisos[0]?.titulo).toContain('aprobada')
  expect(JSON.stringify(avisos)).not.toMatch(/LEAD QA|20000|permanencia/)
  expect(avisos[0]?.opciones.silent).toBe(true) // El timbre del CRM ya sonó.
  await page.evaluate(() => (window as unknown as { pruebaPC: PruebaPC }).pruebaPC.avisos[0]!.pulsar())
  const detalle = page.getByRole('dialog', { name: 'Respuesta de Gerencia' })
  await expect(detalle).toContainText('Autorizada hasta 18%')
  await expect(detalle).toContainText('Tasa aprobada por permanencia.')
  await expect(page).toHaveURL(new RegExp(`/hoy/solicitud-tasa/${id}$`))
  await detalle.screenshot({ path: 'test-results/respuesta-tasa-aprobada.png' })
  await page.getByRole('button', { name: 'Cerrar notificaciones' }).click()
  await expect(page.getByRole('button', { name: /Abrir notificaciones: 0 respuestas/ })).toBeVisible()
  await page.reload()
  await esperarRegistro(page)
  await expect(page.getByRole('button', { name: /Abrir notificaciones: 0 respuestas/ })).toBeVisible()
  await expect(page.getByRole('region', { name: 'Alertas de respuestas de tasa' })).toHaveCount(0)
  await page.getByRole('button', { name: 'Configuración', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Silenciar sonido' })).toBeVisible()
  expect(peticiones.some(p => p.p_solo_mias === true && p.p_limite === 500)).toBe(true)
})

// Ritmo adaptativo (29/09/2026): el CRM pregunta cada 15 s solo mientras hay una solicitud propia
// pendiente (2 min en reposo). Por eso cada escenario parte de la solicitud PENDIENTE, como en la
// realidad: primero se pide la tasa y después llega la respuesta.
test('rechazo y tope: un timbre por lote, filtro propio, sin leer hasta abrir', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'supervisor', rolPortal: 'analista' })
  await instrumentarPC(page)
  let filas: ReturnType<typeof solicitud>[] = [
    solicitud(),
    solicitud({ id: 'e7100000-0000-4000-8000-000000000002', cliente_nombre: 'LEAD QA TOPE' }),
    solicitud({ id: 'e7100000-0000-4000-8000-000000000003', solicitada_por: 'otra-cuenta', cliente_nombre: 'NO REVELAR' }),
  ]
  await page.route('**/rest/v1/rpc/solicitudes_tasa_fn', route => route.fulfill({ json: filas }))
  await loginReal(page)
  await esperarRegistro(page)
  await page.getByRole('button', { name: 'Activar alertas y sonido' }).click()
  await expect.poll(() => contarTonos(page)).toBe(2)
  const antes = await contarTonos(page)
  filas = [
    solicitud({ estado: 'rechazada', estado_efectivo: 'rechazada', vigente: false, resuelta_por: 'gerencia-qa', resuelta_en: new Date().toISOString(), motivo_resolucion: 'Revisar el plazo solicitado.' }),
    solicitud({ id: 'e7100000-0000-4000-8000-000000000002', estado: 'aprobada_con_tope', estado_efectivo: 'aprobada_con_tope', tasa_maxima_autorizada: 16, resuelta_por: 'gerencia-qa', resuelta_en: new Date().toISOString(), cliente_nombre: 'LEAD QA TOPE' }),
    solicitud({ id: 'e7100000-0000-4000-8000-000000000003', estado: 'aprobada', tasa_maxima_autorizada: 18, resuelta_por: 'gerencia-qa', resuelta_en: new Date().toISOString(), es_mia: true, solicitada_por: 'otra-cuenta', cliente_nombre: 'NO REVELAR' }),
  ]
  await expect(page.getByRole('button', { name: /Abrir notificaciones: 2 respuestas/ })).toBeVisible({ timeout: 20000 })
  await expect.poll(() => contarTonos(page)).toBe(antes + 2)
  await page.getByRole('button', { name: /Abrir notificaciones/ }).click()
  await expect(page.getByRole('dialog')).not.toContainText('NO REVELAR')
  await expect(page.getByRole('dialog')).toContainText('rechazada')
  await expect(page.getByRole('dialog')).toContainText('tope')
  await expect(page.getByRole('dialog')).toContainText('2 respuestas de tasa sin leer')
  await page.getByRole('button', { name: 'Ver solicitud de LEAD QA RESPUESTA', exact: true }).click()
  await expect(page.getByRole('dialog')).toContainText('Revisar el plazo solicitado.')
  await page.getByRole('button', { name: 'Cerrar notificaciones' }).click()
  await page.getByRole('button', { name: /Abrir notificaciones: 1 respuesta/ }).click()
  await page.getByRole('button', { name: 'Marcar respuestas como leídas' }).click()
  await expect(page.getByRole('dialog')).toContainText('0 respuestas de tasa sin leer')
})

test('permiso denegado y red caída conservan bandeja; cerrar sesión retira los avisos', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', rolPortal: 'analista', leads: [] })
  await instrumentarPC(page, 'denied')
  let caido = false
  let filas: ReturnType<typeof solicitud>[] = [solicitud()]
  await page.route('**/rest/v1/rpc/solicitudes_tasa_fn', route => route.fulfill(caido
    ? { status: 503, json: { message: 'Sin conexión de prueba' } } : { json: filas }))
  await loginReal(page)
  await esperarRegistro(page)
  await page.getByRole('button', { name: 'Activar alertas y sonido' }).click()
  await page.getByRole('button', { name: 'Configuración', exact: true }).click()
  await expect(page.getByRole('status').filter({ hasText: 'permite las notificaciones' })).toBeVisible()
  await page.getByRole('button', { name: 'Silenciar sonido' }).click()
  const antes = await contarTonos(page)
  caido = true
  await expect(page.getByRole('alert').filter({ hasText: 'No pudimos consultar las respuestas' })).toBeVisible({ timeout: 25000 })
  caido = false
  filas = [solicitud({ estado: 'rechazada', estado_efectivo: 'rechazada', resuelta_por: 'gerencia-qa', resuelta_en: new Date().toISOString() })]
  await expect(page.getByRole('button', { name: /Abrir notificaciones: 1 respuesta/ })).toBeVisible({ timeout: 25000 })
  expect(await contarTonos(page)).toBe(antes)
  expect(await page.evaluate(() => (window as unknown as { pruebaPC: PruebaPC }).pruebaPC.avisos.length)).toBe(0)
  await page.getByRole('button', { name: /salir|cerrar sesión/i }).click()
  await expect(page.getByRole('button', { name: /^Entrar$/ })).toBeVisible()
  await expect(page.locator('[data-sonner-toast]')).toHaveCount(0)
})

test('dos pestañas: una alerta y lectura sincronizada, enlace ajeno no revela datos', async ({ page, context }) => {
  let filas: ReturnType<typeof solicitud>[] = [solicitud()]
  for (const p of [page]) {
    await montarBackendReal(p, { rolCrm: 'vendedor', rolPortal: 'analista' })
    await instrumentarPC(p)
    await p.route('**/rest/v1/rpc/solicitudes_tasa_fn', route => route.fulfill({ json: filas }))
  }
  await loginReal(page)
  await esperarRegistro(page)
  await page.getByRole('button', { name: 'Activar alertas y sonido' }).click()
  const segunda = await context.newPage()
  await montarBackendReal(segunda, { rolCrm: 'vendedor', rolPortal: 'analista' })
  await instrumentarPC(segunda)
  await segunda.route('**/rest/v1/rpc/solicitudes_tasa_fn', route => route.fulfill({ json: filas }))
  await segunda.goto('/#/hoy')
  await expect(segunda.getByRole('button', { name: /Abrir notificaciones/ })).toBeVisible()
  await segunda.getByRole('button', { name: /Abrir notificaciones/ }).click()
  await segunda.getByRole('button', { name: 'Cerrar notificaciones' }).click()
  filas = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 18, resuelta_por: 'gerencia-qa', resuelta_en: new Date().toISOString() })]
  await expect(page.getByRole('button', { name: /Abrir notificaciones: 1 respuesta/ })).toBeVisible({ timeout: 20000 })
  await expect(segunda.getByRole('button', { name: /Abrir notificaciones: 1 respuesta/ })).toBeVisible({ timeout: 20000 })
  expect(await contarTonos(page) + await contarTonos(segunda)).toBe(4) // Dos notas de activación + dos de la respuesta.
  await segunda.getByRole('button', { name: /Abrir notificaciones/ }).click()
  await segunda.getByRole('button', { name: 'Marcar respuestas como leídas' }).click()
  await expect(page.getByRole('button', { name: /Abrir notificaciones: 0 respuestas/ })).toBeVisible()
  await segunda.getByRole('button', { name: 'Cerrar notificaciones' }).click()
  await segunda.goto('/#/hoy/solicitud-tasa/e7100000-0000-4000-8000-000000000099')
  await expect(segunda.getByRole('dialog')).toContainText('no está disponible para tu cuenta')
  await expect(segunda.getByRole('dialog')).not.toContainText('LEAD QA RESPUESTA')
})
