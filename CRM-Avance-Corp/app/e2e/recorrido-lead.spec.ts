import { expect, test, type Page } from '@playwright/test'
import { irACartera, leadReal, loginReal, montarBackendReal, UID } from './_helpers'
import { recorridoFixture, recorridoId, recorridosFixture } from '../src/test/fixtures/recorrido'
import type { RecorridoLead } from '../src/lib/recorrido-lead'

async function abrir(page: Page) {
  await loginReal(page)
  await irACartera(page)
  await page.getByRole('row', { name: /CLIENTE REAL UNO/ }).click()
  const ficha = page.getByRole('dialog', { name: 'CLIENTE REAL UNO' })
  await expect(ficha).toBeVisible()
  return ficha
}

test('la guía comprueba hechos, conserva la ficha ante error y permite recuperar la lectura', async ({ page }) => {
  const lead = leadReal({ vendedor_id: UID, etapa: 'propuesta_enviada' })
  await montarBackendReal(page, { leads: [lead] })
  let caido = true
  await page.route('**/rest/v1/rpc/recorrido_leads_fn', route => route.fulfill(caido
    ? { status: 503, json: { code: '08006', message: 'Lectura temporalmente no disponible' } }
    : { json: recorridosFixture([recorridoFixture(lead.id)]) }))
  const ficha = await abrir(page)
  const guia = ficha.getByRole('region', { name: 'Antes de convertir a cliente' })
  await expect(guia.getByRole('status')).toContainText('No se pudo comprobar')
  await expect(ficha.getByRole('button', { name: /Convertir a cliente/i })).toBeVisible()
  caido = false
  await guia.getByRole('button', { name: 'Volver a comprobar' }).click()
  await expect(guia.getByRole('listitem')).toHaveCount(2)
  await expect(guia.getByRole('listitem').filter({ hasText: 'Asistencia a la cita' })).toContainText('Pendiente')
  await expect(guia.getByRole('listitem').filter({ hasText: 'Entrevista comercial' })).toContainText('Pendiente')
  await expect(guia).toContainText('Cambiar de etapa no registra estos hechos')
})

test('oficina mantiene campos tras respuesta perdida, reintenta la misma operación y devuelve el foco', async ({ page }) => {
  const lead = leadReal({ vendedor_id: UID })
  await montarBackendReal(page, { leads: [lead] })
  let item = recorridoFixture(lead.id)
  const envios: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/recorrido_leads_fn', route => route.fulfill({ json: recorridosFixture([item]) }))
  await page.route('**/rest/v1/rpc/recorrido_atender_oficina_fn', async route => {
    const body = route.request().postDataJSON() as Record<string, unknown>
    envios.push(body)
    if (envios.length === 1) return route.abort('failed')
    item = recorridoFixture(lead.id, { estado: 'completo', habilita_conversion: true, pendiente: 'listo',
      pasos: { gestionado: true, contactado: true, cita_agendada: true, asistencia: true, entrevista: true },
      evidencias: { gestion_id: null, contacto_id: recorridoId(2), cita_id: recorridoId(3),
        asistencia_id: recorridoId(2), asistencia_tarea_id: recorridoId(3), entrevista_tarea_id: recorridoId(3) } })
    return route.fulfill({ json: { ok: true, version: 1, operacion_id: body.p_operacion_id,
      comando: 'recorrido_atender_oficina', lead_id: lead.id, origen: 'oficina', ciclo_n: 1,
      tarea_id: recorridoId(3), actividad_id: recorridoId(2), siguiente_id: null } })
  })
  const ficha = await abrir(page)
  const guia = ficha.getByRole('region', { name: 'Antes de convertir a cliente' })
  await guia.getByRole('button', { name: 'Llegó sin cita' }).click()
  const dialogo = page.getByRole('dialog', { name: 'Registrar visita y entrevista' })
  await expect(dialogo.getByRole('button', { name: 'Guardar entrevista' })).toBeDisabled()
  await dialogo.getByRole('button', { name: 'Asistió y realizamos la entrevista' }).click()
  await dialogo.getByLabel('Resultado comercial').selectOption('interesado')
  await dialogo.getByLabel('Nota del resultado (opcional)').fill('Entrevista en oficina sin cita previa')
  await dialogo.getByRole('button', { name: 'Saltar esta vez' }).click()
  await dialogo.getByRole('button', { name: 'Guardar entrevista' }).click()
  await expect(page.getByText('Confirmación pendiente. Reintenta el mismo guardado; no se duplicará.')).toBeVisible()
  await expect(dialogo.getByLabel('Nota del resultado (opcional)')).toHaveValue('Entrevista en oficina sin cita previa')
  await dialogo.getByRole('button', { name: 'Guardar entrevista' }).click()
  await expect(dialogo).toBeHidden()
  expect(envios).toHaveLength(2)
  expect(envios[1]).toEqual(envios[0])
  expect(envios[0].p_siguiente).toBeNull()
  await expect(guia.getByRole('status')).toHaveText('Asistencia y entrevista registradas')
  await expect(guia.getByRole('listitem').filter({ hasText: 'Registrada' })).toHaveCount(2)
  await expect(guia.getByRole('heading')).toBeFocused()
})

