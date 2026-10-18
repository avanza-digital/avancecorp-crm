// Dirección de la jornada integrada al CRM: sesión real simulada, sin metas.
import { expect, test, type Page } from '@playwright/test'
import { loginReal, UID } from './_helpers'
import { montarColaEquipo } from './_sla-cola'
import { montarLecturasHoySupervisor } from './_hoy-supervisor'
import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'
import { fechaLima } from '../src/lib/agenda-derivada'

async function montarJornada(page: Page) {
  const { analistaUno, analistaDos } = await montarColaEquipo(page, 'supervisor')
  await montarLecturasHoySupervisor(page)
  const hoy = fechaLima(Date.now())
  const base = filaEquipoPrueba()
  const filas = [
    filaEquipoPrueba({ analista_id: analistaUno, nombre_completo: 'Analista Norte Uno',
      marcador: { ...base.marcador, llamadas: 12, utiles: 10, contestadas: 5, tasa_contacto_pct: 50, nivel: 'bien' },
      gestiones_hoy: 12, tareas_pendientes: 7, tareas_vencidas: 4, primer_intento_vencido: 2,
      requiere_atencion: true, motivos_atencion: ['tarea_vencida', 'primer_intento_vencido'] }),
    filaEquipoPrueba({ analista_id: analistaDos, nombre_completo: 'Analista Norte Dos',
      marcador: { ...base.marcador, llamadas: 90, utiles: 90, contestadas: 9, tasa_contacto_pct: 10, nivel: 'bajo' }, gestiones_hoy: 90 }),
  ]
  const dia = { ...diaEquipoPrueba(filas), dia: hoy, supervisor_id: UID, generado_en: new Date().toISOString() }
  let caido = false
  const pedidos: unknown[] = []
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', async route => {
    pedidos.push(route.request().postDataJSON())
    await route.fulfill({ status: caido ? 403 : 200, json: caido ? { code: '42501', message: 'Sin permiso' } : dia })
  })
  return { pedidos, hoy, caer: () => { caido = true } }
}

test('supervisor: resultado visible, tasas de contacto, tabla y detalle con teclado', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const { pedidos, hoy } = await montarJornada(page)
  const errores: string[] = []
  page.on('pageerror', error => errores.push(error.message))
  await loginReal(page)
  await expect(page.getByRole('heading', { name: 'Dirección de la jornada' })).toBeVisible()
  const contacto = page.getByRole('region', { name: 'Llamadas de hoy', exact: true })
  await expect(contacto).toContainText('102')
  await expect(contacto).toContainText('14.00%')
  await expect(contacto).toContainText('14 contestadas / 100 útiles')
  await expect(page.getByRole('region', { name: 'Resultados de hoy', exact: true })
    .getByRole('button', { name: '0 operaciones cerradas', exact: true })).toBeVisible()
  expect(pedidos.at(-1)).toMatchObject({ p_dia: hoy, p_supervisor_id: UID })
  await expect(page.getByRole('link', { name: /Ver citas del equipo/ })).toHaveAttribute('href', `#/reuniones/dia/${hoy}`)
  const pendientes = page.getByRole('button', { name: 'Ver pendientes', exact: true })
  await pendientes.click()
  const tareas = page.getByRole('dialog', { name: 'Pendientes del equipo', exact: true })
  await expect(tareas.getByRole('button', { name: 'Ver tareas de Analista Norte Uno', exact: true })).toBeVisible()
  await expect(tareas.getByRole('row', { name: /Total del equipo/ })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(pendientes).toBeFocused()
  await page.screenshot({ path: test.info().outputPath('jornada-supervisor-escritorio.png'), fullPage: true, animations: 'disabled' })

  const abrir = page.getByRole('button', { name: 'Ver día de Analista Norte Uno', exact: true })
  await abrir.focus(); await page.keyboard.press('Enter')
  await expect(page.getByRole('dialog', { name: 'Detalle de Analista Norte Uno', exact: true })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(abrir).toBeFocused()
  await page.getByRole('checkbox', { name: /Solo quienes necesitan apoyo/ }).check()
  await expect(page.getByRole('button', { name: 'Ver día de Analista Norte Dos', exact: true })).toHaveCount(0)
  await page.getByRole('tab', { name: 'Gestión de hoy', exact: true }).focus()
  await page.keyboard.press('ArrowRight')
  await expect(page.getByRole('tab', { name: 'Resultado del mes', exact: true })).toBeFocused()
  await expect(page.getByRole('link', { name: 'Ver Facturación', exact: true })).toBeVisible()
  await expect(page.locator('main')).not.toContainText(/Cómo leer las cifras|Si faltan datos/)
  expect(errores).toEqual([])
})

test('supervisor: los errores de refresco retiran cifras y detalle anteriores', async ({ page }) => {
  const { caer } = await montarJornada(page)
  await loginReal(page)
  await expect(page.getByRole('button', { name: 'Ver día de Analista Norte Uno' })).toBeVisible()
  caer()
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(page.getByRole('region', { name: 'Llamadas de hoy', exact: true })).toContainText('Actividad de hoy no disponible')
  await expect(page.getByRole('button', { name: 'Ver día de Analista Norte Uno' })).toHaveCount(0)
  await expect(page.getByRole('region', { name: 'Llamadas de hoy', exact: true })).not.toContainText('14 contestadas')
})

test('supervisor: móvil sin desborde y acceso a la tabla del mes', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await montarJornada(page)
  await loginReal(page, { esperarWorkspace: false })
  await expect(page.getByRole('heading', { name: 'Dirección de la jornada' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Ver día de Analista Norte Uno' })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(0)
  await page.getByRole('tab', { name: 'Resultado del mes', exact: true }).click()
  await expect(page.getByRole('tab', { name: 'Resultado del mes', exact: true })).toHaveAttribute('aria-selected', 'true')
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(0)
  await page.screenshot({ path: test.info().outputPath('jornada-supervisor-movil.png'), fullPage: true, animations: 'disabled' })
})
