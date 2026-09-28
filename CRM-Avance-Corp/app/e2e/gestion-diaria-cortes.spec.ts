import { expect, test, type Page } from '@playwright/test'
import { writeFile } from 'node:fs/promises'
import { leadReal, loginReal, montarBackendReal, UID } from './_helpers'
import { idH4, jornadaH4 } from '../src/lib/gestion-diaria-h4.fixture'
import { fechaLima } from '../src/lib/agenda-derivada'

async function preparar(page: Page, popup = false) {
  await page.setViewportSize({ width: 1512, height: 805 })
  const dia = fechaLima(Date.now()), f = jornadaH4(dia, UID)
  await page.clock.install({ time: new Date(f.equipo.generado_en) })
  const lead = leadReal({ id: idH4(20), nombre_completo: 'LEAD DE CORTE H4', fueraDelBoot: true, asignado_supervisor_id: UID })
  await montarBackendReal(page, { rolCrm: 'supervisor', leads: [lead], tareas: [] })
  f.avisos.alertas[0]!.puede_presentar = popup
  const estado = { ...f, errorAvisos: null as string | null, errorEquipo: false, falloAccion: false,
    falloPopup: false, lecturas: 0, presentaciones: 0, acciones: [] as { p_accion: string; p_solicitud_id: string; p_alerta_id: string }[], registros: [] as Record<string, unknown>[] }
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', (r) => estado.errorEquipo
    ? r.fulfill({ status: 400, json: { code: 'XX000', message: 'Error de prueba' } }) : r.fulfill({ json: estado.equipo }))
  await page.route('**/rest/v1/rpc/gestion_diaria_avisos_fn', (r) => {
    estado.lecturas++
    return estado.errorAvisos ? r.fulfill({ status: 400, json: { code: estado.errorAvisos, message: 'Error de prueba' } }) : r.fulfill({ json: estado.avisos })
  })
  await page.route('**/rest/v1/rpc/gestion_diaria_presentar_corte', (r) => {
    estado.presentaciones++
    if (estado.falloPopup) return r.fulfill({ status: 400, json: { code: 'XX000', message: 'Fallo de presentación controlado' } })
    const pedido = r.request().postDataJSON(), aviso = estado.avisos.alertas[0]!
    aviso.puede_presentar = false
    return r.fulfill({ json: { version: 1, solicitud_id: pedido.p_solicitud_id, aviso } })
  })
  await page.route('**/rest/v1/rpc/gestion_diaria_reconocer_corte', (r) => {
    const pedido = r.request().postDataJSON(); estado.acciones.push(pedido)
    if (estado.falloAccion) { estado.falloAccion = false; return r.fulfill({ status: 400, json: { code: 'XX000', message: 'No se confirmó la acción de prueba.' } }) }
    const aviso = estado.avisos.alertas.find((a) => a.id === pedido.p_alerta_id)!
    aviso.estado = pedido.p_accion === 'posponer' ? 'pospuesto' : 'reconocido'
    aviso.puede_posponer = false; aviso.puede_presentar = false
    if (pedido.p_accion === 'posponer') aviso.pospuesto_hasta = `${dia}T13:00:00-05:00`
    else aviso.reconocido_en = estado.avisos.generado_en
    return r.fulfill({ json: estado.avisos })
  })
  await page.route('**/rest/v1/rpc/registro_actividad_fn', (r) => {
    estado.registros.push(r.request().postDataJSON())
    return r.fulfill({ json: { version: 1, zona: 'America/Lima', desde: dia, hasta: dia, limite: 26,
      generado_en: f.equipo.generado_en, items: [{ id: idH4(50), lead_id: lead.id, lead_nombre: lead.nombre_completo,
        lead_etapa: 'nuevo', etapa_en_ese_momento: 'nuevo', tipo: 'llamada_realizada', detalle: 'Llamada desde corte H4', metadata: {},
        creado_por: idH4(2), autor_nombre: 'ANA H4', creado_en: `${dia}T11:00:00-05:00` }] } })
  })
  // El popup puede abrirse antes de que el helper encuentre el menú; Radix
  // oculta correctamente ese fondo del árbol accesible mientras está abierto.
  await loginReal(page, { esperarWorkspace: !popup })
  if (popup) return { estado, lead }
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  await page.mouse.move(900, 90)
  await expect(page.locator('aside [data-splash-destino-visible]').first()).toHaveAttribute('data-splash-destino-visible', 'false')
  await expect(page.getByRole('region', { name: 'Estado de cortes y avisos' })).toContainText('11:30 Evaluado')
  return { estado, lead }
}
const abrirAvisos = (page: Page) => page.getByRole('button', { name: 'Cortes y avisos', exact: true }).click()
const dialogoAvisos = (page: Page) => page.getByRole('dialog', { name: 'Cortes de llamadas y otros avisos', exact: true })

