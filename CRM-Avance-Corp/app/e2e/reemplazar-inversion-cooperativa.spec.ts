// E2E — «Reemplazar inversión» de una COOPERATIVA (Fase 4, 18/10/2026) desde la ficha del inversionista. El backend
// simulado de _helpers.ts sirve la sesión; aquí se simulan la ficha (una inversión INICIAL de Prodelco), la vista previa
// del mes, la subida del comprobante al bucket y la puerta del reemplazo, y se comprueba EXACTAMENTE lo que viaja
// (postDataJSON): p_cierre lleva solo lo que cambia y el comprobante se sube ANTES de confirmar. El servidor real
// (migración 20261018053228) se prueba aparte con su kit (supabase/scripts/reemplazar-inversion-cooperativa/).
import { expect, test, type Page } from '@playwright/test'
import { irAMiCartera, loginReal, montarBackendReal } from './_helpers'
import { carteraF5, fichaF5, FUENTE_F5, inversionProdelcoF5, PERSONA_F5 } from '../src/test/fixtures/f5'
import type { InversionFuente } from '../src/lib/inversionistas'

const NUEVO = '66666666-6666-4666-8666-666666666666'
const AUDITORIA = '77777777-7777-4777-8777-777777777777'
const LEAD = '88888888-8888-4888-8888-888888888888'
const ORIGINAL: InversionFuente = { ...inversionProdelcoF5, inversion_id: FUENTE_F5 }
const DIALOGO = 'Reemplazar inversión en Prodelco PRODELCO SINTÉTICO'

/** La ficha (cartera multiempresa habilitada) y la vista previa: «la venta queda en» el mes de la fecha pedida. */
async function fichaCon(page: Page, inversiones: InversionFuente[], previa: Record<string, unknown> = {}) {
  await page.route('**/rest/v1/rpc/*', async route => {
    const nombre = new URL(route.request().url()).pathname.split('/').at(-1)
    if (nombre === 'cartera_inversionistas_estado_fn') return route.fulfill({ json: { version: 1, habilitada: true, escritura_habilitada: true, motivo: null } })
    if (nombre === 'cartera_inversionistas_filtrada_fn') return route.fulfill({ json: carteraF5 })
    if (nombre === 'inversionista_ficha_fn') return route.fulfill({ json: { ...fichaF5, inversiones, inversiones_total: inversiones.length } })
    if (nombre === 'reemplazar_inversion_cooperativa_vista_previa_fn') {
      const a = route.request().postDataJSON() as { p_fuente_id: string; p_fecha_comercial?: string }
      const fecha = a.p_fecha_comercial ?? '2026-10-05'
      const mes = `${fecha.slice(0, 7)}-01`
      return route.fulfill({ json: { fuente_id: a.p_fuente_id, cooperativa: 'prodelco', es_inicial: true, anulada: false,
        venta_de_lead: true, comprobante: true, fecha_comercial_actual: '2026-10-05', mes_actual: '2026-10-01',
        fecha_comercial_resultante: fecha, mes_resultante: mes, cambia_mes: mes !== '2026-10-01', fecha_futura: false,
        mes_sellado: false, plazo_vencido: false, no_reemplazable: null, ...previa } })
    }
    return route.fallback()
  })
}

async function abrirReemplazo(page: Page) {
  await page.getByRole('button', { name: 'Abrir ficha de ANA SINTÉTICA F5' }).click()
  await page.getByRole('button', { name: 'Reemplazar inversión PRODELCO SINTÉTICO' }).click()
  const dialogo = page.getByRole('dialog', { name: DIALOGO })
  await expect(dialogo).toBeVisible()
  return dialogo
}

