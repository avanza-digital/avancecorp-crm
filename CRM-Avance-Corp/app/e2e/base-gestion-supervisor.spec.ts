// E2E de la vista del supervisor (F4) en sesión REAL con el HTTP de Supabase interceptado: las dos pestañas («Descartes
// del mes», el Centro de rescate intacto y por defecto; «Gestión de la base»), el detalle de «Intentos de hoy», y
// «Ver no contactar» → ficha de consulta → «Quitar No contactar» (lo que viaja a la puerta). También el ESTADO DE
// PRODUCCIÓN: la B6b sin aplicar (PGRST202) no rompe la hoja ni ofrece lo que el servidor aún no tiene.
import { expect, test, type Page } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

const ANA = '00000000-0000-4000-8000-0000000a0a0a'
const LEAD = '00000000-0000-4000-8000-00000000f4a1'
const VETADO = '00000000-0000-4000-8000-00000000f4b2'
const FILA = {
  lead_id: LEAD, nombre_completo: 'ROSA EQUIPO E2E', telefono: '+51987654321', distrito: 'Surco', origen: 'landing',
  categoria_interes: null, monto_estimado: 10000, moneda: 'PEN', motivo_descarte: 'no_responde',
  descartado_en: '2026-09-25T15:00:00Z', dias_desde_descarte: 7, etapa_maxima: 'contactado', intentos: 1,
  ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-09-30T15:00:00Z', proxima_llamada_en: null,
  rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: ANA, gestiona: 'ANA E2E', recibido_en: '2026-08-15T15:00:00Z',
}
const B6B = { no_contactar: false, no_contactar_en: null, no_contactar_motivo: null, no_contactar_por: null }
const FILA_VETADA = {
  ...FILA, lead_id: VETADO, nombre_completo: 'JUAN VETADO E2E', telefono: '+51987654322',
  no_contactar: true, no_contactar_en: '2026-09-28T16:00:00Z', no_contactar_motivo: 'Pidió que no lo llamen más', no_contactar_por: 'ANA E2E',
}
const RESUMEN = [{ vendedor_id: ANA, nombre: 'ANA E2E', en_base: 1, rellamadas_hoy: 0, intentos_hoy: 2, reactivaciones_mes: 0 }]
const HISTORIAL = { version: 1, items: [], senales: { tiene_reunion_realizada: false, tiene_contacto: false, ultima_conversacion_en: null } }

/** El mes en curso en Lima ('YYYY-MM-01'), como lo pide el Centro de rescate. */
function mesLima(): string {
  const partes = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit' }).formatToParts(new Date())
  return `${partes.find((p) => p.type === 'year')?.value}-${partes.find((p) => p.type === 'month')?.value}-01`
}

/** El Centro de rescate («Descartes del mes») con un mes y un descarte, para comprobar que sigue entero. */
async function montarDescartes(page: Page) {
  const mes = mesLima()
  await page.route('**/rest/v1/rpc/rescate_descartes_meses', (route) => route.fulfill({ json: [{ mes, total: 1, pendientes: 1 }] }))
  await page.route('**/rest/v1/rpc/rescate_descartes_mes', (route) => route.fulfill({ json: [{
    episodio_id: 'ep-1', lead_id: LEAD, nombre_completo: 'ROSA EQUIPO E2E', distrito: 'Surco', origen: 'landing', categoria_interes: null,
    monto_estimado: 10000, moneda: 'PEN', motivo_descarte: 'no_responde', descartado_en: `${mes.slice(0, 8)}02T15:00:00Z`,
    asesor_id: ANA, asesor_nombre: 'ANA E2E', puede_rescatar: true, estado: 'pendiente',
  }] }))
}

async function entrar(page: Page) {
  await loginReal(page)
  await page.evaluate(() => { window.location.hash = '#/rescate' })
}

