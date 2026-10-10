// E2E de Facturación — fase 1 de la auditoría del 08/10/2026 (solo pantalla).
//
// Sesión REAL (yo.demo = false) con todo el HTTP de Supabase interceptado. Defiende en
// el navegador lo que las pruebas unitarias no ven: cifras, rótulos y el MAQUETADO real
// (columnas fijas, alturas, qué queda a la vista en un teléfono).
//
//  1. El % del titular habla de SU cifra: si el titular es el total unificado
//     (soles + dólares × tasa), el tramo anterior también se valora unificado.
//  2. Sin tipo de cambio y con dólares, el titular dice «Facturado en soles», nunca
//     «Total facturado». Un aviso ofrece reintentar con UN solo botón (el del pie aparece
//     solo si se elige Soles o Dólares a mano) y, mientras se reintenta, el botón sigue
//     montado («Consultando…», aria-disabled) y no pierde el foco.
//  3. Si la RPC cae, ningún indicador dice «S/ 0»: una avería no es un mes sin ventas.
//  4. Un tramo de solo domingo no tiene promedio: «—», no «S/ 0».
//  5. Escritorio: la cabecera de días queda fija al desplazar DENTRO de la región.
//  6. Teléfono (≤767 px), para TODO rol: tarjetas por analista, sin tabla ni scroll lateral.
//
// El mock de `crm.facturacion_diaria_fn` responde con datos FIJOS por mes: no hace eco
// de los argumentos (trampa conocida del proyecto), así que un cambio en la forma del
// pedido no puede cambiar la respuesta simulada.
import { expect, test, type Locator, type Page } from '@playwright/test'
import { loginReal, montarBackendReal, UID } from './_helpers'
import { irAModulo } from './_navegacion'

/** Jueves 08/10/2026, 10:00 en Lima: octubre es el mes en curso. */
const HOY_OCTUBRE = new Date('2026-10-08T15:00:00Z')
/** Domingo 01/11/2026, 10:00 en Lima. */
const DOMINGO_1_NOVIEMBRE = new Date('2026-11-01T15:00:00Z')

const CORS: Record<string, string> = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': '*',
  'access-control-allow-methods': '*',
  'access-control-expose-headers': 'content-range',
}

/** Una fila tal y como la devuelve `crm.facturacion_diaria_fn` (columnas snake_case). */
interface FilaRpc {
  dia: string
  tipo: string
  moneda: 'PEN' | 'USD'
  analista_id: string | null
  analista_nombre: string
  supervisor_id: string | null
  supervisor_nombre: string
  operaciones: number
  capital: number
}

interface Persona { id: string; nombre: string }
interface Equipo { supervisor_id: string; supervisor_nombre: string }

const ROSA: Equipo = { supervisor_id: 'a0000000-0000-4000-8000-000000000001', supervisor_nombre: 'SUPERVISORA ROSA' }
const DIEGO: Equipo = { supervisor_id: 'a0000000-0000-4000-8000-000000000002', supervisor_nombre: 'SUPERVISOR DIEGO' }
const ELENA: Equipo = { supervisor_id: 'a0000000-0000-4000-8000-000000000003', supervisor_nombre: 'SUPERVISORA ELENA' }
/** El supervisor que entra: `montarBackendReal` identifica a «yo» con UID («Gerente Real»). */
const EQUIPO_PROPIO: Equipo = { supervisor_id: UID, supervisor_nombre: 'Gerente Real' }

const ANA: Persona = { id: 'b0000000-0000-4000-8000-000000000001', nombre: 'ANA PRUEBA' }
const BRUNO: Persona = { id: 'b0000000-0000-4000-8000-000000000002', nombre: 'BRUNO PRUEBA' }
const CARLA: Persona = { id: 'b0000000-0000-4000-8000-000000000003', nombre: 'CARLA PRUEBA' }
const DANIEL: Persona = { id: 'b0000000-0000-4000-8000-000000000004', nombre: 'DANIEL PRUEBA' }
// Los dos analistas del organigrama compartido de los helpers (equipo_visible_fn).
const UNO: Persona = { id: 'vend-1', nombre: 'Analista Real Uno' }
const DOS: Persona = { id: 'vend-2', nombre: 'Analista Real Dos' }

function venta(
  dia: string,
  moneda: 'PEN' | 'USD',
  capital: number,
  quien: Persona,
  equipo: Equipo,
  tipo = 'contrato_nuevo',
): FilaRpc {
  return {
    dia, tipo, moneda, capital, operaciones: 1,
    analista_id: quien.id, analista_nombre: quien.nombre, ...equipo,
  }
}

