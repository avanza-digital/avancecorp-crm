import { irAModulo } from './_navegacion'
// E2E de la pantalla EQUIPO en modo DEMO (sin backend) — la red de seguridad
// del refactor de presentación: supervisor ve cards de SUS analistas + su
// cola, mientras el reparto vive en un módulo aparte; gerencia ve un bloque
// por supervisor con la TABLA
// comparativa y la bandeja global; directorio ve la misma radiografía SIN
// ningún botón de acción (espejo del write-gating de demo-roles.spec.ts).
// En todos: cero requests al host de Supabase (gate fail-closed).
import { expect, test } from '@playwright/test'
import { montarLecturasHoySupervisor } from './_hoy-supervisor'
import {
  bloquearSupabase,
  entrarDemo,
  loginReal,
  montarBackendReal,
  rankingAgostoReal,
  UID,
} from './_helpers'

for (const rolCrm of ['supervisor', 'gerencia'] as const) {
test(`${rolCrm}: ventas propias al final desde octubre y nunca como puesto de analista`, async ({ page }, testInfo) => {
  await page.clock.setFixedTime(new Date('2026-10-16T15:00:00.000Z'))
  const foto = rankingAgostoReal()
  const ventasPropias = {
    persona_id: UID,
    nombre: 'SUPERVISOR VENTAS PROPIAS',
    rol_crm: 'supervisor',
    motivo: 'supervisor',
    conversion: null,
    detalles: (['nuevo', 'renovacion', 'upgrade'] as const).flatMap((categoria) =>
      (['PEN', 'USD'] as const).map((moneda) => ({
        categoria, moneda, capital_objetivo: 0,
        capital_real: categoria === 'nuevo' && moneda === 'PEN' ? 900_000 : 0,
        capital_cumplimiento_pct: null, contratos_objetivo: 0,
        contratos_real: categoria === 'nuevo' && moneda === 'PEN' ? 1 : 0,
        contratos_cumplimiento_pct: null,
      }))),
    cartera: {
      conversiones_clientes: 0, conversiones_renovacion: 0, conversiones_upgrade: 0,
      operaciones_renovacion: 0, operaciones_upgrade: 0, capital_renovado_pen: 0,
      capital_renovado_usd: 0, capital_adicional_pen: 0, capital_adicional_usd: 0,
      renovaciones_sin_desglose: 0,
    },
  }
  await montarBackendReal(page, {
    rolCrm, rolPortal: 'comercial',
    configuracionMetas: { ...foto.configuracionMetas, periodo: '2026-10-01' },
    cumplimientoMetas: { ...foto.cumplimientoMetas, periodo: '2026-10-01', fuera_ranking: [ventasPropias] },
    metricas: { conversionMensual: foto.conversionMensual, cosecha: foto.cosecha },
  })
  // El mes vigente usa el equipo vivo: sus UUID deben coincidir con las metas.
  const analistas = foto.configuracionMetas.vendedores as Array<{ vendedor_id: string; nombre: string }>
  await page.route('**/rest/v1/rpc/equipo_visible_fn', (route) => route.fulfill({ json: [
    { perfil_id: UID, nombre_completo: 'Usuario de prueba', rol_crm: rolCrm, supervisor_id: null, activo: true },
    ...analistas.map((fila) => ({ perfil_id: fila.vendedor_id, nombre_completo: fila.nombre,
      rol_crm: 'vendedor', supervisor_id: UID, activo: true })),
  ] }))
  await loginReal(page)
  if (rolCrm === 'supervisor') await irAModulo(page, 'Gestión de equipo')
  else await page.getByRole('button', { name: 'Ranking', exact: true }).click()
  const selectorMes = page.getByLabel(rolCrm === 'supervisor' ? 'Mes del ranking' : 'Mes calendario')
  await expect(selectorMes).toHaveValue('2026-10')
  const ventas = page.getByRole('complementary', { name: 'Ventas propias de supervisores' })
  await expect(ventas.getByText('SUPERVISOR VENTAS PROPIAS')).toBeVisible()
  await expect(ventas.getByText('Aporta a su equipo')).toBeVisible()
  await expect(ventas.getByText('S/ 900,000', { exact: true })).toBeVisible()
  await page.getByRole('tab', { name: 'Capital total' }).click()
  const tabla = page.getByRole('table', { name: 'Ranking de capital total en soles' })
  await expect(tabla).toBeVisible()
  await expect(tabla.getByRole('row', { name: /ANA AGOSTO/ })).toContainText('S/ 43,530')
  await expect(tabla.getByRole('row', { name: /BRUNO AGOSTO/ })).toContainText('S/ 21,765')
  await expect(tabla.getByText('SUPERVISOR VENTAS PROPIAS')).toHaveCount(0)
  expect(await tabla.evaluate((el) => Boolean(el.compareDocumentPosition(
    document.querySelector('[aria-label="Ventas propias de supervisores"]')!,
  ) & Node.DOCUMENT_POSITION_FOLLOWING))).toBe(true)
  await ventas.scrollIntoViewIfNeeded()
  await page.screenshot({ path: testInfo.outputPath('supervisor-al-final.png') })
  // Incluso si una respuesta anterior trae producción global, el corte del
  // adaptador impide presentar septiembre con las reglas de octubre.
  await selectorMes.fill('2026-09')
  await expect(ventas).toHaveCount(0)
})
}

