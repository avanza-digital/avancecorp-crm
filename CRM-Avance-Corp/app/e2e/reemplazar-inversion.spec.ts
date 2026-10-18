// E2E — «Reemplazar inversión» (Fase 2, 17/10/2026) desde la ficha del inversionista. El backend simulado de
// _helpers.ts sirve la sesión, el cliente (cuentas y datos legales) y la política de tasa; aquí se simulan la ficha,
// la vista previa del mes y las dos puertas del reemplazo, y se comprueba EXACTAMENTE lo que viaja (postDataJSON).
// El servidor real (stack local con las migraciones 20261017162053 y 20261017211313) se probó aparte: ver la nota
// del vault «Reemplazar inversion - plan por fases (2026-10-17)».
import { expect, test, type Page } from '@playwright/test'
import { clienteReal, irAMiCartera, loginReal, montarBackendReal } from './_helpers'
import { carteraF5, fichaF5, inversionF5 } from '../src/test/fixtures/f5'
import type { InversionFuente } from '../src/lib/inversionistas'

const CLIENTE = clienteReal().id
const ORIGINAL = '33333333-3333-4333-8333-333333333333'
const OTRA = '55555555-5555-4555-8555-555555555555'
const NUEVO = '66666666-6666-4666-8666-666666666666'
const AUDITORIA = '77777777-7777-4777-8777-777777777777'
const CON_CUOTAS = '99999999-9999-4999-8999-999999999999'

function inversion(fuente: string, numero: string, over: Partial<InversionFuente> = {}): InversionFuente {
  return {
    ...inversionF5, fuente_id: fuente, inversion_id: fuente, empresa: 'avance', perfil_id: CLIENTE, numero, capital: 5000,
    moneda: 'PEN', estado: 'activo', fecha_comercial: '2026-10-05', fecha_imputacion: '2026-10-05', vence_en: '2027-10-05',
    es_inicial: false, lead_id: null, pdf: null, cotitulares: [], documentos: [],
    contrato: { fecha_inicio: '2026-10-05', tasa_anual: 15, modalidad: 'mensual', tipo_interes: 'simple', categoria: 'nuevo' },
    ...over,
  }
}

/** La ficha (cartera multiempresa habilitada) y la vista previa del mes: «la venta queda en» según la fecha. */
async function fichaCon(page: Page, inversiones: InversionFuente[]) {
  await page.route('**/rest/v1/rpc/*', async route => {
    const nombre = new URL(route.request().url()).pathname.split('/').at(-1)
    if (nombre === 'cartera_inversionistas_estado_fn') return route.fulfill({ json: { version: 1, habilitada: true, escritura_habilitada: true, motivo: null } })
    if (nombre === 'cartera_inversionistas_filtrada_fn') return route.fulfill({ json: carteraF5 })
    if (nombre === 'inversionista_ficha_fn') return route.fulfill({ json: { ...fichaF5, persona: { ...fichaF5.persona, perfil_id: CLIENTE },
      inversiones, inversiones_total: inversiones.length } })
    if (nombre === 'reemplazar_inversion_vista_previa_fn') {
      const a = route.request().postDataJSON() as { p_fuente_id: string; p_fecha_inicio?: string; p_conservar_id?: string }
      const fecha = a.p_fecha_inicio ?? '2026-10-05'
      const mes = `${fecha.slice(0, 7)}-01`
      return route.fulfill({ json: { fuente_id: a.p_fuente_id, fecha_inicio: fecha, fecha_comercial_actual: '2026-10-05',
        mes_actual: '2026-10-01', fecha_comercial_resultante: fecha, mes_resultante: mes, cambia_mes: mes !== '2026-10-01', fecha_corregida: false,
        cuotas_pagadas: a.p_fuente_id === CON_CUOTAS } })
    }
    return route.fallback()
  })
}

async function abrirReemplazo(page: Page, numero: string) {
  await page.getByRole('button', { name: 'Abrir ficha de ANA SINTÉTICA F5' }).click()
  await page.getByRole('button', { name: `Reemplazar inversión ${numero}` }).click()
  const dialogo = page.getByRole('dialog', { name: `Reemplazar inversión ${numero}` })
  await expect(dialogo).toBeVisible()
  return dialogo
}

