// Pipeline · columna «Gestionado» (01/10/2026).
//
// Entre «Nuevo» y «Contactado»: leads que ya se intentaron contactar y cuyo
// cliente aún no responde. NO es una etapa —por dentro siguen en `nuevo`—, es
// una vista que calcula el servidor (`cartera_filtrada_fn`, `p_gestion`). Lo que
// solo se puede comprobar aquí, con la app entera: que la tarjeta cambia de
// columna SIN recargar al registrar el intento, que el arrastre de verdad
// respeta que «Gestionado» no es destino, y que un servidor que todavía no
// conoce el parámetro deja el tablero operable y sin cifras inventadas.
import { expect, test, type Locator, type Page } from '@playwright/test'
import {
  abrirLead,
  bloquearSupabase,
  entrarDemo,
  irAPipeline,
  leadReal,
  loginReal,
  montarBackendReal,
  UID,
} from './_helpers'

const AYUDA = 'Se llena sola al registrar un intento de contacto.'
/** Las columnas del tablero (el menú lateral y el filtro también usan `group`). */
const columnas = (page: Page) => page.locator('[role="group"][aria-labelledby^="pipeline-columna-"]')
const columna = (page: Page, nombre: string) => page.locator('main').getByRole('group', { name: nombre, exact: true })
const tarjeta = (page: Page, col: string, lead: string) => columna(page, col).getByText(lead, { exact: true })

/** La tarjeta ENTERA de un lead en una columna (el nodo que recibe el foco). */
const nodoTarjeta = (page: Page, col: string, leadId: string) =>
  columna(page, col).locator(`[data-foco-clave="lead-${leadId}"]`)
const reintentar = (page: Page, col: string, texto = 'No se pudo cargar') =>
  columna(page, col).getByRole('button', { name: `${texto} · Reintentar la columna ${col}`, exact: true })

/** Registra «No contestó» en una ficha YA ABIERTA: un intento, no una conversación. */
async function registrarNoContestoEn(page: Page, ficha: Locator) {
  await ficha.getByRole('button', { name: /Copiar el número .* y registrar la llamada/ }).click()
  const panel = page.getByRole('dialog', { name: /Cómo salió la llamada/ })
  await panel.getByRole('radio', { name: /^No contestó/ }).check()
  await panel.getByRole('checkbox', { name: /Agendar próxima acción/ }).uncheck()
  await panel.getByRole('button', { name: 'Guardar', exact: true }).click()
  // El panel solo se cierra cuando el servidor confirmó la llamada.
  await expect(panel).toHaveCount(0)
  // `.last()`: el aviso dura 15 s y puede seguir a la vista el de una llamada anterior.
  await expect(page.getByText(/Llamada registrada/).last()).toBeVisible()
}

/** Abre la ficha con un clic, registra «No contestó» y la cierra. */
async function registrarNoContesto(page: Page, nombre: RegExp) {
  const ficha = await abrirLead(page, nombre)
  await registrarNoContestoEn(page, ficha)
  // La ficha abierta se actualiza con la misma gestión que mueve la tarjeta.
  await expect(ficha.getByRole('group', { name: 'Etapa del lead' }).locator('[aria-current="step"]')).toHaveText('Gestionado')
  await expect(ficha.getByText('Gestionado', { exact: true })).toHaveCount(2)
  await page.keyboard.press('Escape')
  await expect(ficha).toBeHidden()
}

const MIO = leadReal({ vendedor_id: UID })
const CONTACTADO = leadReal({
  id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', nombre_completo: 'CLIENTE YA CONTACTADO',
  telefono: '+51999000222', etapa: 'contactado', vendedor_id: UID,
})