for (const [ancho, alto] of [[1440, 1000], [1366, 768], [390, 844]] as const) test(`Gerencia cambia cooperativa, fecha y comprobante y la venta se conserva (${ancho}×${alto})`, async ({ page }, info) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'analista', contratos: [] })
  await fichaCon(page, [ORIGINAL])
  const orden: string[] = []
  let subida: string | null = null
  let pedido: Record<string, unknown> | null = null
  await page.route('**/storage/v1/object/f4-comprobantes/**', route => {
    orden.push('subida')
    subida = decodeURIComponent(new URL(route.request().url()).pathname.split('/storage/v1/object/f4-comprobantes/')[1] ?? '')
    return route.fulfill({ json: { Key: `f4-comprobantes/${subida}` } })
  })
  await page.route('**/rest/v1/rpc/reemplazar_inversion_cooperativa_fn', route => {
    orden.push('puerta')
    pedido = route.request().postDataJSON() as Record<string, unknown>
    return route.fulfill({ json: { ok: true, modo: 'nueva', fuente_id: FUENTE_F5, cierre_id: NUEVO, inversion_id: NUEVO,
      auditoria_id: AUDITORIA, cooperativa: 'qorilazo', fecha_comercial: '2026-09-28', vence_en: '2027-09-23', comprobante_cambiado: true,
      conversion: { lead_id: LEAD, estado: 'acreditada', periodo_antes: '2026-10-01', periodo_despues: '2026-09-01' } } })
  })
  await loginReal(page); await irAMiCartera(page)
  await page.setViewportSize({ width: ancho, height: alto })
  const dialogo = await abrirReemplazo(page)

  // La original, fija; la correcta, precargada con sus tres controles; el mes, del servidor.
  const original = dialogo.getByRole('region', { name: 'La original' })
  await expect(original).toContainText('S/ 3,000')
  await expect(original).toContainText('OP-SINTÉTICA-1')
  await expect(dialogo.getByRole('radio', { name: /Prodelco/ })).toBeChecked()
  await expect(dialogo.getByLabel('Fecha comercial')).toHaveValue('2026-10-05')
  await expect(dialogo.getByRole('radio', { name: /Conservar el de la original/ })).toBeChecked()
  const mes = dialogo.getByRole('status').filter({ hasText: 'La venta queda en' })
  await expect(mes).toContainText('Octubre 2026')
  await expect(mes).toContainText('Igual que ahora')
  const confirmar = dialogo.getByRole('button', { name: 'Reemplazar inversión', exact: true })
  await dialogo.getByLabel('Motivo del reemplazo').fill('Se registró en la cooperativa y el mes equivocados')
  await expect(confirmar).toBeDisabled()                       // sin cambios, no

  await dialogo.getByRole('radio', { name: /Qorilazo/ }).check()
  await dialogo.getByLabel('Fecha comercial').fill('2026-09-28')
  await expect(mes).toContainText('Septiembre 2026')
  await expect(mes).toContainText('Se muda desde octubre 2026')
  await dialogo.getByRole('radio', { name: /Subir otro comprobante/ }).check()
  await dialogo.getByLabel(/Comprobante nuevo/).setInputFiles({ name: 'deposito.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4\n% comprobante sintético') })
  const cambios = dialogo.getByRole('list', { name: 'Cambios' })
  await expect(cambios).toContainText('Qorilazo')
  await expect(cambios).toContainText('Fecha comercial')
  await expect(cambios).toContainText('Comprobante')
  await expect(confirmar).toBeEnabled()
  expect(await dialogo.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
  await expect(dialogo.getByRole('heading', { level: 2 })).toHaveCount(1)
  // «La original» (sin controles) cabe entera: nada que haya que desplazar sin poder enfocarlo.
  expect(await original.evaluate(el => el.scrollHeight <= el.clientHeight + 1)).toBe(true)
  await page.screenshot({ path: info.outputPath('reemplazo-cooperativa.png'), fullPage: true })

  // Con teclado: del motivo se llega a las acciones (van después) y se confirma con Enter.
  await dialogo.getByLabel('Motivo del reemplazo').focus()
  await page.keyboard.press('Tab')
  await expect(dialogo.getByRole('button', { name: 'Cancelar' })).toBeFocused()
  await page.keyboard.press('Tab')
  await expect(confirmar).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(dialogo).toHaveCount(0)
  await expect(page.getByText('Inversión en Prodelco reemplazada. Ahora está en Qorilazo. La venta quedó en septiembre 2026.')).toBeVisible()
  await expect(page.getByRole('region', { name: 'Inversiones y contratos' })).toBeFocused()

  // Lo que viajó: el comprobante ANTES de la puerta, en la carpeta de la persona y del reemplazo; y en p_cierre, las tres.
  expect(orden).toEqual(['subida', 'puerta'])
  expect(subida).toMatch(new RegExp(`^${PERSONA_F5}/reemplazo-${FUENTE_F5}/[0-9a-f-]{36}\\.pdf$`))
  expect(pedido).toEqual({ p_fuente_id: FUENTE_F5, p_motivo: 'Se registró en la cooperativa y el mes equivocados',
    p_cierre: { cooperativa: 'qorilazo', fecha_comercial: '2026-09-28', comprobante_ruta: subida } })
})

