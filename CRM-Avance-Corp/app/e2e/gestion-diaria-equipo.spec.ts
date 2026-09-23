import { expect, test } from '@playwright/test'
import { entrarDemo, leadReal, loginReal, montarBackendReal, UID } from './_helpers'
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
  // El contorno debe sobrevivir al alto contraste: el ring de box-shadow no.
  await page.emulateMedia({ forcedColors: 'active' })
  await page.keyboard.press('Tab')
  for (const control of [tabla.getByRole('button', { name: `Detalle de ${nombre}` }), tabla.getByRole('button', { name: `Ver registro de ${nombre}` })]) {
    await control.focus()
    await expect(control).toBeFocused()
    await expect(control).not.toHaveCSS('outline-style', 'none')
    expect(await control.evaluate((el) => Number.parseFloat(getComputedStyle(el).outlineWidth))).toBeGreaterThanOrEqual(2)
  }
  await page.emulateMedia({ forcedColors: 'none' })
  await tabla.getByRole('button', { name: /^Detalle de / }).click()
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

test('F4.2: detalle → llamadas → ficha fuera del boot → regreso; paginación revocada', async ({ page }, info) => {
  const hoy = fechaLima(Date.now())
  const lead = leadReal({ nombre_completo: 'LEAD FUERA DE LA CACHÉ', fueraDelBoot: true, asignado_supervisor_id: UID })
  const backend = await montarBackendReal(page, { rolCrm: 'supervisor', leads: [lead], tareas: [] })
  const fila = filaEquipoPrueba({ analista_id: 'vend-1', nombre_completo: 'Analista Real Uno', gestiones_hoy: 26,
    minutos_sin_llamar: 60, llamadas_por_lead: 26, ultima_gestion_en: `${hoy}T15:25:00Z`,
    marcador: { ...filaEquipoPrueba().marcador, llamadas: 26, contestadas: 26, utiles: 26, tasa_contacto_pct: 100, nivel: 'bien',
      leads_tocados: 1, primera_llamada_en: `${hoy}T15:00:00Z`, ultima_llamada_en: `${hoy}T15:25:00Z`,
      por_hora: [{ hora: 10, llamadas: 26, contestadas: 26 }] } })
  const equipo = { ...diaEquipoPrueba([fila]), dia: hoy, supervisor_id: UID }
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', (route) => route.fulfill({ json: equipo }))
  let revocado = false
  const items = Array.from({ length: 26 }, (_, i) => ({
    id: `gestion-${i}`, lead_id: lead.id, lead_nombre: lead.nombre_completo, lead_etapa: 'nuevo', etapa_en_ese_momento: 'nuevo',
    tipo: 'llamada_realizada', detalle: `Conversación completa ${i}: solicita revisar el seguimiento.`, metadata: { resultado: 'volver_a_llamar' },
    creado_por: 'vend-1', autor_nombre: 'Analista Real Uno', creado_en: `${hoy}T15:${String(25 - i).padStart(2, '0')}:00.000Z`,
  }))
  await page.route('**/rest/v1/rpc/registro_actividad_fn', async (route) => {
    const pedido = route.request().postDataJSON()
    expect(pedido).toMatchObject({ p_desde: hoy, p_hasta: hoy, p_analista_ids: ['vend-1'], p_limite: 26 })
    if (pedido.p_tipos !== null) expect(pedido.p_tipos).toEqual(['llamada_realizada', 'llamada_no_contestada'])
    if (revocado) return route.fulfill({ status: 403, json: { code: '42501', message: 'Acceso revocado' } })
    return route.fulfill({ json: { version: 1, generado_en: `${hoy}T18:00:00Z`, desde: hoy, hasta: hoy, zona: 'America/Lima', limite: 26,
      items: pedido.p_antes_de ? [items[25]] : items } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  await vista.getByRole('searchbox').fill('Real Uno')
  const abrirDetalle = vista.getByRole('button', { name: 'Detalle de Analista Real Uno', exact: true })
  const detalle = vista.getByRole('region', { name: 'Detalle de Analista Real Uno', exact: true })
  await expect(abrirDetalle).toHaveAttribute('aria-expanded', 'false')
  await abrirDetalle.focus()
  await page.keyboard.press('Enter')
  await expect(abrirDetalle).toHaveAttribute('aria-expanded', 'true')
  await expect(detalle).toBeVisible()
  await page.keyboard.press('Space')
  await expect(detalle).toBeHidden()
  await expect(abrirDetalle).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(detalle).toBeVisible()
  await expect(detalle.getByText('De 10:00 a 10:59: 26 llamadas, 26 contestadas')).toBeAttached()
  const horario = detalle.getByRole('region', { name: 'Llamadas por hora de Analista Real Uno' })
  await horario.focus()
  await expect(horario).toBeFocused()
  await page.keyboard.press('ArrowRight')
  await expect.poll(() => horario.evaluate((el) => el.scrollLeft)).toBeGreaterThan(0)
  await detalle.screenshot({ path: info.outputPath('detalle-horario.png') })
  const abrirRegistro = detalle.getByRole('button', { name: 'Ver llamadas del día de Analista Real Uno' })
  await abrirRegistro.focus()
  await page.keyboard.press('Enter')
  const registro = page.getByRole('region', { name: 'Registro seleccionado', exact: true })
  await expect(registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true })).toBeFocused()
  await expect(registro.getByRole('tab', { name: 'Llamadas', exact: true })).toHaveAttribute('aria-selected', 'true')
  await expect(registro.getByRole('combobox', { name: 'Analista', exact: true })).toHaveCount(0)
  await registro.getByRole('tab', { name: 'Todo', exact: true }).click()
  await abrirRegistro.click()
  await expect(registro.getByRole('tab', { name: 'Llamadas', exact: true })).toHaveAttribute('aria-selected', 'true')
  const enlace = registro.getByRole('button', { name: lead.nombre_completo }).first()
  const cargasAntes = backend.llamadas.getLeads
  await enlace.focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('dialog', { name: lead.nombre_completo })).toBeVisible()
  expect(backend.llamadas.getLeads).toBeGreaterThan(cargasAntes)
  await page.keyboard.press('Escape')
  await expect(enlace).toBeFocused()
  await expect(registro.getByText('Conversación completa 0: solicita revisar el seguimiento.')).toBeVisible()
  // La ficha vuelve a consultar RLS aun si el lead ya fue hidratado.
  backend.leads = []
  await enlace.click()
  await expect(page.getByText('La oportunidad ya no está disponible en tu cartera.')).toBeVisible()
  await expect(page.getByRole('dialog', { name: lead.nombre_completo })).toHaveCount(0)
  await registro.getByRole('button', { name: 'Ver más' }).click()
  await expect(registro.getByRole('listitem')).toHaveCount(26)
  await registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath('registro-detalle.png') })
  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true }).scrollIntoViewIfNeeded()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: info.outputPath('registro-detalle-movil.png') })
  const pestañas = registro.getByRole('tablist', { name: 'Tipo de actividad' })
  await pestañas.scrollIntoViewIfNeeded()
  const etiquetasRecortadas = await pestañas.getByRole('tab').evaluateAll((botones) => botones.filter((boton) => {
    const texto = document.createRange()
    texto.selectNodeContents(boton)
    const caja = boton.getBoundingClientRect()
    const etiqueta = texto.getBoundingClientRect()
    return etiqueta.left < caja.left || etiqueta.right > caja.right
  }).map((boton) => boton.textContent))
  expect(etiquetasRecortadas).toEqual([])
  await page.screenshot({ path: info.outputPath('registro-actividad-movil.png') })
  await page.setViewportSize({ width: 1280, height: 720 })
  const pequenos = await registro.evaluate((raiz) => Array.from(raiz.querySelectorAll<HTMLElement>('*')).filter((el) =>
    el.getClientRects().length > 0 && Array.from(el.childNodes).some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim())
      && Number.parseFloat(getComputedStyle(el).fontSize) < 16).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
  expect(pequenos).toEqual([])
  revocado = true
  await registro.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(registro.getByRole('alert')).toContainText('Ya no tienes autorización')
  await expect(registro.getByRole('listitem')).toHaveCount(0)
  await registro.getByRole('button', { name: 'Cerrar registro', exact: true }).click()
  await expect(abrirRegistro).toBeFocused()
  await expect(vista.getByRole('searchbox')).toHaveValue('Real Uno')
  await expect(abrirDetalle).toHaveAttribute('aria-expanded', 'true')
})
