import { expect, test, type Page } from '@playwright/test'
import { loginReal, montarBackendReal, leadReal, UID } from './_helpers'
import fixture from '../src/lib/gestion-diaria-f5.test.fixture.json' with { type: 'json' }

// Transporte interceptado sobre respuestas SQL sintéticas reales. No prueba
// por sí solo Auth/RLS: las 18 solicitudes PostgREST del banco cubren esa capa.
const DIA = '2026-09-23'
const grupo = fixture.pulso.equipos.find((e) => e.metricas.llamadas === 4)!
const analista = grupo.personas.find((p) => p.activo && p.llamadas === 4)!
const cliente = leadReal({ vendedor_id: analista.analista_id!, nombre_completo: 'CLIENTE FICTICIO F5' })
function moverFechas<T>(foto: T, dia: string): T {
  const diferencia = Date.parse(`${dia}T00:00:00Z`) - Date.parse(`${DIA}T00:00:00Z`)
  return JSON.parse(JSON.stringify(foto), (clave, valor) => {
    if (typeof valor !== 'string' || !/^\d{4}-\d{2}-\d{2}(T|$)/.test(valor) || ['generado_en', 'pendientes_al'].includes(clave)) return valor
    const nueva = new Date(Date.parse(`${valor.slice(0, 10)}T00:00:00Z`) + diferencia).toISOString().slice(0, 10)
    return nueva + valor.slice(10)
  })
}
async function montar(page: Page) {
  await page.setViewportSize({ width: 1512, height: 900 })
  await page.clock.setFixedTime(new Date('2026-09-24T21:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'gerencia', leads: [cliente], tareas: [] })
  await page.addInitScript(({ actor, dia }) => {
    const clave = `avancecorp:gestion-diaria:f5:dia:${actor}`
    if (sessionStorage.getItem(clave) === null) sessionStorage.setItem(clave, dia)
  }, { actor: UID, dia: DIA })
  const estado = { error: false, revocado: false, dias: [] as string[], periodos: [] as number[], registros: [] as Record<string, unknown>[] }
  await page.route('**/rest/v1/rpc/gestion_diaria_pulso_fn', async (route) => {
    const { p_dia } = route.request().postDataJSON(); estado.dias.push(p_dia)
    if (estado.revocado) return route.fulfill({ status: 403, json: { code: '42501', message: 'Acceso revocado' } })
    if (estado.error) return route.fulfill({ status: 400, json: { code: 'XX000', message: 'Fallo controlado' } })
    return route.fulfill({ json: moverFechas(fixture.pulso, p_dia) })
  })
  await page.route('**/rest/v1/rpc/gestion_diaria_habitos_fn', async (route) => {
    const { p_hasta, p_dias } = route.request().postDataJSON(); estado.periodos.push(p_dias)
    return route.fulfill({ json: moverFechas(p_dias === 7 ? fixture.habitos : p_dias === 14 ? fixture.habitos14 : fixture.habitos30, p_hasta) })
  })
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', async (route) => {
    const pedido = route.request().postDataJSON()
    expect(pedido.p_supervisor_id).toBeUndefined()
    return route.fulfill({ json: moverFechas(fixture.equipo, pedido.p_dia) })
  })
  await page.route('**/rest/v1/rpc/registro_actividad_fn', async (route) => {
    const pedido = route.request().postDataJSON(); estado.registros.push(pedido)
    const items = pedido.p_analista_ids && !pedido.p_analista_ids.includes(analista.analista_id) ? [] : [{
      id: '11111111-2222-4333-8444-555555555555', lead_id: cliente.id, lead_nombre: cliente.nombre_completo,
      lead_etapa: 'nuevo', etapa_en_ese_momento: 'nuevo', tipo: 'llamada_realizada', detalle: `Llamada ficticia F5 del ${pedido.p_desde}`,
      metadata: { resultado: 'interesado' }, creado_por: analista.analista_id, autor_nombre: analista.nombre_completo,
      creado_en: `${pedido.p_desde}T15:00:00.000Z`,
    }]
    return route.fulfill({ json: { version: 1, zona: 'America/Lima', desde: pedido.p_desde, hasta: pedido.p_hasta,
      generado_en: fixture.pulso.generado_en, limite: pedido.p_limite, items } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Resumen por supervisor' })).toBeVisible()
  return estado
}

test('F5 escritorio: operación, equipo, analista, registro, ficha y vuelta con contexto', async ({ page }, info) => {
  const estado = await montar(page)
  const vista = page.getByRole('region', { name: 'Toda la operación', exact: true })
  await expect(vista).toContainText('1008 tareas vencidas en total')
  await expect(vista).toContainText('promedio de 7 de 7 días con actividad')
  await page.screenshot({ path: info.outputPath('f5-operacion-escritorio.png'), fullPage: true })
  const enlaceEquipo = vista.getByRole('link', { name: grupo.nombre, exact: true })
  await enlaceEquipo.focus()
  await enlaceEquipo.press('Enter')
  await expect(page).toHaveURL(new RegExp(`/gestion-diaria/equipo/${grupo.clave}$`))
  const detalle = vista.getByRole('region', { name: 'Detalle de la operación' })
  await expect(detalle.getByRole('heading', { name: grupo.nombre, exact: true })).toBeFocused()
  await detalle.getByRole('heading', { name: grupo.nombre, exact: true }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath('f5-equipo-escritorio.png'), fullPage: true })
  await detalle.getByRole('button', { name: `Seleccionar a ${analista.nombre_completo}`, exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/gestion-diaria/analista/${analista.analista_id}$`))
  await expect(detalle.getByRole('heading', { name: analista.nombre_completo!, exact: true })).toBeFocused()
  await expect(detalle).toContainText(`Llamada ficticia F5 del ${DIA}`)
  expect(estado.registros.some((r) => r.p_desde === DIA && JSON.stringify(r.p_analista_ids) === JSON.stringify([analista.analista_id]))).toBe(true)
  await detalle.getByRole('button', { name: cliente.nombre_completo, exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/analista/${analista.analista_id}/lead/${cliente.id}$`))
  await expect(page.getByRole('heading', { name: cliente.nombre_completo, exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/analista/${analista.analista_id}$`))
  await expect(page.getByLabel('Día de la operación', { exact: true })).toHaveValue(DIA)
  await expect(detalle).toContainText(`Llamada ficticia F5 del ${DIA}`)
  await page.goBack()
  await expect(page.getByRole('heading', { name: cliente.nombre_completo, exact: true })).toBeVisible()
  await page.goForward()
  await expect(detalle).toBeVisible()
  await page.screenshot({ path: info.outputPath('f5-analista-escritorio.png'), fullPage: true })
})

test('F5 móvil: fecha, recarga y enlace directo sin desbordamiento', async ({ page }, info) => {
  const estado = await montar(page)
  await page.setViewportSize({ width: 390, height: 844 })
  await page.mouse.move(380, 80)
  const dia = page.getByLabel('Día de la operación', { exact: true })
  await dia.fill('2026-09-22')
  await dia.press('Enter')
  await expect(page.getByRole('region', { name: 'Indicadores de la operación' })).toContainText('2026-09-21 completo')
  await expect.poll(() => estado.dias.at(-1)).toBe('2026-09-22')
  await page.getByRole('link', { name: grupo.nombre, exact: true }).click()
  await page.reload()
  await expect(page.getByLabel('Día de la operación', { exact: true })).toHaveValue('2026-09-22')
  await expect(page).toHaveURL(new RegExp(`/equipo/${grupo.clave}$`))
  const detalle = page.getByRole('region', { name: 'Detalle de la operación' })
  await expect(detalle).toBeVisible()
  await dia.fill('2026-09-21')
  await dia.press('Enter')
  await expect.poll(() => estado.dias.at(-1)).toBe('2026-09-21')
  await expect(detalle).toContainText(grupo.nombre)
  await expect(dia).toBeFocused()
  await detalle.getByRole('heading', { name: grupo.nombre, exact: true }).scrollIntoViewIfNeeded()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: info.outputPath('f5-equipo-movil.png'), fullPage: true })
  await page.getByRole('region', { name: 'Detalle de la operación' }).getByRole('link', { name: 'Toda la operación', exact: true }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria$/)
  await page.getByRole('heading', { name: '¿Qué está pasando en la operación?', exact: true }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath('f5-operacion-movil.png'), fullPage: true })
})

test('F5 hábitos: períodos reales de 7/14/30, hueco, comparación y cortes sin activar umbral', async ({ page }, info) => {
  const estado = await montar(page)
  await page.getByRole('tab', { name: 'Hábitos del equipo', exact: true }).click()
  const informe = page.getByRole('region', { name: 'Reporte de hábitos', exact: true })
  await expect(informe).toContainText('14 días calendario')
  await page.getByLabel(`Período hasta ${DIA}`, { exact: true }).selectOption('7')
  await expect(informe).toContainText('7 días calendario')
  await informe.getByText(`Ver días de ${analista.nombre_completo}`, { exact: true }).click()
  await expect(informe.getByRole('table', { name: `Hábitos diarios de ${analista.nombre_completo}` })).toContainText('165 min')
  await expect(informe).toContainText('La alerta de tasa muy baja sigue apagada')
  await page.screenshot({ path: info.outputPath('f5-habitos.png'), fullPage: true })
  await informe.getByRole('table', { name: `Hábitos diarios de ${analista.nombre_completo}` }).getByRole('row', { name: new RegExp(DIA) }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath('f5-habitos-hueco.png'), fullPage: true })
  await page.getByLabel(`Período hasta ${DIA}`, { exact: true }).selectOption('30')
  await expect(informe).toContainText('30 días calendario')
  expect(estado.periodos).toEqual(expect.arrayContaining([7, 14, 30]))
  await informe.getByRole('link', { name: analista.nombre_completo!, exact: true }).click()
  await expect(page.getByRole('region', { name: 'Detalle de la operación' })).toContainText(analista.nombre_completo!)
})

test('F5 error y revocación ocultan datos; recuperación vuelve a consultar', async ({ page }) => {
  const estado = await montar(page)
  estado.error = true
  await page.getByRole('button', { name: 'Actualizar operación', exact: true }).click()
  const alerta = page.getByRole('region', { name: 'Toda la operación' }).getByRole('alert')
  await expect(alerta).toContainText('datos anteriores se han ocultado')
  await expect(page.getByRole('table', { name: 'Resumen por supervisor' })).toHaveCount(0)
  await expect(page.getByRole('region', { name: 'Registro general de la operación' })).toHaveCount(0)
  estado.error = false
  await alerta.getByRole('button', { name: 'Reintentar', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Resumen por supervisor' })).toBeVisible()
  estado.revocado = true
  await page.getByRole('button', { name: 'Actualizar operación', exact: true }).click()
  await expect(alerta).toContainText('ya no tiene permiso')
  await expect(page.getByRole('table')).toHaveCount(0)
})

test('F5 conserva la fila fuera de equipos y exportación del registro cargado', async ({ page }) => {
  await montar(page)
  await page.getByRole('link', { name: 'Fuera de equipos comerciales', exact: true }).click()
  const detalle = page.getByRole('region', { name: 'Detalle de la operación' })
  await expect(detalle).toContainText('Sin autor: 1 llamadas')
  await expect(detalle).toContainText('Los registros sin autor se consultan en el registro general')
  const general = page.getByRole('region', { name: 'Registro general de la operación' })
  await expect(general).toContainText(`Llamada ficticia F5 del ${DIA}`)
  const descarga = page.waitForEvent('download')
  await general.getByRole('button', { name: /Exportar/ }).click()
  expect((await descarga).suggestedFilename()).toContain(DIA)
})