test('pestañas: «Descartes del mes» intacto por defecto; «Gestión de la base» con el panel, «Gestiona» y el detalle de «Intentos de hoy»', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'supervisor' })
  await montarDescartes(page)
  const cuerposBase: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/obtener_base_gestion', async (route) => {
    cuerposBase.push(route.request().postDataJSON() as Record<string, unknown>)
    await route.fulfill({ json: [{ ...FILA, ...B6B }] })
  })
  await page.route('**/rest/v1/rpc/base_gestion_resumen', (route) => route.fulfill({ json: RESUMEN }))
  const cuerposDetalle: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/base_gestion_resumen_detalle', async (route) => {
    cuerposDetalle.push(route.request().postDataJSON() as Record<string, unknown>)
    await route.fulfill({ json: [
      { lead_id: LEAD, nombre_completo: 'ROSA EQUIPO E2E', en: new Date().toISOString(), detalle: 'no_contesto', autor: 'ANA E2E', sigue_en_base: true },
      { lead_id: 'otro', nombre_completo: 'LUIS YA REACTIVADO', en: new Date(Date.now() - 3_600_000).toISOString(), detalle: 'agendo_reunion', autor: 'ANA E2E', sigue_en_base: false },
    ] })
  })
  await page.route('**/rest/v1/rpc/actividades_de_lead_fn', (route) => route.fulfill({ json: HISTORIAL }))

  await entrar(page)
  // Por defecto, el Centro de rescate de siempre: su carpeta y «Abrir en otra pestaña» siguen ahí.
  await expect(page.getByRole('tab', { name: 'Descartes del mes' })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('button', { name: 'Abrir carpeta No responde' })).toBeVisible()
  await expect(page.getByRole('button', { name: /Abrir en otra pestaña/ })).toBeVisible()
  expect(cuerposBase).toHaveLength(0)

  await page.getByRole('tab', { name: 'Gestión de la base' }).click()
  await expect(page).toHaveURL(/\?rescate_vista=gestion#\/rescate$/)
  const panel = page.getByRole('region', { name: 'Por analista' })
  await expect(panel.getByRole('rowheader', { name: 'ANA E2E' })).toBeVisible()
  const hoja = page.getByRole('region', { name: 'Base para gestión de tu equipo' })
  await expect(hoja.getByRole('columnheader').nth(2)).toHaveText('Gestiona')
  await expect(hoja.getByRole('rowheader', { name: 'ROSA EQUIPO E2E' })).toBeVisible()
  // Con el interruptor apagado se pregunta igual (así se sabe que el servidor tiene la B6b).
  // (Un refresco al volver a la pestaña repite la misma pregunta: se comprueba qué viaja, no cuántas veces.)
  expect(cuerposBase[0]).toEqual({ p_incluir_vetados: false })
  expect(cuerposBase.every((c) => c.p_incluir_vetados === false)).toBe(true)
  await expect(page.getByRole('button', { name: 'Ver no contactar' })).toHaveAttribute('aria-pressed', 'false')

  // «En base» filtra la hoja por ese analista y lo escribe en la URL.
  await panel.getByRole('button', { name: /ANA E2E, en base/ }).click()
  await expect(page).toHaveURL(new RegExp(`rescate_analista=${ANA}`))
  await expect(page.getByRole('combobox', { name: 'Analista' })).toHaveValue(ANA)

  // «Intentos de hoy» abre su detalle; el lead que sigue en la base abre su ficha de consulta encima.
  await panel.getByRole('button', { name: /ANA E2E, intentos de hoy/ }).click()
  const detalle = page.getByRole('dialog', { name: /Intentos de hoy/ })
  await expect(detalle.getByText('No contestó')).toBeVisible()
  await expect(detalle.getByText('Salió de la base')).toBeVisible()
  expect(cuerposDetalle).toContainEqual({ p_vendedor_id: ANA, p_cifra: 'intentos_hoy' })
  await detalle.getByRole('button', { name: 'ROSA EQUIPO E2E' }).click()
  const ficha = page.getByRole('dialog', { name: 'ROSA EQUIPO E2E' })
  await expect(ficha.getByText(/Ficha de consulta/)).toBeVisible()
  await expect(ficha.getByRole('form', { name: '¿Qué pasó con la llamada?' })).toHaveCount(0)
  await expect(ficha.getByRole('button', { name: /Reactivar/ })).toHaveCount(0)

  // Recargar conserva la pestaña y el analista.
  await page.keyboard.press('Escape')
  await page.keyboard.press('Escape')
  await page.reload()
  await expect(page.getByRole('tab', { name: 'Gestión de la base' })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('combobox', { name: 'Analista' })).toHaveValue(ANA)
})