test('sesión real: al registrar un intento la tarjeta pasa de «Nuevo» a «Gestionado» sin recargar', async ({ page }) => {
  const backend = await montarBackendReal(page, { rolCrm: 'vendedor', leads: [MIO, CONTACTADO] })
  const pedidos: Array<Record<string, unknown>> = []
  page.on('request', (peticion) => {
    if (peticion.url().endsWith('/rest/v1/rpc/cartera_filtrada_fn')) pedidos.push(peticion.postDataJSON() as Record<string, unknown>)
  })
  await loginReal(page)
  await irAPipeline(page)

  // Cinco columnas, en orden, y cada lead `nuevo` en UNA sola de las dos mitades.
  await expect(columnas(page)).toHaveCount(5)
  for (const [i, nombre] of ['Nuevo', 'Gestionado', 'Contactado', 'Cita agendada', 'Entrevista realizada'].entries()) {
    await expect(columnas(page).nth(i)).toHaveAccessibleName(nombre)
  }
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toBeVisible()
  await expect(page.getByText('CLIENTE REAL UNO', { exact: true })).toHaveCount(1)
  // ESTADO DE PRODUCCIÓN al estrenar: «Gestionado» vacía, y lo dice.
  await expect(columna(page, 'Gestionado').getByText('Sin leads gestionados por ahora')).toBeVisible()
  await expect(columna(page, 'Gestionado').getByText(AYUDA)).toBeVisible()
  await expect(columna(page, 'Gestionado')).toHaveAccessibleDescription(AYUDA)
  await expect(columna(page, 'Gestionado').getByRole('button', { name: /agregar lead/i })).toHaveCount(0)

  // Cada columna pidió su lista: la gestión solo viaja en las dos de `nuevo`.
  const recorte = (etapa: string) => pedidos.filter((p) => p.p_etapa === etapa).map((p) => p.p_gestion ?? null)
  await expect.poll(() => recorte('nuevo')).toEqual(expect.arrayContaining(['con_gestion', 'sin_gestion']))
  expect(recorte('nuevo')).not.toContain(null)
  for (const etapa of ['contactado', 'reunion_agendada', 'propuesta_enviada']) {
    expect(new Set(recorte(etapa)), etapa).toEqual(new Set([null]))
  }

  // Marca en la página viva: si algo recargara, desaparecería.
  await page.evaluate(() => { (window as unknown as { __sinRecarga: boolean }).__sinRecarga = true })
  await registrarNoContesto(page, /CLIENTE REAL UNO/)

  // El lead sigue en etapa `nuevo` (un intento no es una conversación)…
  expect(backend.leads[0]).toMatchObject({ etapa: 'nuevo', vendedor_id: UID })
  expect(backend.actividades).toHaveLength(1)
  expect(backend.actividades[0]).toMatchObject({ tipo: 'llamada_no_contestada' })
  // …pero cambió de columna, y sin recargar la página.
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toBeVisible()
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toHaveCount(0)
  await expect(page.getByText('CLIENTE REAL UNO', { exact: true })).toHaveCount(1)
  await expect(columna(page, 'Nuevo').getByText('Sin leads en esta etapa')).toBeVisible()
  expect(await page.evaluate(() => (window as unknown as { __sinRecarga?: boolean }).__sinRecarga)).toBe(true)

  // Una tarjeta de «Gestionado» se mueve como cualquier `nuevo`; el menú no
  // ofrece «Gestionado» ni «Nuevo» (ya está en esa etapa).
  await columna(page, 'Gestionado').getByRole('button', { name: 'Acciones de CLIENTE REAL UNO', exact: true }).click()
  await expect(page.getByRole('menuitem')).toHaveText(['Abrir ficha', 'Contactado', 'Cita agendada', 'Entrevista realizada'])
  await page.getByRole('menuitem', { name: 'Contactado' }).click()
  await expect(tarjeta(page, 'Contactado', 'CLIENTE REAL UNO')).toBeVisible()
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toHaveCount(0)
  await expect.poll(() => backend.llamadas.patchLead).toBe(1)
  expect(backend.leads[0]).toMatchObject({ etapa: 'contactado' })
})

