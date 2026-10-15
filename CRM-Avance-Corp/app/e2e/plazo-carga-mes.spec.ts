import { expect, test, type Page, type Route } from '@playwright/test'
import { loginReal, mesPlazoCargaReal, montarBackendReal, plazosCargaMesReal } from './_helpers'
import { irAModulo } from './_navegacion'

// «Plazo de carga» en Configuración (Gerencia; DISENO.md de plazo-carga-mes): ver hasta
// cuándo cuenta cada mes, ampliarlo o reabrir el mes sellado, y leer qué movió.
// El estado de partida es el de PRODUCCIÓN el 14/10: setiembre reabierto por
// script, sin decisión y con el plazo normal (10/10) vencido; octubre en curso.

const HOY = '2026-10-14'
const MOTIVO = 'Los analistas aún cargan ventas de setiembre'
const SEPTIEMBRE = mesPlazoCargaReal({
  mes: '2026-09', mes_nombre: 'setiembre 2026', plazo_base_ultimo_dia: '2026-10-10', plazo_ultimo_dia: '2026-10-10',
})
const OCTUBRE = mesPlazoCargaReal({
  mes: '2026-10', mes_nombre: 'octubre 2026', plazo_base_ultimo_dia: '2026-11-10', plazo_ultimo_dia: '2026-11-10',
})

type Cuerpo = { p_periodo: string; p_ultimo_dia: string; p_motivo: string }

/** Las dos puertas del plazo, con estado: lo que se fija es lo que la lectura devuelve después. */
async function montarPlazo(page: Page, inicial: Record<string, unknown>[], fijar: (cuerpo: Cuerpo) => { status: number; json: unknown }) {
  let meses = inicial
  const pedidos: Cuerpo[] = []
  const fallidas: string[] = []
  page.on('response', (respuesta) => {
    if (/\/rpc\/(plazos_carga_mes_fn|fijar_plazo_carga_mes)$/.test(new URL(respuesta.url()).pathname) && respuesta.status() >= 400) {
      fallidas.push(`${respuesta.status()} ${new URL(respuesta.url()).pathname}`)
    }
  })
  await page.route('**/rest/v1/rpc/plazos_carga_mes_fn', (ruta: Route) => {
    if (ruta.request().method() !== 'POST') return ruta.fallback()
    return ruta.fulfill({ json: plazosCargaMesReal(HOY, meses) })
  })
  await page.route('**/rest/v1/rpc/fijar_plazo_carga_mes', (ruta: Route) => {
    if (ruta.request().method() !== 'POST') return ruta.fallback()
    const cuerpo = ruta.request().postDataJSON() as Cuerpo
    pedidos.push(cuerpo)
    const respuesta = fijar(cuerpo)
    if (respuesta.status === 200) {
      meses = meses.map((m) => m.mes !== cuerpo.p_periodo.slice(0, 7) ? m : {
        ...m,
        sellado: false,
        reabrible: false,
        plazo_ultimo_dia: cuerpo.p_ultimo_dia,
        ampliado: cuerpo.p_ultimo_dia > String(m.plazo_base_ultimo_dia),
        decision: { ultimo_dia: cuerpo.p_ultimo_dia, motivo: cuerpo.p_motivo, decidido_por: 'GERENTE REAL', decidido_en: '2026-10-14T10:05:00-05:00' },
        ultima_reapertura: m.sellado ? { reabierto_en: '2026-10-14T10:05:00-05:00', decidido_por: 'GERENTE REAL' } : m.ultima_reapertura,
      })
    }
    return ruta.fulfill({ status: respuesta.status, json: respuesta.json })
  })
  return { pedidos, fallidas }
}

function acuse(cuerpo: Cuerpo, over: Record<string, unknown> = {}) {
  return {
    ok: true, mes: cuerpo.p_periodo.slice(0, 7), ultimo_dia: cuerpo.p_ultimo_dia, plazo_hasta: '2026-10-21T05:00:00+00:00',
    reabierto: false, reapertura_id: null, acreditaciones_reevaluadas: 12, conflictos_identidad: 0, ventas_devueltas: [],
    ...over,
  }
}

test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-10-14T15:00:00.000Z'))
})