test('«Ver no contactar» → ficha de consulta → «Quitar No contactar» manda el lead y el motivo a la puerta', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'supervisor' })
  await montarDescartes(page)
  let levantado = false
  const cuerposBase: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/obtener_base_gestion', async (route) => {
    const cuerpo = route.request().postDataJSON() as Record<string, unknown>
    cuerposBase.push(cuerpo)
    const vetado = levantado ? { ...FILA_VETADA, ...B6B } : FILA_VETADA
    await route.fulfill({ json: cuerpo.p_incluir_vetados ? [{ ...FILA, ...B6B }, vetado] : [{ ...FILA, ...B6B }] })
  })
  await page.route('**/rest/v1/rpc/base_gestion_resumen', (route) => route.fulfill({ json: RESUMEN }))
  await page.route('**/rest/v1/rpc/actividades_de_lead_fn', (route) => route.fulfill({ json: HISTORIAL }))
  const levantar: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/levantar_no_contactar', async (route) => {
    levantar.push(route.request().postDataJSON() as Record<string, unknown>)
    levantado = true
    await route.fulfill({ json: { ok: true, lead_id: VETADO, inversionista_id: null, leads_afectados: 2 } })
  })

  await entrar(page)
  await page.getByRole('tab', { name: 'Gestión de la base' }).click()
  await page.getByRole('button', { name: 'Ver no contactar' }).click()
  await expect(page.getByRole('button', { name: 'Ver no contactar' })).toHaveAttribute('aria-pressed', 'true')
  const bloque = page.getByRole('region', { name: /^No contactar/ })
  await expect(bloque.getByText('Pidió que no lo llamen más')).toBeVisible()
  expect(cuerposBase).toContainEqual({ p_incluir_vetados: true })
  // El vetado no está en la hoja principal ni se ofrece para llamar.
  await expect(page.getByRole('region', { name: 'Base para gestión de tu equipo' }).getByRole('rowheader', { name: 'JUAN VETADO E2E' })).toHaveCount(0)

  await bloque.getByRole('button', { name: 'JUAN VETADO E2E' }).click()
  const ficha = page.getByRole('dialog', { name: 'JUAN VETADO E2E' })
  await expect(ficha.getByRole('heading', { name: /No contactar · Ley 29571/ })).toBeVisible()
  await ficha.getByRole('button', { name: /Quitar «No contactar»/ }).click()
  const dialogo = page.getByRole('dialog', { name: 'Quitar «No contactar» a JUAN VETADO E2E' })
  await expect(dialogo.getByText(/Se levanta para la persona y todos sus leads/)).toBeVisible()
  await dialogo.getByLabel('Motivo').fill('abc')
  await dialogo.getByRole('button', { name: 'Quitar la marca' }).click()
  await expect(dialogo.getByRole('alert')).toContainText('mínimo 5 caracteres')
  expect(levantar).toHaveLength(0)
  await dialogo.getByLabel('Motivo').fill('Volvió a pedir información por WhatsApp')
  await dialogo.getByRole('button', { name: 'Quitar la marca' }).click()
  await expect(page.getByText('«No contactar» quitado para la persona y sus 2 leads.')).toBeVisible()
  expect(levantar).toEqual([{ p_lead_id: VETADO, p_motivo: 'Volvió a pedir información por WhatsApp' }])
  // Tras refrescar, el lead ya no está vetado: la ficha sigue abierta sin la marca y sin el botón.
  await expect(ficha.getByRole('button', { name: /Quitar «No contactar»/ })).toHaveCount(0)
})

test('ESTADO DE PRODUCCIÓN (B6b sin aplicar): PGRST202 → la hoja llega igual, sin «Ver no contactar» y sin abrir el detalle', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'supervisor' })
  await montarDescartes(page)
  const cuerposBase: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/obtener_base_gestion', async (route) => {
    const cuerpo = route.request().postDataJSON() as Record<string, unknown>
    cuerposBase.push(cuerpo)
    if ('p_incluir_vetados' in cuerpo) {
      await route.fulfill({ status: 404, json: { code: 'PGRST202', message: 'Could not find the function crm.obtener_base_gestion(p_incluir_vetados) in the schema cache', details: null, hint: null } })
      return
    }
    await route.fulfill({ json: [FILA] })
  })
  await page.route('**/rest/v1/rpc/base_gestion_resumen', (route) => route.fulfill({ json: RESUMEN }))

  await entrar(page)
  await page.getByRole('tab', { name: 'Gestión de la base' }).click()
  const hoja = page.getByRole('region', { name: 'Base para gestión de tu equipo' })
  await expect(hoja.getByRole('rowheader', { name: 'ROSA EQUIPO E2E' })).toBeVisible()
  expect(cuerposBase.slice(0, 2)).toEqual([{ p_incluir_vetados: false }, {}])
  await expect(page.getByRole('button', { name: 'Ver no contactar' })).toHaveCount(0)
  const panel = page.getByRole('region', { name: 'Por analista' })
  await expect(panel.getByRole('button', { name: /intentos de hoy/ })).toHaveCount(0)
  await expect(panel.getByRole('button', { name: /en base/ })).toBeVisible()
})
