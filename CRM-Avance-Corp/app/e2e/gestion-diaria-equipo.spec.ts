import { expect, test } from '@playwright/test'
import { entrarDemo, loginReal, montarBackendReal, UID } from './_helpers'
import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'
import { fechaLima } from '../src/lib/agenda-derivada'

test('Supervisor: roster demo, búsqueda y detalle con texto de al menos 16 px', async ({ page }, info) => {
  await entrarDemo(page, 'Supervisor')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  const tabla = vista.getByRole('table')
  await expect(tabla).toBeVisible()
  const analistas = tabla.locator('tr[data-analista]')
  expect(await analistas.count()).toBeGreaterThan(0)
  const nombre = (await analistas.first().getByRole('rowheader').locator('p').first().textContent())!
  await vista.getByRole('searchbox').fill(nombre)
  await expect(analistas).toHaveCount(1)
  await tabla.locator('summary').click()
  await expect(tabla.getByText('Llamadas por lead', { exact: true })).toBeVisible()
  const chicos = await vista.evaluate((raiz) => Array.from(raiz.querySelectorAll<HTMLElement>('*')).filter((el) =>
    el.getClientRects().length > 0 && Array.from(el.childNodes).some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim())
      && Number.parseFloat(getComputedStyle(el).fontSize) < 16).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
  expect(chicos).toEqual([])
  await page.evaluate(() => document.fonts.ready)
  expect(await page.evaluate(() => [...document.fonts].some((f) => f.family.includes('Jakarta') && f.status === 'loaded'))).toBe(true)
  const abrir = tabla.getByRole('button', { name: `Ver registro de ${nombre}` })
  await abrir.focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('heading', { name: `Registro de ${nombre}`, exact: true })).toBeFocused()
  await page.getByRole('button', { name: 'Cerrar registro', exact: true }).click()
  await expect(abrir).toBeFocused()
  await vista.getByRole('heading', { level: 2 }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath('equipo-escritorio.png'), fullPage: true })
  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await vista.getByRole('heading', { level: 2 }).scrollIntoViewIfNeeded()
  await expect(vista.getByRole('searchbox')).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: info.outputPath('equipo-movil.png'), fullPage: true })
})

test('Ruta real con store vacío: cero actividad, 270 pendientes, error y revocación', async ({ page }, info) => {
  await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
  const d = diaEquipoPrueba([filaEquipoPrueba(), filaEquipoPrueba({ analista_id: 'b', nombre_completo: 'BRUNO',
    tareas_pendientes: 270, tareas_vencidas: 270, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] })])
  d.dia = fechaLima(Date.now()); d.supervisor_id = UID
  d.generado_en = new Date().toISOString(); d.pendientes_al = d.generado_en
  let estado: 'ok' | 'error' | 'revocado' = 'ok'
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', async (route) => {
    expect(route.request().postDataJSON()).toEqual({ p_dia: d.dia, p_supervisor_id: UID })
    if (estado === 'error') return route.fulfill({ status: 400, json: { code: 'XX000', message: 'Error controlado de lectura' } })
    if (estado === 'revocado') return route.fulfill({ status: 403, json: { code: '42501', message: 'Acceso revocado' } })
    return route.fulfill({ json: d })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  await expect(vista.getByText('ANA PÉREZ', { exact: true })).toBeVisible()
  await expect(vista.getByText('270 tareas pendientes', { exact: true })).toBeVisible()
  await vista.getByRole('button', { name: /Con problema hoy/ }).click()
  await expect(vista.getByText('ANA PÉREZ', { exact: true })).toHaveCount(0)
  await expect(vista.getByText('BRUNO', { exact: true })).toBeVisible()
  await page.screenshot({ path: info.outputPath('equipo-ruta-real.png'), fullPage: true })
  estado = 'error'
  await vista.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(vista.getByRole('alert')).toContainText('no significa que el equipo no tenga actividad')
  await expect(vista.getByRole('table')).toHaveCount(0)
  estado = 'ok'
  await vista.getByRole('button', { name: 'Reintentar', exact: true }).click()
  await expect(vista.getByRole('table')).toBeVisible()
  estado = 'revocado'
  await vista.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(vista.getByRole('alert')).toContainText('Ya no tienes autorización')
  await expect(vista.getByRole('table')).toHaveCount(0)
})