// Octubre (hasta el jueves 8): S/ 20,500 y US$ 7,300.
const OCTUBRE: FilaRpc[] = [
  venta('2026-10-01', 'PEN', 12_000, ANA, ROSA),
  venta('2026-10-02', 'USD', 5_000, BRUNO, ROSA),
  venta('2026-10-05', 'PEN', 8_500, CARLA, DIEGO, 'contrato_renovacion'),
  venta('2026-10-06', 'USD', 2_300, DANIEL, DIEGO, 'contrato_upgrade'),
]
// Setiembre: el tramo comparable es del 1 al 8 (S/ 10,000 y US$ 3,000). La venta del 21
// queda FUERA: comparar ocho días contra un mes entero mentiría.
const SETIEMBRE: FilaRpc[] = [
  venta('2026-09-03', 'PEN', 10_000, ANA, ROSA),
  venta('2026-09-04', 'USD', 3_000, BRUNO, ROSA),
  venta('2026-09-21', 'PEN', 50_000, CARLA, DIEGO),
]
// El domingo 01/11 hubo una venta.
const NOVIEMBRE: FilaRpc[] = [venta('2026-11-01', 'PEN', 15_000, ANA, ROSA)]

// Muchos analistas (24 en 3 equipos, más los 2 del organigrama): la malla no cabe en alto.
const EQUIPOS = [ROSA, DIEGO, ELENA] as const
const OCTUBRE_GRANDE: FilaRpc[] = Array.from({ length: 24 }, (_, i) => {
  const n = String(i + 1).padStart(2, '0')
  return venta(
    `2026-10-0${(i % 8) + 1}`,
    i % 5 === 4 ? 'USD' : 'PEN',
    1_000 * (i + 1),
    { id: `c0000000-0000-4000-8000-0000000000${n}`, nombre: `ANALISTA ${n}` },
    EQUIPOS[i % 3] ?? ROSA,
  )
})

// El equipo del supervisor: el servidor ya recorta el ámbito a SUS filas.
const OCTUBRE_SUPERVISOR: FilaRpc[] = [
  venta('2026-10-01', 'PEN', 9_000, UNO, EQUIPO_PROPIO),
  venta('2026-10-07', 'USD', 1_500, UNO, EQUIPO_PROPIO),
  venta('2026-10-02', 'PEN', 4_000, DOS, EQUIPO_PROPIO),
]
const SETIEMBRE_SUPERVISOR: FilaRpc[] = [venta('2026-09-02', 'PEN', 5_000, UNO, EQUIPO_PROPIO)]

// Lo que la pantalla tiene que decir con OCTUBRE + SETIEMBRE y la tasa del mock (3.53):
//  titular  = 20,500 + 7,300 × 3.53 = 20,500 + 25,769 = 46,269
//  anterior = 10,000 + 3,000 × 3.53 = 10,000 + 10,590 = 20,590 (solo del 1 al 8)
//  %        = (46,269 − 20,590) / 20,590 = +124.7 %
// Con la regla vieja, Soles decía +105.0 % (solo soles) y Dólares +143.3 % (solo dólares)
// bajo la MISMA cifra de arriba.
const TITULAR = 'S/ 46,269'
const DELTA = '+124.7 % respecto del mismo tramo del mes anterior'
const TASA = 'tipo de cambio S/ 3.53 (Superintendencia de Banca, Seguros y Pensiones, promedio de 7 días hábiles)'
const SIN_SIGLAS = /\bTC\b|prom\./