test('H4: franja compacta, otro analista seleccionado, llamadas y ficha conservan contexto', async ({ page }, info) => {
  const { estado, lead } = await preparar(page)
  const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  await vista.getByRole('button', { name: 'Seleccionar a BRUNO H4' }).click()
  await vista.getByRole('searchbox').fill('BRUNO')
  const franja = page.getByRole('region', { name: 'Estado de cortes y avisos' })
  await expect(franja).toContainText('16:00 Programado')
  const medidas = await vista.evaluate((e) => ({
    franja: e.querySelector('[aria-label="Estado de cortes y avisos"]')!.getBoundingClientRect().toJSON(),
    scroll: e.closest<HTMLElement>('[data-vista-scroll]')!.scrollHeight - e.closest<HTMLElement>('[data-vista-scroll]')!.clientHeight,
  }))
  expect(medidas.franja.height).toBeLessThanOrEqual(45); expect(medidas.scroll).toBeLessThanOrEqual(1)
  await writeFile(info.outputPath('medidas-h4.json'), JSON.stringify(medidas, null, 2))
  await page.screenshot({ path: info.outputPath('h4-franja-escritorio.png') })
  const lecturas = estado.lecturas
  await abrirAvisos(page)
  const dialogo = dialogoAvisos(page)
  await expect(dialogo.getByText('Primer corte · 11:30')).toBeVisible()
  await dialogo.locator('summary').first().click()
  await expect(dialogo.getByText('1 cumplidos · 1 recuperados · 1 sin cartera abierta.')).toBeVisible()
  expect(estado.lecturas).toBe(lecturas)
  await page.screenshot({ path: info.outputPath('h4-cortes-detalle.png') })
  await dialogo.getByRole('button', { name: 'Ver registro de ANA H4', exact: true }).click()
  await expect(dialogo).toHaveCount(0)
  const panel = page.getByRole('region', { name: 'Detalle de ANA H4', exact: true })
  await expect(panel.getByRole('heading', { name: 'Detalle de ANA H4', exact: true })).toBeFocused()
  await expect(panel.getByRole('tab', { name: 'Llamadas', exact: true })).toHaveAttribute('aria-selected', 'true')
  await expect(vista.getByRole('searchbox')).toHaveValue('BRUNO')
  await expect(page.getByText('La selección está fuera de los filtros.')).toBeVisible()
  expect(estado.registros.at(-1)).toMatchObject({ p_analista_ids: [idH4(2)], p_tipos: ['llamada_realizada', 'llamada_no_contestada'] })
  const enlace = panel.getByRole('button', { name: lead.nombre_completo })
  await enlace.click(); await expect(page.getByRole('dialog', { name: lead.nombre_completo })).toBeVisible()
  await page.keyboard.press('Escape'); await expect(enlace).toBeFocused()
  await expect(panel.getByText('Llamada desde corte H4')).toBeVisible()
  await panel.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  await abrirAvisos(page)
  await dialogo.getByRole('tab', { name: 'Otros pendientes', exact: true }).click()
  await dialogo.getByRole('button', { name: 'Ver pendientes', exact: true }).click()
  await expect(page).toHaveURL(/#\/seguimiento$/)
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  // Al volver, abre sola con quien más atención necesita (ANA H4, 1 vencida; plan v2, 27/09).
  await expect(page.getByRole('region', { name: 'Detalle de ANA H4', exact: true })).toBeVisible()
})

test('H4: aplazar una vez, reintento con mismo UUID y reconocimiento reflejado en campana', async ({ page }) => {
  const { estado } = await preparar(page)
  await abrirAvisos(page); const dialogo = dialogoAvisos(page)
  estado.falloAccion = true
  await dialogo.getByRole('button', { name: 'Posponer 1 hora', exact: true }).click()
  await expect(dialogo.getByRole('alert')).toContainText('No se confirmó')
  await dialogo.getByRole('button', { name: 'Posponer 1 hora', exact: true }).click()
  await expect(dialogo.getByText(/Pospuesto hasta las 13:00/)).toBeVisible()
  expect(estado.acciones).toHaveLength(2); expect(estado.acciones[0]).toEqual(estado.acciones[1])
  await expect(dialogo.getByRole('button', { name: 'Posponer 1 hora' })).toHaveCount(0)
  await page.keyboard.press('Escape'); await abrirAvisos(page)
  await expect(dialogo.getByText(/Pospuesto hasta las 13:00/)).toBeVisible()
  await dialogo.getByRole('button', { name: 'Lo estoy atendiendo', exact: true }).click()
  await expect(dialogo.getByText(/Reconocido; el resultado del corte se conserva/)).toBeVisible()
  await expect(dialogo.getByRole('button', { name: 'Lo estoy atendiendo' })).toHaveCount(0)
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: /^Abrir notificaciones/ }).click()
  await page.getByRole('link', { name: 'Ver otros pendientes', exact: true }).click()
  await expect(page.getByText('Primer corte de llamadas', { exact: true }).last()).toBeVisible()
  await expect(page.getByText(/Reconocido; el resultado del corte se conserva/)).toBeVisible()
  await page.getByRole('button', { name: 'Ver registro de ANA H4', exact: true }).click()
  await expect(page.getByRole('region', { name: 'Detalle de ANA H4', exact: true })).toBeVisible()
  expect(estado.acciones).toHaveLength(3); expect(estado.presentaciones).toBe(0)
})

