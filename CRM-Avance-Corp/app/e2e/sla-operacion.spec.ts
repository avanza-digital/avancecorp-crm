import { expect, test, type Page } from '@playwright/test'
import { abrirLead, irAPipeline, leadReal, loginReal, montarBackendReal, UID } from './_helpers'
import type { EstadoSlaV2 } from '../src/lib/sla-operacion'
import muestraSql from '../src/data/sla-operacion-sql.fixture.json' with { type: 'json' }

async function irASeguimiento(page: Page) {
  await page.getByRole('button', { name: 'Seguimiento', exact: true }).click()
  await expect(page).toHaveURL(/#\/seguimiento$/)
  await expect(page.getByRole('heading', { name: 'Seguimiento comercial', exact: true })).toBeVisible()
}

type PedidoCola = {
  p_cursor: { inicio: number } | null
  p_limite: number
  p_senal: string
  p_etapa: string | null
  p_analista_id: string | null
}

async function montarColaEquipo(page: Page, rolCrm: 'gerencia' | 'supervisor') {
  const analistaUno = 'aaaaaaaa-0000-4000-8000-000000000001'
  const analistaDos = 'aaaaaaaa-0000-4000-8000-000000000002'
  const analistaAjeno = 'aaaaaaaa-0000-4000-8000-000000000003'
  const equipoVisible = [
    { perfil_id: analistaUno, nombre_completo: 'Analista Norte Uno', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
    { perfil_id: analistaDos, nombre_completo: 'Analista Norte Dos', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
    ...(rolCrm === 'gerencia' ? [{ perfil_id: analistaAjeno, nombre_completo: 'Analista Sur', rol_crm: 'vendedor', supervisor_id: null, activo: true }] : []),
  ]
  const cartera = Array.from({ length: 14 }, (_, i) => leadReal({
    id: `cccccccc-0000-4000-8000-${String(i + 1).padStart(12, '0')}`,
    nombre_completo: `OPORTUNIDAD ${i < 12 ? 'NORTE' : 'SUR'} ${String(i + 1).padStart(2, '0')}`,
    vendedor_id: i < 6 ? analistaUno : i < 12 ? analistaDos : analistaAjeno,
    etapa: i % 4 < 2 ? 'contactado' : 'propuesta_enviada',
  }))
  // La respuesta simula el ámbito de la RPC, no autorización en el navegador.
  // El banco SQL prueba RLS: aquí comprobamos que la UI conserva sus filas y
  // envía filtros al servidor sin sustituirlos por una búsqueda del store.
  const visibles = rolCrm === 'gerencia' ? cartera : cartera.slice(0, 12)
  await montarBackendReal(page, { rolCrm, leads: visibles })
  await page.route('**/rest/v1/rpc/equipo_visible_fn', (route) => route.fulfill({ json: [
    { perfil_id: UID, nombre_completo: 'Responsable del equipo', rol_crm: rolCrm, supervisor_id: null, activo: true },
    ...equipoVisible,
  ] }))
  const calculado = '2026-09-07T12:00:00.000Z'
  const filas = visibles.map((lead, i) => {
    const original = muestraSql.cola.items[0]!
    const revision = i % 2 === 0
    return {
      ...original, lead_id: lead.id,
      bucket: i % 3 === 0 ? 'primera_atencion' : i % 3 === 1 ? 'tarea_vencida' : 'seguimiento',
      severidad: i % 3 === 0 ? 'critica' : 'media', prioridad: 10 + i,
      referencia_en: calculado,
      lead: { id: lead.id, nombre_completo: lead.nombre_completo, etapa: lead.etapa,
        analista_id: lead.vendedor_id, analista_nombre: equipoVisible.find((miembro) => miembro.perfil_id === lead.vendedor_id)!.nombre_completo },
      senales: { primera_atencion: i % 3 === 0, tareas_vencidas: i % 3 === 1,
        seguimientos_pendientes: i % 3 === 2, revisiones: revision, datos_incompletos: false, por_repartir: false },
      estado: { ...original.estado, lead_id: lead.id,
        compromiso: i % 5 === 4 ? original.estado.compromiso : { tarea: null, validez: 'sin_tarea', hasta_en: null, cobertura_activa: false },
        etapa: { ...original.estado.etapa,
        revision_requerida: revision, motivos_revision: revision ? ['limite_operativo_agotado'] : [] } },
    }
  })
  // Caso histórico como el que motivó aclarar los textos: seguimiento, etapa
  // y Agenda tienen fechas distintas. La UI debe explicar cada una por separado.
  const ejemplo = filas[0]!.estado
  ejemplo.seguimiento = { ...ejemplo.seguimiento, limite_en: '2026-09-07T04:03:00Z', vencido: true, accion_pendiente: true }
  ejemplo.compromiso = {
    tarea: { id: 'eeeeeeee-0000-4000-8000-000000000001', tipo: 'llamada', vence_en: '2026-08-31T15:00:00Z', reprogramaciones: 0 },
    validez: 'valido', cobertura_activa: false, hasta_en: '2026-08-31T19:00:00Z',
  }
  ejemplo.etapa = { ...ejemplo.etapa,
    limite_original_en: '2026-09-01T15:00:00Z', limite_prorrogado_en: '2026-09-01T15:00:00Z',
    limite_operativo_en: '2026-09-01T15:00:00Z', techo_en: '2026-09-02T16:21:00Z',
    prorrogas_usadas: 0,
  }
  await page.route('**/rest/v1/rpc/estado_sla_leads_v2_fn', async (route) => {
    const args = route.request().postDataJSON() as { p_lead_ids: string[] }
    await route.fulfill({ json: { ...muestraSql.estado, calculado_en: calculado,
      filas: args.p_lead_ids.map((id) => filas.find((fila) => fila.lead_id === id)?.estado ?? { ...muestraSql.estado.filas[0], lead_id: id }) } })
  })
  const pedidos: PedidoCola[] = []
  await page.route('**/rest/v1/rpc/cola_accion_v2_fn', async (route) => {
    const args = route.request().postDataJSON() as PedidoCola
    pedidos.push(args)
    const ambito = filas.filter((fila) => (!args.p_etapa || fila.lead.etapa === args.p_etapa)
      && (!args.p_analista_id || fila.lead.analista_id === args.p_analista_id))
    const filtradas = args.p_senal === 'todas' ? ambito : ambito.filter((fila) => fila.senales[args.p_senal as keyof typeof fila.senales])
    const inicio = args.p_cursor?.inicio ?? 0
    const items = filtradas.slice(inicio, inicio + args.p_limite)
    const hayMas = inicio + items.length < filtradas.length
    const totales = Object.fromEntries(Object.keys(filas[0]!.senales).map((senal) => [senal,
      ambito.filter((fila) => fila.senales[senal as keyof typeof fila.senales]).length]))
    await route.fulfill({ json: { ...muestraSql.cola, calculado_en: calculado, limite: args.p_limite,
      filtros: { senal: args.p_senal, etapa: args.p_etapa, analista_id: args.p_analista_id },
      total_items: filtradas.length, rango: { desde: items.length ? inicio + 1 : 0, hasta: inicio + items.length },
      hay_mas: hayMas, cursor_siguiente: hayMas ? { inicio: inicio + items.length } : null,
      totales, items,
    } })
  })
  return { pedidos, analistaUno, analistaDos, analistaAjeno }
}

async function colaConLeadFueraDelLote(page: Page) {
  const lead = leadReal({ id: 'ffffffff-0000-4000-8000-000000002501', vendedor_id: UID,
    nombre_completo: 'OPORTUNIDAD FUERA DEL LOTE', telefono: '+51982224466', monto_estimado: 2000, etapa: 'propuesta_enviada' })
  await montarBackendReal(page, { leads: [], rolCrm: 'gerencia' })
  await page.route('**/rest/v1/rpc/estado_sla_leads_v2_fn', async (route) => {
    const args = route.request().postDataJSON() as { p_lead_ids: string[] }
    await route.fulfill({ json: { ...muestraSql.estado, filas: args.p_lead_ids.map((lead_id) => ({ ...muestraSql.estado.filas[0], lead_id })) } })
  })
  await page.route('**/rest/v1/rpc/cola_accion_v2_fn', async (route) => {
    const args = route.request().postDataJSON() as { p_limite: number; p_senal: string; p_etapa: string | null; p_analista_id: string | null }
    const original = muestraSql.cola.items[0]!
    await route.fulfill({ json: { ...muestraSql.cola, limite: args.p_limite,
      filtros: { senal: args.p_senal, etapa: args.p_etapa, analista_id: args.p_analista_id },
      total_items: 1, rango: { desde: 1, hasta: 1 }, hay_mas: false, cursor_siguiente: null,
      items: [{ ...original, lead_id: lead.id,
        lead: { id: lead.id, nombre_completo: lead.nombre_completo, etapa: lead.etapa, analista_id: UID, analista_nombre: 'Analista de prueba' },
        estado: { ...original.estado, lead_id: lead.id } }],
    } })
  })
  return lead
}

test('la cola abre una ficha completa fuera del lote inicial después de confirmar su lectura RLS', async ({ page }) => {
  const lead = await colaConLeadFueraDelLote(page)
  let responder!: () => void
  const espera = new Promise<void>((resolve) => { responder = resolve })
  let consultasId = 0
  await page.route('**/rest/v1/leads?*', async (route) => {
    const url = new URL(route.request().url())
    if (url.searchParams.get('id') !== `eq.${lead.id}`) return route.fallback()
    consultasId += 1
    expect(url.searchParams.get('activo')).toBe('eq.true')
    expect(url.searchParams.get('select')).toContain('telefono,')
    await espera
    await route.fulfill({ json: [lead] })
  })
  await loginReal(page)
  await irASeguimiento(page)
  const lista = page.getByRole('list', { name: 'Oportunidades de esta página' })
  await lista.getByRole('button', { name: /OPORTUNIDAD FUERA DEL LOTE/ }).click()
  await expect.poll(() => consultasId).toBe(1)
  await expect(page.getByRole('dialog', { name: /OPORTUNIDAD FUERA DEL LOTE/ })).toHaveCount(0)
  responder()
  const ficha = page.getByRole('dialog', { name: /OPORTUNIDAD FUERA DEL LOTE/ })
  await expect(ficha).toBeVisible()
  await expect(ficha.getByRole('region', { name: 'Datos del lead' }).getByText('+51982224466', { exact: true })).toBeVisible()
  await expect(ficha.getByRole('link', { name: 'WhatsApp a OPORTUNIDAD FUERA DEL LOTE' })).toHaveAttribute('href', 'https://wa.me/51982224466')
  await expect(page).toHaveURL(new RegExp(`/lead/${lead.id}$`))
  expect(consultasId).toBe(1)
})

test('si RLS ya no devuelve la oportunidad, la cola informa el fallo y no abre una ficha parcial', async ({ page }) => {
  const lead = await colaConLeadFueraDelLote(page)
  await page.route('**/rest/v1/leads?*', async (route) => {
    if (new URL(route.request().url()).searchParams.get('id') !== `eq.${lead.id}`) return route.fallback()
    await route.fulfill({ json: [] })
  })
  await loginReal(page)
  await irASeguimiento(page)
  await page.getByRole('list', { name: 'Oportunidades de esta página' }).getByRole('button', { name: /OPORTUNIDAD FUERA DEL LOTE/ }).click()
  await expect(page.getByText('La oportunidad ya no está disponible en tu cartera.', { exact: true })).toBeVisible()
  await expect(page.getByRole('dialog', { name: /OPORTUNIDAD FUERA DEL LOTE/ })).toHaveCount(0)
  await expect(page).not.toHaveURL(new RegExp(`/lead/${lead.id}$`))
})

test('Analista: Seguimiento se abre desde su módulo, pagina sin acumular filas y abre la ficha', async ({ page }) => {
  const leads = Array.from({ length: 12 }, (_, i) => leadReal({
    id: `bbbbbbbb-0000-4000-8000-${String(i).padStart(12, '0')}`, vendedor_id: UID,
    nombre_completo: `OPORTUNIDAD SLA ${String(i + 1).padStart(2, '0')}`, etapa: 'contactado',
  }))
  await montarBackendReal(page, { leads, rolCrm: 'vendedor' })
  const calculado = new Date().toISOString()
  function estado(id: string): EstadoSlaV2 {
    return { lead_id: id, evaluacion: 'completa', motivos_datos: [],
      seguimiento: { referencia_en: calculado, ultima_gestion_en: calculado, limite_en: calculado, vencido: true, accion_pendiente: true },
      compromiso: { tarea: null, validez: 'sin_tarea', hasta_en: null, cobertura_activa: false },
      etapa: { limite_original_en: calculado, limite_prorrogado_en: calculado, limite_operativo_en: calculado, techo_en: calculado,
        prorrogas_usadas: 0, prorrogas_restantes: 2, revision_requerida: true, motivos_revision: ['limite_operativo_agotado'] } }
  }
  const pedidos: { p_cursor: unknown; p_senal: string; p_etapa: string | null }[] = []
  await page.route('**/rest/v1/rpc/estado_sla_leads_v2_fn', async (route) => {
    const args = route.request().postDataJSON() as { p_lead_ids: string[] }
    await route.fulfill({ json: { version: 2, modo: 'activo', control_revision: 1, calculado_en: calculado, filas: args.p_lead_ids.map(estado) } })
  })
  await page.route('**/rest/v1/rpc/cola_accion_v2_fn', async (route) => {
    const args = route.request().postDataJSON() as typeof pedidos[number] & { p_limite: number; p_analista_id: string | null }
    pedidos.push(args)
    const inicio = args.p_cursor ? 10 : 0
    const subset = leads.slice(inicio, inicio + args.p_limite)
    await route.fulfill({ json: {
      version: 2, modo: 'activo', control_revision: 1, calculado_en: calculado,
      filtros: { senal: args.p_senal, etapa: args.p_etapa, analista_id: args.p_analista_id },
      limite: args.p_limite, total_items: 12, rango: { desde: inicio + 1, hasta: inicio + subset.length },
      hay_mas: inicio === 0, cursor_siguiente: inicio === 0 ? { opaque: 'siguiente' } : null,
      totales: { primera_atencion: 12, tareas_vencidas: 0, seguimientos_pendientes: 12, revisiones: 12, datos_incompletos: 0, por_repartir: 0 },
      items: subset.map((lead) => ({ lead_id: lead.id, bucket: 'primera_atencion', severidad: 'critica', prioridad: 10,
        referencia_en: calculado, tarea_id: null,
        lead: { id: lead.id, nombre_completo: lead.nombre_completo, etapa: lead.etapa, analista_id: UID, analista_nombre: 'Analista de prueba' },
        senales: { primera_atencion: true, tareas_vencidas: false, seguimientos_pendientes: true, revisiones: true, datos_incompletos: false, por_repartir: false }, estado: estado(lead.id) })),
    } })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Hoy', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Tu agenda de hoy', exact: true })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Seguimiento comercial', exact: true })).toHaveCount(0)
  expect(pedidos).toHaveLength(0)
  await page.screenshot({ path: '/private/tmp/hoy-analista-sin-seguimiento-desktop.png', fullPage: true })
  await irASeguimiento(page)
  const lista = page.getByRole('list', { name: 'Oportunidades de esta página' })
  await expect(lista.locator(':scope > li')).toHaveCount(10)
  await expect(page.getByRole('combobox', { name: 'Analista', exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: /Por repartir/ })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Anterior', exact: true })).toBeDisabled()
  await page.screenshot({ path: '/private/tmp/sla-ui-desktop.png', fullPage: true })
  await page.getByRole('button', { name: 'Siguiente', exact: true }).click()
  await expect(lista.locator(':scope > li')).toHaveCount(2)
  await expect(lista.getByText('OPORTUNIDAD SLA 01', { exact: true })).toHaveCount(0)
  await expect(lista.getByText('OPORTUNIDAD SLA 11', { exact: true })).toBeVisible()
  const revision = page.getByRole('group', { name: 'Prioridades de seguimiento' }).getByRole('button', { name: /Revisión comercial/ })
  await revision.click()
  await expect(revision).toHaveAttribute('aria-pressed', 'true')
  await expect(lista.locator(':scope > li')).toHaveCount(10)
  await expect.poll(() => pedidos.at(-1)?.p_senal).toBe('revisiones')
  expect(pedidos.at(-1)?.p_cursor).toBeNull()
  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByRole('heading', { name: 'Seguimiento comercial' }).scrollIntoViewIfNeeded()
  await expect(page.getByRole('combobox', { name: 'Mostrar', exact: true })).toHaveValue('revisiones')
  await page.screenshot({ path: '/private/tmp/sla-ui-mobile.png', fullPage: true })
  const ancho = await page.evaluate(() => ({ total: document.documentElement.scrollWidth, visible: window.innerWidth }))
  expect(ancho.total).toBeLessThanOrEqual(ancho.visible)
  await lista.getByRole('button').first().click()
  const ficha = page.getByRole('dialog', { name: 'OPORTUNIDAD SLA 01' })
  await expect(ficha.getByRole('region', { name: 'Seguimiento y plazos' })).toBeVisible()
  await expect(ficha.getByText('Este caso necesita una decisión')).toBeVisible()
})


for (const rol of ['gerencia', 'supervisor'] as const) {
  test(`${rol}: Seguimiento tiene módulo propio, filtra el ámbito servido y conserva la navegación paginada`, async ({ page }) => {
    await page.setViewportSize({ width: 1192, height: 784 })
    const { pedidos, analistaUno, analistaAjeno } = await montarColaEquipo(page, rol)
    const errores: string[] = []
    page.on('pageerror', (error) => errores.push(error.message))
    await loginReal(page)
    if (rol === 'gerencia') {
      await expect(page.getByRole('heading', { name: 'Resumen', exact: true })).toBeVisible()
    } else {
      await expect(page.getByRole('link', { name: 'Abrir seguimiento', exact: true })).toBeVisible()
    }
    await expect(page.getByRole('list', { name: 'Oportunidades de esta página' })).toHaveCount(0)
    expect(pedidos).toHaveLength(0)
    await expect(page.getByRole('button', { name: 'Seguimiento', exact: true })).toBeVisible()
    if (rol === 'supervisor') {
      await page.getByRole('link', { name: 'Abrir seguimiento', exact: true }).click()
      await expect(page).toHaveURL(/#\/seguimiento$/)
    } else await irASeguimiento(page)
    const lista = page.getByRole('list', { name: 'Oportunidades de esta página' })
    const prioridades = page.getByRole('group', { name: 'Prioridades de seguimiento' })
    await expect(lista.locator(':scope > li')).toHaveCount(10)
    await expect(page.getByRole('button', { name: 'Todas las acciones', exact: true })).toHaveAttribute('aria-pressed', 'true')
    const analistas = page.getByRole('combobox', { name: 'Analista', exact: true })
    await expect(analistas.locator(`option[value="${UID}"]`)).toHaveCount(0)
    await expect(analistas.locator(`option[value="${analistaAjeno}"]`)).toHaveCount(rol === 'gerencia' ? 1 : 0)
    await expect(page.getByRole('combobox', { name: 'Mostrar', exact: true })).toBeHidden()
    await page.screenshot({ path: `/private/tmp/sla-seguimiento-${rol}-desktop.png`, animations: 'disabled' })
    await page.getByRole('button', { name: 'Siguiente', exact: true }).click()
    await expect(lista.locator(':scope > li')).toHaveCount(rol === 'gerencia' ? 4 : 2)
    await expect(lista.getByText('OPORTUNIDAD NORTE 01', { exact: true })).toHaveCount(0)
    await expect(lista.getByText('OPORTUNIDAD SUR 13', { exact: true })).toHaveCount(rol === 'gerencia' ? 1 : 0)
    const revision = prioridades.getByRole('button', { name: /Revisión comercial/ })
    await revision.click()
    await expect(revision).toHaveAttribute('aria-pressed', 'true')
    await expect.poll(() => pedidos.at(-1)?.p_senal).toBe('revisiones')
    expect(pedidos.at(-1)?.p_cursor).toBeNull()
    await expect(lista.locator(':scope > li')).toHaveCount(rol === 'gerencia' ? 7 : 6)
    // Revisión se solapa con el bucket dominante: no queda limitada a filas
    // cuyo título principal sea «Revisión comercial».
    await expect(lista.getByText('OPORTUNIDAD NORTE 01', { exact: true })).toBeVisible()
    await page.getByRole('combobox', { name: 'Etapa', exact: true }).selectOption('contactado')
    await analistas.selectOption(analistaUno)
    await expect.poll(() => pedidos.at(-1)?.p_analista_id).toBe(analistaUno)
    expect(pedidos.at(-1)).toMatchObject({ p_senal: 'revisiones', p_etapa: 'contactado', p_cursor: null })
    await expect(lista.locator(':scope > li')).toHaveCount(2)
    await expect(lista.getByText('OPORTUNIDAD NORTE 05', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Siguiente', exact: true })).toBeDisabled()
    await page.getByRole('button', { name: 'Todas las acciones', exact: true }).click()
    await page.getByRole('combobox', { name: 'Etapa', exact: true }).selectOption('')
    await analistas.selectOption('')
    await page.getByRole('combobox', { name: 'Por página', exact: true }).selectOption('25')
    await expect(lista.locator(':scope > li')).toHaveCount(rol === 'gerencia' ? 14 : 12)
    expect(pedidos.at(-1)).toMatchObject({ p_senal: 'todas', p_etapa: null, p_analista_id: null, p_limite: 25, p_cursor: null })
    await page.getByRole('combobox', { name: 'Por página', exact: true }).selectOption('10')
    await expect(lista.locator(':scope > li')).toHaveCount(10)
    await page.setViewportSize({ width: 390, height: 844 })
    await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
    await page.getByRole('heading', { name: 'Seguimiento comercial', exact: true }).scrollIntoViewIfNeeded()
    const mostrar = page.getByRole('combobox', { name: 'Mostrar', exact: true })
    await expect(mostrar).toBeVisible()
    const titulo = page.getByRole('heading', { name: 'Seguimiento', exact: true, level: 1 })
    await expect(titulo).toBeVisible()
    const anchoTitulo = await titulo.evaluate((elemento) => ({ contenido: elemento.scrollWidth, disponible: elemento.clientWidth }))
    expect(anchoTitulo.contenido).toBeLessThanOrEqual(anchoTitulo.disponible)
    await page.screenshot({ path: `/private/tmp/sla-seguimiento-${rol}-mobile.png`, animations: 'disabled' })
    const ancho = await page.evaluate(() => ({ total: document.documentElement.scrollWidth, visible: window.innerWidth }))
    expect(ancho.total).toBeLessThanOrEqual(ancho.visible)
    await mostrar.selectOption('tareas_vencidas')
    await expect.poll(() => pedidos.at(-1)?.p_senal).toBe('tareas_vencidas')
    await expect(lista.locator(':scope > li')).toHaveCount(rol === 'gerencia' ? 5 : 4)
    // Volver a una combinación ya consultada puede usar la caché vigente.
    await mostrar.selectOption('revisiones')
    await expect(mostrar).toHaveValue('revisiones')
    await expect(lista.locator(':scope > li')).toHaveCount(rol === 'gerencia' ? 7 : 6)
    await lista.getByRole('button').first().click()
    const ficha = page.getByRole('dialog', { name: 'OPORTUNIDAD NORTE 01', exact: true })
    await expect(ficha).toBeVisible()
    const plazos = ficha.getByRole('region', { name: 'Seguimiento y plazos' })
    await expect(plazos).toBeVisible()
    await plazos.screenshot({ path: `/private/tmp/sla-plazos-${rol}-mobile.png`, animations: 'disabled' })
    await page.setViewportSize({ width: 1192, height: 784 })
    await plazos.screenshot({ path: `/private/tmp/sla-plazos-${rol}-desktop.png`, animations: 'disabled' })
    expect(errores).toEqual([])
  })
}

test('el contacto y su siguiente tarea se confirman juntos antes de cerrar el diálogo', async ({ page }) => {
  const backend = await montarBackendReal(page, { leads: [leadReal({ vendedor_id: UID })] })
  let confirmar!: () => void
  const confirmacion = new Promise<void>((resolve) => { confirmar = resolve })
  await page.route('**/rest/v1/rpc/registrar_actividad_v2', async (route) => {
    await confirmacion
    await route.fallback()
  })
  await loginReal(page)
  await irAPipeline(page)
  const ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await ficha.getByRole('button', { name: /Copiar el número .* y registrar la llamada/ }).click()
  const dialogo = page.getByRole('dialog', { name: /Lograste comunicarte/ })
  await expect(dialogo.getByRole('checkbox', { name: /Agendar el siguiente paso/ })).toBeChecked()
  await dialogo.getByRole('button', { name: 'No contestó', exact: true }).click()
  await expect(dialogo.getByRole('button', { name: 'No contestó', exact: true })).toBeDisabled()
  await expect(page.getByText(/Contacto registrado/)).toHaveCount(0)
  expect(backend.tareas).toHaveLength(0)
  confirmar()
  await expect(dialogo).toHaveCount(0)
  await expect(page.getByText(/Contacto registrado.*siguiente/)).toBeVisible()
  expect(backend.llamadas.rpcSlaComandos).toEqual(['registrar_actividad'])
  expect(backend.llamadas.insertActividad).toBe(0)
  expect(backend.tareas).toHaveLength(1)
  await expect(ficha.getByText(String(backend.tareas[0]?.titulo), { exact: true })).toBeVisible()
})

test('el reintento tras perder la respuesta conserva la siguiente tarea aunque el resync ya la muestre', async ({ page }) => {
  const backend = await montarBackendReal(page, {
    leads: [leadReal({ vendedor_id: UID })], perderProximaRespuestaSla: true,
  })
  const enviados: unknown[] = []
  await page.route('**/rest/v1/rpc/registrar_actividad_v2', async (route) => {
    enviados.push(route.request().postDataJSON())
    await route.fallback()
  })
  await loginReal(page)
  await irAPipeline(page)
  const ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await ficha.getByRole('button', { name: /Copiar el número .* y registrar la llamada/ }).click()
  const dialogo = page.getByRole('dialog', { name: /Lograste comunicarte/ })
  await dialogo.getByRole('textbox', { name: 'Nota del contacto' }).fill('Intento documentado para reintentar')
  await dialogo.getByRole('button', { name: 'No contestó', exact: true }).click()
  await expect(dialogo.getByRole('button', { name: 'Reintentar guardado' })).toBeVisible()
  await expect.poll(() => backend.tareas.length).toBe(1)
  // El store terminó el resync y ahora sabe que el plan ya existe. Eso no
  // debe convertir el reintento original en una actividad sin siguiente.
  await expect(page.getByText(/Confirmación pendiente.*se actualizó la vista/)).toBeVisible()
  await expect(dialogo.getByRole('textbox', { name: 'Nota del contacto' })).toHaveValue('Intento documentado para reintentar')
  await expect(dialogo.getByRole('button', { name: 'No contestó', exact: true })).toBeDisabled()
  await expect(page.getByText(/Contacto registrado/)).toHaveCount(0)
  await dialogo.getByRole('button', { name: 'Reintentar guardado' }).click()
  await expect(dialogo).toHaveCount(0)
  await expect(page.getByText(/Contacto registrado.*siguiente/)).toBeVisible()
  expect(enviados).toHaveLength(2)
  expect(enviados[1]).toEqual(enviados[0])
  expect(backend.tareas).toHaveLength(1)
  expect(backend.llamadas.insertActividad).toBe(0)
})

test('tras recargar verifica explícitamente el guardado original sin reconstruir el formulario', async ({ page }) => {
  const backend = await montarBackendReal(page, { leads: [leadReal({ vendedor_id: UID })], perderProximaRespuestaSla: true })
  const enviados: unknown[] = []
  await page.route('**/rest/v1/rpc/registrar_actividad_v2', async (route) => {
    enviados.push(route.request().postDataJSON()); await route.fallback()
  })
  await page.route('**/rest/v1/rpc/estado_sla_leads_v2_fn', async (route) => {
    const args = route.request().postDataJSON() as { p_lead_ids: string[] }
    await route.fulfill({ json: { ...muestraSql.estado, filas: args.p_lead_ids.map((lead_id) => ({ ...muestraSql.estado.filas[0], lead_id })) } })
  })
  await loginReal(page)
  await irAPipeline(page)
  let ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await ficha.getByRole('button', { name: /Copiar el número .* y registrar la llamada/ }).click()
  const dialogo = page.getByRole('dialog', { name: /Lograste comunicarte/ })
  await dialogo.getByRole('textbox', { name: 'Nota del contacto' }).fill('Conservar después de recargar')
  await dialogo.getByRole('button', { name: 'No contestó', exact: true }).click()
  await expect(dialogo.getByRole('button', { name: 'Reintentar guardado' })).toBeVisible()
  await expect.poll(() => backend.tareas.length).toBe(1)
  await page.reload()
  await expect(page.locator('.ac-splash')).toBeHidden()
  ficha = page.getByRole('dialog', { name: /CLIENTE REAL UNO/ })
  await expect(ficha).toBeVisible()
  const pendientes = ficha.getByRole('region', { name: 'Guardados por confirmar' })
  await expect(pendientes.getByRole('button', { name: 'Verificar guardado' })).toBeVisible()
  await pendientes.scrollIntoViewIfNeeded()
  await pendientes.getByRole('button', { name: 'Verificar guardado' }).hover()
  await page.screenshot({ path: '/private/tmp/sla-ui-recuperacion.png', animations: 'disabled' })
  expect(enviados).toHaveLength(1)
  await pendientes.getByRole('button', { name: 'Verificar guardado' }).click()
  await expect(pendientes.getByRole('status')).toHaveText('Guardado confirmado y vista actualizada.')
  expect(enviados).toHaveLength(2)
  expect(enviados[1]).toEqual(enviados[0])
  expect(backend.tareas).toHaveLength(1)
})

test('Gerencia publica las reglas aprobadas y activa solo después de la confirmación', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia' })
  const politica = muestraSql.configuracion.vigente
  let publicada = false
  let activo = false
  let liberar!: () => void
  const permisoRespuesta = new Promise<void>((resolve) => { liberar = resolve })
  const publicaciones: unknown[] = []
  const activaciones: unknown[] = []
  const control = () => ({ modo: activo ? 'activo' : 'legado', revision: activo ? 1 : 0, primera_activacion_en: activo ? new Date().toISOString() : null, politica_adopcion_id: activo ? politica.base.id : null })
  await page.route('**/rest/v1/rpc/configuracion_sla_fn', async (route) => {
    await route.fulfill({ json: { version: 1, puede_editar: true, expected_version: publicada ? 2 : 1,
      politica: { ...politica.base, version: publicada ? 2 : 1 } } })
  })
  await page.route('**/rest/v1/rpc/metricas_sla_fn', async (route) => {
    const args = route.request().postDataJSON() as { p_desde: string; p_hasta: string }
    await route.fulfill({ json: { version: 1, generado_en: new Date().toISOString(),
      periodo: { desde: args.p_desde, hasta: args.p_hasta, zona: 'America/Lima' },
      ciclos: { primera_gestion: [], primer_contacto: [] }, asignaciones: { primera_gestion: [], primer_contacto: [] }, etapas: [] } })
  })
  await page.route('**/rest/v1/rpc/configuracion_sla_v2_fn', async (route) => {
    const actual = publicada ? politica : { base: { ...politica.base, version: 1 }, operacion: null }
    await route.fulfill({ json: { version: 2, puede_editar: true, expected_version: publicada ? 2 : 1,
      vigente: actual, ultima_publicada: actual, control: control(),
      inicializacion_aprobada: { disponible: !publicada, motivo: publicada ? 'ya_publicadas' : null,
        config: { ...politica.base, etapas: politica.base.etapas.map((etapa) => ({ ...etapa, ...politica.operacion.find((regla) => regla.etapa === etapa.etapa) })) } },
    } })
  })
  await page.route('**/rest/v1/rpc/publicar_reglas_sla_aprobadas_v2', async (route) => {
    publicaciones.push(route.request().postDataJSON())
    await permisoRespuesta
    publicada = true
    await route.fulfill({ json: { version: 2, politica, expected_version: 2 } })
  })
  await page.route('**/rest/v1/rpc/cambiar_modo_sla_operacion', async (route) => {
    activaciones.push(route.request().postDataJSON())
    activo = true
    await route.fulfill({ json: { version: 2, ...control() } })
  })
  await loginReal(page)
  await page.goto('/#/config-sla')
  const encabezado = page.getByRole('heading', { name: 'Seguimiento y compromisos' })
  const panelConfiguracion = encabezado.locator('xpath=ancestor::div[@data-slot="card"]')
  await expect(encabezado).toBeVisible()
  await expect(page.getByRole('button', { name: 'Activar seguimiento operativo' })).toBeDisabled()
  await panelConfiguracion.screenshot({ path: '/private/tmp/sla-ui-config-aprobadas.png', animations: 'disabled' })
  await page.getByRole('button', { name: 'Publicar reglas aprobadas' }).click()
  await expect(page.getByRole('button', { name: 'Publicando…' })).toBeDisabled()
  expect(publicaciones).toEqual([{ p_expected_version: 1 }])
  expect(activaciones).toHaveLength(0)
  liberar()
  await expect(page.getByText('Reglas aprobadas publicadas en la política v2. Ya puedes activar el seguimiento operativo.')).toBeVisible()
  await page.getByRole('button', { name: 'Activar seguimiento operativo' }).click()
  await expect(page.getByText('Seguimiento operativo activado.', { exact: true })).toBeVisible()
  expect(activaciones).toEqual([{ p_expected_revision: 0, p_modo: 'activo' }])
  await expect(page.getByRole('button', { name: 'Desactivar seguimiento operativo' })).toBeEnabled()
  await panelConfiguracion.screenshot({ path: '/private/tmp/sla-ui-config-activa.png', animations: 'disabled' })
})