/** Mock de la RPC de Facturación: filas fijas por mes, o una caída controlada. */
async function montarFacturacion(
  page: Page,
  porMes: Record<string, FilaRpc[]> | 'error',
): Promise<{ cuerpos: unknown[] }> {
  const cuerpos: unknown[] = []
  await page.route('**/rest/v1/rpc/facturacion_diaria_fn', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    const cuerpo = (route.request().postDataJSON() ?? {}) as { p_mes?: unknown }
    cuerpos.push(cuerpo)
    if (porMes === 'error') {
      return route.fulfill({ status: 500, headers: CORS, json: { code: 'XX000', message: 'Caída controlada del e2e' } })
    }
    return route.fulfill({ status: 200, headers: CORS, json: porMes[String(cuerpo.p_mes)] ?? [] })
  })
  // Fase 4: el inspector consume operaciones. Este fixture sigue siendo local y respeta el ámbito enviado.
  await page.route('**/rest/v1/rpc/listar_operaciones_facturacion_fn', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    const p = route.request().postDataJSON()
    const filas = (porMes === 'error' ? [] : Object.values(porMes).flat()).filter((f) =>
      f.dia >= p.p_desde && f.dia <= p.p_hasta && (!p.p_dias || p.p_dias.includes(f.dia)) &&
      (!p.p_analistas || p.p_analistas.includes(f.analista_id)) && (!p.p_equipo || p.p_equipo === f.supervisor_id) &&
      (!p.p_sin_analista || f.analista_id == null) && (!p.p_sin_equipo || f.supervisor_id == null) &&
      (!p.p_tipos || p.p_tipos.includes(f.tipo)) && (!p.p_moneda || p.p_moneda === f.moneda))
    const ops = filas.flatMap((f) => Array.from({ length: f.operaciones }, () => f))
    const pagina = p.p_pagina ?? 1; const tamano = p.p_tamano ?? 25
    return route.fulfill({ headers: CORS, json: { version: 1, pagina, tamano, total: ops.length,
      totales: (['PEN', 'USD'] as const).flatMap((moneda) => {
        const propias = filas.filter((f) => f.moneda === moneda)
        return propias.length ? [{ moneda, operaciones: propias.reduce((n, f) => n + f.operaciones, 0), monto: propias.reduce((n, f) => n + f.capital, 0) }] : []
      }), filas: ops.slice((pagina - 1) * tamano, pagina * tamano).map((f, i) => ({
        n: (pagina - 1) * tamano + i + 1, fecha: f.dia, tipo: f.tipo, moneda: f.moneda, monto: f.capital / f.operaciones,
        anulado: false, analista_id: f.analista_id, analista_nombre: f.analista_nombre, supervisor_id: f.supervisor_id,
        supervisor_nombre: f.supervisor_nombre, visible: true, cliente_nombre: 'Cliente de ejemplo', estado: 'vigente',
        ...(f.tipo === 'cooperativa' ? { cierre_externo_id: `ejemplo-${i}`, cooperativa: 'Ejemplo', lead_id: null }
          : { contrato_id: `ejemplo-${i}`, numero_contrato: `Ejemplo ${i + 1}`, cliente_id: null }),
      })) } })
  })
  return { cuerpos }
}

const areaFacturacion = (page: Page): Locator => page.locator('[data-vista-scroll="facturacion"]')
const mallaDe = (page: Page): Locator => page.getByRole('region', { name: /^Facturación diaria/ })
/** La tarjeta de un indicador, por el comienzo de su rótulo. */
const indicador = (area: Locator, rotulo: RegExp): Locator => area.locator('.facturacion-resumen > *').filter({ hasText: rotulo })
/** La cifra grande de un indicador. */
const cifra = (tarjeta: Locator): Locator => tarjeta.locator('strong')
const moneda = (area: Locator, nombre: 'Todo S/' | 'Soles' | 'Dólares'): Locator =>
  area.getByRole('group', { name: /^Moneda/ }).getByRole('button', { name: nombre, exact: true })
const tramo = (area: Locator, nombre: 'Mes' | 'Semana' | 'Día'): Locator =>
  area.getByRole('group', { name: 'Tramo que se mira' }).getByRole('button', { name: nombre, exact: true })
const cabecerasDeDia = (page: Page, malla: Locator): Locator =>
  malla.locator('thead th').filter({ has: page.getByRole('button', { name: /^Marcar el / }) })

/** Deja que el navegador pinte (las posiciones `sticky` se recalculan al desplazar). */
async function esperarCuadro(page: Page): Promise<void> {
  await page.evaluate(() => new Promise<void>((listo) => requestAnimationFrame(() => requestAnimationFrame(() => listo()))))
}

/**
 * Desplaza SOLO el área de contenido —lo que hace una persona con el dedo o la rueda— hasta
 * dejar el elemento arriba (o su borde de abajo a la vista). `scrollIntoView` movía además la
 * carcasa de la app, que tiene `overflow: hidden`: un estado al que nadie puede llegar.
 */
async function llevarALaVista(page: Page, elemento: Locator, borde: 'arriba' | 'abajo' = 'arriba'): Promise<void> {
  await elemento.evaluate((nodo, alinear) => {
    const area = nodo.closest('[data-vista-scroll]')
    if (!(area instanceof HTMLElement)) throw new Error('El elemento no está dentro del área de contenido')
    const r = nodo.getBoundingClientRect()
    const a = area.getBoundingClientRect()
    area.scrollTop += alinear === 'arriba' ? r.top - a.top : r.bottom - a.bottom
  }, borde)
  await esperarCuadro(page)
}

/** La carcasa de la app no se desplaza nunca: si algo la movió, lo medido no es lo que se ve. */
async function expectCarcasaQuieta(page: Page): Promise<void> {
  const desplazamientos = await page.evaluate(() => [
    document.scrollingElement?.scrollTop ?? 0,
    document.querySelector('[data-gerencia-movil]')?.scrollTop ?? 0,
    document.querySelector('main')?.scrollTop ?? 0,
  ])
  expect(desplazamientos).toEqual([0, 0, 0])
}

