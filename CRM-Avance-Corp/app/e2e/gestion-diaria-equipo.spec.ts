import { expect, test } from '@playwright/test'
import { writeFile } from 'node:fs/promises'
import { entrarDemo, leadReal, loginReal, montarBackendReal, UID } from './_helpers'
import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'
import { fechaLima } from '../src/lib/agenda-derivada'

// Escala del diseño de Gestión Diaria (Miguel, 27/09/2026): el piso es 11 px, como en el analista.
test('Supervisor: roster demo, búsqueda y detalle con texto de al menos 11 px', async ({ page }, info) => {
  await page.setViewportSize({ width: 1512, height: 805 })
  await entrarDemo(page, 'Supervisor')
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  const tabla = vista.getByRole('table')
  await expect(tabla).toBeVisible()
  const analistas = tabla.locator('tr[data-analista]')
  expect(await analistas.count()).toBeGreaterThan(0)
  const nombre = (await analistas.first().getByRole('rowheader').getByRole('button').first().textContent())!
  await vista.getByRole('searchbox').fill(nombre)
  await expect(analistas).toHaveCount(1)
  // El contorno debe sobrevivir al alto contraste: el ring de box-shadow no.
  await page.emulateMedia({ forcedColors: 'active' })
  await page.keyboard.press('Tab')
  for (const control of [tabla.getByRole('button', { name: `Seleccionar a ${nombre}` })]) {
    await control.focus()
    await expect(control).toBeFocused()
    await expect(control).not.toHaveCSS('outline-style', 'none')
    expect(await control.evaluate((el) => Number.parseFloat(getComputedStyle(el).outlineWidth))).toBeGreaterThanOrEqual(2)
  }
  await page.emulateMedia({ forcedColors: 'none' })
  await tabla.getByRole('button', { name: /^Seleccionar a / }).click()
  await expect(vista.getByText('Llamadas por lead', { exact: true })).toBeVisible()
  const chicos = await vista.evaluate((raiz) => Array.from(raiz.querySelectorAll<HTMLElement>('*')).filter((el) =>
    el.getClientRects().length > 0 && Array.from(el.childNodes).some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim())
      && Number.parseFloat(getComputedStyle(el).fontSize) < 11).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
  expect(chicos).toEqual([])
  await page.evaluate(() => document.fonts.ready)
  expect(await page.evaluate(() => [...document.fonts].some((f) => f.family.includes('Jakarta') && f.status === 'loaded'))).toBe(true)
  const abrir = vista.getByRole('button', { name: `Ir al detalle de ${nombre}` })
  await abrir.focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('heading', { name: `Detalle de ${nombre}`, exact: true })).toBeFocused()
  await page.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  await expect(tabla.getByRole('button', { name: `Seleccionar a ${nombre}` })).toBeFocused()
  await vista.getByRole('heading', { level: 2 }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath('equipo-escritorio.png'), fullPage: true })
  await page.setViewportSize({ width: 390, height: 844 })
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
  await expect(vista.getByRole('cell', { name: '270', exact: true }).first()).toBeVisible()
  await vista.getByRole('button', { name: /Con atención/ }).click()
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
  await page.setViewportSize({ width: 1512, height: 805 })
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
    // Main (#80) omite p_tipos en «Todo»; cuando se filtra, exige ambos tipos.
    if (pedido.p_tipos !== undefined) expect(pedido.p_tipos).toEqual(['llamada_realizada', 'llamada_no_contestada'])
    if (revocado) return route.fulfill({ status: 403, json: { code: '42501', message: 'Acceso revocado' } })
    return route.fulfill({ json: { version: 1, generado_en: `${hoy}T18:00:00Z`, desde: hoy, hasta: hoy, zona: 'America/Lima', limite: 26,
      items: pedido.p_antes_de ? [items[25]] : items } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  await vista.getByRole('searchbox').fill('Real Uno')
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await expect(vista).toHaveAttribute('data-estrecho', 'false')
  const abrirDetalle = vista.getByRole('button', { name: 'Seleccionar a Analista Real Uno', exact: true })
  const detalle = page.getByRole('region', { name: 'Detalle de Analista Real Uno', exact: true })
  await abrirDetalle.focus()
  await page.keyboard.press('Enter')
  await expect(abrirDetalle).toHaveAttribute('aria-current', 'true')
  await expect(abrirDetalle).toBeFocused()
  await expect(detalle).toBeVisible()
  // Barras del diseño (27/09): el dato viaja en una lista para el lector de pantalla, sin desplegable.
  await expect(detalle.getByRole('list', { name: 'Llamadas por hora' }).getByText('10:00 — 26 llamadas, 26 contestadas')).toBeAttached()
  await detalle.screenshot({ path: info.outputPath('detalle-horario.png') })
  const abrirRegistro = detalle.getByRole('button', { name: 'Ver llamadas del día de Analista Real Uno' })
  await abrirRegistro.focus()
  await page.keyboard.press('Enter')
  const registro = page.getByRole('region', { name: 'Registro seleccionado', exact: true })
  await expect(registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true })).toBeFocused()
  await expect(registro.getByRole('tab', { name: 'Llamadas', exact: true })).toHaveAttribute('aria-selected', 'true')
  await expect(registro.getByRole('combobox', { name: 'Analista', exact: true })).toHaveCount(0)
  await registro.getByRole('tab', { name: 'Todo', exact: true }).click()
  await detalle.getByRole('tab', { name: 'Resumen', exact: true }).click()
  await abrirRegistro.click()
  await expect(registro.getByRole('tab', { name: 'Llamadas', exact: true })).toHaveAttribute('aria-selected', 'true')
  await detalle.getByRole('button', { name: 'Ampliar panel' }).click()
  await expect(page.getByRole('dialog', { name: 'Detalle de Analista Real Uno' })).toBeVisible()
  const enlace = registro.getByRole('button', { name: lead.nombre_completo }).first()
  const cargasAntes = backend.llamadas.getLeads
  await enlace.focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('dialog', { name: lead.nombre_completo })).toBeVisible()
  expect(backend.llamadas.getLeads).toBeGreaterThan(cargasAntes)
  await page.keyboard.press('Escape')
  await expect(enlace).toBeFocused()
  await expect(page.getByRole('dialog', { name: 'Detalle de Analista Real Uno' })).toBeVisible()
  await detalle.getByRole('button', { name: 'Restaurar panel' }).click()
  await expect(detalle.getByRole('button', { name: 'Ampliar panel' })).toBeFocused()
  await expect(registro.getByRole('listitem')).toHaveCount(25)
  await expect(registro.getByText('Conversación completa 0: solicita revisar el seguimiento.')).toBeVisible()
  // La ficha vuelve a consultar RLS aun si el lead ya fue hidratado.
  backend.leads = []
  await enlace.click()
  await expect(page.getByText('La oportunidad ya no está disponible en tu cartera.')).toBeVisible()
  await expect(page.getByRole('dialog', { name: lead.nombre_completo })).toHaveCount(0)
  await registro.getByRole('button', { name: 'Ver más' }).click()
  await expect(registro.getByRole('listitem')).toHaveCount(26)
  await registro.getByRole('combobox', { name: 'Etapa actual del lead' }).focus()
  await page.setViewportSize({ width: 1512, height: 805 })
  await expect(page.getByRole('dialog', { name: 'Detalle de Analista Real Uno' })).toHaveCount(0)
  await expect(registro.getByRole('combobox', { name: 'Etapa actual del lead' })).toBeFocused()
  await expect(registro.getByRole('listitem')).toHaveCount(26)
  await page.setViewportSize({ width: 390, height: 844 })
  await registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath('registro-detalle.png') })
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(registro.getByRole('listitem')).toHaveCount(26)
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
      && Number.parseFloat(getComputedStyle(el).fontSize) < 11).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
  expect(pequenos).toEqual([])
  revocado = true
  await registro.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(registro.getByRole('alert')).toContainText('Ya no tienes autorización')
  await expect(registro.getByRole('listitem')).toHaveCount(0)
  await detalle.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  await expect(abrirDetalle).toBeFocused()
  await expect(vista.getByRole('searchbox')).toHaveValue('Real Uno')
  await expect(abrirDetalle).not.toHaveAttribute('aria-current')
})