test('una cita futura ofrece ver la cita y no permite declarar asistencia anticipada desde la guía', async ({ page }) => {
  const lead = leadReal({ vendedor_id: UID })
  const fecha = new Date(Date.now() + 86400000).toISOString()
  await montarBackendReal(page, { leads: [lead] })
  const item = recorridoFixture(lead.id, { pendiente: 'esperar_cita', tarea_pendiente_id: recorridoId(3), cita_pendiente_en: fecha })
  await page.route('**/rest/v1/rpc/recorrido_leads_fn', route => route.fulfill({ json: recorridosFixture([item]) }))
  const guia = (await abrir(page)).getByRole('region', { name: 'Antes de convertir a cliente' })
  await expect(guia.getByRole('button', { name: 'Ver cita' })).toBeVisible()
  await expect(guia.getByRole('button', { name: 'Registrar resultado de la cita' })).toHaveCount(0)
  await expect(guia.getByRole('button', { name: 'Llegó sin cita' })).toHaveCount(0)
})

test('la cita pendiente se cierra con el formulario vigente y actualiza los hechos de la guía', async ({ page }) => {
  const lead = leadReal({ vendedor_id: UID })
  const tarea = { id: recorridoId(3), lead_id: lead.id, perfil_id: null, vendedor_id: UID, asignado_supervisor_id: null,
    tipo: 'reunion', titulo: 'Cita en oficina', nota: null, vence_en: new Date(Date.now() - 60000).toISOString(),
    duracion_min: 30, estado: 'pendiente', modalidad_reunion: 'presencial', ubicacion_reunion: 'Oficina',
    enlace_reunion: null, resultado_reunion: null, motivo_no_realizada: null, detalle_cierre_reunion: null,
    confirmada_en: null, reagendada_de: null, reprogramaciones: 0, activo: true, creado_en: new Date().toISOString() }
  const estado = await montarBackendReal(page, { leads: [lead], tareas: [tarea] })
  let item = recorridoFixture(lead.id, { pendiente: 'cerrar_entrevista', tarea_pendiente_id: tarea.id, cita_pendiente_en: tarea.vence_en })
  await page.route('**/rest/v1/rpc/recorrido_leads_fn', route => route.fulfill({ json: recorridosFixture([item]) }))
  await page.route('**/rest/v1/tareas?*', route => new URL(route.request().url()).searchParams.has('id')
    ? route.fulfill({ json: tarea }) : route.fallback())
  let cierre: Record<string, unknown> | null = null
  await page.route('**/rest/v1/rpc/cerrar_reunion_v3', route => {
    cierre = route.request().postDataJSON() as Record<string, unknown>
    estado.tareas = []
    item = recorridoFixture(lead.id, { estado: 'completo', habilita_conversion: true, pendiente: 'listo',
      pasos: { gestionado: true, contactado: false, cita_agendada: true, asistencia: true, entrevista: true },
      evidencias: { gestion_id: null, contacto_id: null, cita_id: tarea.id,
        asistencia_id: recorridoId(2), asistencia_tarea_id: tarea.id, entrevista_tarea_id: tarea.id } })
    return route.fulfill({ json: { ok: true, version: 2, operacion_id: cierre.p_operacion_id,
      comando: 'cerrar_reunion', lead_id: lead.id, tarea_id: tarea.id, actividad_id: recorridoId(2), siguiente_id: null } })
  })
  const guia = (await abrir(page)).getByRole('region', { name: 'Antes de convertir a cliente' })
  await guia.getByRole('button', { name: 'Registrar resultado de la cita' }).click()
  const dialogo = page.getByRole('dialog', { name: 'Cerrar tarea' })
  await dialogo.getByRole('button', { name: 'Se realizó', exact: true }).click()
  await dialogo.getByLabel('Resultado comercial').selectOption('interesado')
  await dialogo.getByRole('button', { name: 'Saltar esta vez' }).click()
  await dialogo.getByRole('button', { name: 'Cerrar tarea', exact: true }).click()
  await expect(dialogo).toBeHidden()
  expect(cierre).toMatchObject({ p_tarea_id: tarea.id, p_resultado_reunion: 'interesado', p_estado: 'completada', p_siguiente: null })
  await expect(guia.getByRole('status')).toHaveText('Asistencia y entrevista registradas')
  await expect(guia.getByRole('heading')).toBeFocused()
})