/** ¿El punto central de este elemento es el propio elemento, o algo lo tapa? */
async function seVeSinTapar(elemento: Locator): Promise<boolean> {
  return elemento.evaluate((nodo) => {
    const r = nodo.getBoundingClientRect()
    return nodo.contains(document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2))
  })
}

async function entrarEnEscritorio(page: Page): Promise<Locator> {
  await loginReal(page)
  await irAModulo(page, 'Facturación')
  await expect(page).toHaveURL(/#\/facturacion$/)
  return areaFacturacion(page)
}

test('1 · Gerencia, octubre con soles y dólares: el titular es el total unificado y su % compara lo mismo en las tres vistas', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.clock.setFixedTime(HOY_OCTUBRE)
  await montarBackendReal(page)
  const { cuerpos } = await montarFacturacion(page, { '2026-10-01': OCTUBRE, '2026-09-01': SETIEMBRE })
  const area = await entrarEnEscritorio(page)
  const malla = mallaDe(page)

  const titular = indicador(area, /^Total facturado/)
  await expect(cifra(titular)).toHaveText(TITULAR)
  const resumen = area.locator('.facturacion-resumen')
  expect((await resumen.boundingBox())!.height).toBeLessThanOrEqual(56)
  const medidasHoja = await malla.evaluate((nodo) => {
    const fila = nodo.querySelector('tbody tr:has([data-numero-fila])')!
    return [...fila.children].filter((_, i, hijos) => i < 2 || i === hijos.length - 1)
      .map((el) => ({ posicion: getComputedStyle(el).position, fondo: getComputedStyle(el).backgroundColor }))
  })
  expect(medidasHoja.every((m) => m.posicion === 'sticky' && m.fondo !== 'rgba(0, 0, 0, 0)')).toBe(true)
  const letras = await area.evaluate((nodo) => [...nodo.querySelectorAll('*')].filter((el) => {
    const r = el.getBoundingClientRect()
    return r.width > 0 && r.height > 0 && !el.closest('.sr-only') && [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent?.trim())
  }).map((el) => parseFloat(getComputedStyle(el).fontSize)))
  expect(Math.min(...letras)).toBeGreaterThanOrEqual(14)
  await expect(cifra(titular)).toHaveText(TITULAR)
  await expect(area.locator('.facturacion-contexto')).toBeVisible()
  await expect(area.locator('.facturacion-contexto')).toContainText(`S/ 20,500 + US$ 7,300 al ${TASA}`)
  await expect(area.locator('.facturacion-contexto')).toContainText(DELTA)
  await expect(malla).toHaveAccessibleName('Facturación diaria de octubre de 2026 en Todo S/, Todos los tipos')
  // En «Todo S/» el pie de la malla da la misma cifra que el titular.
  await expect(malla.getByRole('row', { name: /Total de la empresa/ }).getByRole('cell').last()).toHaveText(TITULAR)
  // La tasa se dice sin siglas: ni «TC» ni «prom. 7d».
  await expect(area).not.toContainText(SIN_SIGLAS)
  await page.screenshot({ path: info.outputPath('caso1-escritorio-todo-soles.png') })

  // Vista Soles: aparece el pie con las dos monedas y cuadra con el titular.
  await moneda(area, 'Soles').click()
  await expect(moneda(area, 'Soles')).toHaveAttribute('aria-pressed', 'true')
  await expect(malla).toHaveAccessibleName(/ en Soles, /)
  const pie = malla.getByRole('row', { name: /Total del día en soles/ })
  await expect(pie.getByRole('rowheader')).toContainText(TASA)
  await expect(pie.getByRole('cell').last()).toHaveText(TITULAR)
  // El 2 de octubre solo hubo dólares: US$ 5,000 × 3.53 = S/ 17,650, con la MISMA tasa.
  await expect(pie.getByRole('cell').nth(2)).toContainText('S/ 17,650')
  // La fila de soles puros sigue siendo solo soles.
  await expect(malla.getByRole('row', { name: /Total de la empresa/ }).getByRole('cell').last()).toHaveText('S/ 20,500')
  // El titular no cambia ni de cifra ni de %.
  await expect(indicador(area, /^Total facturado/)).toHaveCount(1)
  await expect(cifra(titular)).toHaveText(TITULAR)
  await expect(area.locator('.facturacion-contexto')).toContainText(DELTA)
  await expect(area).not.toContainText(SIN_SIGLAS)
  await llevarALaVista(page, pie, 'abajo')
  await expectCarcasaQuieta(page)
  await page.screenshot({ path: info.outputPath('caso1-escritorio-pie-soles.png') })

  // Vista Dólares: la misma cifra y el MISMO %.
  await moneda(area, 'Dólares').click()
  await expect(moneda(area, 'Dólares')).toHaveAttribute('aria-pressed', 'true')
  await expect(cifra(titular)).toHaveText(TITULAR)
  await expect(area.locator('.facturacion-contexto')).toContainText(DELTA)
  await expect(malla.getByRole('row', { name: /Total del día en soles/ }).getByRole('cell').last()).toHaveText(TITULAR)

  // Se pidió el mes y el anterior, con la forma exacta de la RPC.
  expect(cuerpos).toEqual(expect.arrayContaining([{ p_mes: '2026-10-01' }, { p_mes: '2026-09-01' }]))
  for (const cuerpo of cuerpos) expect(Object.keys(cuerpo as object)).toEqual(['p_mes'])
})

