import { expect, test, type Locator, type Page } from '@playwright/test'
import { loginReal, montarBackendReal, leadReal, UID } from './_helpers'
import fixture from '../src/lib/gestion-diaria-f5.test.fixture.json' with { type: 'json' }
import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'

// Transporte interceptado sobre respuestas SQL sintéticas reales. No prueba
// por sí solo Auth/RLS: las 18 solicitudes PostgREST del banco cubren esa capa.
// Pantalla de gerencia con el diseño de Gestión Diaria (G1 y G2, 27/09/2026): la
// operación es la tabla de equipos con la ficha del equipo al lado y, dentro de
// cada equipo, la pantalla del supervisor con la ficha del analista.
const DIA = '2026-09-23'
const grupo = fixture.pulso.equipos.find((e) => e.metricas.llamadas === 4)!
const analista = grupo.personas.find((p) => p.activo && p.llamadas === 4)!
const cliente = leadReal({ vendedor_id: analista.analista_id!, nombre_completo: 'CLIENTE FICTICIO F5' })
/** Así se nombra el equipo en pantalla: «Equipo de SUPERVISOR DOS». */
const EQUIPO = `Equipo de ${grupo.nombre}`
// Umbrales de la ficha al lado (en px de contenedor): la operación y Hábitos, y dentro del equipo.
const EN_LINEA_OPERACION = 1040
const EN_LINEA_EQUIPO = 1100
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
  const estado = { error: false, revocado: false, registroRevocado: false, paginado: false, dias: [] as string[], periodos: [] as number[], registros: [] as Record<string, unknown>[] }
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
    if (estado.registroRevocado) return route.fulfill({ status: 403, json: { code: '42501', message: 'Registro revocado' } })
    const items = pedido.p_analista_ids && !pedido.p_analista_ids.includes(analista.analista_id) ? [] : [{
      id: '11111111-2222-4333-8444-555555555555', lead_id: cliente.id, lead_nombre: cliente.nombre_completo,
      lead_etapa: 'nuevo', etapa_en_ese_momento: 'nuevo', tipo: 'llamada_realizada', detalle: `Llamada ficticia F5 del ${pedido.p_desde}`,
      metadata: { resultado: 'interesado' }, creado_por: analista.analista_id, autor_nombre: analista.nombre_completo,
      creado_en: `${pedido.p_desde}T15:00:00.000Z`,
    }]
    const paginas = estado.paginado && items[0] ? Array.from({ length: 26 }, (_, i) => ({ ...items[0],
      id: `11111111-2222-4333-8444-${String(i + 1).padStart(12, '0')}`,
      detalle: `${items[0]!.detalle} · gestión ${i + 1}`, creado_en: `${pedido.p_desde}T15:${String(25 - i).padStart(2, '0')}:00.000Z`,
    })) : items
    return route.fulfill({ json: { version: 1, zona: 'America/Lima', desde: pedido.p_desde, hasta: pedido.p_hasta,
      generado_en: fixture.pulso.generado_en, limite: pedido.p_limite, items: pedido.p_antes_de ? paginas.slice(25) : paginas } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Equipos de la operación' })).toBeVisible()
  return estado
}
/** El día elegido (23/09) es pasado: la región se llama «Toda la operación», sin «hoy». */
const operacion = (page: Page) => page.getByRole('region', { name: 'Toda la operación', exact: true })
/** Medidas por CSS: con una ventana abierta, Radix oculta el resto del árbol accesible. */
const raizOperacion = (page: Page) => page.locator('section[aria-label="Toda la operación"]')
/** Los botones de la operación van al final de la fila de pestañas (cabecera compacta, 27/09). */
const botonCabecera = (page: Page, nombre: string) => operacion(page).getByRole('group', { name: 'Acciones de la operación', exact: true }).getByRole('button', { name: nombre, exact: true })
async function entrarAlEquipo(page: Page) {
  // La ficha del equipo que más atención necesita se abre sola en pantalla ancha: «Ver el equipo» entra.
  await operacion(page).getByRole('region', { name: `Detalle del ${EQUIPO}`, exact: true }).getByRole('button', { name: 'Ver el equipo', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/gestion-diaria/equipo/${grupo.clave}$`))
  return operacion(page).getByRole('region', { name: EQUIPO, exact: true })
}

test('F6 horizontal: gerencia conserva tabla y detalle con el menú abierto en un portátil', async ({ page, browser, baseURL }, info) => {
  const referencia = await browser.newPage({ baseURL, viewport: { width: 1366, height: 900 } })
  await referencia.clock.setFixedTime(new Date('2026-09-24T15:00:00Z'))
  await montarBackendReal(referencia, { rolCrm: 'supervisor', leads: [], tareas: [] })
  await referencia.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', route => route.fulfill({ json: {
    ...diaEquipoPrueba(Array.from({ length: 10 }, (_, i) => filaEquipoPrueba({
      analista_id: `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`, nombre_completo: `ANALISTA ${i + 1}`,
    }))), dia: '2026-09-24', supervisor_id: UID,
  } }))
  await loginReal(referencia)
  await referencia.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  await expect(referencia.getByRole('group', { name: 'Resumen del equipo' })).toBeVisible()
  await referencia.screenshot({ path: info.outputPath('supervision-1366-menu-abierto.png'), fullPage: true })
  await referencia.close()

  await montar(page)
  await page.getByRole('button', { name: 'Fijar menú abierto', exact: true }).click()
  await page.mouse.move(1000, 80)
  const vista = operacion(page)
  const ficha = vista.getByRole('region', { name: `Detalle del ${EQUIPO}`, exact: true })
  // La tarjeta de la tabla (buscador + tabla) es la que se compara con la ficha.
  const tarjeta = vista.getByRole('region', { name: 'Desplazar tabla de equipos', exact: true }).locator('..')
  const pastillas = vista.getByRole('group', { name: 'Resumen de la operación', exact: true }).getByRole('button')
  // Con el menú fijado, 1366 deja 1078 px a la operación (ficha al lado) y 1280, 992: por debajo de
  // 1040 la tabla ocupa todo el ancho y la ficha automática se cierra sin abrir ninguna ventana.
  for (const [width, height] of [[1366, 900], [1366, 768], [1280, 800]]) {
    await page.setViewportSize({ width: width!, height: height! })
    const enLinea = width === 1366
    await expect(vista).toHaveAttribute('data-estrecho', String(!enLinea))
    if (enLinea) await expect(ficha).toBeVisible()
    else await expect(ficha).toBeHidden()
    await expect(page.getByRole('dialog')).toHaveCount(0)
    await page.screenshot({ path: info.outputPath(`gerencia-${width}x${height}-menu-abierto.png`), fullPage: true })
    const tabla = (await tarjeta.boundingBox())!
    if (enLinea) {
      const lateral = (await ficha.boundingBox())!
      expect(lateral.x).toBeGreaterThanOrEqual(tabla.x + tabla.width)
      expect(Math.abs(lateral.y - tabla.y)).toBeLessThan(2)
    } else {
      expect(Math.abs(tabla.width - (await raizOperacion(page).boundingBox())!.width)).toBeLessThan(2)
    }
    // Sin franja de cifras (como el supervisor): la tabla empieza bajo cabecera y pestañas.
    expect(tabla.y).toBeLessThan(360)
    const posiciones = await pastillas.evaluateAll(nodos => nodos.map(n => n.getBoundingClientRect().y))
    expect(posiciones).toHaveLength(3)
    expect(new Set(posiciones).size).toBe(1)
    expect(await page.locator('[data-vista-scroll="gestion-diaria"]').evaluate(n => n.scrollHeight <= n.clientHeight + 1 && n.scrollWidth <= n.clientWidth + 1)).toBe(true)
  }
  // Con la ficha al lado, Primer intento y Dispersión se desplazan dentro de la tabla, no la página.
  await page.setViewportSize({ width: 1366, height: 768 })
  await expect(ficha).toBeVisible()
  const columnas = vista.getByRole('region', { name: 'Desplazar tabla de equipos', exact: true })
  await columnas.focus(); await columnas.press('ArrowRight')
  await expect.poll(() => columnas.evaluate(n => n.scrollLeft)).toBeGreaterThan(0)
  await columnas.evaluate(n => { n.scrollTop = n.scrollHeight; n.scrollLeft = n.scrollWidth })
  // La cabecera pegada sigue encima de las filas; se mira la última columna, la que queda a la vista.
  const encabezado = columnas.getByRole('columnheader').last()
  await page.screenshot({ path: info.outputPath('gerencia-tabla-desplazada.png'), fullPage: true })
  await expect.poll(() => encabezado.evaluate(n => {
    const r = n.getBoundingClientRect()
    return Boolean(document.elementFromPoint(r.x + 16, r.bottom - 8)?.closest('thead'))
  })).toBe(true)
  await page.getByRole('button', { name: 'Ordenar equipos por dispersión', exact: true }).focus()
  await expect(vista.getByRole('button', { name: `Seleccionar ${EQUIPO}`, exact: true })).toBeInViewport()
  await botonCabecera(page, 'Comparar días').click()
  await expect(page.getByRole('table', { name: 'Cifras del día, anterior y referencia' }).getByRole('row')).toHaveCount(9)
  await page.screenshot({ path: info.outputPath('gerencia-comparacion.png'), fullPage: true })
  await page.keyboard.press('Escape')
  await expect(botonCabecera(page, 'Comparar días')).toBeFocused()

  // Dentro del equipo la ficha va al lado desde 1100 px: con el menú fijado, un portátil de 1440.
  await page.setViewportSize({ width: 1440, height: 900 })
  const margen = 1440 - await raizOperacion(page).evaluate(n => n.clientWidth)
  const equipo = await entrarAlEquipo(page)
  const tablaAnalistas = equipo.getByRole('table', { name: 'Actividad y pendientes por analista' })
  await equipo.getByRole('button', { name: `Seleccionar a ${analista.nombre_completo}`, exact: true }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  const detalle = equipo.getByRole('region', { name: `Detalle de ${analista.nombre_completo}`, exact: true })
  await expect(detalle).toBeVisible()
  const cajaTabla = (await tablaAnalistas.boundingBox())!
  expect((await detalle.boundingBox())!.x).toBeGreaterThanOrEqual(cajaTabla.x + cajaTabla.width)
  expect(await tablaAnalistas.locator('tbody tr').first().evaluate(n => getComputedStyle(n).display)).toBe('table-row')
  await page.screenshot({ path: info.outputPath('gerencia-analista-horizontal.png'), fullPage: true })
  // Umbral exacto dentro del equipo: 1100 px en línea, 1099 en ventana.
  const raizEquipo = page.locator(`section[aria-label="${EQUIPO}"]`)
  await page.setViewportSize({ width: EN_LINEA_EQUIPO + margen, height: 900 })
  await expect.poll(() => raizEquipo.evaluate(n => n.clientWidth)).toBe(EN_LINEA_EQUIPO)
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(detalle).toBeVisible()
  await page.setViewportSize({ width: EN_LINEA_EQUIPO - 1 + margen, height: 900 })
  await expect.poll(() => raizEquipo.evaluate(n => n.clientWidth)).toBe(EN_LINEA_EQUIPO - 1)
  await expect(page.getByRole('dialog', { name: `Detalle de ${analista.nombre_completo}`, exact: true })).toBeVisible()
  await page.setViewportSize({ width: 1440, height: 900 })
  await expect(page.getByRole('dialog')).toHaveCount(0)

  await page.getByRole('tab', { name: 'Hábitos del equipo', exact: true }).click()
  await page.getByRole('button', { name: `Ver hábitos de ${analista.nombre_completo}`, exact: true }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  // Hábitos va al lado desde 1040 px de operación. A 1440 con el menú fijado la operación mide
  // ~1150: el tramo 1040–1235 donde antes la ficha se apilaba bajo la tabla (arreglado en G3).
  await page.setViewportSize({ width: 1440, height: 900 })
  await expect(page.getByRole('dialog')).toHaveCount(0)
  const habitos = await page.getByRole('region', { name: 'Comparación de hábitos', exact: true }).boundingBox()
  const detalleHabitos = await page.getByRole('region', { name: 'Detalle de hábitos', exact: true }).boundingBox()
  expect(detalleHabitos!.x).toBeGreaterThanOrEqual(habitos!.x + habitos!.width)
  await page.screenshot({ path: info.outputPath('gerencia-habitos-horizontal.png'), fullPage: true })
  // Umbral exacto de la operación, que también rige Hábitos: 1040 px en línea, 1039 en ventana.
  await page.setViewportSize({ width: EN_LINEA_OPERACION + margen, height: 700 })
  await expect.poll(() => raizOperacion(page).evaluate(n => n.clientWidth)).toBe(EN_LINEA_OPERACION)
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page.getByRole('region', { name: 'Detalle de hábitos', exact: true })).toBeVisible()
  await page.setViewportSize({ width: EN_LINEA_OPERACION - 1 + margen, height: 700 })
  await expect.poll(() => raizOperacion(page).evaluate(n => n.clientWidth)).toBe(EN_LINEA_OPERACION - 1)
  await expect(page.getByRole('dialog', { name: analista.nombre_completo!, exact: true })).toBeVisible()
})

test('F5 escritorio: operación, equipo, analista, registro, ficha y vuelta con contexto', async ({ page }, info) => {
  const estado = await montar(page)
  const vista = operacion(page)
  // «Toda la operación» al pie de la tabla; la comparación con el día anterior y la referencia, en «Comparar días».
  await expect(vista.getByRole('button', { name: '1008 tareas vencidas en toda la operación: ver los equipos con vencidas', exact: true })).toBeVisible()
  await botonCabecera(page, 'Comparar días').click()
  await expect(page.getByRole('dialog', { name: 'Comparación de la operación' })).toContainText('Referencia: 7 de 7 jornadas con actividad')
  await page.keyboard.press('Escape')
  await page.screenshot({ path: info.outputPath('f5-operacion-escritorio.png'), fullPage: true })
  // Con el teclado: la fila elige el equipo, la flecha lleva a su ficha y «Ver el equipo» entra.
  const filaEquipo = vista.getByRole('button', { name: `Seleccionar ${EQUIPO}`, exact: true })
  await filaEquipo.focus()
  await filaEquipo.press('Enter')
  await expect(filaEquipo).toHaveAttribute('aria-current', 'true')
  await expect(filaEquipo).toBeFocused()
  await vista.getByRole('button', { name: `Ir al detalle de ${EQUIPO}`, exact: true }).press('Enter')
  const fichaEquipo = vista.getByRole('region', { name: `Detalle del ${EQUIPO}`, exact: true })
  await expect(fichaEquipo.getByRole('heading', { name: `Detalle del ${EQUIPO}`, exact: true })).toBeFocused()
  await fichaEquipo.getByRole('button', { name: 'Ver el equipo', exact: true }).press('Enter')
  await expect(page).toHaveURL(new RegExp(`/gestion-diaria/equipo/${grupo.clave}$`))
  const equipo = vista.getByRole('region', { name: EQUIPO, exact: true })
  await expect(equipo.getByRole('heading', { level: 3, name: EQUIPO, exact: true })).toBeFocused()
  await page.screenshot({ path: info.outputPath('f5-equipo-escritorio.png'), fullPage: true })
  const buscar = equipo.getByRole('searchbox', { name: 'Buscar analista', exact: true })
  await buscar.fill(analista.nombre_completo!)
  const fila = equipo.getByRole('button', { name: `Seleccionar a ${analista.nombre_completo}`, exact: true })
  await fila.click()
  await expect(page).toHaveURL(new RegExp(`/gestion-diaria/analista/${analista.analista_id}$`))
  await expect(fila).toBeFocused()
  const detalle = equipo.getByRole('region', { name: `Detalle de ${analista.nombre_completo}`, exact: true })
  await equipo.getByRole('button', { name: `Ir al detalle de ${analista.nombre_completo}`, exact: true }).click()
  await expect(detalle.getByRole('heading', { name: `Detalle de ${analista.nombre_completo}`, exact: true })).toBeFocused()
  await detalle.getByRole('tab', { name: 'Registro', exact: true }).click()
  await expect(detalle).toContainText(`Llamada ficticia F5 del ${DIA}`)
  expect(estado.registros.some((r) => r.p_desde === DIA && JSON.stringify(r.p_analista_ids) === JSON.stringify([analista.analista_id]))).toBe(true)
  await detalle.getByRole('button', { name: cliente.nombre_completo, exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/analista/${analista.analista_id}/lead/${cliente.id}$`))
  await expect(page.getByRole('heading', { name: cliente.nombre_completo, exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Cerrar ficha', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/analista/${analista.analista_id}$`))
  await expect(page.getByLabel('Día de la operación', { exact: true })).toHaveValue(DIA)
  await expect(detalle).toContainText(`Llamada ficticia F5 del ${DIA}`)
  await expect(buscar).toHaveValue(analista.nombre_completo!)
  await page.goBack()
  await expect(page.getByRole('heading', { name: cliente.nombre_completo, exact: true })).toBeVisible()
  await page.goForward()
  await expect(detalle).toBeVisible()
  await page.screenshot({ path: info.outputPath('f5-analista-escritorio.png'), fullPage: true })
})

test('F5 móvil: fecha, recarga y enlace directo sin desbordamiento', async ({ page }, info) => {
  const estado = await montar(page)
  const vista = operacion(page)
  // Ninguna pastilla se sale de su fila (se mide el texto, no la caja del bloque).
  for (const width of [390, 360, 320]) {
    await page.setViewportSize({ width, height: 844 })
    await expect.poll(() => vista.getByRole('group', { name: 'Resumen de la operación', exact: true }).locator('xpath=..').evaluateAll(casillas =>
      casillas.flatMap(casilla => Array.from(casilla.children).filter(n => {
        const caja = casilla.getBoundingClientRect(), rango = document.createRange()
        rango.selectNodeContents(n)
        const texto = rango.getBoundingClientRect()
        return texto.left < caja.left - 0.5 || texto.right > caja.right + 0.5
      }).map(n => n.textContent)),
    )).toEqual([])
  }
  await page.setViewportSize({ width: 390, height: 844 })
  await page.mouse.move(380, 80)
  const dia = page.getByLabel('Día de la operación', { exact: true })
  // La fecha se aplica al completarse (ya no hay «Consultar» ni Enter).
  await dia.fill('2026-09-22')
  await expect.poll(() => estado.dias.at(-1)).toBe('2026-09-22')
  await expect(vista).toContainText('El martes, 22 de setiembre frente al día anterior')
  await botonCabecera(page, 'Comparar días').click()
  await expect(page.getByRole('dialog', { name: 'Comparación de la operación' })).toContainText('Anterior: 2026-09-21 completo')
  await page.keyboard.press('Escape')
  // En el celular la ficha del equipo se abre en una ventana; «Ver el equipo» entra por la ruta.
  await vista.getByRole('button', { name: `Seleccionar ${EQUIPO}`, exact: true }).click()
  const ventanaEquipo = page.getByRole('dialog', { name: `Detalle del ${EQUIPO}`, exact: true })
  await expect(ventanaEquipo).toBeVisible()
  await ventanaEquipo.getByRole('button', { name: 'Ver el equipo', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/equipo/${grupo.clave}$`))
  await page.reload()
  // Los portales se alojan fuera del workspace; esperar también su salida del splash.
  await expect.poll(() => page.locator('main').evaluate((n) => n.closest('[inert]') === null)).toBe(true)
  await expect(page).toHaveURL(new RegExp(`/equipo/${grupo.clave}$`))
  const equipo = vista.getByRole('region', { name: EQUIPO, exact: true })
  await expect(equipo.getByRole('heading', { level: 3, name: EQUIPO, exact: true })).toBeVisible()
  // Sin selección automática en el celular: el enlace directo no abre ninguna ventana.
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(dia).toHaveValue('2026-09-22')
  await dia.fill('2026-09-21')
  await expect.poll(() => estado.dias.at(-1)).toBe('2026-09-21')
  await expect(dia).toBeFocused()
  await expect(equipo.getByRole('heading', { level: 3, name: EQUIPO, exact: true })).toBeVisible()
  await equipo.getByRole('heading', { level: 3, name: EQUIPO, exact: true }).scrollIntoViewIfNeeded()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: info.outputPath('f5-equipo-movil.png'), fullPage: true })
  const fila = equipo.getByRole('button', { name: `Seleccionar a ${analista.nombre_completo}`, exact: true })
  await fila.click()
  const ventanaAnalista = page.getByRole('dialog', { name: `Detalle de ${analista.nombre_completo}`, exact: true })
  await expect(ventanaAnalista).toBeVisible()
  await ventanaAnalista.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/equipo/${grupo.clave}$`))
  await expect(fila).toBeFocused()
  await equipo.getByRole('navigation', { name: 'Ruta de la operación' }).getByRole('link', { name: 'Toda la operación', exact: true }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria$/)
  await expect(vista.getByRole('button', { name: `Seleccionar ${EQUIPO}`, exact: true })).toBeFocused()
  await vista.getByRole('heading', { level: 2, name: 'Toda la operación', exact: true }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath('f5-operacion-movil.png'), fullPage: true })
})

test('F5 hábitos: períodos reales de 7/14/30, hueco, comparación y cortes sin activar umbral', async ({ page }, info) => {
  const estado = await montar(page)
  await page.getByRole('tab', { name: 'Hábitos del equipo', exact: true }).click()
  const informe = page.getByRole('region', { name: 'Reporte de hábitos', exact: true })
  await expect(informe).toContainText('14 días calendario')
  await page.getByLabel(`Período hasta ${DIA}`, { exact: true }).selectOption('7')
  await expect(informe).toContainText('7 días calendario')
  await informe.getByRole('button', { name: `Ver hábitos de ${analista.nombre_completo}`, exact: true }).click()
  await informe.getByText(`Ver días de ${analista.nombre_completo}`, { exact: true }).click()
  await expect(informe.getByRole('table', { name: `Hábitos diarios de ${analista.nombre_completo}` })).toContainText('165 min')
  await informe.getByRole('button', { name: 'Cómo leer los hábitos', exact: true }).click()
  await expect(page.getByRole('dialog')).toContainText('La alerta de tasa muy baja sigue apagada')
  await page.getByRole('button', { name: 'Cerrar explicación', exact: true }).click()
  await page.screenshot({ path: info.outputPath('f5-habitos.png'), fullPage: true })
  await informe.getByRole('table', { name: `Hábitos diarios de ${analista.nombre_completo}` }).getByRole('row', { name: new RegExp(DIA) }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath('f5-habitos-hueco.png'), fullPage: true })
  await page.getByLabel(`Período hasta ${DIA}`, { exact: true }).selectOption('30')
  await expect(informe).toContainText('30 días calendario')
  expect(estado.periodos).toEqual(expect.arrayContaining([7, 14, 30]))
  await informe.getByRole('button', { name: `Ver hábitos de ${analista.nombre_completo}`, exact: true }).click()
  await informe.getByRole('link', { name: 'Ver pulso y registro', exact: true }).click()
  // «Ver pulso y registro» lleva a la ficha del analista dentro de su equipo.
  await expect(page).toHaveURL(new RegExp(`/gestion-diaria/analista/${analista.analista_id}$`))
  await expect(operacion(page).getByRole('region', { name: EQUIPO, exact: true })
    .getByRole('region', { name: `Detalle de ${analista.nombre_completo}`, exact: true })).toBeVisible()
})

test('F5 error y revocación ocultan datos; recuperación vuelve a consultar', async ({ page }) => {
  const estado = await montar(page)
  const vista = operacion(page)
  // Con el registro general abierto, para comprobar que el error también lo retira.
  await botonCabecera(page, 'Registro general').click()
  await expect(vista.getByRole('region', { name: 'Registro general', exact: true })).toContainText(`Llamada ficticia F5 del ${DIA}`)
  estado.error = true
  await botonCabecera(page, 'Actualizar').click()
  const alerta = vista.getByRole('alert')
  await expect(alerta).toContainText('datos anteriores se han ocultado')
  await expect(page.getByRole('table', { name: 'Equipos de la operación' })).toHaveCount(0)
  await expect(vista.getByRole('rowheader', { name: /^Toda la operación/ })).toHaveCount(0)
  await expect(vista.getByRole('region', { name: 'Registro general', exact: true })).toHaveCount(0)
  estado.error = false
  await alerta.getByRole('button', { name: 'Reintentar', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Equipos de la operación' })).toBeVisible()
  estado.revocado = true
  await botonCabecera(page, 'Actualizar').click()
  await expect(alerta).toContainText('ya no tiene permiso')
  await expect(page.getByRole('table')).toHaveCount(0)
})

test('F5 conserva la fila fuera de equipos y exportación del registro cargado', async ({ page }) => {
  await montar(page)
  const vista = operacion(page)
  const filas = vista.getByRole('table', { name: 'Equipos de la operación' }).getByRole('button', { name: /^Seleccionar / })
  // El grupo sin supervisor no compite con los equipos: siempre al final.
  await expect(filas.last()).toHaveAccessibleName('Seleccionar Fuera de equipos comerciales')
  await filas.last().click()
  await vista.getByRole('region', { name: 'Detalle del grupo Fuera de equipos comerciales', exact: true }).getByRole('button', { name: 'Ver el equipo', exact: true }).click()
  await expect(page).toHaveURL(/\/gestion-diaria\/equipo\/fuera$/)
  const fuera = vista.getByRole('region', { name: 'Fuera de equipos comerciales', exact: true })
  await expect(fuera).toContainText('Sin autor: 1 llamadas')
  // Los registros sin autor se consultan en el registro general.
  await fuera.getByRole('button', { name: 'Ver registros sin autor en el registro general', exact: true }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria$/)
  const general = vista.getByRole('region', { name: 'Registro general', exact: true })
  await expect(general).toContainText(`Llamada ficticia F5 del ${DIA}`)
  const descarga = page.waitForEvent('download')
  await general.getByRole('button', { name: /Exportar/ }).click()
  expect((await descarga).suggestedFilename()).toContain(DIA)
})

test('F6 gerencia: densidad, filtros y registro permanecen al ampliar, redimensionar y volver', async ({ page }, info) => {
  const estado = await montar(page)
  estado.paginado = true
  const vista = operacion(page)
  // Las cifras de «Toda la operación» (pie de la tabla) no cambian al filtrar equipos.
  const total = vista.getByRole('table', { name: 'Equipos de la operación' }).locator('tfoot tr')
  // Se toma la foto con el detalle ya llegado (atención y nivel de contacto), no mientras consulta.
  await expect(total).not.toContainText('Consultando')
  const valores = await total.textContent()
  await expect(vista).toHaveAttribute('data-estrecho', 'false')
  expect(await page.locator('[data-vista-scroll="gestion-diaria"]').evaluate((n) => n.scrollHeight <= n.clientHeight + 1)).toBe(true)
  const equipos = vista.getByRole('table', { name: 'Equipos de la operación' })
  const ultimaFila = await equipos.locator('tbody tr').last().boundingBox()
  const tabla = await vista.getByRole('region', { name: 'Desplazar tabla de equipos', exact: true }).boundingBox()
  expect(ultimaFila!.y + ultimaFila!.height).toBeLessThanOrEqual(tabla!.y + tabla!.height + 1)
  const buscarEquipo = vista.getByRole('searchbox', { name: 'Buscar equipo', exact: true })
  await buscarEquipo.fill(grupo.nombre)
  await expect(equipos.locator('tbody tr')).toHaveCount(1)
  await expect(total).toHaveText(valores!)
  await equipos.getByRole('button', { name: `Seleccionar ${EQUIPO}`, exact: true }).click()
  const equipo = await entrarAlEquipo(page)
  const buscar = equipo.getByRole('searchbox', { name: 'Buscar analista', exact: true })
  await buscar.fill(analista.nombre_completo!)
  const seleccionar = equipo.getByRole('button', { name: `Seleccionar a ${analista.nombre_completo}`, exact: true })
  await seleccionar.click()
  const panel = page.getByRole('region', { name: `Detalle de ${analista.nombre_completo}`, exact: true })
  const ventana = page.getByRole('dialog', { name: `Detalle de ${analista.nombre_completo}`, exact: true })
  await panel.getByRole('tab', { name: 'Registro', exact: true }).click()
  const registro = panel.getByRole('region', { name: 'Registro seleccionado', exact: true })
  // El filtro del registro compacto de la ficha es la pastilla de tipo (sin selector de etapa).
  const llamadas = registro.getByRole('tab', { name: 'Llamadas', exact: true })
  await llamadas.click()
  await expect(registro).toContainText(`Llamada ficticia F5 del ${DIA}`)
  await expect(registro.getByRole('listitem')).toHaveCount(25)
  await registro.getByRole('button', { name: 'Ver más', exact: true }).click()
  await expect(registro.getByRole('listitem')).toHaveCount(26)
  await panel.getByRole('button', { name: 'Ampliar panel', exact: true }).click()
  await expect(ventana).toBeVisible()
  await expect(llamadas).toHaveAttribute('aria-selected', 'true')
  await expect(registro.getByRole('listitem')).toHaveCount(26)
  await registro.getByRole('button', { name: cliente.nombre_completo, exact: true }).first().click()
  await expect(page.getByRole('heading', { name: cliente.nombre_completo, exact: true })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('heading', { name: cliente.nombre_completo, exact: true })).toHaveCount(0)
  await expect(ventana).toBeVisible()
  await expect(registro.getByRole('listitem')).toHaveCount(26)
  await page.screenshot({ path: info.outputPath('f6-registro-ampliado.png'), fullPage: true })
  await panel.getByRole('button', { name: 'Restaurar panel', exact: true }).click()
  await page.setViewportSize({ width: 1000, height: 900 })
  await expect(ventana).toBeVisible()
  await expect(llamadas).toHaveAttribute('aria-selected', 'true')
  await expect(registro.getByRole('listitem')).toHaveCount(26)
  await page.setViewportSize({ width: 1512, height: 900 })
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(llamadas).toHaveAttribute('aria-selected', 'true')
  await expect(registro.getByRole('listitem')).toHaveCount(26)
  // Volver: cerrar la ficha devuelve el foco a su fila, con la búsqueda del equipo intacta.
  await panel.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  await expect(seleccionar).toBeFocused()
  await expect(buscar).toHaveValue(analista.nombre_completo!)
  // «Registro general» sale a la operación, que conserva su búsqueda de equipos.
  await botonCabecera(page, 'Registro general').click()
  await expect(page).toHaveURL(/#\/gestion-diaria$/)
  const general = vista.getByRole('region', { name: 'Registro general', exact: true })
  await expect(general).toBeVisible()
  await expect(buscarEquipo).toHaveValue(grupo.nombre)
  await general.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  await expect(botonCabecera(page, 'Registro general')).toBeFocused()
  // Atrás vuelve al equipo con su búsqueda; la miga regresa a la operación, enfocando la fila del equipo.
  await page.goBack()
  await expect(page).toHaveURL(new RegExp(`/gestion-diaria/equipo/${grupo.clave}$`))
  await expect(buscar).toHaveValue(analista.nombre_completo!)
  await equipo.getByRole('navigation', { name: 'Ruta de la operación' }).getByRole('link', { name: 'Toda la operación', exact: true }).click()
  await expect(buscarEquipo).toHaveValue(grupo.nombre)
  await expect(equipos.getByRole('button', { name: `Seleccionar ${EQUIPO}`, exact: true })).toBeFocused()
})

test('F6 hábitos: búsqueda, selección por teclado y móvil conservan el día abierto', async ({ page }, info) => {
  await montar(page)
  await page.getByRole('tab', { name: 'Hábitos del equipo', exact: true }).click()
  const buscar = page.getByRole('searchbox', { name: 'Buscar analista en hábitos', exact: true })
  await buscar.fill(analista.nombre_completo!)
  const seleccion = page.getByRole('button', { name: `Ver hábitos de ${analista.nombre_completo}`, exact: true })
  await seleccion.focus(); await seleccion.press('Enter')
  await expect(seleccion).toBeFocused()
  await page.getByRole('button', { name: `Ir al detalle de hábitos de ${analista.nombre_completo}` }).click()
  const panel = page.getByRole('region', { name: 'Detalle de hábitos', exact: true })
  await expect(panel.getByRole('heading', { name: analista.nombre_completo!, exact: true })).toBeFocused()
  await panel.getByText(`Ver días de ${analista.nombre_completo}`, { exact: true }).click()
  await expect(panel.locator('details')).toHaveAttribute('open', '')
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(page.getByRole('dialog', { name: analista.nombre_completo!, exact: true })).toBeVisible()
  await expect(panel.locator('details')).toHaveAttribute('open', '')
  expect(await panel.evaluate((n) => n.scrollWidth <= n.clientWidth)).toBe(true)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: info.outputPath('f6-habitos-movil.png'), fullPage: true })
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(seleccion).toBeFocused()
  await expect(buscar).toHaveValue(analista.nombre_completo!)
  await buscar.focus()
  await seleccion.click()
  await panel.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  await expect(seleccion).toBeFocused()
  await buscar.fill('NO EXISTE')
  await expect(page.getByRole('table', { name: 'Comparación de hábitos por analista' })).toContainText('Ningún analista coincide')
})

for (const ambito of ['general', 'analista']) test(`F6 una revocación del registro ${ambito} oculta Pulso y Hábitos hasta verificar la sesión`, async ({ page }) => {
  const estado = await montar(page)
  const vista = operacion(page)
  let registro: Locator
  if (ambito === 'general') {
    await botonCabecera(page, 'Registro general').click()
    registro = vista.getByRole('region', { name: 'Registro general', exact: true }).getByRole('region', { name: 'Registro seleccionado', exact: true })
  } else {
    const equipo = await entrarAlEquipo(page)
    await equipo.getByRole('button', { name: `Seleccionar a ${analista.nombre_completo}`, exact: true }).click()
    const ficha = equipo.getByRole('region', { name: `Detalle de ${analista.nombre_completo}`, exact: true })
    await ficha.getByRole('tab', { name: 'Registro', exact: true }).click()
    registro = ficha.getByRole('region', { name: 'Registro seleccionado', exact: true })
  }
  await expect(registro).toContainText(`Llamada ficticia F5 del ${DIA}`)
  estado.registroRevocado = true
  // Los dos registros son compactos (como el supervisor), sin «Actualizar» propio: la consulta
  // nueva la pide su pastilla de tipo (un control que también desaparece).
  await registro.getByRole('tab', { name: 'Llamadas', exact: true }).click()
  await expect(vista.getByRole('alert').filter({ hasText: 'ya no tiene permiso' })).toBeVisible()
  await expect(page.getByRole('table')).toHaveCount(0)
  await expect(registro).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Verificar sesión', exact: true })).toBeFocused()
  await page.getByRole('tab', { name: 'Hábitos del equipo', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Verificar sesión', exact: true })).toBeVisible()
  await expect(page.getByRole('table')).toHaveCount(0)
  estado.registroRevocado = false
  await page.getByRole('button', { name: 'Verificar sesión', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Equipos de la operación' })).toBeVisible()
})

test('F6 al ampliar desde móvil aparece el equipo seleccionado y su detalle', async ({ page }) => {
  await montar(page)
  // Otro equipo que el que la selección automática abriría al ampliar: así se prueba la elección del usuario.
  const otro = `Equipo de ${fixture.pulso.equipos.find((e) => e.clave !== grupo.clave && e.clave !== 'fuera' && e.metricas.llamadas > 0)!.nombre}`
  await page.setViewportSize({ width: 390, height: 844 })
  await operacion(page).getByRole('button', { name: `Seleccionar ${otro}`, exact: true }).click()
  // En el celular, la ficha del equipo elegido se abre en una ventana.
  await expect(page.getByRole('dialog', { name: `Detalle del ${otro}`, exact: true })).toBeVisible()
  await page.setViewportSize({ width: 1512, height: 900 })
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(operacion(page).getByRole('region', { name: `Detalle del ${otro}`, exact: true })
    .getByRole('heading', { name: `Detalle del ${otro}`, exact: true })).toBeVisible()
})
