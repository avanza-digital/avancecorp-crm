import { expect, test } from '@playwright/test'
import {
  ANALISTA_ANA_ID,
  bloquearSupabase,
  entrarDemo,
  loginReal,
  metricasDistribucionReal,
  montarBackendReal,
} from './_helpers'

// Panel de rendimiento: resumen + evidencia, tarjetas por analista (con edición
// del límite) y tabla completa por rangos bajo demanda. Los tiempos/SLA viven
// exclusivamente en su módulo versionado, no en este tablero.
test.describe('distribución de leads en Hoy > Gerencia', () => {
  test('sesión real: resumen, tarjetas y tabla bajo demanda con edición del límite', async ({ page }) => {
    const estado = await montarBackendReal(page, {
      metricas: { distribucion: metricasDistribucionReal() },
    })

    await loginReal(page)
    await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible()
    await page.getByRole('button', { name: 'Rendimiento' }).click()

    await expect(page.getByRole('heading', { name: 'Rendimiento y capacidad comercial' })).toBeVisible()
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)

    // Nivel 1: avisos de evidencia en lenguaje comercial.
    await expect(page.getByRole('heading', { name: 'Lo que merece tu atención' })).toBeVisible()
    await expect(page.getByText(/2 leads sin atender/)).toBeVisible()
    await expect(page.getByText(/24 horas/i)).toHaveCount(0)
    await expect(page.getByText(/métricas SLA versionadas/)).toBeVisible()

    // Nivel 2: tarjetas por analista con carga contra límite.
    const fichaAna = page.getByRole('article', { name: 'Ficha de Ana Capital' })
    await expect(fichaAna).toBeVisible()
    await expect(fichaAna).toContainText('8 de 20 leads')
    await expect(fichaAna).toContainText('12 cupos libres')

    // La tabla completa vive bajo demanda.
    await expect(
      page.getByRole('region', { name: 'Analistas por rango de monto en soles' }),
    ).toHaveCount(0)
    await page.getByRole('button', { name: 'Ver tabla completa por rangos' }).click()
    const tabla = page.getByRole('region', { name: 'Analistas por rango de monto en soles' })
    await expect(tabla).toBeVisible()

    const filaAna = tabla.getByRole('row', { name: /Ana Capital/ })
    await expect(filaAna).toBeVisible()
    await expect(filaAna).toContainText('recibió 3') // cartera Y recibidos, juntos

    await page.getByRole('button', { name: 'Conversión por monto' }).click()
    await expect(filaAna).toContainText('50%')
    await expect(filaAna).toContainText('3 de 6')
    await page.getByRole('button', { name: 'Carga actual' }).click()

    // Edición del límite de cartera, ahora desde la tarjeta del analista.
    await fichaAna.getByRole('button', { name: 'Editar límite de cartera de Ana Capital' }).click()
    const capacidad = fichaAna.getByRole('spinbutton', {
      name: 'Límite de cartera para Ana Capital',
    })
    await capacidad.fill('24')
    await fichaAna.getByRole('button', { name: 'Guardar' }).click()

    await expect.poll(() => estado.llamadas.rpcActualizarCapacidad).toBe(1)
    expect(estado.ultimaActualizacionCapacidad).toEqual({
      analistaId: ANALISTA_ANA_ID,
      capacidad: 24,
    })
    await expect(fichaAna).toContainText('8 de 24 leads')
    await expect.poll(() => estado.llamadas.rpcMetricasDistribucion).toBeGreaterThanOrEqual(2)
  })

  test('móvil 390px: la pantalla no desborda; lo ancho scrollea en contenedores internos', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 })
    await bloquearSupabase(page)

    await entrarDemo(page, 'Gerencia')
    await page.getByRole('button', { name: 'Rendimiento' }).click()
    await expect(page.getByRole('heading', { name: 'Rendimiento y capacidad comercial' })).toBeVisible()

    const desborde = () =>
      page.evaluate(
        () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
      )
    expect(await desborde()).toBeLessThanOrEqual(1)

    // La tabla por rangos es lo más ancho del tablero: abierta debe scrollear
    // DENTRO de su contenedor, jamás empujar la página completa.
    await page.getByRole('button', { name: 'Ver tabla completa por rangos' }).click()
    await expect(
      page.getByRole('region', { name: 'Analistas por rango de monto en soles' }),
    ).toBeVisible()
    expect(await desborde()).toBeLessThanOrEqual(1)
  })

  test('demo: tablero ficticio SIEMPRE etiquetado como demostración y sin consultar Supabase', async ({ page }) => {
    const requestsSupabase = await bloquearSupabase(page)

    await entrarDemo(page, 'Gerencia')
    await page.getByRole('button', { name: 'Rendimiento' }).click()

    await expect(page.getByRole('heading', { name: 'Rendimiento y capacidad comercial' })).toBeVisible()
    await expect(page.getByText('Datos ficticios de demostración', { exact: true })).toBeVisible()
    await expect(
      page.getByText('No representan información real de la empresa', { exact: false }),
    ).toBeVisible()
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)
    expect(requestsSupabase()).toBe(0)
  })
})