test('H4: popup único, cierre conserva pendiente y abre el registro correcto', async ({ page }) => {
  const { estado } = await preparar(page, true)
  const popup = page.getByRole('dialog', { name: 'Primer corte de llamadas', exact: true })
  await expect(popup).toBeVisible()
  await popup.getByRole('button', { name: 'Ver registro de ANA H4', exact: true }).click()
  await expect(popup).toHaveCount(0)
  await expect(page.getByRole('region', { name: 'Detalle de ANA H4', exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.mouse.move(900, 90)
  await abrirAvisos(page); await expect(dialogoAvisos(page).getByText('Pendiente de atención.')).toBeVisible()
  await page.keyboard.press('Escape'); await abrirAvisos(page); await page.keyboard.press('Escape')
  await page.clock.runFor(3000)
  expect(estado.presentaciones).toBe(1); expect(estado.acciones).toHaveLength(0)
})

test('H4: error de popup deja lista disponible; refresco refleja otra sesión y revocación', async ({ page }) => {
  const { estado } = await preparar(page)
  estado.falloPopup = true; estado.avisos.alertas[0]!.puede_presentar = true
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await page.clock.runFor(4000)
  await abrirAvisos(page); const dialogo = dialogoAvisos(page)
  await expect(dialogo.getByText(/No se pudo abrir el aviso emergente/)).toBeVisible()
  await expect(dialogo.getByRole('button', { name: 'Ver registro de ANA H4' })).toBeVisible()
  await page.keyboard.press('Escape')
  const aviso = estado.avisos.alertas[0]!
  aviso.estado = 'reconocido'; aviso.reconocido_en = estado.avisos.generado_en; aviso.puede_presentar = false; aviso.puede_posponer = false
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await abrirAvisos(page); await expect(dialogo.getByText(/Reconocido; el resultado del corte se conserva/)).toBeVisible()
  await page.keyboard.press('Escape')
  estado.errorAvisos = '42501'
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(page.getByRole('region', { name: 'Estado de cortes y avisos' })).toContainText('Avisos no disponibles')
  await abrirAvisos(page)
  await expect(dialogo.getByRole('button', { name: 'Ver registro de ANA H4' })).toHaveCount(0)
  await dialogo.getByRole('tab', { name: 'Otros pendientes' }).click()
  await expect(dialogo.getByText(/No pudimos confirmar los otros pendientes/)).toBeVisible()
})

test('H4: teclado, móvil y reflow de cortes; cerrar devuelve el foco', async ({ page }, info) => {
  await preparar(page)
  await page.setViewportSize({ width: 390, height: 844 })
  const origen = page.getByRole('button', { name: 'Cortes y avisos' })
  await origen.focus(); await page.keyboard.press('Enter')
  const dialogo = dialogoAvisos(page)
  await dialogo.getByRole('tab', { name: 'Cortes', exact: true }).focus()
  await page.keyboard.press('ArrowRight'); await expect(dialogo.getByRole('tab', { name: 'Otros pendientes' })).toHaveAttribute('aria-selected', 'true')
  await page.keyboard.press('ArrowLeft'); await dialogo.locator('summary').first().focus(); await page.keyboard.press('Enter')
  await expect(dialogo.locator('details').first()).toHaveAttribute('open', '')
  expect(await dialogo.evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(true)
  const defectos = await dialogo.evaluate((e) => [...e.querySelectorAll<HTMLElement>('*')].filter((n) => n.getClientRects().length && !n.closest('[hidden]') &&
    ((n.matches('button,summary') && n.getBoundingClientRect().height < 43.9) ||
      [...n.childNodes].some((t) => t.nodeType === Node.TEXT_NODE && t.textContent?.trim()) && parseFloat(getComputedStyle(n).fontSize) < 16)).map((n) => n.textContent))
  expect(defectos).toEqual([])
  await page.screenshot({ path: info.outputPath('h4-cortes-movil.png') })
  await page.setViewportSize({ width: 756, height: 402 })
  expect(await dialogo.evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(true)
  await page.keyboard.press('Escape'); await expect(origen).toBeFocused()
})

test('H4: contrato anterior sin detalle diario conserva la jornada con reloj simulado', async ({ page }) => {
  await page.clock.install({ time: new Date('2026-09-26T12:00:00-05:00') })
  await montarBackendReal(page, { rolCrm: 'supervisor' })
  await loginReal(page)
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  await abrirAvisos(page)
  const dialogo = dialogoAvisos(page)
  await expect(dialogo.getByText('Los avisos de cortes están desactivados para esta jornada.', { exact: true })).toBeVisible()
  await expect(dialogo.getByText(/No pudimos confirmar los avisos de cortes/)).toHaveCount(0)
  await dialogo.getByRole('tab', { name: 'Otros pendientes', exact: true }).click()
  await expect(dialogo.getByRole('heading', { name: 'Otros pendientes del equipo', exact: true })).toBeVisible()
  await expect(dialogo.getByText(/No pudimos confirmar los otros pendientes/)).toHaveCount(0)
})
