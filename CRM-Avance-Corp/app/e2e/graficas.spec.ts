// E2E del Resumen analítico de Gerencia. La pantalla vigente combina las RPC
// de conversiones/reuniones con Metas versionadas; las antiguas gráficas
// financieras ya no forman parte de la navegación.
import { expect, test } from '@playwright/test'
import { montarConsultaCitas } from './_citas'
import {
  bloquearSupabase,
  conversionMensualReal,
  entrarDemo,
  loginReal,
  metricasConversionesReal,
  metricasReunionesReal,
  montarBackendReal,
  rankingAgostoReal,
} from './_helpers'

test('demo gerencia: el resumen analítico usa fixtures y no consulta Supabase', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Gerencia')

  await expect(page.getByRole('heading', { name: 'Resumen' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Resultados por semana de ingreso' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Mejores analistas' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Resultados por origen' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Avance de metas' })).toBeVisible()
  await expect(
    page.getByRole('img', { name: 'Prospectos por semana de ingreso y resultados' }),
  ).toBeVisible()
  await expect(page.getByText('Datos de ejemplo').first()).toBeVisible()
  expect(requestsSupabase()).toBe(0)
})

test.describe('resumen de Gerencia en sesión real', () => {
  test('distingue base, llegadas, avance inferido y citas en las lecturas simuladas', async ({ page }, testInfo) => {
    await page.clock.setFixedTime(new Date('2026-09-04T15:00:00.000Z'))
    await montarBackendReal(page, {
      metricas: {
        conversiones: metricasConversionesReal(),
        reuniones: metricasReunionesReal(),
        conversionMensual: conversionMensualReal(),
      },
    })
    await loginReal(page)

    await expect(page.getByRole('heading', { name: 'Resumen' })).toBeVisible()
    // El héroe obedece al núcleo del RANGO visible. Este fixture conserva el
    // contrato anterior: debe identificarlo como histórico, nunca inventar
    // llegadas ni volver a presentar asignaciones como captación.
    await expect(page.getByText('Base histórica · 20 registros en la base histórica · 2 cierres no referidos')).toBeVisible()
    const conversion = page.getByText(/Índice comercial del período/).locator('..')
    await expect(conversion).toContainText('10.00%')
    await expect(conversion).toContainText('Base histórica · 20 registros')
    await expect(page.getByText(/asignaciones contabilizadas/)).toHaveCount(0)
    // El capital confirmado viene de Cumplimiento/Metas, no se recompone desde
    // la RPC histórica de conversiones. Sin esa fuente, el vacío es explícito.
    const capital = page.locator('[data-gi-kpi]').filter({ hasText: 'Capital confirmado del mes' })
    await expect(capital).toContainText('—')
    await expect(capital).toContainText('Cumplimiento confirmado no disponible')
    await expect(page.getByText('8 pactadas')).toBeVisible()
    await expect(
      page.getByRole('img', { name: 'Prospectos por semana de ingreso y resultados' }),
    ).toBeVisible()
    const origenes = page.getByRole('heading', { name: 'Resultados por origen' }).locator('..')
    await expect(origenes.getByText('Referido', { exact: true })).toBeVisible()
    await expect(origenes).toContainText('No es la conversión ponderada.')
    await expect(page.getByText('de 20 prospectos del período')).toBeVisible()
    await expect(page.getByText('Datos de ejemplo')).toHaveCount(0)
    await page.screenshot({ path: testInfo.outputPath('resumen-desktop.png'), fullPage: true, animations: 'disabled' })
    await page.setViewportSize({ width: 390, height: 844 })
    await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
    await page.mouse.move(380, 70)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
    await page.screenshot({ path: testInfo.outputPath('resumen-mobile.png'), fullPage: true, animations: 'disabled' })
    await page.setViewportSize({ width: 1280, height: 900 })

    await page.getByRole('button', { name: 'Conversiones', exact: true }).click()
    await expect(page.getByRole('heading', { name: 'Conversión del equipo' })).toBeVisible()
    const avance = page.locator('[data-gi-kpi]').filter({ hasText: 'Reunión o avance posterior' })
    await expect(avance).toContainText('6')
    await expect(avance).toContainText('8 con señal de agenda o avance posterior · no confirma asistencia')
    await expect(page.getByText('Leads que llegaron a cita', { exact: true })).toHaveCount(0)
    await expect(page.getByRole('heading', { name: 'Avance comercial inferido' })).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Resultados por semana de ingreso' })).toBeVisible()
    await expect(page.getByText(/no cierres ocurridos esa semana/)).toBeVisible()
    await page.mouse.move(1200, 70)
    await expect(page.getByRole('button', { name: 'Conversiones', exact: true })).toHaveAttribute('title', 'Conversiones')
    await page.screenshot({ path: testInfo.outputPath('conversiones-desktop.png'), fullPage: true, animations: 'disabled' })
    await page.setViewportSize({ width: 390, height: 844 })
    await page.mouse.move(380, 70)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
    const graficoAnalista = page.getByRole('region', { name: 'Gráfico del índice comercial por analista', exact: true })
    const graficoAvance = page.getByRole('region', { name: 'Gráfico de avance inferido', exact: true })
    for (const grafico of [graficoAnalista, graficoAvance]) {
      await expect(grafico).toHaveAttribute('tabindex', '0')
      expect(await grafico.evaluate((element) => element.scrollWidth > element.clientWidth)).toBe(true)
      expect(await grafico.getByRole('img').evaluate((element) => element.getBoundingClientRect().width)).toBeGreaterThanOrEqual(430)
      await grafico.focus()
      await page.keyboard.press('ArrowRight')
      await expect.poll(() => grafico.evaluate((element) => element.scrollLeft)).toBeGreaterThan(0)
    }
    await page.screenshot({ path: testInfo.outputPath('conversiones-mobile.png'), fullPage: true, animations: 'disabled' })
    await page.getByRole('heading', { name: 'Avance comercial inferido' }).scrollIntoViewIfNeeded()
    await page.screenshot({ path: testInfo.outputPath('conversiones-mobile-avance.png'), fullPage: true, animations: 'disabled' })
    await page.setViewportSize({ width: 1280, height: 900 })

    await montarConsultaCitas(page)
    await page.getByRole('button', { name: 'Citas', exact: true }).click()
    await expect(page.getByRole('heading', { name: 'Citas del equipo' })).toBeVisible()
    await expect(page.getByRole('button',{name:'No asistieron 2'})).toBeVisible()
    await expect(page.getByRole('button',{name:'Reprogramaron 1'})).toBeVisible()
    await expect(page.getByRole('button',{name:'Asistió 1'})).toBeVisible()
    await expect(page.getByRole('button',{name:'Depositó —'})).toBeDisabled()
    await expect(page.getByRole('region',{name:'Conversión de inasistencias a depósito'})).toContainText('Sin verificar')
    await expect(page.getByRole('table',{name:'Resultados por analista de las citas filtradas'})).toContainText('3 / 2')
    await expect(page.getByText('Reunión o avance posterior', { exact: true })).toHaveCount(0)
    await page.mouse.move(1200,70)
    await expect(page.getByRole('button',{name:'Citas',exact:true})).toHaveAttribute('title','Citas')
    await page.screenshot({ path: testInfo.outputPath('citas-desktop.png'), fullPage: true, animations: 'disabled' })
    await page.setViewportSize({ width: 390, height: 844 })
    await page.mouse.move(380,70)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
    await page.getByRole('heading',{name:'Citas del equipo'}).scrollIntoViewIfNeeded()
    const exportar = await page.getByRole('button',{name:'Exportar citas'}).boundingBox()
    expect(exportar!.x+exportar!.width).toBeLessThanOrEqual(390)
    await page.screenshot({ path: testInfo.outputPath('citas-mobile-inicio.png'), fullPage: true, animations: 'disabled' })
    const tabla = page.getByRole('region', { name: 'Tabla de citas por lead y analista', exact: true })
    await tabla.focus()
    await page.keyboard.press('ArrowRight')
    await expect.poll(() => tabla.evaluate((element) => element.scrollLeft)).toBeGreaterThan(0)
    await page.screenshot({ path: testInfo.outputPath('citas-mobile.png'), fullPage: true, animations: 'disabled' })
  })

  test('sin paridad del rango no publica su conversión ni la reemplaza con el mes', async ({ page }) => {
    await page.clock.setFixedTime(new Date('2026-09-04T15:00:00.000Z'))
    const conversiones = metricasConversionesReal()
    // Mutación exclusivamente local de la respuesta de esta prueba. Se conserva
    // el contrato y se simula una comprobación ejecutada que NO concilia.
    conversiones.sondas = {
      ...(conversiones.sondas as Record<string, unknown>),
      cuadra: false,
      paridad_nucleo: 2,
    }
    await montarBackendReal(page, {
      metricas: {
        conversiones,
        reuniones: metricasReunionesReal(),
        conversionMensual: conversionMensualReal(),
      },
    })
    await loginReal(page)
    const heroe = page.locator('[data-gi-hero]')
    await expect(heroe).toContainText('Cifras en revisión: falta verificar la conversión del rango.')
    await expect(heroe).not.toContainText('10.00%')
    await expect(heroe).not.toContainText('Base histórica · 20')
    const origenes = page.getByRole('heading', { name: 'Resultados por origen' }).locator('..')
    await expect(origenes).toContainText('Cifras en revisión: los resultados por origen permanecen ocultos.')
    await expect(origenes.getByText('Referido', { exact: true })).toHaveCount(0)
    // La lectura de eventos de citas sigue disponible: no comparte la sonda.
    await expect(page.locator('[data-gi-kpi]').filter({ hasText: 'Citas realizadas' })).toContainText('8 pactadas')
  })

  test('un rango vacío con foto mensual ausente no inventa metas ni series demo', async ({ page }) => {
    await montarBackendReal(page)
    await loginReal(page)

    await expect(page.getByRole('heading', { name: 'Resumen' })).toBeVisible()
    await expect(page.getByText(/No pudimos cargar las metas mensuales de/)).toBeVisible()
    await expect(
      page.getByRole('img', { name: 'Prospectos por semana de ingreso y resultados' }),
    ).toHaveCount(0)
    await expect(page.getByText('Datos de ejemplo')).toHaveCount(0)
  })

  test('ranking real de Gerencia consulta agosto como mes calendario completo', async ({ page }) => {
    await page.clock.setFixedTime(new Date('2026-09-02T15:00:00.000Z'))
    const foto = rankingAgostoReal()
    const llamadas: { ruta: string; cuerpo: Record<string, unknown> }[] = []
    const respuestasNoSimuladas: string[] = []
    page.on('request', (request) => {
      if (request.method() !== 'POST') return
      const ruta = new URL(request.url()).pathname
      if (![
        '/rest/v1/rpc/conversion_mensual_fn',
        '/rest/v1/rpc/cumplimiento_metas_fn',
        '/rest/v1/rpc/metricas_conversiones_equipo_fn',
        '/functions/v1/crm-tipo-cambio',
      ].includes(ruta)) return
      llamadas.push({ ruta, cuerpo: request.postDataJSON() as Record<string, unknown> })
    })
    page.on('response', (response) => {
      if (response.status() < 400) return
      const request = response.request()
      respuestasNoSimuladas.push(
        `${response.status()} ${request.method()} ${new URL(response.url()).pathname}`,
      )
    })

    await montarBackendReal(page, {
      rolCrm: 'gerencia',
      rolPortal: 'comercial',
      configuracionMetas: foto.configuracionMetas,
      cumplimientoMetas: foto.cumplimientoMetas,
      metricas: {
        conversionMensual: foto.conversionMensual,
        cosecha: foto.cosecha,
      },
    })
    await loginReal(page)
    await page.getByRole('button', { name: 'Ranking', exact: true }).click()

    // El ranking ya no expone un rango ambiguo: el selector mensual gobierna
    // las tres fuentes y el TC con el calendario completo de agosto.
    const selectorMes = page.getByLabel('Mes calendario')
    await expect(selectorMes).toHaveValue('2026-09')
    await expect(page.getByText('ANA AGOSTO')).toHaveCount(0)
    await selectorMes.fill('2026-08')

    await expect(page.getByText('Mes calendario · agosto 2026')).toBeVisible()
    const conversion = page.getByRole('table', { name: 'Ranking de conversión general' })
    await expect(conversion.getByRole('row', { name: /ANA AGOSTO/ })).toContainText('8.33%')

    await page.getByRole('tab', { name: 'Capital total' }).click()
    await expect(page.getByText(/TC S\/ 3\.53 \(SBS · prom\. 7d al 31\/08\/2026\)/)).toBeVisible()
    await expect(
      page.getByRole('table', { name: 'Ranking de capital total en soles' })
        .getByRole('row', { name: /ANA AGOSTO/ }),
    ).toContainText('S/ 43,530')

    await page.getByRole('tab', { name: 'Resultados de los leads del mes' }).click()
    const cosecha = page.getByRole('list', { name: 'Resultados de los leads del mes por analista' })
    await expect(cosecha.getByText('ANA AGOSTO')).toBeVisible()
    await expect(cosecha.getByText('De sus 12 leads del mes, 1 ya es cliente (8.33%)')).toBeVisible()

    expect(llamadas).toEqual(expect.arrayContaining([
      expect.objectContaining({
        ruta: '/rest/v1/rpc/conversion_mensual_fn',
        cuerpo: expect.objectContaining({ p_periodo: '2026-08-01' }),
      }),
      expect.objectContaining({
        ruta: '/rest/v1/rpc/cumplimiento_metas_fn',
        cuerpo: expect.objectContaining({ p_periodo: '2026-08-01' }),
      }),
      expect.objectContaining({
        ruta: '/rest/v1/rpc/metricas_conversiones_equipo_fn',
        cuerpo: expect.objectContaining({ p_desde: '2026-08-01', p_hasta: '2026-08-31' }),
      }),
      expect.objectContaining({
        ruta: '/functions/v1/crm-tipo-cambio',
        cuerpo: expect.objectContaining({ fecha_corte: '2026-08-31' }),
      }),
    ]))
    expect(respuestasNoSimuladas).toEqual([])
  })
})
