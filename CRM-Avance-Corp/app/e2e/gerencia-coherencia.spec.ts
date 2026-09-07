import { expect, test } from '@playwright/test'
import * as v from 'valibot'
import { metricasConversionesDemo } from '../src/lib/demo-inteligencia-comercial'
import { MetricasConversionesSchema } from '../src/lib/metricas-conversiones'
import { loginReal, metricasConversionesReal, montarBackendReal, rankingAgostoReal } from './_helpers'

test('siete hallazgos: conserva el corte mensual, combina fuentes y protege el mes cerrado', async ({ page }, testInfo) => {
  await page.clock.setFixedTime(new Date('2026-09-07T15:00:00.000Z'))
  const foto = rankingAgostoReal()
  await montarBackendReal(page, {
    rolCrm: 'gerencia', rolPortal: 'comercial',
    configuracionMetas: foto.configuracionMetas,
    cumplimientoMetas: foto.cumplimientoMetas,
    metricas: { conversionMensual: foto.conversionMensual, cosecha: foto.cosecha },
  })
  const consultas: Array<{ p_desde: string; p_hasta: string; p_origen: string | null }> = []
  await page.route('**/rest/v1/rpc/metricas_conversiones_fn', async (route) => {
    const consulta = route.request().postDataJSON() as typeof consultas[number]
    const { p_desde: desde, p_hasta: hasta } = consulta
    const origen = consulta.p_origen ?? null
    consultas.push({ ...consulta, p_origen: origen })
    const mensual = desde.endsWith('-01')
    const plantilla = metricasConversionesDemo(desde, hasta)
    const datos = metricasConversionesReal()
    const cierres = mensual ? origen == null ? 2 : origen === 'referido' ? 0 : 1 : 0
    const semanas = plantilla.cierres_por_semana!.semanas.map((semana, indice) => ({
      ...semana, cierres: indice === 0 ? cierres : 0, aporte_cierres: indice === 0 ? cierres : 0,
    }))
    datos.periodo = plantilla.periodo
    datos.origen_filtrado = origen
    datos.nucleo = {
      ...(datos.nucleo as Record<string, unknown>), base: 'llegada_unica', atribucion: 'primer_analista',
      llegadas: mensual ? 20 : 10, altas_manuales: 0, divisor: mensual ? 20 : 10,
      numerador: mensual ? 3 : 1, conversion_pct: mensual ? 15 : 10,
      cierres_no_referidos: mensual ? 2 : 0, cierres_referidos: 0,
      operaciones_cartera: 1, upgrades: 1, renovaciones: 0, aporte_cartera: 1,
    }
    datos.cohorte = { ...(datos.cohorte as object), leads: mensual ? 20 : 10, clientes: mensual ? 2 : 0 }
    datos.cierres_por_semana = { ...plantilla.cierres_por_semana, origen_filtrado: origen, cierres, aporte_cierres: cierres, semanas }
    datos.conversion_operaciones = {
      ...plantilla.conversion_operaciones, cantidad: 1, aporte_total: 1,
      detalle: [{ ...plantilla.conversion_operaciones!.detalle[1], analista_id: foto.conversionMensual.responsables[0]!.vendedor_id }],
    }
    const responsableBase = (datos.responsables as Array<Record<string, unknown>>)[0]!
    datos.responsables = foto.conversionMensual.responsables.map((fila, indice) => ({
      ...responsableBase, vendedor_id: fila.vendedor_id,
      nucleo_divisor: mensual ? indice === 0 ? 12 : 8 : indice === 0 ? 6 : 4,
      nucleo_numerador: mensual ? indice === 0 ? 2 : 1 : indice === 0 ? 1 : 0,
      nucleo_conversion_pct: mensual ? indice === 0 ? 16.67 : 12.5 : indice === 0 ? 16.67 : 0,
      cierres_por_semana: semanas.map((semana, semanaIndice) => {
        const cantidad = mensual && semanaIndice === 0 && (origen == null || origen === (indice === 0 ? 'landing' : 'formulario')) ? 1 : 0
        return { ...semana, cierres: cantidad, aporte_cierres: cantidad }
      }),
    }))
    const validacion = v.safeParse(MetricasConversionesSchema, datos)
    expect(validacion.issues).toBeUndefined()
    await route.fulfill({ json: datos })
  })
  await loginReal(page)
  await page.getByLabel('Desde', { exact: true }).fill('2026-08-04')
  await page.getByLabel('Hasta', { exact: true }).fill('2026-08-07')
  await page.getByRole('button', { name: 'Aplicar', exact: true }).click()
  const hero = page.locator('[data-gi-hero]')
  await expect(hero).toContainText('Índice comercial del período')
  await expect(hero).toContainText('10.00%')
  await expect(page.getByText('Prospectos del período que cerraron', { exact: true })).toBeVisible()
  await page.getByRole('checkbox', { name: 'Referido', exact: true }).uncheck()
  await page.getByRole('checkbox', { name: 'Renovación', exact: true }).uncheck()
  await expect(hero).toContainText('Landing + Formulario + Upgrade')
  await expect(hero).toContainText('0 cierres + 1 operaciones')
  await expect(hero).toContainText('10.00%')
  await page.getByRole('button', { name: 'Ranking', exact: true }).click()
  await expect(page.getByLabel('Mes calendario')).toHaveValue('2026-08')
  await expect(page.getByRole('tab', { name: 'Aporte: Landing + Formulario + Upgrade', exact: true })).toBeVisible()
  await expect(page.getByRole('cell', { name: /^16.67%/ })).toBeVisible()
  for (const origen of [null, 'landing', 'formulario']) {
    expect(consultas).toContainEqual({ p_desde: '2026-08-01', p_hasta: '2026-08-31', p_origen: origen })
  }
  await page.screenshot({ path: testInfo.outputPath('ranking-fuentes-desktop.png'), fullPage: true, animations: 'disabled' })
  await page.setViewportSize({ width: 390, height: 844 })
  const ocultarMenu = page.getByRole('button', { name: 'Ocultar menú', exact: true })
  if (await ocultarMenu.isVisible()) await ocultarMenu.click()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
  await page.screenshot({ path: testInfo.outputPath('ranking-fuentes-mobile.png'), fullPage: true, animations: 'disabled' })
  await page.getByLabel('Mes calendario').fill('2026-07')
  await expect(page.getByText(/Mes cerrado: el desglose por fuente no está disponible/)).toBeVisible()
  await expect(page.getByRole('checkbox', { name: 'Upgrade', exact: true })).toBeDisabled()
  await page.getByRole('button', { name: 'Todas las fuentes', exact: true }).click()
  await expect(page.getByRole('tab', { name: 'Conversión general', exact: true })).toBeVisible()
  expect(consultas.some((consulta) => consulta.p_desde.startsWith('2026-07'))).toBe(false)
})
