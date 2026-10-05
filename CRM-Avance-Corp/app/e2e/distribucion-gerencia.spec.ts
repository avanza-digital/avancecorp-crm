import { irAModulo } from './_navegacion'
import { expect, test } from '@playwright/test'
import {
  ANALISTA_ANA_ID,
  bloquearSupabase,
  entrarDemo,
  loginReal,
  metricasDistribucionReal,
  montarBackendReal,
} from './_helpers'

// Rendimiento: conversión comercial del mes y capacidad actual. Las asignaciones
// repetidas y su puntería se conservan en Repartir, no como captación comercial.
// Los tiempos/SLA viven exclusivamente en su módulo versionado.
test.describe('distribución de leads en Hoy > Gerencia', () => {
  test('sesión real: resumen, tarjetas y tabla bajo demanda con edición del límite', async ({ page }) => {
    const estado = await montarBackendReal(page, {
      metricas: { distribucion: metricasDistribucionReal() },
    })

    await loginReal(page)
    await expect(page.getByRole('button', { name: 'Resumen', exact: true })).toBeVisible()
    await irAModulo(page, 'Rendimiento')

    await expect(page.getByRole('heading', { name: 'Rendimiento y capacidad comercial' })).toBeVisible()
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)
    // Este fixture conserva el contrato histórico; no se presenta como llegadas nuevas.
    await expect(page.getByText('Base histórica del rango', { exact: true })).toBeVisible()
    await expect(page.getByText('Puntería del período', { exact: true })).toHaveCount(0)
    await expect(page.getByText('Cierres de asignaciones', { exact: true })).toHaveCount(0)
    await expect(page.getByRole('option', { name: /cierres/i })).toHaveCount(0)

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
    await expect(fichaAna).toContainText('Capital estimado actual')
    await expect(fichaAna).not.toContainText(/Recibió|asignaciones en el período|Cierra el|Salidas del período/)
    await expect(page.getByText(/Carga y capacidad actuales; no dependen del mes elegido/)).toBeVisible()

    // La tabla completa vive bajo demanda.
    await expect(
      page.getByRole('region', { name: 'Analistas por rango de monto en soles' }),
    ).toHaveCount(0)
    await page.getByRole('button', { name: 'Ver tabla completa por rangos' }).click()
    const tabla = page.getByRole('region', { name: 'Analistas por rango de monto en soles' })
    await expect(tabla).toBeVisible()

    const filaAna = tabla.getByRole('row', { name: /Ana Capital/ })
    await expect(filaAna).toBeVisible()
    await expect(tabla.getByRole('table', { name: /Carga actual por analista/ })).toBeVisible()
    await expect(filaAna).toContainText('8')
    await expect(filaAna).not.toContainText(/recibió|asignaciones|50%|3 de 6/)
    await expect(page.getByRole('button', { name: /Conversión por monto|Cierres de asignaciones por monto/ })).toHaveCount(0)

    // Edición del límite de cartera, ahora desde la tarjeta del analista.
    await fichaAna.getByRole('button', { name: 'Editar límite de cartera de Ana Capital' }).click()
    const capacidad = fichaAna.getByRole('spinbutton', {
      name: 'Límite de cartera para Ana Capital',
    })
    await capacidad.fill('24')
    await fichaAna.getByRole('button', { name: 'Revisar cambio' }).click()
    const revision = fichaAna.getByRole('region', { name: 'Revisar cambio de límite' })
    await expect(revision).toContainText('Ana Capital: de 20 a 24 leads.')
    await expect(revision).toContainText('Carga actual: 8 leads.')
    expect(estado.llamadas.rpcActualizarCapacidad).toBe(0)
    await fichaAna.getByRole('button', { name: 'Confirmar cambio' }).click()

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
    await irAModulo(page, 'Rendimiento')
    await expect(page.getByRole('heading', { name: 'Rendimiento y capacidad comercial' })).toBeVisible()
    const primeraFicha = page.getByRole('article', { name: /^Ficha de/ }).first()
    await expect(primeraFicha).toBeVisible()
    await expect(primeraFicha).toContainText('Cartera actual')
    await expect(primeraFicha).not.toContainText(/Recibió|asignaciones en el período|Cierra el|Salidas del período/)
    await expect(page.getByText('Cierres de asignaciones', { exact: true })).toHaveCount(0)

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
    const tabla = page.getByRole('table', { name: /Carga actual por analista/ })
    await expect(tabla).not.toContainText(/recibió|asignaciones|%/)
    await expect(page.getByRole('button', { name: /Conversión por monto|Cierres de asignaciones por monto/ })).toHaveCount(0)
    expect(await desborde()).toBeLessThanOrEqual(1)
  })

  test('demo: tablero ficticio SIEMPRE etiquetado como demostración y sin consultar Supabase', async ({ page }) => {
    const requestsSupabase = await bloquearSupabase(page)

    await entrarDemo(page, 'Gerencia')
    await irAModulo(page, 'Rendimiento')

    await expect(page.getByRole('heading', { name: 'Rendimiento y capacidad comercial' })).toBeVisible()
    await expect(page.getByText('Datos ficticios de demostración', { exact: true })).toBeVisible()
    await expect(
      page.getByText('No representan información real de la empresa', { exact: false }),
    ).toBeVisible()
    await expect(page.getByText('Altas por analista', { exact: true })).toHaveCount(0)
    await expect(page.getByText('Puntería del período', { exact: true })).toHaveCount(0)
    await expect(page.getByText('Cierres de asignaciones', { exact: true })).toHaveCount(0)
    expect(requestsSupabase()).toBe(0)
  })
})
