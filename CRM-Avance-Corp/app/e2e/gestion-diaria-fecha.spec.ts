import { responderRegistroV2 } from './_gestiones-v2'
import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal, UID } from './_helpers'
import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'

for (const ancho of [1512, 390]) {
  test(`Supervisor: consulta por fecha y vuelta a hoy en ${ancho}px`, async ({ page }, info) => {
    const hoy = '2026-09-24', anterior = '2026-09-10', instante = `${hoy}T15:00:00.000Z`
    const analista = '00000000-0000-4000-8000-000000000010'
    await page.setViewportSize({ width: 1512, height: 844 })
    await page.clock.install({ time: new Date(instante) })
    await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
    const fechas: string[] = []
    const registros: Record<string, unknown>[] = []
    await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', route => {
      const { p_dia, p_supervisor_id } = route.request().postDataJSON()
      expect(p_supervisor_id).toBe(UID)
      fechas.push(p_dia)
      const llamadas = p_dia === hoy ? 9 : 2
      const fila = filaEquipoPrueba({ analista_id: analista, gestiones_hoy: llamadas,
        marcador: { ...filaEquipoPrueba().marcador, llamadas, utiles: llamadas, contestadas: llamadas,
          tasa_contacto_pct: 100, por_hora: [{ hora: 10, llamadas, contestadas: llamadas }] },
      })
      return route.fulfill({ json: { ...diaEquipoPrueba([fila]), dia: p_dia, supervisor_id: UID, generado_en: instante } })
    })
    await page.route('**/rest/v1/rpc/registro_actividad_v2_fn', route => {
      const pedido = route.request().postDataJSON()
      registros.push(pedido)
      return responderRegistroV2(route, { json: {
        version: 1, zona: 'America/Lima', desde: pedido.p_desde, hasta: pedido.p_hasta, generado_en: instante, limite: 26,
        items: [{ id: `00000000-0000-4000-8000-0000000000${pedido.p_desde === hoy ? '24' : '10'}`,
          lead_id: '00000000-0000-4000-8000-000000000099', lead_nombre: 'LEAD DE PRUEBA', lead_etapa: 'nuevo',
          etapa_en_ese_momento: 'nuevo', tipo: 'nota', detalle: `Gestión del ${pedido.p_desde}`, metadata: {},
          creado_por: analista, autor_nombre: 'ANA PÉREZ', creado_en: `${pedido.p_desde}T15:00:00.000Z` }],
      } })
    })
    await loginReal(page)
    await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
    await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
    await page.setViewportSize({ width: ancho, height: 844 })
    await page.mouse.move(ancho - 20, 80)
    const fecha = page.getByLabel('Fecha de gestión', { exact: true })
    await expect(fecha).toHaveValue(hoy)
    await expect(page.getByRole('row', { name: /ANA PÉREZ/ }).getByText('9', { exact: true })).toBeVisible()
    await page.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' }).click()
    await page.getByRole('tab', { name: 'Registro', exact: true }).click()
    await expect(page.getByRole('region', { name: 'Registro seleccionado' }).getByText(`Gestión del ${hoy}`)).toBeVisible()
    await page.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
    await fecha.fill(anterior)
    await expect(page.getByRole('region', { name: 'Mi equipo por fecha', exact: true })).toBeVisible()
    await expect(page.getByRole('row', { name: /ANA PÉREZ/ }).getByText('2', { exact: true })).toBeVisible()
    await expect(page.getByText(`Gestión del ${hoy}`, { exact: true })).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Cortes y avisos', exact: true })).toHaveCount(0)
    await expect(page.getByText('Actividad del día elegido. El equipo y los pendientes reflejan su estado actual.')).toBeVisible()
    await page.getByRole('button', { name: 'Cortes del día', exact: true }).click()
    await expect(page.getByRole('dialog', { name: 'Cortes del día seleccionado', exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Avisos de cortes', exact: true })).toHaveCount(0)
    await page.getByRole('button', { name: 'Cerrar avisos', exact: true }).click()
    await page.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' }).click()
    await page.getByRole('tab', { name: 'Registro', exact: true }).click()
    await expect(page.getByRole('region', { name: 'Registro seleccionado' }).getByText(`Gestión del ${anterior}`)).toBeVisible()
    expect(registros.at(-1)).toMatchObject({ p_desde: anterior, p_hasta: anterior, p_analista_ids: [analista] })
    await page.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
    await page.getByRole('button', { name: 'Registro del equipo', exact: true }).click()
    await expect(page.getByRole('region', { name: 'Registro seleccionado' }).getByText(`Gestión del ${anterior}`)).toBeVisible()
    expect(registros.at(-1)).toMatchObject({ p_desde: anterior, p_hasta: anterior })
    expect(registros.at(-1)?.p_analista_ids ?? null).toBeNull()
    await page.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
    await fecha.scrollIntoViewIfNeeded()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await page.screenshot({ path: info.outputPath(`fecha-supervisor-${ancho}.png`), fullPage: true })
    await page.getByRole('region', { name: 'Mi equipo por fecha', exact: true }).getByRole('button', { name: 'Hoy', exact: true }).click()
    await expect(fecha).toHaveValue(hoy)
    await expect(page.getByRole('row', { name: /ANA PÉREZ/ }).getByText('9', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Cortes y avisos', exact: true })).toBeVisible()
    expect(fechas).toContain(anterior)
    if (ancho === 1512) {
      await fecha.focus()
      for (let i = 0; i < 3; i++) await fecha.press('ArrowLeft')
      await fecha.press('ArrowRight')
      await fecha.press('ArrowRight')
      // locator.press reenfoca el campo y reinicia el año en Chromium.
      // El teclado escribe sobre el segmento que ya tiene el foco.
      await page.keyboard.type('2025')
      await page.keyboard.press('Tab')
      await expect(fecha).toHaveValue('2025-09-24')
      await expect.poll(() => fechas.at(-1)).toBe('2025-09-24')
    }
  })
}