test('2 · Sin tipo de cambio: «Facturado en soles», un solo reintento que no se desmonta y un pie que no inventa total', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.clock.setFixedTime(HOY_OCTUBRE)
  await montarBackendReal(page)
  await montarFacturacion(page, { '2026-10-01': OCTUBRE, '2026-09-01': SETIEMBRE })
  // La edge del tipo de cambio: primero cae (502); luego la respuesta se queda EN VUELO
  // hasta que la prueba la suelta, y entonces llega la del mock común (3.53, «SBS · prom. 7d»).
  let tasa: 'cae' | 'en vuelo' = 'cae'
  let pedidosTasa = 0
  let soltar!: () => void
  const enVuelo = new Promise<void>((listo) => { soltar = listo })
  await page.route('**/functions/v1/crm-tipo-cambio', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    pedidosTasa += 1
    if (tasa === 'cae') return route.fulfill({ status: 502, headers: CORS, json: { error: 'BCRP no responde (e2e)' } })
    await enVuelo
    return route.fallback()
  })
  const area = await entrarEnEscritorio(page)
  const malla = mallaDe(page)
  // El aviso ya no lleva role="status" (su porqué se anuncia en la región viva): se busca por su texto.
  const noLlego = area.getByText(/^No llegó el tipo de cambio/)
  const consultando = area.getByText('Consultando el tipo de cambio…', { exact: true })
  const reintento = area.getByRole('button', { name: 'Reintentar el tipo de cambio' })
  const pie = malla.getByRole('row', { name: /Total del día en soles/ })

  // La tasa no llegó: la perilla se replegó sola a Soles y el aviso dice por qué.
  await expect(noLlego).toBeVisible()
  await expect(moneda(area, 'Soles')).toHaveAttribute('aria-pressed', 'true')
  await expect(area.getByRole('status').filter({ hasText: 'Soles, no llegó el tipo de cambio' })).toHaveCount(1)
  // Un solo botón de reintento: con el aviso a la vista, el del pie no se duplica.
  await expect(reintento).toHaveCount(1)
  await expect(pie.getByRole('button', { name: 'Reintentar el tipo de cambio' })).toHaveCount(0)
  // El titular no se rotula «Total»…
  const titular = indicador(area, /^Facturado en soles/)
  await expect(cifra(titular)).toHaveText('S/ 20,500')
  await expect(area.locator('.facturacion-contexto')).toContainText('solo soles — falta el tipo de cambio para sumar soles y dólares')
  await expect(area.getByText(/Total facturado/)).toHaveCount(0)
  // …y el pie no afirma un total sin tasa.
  await expect(pie.getByRole('rowheader')).toContainText('total no disponible: falta el tipo de cambio')
  await expect(pie.getByRole('cell').last()).toHaveText('—')
  await expect(area).not.toContainText(SIN_SIGLAS)
  await page.screenshot({ path: info.outputPath('caso2-escritorio-sin-tipo-de-cambio.png') })

  // Si la persona elige Soles a mano, el aviso sobra y el reintento pasa al pie.
  await moneda(area, 'Soles').click()
  await expect(noLlego).toHaveCount(0)
  await expect(pie.getByRole('button', { name: 'Reintentar el tipo de cambio' })).toBeVisible()
  await expect(reintento).toHaveCount(1)
  await moneda(area, 'Todo S/').click()
  await expect(noLlego).toBeVisible()
  await expect(pie.getByRole('button', { name: 'Reintentar el tipo de cambio' })).toHaveCount(0)

  // Reintentar NO desmonta el botón: mientras se consulta, el aviso sigue montado, dice
  // «Consultando…», el botón queda aria-disabled y el foco no se pierde. Sin salto de cifras.
  tasa = 'en vuelo'
  await reintento.click()
  await expect(consultando).toBeVisible()
  await expect(noLlego).toHaveCount(0)
  await expect(reintento).toHaveCount(1)
  await expect(reintento).toHaveAttribute('aria-disabled', 'true')
  await expect(reintento).toBeFocused()
  await expect(moneda(area, 'Soles')).toHaveAttribute('aria-pressed', 'true')
  await expect(cifra(titular)).toHaveText('S/ 20,500')
  await page.screenshot({ path: info.outputPath('caso2-escritorio-reintentando.png') })

  // La tasa llega: el aviso se va, la pantalla vuelve a «Todo S/» con el total completo
  // y el foco, que estaba en el botón que desaparece, pasa a la moneda que se está viendo.
  soltar()
  await expect(reintento).toHaveCount(0)
  await expect(consultando).toHaveCount(0)
  await expect(moneda(area, 'Todo S/')).toHaveAttribute('aria-pressed', 'true')
  await expect(moneda(area, 'Todo S/')).toBeFocused()
  await expect(cifra(indicador(area, /^Total facturado/))).toHaveText(TITULAR)
  expect(pedidosTasa).toBeGreaterThanOrEqual(2)
})

