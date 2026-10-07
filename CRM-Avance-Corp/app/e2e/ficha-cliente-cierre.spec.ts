// Ficha heredada por perfil: usa el mismo cierre atómico que Agenda.
// Transporte simulado y cerrado a producción; RLS se verifica en el banco SQL.
import { expect, test } from '@playwright/test'
import { clienteReal, irAMiCartera, loginReal, montarBackendReal, UID } from './_helpers'

for (const tipo of ['llamada', 'reunion'] as const) {
  test(`ficha de cliente: cierra ${tipo} con resultado e historial sin salir a Agenda`, async ({ page }) => {
    const cliente = clienteReal()
    const id = 'cf111111-1111-4111-8111-111111111111'
    const tarea = { id, lead_id: null, perfil_id: cliente.id, inversionista_id: null, vendedor_id: UID,
      asignado_supervisor_id: null, tipo, titulo: `Gestionar a CLIENTE PORTAL UNO: ${tipo}`, nota: null,
      vence_en: new Date().toISOString(), creado_en: new Date().toISOString(), creado_por: UID,
      estado: 'pendiente', activo: true, duracion_min: tipo === 'reunion' ? 30 : null,
      modalidad_reunion: tipo === 'reunion' ? 'virtual' : null, ubicacion_reunion: null, enlace_reunion: null,
      resultado_reunion: null, motivo_no_realizada: null, detalle_cierre_reunion: null,
      confirmada_en: null, reagendada_de: null, reprogramaciones: 0 }
    const backend = await montarBackendReal(page, { rolCrm: 'vendedor', clientes: [cliente], contratos: [], tareas: [tarea] })
    // El roster base de otros escenarios identifica UID como gerente. Aquí
    // sesión y responsable son realmente el mismo analista activo.
    await page.route('**/rest/v1/rpc/equipo_visible_fn', route => route.fulfill({ contentType: 'application/json',
      body: JSON.stringify([{ perfil_id: UID, nombre_completo: 'Analista de prueba', rol_crm: 'vendedor', supervisor_id: null, activo: true }]) }))
    const historial: Record<string, unknown>[] = []
    const envios: Record<string, unknown>[] = []
    let rechazar = tipo === 'llamada'
    await page.route('**/rest/v1/actividades_cliente?*', route => route.fulfill({ contentType: 'application/json', body: JSON.stringify(historial) }))
    await page.route('**/rest/v1/rpc/cerrar_tarea', async route => {
      const datos = route.request().postDataJSON() as Record<string, unknown>
      envios.push(datos)
      if (rechazar) {
        rechazar = false
        return route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: '22023', message: 'Rechazo de ensayo: vuelve a guardar' }) })
      }
      historial.push({ id: 'cf222222-2222-4222-8222-222222222222', cliente_id: cliente.id, vendedor_id: UID,
        tarea_id: id, tipo: datos.p_resultado_tipo, detalle: datos.p_resultado_detalle, creado_por: UID, creado_en: new Date().toISOString() })
      await route.fallback()
    })
    await loginReal(page)
    await irAMiCartera(page)
    await page.getByRole('row', { name: /CLIENTE PORTAL UNO/ }).getByRole('button', { name: 'Ver detalle' }).click()
    const ficha = page.getByRole('dialog', { name: 'CLIENTE PORTAL UNO' })
    await ficha.getByRole('button', { name: `Cerrar tarea — ${tarea.titulo}` }).click()
    const cierre = page.getByRole('dialog', { name: 'Cerrar tarea', exact: true })
    await cierre.getByRole('button', { name: tipo === 'llamada' ? 'Contestó' : 'Se realizó', exact: true }).click()
    if (tipo === 'reunion') await cierre.getByLabel('Resultado comercial', { exact: true }).selectOption('propuesta')
    await cierre.getByLabel('Nota del resultado (opcional)').fill('Gestión registrada desde la ficha del cliente')
    await cierre.getByRole('button', { name: 'Saltar esta vez' }).click()
    await cierre.getByRole('button', { name: 'Cerrar tarea', exact: true }).click()
    if (tipo === 'llamada') {
      // Un rechazo no desmonta el formulario ni pierde la nota del analista.
      await expect(page.getByText('Rechazo de ensayo: vuelve a guardar')).toBeVisible()
      await expect(cierre).toBeVisible()
      await expect(cierre.getByLabel('Nota del resultado (opcional)')).toHaveValue('Gestión registrada desde la ficha del cliente')
      await cierre.getByRole('button', { name: 'Cerrar tarea', exact: true }).click()
    }
    await expect(cierre).toHaveCount(0)
    await expect(ficha.getByRole('button', { name: `Cerrar tarea — ${tarea.titulo}` })).toHaveCount(0)
    await expect(ficha.getByText('Gestión registrada desde la ficha del cliente', { exact: true })).toBeVisible()
    expect(envios.at(-1)).toMatchObject({ p_tarea_id: id, p_estado: 'completada',
      p_resultado_tipo: tipo === 'llamada' ? 'llamada_realizada' : 'reunion_realizada',
      ...(tipo === 'reunion' ? { p_resultado_reunion: 'propuesta' } : {}) })
    expect(backend.tareas.some(t => t.id === id)).toBe(false)
    expect(historial).toHaveLength(1)
  })
}