test('sesión real: «Gestionado» no es destino del arrastre; Contactado sí', async ({ page }) => {
  const backend = await montarBackendReal(page, { rolCrm: 'vendedor', leads: [MIO, CONTACTADO] })
  await loginReal(page)
  await irAPipeline(page)
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toBeVisible()
  const carril = (nombre: string) => columna(page, nombre).locator('.ac-scroll')

  // Soltar una tarjeta de «Nuevo» sobre «Gestionado»: no pasa nada y no se
  // llama al servidor. La columna se llena sola; no se arrastra hasta ella.
  await tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO').dragTo(carril('Gestionado'))
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toBeVisible()
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toHaveCount(0)
  expect(backend.llamadas.patchLead).toBe(0)
  // Tampoco una de «Contactado».
  await tarjeta(page, 'Contactado', 'CLIENTE YA CONTACTADO').dragTo(carril('Gestionado'))
  await expect(tarjeta(page, 'Contactado', 'CLIENTE YA CONTACTADO')).toBeVisible()
  expect(backend.llamadas.patchLead).toBe(0)
  // Un soltar rechazado no llega como `drop`: aun así el arrastre terminó, y
  // un clic vuelve a abrir la ficha (el tablero no se queda sordo).
  const ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await page.keyboard.press('Escape')
  await expect(ficha).toBeHidden()

  // El tablero no queda mudo tras el rechazo: el mismo arrastre a un destino
  // real SÍ mueve el lead.
  await tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO').dragTo(carril('Contactado'))
  await expect(tarjeta(page, 'Contactado', 'CLIENTE REAL UNO')).toBeVisible()
  await expect.poll(() => backend.llamadas.patchLead).toBe(1)
  expect(backend.leads[0]).toMatchObject({ etapa: 'contactado' })
})

// Decisión de Miguel: un lead REASIGNADO que el analista anterior ya intentó es
// «Nuevo» para el analista actual. Solo cuenta lo gestionado en la tenencia
// vigente — y eso lo decide el servidor; el tablero solo tiene que seguirlo.
test('sesión real: reasignar devuelve a «Nuevo» un lead que el analista anterior ya había intentado', async ({ page }) => {
  const lead = leadReal({ vendedor_id: 'vend-1', creado_en: '2026-07-01T00:00:00.000Z' })
  const backend = await montarBackendReal(page, {
    leads: [lead],
    actividades: [{
      id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', lead_id: lead.id, tipo: 'whatsapp_enviado', detalle: null,
      creado_en: '2026-07-02T15:00:00.000Z', autor_nombre: 'Analista Real Uno',
    }],
  })
  await loginReal(page)
  await irAPipeline(page)
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toBeVisible()

  const ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await ficha.getByLabel('Reasignar responsable comercial').selectOption('vend-2')
  await expect.poll(() => backend.leads[0]?.vendedor_id).toBe('vend-2')
  await page.keyboard.press('Escape')
  await expect(ficha).toBeHidden()

  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toBeVisible()
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toHaveCount(0)
  await expect(columna(page, 'Gestionado').getByText('Sin leads gestionados por ahora')).toBeVisible()
})

