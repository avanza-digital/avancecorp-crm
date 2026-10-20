import { readFile } from 'node:fs/promises'
import { expect, test, type Page } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

// Datos ficticios: tres analistas en dos equipos, citas creadas en octubre (y dos
// a fines de septiembre, una con fecha en octubre) y dos conversiones posteriores a su
// entrevista. El servidor entrega cada mes por la fecha prevista de la cita. La consulta V2 no está instalada en el
// backend simulado y la pantalla cae a la consulta V1, que responde este mock. Además, tres reuniones de
// ANALISTA TRES con clientes SIN lead (Fase 0b), del lector propio de la Proyección.
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
// [tarea, persona, creada, prevista, estado, asistencia] de ANALISTA TRES (SUPERVISOR SUR).
const REUNIONES_CLIENTES = [
  [201, 'persona', '2026-10-06', '2026-10-07', 'completada', '2026-10-07T16:00:00Z'],
  [202, 'perfil', '2026-10-09', '2026-10-10', 'no_show', null],
  [203, 'oculta', '2026-10-11', '2026-10-25', 'pendiente', null],
] as const

async function montarProyeccion(page: Page) {
  // Una llamada por rango: las reuniones con clientes sin lead CREADAS (día de Lima) en él.
  await page.route('**/rest/v1/rpc/citas_clientes_proyeccion_fn', async route => {
    const { p_desde: desde, p_hasta: hasta } = route.request().postDataJSON() as { p_desde: string; p_hasta: string }
    const citas = REUNIONES_CLIENTES.filter(([, , creada]) => creada >= desde && creada <= hasta).map(([n, persona, creada, prevista, estado, asistencia]) => {
      const cliente = id(n + 100)
      const identidad = persona === 'oculta'
        ? { sujeto_tipo: 'inversionista', sujeto_id: null, sujeto_nombre: 'Cliente fuera de tu cartera', inversionista_id: null, perfil_id: null, identidad_visible: false, identidad_persona: `oculta:${id(n)}` }
        : persona === 'persona'
          ? { sujeto_tipo: 'inversionista', sujeto_id: cliente, sujeto_nombre: 'CLIENTE SIN LEAD UNO', inversionista_id: cliente, perfil_id: null, identidad_visible: true, identidad_persona: `persona:${cliente}` }
          : { sujeto_tipo: 'perfil', sujeto_id: cliente, sujeto_nombre: 'CLIENTE SIN LEAD DOS', inversionista_id: null, perfil_id: cliente, identidad_visible: true, identidad_persona: `perfil:${cliente}` }
      return { id: id(n), creado_en: `${creada}T15:00:00Z`, vence_en: `${prevista}T15:00:00Z`, estado, cancelada_por: null, asistencia_registrada_en: asistencia,
        analista_id: id(22), analista_nombre: 'ANALISTA TRES', supervisor_id: id(31), supervisor_nombre: 'SUPERVISOR SUR', ...identidad }
    })
    await route.fulfill({ json: { version: 1, periodo: { desde, hasta }, criterio: 'creado_en', generado_en: '2026-10-19T17:00:00Z', citas } })
  })
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
    // ANALISTA TRES vende a quien entrevistó el 08/10 (lead 106): su fila tiene % Conv. y Proyectado.
    const conversionTres = { lead_id: id(106), perfil_id: id(506), convertido_en: `${mes}-10T15:00:00Z`, fecha_comercial: `${mes}-10` }
    const configuracion = { citas_por_lead: 1.25, entrevistas_porcentaje: 70, depositos_porcentaje: 70, excluir_manuales_base: false,
      actividad_manuales: 'incluir', conteo_entrevistas: 'citas_realizadas', base_avance: 'actividad_real', base_depositos: 'personas_entrevistadas',
      mes_resultado: 'evento', analista_resultado: 'evento', mes_inicio: mes, mostrar_meta_citas: false }
    await route.fulfill({ json: {
      version: 2, periodo: { desde, hasta }, generado_en: '2026-10-19T17:00:00Z', citas, citas_clientes: 0,
      disponibilidad_depositos: 'conversion_cliente', criterio_depositos: 'fecha_comercial', conversiones: delMes ? [conversion, conversionTres] : [],
      gestion: { version: 2, citas_por_lead: 1.25, entrevistas_porcentaje: 70, depositos_porcentaje: 70, actividad_manuales: 'incluir',
        control: { version: 1, mes_inicio: mes, configuracion }, asignaciones: [], capital: [],
        poblacion: citas.map((c, i) => ({ lead_id: leads[i], nombre: c.nombre, telefono: c.telefono, origen: c.origen, moneda: c.moneda,
          monto_estimado: c.monto_estimado, registro_manual: false, creado_por: c.analista_id, analista_origen_id: c.analista_id,
          primera_asignacion_en: `${mes}-01T15:00:00Z`, analista_origen_nombre: c.analista_nombre, supervisor_origen_id: c.supervisor_id,
          supervisor_origen_nombre: c.supervisor_nombre })),
        conversiones: delMes ? [{ ...conversion, analista_id: id(20), analista_nombre: 'ANALISTA UNO', supervisor_id: id(30),
          supervisor_nombre: 'SUPERVISORA NORTE', contrato_id: null }, { ...conversionTres, analista_id: id(22), analista_nombre: 'ANALISTA TRES',
          supervisor_id: id(31), supervisor_nombre: 'SUPERVISOR SUR', contrato_id: null }] : [] },
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
const desbordePagina = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)

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

  // Exportar: un menú con la hoja por analista y las citas del periodo; Esc lo cierra y devuelve el foco.
  const exportar = page.getByRole('button', { name: 'Exportar', exact: true })
  await exportar.click()
  const menuExportar = page.getByRole('menu')
  await expect(menuExportar.getByRole('menuitem')).toHaveText(['Hoja por analista', 'Citas del periodo'])
  await expect(menuExportar.getByRole('menuitem', { name: 'Hoja por analista' })).toBeFocused()
  await page.screenshot({ path: info.outputPath('proyeccion-exportar-1440.png') })
  await page.keyboard.press('Escape')
  await expect(menuExportar).toHaveCount(0)
  await expect(exportar).toBeFocused()
  // «Citas del periodo» trae exactamente las 10 que suma Citas del total: 5 con lead, 2 de ANALISTA TRES y sus 3 reuniones con clientes sin lead.
  await expect(hoja.getByRole('button', { name: '10 citas de todos los analistas' })).toBeVisible()
  await exportar.click()
  const descarga = page.waitForEvent('download')
  await page.getByRole('menuitem', { name: 'Citas del periodo' }).click()
  const archivo = await descarga
  expect(archivo.suggestedFilename()).toBe('proyeccion-citas-del-periodo-2026-10-01_2026-10-19.csv')
  const filas = (await readFile((await archivo.path())!, 'utf8')).replace(/^\uFEFF/, '').split('\r\n')
  expect(filas[0]).toBe('"Código de cita","Creada","Fecha","Hora","Persona","Analista","Supervisor","Estado","Moneda","Monto","Monto S/","Origen"')
  expect(filas).toHaveLength(11)
  const reuniones = filas.filter(f => f.endsWith('"Cliente"'))
  expect(reuniones.map(f => f.slice(1, 37)).sort()).toEqual([id(201), id(202), id(203)])
  expect(reuniones.every(f => f.includes('"ANALISTA TRES","SUPERVISOR SUR"'))).toBe(true)
  await expect(page.getByText('Se descargaron las 10 citas del periodo.')).toBeVisible()

  await hoja.getByRole('button', { name: '4 citas de ANALISTA UNO' }).click()
  const lista = page.getByRole('dialog', { name: 'Citas · ANALISTA UNO' })
  await expect(lista.getByTestId('pc-detalle-conteo')).toHaveText('1–19 oct 2026 · 4 citas')
  await expect(lista.locator('tbody tr')).toHaveCount(4)
  await page.keyboard.press('Escape')
  await expect(lista).toHaveCount(0)

  const conversion = hoja.getByRole('button', { name: /^% Conv\. de ANALISTA UNO: 50%/ })
  await conversion.click()
  const vinculadas = page.getByRole('dialog', { name: 'Entrevistas que cerraron cliente · ANALISTA UNO' })
  await expect(vinculadas.locator('tbody tr')).toHaveCount(1)
  await page.keyboard.press('Escape')
  // La hoja lateral devuelve el foco al cerrarse (en el cuadro siguiente): esperar a
  // que desaparezca Y a que el foco vuelva a su cifra antes de abrir un embudo, o ese
  // foco tardío lo cerraría o lo reiniciaría (intermitente, 1 de cada 4–5 corridas).
  await expect(vinculadas).toHaveCount(0)
  await expect(conversion).toBeFocused()

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
  // ANALISTA TRES: 3 citas con lead (una de septiembre) + 3 reuniones con clientes sin lead.
  await expect(hoja.getByRole('button', { name: '6 citas de ANALISTA TRES' })).toBeVisible()
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
  // El # depende del orden (las reuniones con clientes suben a ANALISTA TRES): se comparan tramos y Citas.
  expect(await uno.locator('td').evaluateAll(celdas => celdas.slice(1, 5).map(td => td.textContent))).toEqual(['3', '1', '0', '4'])
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

test('Proyección: el mes sin citas muestra la hoja vacía sin errores y en el celular pinta tarjetas sin desplazar la página', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const hoja = await abrirProyeccion(page)
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
  // Los filtros de arriba no se pintan en Proyección: el periodo se elige en su barra.
  await page.getByLabel('Desde', { exact: true }).fill('2026-08-01')
  await page.getByLabel('Hasta', { exact: true }).fill('2026-08-31')
  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–31 ago 2026')
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(0)
  await expect(hoja.getByRole('row', { name: /^Total · 0 analistas/ })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Exportar', exact: true })).toBeDisabled()
  await expect(page.getByRole('alert')).toHaveCount(0)
  await expect(page.getByText('No hay citas con esta combinación')).toHaveCount(0)
  await atajo(page, 'Mes').click()
  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–19 oct 2026')
  await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
  // En el celular la hoja se vuelve tarjetas: el Total primero y una por analista, en el orden de la hoja.
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(hoja).toHaveCount(0)
  const tarjetas = page.getByRole('list', { name: /^Proyección de citas por analista/ }).getByRole('listitem')
  await expect(tarjetas).toHaveCount(4)
  await expect(tarjetas.first()).toContainText('Total · 3 analistas')
  expect(await desbordePagina(page)).toBeLessThanOrEqual(0)
  await page.screenshot({ path: info.outputPath('proyeccion-390.png'), fullPage: true })
  // Una cifra de la tarjeta abre la misma lista que en la hoja.
  const uno = tarjetas.filter({ hasText: 'ANALISTA UNO' })
  await uno.getByRole('button', { name: '4 citas de ANALISTA UNO' }).click()
  const lista = page.getByRole('dialog', { name: 'Citas · ANALISTA UNO' })
  await expect(lista.getByTestId('pc-detalle-conteo')).toHaveText('1–19 oct 2026 · 4 citas')
  await expect(lista.locator('tbody tr')).toHaveCount(4)
  await page.keyboard.press('Escape')
  await expect(lista).toHaveCount(0)
  // Días: la fila de tramos se desplaza dentro de la tarjeta, nunca la página.
  await tiempo(page, 'Días').click()
  const dias = uno.getByRole('group', { name: 'Citas por día de ANALISTA UNO' })
  await expect(dias.locator('.pc-tiempo')).toHaveCount(19)
  expect(await dias.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true)
  expect(await desbordePagina(page)).toBeLessThanOrEqual(0)
  await tiempo(page, 'Mes').click()
  // A 375 y 320 px: ninguna pestaña ni control de la barra, del orden o de los filtros queda fuera de la pantalla.
  for (const ancho of [375, 320]) {
    await page.setViewportSize({ width: ancho, height: 800 })
    const pestanas = page.getByRole('tablist', { name: 'Cómo ver las citas' })
    expect(await pestanas.evaluate(el => el.scrollWidth - el.clientWidth), `${ancho} px`).toBeLessThanOrEqual(0)
    await expect(page.getByRole('tab', { name: 'Proyección' })).toBeInViewport()
    await expect(tarjetas).toHaveCount(4)
    const fuera = await page.locator('.pc-periodo, .pc-controles').locator('button, select, input').evaluateAll(controles => controles
      .filter(c => { const r = c.getBoundingClientRect(); return r.left < -0.5 || r.right > window.innerWidth + 0.5 })
      .map(c => c.getAttribute('aria-label') ?? c.textContent))
    expect(fuera, `${ancho} px`).toEqual([])
    expect(await desbordePagina(page), `${ancho} px`).toBeLessThanOrEqual(0)
  }
  await page.screenshot({ path: info.outputPath('proyeccion-320.png') })
  // «Filtros» abre los mismos embudos de la hoja, dentro de la pantalla; al cerrarlo el foco vuelve a «Filtros».
  const filtros = page.getByRole('button', { name: /^Filtros/ })
  await filtros.click()
  await page.getByRole('menuitem', { name: 'Analista' }).click()
  const embudo = page.getByRole('dialog', { name: 'Filtrar Analista' })
  await expect(embudo.getByRole('searchbox', { name: 'Buscar analista' })).toBeFocused()
  const caja = (await embudo.boundingBox())!
  expect(caja.x).toBeGreaterThanOrEqual(0)
  expect(caja.x + caja.width).toBeLessThanOrEqual(320)
  await embudo.getByRole('checkbox', { name: 'ANALISTA DOS · 1 cita' }).uncheck()
  await embudo.getByRole('button', { name: 'Aplicar' }).click()
  await expect(tarjetas).toHaveCount(3)
  await expect(filtros).toBeFocused()
  await expect(filtros).toHaveAccessibleName('Filtros, 1 con filtro')
  expect(await desbordePagina(page)).toBeLessThanOrEqual(0)
})

test('Proyección: las reuniones con clientes sin lead cuentan en Citas, Clientes y % Entrev., no en Monto, Ticket ni Proyectado', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const hoja = await abrirProyeccion(page)
  const tres = hoja.getByRole('row', { name: /ANALISTA TRES/ })
  // 2 citas con lead (106 realizada, 107 cancelada) + 3 reuniones (completada, no asistió, pendiente).
  await expect(tres.getByRole('button', { name: '5 citas de ANALISTA TRES' })).toBeVisible()
  await expect(tres.getByRole('button', { name: '3 citas con clientes de ANALISTA TRES' })).toBeVisible()
  // Monto y Ticket cita: solo las 2 citas con lead (S/ 80,000 ÷ 2).
  await expect(tres.getByRole('button', { name: 'S/ 80,000 en citas de ANALISTA TRES' })).toBeVisible()
  await expect(tres.locator('td').nth(3)).toHaveText('S/40,000')
  // % Entrev.: (1 + 1) entrevistas ÷ (1 + 2) resueltas. % Conv. y Proyectado, de las citas con lead: 2 × 100 % × 100 % × S/ 40,000.
  await expect(tres.getByRole('button', { name: /^% Entrev\. de ANALISTA TRES: 66\.7%/ })).toBeVisible()
  await expect(tres.getByRole('button', { name: /^% Conv\. de ANALISTA TRES: 100%/ })).toBeVisible()
  await expect(tres.locator('td.pc-proyectado')).toHaveText('S/80,000')
  await page.screenshot({ path: info.outputPath('proyeccion-clientes-1440.png'), fullPage: true })

  // Embudo de Clientes: estas personas, la redactada con el texto del servidor.
  await hoja.getByRole('button', { name: 'Filtrar Clientes' }).click()
  const menu = page.getByRole('dialog', { name: 'Filtrar Clientes' })
  await expect(menu.getByRole('checkbox')).toHaveCount(4)
  for (const nombre of ['Cliente fuera de tu cartera · 1 cita', 'CLIENTE SIN LEAD DOS · 1 cita', 'CLIENTE SIN LEAD UNO · 1 cita']) {
    await expect(menu.getByRole('checkbox', { name: nombre })).toBeChecked()
  }
  await page.keyboard.press('Escape')
  await expect(menu).toHaveCount(0)

  // Lista de Clientes: sin botón de ficha (no tienen lead), monto «—» y origen Cliente.
  await tres.getByRole('button', { name: '3 citas con clientes de ANALISTA TRES' }).click()
  const lista = page.getByRole('dialog', { name: 'Citas con clientes · ANALISTA TRES' })
  await expect(lista.getByTestId('pc-detalle-conteo')).toHaveText('1–19 oct 2026 · 3 citas')
  await expect(lista.locator('tbody tr')).toHaveCount(3)
  await expect(lista.locator('tbody button')).toHaveCount(0)
  await expect(lista.getByRole('row', { name: /CLIENTE SIN LEAD UNO/ })).toContainText('Realizada')
  await expect(lista.getByRole('row', { name: /CLIENTE SIN LEAD DOS/ })).toContainText('No asistió')
  await expect(lista.getByRole('row', { name: /Cliente fuera de tu cartera/ })).toContainText('Programada')
  await expect(lista.locator('tbody td.pc-num')).toHaveText(['—', '—', '—'])
  await expect(lista.locator('tbody .pc-origen')).toHaveText(['Cliente', 'Cliente', 'Cliente'])
  await page.keyboard.press('Escape')
  await expect(lista).toHaveCount(0)
})
