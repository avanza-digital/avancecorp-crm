import { expect, test, type Page } from '@playwright/test'
import { leadReal, loginReal, montarBackendReal, UID } from './_helpers'

const lead = leadReal({ vendedor_id: UID, nombre_completo: 'QA CONSULTAS DE TASA', dni: '70909002', etapa: 'propuesta_enviada', monto_estimado: 20000 })

async function abrir(page: Page) {
  await page.goto('/#/cartera')
  await page.getByRole('row', { name: `Abrir ficha de ${lead.nombre_completo}`, exact: true }).click()
  return page.getByRole('dialog', { name: lead.nombre_completo, exact: true })
}

async function politicaObservacion(page: Page) {
  // Estado auditado en producción: modo observación con capacidad explícita.
  await page.route('**/rest/v1/rpc/politica_rentabilidad_fn', async route => {
    await route.fulfill({ json: {
      version: 1, observacion_sin_aprobacion: true, expected_version: 18,
      vigente: { id: 'politica-e2e', version: 18, vigente_desde: '2026-09-23T00:00:00Z',
        tasa_base_nueva: 15, regla_renovacion: 'heredar', regla_upgrade: 'heredar', tope_tecnico: 25,
        vigencia_solicitud_dias: 1, modo: 'observacion', nota: null, publicada_en: '2026-09-23T00:00:00Z' },
      historial: [], observacion_activa_desde: '2026-09-23T00:00:00Z', puede_publicar: false,
    } })
  })
  await page.route('**/rest/v1/rpc/resolver_tasa_lead_fn', async route => {
    await route.fulfill({ json: {
      cliente_id: null, categoria: 'nuevo', tasa_base: 15, regla: 'primera_inversion', contrato_origen: null,
      contratos_previos: 0, contratos_activos: 0, prioridad_bandeja: false, observacion_sin_aprobacion: true,
      politica: { id: 'politica-e2e', version: 18, modo: 'observacion', tasa_base_nueva: 15, tope_tecnico: 25, vigencia_solicitud_dias: 1 },
    } })
  })
}

for (const rol of ['coordinador', 'vendedor', 'supervisor', 'gerencia', 'directorio']) {
  test(`${rol}: ficha y consultas de tasa respetan la capacidad de lectura`, async ({ page }) => {
    await page.clock.install()
    await montarBackendReal(page, { rolCrm: rol, rolPortal: rol === 'directorio' ? 'directorio' : 'comercial', leads: [lead] })
    await politicaObservacion(page)
    let consultas = 0
    await page.route('**/rest/v1/rpc/solicitudes_tasa_lead_fn', async route => {
      if (route.request().method() !== 'POST') return route.fallback()
      consultas++
      await route.fulfill(rol === 'coordinador'
        ? { status: 403, json: { code: '42501', message: 'No autorizado' } }
        : { json: [] })
    })
    await loginReal(page)
    let ficha = await abrir(page)
    await expect(ficha.getByRole('heading', { name: 'Datos', exact: true })).toBeVisible()
    if (rol === 'coordinador') {
      await expect(ficha.getByRole('button', { name: 'Mostrar solicitud de tasa' })).toHaveCount(0)
      await page.clock.fastForward(180_000)
      await ficha.getByRole('button', { name: 'Cerrar ficha' }).click()
      ficha = await abrir(page)
      await expect(ficha.getByRole('button', { name: 'Mostrar solicitud de tasa' })).toHaveCount(0)
      await page.waitForLoadState('networkidle')
      expect(consultas).toBe(0)
    } else {
      await ficha.getByRole('button', { name: 'Mostrar solicitud de tasa' }).click()
      await expect(ficha.getByLabel('Tasa anual (%)')).toBeVisible()
      await page.waitForLoadState('networkidle')
      expect(consultas).toBe(1)
      if (rol === 'directorio') {
        await expect(ficha.getByLabel('Tasa anual (%)')).toBeDisabled()
        await expect(ficha.getByRole('button', { name: /Convertir a cliente/ })).toHaveCount(0)
      }
    }
  })
}

test('403 en observación no crea ráfagas ni vuelve a consultarse al reabrir la ficha', async ({ page }) => {
  await page.clock.install()
  await montarBackendReal(page, { rolCrm: 'vendedor', leads: [lead] })
  await politicaObservacion(page)
  let consultas = 0
  await page.route('**/rest/v1/rpc/solicitudes_tasa_lead_fn', async route => {
    if (route.request().method() !== 'POST') return route.fallback()
    consultas++
    await route.fulfill({ status: 403, json: { code: '42501', message: 'No autorizado' } })
  })
  await loginReal(page)
  let ficha = await abrir(page)
  await ficha.getByRole('button', { name: 'Mostrar solicitud de tasa' }).click()
  await expect(ficha.getByLabel('Tasa anual (%)')).toBeVisible()
  await ficha.getByLabel('Tasa anual (%)').fill('19')
  await page.clock.fastForward(180_000)
  await expect(ficha.getByLabel('Tasa anual (%)')).toHaveValue('19')
  await page.waitForLoadState('networkidle')
  expect(consultas).toBe(1)
  await ficha.getByRole('button', { name: 'Cerrar ficha' }).click()
  ficha = await abrir(page)
  await ficha.getByRole('button', { name: 'Mostrar solicitud de tasa' }).click()
  await expect(ficha.getByLabel('Tasa anual (%)')).toBeVisible()
  await page.clock.fastForward(120_000)
  await page.waitForLoadState('networkidle')
  expect(consultas).toBe(1)
})

test('una sesión vencida recupera las solicitudes al renovarse, sin cerrar el formulario', async ({ page }) => {
  await page.clock.install()
  await montarBackendReal(page, { rolCrm: 'vendedor', leads: [lead] })
  await politicaObservacion(page)
  let vencida = true
  let recuperadas = 0
  await page.route('**/rest/v1/rpc/solicitudes_tasa_lead_fn', async route => {
    if (route.request().method() !== 'POST') return route.fallback()
    if (vencida) return route.fulfill({ status: 401, json: { code: 'PGRST301', message: 'JWT expired' } })
    recuperadas++
    await route.fulfill({ json: [] })
  })
  await loginReal(page)
  const ficha = await abrir(page)
  await ficha.getByRole('button', { name: 'Mostrar solicitud de tasa' }).click()
  await expect(ficha.getByLabel('Tasa anual (%)')).toBeVisible()
  await ficha.getByLabel('Tasa anual (%)').fill('19')
  vencida = false
  await page.clock.fastForward(61_000)
  await expect.poll(() => recuperadas).toBeGreaterThan(0)
  await expect(ficha.getByLabel('Tasa anual (%)')).toHaveValue('19')
})