test('Solo la cooperativa: no se sube nada, viaja solo esa clave y un rechazo del servidor se muestra tal cual', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'admin', contratos: [] })
  await fichaCon(page, [ORIGINAL])
  let subidas = 0
  const pedidos: unknown[] = []
  await page.route('**/storage/v1/object/f4-comprobantes/**', route => { subidas++; return route.abort() })
  await page.route('**/rest/v1/rpc/reemplazar_inversion_cooperativa_fn', route => {
    pedidos.push(route.request().postDataJSON())
    return pedidos.length === 1
      ? route.fulfill({ status: 400, json: { code: 'P0409', details: null, hint: null, message: 'El mes de esta venta ya está cerrado: no se reemplaza' } })
      : route.fulfill({ json: { ok: true, idempotente: true, fuente_id: FUENTE_F5, cierre_id: NUEVO, auditoria_id: AUDITORIA,
        cooperativa: 'qorilazo', fecha_comercial: '2026-10-05' } })
  })
  await loginReal(page); await irAMiCartera(page)
  const dialogo = await abrirReemplazo(page)
  await dialogo.getByRole('radio', { name: /Qorilazo/ }).check()
  await dialogo.getByLabel('Motivo del reemplazo').fill('Se registró en la cooperativa equivocada')
  const confirmar = dialogo.getByRole('button', { name: 'Reemplazar inversión', exact: true })
  await confirmar.click()
  await expect(dialogo.getByRole('alert')).toHaveText('El mes de esta venta ya está cerrado: no se reemplaza')
  await expect(dialogo).toBeVisible()
  await confirmar.click()                                      // el reintento ya hecho vuelve como idempotente
  await expect(dialogo).toHaveCount(0)
  await expect(page.getByText('Inversión en Prodelco reemplazada. Ahora está en Qorilazo.')).toBeVisible()
  expect(subidas).toBe(0)
  expect(pedidos).toEqual([1, 2].map(() => ({ p_fuente_id: FUENTE_F5, p_motivo: 'Se registró en la cooperativa equivocada', p_cierre: { cooperativa: 'qorilazo' } })))
})

test('Si la original no se puede reemplazar, se dice al abrir y no deja confirmar (el servidor se negaría)', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'analista', contratos: [] })
  await fichaCon(page, [ORIGINAL], { no_reemplazable: 'La inversión tiene una reinversión registrada: no se elimina' })
  let llamadas = 0
  await page.route('**/rest/v1/rpc/reemplazar_inversion_cooperativa_fn', route => { llamadas++; return route.abort() })
  await loginReal(page); await irAMiCartera(page)
  const dialogo = await abrirReemplazo(page)
  await expect(dialogo.getByRole('alert')).toContainText('tiene una reinversión registrada')
  await dialogo.getByRole('radio', { name: /Qorilazo/ }).check()
  await dialogo.getByLabel('Motivo del reemplazo').fill('Se registró en la cooperativa equivocada')
  await expect(dialogo.getByRole('button', { name: 'Reemplazar inversión', exact: true })).toBeDisabled()
  expect(llamadas).toBe(0)
})

for (const [rolCrm, rolPortal, inicial, visible] of [
  ['gerencia', 'analista', true, true],       // Gerencia sin admin del portal: sí
  ['gerencia', 'admin', true, true],          // Gerencia con admin del portal: sí
  ['vendedor', 'admin', true, false],         // admin del portal sin Gerencia: NO (es la venta de un lead; auditoría RLS, P1)
  ['vendedor', 'analista', true, false],      // analista: no
  ['gerencia', 'analista', false, false],     // un aporte adicional no se reemplaza: se corrige o se elimina
] as const) test(`«Reemplazar inversión» de cooperativa ${visible ? 'se ofrece' : 'no se ofrece'} a ${rolCrm}/${rolPortal}${inicial ? '' : ' en un aporte adicional'}`, async ({ page }) => {
  await montarBackendReal(page, { rolCrm, rolPortal, contratos: [] })
  await fichaCon(page, [{ ...ORIGINAL, es_inicial: inicial }])
  await loginReal(page); await irAMiCartera(page)
  await page.getByRole('button', { name: 'Abrir ficha de ANA SINTÉTICA F5' }).click()
  await expect(page.getByRole('button', { name: 'Ver inversión PRODELCO SINTÉTICO' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Reemplazar inversión PRODELCO SINTÉTICO' })).toHaveCount(visible ? 1 : 0)
})
