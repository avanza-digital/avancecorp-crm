// E2E de las GRÁFICAS de gerencia (panel Hoy). Dos mundos, como el resto de la
// suite:
//  - DEMO: las 3 gráficas se alimentan de agregados derivados de las fixtures
//    (lib/demo-metricas) y NINGÚN request sale a Supabase (fail-closed).
//  - REAL: backend interceptado con las 3 RPCs crm.metricas_*_fn mockeadas
//    (_helpers.montarBackendReal.metricas) — pinta con data del mock y muestra
//    el estado vacío honesto sin data.
import { expect, test } from '@playwright/test'
import { bloquearSupabase, entrarDemo, loginReal, montarBackendReal } from './_helpers'

const GRAFICAS = [
  'grafica-capital',
  'grafica-pagos',
  'grafica-vencimientos',
] as const

test('demo gerencia: las 3 gráficas pintan desde las fixtures — 0 requests a Supabase', async ({ page }) => {
  // Fail-closed: una sesión demo no tiene backend; cualquier request al host
  // de Supabase se aborta y se cuenta (0 al final o el test falla).
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Gerencia') // la vista por defecto es Hoy

  // Las 3 tarjetas existen y cada una dibujó barras DE VERDAD (recharts pinta
  // cada barra como .recharts-bar-rectangle dentro del svg).
  for (const id of GRAFICAS) {
    const card = page.getByTestId(id)
    await expect(card).toBeVisible()
    await expect(card.locator('.recharts-bar-rectangle').first()).toBeVisible()
  }

  // Capital: PEN muestra las categorías de los contratos demo A (nuevo) y C
  // (upgrade); el contrato B es USD → hay tabs y JAMÁS se suma con PEN.
  // `.first()`: el texto exacto de la leyenda resuelve al item Y a su span
  // interno (strict mode) — nos basta con que exista visible.
  const capital = page.getByTestId('grafica-capital')
  await expect(capital.getByText('Nuevo', { exact: true }).first()).toBeVisible()
  await expect(capital.getByText('Upgrade', { exact: true }).first()).toBeVisible()
  // Los tabs de moneda ahora hablan es-PE: 'Soles'/'Dólares' (PEN/USD jamás sumados).
  await capital.getByRole('button', { name: 'Dólares' }).click()
  await expect(capital.getByText('Renovación', { exact: true }).first()).toBeVisible()

  // Pagos: leyenda con las dos series del semáforo (pagado vs vencido).
  const pagos = page.getByTestId('grafica-pagos')
  await expect(pagos.getByText('Pagado', { exact: true }).first()).toBeVisible()
  await expect(pagos.getByText('Vencido', { exact: true }).first()).toBeVisible()

  // Ninguna request salió al host de Supabase.
  expect(requestsSupabase()).toBe(0)
})

// ── Sesión REAL ────────────────────────────────────────────────────────────────
// GATE DE LEADS CERRADO (config.ts FUNCIONES_LEADS_APROBADAS=false, decisión de
// Miguel 2026-07-16): la vista Hoy (donde viven las gráficas) NO existe para
// cuentas reales, así que estos tests solo corren contra un dev server con
//   VITE_ENABLE_DEMO=true VITE_LEADS_PREVIEW=true npm run dev   (server aparte)
// criterio que acciones-real.spec.ts).
test.describe('gráficas en sesión REAL (RPCs mockeadas)', () => {
  // Gate parcial 2026-07-16: gerencia real SÍ ve Hoy — estos tests corren en la suite normal.

  test('real: las 3 gráficas pintan con la data del mock de las RPCs', async ({ page }) => {
    await montarBackendReal(page, {
      metricas: {
        // numeric va como STRING a propósito: PostgREST serializa así y el
        // wrapper debe coercionar (mismo trato que capital/monto_estimado).
        capital: [
          { mes: '2026-05-01', moneda: 'PEN', categoria: 'nuevo', contratos: 2, capital_colocado: '65000.00' },
          { mes: '2026-07-01', moneda: 'PEN', categoria: null, contratos: 1, capital_colocado: 15000 },
          { mes: '2026-06-01', moneda: 'USD', categoria: 'renovacion', contratos: 1, capital_colocado: '25000.00' },
        ],
        pagos: [
          { mes: '2026-06-01', moneda: 'PEN', tipo: 'cuota', estado: 'pagado', cuotas: 3, monto_programado: '1500.00', monto_pagado: '1500.00' },
          { mes: '2026-07-01', moneda: 'PEN', tipo: 'cuota', estado: 'vencido', cuotas: 1, monto_programado: '500.00', monto_pagado: 0 },
        ],
        vencimientos: [
          { mes: '2026-09-01', moneda: 'PEN', contratos_por_vencer: 1, capital_por_vencer: '30000.00' },
        ],
      },
    })
    await loginReal(page)
    await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible()

    for (const id of GRAFICAS) {
      const card = page.getByTestId(id)
      await expect(card).toBeVisible()
      await expect(card.locator('.recharts-bar-rectangle').first()).toBeVisible()
    }

    // Detalles que solo salen de la data mockeada (no de fixtures demo).
    // categoria null → bucket 'Sin categoría' en la leyenda del capital.
    // `.first()`: el texto exacto de la leyenda resuelve al item Y a su span.
    await expect(
      page.getByTestId('grafica-capital').getByText('Sin categoría', { exact: true }).first(),
    ).toBeVisible()
    // El mes con hueco (jun 26 entre may y jul del capital) se rellenó: eje continuo.
    await expect(page.getByTestId('grafica-capital').getByText('jun 26')).toBeVisible()
    // Nada en la página dice "(demo)": la sesión es real.
    await expect(page.getByText('(demo)')).toHaveCount(0)
  })

  test('real sin data: estado vacío honesto en las 3 tarjetas (nada inventado)', async ({ page }) => {
    await montarBackendReal(page) // metricas: vacías por defecto
    await loginReal(page)
    await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible()

    // Regla A3: sesión real sin datos → PanelVacio honesto POR TARJETA (copys
    // nuevos que dicen de dónde se llena cada una), jamás series demo.
    await expect(page.getByTestId('grafica-capital').getByText('Aún no hay capital para graficar')).toBeVisible()
    await expect(page.getByTestId('grafica-pagos').getByText('Aún no hay pagos para graficar')).toBeVisible()
    await expect(page.getByTestId('grafica-vencimientos').getByText('Aún no hay vencimientos para graficar')).toBeVisible()
    // Y por supuesto, ni una barra pintada en las 3 tarjetas.
    for (const id of GRAFICAS) {
      await expect(page.getByTestId(id).locator('.recharts-bar-rectangle')).toHaveCount(0)
    }
  })
})