test('Gerencia ve setiembre vencido, amplía su plazo y lee el resultado', async ({ page }, info) => {
  await montarBackendReal(page, { rolCrm: 'gerencia' })
  const { pedidos, fallidas } = await montarPlazo(page, [SEPTIEMBRE, OCTUBRE], (cuerpo) => ({ status: 200, json: acuse(cuerpo) }))
  await loginReal(page)
  await irAModulo(page, 'Configuración')

  const tarjeta = page.getByRole('region', { name: 'Plazo de carga' })
  const setiembre = tarjeta.getByRole('listitem').filter({ hasText: 'Setiembre 2026' })
  await expect(setiembre).toContainText('Setiembre 2026 · el plazo de carga venció el 10 oct.')
  await expect(setiembre).toContainText('su conversión queda fuera de plazo')
  await expect(tarjeta.getByRole('listitem').filter({ hasText: 'Octubre 2026' })).toContainText('Octubre 2026 · se puede cargar hasta el 10 nov.')
  await tarjeta.screenshot({ path: info.outputPath('plazo-carga-produccion.png') })

  await tarjeta.getByRole('button', { name: 'Ampliar plazo de setiembre 2026' }).click()
  const dialogo = page.getByRole('dialog', { name: 'Ampliar el plazo de setiembre 2026' })
  const fecha = dialogo.getByLabel('Último día para cargar')
  await expect(fecha).toBeFocused()
  await expect(fecha).toHaveAttribute('min', HOY)
  await fecha.fill('2026-10-20')
  await dialogo.getByLabel('Motivo').fill(MOTIVO)
  await dialogo.screenshot({ path: info.outputPath('plazo-carga-dialogo.png') })
  await dialogo.getByRole('button', { name: 'Guardar plazo' }).click()

  await expect(dialogo).toHaveCount(0)
  await expect(tarjeta.getByRole('status')).toContainText('Setiembre 2026: se puede cargar hasta el 20 oct.')
  await expect(tarjeta.getByRole('status')).toContainText('Se volvieron a revisar 12 conversiones con el plazo nuevo.')
  await expect(setiembre).toContainText('Setiembre 2026 · se puede cargar hasta el 20 oct.')
  await expect(setiembre).toContainText(`Ampliado por GERENTE REAL el 14 oct. · «${MOTIVO}»`)
  await expect(setiembre).not.toContainText('fuera de plazo')
  await tarjeta.screenshot({ path: info.outputPath('plazo-carga-ampliado.png') })

  expect(pedidos).toEqual([{ p_periodo: '2026-09-01', p_ultimo_dia: '2026-10-20', p_motivo: MOTIVO }])
  expect(fallidas).toEqual([])
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})

test('reabrir setiembre sellado: la negativa del servidor se lee tal cual; al reabrir, la venta devuelta', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia' })
  let intentos = 0
  const { pedidos } = await montarPlazo(
    page,
    [{ ...SEPTIEMBRE, sellado: true, reabrible: true }, OCTUBRE],
    (cuerpo) => {
      intentos += 1
      if (intentos === 1) {
        return { status: 400, json: { code: 'P0409', message: 'Hay ventas en cooperativa de setiembre 2026 imputadas a otro mes sin rastro de registro tardío: revisar con soporte', details: null, hint: null } }
      }
      return {
        status: 200,
        json: acuse(cuerpo, {
          reabierto: true, reapertura_id: '55555555-5555-4555-8555-555555555555', acreditaciones_reevaluadas: 3,
          ventas_devueltas: [{ cooperativa: 'qorilazo', monto: '20000.00', moneda: 'PEN', fecha_comercial: '2026-09-15', imputada_antes_a: '2026-10-13' }],
        }),
      }
    },
  )
  await loginReal(page)
  await irAModulo(page, 'Configuración')

  const tarjeta = page.getByRole('region', { name: 'Plazo de carga' })
  const setiembre = tarjeta.getByRole('listitem').filter({ hasText: 'Setiembre 2026' })
  await expect(setiembre).toContainText('Setiembre 2026 · cerrado · se pudo cargar hasta el 10 oct.')
  await setiembre.getByRole('button', { name: 'Reabrir setiembre' }).click()

  const dialogo = page.getByRole('dialog', { name: 'Reabrir setiembre 2026' })
  await expect(dialogo).toContainText('Se retira el cierre de setiembre; se vuelve a sellar solo al vencer este plazo.')
  await dialogo.getByLabel('Último día para cargar').fill('2026-10-20')
  await dialogo.getByLabel('Motivo').fill(MOTIVO)
  await dialogo.getByRole('button', { name: 'Reabrir setiembre' }).click()

  await expect(dialogo.getByRole('alert')).toHaveText('Hay ventas en cooperativa de setiembre 2026 imputadas a otro mes sin rastro de registro tardío: revisar con soporte')
  await expect(dialogo.getByLabel('Motivo')).toHaveValue(MOTIVO)

  await dialogo.getByRole('button', { name: 'Reabrir setiembre' }).click()
  await expect(dialogo).toHaveCount(0)
  const aviso = tarjeta.getByRole('status')
  await expect(aviso).toContainText('Setiembre 2026 reabierto: se puede cargar hasta el 20 oct.')
  await expect(aviso).toContainText('Venta devuelta a setiembre: COOPAC Qorilazo · S/ 20,000 · del 15 set. (estaba contada el 13 oct.).')
  await expect(setiembre).toContainText('Reabierto por GERENTE REAL el 14 oct.')
  await expect(setiembre.getByRole('button', { name: 'Ampliar plazo de setiembre 2026' })).toBeVisible()
  expect(pedidos).toHaveLength(2)
})