for (const [ancho, alto] of [[1440, 1000], [1366, 768], [390, 844]] as const) test(`Gerencia y admin reemplazan con los datos correctos y la venta se conserva (${ancho}×${alto})`, async ({ page }, info) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'admin', contratos: [] })
  await fichaCon(page, [inversion(ORIGINAL, '2026-01-999999')])
  let pedido: Record<string, unknown> | null = null
  await page.route('**/rest/v1/rpc/reemplazar_inversion_fn', async route => {
    pedido = route.request().postDataJSON() as Record<string, unknown>
    return route.fulfill({ json: { ok: true, modo: 'nueva', fuente_id: ORIGINAL, contrato_id: NUEVO, numero_contrato: '2026-01-999999',
      auditoria_id: AUDITORIA, conversion: null, id: NUEVO, cuenta_bancaria_id: null,
      pdf: { contrato_id: NUEVO, job_id: null, estado: 'pendiente', reintentable: true } } })
  })
  await loginReal(page); await irAMiCartera(page)
  await page.setViewportSize({ width: ancho, height: alto })
  const dialogo = await abrirReemplazo(page, '2026-01-999999')

  // La original, fija; la correcta, precargada; el mes, del servidor.
  await expect(dialogo.getByText('El cliente y el analista no cambian en un reemplazo.')).toBeVisible()
  await expect(dialogo.locator('#ct-capital')).toHaveValue('5000')
  await expect(dialogo.locator('#ct-numero')).toHaveValue('999999')
  await expect(dialogo.getByRole('status').filter({ hasText: 'La venta queda en' })).toContainText('Octubre 2026')
  await expect(dialogo.getByRole('status').filter({ hasText: 'La venta queda en' })).toContainText('Igual que ahora')

  await dialogo.locator('#ct-capital').fill('50000')
  await dialogo.getByRole('radio', { name: /BCP.*8901/i }).check()
  const confirmar = dialogo.getByRole('button', { name: 'Reemplazar inversión', exact: true })
  await expect(confirmar).toBeDisabled()                       // sin motivo, no
  await dialogo.getByLabel('Motivo del reemplazo').fill('El capital se registró con un cero de menos')
  await expect(confirmar).toBeEnabled()
  await expect(dialogo.getByRole('list', { name: 'Cambios' })).toContainText('S/ 50,000')
  expect(await dialogo.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
  // Un solo título de diálogo (el formulario incrustado pinta un h3, no otro título).
  await expect(dialogo.getByRole('heading', { level: 2 })).toHaveCount(1)
  // Nada que haya que desplazar sin poder enfocarlo: «La original» (sin controles) cabe entera, y en celular el
  // formulario no lleva un desplazamiento propio dentro del del diálogo.
  const sinDesbordar = (el: Element) => el.scrollHeight <= el.clientHeight + 1
  expect(await dialogo.getByRole('region', { name: 'La original' }).evaluate(sinDesbordar)).toBe(true)
  if (ancho < 1024) {
    expect(await dialogo.getByRole('region', { name: 'La correcta' }).evaluate(sinDesbordar)).toBe(true)
    expect(await dialogo.locator('form').evaluate(f => [...f.querySelectorAll('*')].every(el =>
      !/(auto|scroll)/.test(getComputedStyle(el).overflowY) || el.scrollHeight <= el.clientHeight + 1))).toBe(true)
  }
  await page.screenshot({ path: info.outputPath('reemplazo-nueva.png'), fullPage: true })

  // Ida y vuelta a «Quedarme con la otra»: lo editado, el resumen y la cuenta siguen ahí.
  await dialogo.getByRole('button', { name: 'Quedarme con la otra' }).click()
  await expect(dialogo.locator('#ct-capital')).toBeHidden()
  await dialogo.getByRole('button', { name: 'Con los datos correctos' }).click()
  await expect(dialogo.locator('#ct-capital')).toHaveValue('50000')
  await expect(dialogo.getByRole('radio', { name: /BCP.*8901/i })).toBeChecked()
  await expect(dialogo.getByRole('list', { name: 'Cambios' })).toContainText('S/ 50,000')

  // Un Enter en un campo de «La correcta» NO confirma (es irreversible): solo el botón.
  await dialogo.locator('#ct-capital').press('Enter')
  // Aserción negativa: se deja un margen para que un envío, si lo hubiera, llegue al servidor simulado.
  await page.waitForTimeout(600)
  await expect(dialogo).toBeVisible()
  expect(pedido).toBeNull()

  // Con teclado: del motivo se llega a las acciones (van después) y se confirma con Enter.
  await dialogo.getByLabel('Motivo del reemplazo').focus()
  await page.keyboard.press('Tab')
  await expect(dialogo.getByRole('button', { name: 'Cancelar' })).toBeFocused()
  await page.keyboard.press('Tab')
  await expect(confirmar).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(dialogo).toHaveCount(0)
  await expect(page.getByText('Inversión 2026-01-999999 reemplazada por N° 2026-01-999999.')).toBeVisible()
  // El foco no se pierde: la fila de la original desaparece, así que va a las inversiones.
  await expect(page.getByRole('region', { name: 'Inversiones y contratos' })).toBeFocused()
  // Lo que viajó: el mismo contenido económico que el alta, SIN analista ni clave del alta (los fija el servidor).
  expect(pedido).not.toBeNull()
  const p = pedido as unknown as { p_fuente_id: string; p_motivo: string; p_contrato: Record<string, unknown>; p_cronograma: unknown[]; p_cuenta: { tipo: string } }
  expect(p.p_fuente_id).toBe(ORIGINAL)
  expect(p.p_motivo).toBe('El capital se registró con un cero de menos')
  expect(p.p_contrato).toMatchObject({ cliente_id: CLIENTE, capital: 50000, moneda: 'PEN', categoria: 'nuevo', numero_contrato: '2026-01-999999', fecha_inicio: '2026-10-05' })
  expect(p.p_contrato).not.toHaveProperty('analista_cierre_id')
  expect(p.p_contrato).not.toHaveProperty('clave_idempotencia')
  expect(p.p_cronograma.length).toBeGreaterThan(0)
  expect(p.p_cuenta.tipo).toBe('perfil')
})