test('Directorio ve los hechos sin controles para declararlos', async ({ page }) => {
  const lead = leadReal({ vendedor_id: UID })
  await montarBackendReal(page, { leads: [lead], rolCrm: 'directorio', rolPortal: 'directorio' })
  await page.route('**/rest/v1/rpc/recorrido_leads_fn', route => route.fulfill({ json: recorridosFixture([recorridoFixture(lead.id)]) }))
  const guia = (await abrir(page)).getByRole('region', { name: 'Antes de convertir a cliente' })
  await expect(guia.getByRole('listitem')).toHaveCount(2)
  await expect(guia.getByRole('button', { name: 'Llegó sin cita' })).toHaveCount(0)
  await expect(guia.getByRole('button', { name: 'Agendar cita' })).toHaveCount(0)
})

test('la primera conversión explica el bloqueo y conserva documento y nombre para corregir los hechos', async ({ page }) => {
  const lead = leadReal({ vendedor_id: UID })
  await montarBackendReal(page, { leads: [lead] })
  const item: RecorridoLead = recorridoFixture(lead.id, { exigible: true })
  await page.route('**/rest/v1/rpc/recorrido_leads_fn', route => route.fulfill({ json: recorridosFixture([item],
    { modo: 'exigir', cohorte_desde: '2026-10-18T15:00:00Z' }) }))
  await page.route('**/rest/v1/rpc/preparar_persona_lead_inversion_fn', route => route.fulfill({ status: 400,
    json: { code: 'P0409', message: 'Antes de convertir, registra que asistió a su cita y que la entrevista se realizó, con su resultado.' } }))
  const ficha = await abrir(page)
  await ficha.getByRole('button', { name: /Convertir a cliente/i }).click()
  await page.getByLabel('Documento', { exact: true }).fill('95554444')
  await page.getByRole('button', { name: 'Continuar a Nueva inversión' }).click()
  await expect(page.getByText(/Antes de convertir, registra que asistió/)).toBeVisible()
  await expect(page.getByLabel('Documento', { exact: true })).toHaveValue('95554444')
  await expect(page.getByRole('button', { name: 'Continuar a Nueva inversión' })).toBeEnabled()
})
