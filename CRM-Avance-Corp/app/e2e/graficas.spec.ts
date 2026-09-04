// E2E del Resumen analítico de Gerencia. La pantalla vigente combina las RPC
// de conversiones/reuniones con Metas versionadas; las antiguas gráficas
// financieras ya no forman parte de la navegación.
import { expect, test } from '@playwright/test'
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
  await expect(page.getByRole('heading', { name: 'Ritmo semanal del equipo' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Mejores analistas' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Conversión por origen' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Avance de metas' })).toBeVisible()
  await expect(
    page.getByRole('img', { name: 'Leads recibidos y cierres por semana del rango aplicado' }),
  ).toBeVisible()
  await expect(page.getByText('Datos de ejemplo').first()).toBeVisible()
  expect(requestsSupabase()).toBe(0)
})

test.describe('resumen de Gerencia en sesión real', () => {
  test('muestra conversiones y reuniones provenientes de las RPC mockeadas', async ({ page }) => {
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
    const conversion = page.locator('[data-gi-kpi]').filter({ hasText: 'Conversión del rango' })
    await expect(conversion).toContainText('10.00%')
    await expect(conversion).toContainText('20 registros en la base histórica')
    await expect(page.getByText(/asignaciones contabilizadas/)).toHaveCount(0)
    // El capital confirmado viene de Cumplimiento/Metas, no se recompone desde
    // la RPC histórica de conversiones. Sin esa fuente, el vacío es explícito.
    const capital = page.locator('[data-gi-kpi]').filter({ hasText: 'Capital confirmado del mes' })
    await expect(capital).toContainText('—')
    await expect(capital).toContainText('Cumplimiento confirmado no disponible')
    await expect(page.getByText('8 pactadas')).toBeVisible()
    await expect(
      page.getByRole('img', { name: 'Leads recibidos y cierres por semana del rango aplicado' }),
    ).toBeVisible()
    const origenes = page.getByRole('heading', { name: 'Conversión por origen' }).locator('..')
    await expect(origenes.getByText('Referido', { exact: true })).toBeVisible()
    await expect(page.getByText('Datos de ejemplo')).toHaveCount(0)
  })

  test('sin actividad muestra un único vacío honesto y no inventa series demo', async ({ page }) => {
    await montarBackendReal(page)
    await loginReal(page)

    await expect(page.getByRole('heading', { name: 'Resumen' })).toBeVisible()
    await expect(page.getByText('Aún no hay actividad comercial en este período')).toBeVisible()
    await expect(
      page.getByRole('img', { name: 'Leads recibidos y cierres por semana del rango aplicado' }),
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

    await page.getByRole('tab', { name: 'Cosecha del lote' }).click()
    const cosecha = page.getByRole('list', { name: 'Cosecha del lote por analista' })
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
