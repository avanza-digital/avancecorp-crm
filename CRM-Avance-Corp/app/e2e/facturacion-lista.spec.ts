// Fase 4: sesión real interceptada. Ejecutar exclusivamente con test:e2e:docker por el PRIMARY.
import { expect, test, type Page } from '@playwright/test'
import { loginReal, montarBackendReal, UID } from './_helpers'
import type { OperacionFacturacion, ParametrosOperacionesFacturacion } from '../src/data/crm-api'

const ANA = 'b0000000-0000-4000-8000-000000000001'
const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
const operaciones: OperacionFacturacion[] = Array.from({ length: 27 }, (_, i) => ({
  n: i + 1, fecha: '2026-10-05', tipo: 'contrato_nuevo', moneda: 'PEN', monto: 1000, anulado: i === 2,
  analista_id: ANA, analista_nombre: 'ANA PRUEBA', supervisor_id: UID, supervisor_nombre: 'Gerente Real',
  visible: true, cliente_nombre: `Cliente ejemplo ${i + 1}`, estado: i === 2 ? 'anulado' : 'vigente',
  contrato_id: `c0000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`, numero_contrato: `2026-10-${String(i + 1).padStart(6, '0')}`, cliente_id: null,
}))
const agregado = { dia: '2026-10-05', tipo: 'contrato_nuevo', moneda: 'PEN', operaciones: 27, capital: 27000,
  analista_id: ANA, analista_nombre: 'ANA PRUEBA', supervisor_id: UID, supervisor_nombre: 'Gerente Real' }

async function montar(page: Page, estado: 'normal' | 'ajeno' | 'vacio' | 'error' = 'normal') {
  const pedidos: ParametrosOperacionesFacturacion[] = []
  await page.clock.setFixedTime(new Date('2026-10-09T15:00:00Z'))
  await montarBackendReal(page, estado === 'ajeno' ? { rolCrm: 'supervisor' } : {})
  await page.route('**/rest/v1/rpc/facturacion_diaria_fn', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    const args = route.request().postDataJSON()
    return route.fulfill({ headers: CORS, json: args.p_mes === '2026-10-01' && estado !== 'vacio' ? [agregado] : [] })
  })
  await page.route('**/rest/v1/rpc/listar_operaciones_facturacion_fn', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    const p: ParametrosOperacionesFacturacion = route.request().postDataJSON()
    pedidos.push(p)
    if (estado === 'error') return route.fulfill({ status: 500, headers: CORS, json: { code: 'XX000', message: 'Servidor no disponible' } })
    const filas = estado === 'vacio' ? [] : operaciones.filter((f) => f.fecha >= p.p_desde && f.fecha <= p.p_hasta &&
      (!p.p_dias || p.p_dias.includes(f.fecha)) && (!p.p_analistas || p.p_analistas.includes(f.analista_id!)) &&
      (!p.p_equipo || f.supervisor_id === p.p_equipo) && (!p.p_moneda || f.moneda === p.p_moneda) && (!p.p_tipos || p.p_tipos.includes(f.tipo)))
    const pagina = p.p_pagina ?? 1; const tamano = p.p_tamano ?? 25
    return route.fulfill({ headers: CORS, json: { version: 1, pagina, tamano, total: filas.length,
      totales: filas.length ? [{ moneda: 'PEN', operaciones: filas.length, monto: filas.length * 1000 }] : [],
      filas: filas.slice((pagina - 1) * tamano, pagina * tamano).map((f) => estado === 'ajeno'
        ? { n: f.n, fecha: f.fecha, tipo: f.tipo, moneda: f.moneda, monto: f.monto, anulado: f.anulado,
          analista_id: f.analista_id, analista_nombre: f.analista_nombre, supervisor_id: f.supervisor_id,
          supervisor_nombre: f.supervisor_nombre, visible: false, cliente_nombre: 'Cliente de otro equipo' } : f) } })
  })
  await loginReal(page, { esperarWorkspace: false })
  await expect(page).toHaveURL(/#\/[\w-]+/)
  await page.evaluate(() => { window.location.hash = '#/facturacion' })
  await expect(page.getByRole('region', { name: 'Resumen de lo que estás viendo' })).toBeVisible()
  return pedidos
}