test('demo supervisor: Gestión de equipo conserva seguimiento y separa el reparto', async ({ page }) => {
  // Fail-closed: en demo NINGÚN request debe salir al host de Supabase.
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Supervisor')
  await irAModulo(page, 'Gestión de equipo')

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
  const respuestasNoSimuladas: string[] = []
  const compatibilidad: Promise<void>[] = []
  const consultasReconocimientos: string[] = []
  const respuestasReconocimientos: number[] = []
  page.on('request', (request) => {
    if (request.url().includes('alertas_reconocimientos')) {
      consultasReconocimientos.push(
        `${request.method()} ${new URL(request.url()).pathname} ${request.headers()['accept-profile'] ?? ''}`,
      )
    }
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
    if (response.url().includes('alertas_reconocimientos')) {
      respuestasReconocimientos.push(response.status())
    }
    if (response.status() < 400) return
    const request = response.request()
    if (response.status() === 404 && new URL(response.url()).pathname === '/rest/v1/rpc/cumplimiento_metas_v2_fn') {
      compatibilidad.push(response.json().then((cuerpo) => { expect(cuerpo.code).toBe('PGRST202') }))
      return
    }
    respuestasNoSimuladas.push(
      `${response.status()} ${request.method()} ${new URL(response.url()).pathname}`,
    )
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
  await montarLecturasHoySupervisor(page)
  await loginReal(page)
  await irAModulo(page, 'Gestión de equipo')

  const selectorMes = page.getByLabel('Mes del ranking')
  await expect(selectorMes).toHaveValue('2026-09')
  await expect(page.getByText('ANA AGOSTO')).toHaveCount(0)
  await selectorMes.fill('2026-08')
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

  await page.getByRole('tab', { name: 'Resultados de los leads del mes' }).click()
  const cosecha = page.getByRole('list', { name: 'Resultados de los leads del mes por analista' })
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
  await Promise.all(compatibilidad)
  expect(compatibilidad.length).toBeGreaterThan(0)
  expect(respuestasNoSimuladas).toEqual([])
  expect(consultasReconocimientos).toEqual([
    'GET /rest/v1/alertas_reconocimientos_vigentes crm',
  ])
  expect(respuestasReconocimientos).toEqual([200])
})

test('demo gerencia: un bloque por supervisor con la TABLA comparativa de analistas', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Gerencia')
  await irAModulo(page, 'Gestión de equipo')

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
  await irAModulo(page, 'Gestión de equipo')

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
  await irAModulo(page, 'Gestión de equipo')

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