test('Quedarme con la otra: se elige la carga doble y la venta pasa a ella', async ({ page }, info) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'admin', contratos: [] })
  await fichaCon(page, [inversion(ORIGINAL, '2026-01-999999'), inversion(OTRA, '2026-01-999998'),
    inversion('88888888-8888-4888-8888-888888888888', '2026-01-999997', { capital: 800 })])
  let pedido: unknown = null
  await page.route('**/rest/v1/rpc/reemplazar_inversion_por_existente_fn', async route => {
    pedido = route.request().postDataJSON()
    return route.fulfill({ json: { ok: true, modo: 'existente', fuente_id: ORIGINAL, contrato_id: OTRA, numero_contrato: '2026-01-999998',
      auditoria_id: AUDITORIA, conversion: null } })
  })
  await loginReal(page); await irAMiCartera(page)
  const dialogo = await abrirReemplazo(page, '2026-01-999999')
  await dialogo.getByRole('button', { name: 'Quedarme con la otra' }).click()
  await expect(dialogo.getByText('Elige la inversión que se conserva.')).toBeVisible()
  await expect(dialogo.getByRole('radio', { name: /2026-01-999997/ })).toBeVisible()
  await expect(dialogo.getByText('Distinta: capital')).toBeVisible()
  await dialogo.getByRole('radio', { name: /2026-01-999998/ }).check()
  await expect(dialogo.getByText('Igual a la original')).toBeVisible()
  await expect(dialogo.getByRole('status').filter({ hasText: 'La venta queda en' })).toContainText('Octubre 2026')
  await dialogo.getByLabel('Motivo del reemplazo').fill('Se cargó dos veces el mismo contrato')
  await page.screenshot({ path: info.outputPath('reemplazo-existente.png'), fullPage: true })
  await dialogo.getByRole('button', { name: 'Quedarme con 2026-01-999998' }).click()
  await expect(dialogo).toHaveCount(0)
  await expect(page.getByText('Inversión 2026-01-999999 reemplazada por N° 2026-01-999998.')).toBeVisible()
  await expect(page.getByRole('region', { name: 'Inversiones y contratos' })).toBeFocused()
  expect(pedido).toEqual({ p_fuente_id: ORIGINAL, p_conservar_id: OTRA, p_motivo: 'Se cargó dos veces el mismo contrato' })
})