test('una celda abre sus operaciones, suma exacta entre páginas, foco, Esc y fondo usable', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  const pedidos = await montar(page)
  const malla = page.getByRole('region', { name: /Facturación diaria/ })
  const celda = malla.getByRole('button', { name: /^ANA PRUEBA, lunes, 5 de octubre: S\/ 27,000, ver 27 operaciones$/ })
  await celda.click()
  // La clase identifica la misma sección al pasar de región a diálogo por el ancho.
  const panel = page.locator('.lista-operaciones')
  await expect(panel).not.toHaveAttribute('aria-modal')
  await expect(panel.getByRole('heading', { level: 2 })).toBeFocused()
  const cajaPanel = await panel.boundingBox()
  expect(cajaPanel?.y).toBe(64)
  const buscador = page.getByRole('combobox', { name: 'Buscar lead por nombre, teléfono o DNI' })
  await buscador.click()
  await expect(buscador).toBeFocused()
  await expect(panel).toBeVisible()
  // La hoja empieza debajo de la franja operable del topbar.
  expect(await page.evaluate(() => document.elementFromPoint(innerWidth - 24, 32)?.closest('.lista-operaciones') == null)).toBe(true)
  await expect(panel).toContainText('Cuadra. Pulsaste S/ 27,000')
  await expect(panel).toContainText('Mostrando 1–25 de 27')
  const importes = () => panel.locator('tbody .lista-col-7').allTextContents()
  const sumar = (xs: string[]) => xs.reduce((s, v) => s + Number(v.replace(/[^0-9.]/g, '')), 0)
  let suma = sumar(await importes())
  await panel.getByRole('button', { name: 'Página siguiente', exact: true }).click()
  await expect(panel).toContainText('Mostrando 26–27 de 27')
  suma += sumar(await importes())
  expect(suma).toBe(27000)
  // El mock hace eco de página y filtros: se exige el cuerpo completo, no solo el resultado.
  const alcance = { p_desde: '2026-10-05', p_hasta: '2026-10-05', p_analistas: [ANA], p_equipo: UID, p_pagina: 1, p_tamano: 25 }
  expect(pedidos[0]).toEqual(alcance)
  expect(pedidos.at(-1)).toEqual({ ...alcance, p_pagina: 2 })
  await panel.getByRole('button', { name: '50 filas por página' }).click()
  await expect(panel).toContainText('Mostrando 1–27 de 27')
  expect(pedidos.at(-1)).toEqual({ ...alcance, p_tamano: 50 })
  // La región de fondo mantiene foco y responde con el inspector abierto.
  const dia = malla.getByRole('button', { name: 'Marcar el miércoles, 7 de octubre' })
  await dia.focus(); await page.keyboard.press('Enter')
  await expect(dia).toHaveAttribute('aria-pressed', 'true')
  await expect(panel).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(panel).toHaveCount(0); await expect(celda).toBeFocused()
})

test('días sueltos viajan como p_dias y el cero también se abre', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  const pedidos = await montar(page)
  const malla = page.getByRole('region', { name: /Facturación diaria/ })
  await malla.getByRole('button', { name: 'Marcar el lunes, 5 de octubre' }).click()
  await malla.getByRole('button', { name: 'Marcar el miércoles, 7 de octubre' }).click()
  await malla.getByRole('button', { name: 'Ver los días elegidos de ANA PRUEBA: total S/ 27,000, ver 27 operaciones' }).click()
  await expect(page.locator('.lista-operaciones')).toContainText('Cuadra.')
  expect(pedidos.at(-1)).toEqual({ p_desde: '2026-10-05', p_hasta: '2026-10-07', p_dias: ['2026-10-05', '2026-10-07'], p_analistas: [ANA], p_equipo: UID, p_pagina: 1, p_tamano: 25 })
  await page.keyboard.press('Escape')
  await malla.getByRole('button', { name: /^ANA PRUEBA, martes, 6 de octubre: S\/ 0, sin operaciones, abrir$/ }).click()
  await expect(page.locator('.lista-operaciones')).toContainText('Sin operaciones en este número')
  expect(pedidos.at(-1)).toMatchObject({ p_desde: '2026-10-06', p_hasta: '2026-10-06' })
  expect(pedidos.at(-1)).not.toHaveProperty('p_dias')
})

