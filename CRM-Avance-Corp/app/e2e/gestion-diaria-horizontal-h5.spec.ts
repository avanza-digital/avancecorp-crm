import { responderRegistroV2 } from './_gestiones-v2'
import { expect, test } from '@playwright/test'
import { writeFile } from 'node:fs/promises'
import { loginReal, montarBackendReal, UID } from './_helpers'
import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'
import { fechaLima } from '../src/lib/agenda-derivada'

// El tamaño del equipo no debe producir una lectura de actividad por fila.
// Se mide la app completa, con los proveedores y adaptadores reales.
test('H5: consultas iguales con 1 y 32 analistas, bajo demanda y panel estable', async ({ browser, baseURL }, info) => {
  const resultados: { cantidad: number; lecturas: unknown; etapas: Record<string, Record<string, number>> }[] = []
  for (const cantidad of [1, 32]) {
    const page = await browser.newPage({ baseURL })
    // Ambos tamaños arrancan en el módulo medido. Pasar antes por «Hoy»
    // mezcla sus consultas y refrescos de arranque con el coste de este equipo.
    await page.addInitScript(() => {
      window.history.replaceState(null, '', '/#/gestion-diaria')
    })
    const peticiones: Record<string, number> = {}
    const etapas: Record<string, Record<string, number>> = {}
    page.on('request', solicitud => {
      const ruta = new URL(solicitud.url()).pathname
      if (ruta.startsWith('/rest/v1/')) {
        const clave = `${solicitud.method()} ${ruta}`
        peticiones[clave] = (peticiones[clave] ?? 0) + 1
      }
    })
    const medir = async (etapa: string) => {
      // Tras confirmar la UI esperamos también las solicitudes disparadas por efectos.
      await page.waitForLoadState('networkidle')
      etapas[etapa] = { ...peticiones }
    }
    await page.setViewportSize({ width: 1512, height: 805 })
    await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
    const instante = '2026-09-24T15:00:00.000Z'
    await page.clock.install({ time: new Date(instante) })
    const dia = fechaLima(Date.parse(instante))
    const idAnalista = (i: number) => `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`
    const filas = Array.from({ length: cantidad }, (_, i) => filaEquipoPrueba({
      analista_id: idAnalista(i), nombre_completo: `ANALISTA ${String(i + 1).padStart(2, '0')}`,
    }))
    const equipo = { ...diaEquipoPrueba(filas), dia, supervisor_id: UID }
    const lecturas = { equipo: 0, registro: 0, pendientes: 0 }
    const pedidosRegistro: Record<string, unknown>[] = []
    let falloEquipo = false
    await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', route => {
      lecturas.equipo++
      return falloEquipo
        ? route.fulfill({ status: 500, json: { code: 'XX000', message: 'Interrupción temporal de prueba' } })
        : route.fulfill({ json: equipo })
    })
    await page.route('**/rest/v1/rpc/registro_actividad_v2_fn', route => {
      lecturas.registro++
      pedidosRegistro.push(route.request().postDataJSON())
      return responderRegistroV2(route, { json: { version: 1, zona: 'America/Lima', desde: dia, hasta: dia,
        generado_en: instante, limite: 26, items: [] } })
    })
    await page.route('**/rest/v1/rpc/gestion_diaria_pendientes_v2_fn', route => {
      lecturas.pendientes++
      return route.fulfill({ status: 500, json: { code: 'XX000', message: 'No se debe consultar una pestaña no visitada' } })
    })
    await loginReal(page)
    await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
    await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
    await page.mouse.move(900, 90)
    const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
    await expect(vista).toHaveAttribute('data-estrecho', 'false')
    await expect(vista.locator('tr[data-analista]')).toHaveCount(cantidad)
    await medir('inicio')
    expect(lecturas).toEqual({ equipo: 1, registro: 0, pendientes: 0 })
    const indicadores = await vista.getByRole('group', { name: 'Resumen del equipo' }).textContent()
    await vista.getByRole('button', { name: 'Ordenar por analista' }).click()
    await vista.getByRole('searchbox').fill('ANALISTA 01')
    await expect(vista.locator('tr[data-analista]')).toHaveCount(1)
    await expect(vista.getByRole('group', { name: 'Resumen del equipo' })).toHaveText(indicadores!)
    await medir('filtrar')
    expect(lecturas).toEqual({ equipo: 1, registro: 0, pendientes: 0 })
    await vista.getByRole('button', { name: 'Seleccionar a ANALISTA 01' }).click()
    const panel = page.getByRole('region', { name: 'Detalle de ANALISTA 01', exact: true })
    await expect(panel.getByText('No hay gestiones visibles de este analista en el día.')).toBeVisible()
    await medir('seleccionar')
    expect(lecturas).toEqual({ equipo: 1, registro: 1, pendientes: 0 })
    await panel.getByRole('tab', { name: 'Registro', exact: true }).click()
    await expect(panel.getByRole('region', { name: 'Registro seleccionado' })).toBeVisible()
    await medir('registro')
    expect(lecturas.registro).toBe(1)
    await panel.getByRole('tab', { name: 'Resumen', exact: true }).click()
    await panel.getByRole('tab', { name: 'Registro', exact: true }).click()
    await medir('alternar')
    expect(lecturas.registro).toBe(1)
    falloEquipo = true
    await vista.locator(':scope > header').getByRole('button', { name: 'Actualizar', exact: true }).click()
    await expect(vista.getByRole('alert')).toContainText('No pudimos consultar la actividad')
    await expect(panel.getByRole('tab', { name: 'Registro', exact: true })).toHaveAttribute('aria-selected', 'true')
    await expect(panel.getByRole('region', { name: 'Registro seleccionado' })).toBeVisible()
    await medir('refrescar')
    expect(lecturas.registro).toBe(2)
    falloEquipo = false
    await vista.getByRole('button', { name: 'Reintentar', exact: true }).click()
    await expect(vista.getByRole('table')).toBeVisible()
    await expect(vista.getByRole('searchbox')).toHaveValue('ANALISTA 01')
    await expect(panel.getByRole('tab', { name: 'Registro', exact: true })).toHaveAttribute('aria-selected', 'true')
    await medir('recuperar')
    expect(lecturas.pendientes).toBe(0)
    expect(lecturas.registro).toBe(2)
    for (const pedido of pedidosRegistro) expect(pedido).toMatchObject({ p_analista_ids: [idAnalista(0)], p_desde: dia, p_hasta: dia })
    resultados.push({ cantidad, lecturas, etapas })
    await page.close()
  }
  await writeFile(info.outputPath('consultas-h5.json'), JSON.stringify(resultados, null, 2))
  // Los proveedores se refrescan en paralelo: la foto intermedia de error
  // puede anteceder a postventa. La recuperación confirma el ciclo completo.
  for (const etapa of ['inicio', 'filtrar', 'seleccionar', 'registro', 'alternar', 'recuperar']) {
    expect(resultados[1]!.etapas[etapa]).toEqual(resultados[0]!.etapas[etapa])
  }
})

