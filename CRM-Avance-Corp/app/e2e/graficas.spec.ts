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
    await montarBackendReal(page, {
      metricas: {
        conversiones: metricasConversionesReal(),
        reuniones: metricasReunionesReal(),
        conversionMensual: conversionMensualReal(),
      },
    })
    await loginReal(page)

    await expect(page.getByRole('heading', { name: 'Resumen' })).toBeVisible()
    // El héroe dice LA conversión del MES (RPC mensual), no la cohorte del rango;
    // el único contador visible de leads queda en el KPI del período.
    await expect(page.getByText('2 cierres este mes')).toBeVisible()
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
})
