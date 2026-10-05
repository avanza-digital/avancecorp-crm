import { expect, test, type Page } from '@playwright/test'
import { leadReal, loginReal, montarBackendReal, UID } from './_helpers'

// En Tokio ya es 6 de octubre; el dashboard debe seguir mostrando el 5 de Lima.
test.use({ timezoneId: 'Asia/Tokyo' })
const AHORA = '2026-10-06T04:30:00Z'
const HOY = '2026-10-05'

async function montarHoy(page: Page, cantidad: number, caido = false) {
  await page.clock.setFixedTime(new Date(AHORA))
  const recibidos = Array.from({ length: cantidad }, (_, i) => leadReal({
    id: `cccccccc-0000-4000-8000-${String(i).padStart(12, '0')}`,
    nombre_completo: `RECIBIDO HOY ${String(i + 1).padStart(2, '0')}`,
    vendedor_id: UID, etapa: i === 0 ? 'propuesta_enviada' : i === 1 ? 'contactado' : 'nuevo',
    tenencia_desde: '2026-10-05T14:00:00Z',
    creado_en: '2026-09-01T15:00:00Z',
    actualizado_en: new Date(Date.parse(AHORA) - i * 60000).toISOString(),
  }))
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', leads: recibidos,
    actividades: recibidos.slice(0, 2).map((l, i) => ({
      id: `eeeeeeee-0000-4000-8000-${String(i).padStart(12, '0')}`, lead_id: l.id,
      tipo: 'llamada_realizada', detalle: null, autor_id: UID,
      creado_en: '2026-10-05T15:00:00Z', metadata: {},
    })),
    tareas: recibidos[0] ? [{
      id: 'dddddddd-0000-4000-8000-000000000001', lead_id: recibidos[0].id, perfil_id: null,
      vendedor_id: UID, asignado_supervisor_id: null, tipo: 'reunion', titulo: 'Cita de hoy', nota: null,
      vence_en: '2026-10-06T04:45:00Z', estado: 'pendiente', activo: true, reprogramaciones: 0,
      creado_en: '2026-10-05T15:00:00Z', duracion_min: 30, modalidad_reunion: 'virtual',
      ubicacion_reunion: null, enlace_reunion: 'https://meet.google.com/abc-defg-hij', resultado_reunion: null,
      motivo_no_realizada: null, detalle_cierre_reunion: null, confirmada_en: null, reagendada_de: null,
    }] : [],
  })
  // Activo es el modo usado en producción, con agenda y citas siempre visibles.
  await page.route('**/rest/v1/rpc/estado_sla_leads_v2_fn', route => route.fulfill({ json: {
    version: 2, modo: 'activo', control_revision: 1, calculado_en: AHORA, filas: [],
  } }))
  const consultas: Record<string, unknown>[] = []
  let fallar = caido
  await page.route('**/rest/v1/rpc/cartera_filtrada_fn', async route => {
    const pedido = route.request().postDataJSON() as Record<string, unknown>
    if (!pedido.p_desde) return route.fallback()
    consultas.push(pedido)
    expect(pedido.p_desde).toBe(HOY)
    expect(pedido.p_hasta).toBe(HOY)
    expect(pedido.p_vendedor_id).toBe(UID)
    expect(pedido.p_etapa).toBeUndefined()
    expect([undefined, 'sin_gestion']).toContain(pedido.p_gestion)
    if (fallar) return route.fulfill({ status: 500, json: { message: 'sin conexión', code: 'PGRST000' } })
    const filas = pedido.p_gestion === 'sin_gestion'
      ? estado.leads.filter(l => !estado.actividades.some(a => a.lead_id === l.id
        && ['llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada'].includes(String(a.tipo))
        && !Object.hasOwn((a.metadata ?? {}) as object, 'deshecho_en')
        && String(a.creado_en) >= String(l.tenencia_desde)))
      : estado.leads
    const total = filas.length
    const inicio = pedido.p_antes_id ? filas.findIndex(l => l.id === pedido.p_antes_id) + 1 : 0
    await route.fulfill({ json: {
      version: 1, generado_en: AHORA, desde: HOY, hasta: HOY,
      items: filas.slice(inicio, inicio + Number(pedido.p_limite)).map(l => ({
        ...l, ultimo_contacto_en: null, recibido_en: '2026-10-05T14:30:00Z', recepcion_aproximada: false,
      })),
      resumen: {
        totales: { vivos: total, abiertos: total, asignados: total, parkeados: 0, convertidos: 0,
          descartados: 0, asignados_pen: total, asignados_usd: 0 },
        capital: { asignado: { pen: total * 1000, usd: 0 }, parkeado: { pen: 0, usd: 0 }, ganado: { pen: 0, usd: 0 } },
        embudo: ['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada'].map(etapa => ({
          etapa, n: filas.filter(l => l.etapa === etapa).length,
        })),
      },
    } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Hoy', exact: true }).click()
  return { consultas, estado, recuperar: () => { fallar = false } }
}

test('Hoy lista los recibidos en Lima, pagina y abre la ficha; cabe en escritorio y móvil', async ({ page }) => {
  await page.setViewportSize({ width: 1512, height: 900 })
  // Cuenta de prueba con sus avisos ya configurados: la captura muestra el
  // dashboard cotidiano, sin el aviso inicial de activación de notificaciones.
  await page.addInitScript((id) => {
    localStorage.setItem(`ac-crm-respuestas-tasa-v1:${id}`, JSON.stringify({
      iniciado: true, configurado: true, sonido: false, escritorio: false, respuestas: {},
    }))
  }, UID)
  const { consultas } = await montarHoy(page, 55)
  const agendaTab = page.getByRole('tab', { name: 'Tu agenda de hoy', exact: true })
  const leadsTab = page.getByRole('tab', { name: /^Leads de hoy/ })
  await expect(agendaTab).toHaveAttribute('aria-selected', 'true')
  await expect(leadsTab).toHaveText('Leads de hoy 53 sin gestionar')
  const contador = leadsTab.locator('.hoy-leads-contador')
  const citasAntes = page.getByRole('heading', { name: 'Tus citas', exact: true }).locator('..').locator('..')
  await expect(citasAntes.getByRole('button', { name: 'Cerrar tarea — Cita de hoy', exact: true })).toBeVisible()
  const cajaCitas = await citasAntes.boundingBox()
  await page.screenshot({ path: test.info().outputPath('vista-agenda.png'), fullPage: true })
  // La geometría se mide sin las transiciones de entrada de la pantalla.
  // Para el aviso, verificamos expresamente ambos modos de movimiento.
  await page.emulateMedia({ reducedMotion: 'no-preference' })
  await expect(contador).toHaveCSS('animation-name', 'hoy-leads-latido')
  await expect(contador).toHaveCSS('animation-duration', '30s')
  await leadsTab.click()
  await expect(leadsTab).toHaveAttribute('aria-selected', 'true')
  await expect(contador).toHaveText('53')
  await expect(contador).toHaveCSS('animation-name', 'hoy-leads-latido')
  await expect(contador).toHaveCSS('background-color', 'rgb(185, 78, 6)')
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await expect(contador).toHaveCSS('animation-name', 'none')
  const panel = page.getByRole('region', { name: 'Leads recibidos hoy' })
  await expect(panel.getByText('55 leads recibidos hoy')).toBeVisible()
  expect(await citasAntes.boundingBox()).toEqual(cajaCitas)
  await page.screenshot({ path: test.info().outputPath('vista-leads.png'), fullPage: true })
  await expect(panel.getByRole('listitem')).toHaveCount(50)
  await expect(panel.getByRole('button', { name: 'Abrir lead RECIBIDO HOY 01' })).toContainText('Entrevista realizada')
  await expect(panel.getByRole('button', { name: 'Abrir lead RECIBIDO HOY 02' })).toContainText('Contactado')
  await expect(agendaTab).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Tus citas', exact: true })).toBeVisible()
  const citas = page.getByRole('heading', { name: 'Tus citas', exact: true }).locator('..').locator('..')
  const anchoPanel = await panel.evaluate(el => el.getBoundingClientRect().width)
  expect(anchoPanel).toBeGreaterThan(await citas.evaluate(el => el.getBoundingClientRect().width))
  await expect(citas.getByRole('button', { name: 'Cerrar tarea — Cita de hoy', exact: true })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Tu cumplimiento del mes', exact: true })).toBeVisible()
  await page.screenshot({ path: test.info().outputPath('hoy-recibidos-desktop.png'), fullPage: true })
  const alto = await page.evaluate(() => ({ total: document.documentElement.scrollHeight, visible: innerHeight }))
  expect(alto.total).toBeLessThanOrEqual(alto.visible)
  await page.setViewportSize({ width: 1280, height: 800 })
  const listaCitas = citas.locator('.overflow-y-auto')
  expect(await listaCitas.evaluate(el => el.clientHeight)).toBeGreaterThanOrEqual(200)
  await page.screenshot({ path: test.info().outputPath('hoy-recibidos-portatil.png'), fullPage: true })
  await panel.getByRole('button', { name: 'Cargar más leads de hoy' }).click()
  await expect(panel.getByRole('listitem')).toHaveCount(55)
  await expect(panel.getByRole('button', { name: 'Abrir lead RECIBIDO HOY 51' })).toBeFocused()
  expect(consultas.filter(c => !c.p_gestion).at(-1)?.p_antes_id).toBe('cccccccc-0000-4000-8000-000000000049')
  await panel.getByRole('button', { name: 'Abrir lead RECIBIDO HOY 55' }).click()
  await expect(page.getByRole('dialog', { name: 'RECIBIDO HOY 55', exact: true })).toBeVisible()
  await page.keyboard.press('Escape')
  await page.setViewportSize({ width: 390, height: 844 })
  const menu = page.getByRole('button', { name: 'Ocultar menú', exact: true })
  if (await menu.isVisible()) await menu.click()
  await panel.scrollIntoViewIfNeeded()
  await expect(page.getByRole('tab', { name: /^Leads de hoy/ })).toBeVisible()
  const cajaContador = await contador.boundingBox()
  const cajaPestanas = await page.getByRole('tablist', { name: 'Agenda y leads de hoy' }).boundingBox()
  expect(cajaContador).not.toBeNull()
  expect(cajaPestanas).not.toBeNull()
  expect(cajaContador!.x + cajaContador!.width).toBeLessThanOrEqual(cajaPestanas!.x + cajaPestanas!.width)
  await page.screenshot({ path: test.info().outputPath('hoy-recibidos-mobile.png'), fullPage: true })
  const ancho = await page.evaluate(() => ({ total: document.documentElement.scrollWidth, visible: innerWidth }))
  expect(ancho.total).toBeLessThanOrEqual(ancho.visible)
  const filaEtapaLarga = panel.getByRole('button', { name: 'Abrir lead RECIBIDO HOY 01' })
  const etiqueta = filaEtapaLarga.getByText('Entrevista realizada', { exact: false })
  await filaEtapaLarga.scrollIntoViewIfNeeded()
  await expect(etiqueta).toBeVisible()
  const cajaEtapa = await etiqueta.boundingBox()
  const cajaFila = await filaEtapaLarga.boundingBox()
  expect(cajaEtapa!.width).toBeGreaterThan(0)
  expect(cajaEtapa!.x + cajaEtapa!.width).toBeLessThanOrEqual(cajaFila!.x + cajaFila!.width)
  await page.screenshot({ path: test.info().outputPath('hoy-etapa-mobile.png'), fullPage: true })
})

test('registrar una gestión desde la ficha baja el contador y conserva el lead con su estado', async ({ page }) => {
  const { estado } = await montarHoy(page, 3)
  const pestana = page.getByRole('tab', { name: /^Leads de hoy/ })
  await expect(pestana).toHaveText('Leads de hoy 1 sin gestionar')
  await pestana.click()
  const panel = page.getByRole('region', { name: 'Leads recibidos hoy' })
  const fila = panel.getByRole('button', { name: 'Abrir lead RECIBIDO HOY 03' })
  await expect(fila).toContainText('Nuevo')
  await fila.click()
  const ficha = page.getByRole('dialog', { name: 'RECIBIDO HOY 03', exact: true })
  await ficha.getByRole('button', { name: /Copiar el número .* y registrar la llamada/ }).click()
  const llamada = page.getByRole('dialog', { name: /Cómo salió la llamada/ })
  await llamada.getByRole('radio', { name: /^No contestó/ }).check()
  await llamada.getByRole('button', { name: 'Guardar', exact: true }).click()
  await expect(llamada).toHaveCount(0)
  await page.keyboard.press('Escape')
  await expect(pestana).toHaveText('Leads de hoy 0 sin gestionar')
  await expect(pestana.locator('.hoy-leads-contador')).toHaveCSS('animation-name', 'none')
  await expect(panel.getByText('3 leads recibidos hoy')).toBeVisible()
  await expect(panel.getByRole('listitem')).toHaveCount(3)
  await expect(fila).toContainText('Gestionado')
  expect(estado.llamadas.rpcSlaComandos).toEqual(['registrar_llamada'])
  await page.screenshot({ path: test.info().outputPath('hoy-gestionado-sin-pendientes.png'), fullPage: true })
})

test('un fallo no se presenta como cero recibidos; se puede reintentar hasta el vacío real', async ({ page }) => {
  const { recuperar } = await montarHoy(page, 0, true)
  await page.getByRole('tab', { name: /^Leads de hoy/ }).click()
  const panel = page.getByRole('region', { name: 'Leads recibidos hoy' })
  await expect(panel.getByRole('alert')).toContainText('No se pudieron cargar')
  await expect(panel.getByText('Todavía no has recibido leads hoy.')).toHaveCount(0)
  recuperar()
  await panel.getByRole('button', { name: 'Reintentar' }).click()
  await expect(panel.getByText('Todavía no has recibido leads hoy.')).toBeVisible()
  await expect(panel.getByText('0 leads recibidos hoy')).toBeVisible()
  const contador = page.getByRole('tab', { name: 'Leads de hoy 0 sin gestionar' }).locator('.hoy-leads-contador')
  await expect(contador).toHaveText('0')
  await expect(contador).toHaveCSS('animation-name', 'none')
  const citas = page.getByRole('heading', { name: 'Tus citas', exact: true }).locator('..').locator('..')
  expect(await citas.evaluate(el => el.getBoundingClientRect().width)).toBeLessThan(await panel.evaluate(el => el.getBoundingClientRect().width))
  await expect(citas.getByText('Sin citas agendadas', { exact: true })).toBeVisible()
  await expect(citas).toHaveCSS('align-self', 'flex-start')
  await page.screenshot({ path: test.info().outputPath('hoy-sin-citas.png'), fullPage: true })
})
