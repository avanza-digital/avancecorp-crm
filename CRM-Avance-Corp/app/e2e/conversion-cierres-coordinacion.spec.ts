import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'
import { irAModulo } from './_navegacion'

const analista = '20000000-0000-4000-8000-000000000001'
const cifras = {
  divisor: 56, divisor_formulario: 22, divisor_landing: 34, numerador: 2, conversion_pct: 3.57,
  numerador_bruto: 2, ajuste_pendiente: 0, desglose_disponible: true,
  cierres: { formulario: 1, landing: 0, base_cargada: 0, referido: 1, referido_aporte: 1, oficina: 0, otros: 0 },
  cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
}
const resumen = {
  version: 1, generado_en: '2026-10-12T15:00:00Z', alcance: 'global',
  periodo: { modo: 'mes', mes: '2026-10', mes_nombre: 'octubre', anio: 2026, zona: 'America/Lima', desde: '2026-10-01', hasta: '2026-10-31', dias: 31, cruza_meses_sellados: false },
  sellado: false, peso_referido: 1, peso_renovacion: 0.15, tope_referidos_pct: 25,
  fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead', modo: 'mensual' },
  empresa: cifras, sin_analista: null,
  analistas: [{ ...cifras, analista_id: analista, nombre: 'ANA TORRES', supervisor_id: null, supervisor_nombre: null, en_nucleo: true }],
}

async function entrar(page: Parameters<typeof loginReal>[0]) {
  await montarBackendReal(page, { rolCrm: 'coordinador', rolPortal: 'comercial', conversionCoordinacion: resumen })
  await loginReal(page)
  await irAModulo(page, 'Repartir leads')
  await page.getByRole('tab', { name: 'Conversiones', exact: true }).click()
  await page.getByLabel('Mes de conversión').fill('2026-10')
  await expect(page.getByRole('button', { name: 'Ver cierres de ANA TORRES' })).toBeVisible()
}

const detalle = {
  version: 1, analista_id: analista, desde: '2026-10-01', hasta: '2026-10-31', disponible: true,
  total: 2, pagina: 0, por_pagina: 20,
  filas: [
    { nombre: 'CLIENTE FORMULARIO', origen: 'formulario', fecha: '2026-10-07', registro: 'sistema', aporte: 1 },
    { nombre: 'CLIENTE REFERIDO MANUAL', origen: 'referido', fecha: '2026-10-01', registro: 'manual', aporte: 1 },
  ],
}

test('coordinadora abre los cierres con teclado y vuelve a la misma fila', async ({ page }) => {
  await entrar(page)
  let pedido: unknown
  await page.route('**/rest/v1/rpc/conversion_cierres_coordinacion_fn', (route) => {
    pedido = route.request().postDataJSON()
    return route.fulfill({ json: detalle })
  })
  const boton = page.getByRole('button', { name: 'Ver cierres de ANA TORRES' })
  await boton.focus()
  await page.keyboard.press('Enter')
  const panel = page.getByRole('dialog', { name: 'Cierres de ANA TORRES' })
  await expect(panel.getByText('CLIENTE REFERIDO MANUAL')).toBeVisible()
  await expect(panel.getByText('Registro manual')).toBeVisible()
  await expect(panel.getByText('Referido · 01/10/2026')).toBeVisible()
  await expect(panel.getByText('CLIENTE FORMULARIO')).toBeVisible()
  await expect(panel.getByRole('link')).toHaveCount(0)
  expect(pedido).toEqual({ p_analista: analista, p_periodo: '2026-10-01', p_pagina: 0 })
  await expect(panel.getByRole('button', { name: 'Cerrar detalle de cierres' })).toBeFocused()
  await page.screenshot({ path: 'artifacts/conversion-cierres-coordinacion.png' })
  await page.keyboard.press('Escape')
  await expect(panel).not.toBeVisible()
  await expect(boton).toBeFocused()
})

test('un fallo de permisos no muestra nombres ni impide cerrar o reintentar', async ({ page }) => {
  await entrar(page)
  let falla = true
  await page.route('**/rest/v1/rpc/conversion_cierres_coordinacion_fn', (route) => route.fulfill(falla
    ? { status: 403, json: { code: '42501', message: 'detalle interno que no debe verse' } }
    : { json: detalle }))
  await page.getByRole('button', { name: 'Ver cierres de ANA TORRES' }).click()
  await expect(page.getByText('No tienes permiso para consultar los cierres.').last()).toBeVisible()
  await expect(page.getByText('CLIENTE REFERIDO MANUAL')).toHaveCount(0)
  await expect(page.getByText('detalle interno que no debe verse')).toHaveCount(0)
  falla = false
  await page.getByRole('button', { name: 'Reintentar' }).click()
  await expect(page.getByText('CLIENTE REFERIDO MANUAL')).toBeVisible()
  await page.getByRole('button', { name: 'Cerrar detalle de cierres' }).click()
  await expect(page.getByRole('button', { name: 'Ver cierres de ANA TORRES' })).toBeFocused()
})
