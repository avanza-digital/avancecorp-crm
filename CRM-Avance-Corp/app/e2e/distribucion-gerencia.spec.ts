import { expect, test } from '@playwright/test'
import {
  ANALISTA_ANA_ID,
  bloquearSupabase,
  entrarDemo,
  loginReal,
  metricasDistribucionReal,
  montarBackendReal,
} from './_helpers'

// Panel REDISEÑADO (2026-07-19): "Distribución de leads" en pirámide de tres
// niveles — resumen + "Lo que merece tu atención" (evidencia), tarjetas por
// analista (el límite de cartera se edita ahí), asistente de reparto por monto
// y la tabla completa por rangos como respaldo bajo demanda.
test.describe('distribución de leads en Hoy > Gerencia', () => {
  test('sesión real: resumen, tarjetas, asistente y tabla bajo demanda con edición del límite', async ({ page }) => {
    const estado = await montarBackendReal(page, {
      metricas: { distribucion: metricasDistribucionReal() },
    })

    await loginReal(page)
    await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible()

    await expect(page.getByRole('heading', { name: 'Distribución de leads' })).toBeVisible()
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)

    // Nivel 1: avisos de evidencia en lenguaje comercial.
    await expect(page.getByRole('heading', { name: 'Lo que merece tu atención' })).toBeVisible()
    await expect(
      page.getByText('1 lead lleva más de 24 horas sin primera atención.'),
    ).toBeVisible()

    // Nivel 2: tarjetas por analista con carga contra límite.
    const fichaAna = page.getByRole('article', { name: 'Ficha de Ana Capital' })
    await expect(fichaAna).toBeVisible()
    await expect(fichaAna).toContainText('8 de 20 leads')
    await expect(fichaAna).toContainText('12 cupos libres')

    // Nivel 3a: asistente de reparto — candidatos por monto, orden por espacio.
    const asistente = page.getByRole('heading', { name: '¿Vas a repartir un lead?' }).locator('..')
    await expect(asistente).toBeVisible()
    await page.getByLabel('Monto del lead').selectOption('pen_10000_20000')
    const candidatos = page.locator('ol > li')
    await expect(candidatos.first()).toContainText('Ana Capital')
    await expect(candidatos.first()).toContainText('12 cupos libres')
    await expect(candidatos.first()).toContainText('Sin resultados con este monto aún')
    await expect(candidatos.nth(1)).toContainText('Bruno Crecimiento')
    await expect(candidatos.nth(1)).toContainText('Cierra el 0% con este monto (0 de 1)')

    // Nivel 3b: la tabla completa vive bajo demanda.
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

    // Colas pendientes visibles sin pasos extra.
    await expect(page.getByText('Pendientes de Gerencia', { exact: true })).toBeVisible()
    await expect(page.getByText('Pendientes de Diego Supervisor', { exact: true })).toBeVisible()

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
    await expect(page.getByRole('heading', { name: 'Distribución de leads' })).toBeVisible()

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

    await expect(page.getByRole('heading', { name: 'Distribución de leads' })).toBeVisible()
    await expect(page.getByText('Datos ficticios de demostración', { exact: true })).toBeVisible()
    await expect(
      page.getByText('No representan información real de la empresa', { exact: false }),
    ).toBeVisible()
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)
    expect(requestsSupabase()).toBe(0)
  })
})