test('3 · La RPC cae: «No se pudo cargar…» y ningún indicador dice «S/ 0»', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.clock.setFixedTime(HOY_OCTUBRE)
  await montarBackendReal(page)
  const { cuerpos } = await montarFacturacion(page, 'error')
  const area = await entrarEnEscritorio(page)

  await expect(area.getByText('No se pudo cargar la facturación de este mes.')).toBeVisible()
  await expect(area.getByRole('button', { name: 'Reintentar', exact: true })).toBeVisible()
  // Una avería no es un mes sin ventas.
  await expect(area.getByText(/Todavía no hay cierres/)).toHaveCount(0)
  await expect(mallaDe(page)).toHaveCount(0)
  const indicadores = area.locator('.facturacion-resumen > *')
  await expect(indicadores).toHaveCount(4)
  for (let i = 0; i < 4; i += 1) {
    await expect(cifra(indicadores.nth(i))).toHaveText('—')
    await expect(indicadores.nth(i)).not.toContainText('S/ 0')
  }
  await expect(area.locator('.facturacion-contexto')).toBeVisible()
  await expect(area.locator('.facturacion-contexto')).toContainText('No se pudo cargar: la cifra no está disponible')
  expect(cuerpos.length).toBeGreaterThan(0)
})

test('4 · Domingo 01/11 con una venta, vista «Día»: el promedio por día hábil es «—», no «S/ 0»', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.clock.setFixedTime(DOMINGO_1_NOVIEMBRE)
  await montarBackendReal(page)
  await montarFacturacion(page, { '2026-11-01': NOVIEMBRE, '2026-10-01': OCTUBRE })
  const area = await entrarEnEscritorio(page)
  await expect(mallaDe(page)).toBeVisible()

  const promedio = indicador(area, /^Promedio por día hábil/)
  // El 1 de un mes que cae en domingo: tampoco hay días hábiles en el mes, todavía.
  await expect(cifra(promedio)).toHaveText('—')

  await tramo(area, 'Día').click()
  await expect(tramo(area, 'Día')).toHaveAttribute('aria-pressed', 'true')
  await expect(area.getByText('Ese día, por tipo: por equipo y por analista')).toBeVisible()
  await expect(cifra(promedio)).toHaveText('—')
  await expect(area.locator('.facturacion-contexto')).toBeVisible()
  await expect(area.locator('.facturacion-contexto')).toContainText('Sin días hábiles en este tramo: el domingo no cuenta')
  await expect(promedio).not.toContainText('S/ 0')
  // Y el dinero de ese domingo sí está en pantalla.
  await expect(cifra(indicador(area, /^Ese día/))).toHaveText('S/ 15,000')
})