// ESTADO DE PRODUCCIÓN («gate de realidad»): la pantalla puede publicarse antes
// que la migración. Un servidor que aún no conoce `p_gestion` no encuentra la
// función con esa firma (PGRST202) en las dos listas que lo mandan.
test('servidor todavía sin el parámetro: lo dice, no inventa cifras y el resto del tablero se opera', async ({ page }) => {
  const backend = await montarBackendReal(page, { rolCrm: 'vendedor', leads: [MIO, CONTACTADO] })
  let servidorViejo = true
  await page.route('**/rest/v1/rpc/cartera_filtrada_fn', async (route) => {
    const cuerpo = (route.request().postDataJSON() ?? {}) as { p_gestion?: string }
    if (servidorViejo && cuerpo.p_gestion != null) {
      return route.fulfill({ status: 404, json: {
        code: 'PGRST202', details: null, hint: null,
        message: 'Could not find the function crm.cartera_filtrada_fn(p_etapa, p_gestion, p_limite) in the schema cache',
      } })
    }
    return route.fallback()
  })
  await loginReal(page)
  await irAPipeline(page)

  for (const nombre of ['Nuevo', 'Gestionado']) {
    const col = columna(page, nombre)
    await expect(col.getByText('No se pudo cargar esta columna')).toBeVisible()
    await expect(reintentar(page, nombre)).toBeVisible()
    // Ni «0» ni «Sin leads»: de lo que no se pudo leer no se afirma nada.
    await expect(col.getByText('Total no disponible')).toBeAttached()
    await expect(col.getByText('0', { exact: true })).toHaveCount(0)
    await expect(col.getByText('Sin leads', { exact: true })).toHaveCount(0)
  }
  await expect(page.getByText('CLIENTE REAL UNO', { exact: true })).toHaveCount(0)
  await expect(columna(page, 'Gestionado').getByText(AYUDA)).toBeVisible()

  // Las columnas que no mandan el parámetro cargan y se operan.
  await expect(tarjeta(page, 'Contactado', 'CLIENTE YA CONTACTADO')).toBeVisible()
  await columna(page, 'Contactado').getByRole('button', { name: 'Acciones de CLIENTE YA CONTACTADO', exact: true }).click()
  await page.getByRole('menuitem', { name: 'Cita agendada' }).click()
  await expect(tarjeta(page, 'Cita agendada', 'CLIENTE YA CONTACTADO')).toBeVisible()
  await expect.poll(() => backend.llamadas.patchLead).toBe(1)

  // Llega la migración: «Reintentar» recupera cada columna sin recargar.
  servidorViejo = false
  await reintentar(page, 'Nuevo').click()
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toBeVisible()
  // Con teclado: el botón desaparece al recuperarse la columna y el foco no se
  // pierde — pasa a la columna que se acaba de recuperar.
  await reintentar(page, 'Gestionado').focus()
  await page.keyboard.press('Enter')
  await expect(columna(page, 'Gestionado').getByText('Sin leads gestionados por ahora')).toBeVisible()
  await expect(columna(page, 'Gestionado')).toBeFocused()
  await expect(page.getByRole('button', { name: /Reintentar/ })).toHaveCount(0)
})

// Regla del 01/10: un resultado de llamada DESHECHO no cuenta como gestión.
test('sesión real: «Deshacer» el resultado de la llamada devuelve la tarjeta a «Nuevo»', async ({ page }) => {
  const backend = await montarBackendReal(page, { rolCrm: 'vendedor', leads: [MIO, CONTACTADO] })
  await loginReal(page)
  await irAPipeline(page)
  await registrarNoContesto(page, /CLIENTE REAL UNO/)
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toBeVisible()

  // El aviso de la llamada ofrece «Deshacer» durante 15 segundos.
  await page.getByRole('button', { name: 'Deshacer', exact: true }).click()
  await expect(page.getByText(/^Deshecho: /)).toBeVisible()

  // La llamada sigue en el timeline, marcada como deshecha: ya no es gestión.
  expect(backend.actividades).toHaveLength(1)
  expect(backend.actividades[0]).toMatchObject({
    tipo: 'llamada_no_contestada', metadata: { evento: 'resultado_llamada', deshecho_en: expect.any(String) },
  })
  expect(backend.leads[0]).toMatchObject({ etapa: 'nuevo', vendedor_id: UID })
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toBeVisible()
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toHaveCount(0)
  await expect(columna(page, 'Gestionado').getByText('Sin leads gestionados por ahora')).toBeVisible()
  const ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await expect(ficha.getByRole('group', { name: 'Etapa del lead' }).locator('[aria-current="step"]')).toHaveText('Nuevo')
  await expect(ficha.getByText('Nuevo', { exact: true })).toHaveCount(2)
})

