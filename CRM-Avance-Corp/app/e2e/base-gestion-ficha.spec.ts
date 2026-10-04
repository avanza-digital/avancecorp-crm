// E2E de la ficha de la base para gestión (F2), en sesión REAL con el HTTP de Supabase interceptado: el analista
// abre la ficha desde su hoja, lee el historial servido POR LEAD, registra «volver a llamar» con atajo, fecha y nota
// (y se comprueba lo que viaja a la puerta) y reactiva el lead, que vuelve a su cartera.
import { expect, test } from '@playwright/test'
import { leadReal, loginReal, montarBackendReal, UID } from './_helpers'

const LEAD = '00000000-0000-4000-8000-00000000ba5e'
const FILA = {
  lead_id: LEAD, nombre_completo: 'ROSA BASE E2E', telefono: '+51987654321', distrito: 'Surco', origen: 'landing',
  categoria_interes: null, monto_estimado: 10000, moneda: 'PEN', motivo_descarte: 'no_responde',
  descartado_en: '2026-09-25T15:00:00Z', dias_desde_descarte: 7, etapa_maxima: 'contactado', intentos: 1,
  ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-09-30T15:00:00Z', proxima_llamada_en: null,
  rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: UID, gestiona: 'QA REAL', recibido_en: '2026-08-15T15:00:00Z',
}
const HISTORIAL = {
  version: 1,
  items: [{
    id: 'act-base-1', lead_id: LEAD, tipo: 'llamada_no_contestada', detalle: 'sin respuesta', autor_nombre: 'QA REAL',
    creado_en: '2026-09-30T15:00:00Z', metadata: { evento: 'intento_base', intento_n: 1, resultado: 'no_contesto' },
  }],
  senales: { tiene_reunion_realizada: false, tiene_contacto: false, ultima_conversacion_en: null },
}

test('la ficha de la base registra «volver a llamar» con su fecha y reactiva el lead', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', leads: [leadReal({ vendedor_id: UID })] })
  // Tras reactivarlo, el lead ya no está en la base (era el único): la base queda vacía.
  let reactivado = false
  await page.route('**/rest/v1/rpc/obtener_base_gestion', (route) => route.fulfill({ json: reactivado ? [] : [FILA] }))
  await page.route('**/rest/v1/rpc/actividades_de_lead_fn', (route) => route.fulfill({ json: HISTORIAL }))
  const intentos: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/registrar_intento_base', async (route) => {
    const cuerpo = route.request().postDataJSON() as Record<string, unknown>
    intentos.push(cuerpo)
    await route.fulfill({ json: { ok: true, replay: false, intento_n: 2, etapa: 'descartado', reactivado: false, enfriado_hasta: null, proxima_llamada_en: cuerpo.p_proxima_llamada } })
  })
  const reactivaciones: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/reactivar_lead_base', async (route) => {
    reactivaciones.push(route.request().postDataJSON() as Record<string, unknown>)
    reactivado = true
    await route.fulfill({ json: { replay: false, etapa: 'contactado', ciclo_n: 2 } })
  })

  await loginReal(page)
  await page.evaluate(() => { window.location.hash = '#/rescate' })
  await page.getByRole('button', { name: 'ROSA BASE E2E', exact: true }).click()
  const ficha = page.getByRole('dialog', { name: 'ROSA BASE E2E' })
  await expect(ficha.getByText('Intento 1 · No contestó')).toBeVisible()

  const formulario = ficha.getByRole('form', { name: '¿Qué pasó con la llamada?' })
  await formulario.getByText('No contestó', { exact: true }).click()
  // Elegido, la lista se contrae (el selector de Gestión Diaria): otro atajo no lo cambia hasta «Cambiar resultado».
  await expect(formulario.getByRole('radio')).toHaveCount(1)
  await page.keyboard.press('2')
  await expect(formulario.getByRole('radio', { name: /No contestó/ })).toBeChecked()
  await formulario.getByRole('button', { name: 'Cambiar resultado' }).click()
  await page.keyboard.press('2')
  await expect(formulario.getByRole('radio', { name: /volver a llamar/ })).toBeChecked()
  await formulario.getByLabel(/Nota/).fill('pidió que lo llamen mañana')
  await formulario.getByRole('button', { name: 'Guardar intento' }).click()
  await expect(page.getByText(/Intento 2 registrado/)).toBeVisible()
  expect(intentos).toHaveLength(1)
  expect(intentos[0]).toMatchObject({ p_lead_id: LEAD, p_resultado: 'volver_a_llamar', p_nota: 'pidió que lo llamen mañana' })
  expect(String(intentos[0]?.p_operacion_id)).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
  // Mañana a las 10:00 de Lima (el valor por defecto), como instante.
  expect(Date.parse(String(intentos[0]?.p_proxima_llamada))).toBeGreaterThan(Date.now())

  await ficha.getByRole('button', { name: 'Reactivar' }).click()
  const confirmar = page.getByRole('dialog', { name: '¿Reactivar a ROSA BASE E2E?' })
  await confirmar.getByRole('button', { name: 'Reactivar' }).click()
  await expect(page.getByText(/Reactivado: el lead volvió a tu cartera/)).toBeVisible()
  await expect(ficha).toHaveCount(0)
  expect(reactivaciones).toHaveLength(1)
  expect(reactivaciones[0]).toMatchObject({ p_lead_id: LEAD })
  // El lead salió de la lista con la ficha abierta: el foco NO cae en <body> (era el último: va al resumen).
  await expect(page.getByText('No tienes leads descartados por gestionar')).toBeVisible()
  await expect(page.getByRole('region', { name: 'Resumen de tu base' })).toBeFocused()
})

test('si el lead sale de la base con la ficha abierta, el foco pasa a su vecino (no cae en <body>)', async ({ page }) => {
  const OTRO = '00000000-0000-4000-8000-00000000ba5f'
  await montarBackendReal(page, { rolCrm: 'vendedor', leads: [leadReal({ vendedor_id: UID })] })
  let reactivado = false
  const otro = { ...FILA, lead_id: OTRO, nombre_completo: 'LUIS VECINO E2E', telefono: '+51987654322' }
  await page.route('**/rest/v1/rpc/obtener_base_gestion', (route) => route.fulfill({ json: reactivado ? [otro] : [FILA, otro] }))
  await page.route('**/rest/v1/rpc/actividades_de_lead_fn', (route) => route.fulfill({ json: HISTORIAL }))
  await page.route('**/rest/v1/rpc/reactivar_lead_base', async (route) => {
    reactivado = true
    await route.fulfill({ json: { replay: false, etapa: 'contactado', ciclo_n: 2 } })
  })

  await loginReal(page)
  await page.evaluate(() => { window.location.hash = '#/rescate' })
  await page.getByRole('button', { name: 'ROSA BASE E2E', exact: true }).click()
  const ficha = page.getByRole('dialog', { name: 'ROSA BASE E2E' })
  await ficha.getByRole('button', { name: 'Reactivar' }).click()
  await page.getByRole('dialog', { name: '¿Reactivar a ROSA BASE E2E?' }).getByRole('button', { name: 'Reactivar' }).click()
  await expect(ficha).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'ROSA BASE E2E', exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'LUIS VECINO E2E', exact: true })).toBeFocused()
})
