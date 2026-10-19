import { expect, test, type Page } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

// Datos ficticios: tres analistas en dos equipos, citas creadas en octubre (y dos
// a fines de septiembre, una con fecha en octubre) y una conversión posterior a su
// entrevista. El servidor entrega cada mes por la fecha prevista de la cita. La consulta V2 no está instalada en el
// backend simulado y la pantalla cae a la consulta V1, que responde este mock.
const id = (n: number) => `85000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const ANALISTAS = [
  { n: 20, nombre: 'ANALISTA UNO', sup: 30, supNombre: 'SUPERVISORA NORTE' },
  { n: 21, nombre: 'ANALISTA DOS', sup: 30, supNombre: 'SUPERVISORA NORTE' },
  { n: 22, nombre: 'ANALISTA TRES', sup: 31, supNombre: 'SUPERVISOR SUR' },
]
// [analista, lead, estado comercial, creada, prevista, moneda, monto, origen]
const CITAS = [
  [0, 101, 'realizada', '2026-10-02', '2026-10-02', 'PEN', 10000, 'formulario'], [0, 102, 'realizada', '2026-10-03', '2026-10-03', 'USD', 2000, 'formulario'],
  [0, 103, 'no_show', '2026-10-04', '2026-10-04', 'PEN', 20000, 'referido'], [0, 104, 'programada', '2026-10-12', '2026-10-12', 'PEN', null, 'formulario'],
  [1, 105, 'programada', '2026-10-18', '2026-10-18', 'PEN', 5000, 'formulario'],
  [2, 106, 'realizada', '2026-10-08', '2026-10-08', 'PEN', 50000, 'formulario'], [2, 107, 'cancelada', '2026-10-15', '2026-10-15', 'PEN', 30000, 'referido'],
  [0, 109, 'programada', '2026-09-30', '2026-10-05', 'PEN', 8000, 'formulario'], [2, 108, 'programada', '2026-09-28', '2026-09-29', 'PEN', 7000, 'formulario'],
] as const

async function montarProyeccion(page: Page) {
  await page.route('**/rest/v1/rpc/citas_gerencia_consulta_fn', async route => {
    const { p_desde: desde, p_hasta: hasta } = route.request().postDataJSON() as { p_desde: string; p_hasta: string }
    const mes = desde.slice(0, 7)
    const delMes = mes === '2026-10'
    const citas = CITAS.map((fila, i) => [fila, i] as const).filter(([fila]) => fila[4].startsWith(mes)).map(([[a, lead, estado, creada, prevista, moneda, monto, origen], i]) => {
      const analista = ANALISTAS[a]!
      return {
        id: id(i + 1), lead_id: id(lead), nombre: `PERSONA ${lead}`, telefono: '+51900000001',
        analista_id: id(analista.n), analista_nombre: analista.nombre, supervisor_id: id(analista.sup), supervisor_nombre: analista.supNombre,
        vence_en: `${prevista}T20:00:00Z`, estado: estado === 'realizada' ? 'completada' : estado === 'programada' ? 'pendiente' : estado,
        estado_comercial: estado, cancelada_por: estado === 'cancelada' ? 'asesor' : null, modalidad: 'virtual', origen, moneda, monto_estimado: monto,
        resultado: 'sin_clasificar', nota: 'Datos ficticios de prueba', reagendada_de: null, creado_en: `${creada}T15:00:00Z`,
        asistencia_registrada_en: estado === 'realizada' ? `${prevista}T21:00:00Z` : null, cierre_posterior: false,
        manual_propio: false, registro_manual: false,
      }
    })
    const leads = citas.map(c => c.lead_id)
    const conversion = { lead_id: id(101), perfil_id: id(501), convertido_en: `${mes}-06T15:00:00Z`, fecha_comercial: `${mes}-06` }
    const configuracion = { citas_por_lead: 1.25, entrevistas_porcentaje: 70, depositos_porcentaje: 70, excluir_manuales_base: false,
      actividad_manuales: 'incluir', conteo_entrevistas: 'citas_realizadas', base_avance: 'actividad_real', base_depositos: 'personas_entrevistadas',
      mes_resultado: 'evento', analista_resultado: 'evento', mes_inicio: mes, mostrar_meta_citas: false }
    await route.fulfill({ json: {
      version: 2, periodo: { desde, hasta }, generado_en: '2026-10-19T17:00:00Z', citas, citas_clientes: 0,
      disponibilidad_depositos: 'conversion_cliente', criterio_depositos: 'fecha_comercial', conversiones: delMes ? [conversion] : [],
      gestion: { version: 2, citas_por_lead: 1.25, entrevistas_porcentaje: 70, depositos_porcentaje: 70, actividad_manuales: 'incluir',
        control: { version: 1, mes_inicio: mes, configuracion }, asignaciones: [], capital: [],
        poblacion: citas.map((c, i) => ({ lead_id: leads[i], nombre: c.nombre, telefono: c.telefono, origen: c.origen, moneda: c.moneda,
          monto_estimado: c.monto_estimado, registro_manual: false, creado_por: c.analista_id, analista_origen_id: c.analista_id,
          primera_asignacion_en: `${mes}-01T15:00:00Z`, analista_origen_nombre: c.analista_nombre, supervisor_origen_id: c.supervisor_id,
          supervisor_origen_nombre: c.supervisor_nombre })),
        conversiones: delMes ? [{ ...conversion, analista_id: id(20), analista_nombre: 'ANALISTA UNO', supervisor_id: id(30),
          supervisor_nombre: 'SUPERVISORA NORTE', contrato_id: null }] : [] },
    } })
  })
}

async function abrirProyeccion(page: Page) {
  await page.clock.setFixedTime(new Date('2026-10-19T17:00:00Z'))
  await montarBackendReal(page)
  await montarProyeccion(page)
  await loginReal(page)
  await page.getByRole('button', { name: 'Citas', exact: true }).click()
  await page.getByRole('tab', { name: 'Proyección' }).click()
  return page.getByRole('table', { name: /Proyección de citas por analista/ })
}
const atajo = (page: Page, nombre: string) => page.getByRole('group', { name: 'Atajos de periodo' }).getByRole('button', { name: nombre, exact: true })
const tiempo = (page: Page, nombre: 'Mes' | 'Semanas' | 'Días') => page.getByRole('group', { name: 'Columnas de tiempo' }).getByRole('button', { name: nombre, exact: true })

test('Proyección: la hoja pinta una fila por analista, un número abre su lista y un embudo filtra', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const hoja = await abrirProyeccion(page)
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
  // Hoja plana: sin bandas por equipo ni pastillas de totales, # continuo; los filtros de arriba no se pintan.
  await expect(hoja.getByRole('button', { name: /^Equipo / })).toHaveCount(0)
  await expect(page.getByRole('group', { name: 'Totales de la proyección' })).toHaveCount(0)
  await expect(hoja.locator('tr.pc-fila td.pc-n0')).toHaveText(['1', '2', '3'])
  await expect(page.getByRole('region', { name: 'Consulta de citas' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Exportar citas' })).toHaveCount(0)
  await expect(hoja.getByRole('row', { name: /^Total · 3 analistas/ })).toBeVisible()
  // Nombres propios: Resultados ya usa «Ticket del mes» y «Cierre proyectado» para otras cifras.
  await expect(hoja.locator('thead th[data-col]')).toHaveText(['Analista', 'Citas', 'Monto S/', 'Ticket cita S/', '% Entrev.', '% Conv.',
    'Proyectado citas S/', 'Referidos', 'Clientes', 'Leads'])
  // Sin desplazamiento horizontal a 1440 px en la vista del mes, aun con esos dos nombres largos.
  const scroll = page.getByRole('region', { name: 'Hoja de proyección por analista' })
  const anchos = await hoja.locator('thead th').evaluateAll(ths => ths.map(th => `${th.textContent}:${Math.round(th.getBoundingClientRect().width)}`).join(' · '))
  expect(await scroll.evaluate(el => el.scrollWidth - el.clientWidth), anchos).toBeLessThanOrEqual(0)
  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
  await page.screenshot({ path: info.outputPath('proyeccion-1440.png'), fullPage: true })

  await hoja.getByRole('button', { name: '4 citas de ANALISTA UNO' }).click()
  const lista = page.getByRole('dialog', { name: 'Citas · ANALISTA UNO' })
  await expect(lista.getByTestId('pc-detalle-conteo')).toHaveText('1–19 oct 2026 · 4 citas')
  await expect(lista.locator('tbody tr')).toHaveCount(4)
  await page.keyboard.press('Escape')
  await expect(lista).toHaveCount(0)

  await hoja.getByRole('button', { name: /^% Conv\. de ANALISTA UNO: 50%/ }).click()
  const vinculadas = page.getByRole('dialog', { name: 'Entrevistas que cerraron cliente · ANALISTA UNO' })
  await expect(vinculadas.locator('tbody tr')).toHaveCount(1)
  await page.keyboard.press('Escape')
  // La hoja lateral devuelve el foco al cerrarse: esperar a que desaparezca antes
  // de abrir un embudo, o ese foco tardío lo cerraría (era intermitente).
  await expect(vinculadas).toHaveCount(0)

  const embudo = hoja.getByRole('button', { name: 'Filtrar Analista' })
  await embudo.click()
  const menu = page.getByRole('dialog', { name: 'Filtrar Analista' })
  await expect(menu.getByRole('searchbox', { name: 'Buscar analista' })).toBeFocused()
  await menu.getByRole('checkbox', { name: 'ANALISTA DOS · 1 cita' }).uncheck()
  await menu.getByRole('button', { name: 'Aplicar' }).click()
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(2)
  await expect(hoja.getByRole('row', { name: /ANALISTA DOS/ })).toHaveCount(0)
  await expect(page.getByRole('group', { name: 'Filtros de columna' })).toContainText('Analista')
  await expect(embudo).toBeFocused()
  await page.getByRole('button', { name: 'Quitar filtro de Analista' }).click()
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)

  // Un rango que cruza meses carga septiembre y lo suma a octubre.
  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–19 oct 2026')
  await page.getByLabel('Desde', { exact: true }).fill('2026-09-25')
  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('25 set – 19 oct 2026')
  await expect(hoja.getByRole('button', { name: '5 citas de ANALISTA UNO' })).toBeVisible()
  await expect(hoja.getByRole('button', { name: '3 citas de ANALISTA TRES' })).toBeVisible()
  await atajo(page, 'S3').click()
  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('15–21 oct 2026')
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(2)
  // El Supervisor de la barra acota la hoja.
  await page.getByRole('group', { name: 'Consulta de la proyección' }).getByLabel('Supervisor').selectOption({ label: 'SUPERVISOR SUR' })
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(1)
  await expect(hoja.getByRole('row', { name: /ANALISTA TRES/ })).toBeVisible()
})

test('Proyección: Semanas y Días ponen columnas de tiempo antes de Citas y cada número abre su lista', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const hoja = await abrirProyeccion(page)
  const uno = hoja.getByRole('row', { name: /ANALISTA UNO/ })
  // ANALISTA UNO, 1–19 oct: tres citas creadas el 2, 3 y 4 (S1) y una el 12 (S2).
  await tiempo(page, 'Semanas').click()
  await expect(tiempo(page, 'Semanas')).toHaveAttribute('aria-pressed', 'true')
  await expect(hoja.locator('thead th.pc-tiempo .sr-only')).toHaveText(['S1 1–7 oct', 'S2 8–14 oct', 'S3 15–19 oct'])
  await expect(hoja.locator('thead th.pc-tcierre')).toContainText('Citas')
  expect(await uno.locator('td').evaluateAll(celdas => celdas.slice(0, 5).map(td => td.textContent))).toEqual(['1', '3', '1', '0', '4'])
  const sumas = await hoja.locator('tbody tr, tfoot tr').evaluateAll(filas => filas.map(tr => {
    const n = [...tr.querySelectorAll('td')].map(td => Number(td.textContent))
    return n[1]! + n[2]! + n[3]! - n[4]!
  }))
  expect(sumas).toEqual([0, 0, 0, 0])
  await page.screenshot({ path: info.outputPath('proyeccion-semanas-1440.png'), fullPage: true })
  await uno.getByRole('button', { name: '3 citas de ANALISTA UNO, S1 1–7 oct' }).click()
  const semana = page.getByRole('dialog', { name: 'Citas · S1 1–7 oct · ANALISTA UNO' })
  await expect(semana.getByTestId('pc-detalle-conteo')).toHaveText('1–7 oct 2026 · 3 citas')
  await expect(semana.locator('tbody tr')).toHaveCount(3)
  await page.keyboard.press('Escape')
  await expect(semana).toHaveCount(0)
  // Un mes completo en Semanas (4 semanas) y un rango de un mes que cruza dos (5) caben a 1440 px sin desplazar la hoja.
  const scroll = page.getByRole('region', { name: 'Hoja de proyección por analista' })
  for (const [desde, hasta, semanas] of [['2026-10-01', '2026-10-31', 4], ['2026-09-20', '2026-10-20', 5]] as const) {
    await page.getByLabel('Desde', { exact: true }).fill(desde)
    await page.getByLabel('Hasta', { exact: true }).fill(hasta)
    await expect(hoja.locator('thead th.pc-tiempo')).toHaveCount(semanas)
    const anchos = await hoja.locator('thead th').evaluateAll(ths => ths.map(th => `${th.textContent}:${Math.round(th.getBoundingClientRect().width)}`).join(' · '))
    expect(await scroll.evaluate(el => el.scrollWidth - el.clientWidth), `${desde} → ${hasta}: ${anchos}`).toBeLessThanOrEqual(0)
    await page.screenshot({ path: info.outputPath(`proyeccion-semanas-${semanas}-1440.png`), fullPage: true })
  }
  await atajo(page, 'Mes').click()
  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–19 oct 2026')

  await tiempo(page, 'Días').click()
  await expect(hoja.locator('thead th.pc-tiempo')).toHaveCount(19)
  await expect(hoja.locator('thead th.pc-hoy .sr-only')).toHaveText('lun 19 oct')
  await expect(hoja.locator('thead th.pc-domingo')).toHaveCount(3)
  // La hoja se desplaza dentro de su contenedor, nunca la página; # y Analista quedan fijos.
  expect(await scroll.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true)
  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
  const nombre = uno.getByRole('rowheader')
  const antes = await nombre.boundingBox()
  await scroll.evaluate(el => { el.scrollLeft = el.scrollWidth })
  expect((await nombre.boundingBox())?.x).toBe(antes?.x)
  await scroll.evaluate(el => { el.scrollLeft = 0 })
  await page.screenshot({ path: info.outputPath('proyeccion-dias-1440.png'), fullPage: true })
  await uno.getByRole('button', { name: '1 cita de ANALISTA UNO, 2 oct' }).click()
  const dia = page.getByRole('dialog', { name: 'Citas · 2 oct · ANALISTA UNO' })
  await expect(dia.getByTestId('pc-detalle-conteo')).toHaveText('2 oct 2026 · 1 cita')
  await expect(dia.locator('tbody tr')).toHaveCount(1)
  await page.keyboard.press('Escape')
  await expect(dia).toHaveCount(0)
  // Con más de 31 días, «Días» se deshabilita y la hoja cae a semanas.
  await page.getByLabel('Desde', { exact: true }).fill('2026-09-01')
  await expect(tiempo(page, 'Días')).toBeDisabled()
  await expect(tiempo(page, 'Semanas')).toHaveAttribute('aria-pressed', 'true')
  await expect(hoja.locator('thead th.pc-tiempo .sr-only').first()).toHaveText('S1 1–7 set')
})

test('Proyección: el mes sin citas muestra la hoja vacía sin errores y en el celular solo desplaza la hoja', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const hoja = await abrirProyeccion(page)
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
  // Los filtros de arriba no se pintan en Proyección: el periodo se elige en su barra.
  await page.getByLabel('Desde', { exact: true }).fill('2026-08-01')
  await page.getByLabel('Hasta', { exact: true }).fill('2026-08-31')
  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–31 ago 2026')
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(0)
  await expect(hoja.getByRole('row', { name: /^Total · 0 analistas/ })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Exportar CSV' })).toBeDisabled()
  await expect(page.getByRole('alert')).toHaveCount(0)
  await expect(page.getByText('No hay citas con esta combinación')).toHaveCount(0)
  await atajo(page, 'Mes').click()
  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–19 oct 2026')
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
  const scroll = page.getByRole('region', { name: 'Hoja de proyección por analista' })
  expect(await scroll.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true)
  await page.screenshot({ path: info.outputPath('proyeccion-390.png'), fullPage: true })
  // Con cuatro pestañas, a 375 y 320 px ninguna queda fuera de la pantalla.
  for (const ancho of [375, 320]) {
    await page.setViewportSize({ width: ancho, height: 800 })
    const pestanas = page.getByRole('tablist', { name: 'Cómo ver las citas' })
    expect(await pestanas.evaluate(el => el.scrollWidth - el.clientWidth), `${ancho} px`).toBeLessThanOrEqual(0)
    await expect(page.getByRole('tab', { name: 'Proyección' })).toBeInViewport()
    expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
  }
  await page.screenshot({ path: info.outputPath('proyeccion-320.png') })
})