test('5 · Escritorio 1440×700: la cabecera de días queda fija al desplazar DENTRO de la región', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 700 })
  await page.clock.setFixedTime(HOY_OCTUBRE)
  await montarBackendReal(page)
  await montarFacturacion(page, { '2026-10-01': OCTUBRE_GRANDE, '2026-09-01': SETIEMBRE })
  await entrarEnEscritorio(page)
  const malla = mallaDe(page)
  await expect(malla.getByRole('rowheader', { name: /ANALISTA 24/ })).toBeVisible()
  await llevarALaVista(page, malla)
  await expectCarcasaQuieta(page)

  // La región tiene altura propia (100dvh − 8rem) y la malla no cabe: se desplaza ELLA.
  const alto = await malla.evaluate((nodo) => ({
    maximo: parseFloat(getComputedStyle(nodo).maxHeight),
    esperado: innerHeight - 8 * parseFloat(getComputedStyle(document.documentElement).fontSize),
    scrollHeight: nodo.scrollHeight,
    clientHeight: nodo.clientHeight,
  }))
  expect(Math.abs(alto.maximo - alto.esperado)).toBeLessThanOrEqual(1)
  expect(alto.scrollHeight).toBeGreaterThan(alto.clientHeight + 300)

  const esquina = malla.locator('thead th').first()
  const dia = cabecerasDeDia(page, malla).first()
  const primeraFila = malla.locator('tbody tr').first()
  const antes = { region: (await malla.boundingBox())!, fila: (await primeraFila.boundingBox())! }

  await malla.evaluate((nodo) => { nodo.scrollTop = 400 })
  await esperarCuadro(page)
  const desplazado = await malla.evaluate((nodo) => nodo.scrollTop)
  expect(desplazado).toBeGreaterThanOrEqual(300)

  const region = (await malla.boundingBox())!
  const cajaEsquina = (await esquina.boundingBox())!
  const cajaDia = (await dia.boundingBox())!
  const cajaFila = (await primeraFila.boundingBox())!
  const cajaThead = (await malla.locator('thead').boundingBox())!
  console.log(`[caso 5] región y=${region.y.toFixed(1)} alto=${region.height.toFixed(1)} · scrollTop=${desplazado} · `
    + `th esquina y=${cajaEsquina.y.toFixed(1)} · th día y=${cajaDia.y.toFixed(1)} · `
    + `elemento thead y=${cajaThead.y.toFixed(1)} · primera fila y: ${antes.fila.y.toFixed(1)} → ${cajaFila.y.toFixed(1)}`)

  // La región no se movió: lo que se desplazó fue la malla dentro de ella.
  expect(Math.abs(region.y - antes.region.y)).toBeLessThanOrEqual(1)
  expect(cajaFila.y).toBeLessThan(antes.fila.y - 300)
  // La cabecera de días (el `sticky` vive en sus celdas `th`) sigue pegada arriba de la región…
  expect(Math.abs(cajaDia.y - region.y)).toBeLessThanOrEqual(3)
  expect(Math.abs(cajaEsquina.y - region.y)).toBeLessThanOrEqual(3)
  // …y se ve por encima de las filas que pasan por debajo.
  expect(await seVeSinTapar(dia)).toBe(true)
  await expectCarcasaQuieta(page)
  await page.screenshot({ path: info.outputPath('caso5-escritorio-cabecera-fija.png') })
})