// La tenencia es de la FILA y la sella el servidor: al nacer con analista, al
// asignar, al reasignar y al REABRIR un descartado, aunque vuelva al mismo
// analista. Un lead con analista y sin tenencia no tiene gestión vigente.
test('sesión real: descartar y reabrir estrena tenencia; sin tenencia no hay gestión', async ({ page }) => {
  const sinTenencia = leadReal({
    id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', nombre_completo: 'CLIENTE SIN TENENCIA',
    telefono: '+51999000333', vendedor_id: UID, tenencia_desde: null,
  })
  const backend = await montarBackendReal(page, {
    rolCrm: 'vendedor',
    leads: [MIO, sinTenencia],
    actividades: [{
      id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', lead_id: sinTenencia.id, tipo: 'whatsapp_enviado', detalle: null,
      creado_en: '2026-07-02T15:00:00.000Z', autor_nombre: 'Analista Real Uno',
    }],
  })
  // Lo que el servidor sirve en cada mitad de `nuevo`, fila por fila.
  const servidas: Array<{ gestion: string | null; id: string; tenencia_desde: string | null }> = []
  page.on('response', (respuesta) => {
    if (!respuesta.url().endsWith('/rest/v1/rpc/cartera_filtrada_fn') || !respuesta.ok()) return
    const pedido = (respuesta.request().postDataJSON() ?? {}) as { p_gestion?: string }
    void respuesta.json().then((cuerpo: { items?: Array<{ id: string; tenencia_desde: string | null }> }) => {
      for (const fila of cuerpo.items ?? []) servidas.push({ gestion: pedido.p_gestion ?? null, id: fila.id, tenencia_desde: fila.tenencia_desde })
    }).catch(() => { /* respuesta cancelada por una relectura: no hay filas que anotar */ })
  })
  await loginReal(page)
  await irAPipeline(page)

  // Tiene analista y un WhatsApp enviado, pero NO tiene tenencia: es «Nuevo».
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE SIN TENENCIA')).toBeVisible()
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toBeVisible()
  await expect(columna(page, 'Gestionado').getByText('Sin leads gestionados por ahora')).toBeVisible()

  await registrarNoContesto(page, /CLIENTE REAL UNO/)
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toBeVisible()
  // Nació con su analista: su tenencia es la del alta, y así se sirve.
  await expect.poll(() => servidas.find((f) => f.id === MIO.id && f.gestion === 'con_gestion')?.tenencia_desde).toBe(MIO.creado_en)

  // Descartar desde la ficha: sale del tablero y se queda sin tenencia.
  const ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await ficha.getByRole('button', { name: /descartar/i }).click()
  await page.getByRole('dialog', { name: 'Descartar lead' }).getByRole('button', { name: /descartar/i }).click()
  await expect(ficha.getByText('Lead descartado')).toBeVisible()
  await expect.poll(() => backend.leads[0]?.etapa).toBe('descartado')
  expect(backend.leads[0]?.tenencia_desde).toBeNull()
  await expect(page.locator('main').getByText('CLIENTE REAL UNO', { exact: true })).toHaveCount(0)

  // Reabrir por la puerta ordinaria (no es el «Deshacer»): vuelve a `nuevo`, con
  // el MISMO analista y una tenencia nueva.
  await ficha.getByRole('button', { name: 'Reabrir', exact: true }).click()
  await expect(page.getByText(/Lead reabierto/)).toBeVisible()
  await expect.poll(() => backend.leads[0]?.etapa).toBe('nuevo')
  expect(backend.leads[0]?.vendedor_id).toBe(UID)
  const tenenciaNueva = backend.leads[0]?.tenencia_desde
  const intentoAnterior = backend.actividades.find((a) => a.lead_id === MIO.id)
  expect(intentoAnterior).toMatchObject({ tipo: 'llamada_no_contestada' })
  expect(Date.parse(String(tenenciaNueva))).toBeGreaterThan(Date.parse(String(intentoAnterior?.creado_en)))
  await page.keyboard.press('Escape')
  await expect(ficha).toBeHidden()

  // Su intento de antes sigue en el timeline, pero es anterior a la tenencia
  // nueva: la tarjeta es «Nuevo» otra vez.
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toBeVisible()
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toHaveCount(0)
  // Y la fila se sirve con esa tenencia nueva, en la mitad «sin gestión».
  await expect.poll(() => servidas.some((f) => f.id === MIO.id && f.gestion === 'sin_gestion' && f.tenencia_desde === tenenciaNueva)).toBe(true)

  // Un intento en la tenencia nueva sí cuenta.
  await registrarNoContesto(page, /CLIENTE REAL UNO/)
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toBeVisible()
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE SIN TENENCIA')).toBeVisible()

  // La lista nunca contradice a su filtro: lo servido como «con gestión» trae
  // siempre tenencia, y el lead sin tenencia jamás salió en esa mitad.
  await expect.poll(() => servidas.some((f) => f.id === MIO.id && f.gestion === 'con_gestion' && f.tenencia_desde === tenenciaNueva)).toBe(true)
  const conGestion = servidas.filter((f) => f.gestion === 'con_gestion')
  expect(conGestion.every((f) => f.tenencia_desde != null)).toBe(true)
  expect(conGestion.some((f) => f.id === sinTenencia.id)).toBe(false)
  const delSinTenencia = servidas.filter((f) => f.id === sinTenencia.id)
  expect(delSinTenencia.length).toBeGreaterThan(0)
  expect(delSinTenencia.every((f) => f.gestion === 'sin_gestion' && f.tenencia_desde === null)).toBe(true)
})