// Diseño de Gestión Diaria (27/09/2026): filas de 52 px con aire en vez de las 44 px de H2 (23/09); se ven
// menos filas sin desplazar y el resto se alcanza dentro de la tabla, sin mover la página.
for (const medida of [{ width: 1512, height: 805, filas: 6 }, { width: 1366, height: 768, filas: 5 }]) {
  test(`H2 densidad ${medida.width}: ${medida.filas} filas, seis columnas y texto completo`, async ({ page }, info) => {
    await page.setViewportSize(medida)
    await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
    const nombres = ['ANA PÉREZ', 'BRUNO DÍAZ', 'CARLA LEÓN', 'DAVID ROJAS', 'ELENA PAZ', 'FABIO VEGA', 'GINA SOTO', 'HUGO RUIZ', 'INES TORRES', 'JOSÉ LUNA', 'KARLA SOL']
    const d = diaEquipoPrueba(nombres.map((nombre, i) => filaEquipoPrueba({ analista_id: `a-${i}`, nombre_completo: nombre,
      tareas_pendientes: 270, tareas_vencidas: 108, requiere_atencion: true, motivos_atencion: ['tarea_vencida'],
      gestiones_hoy: 2, marcador: { ...filaEquipoPrueba().marcador, llamadas: 2, utiles: 2, contestadas: 1, tasa_contacto_pct: 50, por_hora: [{ hora: 10, llamadas: 2, contestadas: 1 }] },
    })))
    d.dia = fechaLima(Date.now()); d.supervisor_id = UID
    await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', (route) => route.fulfill({ json: d }))
    await loginReal(page)
    await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
    await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
    await page.mouse.move(900, 90)
    const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
    await expect(vista).toHaveAttribute('data-estrecho', 'false')
    await page.evaluate(() => document.fonts.ready)
    const primera = vista.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' })
    await primera.click()
    await expect(primera).toBeFocused()
    const geometria = await vista.evaluate((nodo) => {
      const tabla = nodo.querySelector('.gd-tabla-scroll')!
      const caja = tabla.getBoundingClientRect()
      const filas = [...tabla.querySelectorAll<HTMLElement>('tr[data-analista]')].map((f) => f.getBoundingClientRect().toJSON())
      const fuentesPequenas = [...nodo.querySelectorAll<HTMLElement>('*')].filter((e) => e.getClientRects().length && !e.closest('[hidden],.sr-only')
        && [...e.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim()) && parseFloat(getComputedStyle(e).fontSize) < 11).map((e) => e.textContent)
      const controlesBajos = [...nodo.querySelectorAll<HTMLElement>('button,input,select')].filter((e) => e.getClientRects().length && e.getBoundingClientRect().height < 23.9).map((e) => e.textContent)
      const contenedor = nodo.closest<HTMLElement>('[data-vista-scroll]')!
      return { viewport: [innerWidth, innerHeight], ancho: nodo.clientWidth, tabla: caja.toJSON(), filas,
        completas: filas.filter((f) => f.bottom <= caja.bottom + .5).length, fuentesPequenas, controlesBajos,
        scrollPagina: contenedor.scrollHeight - contenedor.clientHeight, overflowTabla: tabla.scrollWidth - tabla.clientWidth }
    })
    expect(geometria.completas).toBeGreaterThanOrEqual(medida.filas)
    expect(geometria.filas.slice(0, medida.filas).every((f) => Math.abs(f.height - 52) < 1.5)).toBe(true)
    expect(geometria.fuentesPequenas).toEqual([])
    expect(geometria.controlesBajos).toEqual([])
    expect(geometria.scrollPagina).toBeLessThanOrEqual(1)
    expect(geometria.overflowTabla).toBe(0)
    await writeFile(info.outputPath('medidas-h2.json'), JSON.stringify(geometria, null, 2))
    await info.attach('medidas-h2.json', { body: JSON.stringify(geometria, null, 2), contentType: 'application/json' })
    await page.screenshot({ path: info.outputPath(`horizontal-${medida.width}.png`) })
    // Las filas restantes siguen alcanzables en su región, sin mover la página.
    await vista.getByRole('button', { name: 'Seleccionar a KARLA SOL' }).focus()
    await expect(vista.getByRole('button', { name: 'Seleccionar a KARLA SOL' })).toBeInViewport()
    if (medida.width === 1512) {
      const indicadores = await vista.getByRole('group', { name: 'Resumen del equipo' }).textContent()
      await vista.getByRole('searchbox').fill('KARLA')
      await expect(vista.getByRole('group', { name: 'Resumen del equipo' })).toHaveText(indicadores!)
      await expect(page.getByText('La selección está fuera de los filtros.')).toBeVisible()
      await page.getByRole('button', { name: 'Limpiar filtros' }).click()
      await page.setViewportSize({ width: 756, height: 402 }) // espacio CSS de 1512×805 al 200 %
      const dialogo = page.getByRole('dialog', { name: 'Detalle de ANA PÉREZ' })
      await expect(dialogo).toBeVisible()
      await expect(dialogo.getByRole('heading', { name: 'Detalle de ANA PÉREZ', exact: true }).last()).toBeFocused()
      await page.screenshot({ path: info.outputPath('horizontal-200-por-ciento.png') })
      await page.keyboard.press('Escape')
      await expect(dialogo).toHaveCount(0)
      await page.setViewportSize({ width: 390, height: 844 })
      await vista.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' }).click()
      await expect(dialogo).toBeVisible()
      await dialogo.getByRole('tab', { name: 'Pendientes', exact: true }).click()
      // El Resumen nuevo también muestra 270 en su cuadro de Pendientes: se mira la pestaña Pendientes.
      await expect(dialogo.getByLabel('Pendientes de ANA PÉREZ', { exact: true }).getByText('270', { exact: true })).toBeVisible()
      expect(await dialogo.evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(true)
      await page.screenshot({ path: info.outputPath('horizontal-movil.png') })
      await page.keyboard.press('Escape')
      await expect(dialogo).toHaveCount(0)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    }
  })
}

test('H2 nombre largo, varios motivos, control de foco y cambio de ruta', async ({ page }, info) => {
  await page.setViewportSize({ width: 1512, height: 805 })
  await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
  const nombre = 'MARÍA ALEJANDRA DE LOS ÁNGELES FERNÁNDEZ DEL CASTILLO'
  const d = diaEquipoPrueba([filaEquipoPrueba({ analista_id: 'larga', nombre_completo: nombre,
    tareas_pendientes: 999, tareas_vencidas: 321, primer_intento_vencido: 8, datos_incompletos: 2,
    requiere_atencion: true, motivos_atencion: ['tarea_vencida', 'primer_intento_vencido', 'datos_incompletos'] })])
  d.dia = fechaLima(Date.now()); d.supervisor_id = UID
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', (route) => route.fulfill({ json: d }))
  await loginReal(page)
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  await page.mouse.move(900, 90)
  const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  await expect(vista).toHaveAttribute('data-estrecho', 'false')
  const seleccion = vista.getByRole('button', { name: `Seleccionar a ${nombre}` })
  await seleccion.click()
  await expect(seleccion).toHaveText(nombre)
  const panel = page.getByRole('region', { name: `Detalle de ${nombre}` })
  await expect(panel.getByRole('button', { name: '321 tareas vencidas' })).toBeVisible()
  for (const motivo of ['Primer intento fuera de plazo', 'Datos pendientes de revisar']) await expect(panel.getByText(motivo, { exact: true })).toBeVisible()
  expect(await seleccion.evaluate((e) => e.scrollHeight <= e.clientHeight && e.scrollWidth <= e.clientWidth)).toBe(true)
  await panel.getByRole('button', { name: 'Ampliar panel' }).click()
  const dialogo = page.getByRole('dialog', { name: `Detalle de ${nombre}` })
  await expect(dialogo).toBeVisible()
  await panel.getByRole('button', { name: 'Cerrar detalle' }).focus()
  for (let n = 0; n < 18; n++) {
    await page.keyboard.press('Tab')
    expect(await dialogo.evaluate((e) => e.contains(document.activeElement))).toBe(true)
  }
  await page.screenshot({ path: info.outputPath('horizontal-nombre-largo.png') })
  await page.keyboard.press('Escape')
  await expect(dialogo).toHaveCount(0)
  await expect(seleccion).toBeFocused()
  await page.getByRole('button', { name: 'Agenda', exact: true }).click()
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  // Al volver, la pantalla abre sola con quien más atención necesita (plan v2, 27/09), sin mover el foco.
  await expect(page.getByRole('region', { name: `Detalle de ${nombre}` })).toBeVisible()
  await expect(vista.getByRole('button', { name: `Seleccionar a ${nombre}` })).toHaveAttribute('aria-current', 'true')
})