test.describe('6 · Teléfono 390×844, para todo rol', () => {
  test.use({ viewport: { width: 390, height: 844 }, hasTouch: true })

  /** Las tarjetas sustituyen la malla: sin scroll lateral y blancos táctiles de 44 px. */
  async function comprobarTarjetasDeTelefono(page: Page, tarjetas: Locator): Promise<void> {
    await expect(mallaDe(page)).toHaveCount(0)
    await expect(tarjetas).toBeVisible()
    expect(await tarjetas.locator('.facturacion-tarjeta').count()).toBeGreaterThan(0)
    await llevarALaVista(page, tarjetas)
    const medidas = await tarjetas.evaluate((nodo) => ({
      nombres: [...nodo.querySelectorAll('button[aria-label^="Ver el mes"]')].map((el) => parseFloat(getComputedStyle(el).fontSize)),
      botones: [...nodo.querySelectorAll('button')].map((el) => el.getBoundingClientRect().height),
      ancho: nodo.scrollWidth, visible: nodo.clientWidth,
    }))
    expect(Math.min(...medidas.nombres)).toBeGreaterThanOrEqual(16)
    expect(Math.min(...medidas.botones)).toBeGreaterThanOrEqual(44)
    expect(medidas.ancho).toBeLessThanOrEqual(medidas.visible + 1)
    const primera = tarjetas.locator('.facturacion-tarjeta').first()
    await expect(primera.getByRole('button', { name: /^Ver el mes.*operaci/ })).toBeVisible()
    await expect(primera.getByRole('button', { name: /^Ver el mes/ })).toHaveCount(1)
    await primera.getByRole('button', { name: /^Ver el mes/ }).click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await page.getByRole('button', { name: 'Cerrar detalle' }).click()
    await expectCarcasaQuieta(page)
  }

  test('supervisor: tarjetas de su ámbito, con nombres y cifras legibles', async ({ page }, info) => {
    await page.clock.setFixedTime(HOY_OCTUBRE)
    await montarBackendReal(page, { rolCrm: 'supervisor' })
    await montarFacturacion(page, { '2026-10-01': OCTUBRE_SUPERVISOR, '2026-09-01': SETIEMBRE_SUPERVISOR })
    // En el celular no hay menú de escritorio que esperar: se espera a que la app
    // escriba su primera ruta y se abre Facturación por su enlace.
    await loginReal(page, { esperarWorkspace: false })
    await expect(page).toHaveURL(/#\/[\w-]+/)
    await page.evaluate(() => { window.location.hash = '#/facturacion' })
    const tarjetas = page.getByRole('region', { name: 'Facturación por analista' })
    await expect(tarjetas.getByRole('button', { name: /^Ver el mes de Analista Real Uno: total/ })).toBeVisible()
    await comprobarTarjetasDeTelefono(page, tarjetas)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await page.screenshot({ path: info.outputPath('caso6-telefono-supervisor.png') })
  })

  test('gerencia: lo mismo con la barra inferior', async ({ page }, info) => {
    await page.clock.setFixedTime(HOY_OCTUBRE)
    await montarBackendReal(page)
    await montarFacturacion(page, { '2026-10-01': OCTUBRE_GRANDE, '2026-09-01': SETIEMBRE })
    await loginReal(page, { esperarWorkspace: false })
    await irAModulo(page, 'Facturación')
    await expect(page).toHaveURL(/#\/facturacion$/)
    const tarjetas = page.getByRole('region', { name: 'Facturación por analista' })
    await comprobarTarjetasDeTelefono(page, tarjetas)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await page.screenshot({ path: info.outputPath('caso6-telefono-gerencia.png') })
  })
})

test('7 · Shift+Tab descubre el total de una fila tapada por la cabecera fija', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 700 })
  await page.clock.setFixedTime(HOY_OCTUBRE)
  await montarBackendReal(page)
  await montarFacturacion(page, { '2026-10-01': OCTUBRE_GRANDE, '2026-09-01': SETIEMBRE })
  await entrarEnEscritorio(page)
  const malla = mallaDe(page)
  await expect(malla).toBeVisible()
  await llevarALaVista(page, malla)
  const filas = malla.locator('tbody tr:has([data-numero-fila])')
  const total = filas.nth(3).locator('.facturacion-total button')
  const siguiente = filas.nth(4).getByRole('checkbox')
  await siguiente.focus()
  // Sitúa el centro del total justo bajo la cabecera; el siguiente checkbox queda a la vista.
  await total.evaluate((nodo) => {
    const region = nodo.closest('.facturacion-malla')!
    const cabecera = region.querySelector('thead')!.getBoundingClientRect()
    const caja = nodo.getBoundingClientRect()
    region.scrollTop += caja.top - (region.getBoundingClientRect().top + cabecera.height - caja.height / 2 - 4)
  })
  await esperarCuadro(page)
  await expect(siguiente).toBeFocused()
  expect(await seVeSinTapar(siguiente)).toBe(true)
  expect(await seVeSinTapar(total)).toBe(false)
  await page.keyboard.press('Shift+Tab')
  await expect(total).toBeFocused()
  await expect.poll(() => seVeSinTapar(total)).toBe(true)
  const reservas = await malla.evaluate((nodo) => {
    const estilo = getComputedStyle(nodo)
    const ancho = (selector: string) => nodo.querySelector(selector)!.getBoundingClientRect().width
    return {
      arriba: parseFloat(estilo.scrollPaddingTop), alto: nodo.querySelector('thead')!.getBoundingClientRect().height,
      izquierda: parseFloat(estilo.scrollPaddingLeft), fijas: ancho('thead .facturacion-numero') + ancho('thead .facturacion-nombre'),
      derecha: parseFloat(estilo.scrollPaddingRight), total: ancho('thead .facturacion-total'),
    }
  })
  expect(reservas.arriba).toBeCloseTo(reservas.alto + 4, 1)
  expect(reservas.izquierda).toBeCloseTo(reservas.fijas, 1)
  expect(reservas.derecha).toBeCloseTo(reservas.total, 1)
})

test('8 · A 800×900 las tarjetas conservan los días y el desglose en una región estrecha', async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 900 })
  await page.clock.setFixedTime(HOY_OCTUBRE)
  await montarBackendReal(page)
  await montarFacturacion(page, { '2026-10-01': OCTUBRE, '2026-09-01': SETIEMBRE })
  await loginReal(page, { esperarWorkspace: false })
  await irAModulo(page, 'Facturación')
  const tarjetas = page.getByRole('region', { name: 'Facturación por analista' })
  await expect(tarjetas).toBeVisible()
  await expect(mallaDe(page)).toHaveCount(0)
  const ventaAna = tarjetas.getByRole('button', { name: /^ANA PRUEBA,.*1 de octubre: S\/ 12,000, ver 1 operación$/ })
  await expect(ventaAna).toBeVisible()
  await ventaAna.click()
  await expect(page.locator('.lista-operaciones')).toContainText('S/ 12,000')
})
