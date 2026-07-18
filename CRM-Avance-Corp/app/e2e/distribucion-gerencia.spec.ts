import { expect, test } from '@playwright/test'
import {
  ANALISTA_ANA_ID,
  bloquearSupabase,
  entrarDemo,
  loginReal,
  metricasDistribucionReal,
  montarBackendReal,
} from './_helpers'

test.describe('distribución de leads por capital en Hoy > Gerencia', () => {
  test('sesión real: muestra la matriz y permite actualizar capacidad', async ({ page }) => {
    const estado = await montarBackendReal(page, {
      metricas: { distribucion: metricasDistribucionReal() },
    })

    await loginReal(page)
    await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible()

    await expect(
      page.getByRole('heading', { name: 'Distribución de leads por capital' }),
    ).toBeVisible()
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)
    const matriz = page.getByRole('region', { name: 'Matriz PEN desplazable' })
    await expect(matriz).toBeVisible()
    await expect(page.getByText('7 bandas comerciales', { exact: true })).toBeVisible()

    const filaAna = matriz.getByRole('row', { name: /Ana Capital/ })
    await expect(filaAna).toBeVisible()
    await expect(filaAna).toContainText('8/20')
    await expect(filaAna).toContainText('C 3 · D 3')
    await expect(filaAna).toContainText('50%')
    await expect(page.getByText('Cola global', { exact: true })).toBeVisible()
    await expect(page.getByText('Bandeja de Diego Supervisor', { exact: true })).toBeVisible()

    await filaAna.getByRole('button', { name: 'Editar capacidad de Ana Capital' }).click()
    const capacidad = filaAna.getByRole('spinbutton', {
      name: 'Capacidad objetivo para Ana Capital',
    })
    await capacidad.fill('24')
    await filaAna.getByRole('button', { name: 'Guardar' }).click()

    await expect.poll(() => estado.llamadas.rpcActualizarCapacidad).toBe(1)
    expect(estado.ultimaActualizacionCapacidad).toEqual({
      analistaId: ANALISTA_ANA_ID,
      capacidad: 24,
    })
    await expect(filaAna).toContainText('8/24')
    await expect.poll(() => estado.llamadas.rpcMetricasDistribucion).toBeGreaterThanOrEqual(2)
  })

  test('demo: explica que no inventa historial y no consulta Supabase', async ({ page }) => {
    const requestsSupabase = await bloquearSupabase(page)

    await entrarDemo(page, 'Gerencia')

    await expect(
      page.getByRole('heading', { name: 'Distribución de leads por capital' }),
    ).toBeVisible()
    await expect(
      page.getByText('La demostración no inventa historial de asignaciones', { exact: true }),
    ).toBeVisible()
    await expect(page.getByRole('region', { name: 'Matriz PEN desplazable' })).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Cargar distribución' })).toHaveCount(0)
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)
    expect(requestsSupabase()).toBe(0)
  })
})