// Revisión, punto 1 — en un navegador de verdad. Con la tarjeta en vuelo, otra
// pestaña registra el intento y el tablero se pone al día: la tarjeta salta a
// «Gestionado» y su nodo de origen desaparece. El navegador ya no le entrega
// `dragend` a nadie y, si se suelta donde no se recibe, tampoco hay `drop`.
test('sesión real: si la tarjeta cambia de columna en pleno arrastre, el tablero no se queda sordo', async ({ page }) => {
  // Monitor ancho: las cinco columnas a la vista. Aquí el ratón se mueve a mano
  // (no con `dragTo`), y fuera de la ventana no hay columna sobre la que pasar.
  await page.setViewportSize({ width: 1920, height: 1080 })
  const backend = await montarBackendReal(page, { rolCrm: 'vendedor', leads: [MIO, CONTACTADO] })
  await loginReal(page)
  await irAPipeline(page)
  await expect(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO')).toBeVisible()
  const centro = async (objetivo: Locator) => {
    const caja = await objetivo.boundingBox()
    if (!caja) throw new Error('Sin caja que medir')
    return { x: caja.x + caja.width / 2, y: caja.y + caja.height / 2 }
  }
  const origen = await centro(tarjeta(page, 'Nuevo', 'CLIENTE REAL UNO'))
  const sobreCita = await centro(columna(page, 'Cita agendada').locator('.ac-scroll'))

  await page.mouse.move(origen.x, origen.y)
  await page.mouse.down()
  await page.mouse.move(sobreCita.x, sobreCita.y, { steps: 12 })
  // El arrastre está en curso: «Cita agendada» se ofrece como destino.
  await expect(columna(page, 'Cita agendada').getByText('Suelta aquí para mover el lead')).toBeVisible()

  // Otra pestaña registra «no contestó»; al volver el foco el tablero se pone al día.
  backend.actividades.push({
    id: 'ffffffff-ffff-4fff-8fff-ffffffffffff', lead_id: MIO.id, tipo: 'llamada_no_contestada', detalle: null,
    creado_en: new Date().toISOString(), autor_nombre: 'Analista Real Uno',
  })
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toBeVisible()
  // El arrastre de aquel nodo se dio por terminado sin esperar a `drop` ni a
  // `dragend`: con el ratón todavía encima, la columna deja de ofrecerse.
  await expect(columna(page, 'Cita agendada').getByText('Sin leads en esta etapa')).toBeVisible()
  await expect(columna(page, 'Cita agendada').getByText('Suelta aquí para mover el lead')).toHaveCount(0)

  await page.mouse.up()
  // Soltar ya no mueve nada: la tarjeta que se arrastraba dejó de existir.
  expect(backend.llamadas.patchLead).toBe(0)
  await expect(tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO')).toBeVisible()
  // Y el tablero sigue vivo: un clic abre la ficha…
  const ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await page.keyboard.press('Escape')
  await expect(ficha).toBeHidden()
  // …y el siguiente arrastre funciona, también desde «Gestionado».
  await tarjeta(page, 'Gestionado', 'CLIENTE REAL UNO').dragTo(columna(page, 'Contactado').locator('.ac-scroll'))
  await expect(tarjeta(page, 'Contactado', 'CLIENTE REAL UNO')).toBeVisible()
  await expect.poll(() => backend.llamadas.patchLead).toBe(1)
})

// Accesibilidad. La tarjeta que se abrió con el teclado cambia de columna con
// la ficha abierta, y eso es OTRO nodo: sin más, al cerrar la ficha el foco cae
// a <body> y el siguiente Tab reinicia la página. Hay dos carreras posibles y
// en las dos el foco tiene que acabar en la tarjeta, ya en «Gestionado».
for (const caso of ['las listas llegan con la ficha abierta', 'la ficha se cierra antes de que lleguen las listas'] as const) {
  test(`teclado: tras registrar el intento el foco sigue a la tarjeta hasta «Gestionado» (${caso})`, async ({ page }) => {
    await montarBackendReal(page, { rolCrm: 'vendedor', leads: [MIO, CONTACTADO] })
    // Compuerta sobre las listas del tablero: retenidas, la ficha se cierra con
    // la tarjeta todavía en «Nuevo»; después se sueltan en el orden que se quiera.
    let retener = false
    let retenidas: Array<{ gestion: string | null; soltar: () => void }> = []
    await page.route('**/rest/v1/rpc/cartera_filtrada_fn', async (route) => {
      if (retener) {
        const gestion = ((route.request().postDataJSON() ?? {}) as { p_gestion?: string }).p_gestion ?? null
        await new Promise<void>((soltar) => { retenidas.push({ gestion, soltar }) })
      }
      // Una relectura puede cancelar la petición retenida: no hay a quién responder.
      await route.fallback().catch(() => {})
    })
    const soltarListas = (cuales: (gestion: string | null) => boolean) => {
      for (const lista of retenidas.filter((r) => cuales(r.gestion))) lista.soltar()
      retenidas = retenidas.filter((r) => !cuales(r.gestion))
    }
    await loginReal(page)
    await irAPipeline(page)

    const enNuevo = nodoTarjeta(page, 'Nuevo', MIO.id)
    const enGestionado = nodoTarjeta(page, 'Gestionado', MIO.id)
    await enNuevo.focus()
    await expect(enNuevo).toBeFocused()
    await page.keyboard.press('Enter')
    const ficha = page.getByRole('dialog', { name: /CLIENTE REAL UNO/ })
    await expect(ficha).toBeVisible()

    retener = caso === 'la ficha se cierra antes de que lleguen las listas'
    await registrarNoContestoEn(page, ficha)
    if (retener) {
      // La ficha se cierra con el tablero aún sin enterarse: el foco vuelve al
      // nodo de siempre, que sigue ahí…
      await page.keyboard.press('Escape')
      await expect(ficha).toBeHidden()
      await expect(enNuevo).toBeFocused()
      // Las dos mitades de `nuevo` ya se pidieron y siguen retenidas.
      await expect.poll(() => ['sin_gestion', 'con_gestion'].every((g) => retenidas.some((r) => r.gestion === g))).toBe(true)
      // …y cuando por fin llegan las listas, ese nodo desaparece. «Nuevo» y
      // «Gestionado» son dos respuestas: aquí llega antes la de «Nuevo», y por
      // un momento la tarjeta no está en ninguna de las dos columnas.
      retener = false
      soltarListas((gestion) => gestion !== 'con_gestion')
      await expect(enNuevo).toHaveCount(0)
      await expect(enGestionado).toHaveCount(0)
      soltarListas((gestion) => gestion === 'con_gestion')
    } else {
      // La tarjeta cambia de columna DETRÁS de la ficha, que sigue abierta.
      await expect(enGestionado).toBeAttached()
      await expect(enNuevo).toHaveCount(0)
      await page.keyboard.press('Escape')
      await expect(ficha).toBeHidden()
    }

    await expect(enGestionado).toBeVisible()
    await expect(enGestionado).toBeFocused()
    // El teclado sigue donde estaba: Enter vuelve a abrir la ficha desde ahí.
    await page.keyboard.press('Enter')
    await expect(ficha).toBeVisible()
  })
}

test('demo: la columna se calcula en el navegador y un intento mueve la tarjeta, sin tocar el servidor', async ({ page }) => {
  const peticiones = await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  await irAPipeline(page)

  await expect(columnas(page)).toHaveCount(5)
  for (const [i, nombre] of ['Nuevo', 'Gestionado', 'Contactado', 'Cita agendada', 'Entrevista realizada'].entries()) {
    await expect(columnas(page).nth(i)).toHaveAccessibleName(nombre)
  }
  // El fixture trae a JUAN con una llamada sin respuesta de hoy; TERESA no
  // tiene ninguna gestión.
  await expect(tarjeta(page, 'Gestionado', 'JUAN PÉREZ ROJAS')).toBeVisible()
  await expect(tarjeta(page, 'Nuevo', 'TERESA GONZALES PAZ')).toBeVisible()
  await expect(columna(page, 'Gestionado').getByText(AYUDA)).toBeVisible()

  await registrarNoContesto(page, /TERESA GONZALES PAZ/)

  await expect(tarjeta(page, 'Gestionado', 'TERESA GONZALES PAZ')).toBeVisible()
  await expect(tarjeta(page, 'Nuevo', 'TERESA GONZALES PAZ')).toHaveCount(0)
  expect(peticiones()).toBe(0)
})

test('escala: las columnas conservan sus 290 px; caben las cinco en un monitor ancho y se deslizan en un portátil', async ({ page }) => {
  await page.setViewportSize({ width: 1920, height: 1080 })
  await entrarDemo(page, 'Gerencia')
  await irAPipeline(page)

  const medir = () => page.evaluate(() => {
    const columnas = [...document.querySelectorAll<HTMLElement>('[role="group"][aria-labelledby^="pipeline-columna-"]')]
    const carril = columnas[0]!.parentElement!
    const ayuda = columnas[1]!.querySelector<HTMLElement>('.ac-scroll > p')!
    return {
      anchos: columnas.map((c) => Math.round(c.getBoundingClientRect().width)),
      // Cabeceras de una sola línea: mismo alto y mismo arranque de carril.
      carrilesDesde: [...new Set(columnas.map((c) => Math.round(c.querySelector('.ac-scroll')!.getBoundingClientRect().top)))],
      carrilesHasta: [...new Set(columnas.map((c) => Math.round(c.querySelector('.ac-scroll')!.getBoundingClientRect().bottom)))],
      desliza: carril.scrollWidth > carril.clientWidth + 1,
      letraAyuda: Number.parseFloat(getComputedStyle(ayuda).fontSize),
    }
  })

  const ancho = await medir()
  expect(ancho.anchos).toEqual([290, 290, 290, 290, 290])
  expect(ancho.desliza).toBe(false)
  expect(ancho.carrilesDesde).toHaveLength(1)
  expect(ancho.carrilesHasta).toHaveLength(1)
  // La explicación de la columna no se achica: detalle legible.
  expect(ancho.letraAyuda).toBeGreaterThanOrEqual(14)

  // Portátil con el menú abierto: no se estrechan (recortaría nombres y
  // cabeceras); el carril se desliza en horizontal.
  await page.setViewportSize({ width: 1366, height: 768 })
  const portatil = await medir()
  expect(portatil.anchos).toEqual([290, 290, 290, 290, 290])
  expect(portatil.desliza).toBe(true)
  expect(portatil.carrilesDesde).toHaveLength(1)
})