test('Un rechazo del servidor (mes cerrado) se muestra tal cual y no cierra el diálogo', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'admin', contratos: [] })
  await fichaCon(page, [inversion(ORIGINAL, '2026-01-999999'), inversion(OTRA, '2026-01-999998')])
  let intentos = 0
  await page.route('**/rest/v1/rpc/reemplazar_inversion_por_existente_fn', async route => {
    intentos++
    return route.fulfill({ status: 400, json: { code: 'P0409', details: null, hint: null,
      message: 'El mes de esta venta ya está cerrado: no se reemplaza' } })
  })
  await loginReal(page); await irAMiCartera(page)
  const dialogo = await abrirReemplazo(page, '2026-01-999999')
  await dialogo.getByRole('button', { name: 'Quedarme con la otra' }).click()
  await dialogo.getByRole('radio', { name: /2026-01-999998/ }).check()
  await dialogo.getByLabel('Motivo del reemplazo').fill('Se cargó dos veces el mismo contrato')
  await dialogo.getByRole('button', { name: 'Quedarme con 2026-01-999998' }).click()
  await expect(dialogo.getByRole('alert')).toHaveText('El mes de esta venta ya está cerrado: no se reemplaza')
  await expect(dialogo).toBeVisible()
  expect(intentos).toBe(1)
})

test('Con cuotas pagadas la pantalla lo dice al abrir y no deja confirmar (el servidor se negaría)', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'admin', contratos: [] })
  await fichaCon(page, [inversion(CON_CUOTAS, '2026-01-999996')])
  let llamadas = 0
  await page.route('**/rest/v1/rpc/reemplazar_inversion_fn', route => { llamadas++; return route.abort() })
  await loginReal(page); await irAMiCartera(page)
  const dialogo = await abrirReemplazo(page, '2026-01-999996')
  await expect(dialogo.getByRole('alert')).toContainText('ya tiene cuotas pagadas')
  await dialogo.getByLabel('Motivo del reemplazo').fill('Error de carga')
  await expect(dialogo.getByRole('button', { name: 'Reemplazar inversión', exact: true })).toBeDisabled()
  await dialogo.getByRole('button', { name: 'Quedarme con la otra' }).click()
  await expect(dialogo.getByRole('alert')).toContainText('ya tiene cuotas pagadas')
  expect(llamadas).toBe(0)
})

for (const [rolCrm, rolPortal, esVenta, visible] of [
  ['vendedor', 'analista', false, false],     // analista: no
  ['gerencia', 'analista', false, false],     // Gerencia sin admin del portal: no (Avance la reemplaza un admin)
  ['vendedor', 'admin', true, false],         // admin sin Gerencia, venta de un lead: no
  ['vendedor', 'admin', false, true],         // admin sin Gerencia, inversión sin venta: sí
] as const) test(`«Reemplazar inversión» ${visible ? 'se ofrece' : 'no se ofrece'} a ${rolCrm}/${rolPortal}${esVenta ? ' en la venta de un lead' : ''}`, async ({ page }) => {
  await montarBackendReal(page, { rolCrm, rolPortal, contratos: [] })
  await fichaCon(page, [inversion(ORIGINAL, '2026-01-999999', esVenta ? { es_inicial: true } : {})])
  await loginReal(page); await irAMiCartera(page)
  await page.getByRole('button', { name: 'Abrir ficha de ANA SINTÉTICA F5' }).click()
  await expect(page.getByText('2026-01-999999').first()).toBeVisible()
  await expect(page.getByRole('button', { name: 'Reemplazar inversión 2026-01-999999' })).toHaveCount(visible ? 1 : 0)
})
