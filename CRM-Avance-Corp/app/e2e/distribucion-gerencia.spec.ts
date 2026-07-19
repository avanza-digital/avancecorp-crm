import { expect, test } from '@playwright/test'
import {
  ANALISTA_ANA_ID,
  bloquearSupabase,
  entrarDemo,
  loginReal,
  metricasDistribucionReal,
  montarBackendReal,
} from './_helpers'

// Panel REDISEÑADO (2026-07-18): "Supervisión de distribución" — primero la
// lectura por equipos (cards por supervisor), la matriz por analista queda
// bajo demanda tras "Abrir análisis completo", y las colas pendientes son
// chips SOLO de los rangos con cantidad > 0.
test.describe('supervisión de distribución de leads en Hoy > Gerencia', () => {
  test('sesión real: equipos primero, matriz bajo demanda y edición del límite de cartera', async ({ page }) => {
    const estado = await montarBackendReal(page, {
      metricas: { distribucion: metricasDistribucionReal() },
    })

    await loginReal(page)
    await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible()

    await expect(
      page.getByRole('heading', { name: 'Supervisión de distribución' }),
    ).toBeVisible()
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)

    // Primer nivel: la lectura por equipos (cadena de mando), sin matriz aún.
    await expect(page.getByRole('heading', { name: 'Equipos bajo supervisión' })).toBeVisible()
    await expect(
      page.getByRole('region', { name: 'Analistas por rango de monto en soles' }),
    ).toHaveCount(0)

    // Segundo nivel bajo demanda: la matriz PEN de 7 rangos del equipo elegido.
    await page.getByRole('button', { name: 'Abrir análisis completo' }).click()
    const matriz = page.getByRole('region', { name: 'Analistas por rango de monto en soles' })
    await expect(matriz).toBeVisible()
    await expect(page.getByText('PEN · 7 rangos', { exact: true })).toBeVisible()

    const filaAna = matriz.getByRole('row', { name: /Ana Capital/ })
    await expect(filaAna).toBeVisible()
    await expect(filaAna).toContainText('8 de 20') // carga activa de su límite

    // La conversión histórica vive en su propio modo de lectura (ya no C·D).
    await page.getByRole('button', { name: 'Conversión por monto' }).click()
    await expect(filaAna).toContainText('50%')
    await expect(filaAna).toContainText('3 de 6')
    await page.getByRole('button', { name: 'Carga actual' }).click()

    // Colas pendientes: la de Gerencia y la bandeja del supervisor.
    await expect(page.getByText('Pendientes de Gerencia', { exact: true })).toBeVisible()
    await expect(page.getByText('Pendientes de Diego Supervisor', { exact: true })).toBeVisible()

    await filaAna.getByRole('button', { name: 'Editar límite de cartera de Ana Capital' }).click()
    const capacidad = filaAna.getByRole('spinbutton', {
      name: 'Límite de cartera para Ana Capital',
    })
    await capacidad.fill('24')
    await filaAna.getByRole('button', { name: 'Guardar' }).click()

    await expect.poll(() => estado.llamadas.rpcActualizarCapacidad).toBe(1)
    expect(estado.ultimaActualizacionCapacidad).toEqual({
      analistaId: ANALISTA_ANA_ID,
      capacidad: 24,
    })
    await expect(filaAna).toContainText('8 de 24')
    await expect.poll(() => estado.llamadas.rpcMetricasDistribucion).toBeGreaterThanOrEqual(2)
  })

  test('demo: tablero ficticio SIEMPRE etiquetado como demostración y sin consultar Supabase', async ({ page }) => {
    const requestsSupabase = await bloquearSupabase(page)

    await entrarDemo(page, 'Gerencia')

    await expect(
      page.getByRole('heading', { name: 'Supervisión de distribución' }),
    ).toBeVisible()
    // El rediseño reemplazó el "no inventa historial": ahora la demo trae un
    // tablero ficticio completo con su aviso de honestidad siempre visible.
    await expect(page.getByText('Datos ficticios de demostración', { exact: true })).toBeVisible()
    await expect(
      page.getByText('No representan información real de la empresa', { exact: false }),
    ).toBeVisible()
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)
    expect(requestsSupabase()).toBe(0)
  })
})