test('H5: Actualizar conserva el filtro del registro del equipo y consulta una sola primera página', async ({ page }) => {
  await page.setViewportSize({ width: 1512, height: 805 })
  const instante = '2026-09-24T15:00:00.000Z', dia = fechaLima(Date.parse(instante))
  await page.clock.install({ time: new Date(instante) })
  await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', route => route.fulfill({
    json: { ...diaEquipoPrueba([filaEquipoPrueba()]), dia, supervisor_id: UID },
  }))
  const pedidos: Record<string, unknown>[] = []
  const items = Array.from({ length: 26 }, (_, i) => ({
    id: `00000000-0000-4000-8000-${String(i + 100).padStart(12, '0')}`,
    lead_id: '00000000-0000-4000-8000-000000000099', lead_nombre: 'LEAD SINTÉTICO H5',
    lead_etapa: 'nuevo', etapa_en_ese_momento: 'nuevo', tipo: 'llamada_realizada',
    detalle: `Conversación ${i}`, metadata: {}, creado_por: UID, autor_nombre: 'ANALISTA H5',
    creado_en: `${dia}T14:${String(25 - i).padStart(2, '0')}:00.000Z`,
  }))
  await page.route('**/rest/v1/rpc/registro_actividad_v2_fn', async route => {
    const pedido = route.request().postDataJSON(); pedidos.push(pedido)
    // Mantiene en vuelo la petición para detectar si el efecto la cancela y duplica.
    await new Promise(resolve => setTimeout(resolve, 100))
    return responderRegistroV2(route, { json: { version: 1, zona: 'America/Lima', desde: dia, hasta: dia,
      generado_en: instante, limite: 26, items: pedido.p_antes_de ? items.slice(25) : items } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  await page.mouse.move(900, 90)
  const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  await vista.getByRole('button', { name: 'Registro del equipo', exact: true }).click()
  const registro = page.getByRole('region', { name: 'Registro seleccionado', exact: true })
  await registro.getByRole('tab', { name: 'Llamadas', exact: true }).click()
  await expect(registro.getByRole('listitem')).toHaveCount(25)
  await registro.getByRole('button', { name: 'Ver más', exact: true }).click()
  await expect(registro.getByRole('listitem')).toHaveCount(26)
  await page.waitForLoadState('networkidle')
  const anteriores = pedidos.length
  await vista.locator(':scope > header').getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(registro.getByRole('listitem')).toHaveCount(25)
  await expect(registro.getByRole('tab', { name: 'Llamadas', exact: true })).toHaveAttribute('aria-selected', 'true')
  await page.waitForLoadState('networkidle')
  expect(pedidos.slice(anteriores)).toHaveLength(1)
  expect(pedidos.at(-1)).toMatchObject({ p_tipos: ['llamada_realizada', 'llamada_no_contestada'] })
  expect(pedidos.at(-1)?.p_antes_de ?? null).toBeNull()
})