test.describe('hoja modal en ventana estrecha sin pantalla táctil', () => {
  test.use({ hasTouch: false })
  test('a 1100×800 mantiene la tabla, bloquea el fondo y Esc devuelve el foco', async ({ page }) => {
    await page.setViewportSize({ width: 1100, height: 800 })
    await montar(page)
    const fijarMenu = page.getByRole('button', { name: 'Fijar menú abierto' })
    if (await fijarMenu.isVisible()) await fijarMenu.click()
    await expect(page.getByRole('button', { name: 'Ocultar menú' })).toHaveAttribute('aria-expanded', 'true')
    const malla = page.getByRole('region', { name: /Facturación diaria/ })
    const celda = malla.getByRole('button', { name: /^ANA PRUEBA, lunes, 5 de octubre: S\/ 27,000, ver 27 operaciones$/ })
    // La malla SIEMPRE reserva su columna fija de totales; la hoja modal no debe sumarle su solape.
    const reservaPropia = await malla.evaluate((n) => getComputedStyle(n).scrollPaddingRight)
    await celda.click()
    const panel = page.locator('.lista-operaciones')
    await expect(panel).toHaveAttribute('role', 'dialog')
    await expect(panel).toHaveAttribute('aria-modal', 'true')
    await expect(panel.getByRole('table')).toBeVisible()
    await expect(panel.getByRole('list')).toHaveCount(0)
    await expect(page.locator('#app-content')).toHaveAttribute('inert', '')
    await expect(page.locator('#root')).not.toHaveAttribute('inert')
    await expect(page.locator('[data-sonner-toaster]').locator('xpath=ancestor-or-self::*[@inert]')).toHaveCount(0)
    await expect(page.locator('.facturacion-pantalla')).toHaveCSS('padding-right', '0px')
    await expect(malla).toHaveCSS('scroll-padding-right', reservaPropia)
    expect(await malla.evaluate((n) => n.style.getPropertyValue('--lista-solape'))).toBe('')
    await expect(panel.getByRole('heading', { level: 2 })).toBeFocused()
    await page.keyboard.press('Escape')
    await expect(panel).toHaveCount(0)
    await expect(page.locator('#app-content')).not.toHaveAttribute('inert')
    await expect(celda).toBeFocused()
  })
})

test('celular: pantalla completa con tarjetas y fila de otro equipo sin referencias', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await montar(page, 'ajeno')
  await page.getByRole('region', { name: 'Facturación por analista' }).getByRole('button', { name: /^ANA PRUEBA, lunes, 5 de octubre/ }).click()
  const panel = page.getByRole('dialog')
  await expect(panel.getByRole('list')).toBeVisible()
  await expect(panel.getByRole('table')).toHaveCount(0)
  await expect(panel.getByRole('listitem')).toHaveCount(25)
  await expect(panel.getByRole('listitem').first()).toContainText('Cliente de otro equipo')
  await expect(panel).not.toContainText('2026-10-000001')
  const caja = await panel.boundingBox()
  expect(caja?.width).toBe(390); expect(caja?.height).toBe(844)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await panel.getByRole('button', { name: 'Cerrar detalle' }).click()
  await expect(panel).toHaveCount(0)
})

for (const estado of ['vacio', 'error'] as const) test(`realidad: ${estado === 'vacio' ? 'mes vacío' : 'servidor caído con reintento'}`, async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await montar(page, estado)
  await page.getByRole('region', { name: 'Resumen de lo que estás viendo' }).getByRole('button', { name: /^Facturado:/ }).click()
  const panel = page.locator('.lista-operaciones')
  if (estado === 'vacio') await expect(panel).toContainText('Sin operaciones en este número')
  else {
    await expect(panel).toContainText('No se pudo cargar la lista de operaciones')
    await expect(panel.getByRole('button', { name: /Reintentar/ })).toBeVisible()
    await expect(panel).not.toContainText('Sin operaciones en este número')
  }
})

test('Gerencia en celular: el modal ocupa los 844 px completos y deja el fondo inerte', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await montar(page)
  await expect(page.locator('[data-gerencia-movil="true"]')).toBeVisible()
  await page.getByRole('region', { name: 'Facturación por analista' }).getByRole('button', { name: /^ANA PRUEBA, lunes, 5 de octubre/ }).click()
  const panel = page.getByRole('dialog')
  await expect(panel).toHaveAttribute('aria-modal', 'true')
  await expect(page.locator('#app-content')).toHaveAttribute('inert', '')
  await expect.poll(async () => {
    const caja = await panel.boundingBox()
    return caja && { y: caja.y, ancho: caja.width, alto: caja.height }
  }).toEqual({ y: 0, ancho: 390, alto: 844 })
  await panel.getByRole('button', { name: 'Página siguiente' }).click()
  await expect(panel.getByRole('listitem').first()).toBeFocused()
  await expect(panel.getByRole('listitem').first()).toBeInViewport()
  await page.keyboard.press('Escape')
  await expect(panel).toHaveCount(0)
  await expect(page.locator('#app-content')).not.toHaveAttribute('inert')
})
