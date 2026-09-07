import { expect, test } from '@playwright/test'
import { abrirLead, irAPipeline, leadReal, loginReal, montarBackendReal, UID } from './_helpers'
import type { EstadoSlaV2 } from '../src/lib/sla-operacion'
import muestraSql from '../src/data/sla-operacion-sql.fixture.json' with { type: 'json' }

test('SLA activo: pagina sin acumular filas, filtra en servidor y abre la ficha', async ({ page }) => {
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
  const lista = page.getByRole('list', { name: 'Oportunidades de esta página' })
  await expect(lista.locator(':scope > li')).toHaveCount(10)
  await expect(page.getByRole('button', { name: 'Anterior', exact: true })).toBeDisabled()
  await page.screenshot({ path: '/private/tmp/sla-ui-desktop.png', fullPage: true })
  await page.getByRole('button', { name: 'Siguiente', exact: true }).click()
  await expect(lista.locator(':scope > li')).toHaveCount(2)
  await expect(lista.getByText('OPORTUNIDAD SLA 01', { exact: true })).toHaveCount(0)
  await expect(lista.getByText('OPORTUNIDAD SLA 11', { exact: true })).toBeVisible()
  await page.getByRole('combobox', { name: 'Mostrar', exact: true }).selectOption('revisiones')
  await expect(lista.locator(':scope > li')).toHaveCount(10)
  await expect.poll(() => pedidos.at(-1)?.p_senal).toBe('revisiones')
  expect(pedidos.at(-1)?.p_cursor).toBeNull()
  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByRole('heading', { name: 'Seguimiento comercial' }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: '/private/tmp/sla-ui-mobile.png', fullPage: true })
  const ancho = await page.evaluate(() => ({ total: document.documentElement.scrollWidth, visible: window.innerWidth }))
  expect(ancho.total).toBeLessThanOrEqual(ancho.visible)
  await lista.getByRole('button').first().click()
  const ficha = page.getByRole('dialog', { name: 'OPORTUNIDAD SLA 01' })
  await expect(ficha.getByRole('region', { name: 'Plazos de seguimiento' })).toBeVisible()
  await expect(ficha.getByText('Revisión comercial pendiente')).toBeVisible()
})


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
