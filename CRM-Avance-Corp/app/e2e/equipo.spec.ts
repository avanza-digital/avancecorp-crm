// E2E de la pantalla EQUIPO en modo DEMO (sin backend) — la red de seguridad
// del refactor de presentación: supervisor ve cards de SUS analistas + su
// cola, mientras el reparto vive en un módulo aparte; gerencia ve un bloque
// por supervisor con la TABLA
// comparativa y la bandeja global; directorio ve la misma radiografía SIN
// ningún botón de acción (espejo del write-gating de demo-roles.spec.ts).
// En todos: cero requests al host de Supabase (gate fail-closed).
import { expect, test } from '@playwright/test'
import {
  bloquearSupabase,
  entrarDemo,
  loginReal,
  montarBackendReal,
  rankingAgostoReal,
} from './_helpers'

test('demo supervisor: Gestión de equipo conserva seguimiento y separa el reparto', async ({ page }) => {
  // Fail-closed: en demo NINGÚN request debe salir al host de Supabase.
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Supervisor')
  await page.getByRole('button', { name: 'Gestión de equipo' }).click()

  // Cards SOLO de sus analistas directos (d-sup1 → d-v1 y d-v2); el equipo
  // de d-sup2 queda fuera del ámbito (anti-fuga, espejo de store-ambito).
  const cards = page.getByRole('list', { name: 'Analistas de mi equipo' })
  await expect(cards.getByText('ANALISTA UNO')).toBeVisible()
  await expect(cards.getByText('ANALISTA DOS')).toBeVisible()
  await expect(cards.getByText('ANALISTA TRES')).toHaveCount(0)

  // No duplica controles: el botón del módulo existe en el menú, pero esta
  // pantalla conserva solo la cola y el desempeño del equipo.
  await expect(page.getByRole('button', { name: 'Derivar leads' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Cola del equipo' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Por repartir', exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Asignar' })).toHaveCount(0)

  expect(requestsSupabase()).toBe(0)
})

test('supervisor real: el selector mensual recupera la foto completa de agosto', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-09-02T15:00:00.000Z'))
  const foto = rankingAgostoReal()
  const llamadas: { ruta: string; cuerpo: Record<string, unknown> }[] = []
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

  await montarBackendReal(page, {
    rolCrm: 'supervisor',
    rolPortal: 'comercial',
    configuracionMetas: foto.configuracionMetas,
    cumplimientoMetas: foto.cumplimientoMetas,
    metricas: {
      conversionMensual: foto.conversionMensual,
      cosecha: foto.cosecha,
    },
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Gestión de equipo', exact: true }).click()

  await page.getByLabel('Mes del ranking').fill('2026-08')
  await expect(page.getByText('Mes calendario · agosto 2026')).toBeVisible()
  await expect(page.locator('[data-gi-panel]').getByText('Mi equipo', { exact: true })).toBeVisible()
  await page.getByRole('tab', { name: 'Conversión general' }).click()
  await expect(
    page.getByRole('table', { name: 'Ranking de conversión general' })
      .getByRole('row', { name: /BRUNO AGOSTO/ }),
  ).toContainText('12.50%')

  await page.getByRole('tab', { name: 'Capital total' }).click()
  await expect(page.getByText(/TC S\/ 3\.53 \(SBS · prom\. 7d al 31\/08\/2026\)/)).toBeVisible()
  await expect(
    page.getByRole('table', { name: 'Ranking de capital total en soles' })
      .getByRole('row', { name: /BRUNO AGOSTO/ }),
  ).toContainText('S/ 21,765')

  await page.getByRole('tab', { name: 'Cosecha del lote' }).click()
  const cosecha = page.getByRole('list', { name: 'Cosecha del lote por analista' })
  await expect(cosecha.getByText('BRUNO AGOSTO')).toBeVisible()
  await expect(cosecha.getByText('De sus 8 leads del mes, 1 ya es cliente (12.50%)')).toBeVisible()

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
})

test('demo gerencia: un bloque por supervisor con la TABLA comparativa de analistas', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Gerencia')
  await page.getByRole('button', { name: 'Equipo' }).click()

  // Refactor de comodidad (2026-07-18): PRIMERO la tabla comparativa de
  // supervisores; el detalle por equipo se abre BAJO DEMANDA (patrón
  // detalle-bajo-demanda, como la tabla por rangos de Distribución de leads).
  await expect(page.getByRole('heading', { name: 'Comparativa de equipos' })).toBeVisible()
  await expect(page.getByRole('row', { name: /SUPERVISOR UNO/ })).toBeVisible()
  const filaSup2 = page.getByRole('row', { name: /SUPERVISOR DOS/ })
  await expect(filaSup2).toBeVisible()

  // Con >1 equipo, ningún detalle se abre solo.
  await expect(page.getByRole('heading', { name: 'Equipo de SUPERVISOR UNO' })).toHaveCount(0)
  await expect(page.getByRole('heading', { name: 'Equipo de SUPERVISOR DOS' })).toHaveCount(0)

  // Abrir el equipo de SUPERVISOR DOS: aparece SU tabla de analistas (solo una).
  await filaSup2.getByRole('button', { name: 'Ver equipo' }).click()
  await expect(page.getByRole('heading', { name: 'Equipo de SUPERVISOR DOS' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Equipo de SUPERVISOR UNO' })).toHaveCount(0)
  for (const col of ['Analista', 'Sin tocar']) {
    await expect(page.getByRole('columnheader', { name: col })).toHaveCount(1)
  }

  // La fila de ANALISTA TRES pinta sus números del ámbito global: S/ 113k en
  // proceso (l4+l13+l20), sin fabricar una conversión cuando no existe divisor
  // mensual canónico, y el semáforo ROJO de última actividad (l20 lleva 8 días
  // sin movimiento — umbral >5 d).
  const filaV3 = page.getByRole('row', { name: /ANALISTA TRES/ })
  await expect(filaV3.getByText('S/ 113k')).toBeVisible()
  await expect(filaV3.getByText('Sin divisor mensual')).toBeVisible()
  await expect(filaV3.getByText('8 d sin act.')).toBeVisible()

  expect(requestsSupabase()).toBe(0)
})

test('demo gerencia: reparte desde la bandeja global (optgroup por equipo) con toast "(demo)"', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Gerencia')
  await page.getByRole('button', { name: 'Equipo' }).click()

  // La bandeja global existe para gerencia y ve parkeados de TODAS las
  // bandejas (l14 es de la bandeja de d-sup2).
  await expect(page.getByRole('heading', { name: 'Por repartir (toda la empresa)' })).toBeVisible()
  await expect(page.getByText('Bandeja: SUPERVISOR DOS')).toBeVisible()

  // Asignar cruzando de bandeja: SOFÍA (bandeja d-sup2) → ANALISTA TRES.
  await page.getByLabel('Asignar analista a SOFÍA HERRERA LUNA').selectOption({ label: 'ANALISTA TRES' })
  await page.getByRole('button', { name: 'Asignar', disabled: false }).click()
  await expect(page.getByText('SOFÍA HERRERA LUNA asignado a ANALISTA TRES (demo)')).toBeVisible()

  expect(requestsSupabase()).toBe(0)
})

test('demo directorio: la misma radiografía en tabla pero SIN botones de acción', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Directorio')
  await page.getByRole('button', { name: 'Equipo' }).click()

  // Misma radiografía que gerencia: comparativa primero, detalle bajo demanda.
  await expect(page.getByText(/Vista de auditoría del Directorio/)).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Comparativa de equipos' })).toBeVisible()
  await page
    .getByRole('row', { name: /SUPERVISOR UNO/ })
    .getByRole('button', { name: 'Ver equipo' })
    .click()
  await expect(page.getByRole('heading', { name: 'Equipo de SUPERVISOR UNO' })).toBeVisible()
  await expect(page.getByRole('row', { name: /ANALISTA UNO/ })).toBeVisible()

  // Solo lectura total: ni bandeja global ni un solo botón "Asignar"
  // (espejo del write-gating ya probado para el pipeline en demo-roles).
  await expect(page.getByRole('heading', { name: 'Por repartir (toda la empresa)' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Asignar' })).toHaveCount(0)

  expect(requestsSupabase()).toBe(0)
})
