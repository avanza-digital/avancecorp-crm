// Gestión Diaria del analista con la cola del DÍA v3 (29/09/2026): las tareas
// de CLIENTES de la cartera entran en la misma cola que los leads, una fila por
// tarea. Sesión real con transporte interceptado: la cola hace eco de los
// argumentos y se recalcula desde las tareas del backend simulado, así que
// cerrar una tarea con `cerrar_tarea` la saca de verdad de la siguiente
// lectura. No acredita RLS (lo hace el gate del banco).
import { expect, test } from '@playwright/test'
import { leadReal, loginReal, montarBackendReal, UID } from './_helpers'
import { finDelDiaLima, montarColaDiaV3 } from './_sla-cola'

const LEAD = 'cccccccc-0000-4000-8000-00000000c0a1'
const PERFIL = 'dddddddd-0000-4000-8000-00000000c0b1'
const T_VENCIDA = 'eeeeeeee-0000-4000-8000-00000000c0c1'
const T_HOY = 'eeeeeeee-0000-4000-8000-00000000c0c2'
const T_MANANA = 'eeeeeeee-0000-4000-8000-00000000c0c3'

function tareaCliente(id: string, venceEn: number, titulo: string) {
  return { id, lead_id: null, perfil_id: PERFIL, inversionista_id: null, vendedor_id: UID, asignado_supervisor_id: null,
    tipo: 'tarea', titulo, nota: null, vence_en: new Date(venceEn).toISOString(), duracion_min: null, estado: 'pendiente',
    modalidad_reunion: null, ubicacion_reunion: null, enlace_reunion: null, resultado_reunion: null, motivo_no_realizada: null, detalle_cierre_reunion: null,
    confirmada_en: null, reagendada_de: null, reprogramaciones: 0, activo: true, creado_en: new Date(venceEn - 86_400_000).toISOString(),
    creado_por: UID, nombre_cliente: 'ROSA CLIENTE PORTAL' }
}

test('Analista: las tareas de clientes entran en su cola, se registran y «Ahora» pasa a la siguiente', async ({ page }, info) => {
  const ahora = Date.now()
  const fin = finDelDiaLima(ahora)
  const backend = await montarBackendReal(page, {
    rolCrm: 'vendedor',
    leads: [leadReal({ id: LEAD, nombre_completo: 'LEAD CON TAREA VENCIDA', vendedor_id: UID, etapa: 'contactado' })],
    tareas: [
      tareaCliente(T_VENCIDA, ahora - 2 * 3_600_000, 'Gestionar a ROSA: enviar estado de cuenta'),
      // Hoy aún futura: a mitad de camino entre ahora y la medianoche de Lima.
      tareaCliente(T_HOY, ahora + Math.floor((fin - ahora) / 2), 'Gestionar a ROSA: confirmar la renovación'),
      // Mañana: vive en la Agenda, no en la cola del día.
      tareaCliente(T_MANANA, fin + 10 * 3_600_000, 'Gestionar a ROSA: llamada de mañana'),
    ],
  })
  const { pedidosTrabajo } = await montarColaDiaV3(page, backend, [{ id: LEAD, nombre_completo: 'LEAD CON TAREA VENCIDA', etapa: 'contactado' }])
  await loginReal(page)
  await page.goto('/#/gestion-diaria')
  await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toBeVisible()

  // La pantalla lee la v3 con los filtros del día (sin cursor, sin etapa ni analista).
  await expect.poll(() => pedidosTrabajo.length).toBeGreaterThan(0)
  expect(pedidosTrabajo.at(-1)).toEqual({ p_limite: 8, p_filtro: 'todo', p_pagina: 0 })

  // Dos tareas de la MISMA persona = dos filas; la de mañana no entra.
  const todo = page.getByRole('list', { name: /^Todo/ })
  await expect(todo.getByRole('button', { name: /ROSA CLIENTE PORTAL/ })).toHaveCount(2)
  await expect(todo.getByRole('button', { name: /LEAD CON TAREA VENCIDA/ })).toHaveCount(1)
  await expect(todo.getByText(/Cliente de tu cartera · gestión agendada/)).toHaveCount(2)

  // Se elige la vencida del cliente: «Ahora» dice quién es y qué toca, sin inventar ficha ni teléfono.
  await todo.getByRole('button', { name: /ROSA CLIENTE PORTAL/ }).first().click()
  const tarjeta = page.getByRole('region', { name: 'Ahora' })
  await expect(tarjeta.getByRole('button', { name: 'ROSA CLIENTE PORTAL, sin ficha en tu cartera' })).toBeVisible()
  await expect(tarjeta.getByText('Cliente de tu cartera', { exact: true })).toBeVisible()
  await expect(tarjeta.getByText(/^Tarea · Gestionar a ROSA: enviar estado de cuenta$/)).toBeVisible()
  await expect(tarjeta.getByText(/^Se pasó hace /)).toBeVisible()
  await expect(tarjeta.getByText(/aún no tiene ficha en tu cartera/)).toBeVisible()
  await expect(tarjeta.getByRole('button', { name: /^Llamar/ })).toHaveCount(0)
  await expect(tarjeta.getByRole('link', { name: /Llamar/ })).toHaveCount(0)
  await page.screenshot({ path: info.outputPath('clientes-v3-ahora.png'), fullPage: true })

  // «Registrar resultado» abre el cierre de ESA tarea y, al cerrarla, «Ahora» pasa a la de hoy.
  await tarjeta.getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE PORTAL' }).click()
  const dialogo = page.getByRole('dialog', { name: 'Cerrar tarea' })
  await expect(dialogo.getByText('Gestionar a ROSA: enviar estado de cuenta')).toBeVisible()
  await dialogo.getByRole('button', { name: 'Cerrar tarea' }).click()
  await expect(dialogo).toHaveCount(0)
  await expect(todo.getByRole('button', { name: /ROSA CLIENTE PORTAL/ })).toHaveCount(1)
  await expect(tarjeta.getByText(/^Tarea · Gestionar a ROSA: confirmar la renovación$/)).toBeVisible()
  await expect(tarjeta.getByText(/^Quedan /)).toBeVisible()
  // El foco no se pierde al cambiar de persona: vuelve al nombre de la nueva.
  await expect(tarjeta.getByRole('button', { name: 'ROSA CLIENTE PORTAL, sin ficha en tu cartera' })).toBeFocused()
  expect(backend.tareas.some((t) => t.id === T_VENCIDA)).toBe(false)
  await page.screenshot({ path: info.outputPath('clientes-v3-tras-guardar.png'), fullPage: true })
})
