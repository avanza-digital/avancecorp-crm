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
  await expect(page.getByRole('heading', { name: 'Evolución de la conversión' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Mejores vendedores' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Conversión por origen' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Avance de metas' })).toBeVisible()
  await expect(
    page.getByRole('img', { name: 'Evolución semanal de la conversión a clientes en el rango aplicado' }),
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
    // El héroe dice LA conversión del MES (RPC mensual), no la cohorte del rango.
    await expect(page.getByText('2 cierres de 20 recibidos este mes')).toBeVisible()
    await expect(page.getByText('S/ 125,000').first()).toBeVisible()
    await expect(page.getByText('8 pactadas')).toBeVisible()
    await expect(
      page.getByRole('img', { name: 'Evolución semanal de la conversión a clientes en el rango aplicado' }),
    ).toBeVisible()
    await expect(page.getByText('Referido')).toBeVisible()
    await expect(page.getByText('Datos de ejemplo')).toHaveCount(0)
  })

  test('sin actividad muestra un único vacío honesto y no inventa series demo', async ({ page }) => {
    await montarBackendReal(page)
    await loginReal(page)

    await expect(page.getByRole('heading', { name: 'Resumen' })).toBeVisible()
    await expect(page.getByText('Aún no hay actividad comercial en este período')).toBeVisible()
    await expect(
      page.getByRole('img', { name: 'Evolución semanal de la conversión a clientes en el rango aplicado' }),
    ).toHaveCount(0)
    await expect(page.getByText('Datos de ejemplo')).toHaveCount(0)
  })
})
