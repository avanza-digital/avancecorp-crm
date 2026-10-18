// F3 de la cola v3 (29/09/2026): «Seguimiento comercial» y «Hoy» del supervisor
// La cola lee `crm.cola_accion_v3_fn`, que suma a los leads las tareas de CLIENTES del
// día. Sesión real con transporte interceptado: la cola hace eco de los
// argumentos y aplica la regla del servidor para clientes (`p_etapa` los
// excluye; `p_analista_id` filtra a su responsable). No acredita RLS: eso lo
// hace el gate del banco. Hoy abre ahora el detalle por analista mediante
// `gestion_diaria_pendientes_v2_fn`; se conserva la identidad del cliente.
import { expect, test, type Page } from '@playwright/test'
import { loginReal, UID } from './_helpers'
import { montarLecturasHoySupervisor } from './_hoy-supervisor'
import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'
import { paginaPendientes, tareaPendiente } from '../src/lib/gestion-diaria-pendientes.fixture'
import { montarColaEquipo, type ClienteCola } from './_sla-cola'

const ANALISTA_UNO = 'aaaaaaaa-0000-4000-8000-000000000001'
const ANALISTA_DOS = 'aaaaaaaa-0000-4000-8000-000000000002'
const INVERSIONISTA = 'dddddddd-0000-4000-8000-0000000000a1'
const CLIENTES: ClienteCola[] = [
  { tarea: 'eeeeeeee-0000-4000-8000-0000000000c1', nombre: 'CLIENTA INVERSIONISTA', inversionista_id: INVERSIONISTA, perfil_id: null, vencida: true, responsable: ANALISTA_UNO },
  { tarea: 'eeeeeeee-0000-4000-8000-0000000000c2', nombre: 'CLIENTE SOLO PORTAL', inversionista_id: null, perfil_id: 'ffffffff-0000-4000-8000-0000000000b1', vencida: false, responsable: ANALISTA_DOS },
]
const listaCola = (page: Page) => page.getByRole('list', { name: 'Oportunidades de esta página' })

test('Seguimiento comercial (supervisor): las tareas de clientes entran con los leads y respetan etapa y analista', async ({ page }, info) => {
  const { pedidos } = await montarColaEquipo(page, 'supervisor', 4, CLIENTES)
  await loginReal(page)
  await page.goto('/#/gestion-diaria/cola')
  await expect(page.getByRole('heading', { name: 'Seguimiento comercial', exact: true })).toBeVisible()
  await expect.poll(() => pedidos.at(-1)).toMatchObject({ p_senal: 'pendientes', p_cursor: null })

  // «Para atender ahora»: la del cliente vencida entra; la de hoy todavía no.
  const inversionista = listaCola(page).getByRole('link', { name: /CLIENTA INVERSIONISTA/ })
  await expect(inversionista).toContainText('Cliente de la cartera')
  await expect(inversionista).toContainText('Gestión con cliente vencida')
  await expect(listaCola(page).getByText('CLIENTE SOLO PORTAL')).toHaveCount(0)
  await expect(page.getByText(/1 gestión con un cliente en esta página/)).toBeVisible()

  // «Todas las acciones»: aparece la de hoy; solo del portal → se lee, sin botón.
  await page.getByRole('button', { name: 'Todas las acciones', exact: true }).click()
  const portal = listaCola(page).locator(':scope > li', { hasText: 'CLIENTE SOLO PORTAL' })
  await expect(portal).toContainText('Gestión con cliente para hoy')
  await expect(portal).toContainText('Sin ficha en la cartera')
  // La nota se VE en cualquier ancho (antes vivía en una columna que el CSS oculta en estrecho).
  await expect(portal.getByText('Sin ficha en la cartera')).toBeVisible()
  await expect(portal.getByRole('button')).toHaveCount(0)
  await expect(portal.getByRole('link')).toHaveCount(0)
  await page.screenshot({ path: info.outputPath('seguimiento-v3-clientes.png'), fullPage: true })

  // Una etapa deja fuera a los clientes (no tienen etapa): lo decide el servidor.
  await page.getByRole('combobox', { name: 'Etapa', exact: true }).selectOption('contactado')
  await expect.poll(() => pedidos.at(-1)).toMatchObject({ p_etapa: 'contactado' })
  await expect(listaCola(page).getByText(/CLIENTA INVERSIONISTA|CLIENTE SOLO PORTAL/)).toHaveCount(0)

  // Por analista: solo la del cliente del que es responsable.
  await page.getByRole('button', { name: 'Limpiar filtros', exact: true }).click()
  await page.getByRole('button', { name: 'Todas las acciones', exact: true }).click()
  await page.getByRole('combobox', { name: 'Analista', exact: true }).selectOption(ANALISTA_UNO)
  await expect.poll(() => pedidos.at(-1)).toMatchObject({ p_analista_id: ANALISTA_UNO })
  await expect(listaCola(page).getByRole('link', { name: /CLIENTA INVERSIONISTA/ })).toBeVisible()
  await expect(listaCola(page).getByText('CLIENTE SOLO PORTAL')).toHaveCount(0)

  // Abrir la ficha del cliente lleva a su ficha de «Mi cartera», no a la de un lead.
  await listaCola(page).getByRole('link', { name: /CLIENTA INVERSIONISTA/ }).click()
  await expect(page).toHaveURL(new RegExp(`#/mi-cartera/.*${INVERSIONISTA}`))
})

test('Hoy del supervisor: la tarea del cliente dice que es de un cliente y abre su ficha', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  const corte = '2026-09-23T17:00:00.000Z'
  await page.clock.setFixedTime(new Date(corte))
  await montarColaEquipo(page, 'supervisor', 4, CLIENTES)
  await montarLecturasHoySupervisor(page)
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', async route => {
    const pedido = route.request().postDataJSON()
    const equipo = CLIENTES.map((c, i) => filaEquipoPrueba({ analista_id: c.responsable!,
      nombre_completo: i === 0 ? 'Analista Norte Uno' : 'Analista Norte Dos',
      tareas_pendientes: 1, tareas_vencidas: c.vencida ? 1 : 0,
      requiere_atencion: c.vencida, motivos_atencion: c.vencida ? ['tarea_vencida'] : [] }))
    await route.fulfill({ json: { ...diaEquipoPrueba(equipo), dia: pedido.p_dia,
      supervisor_id: UID, generado_en: corte, pendientes_al: corte } })
  })
  const pedidos: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/gestion_diaria_pendientes_v2_fn', async route => {
    const pedido = route.request().postDataJSON()
    pedidos.push(pedido)
    const propias = CLIENTES.filter(c => c.responsable === pedido.p_analista_id)
    const items = propias.filter(c => !pedido.p_solo_vencidas || c.vencida).map((c, i) => tareaPendiente(i, {
      id: c.tarea, vendedor_id: c.responsable!, titulo: 'Llamar',
      vence_en: c.vencida ? '2026-09-23T15:00:00.000Z' : '2026-09-23T18:00:00.000Z',
      referencia_tipo: c.inversionista_id ? 'postventa' : 'perfil', lead_id: null, lead_nombre: null,
      sujeto_tipo: c.inversionista_id ? 'inversionista' : 'perfil', sujeto_id: c.inversionista_id ?? c.perfil_id,
      sujeto_nombre: c.nombre, inversionista_id: c.inversionista_id, perfil_id: c.perfil_id, identidad_visible: true,
    }))
    await route.fulfill({ json: paginaPendientes(items, { version: 2, supervisor_id: UID,
      analista_id: pedido.p_analista_id, solo_vencidas: pedido.p_solo_vencidas, limite: pedido.p_limite,
      generado_en: corte, pendientes_al: corte,
      resumen: { tareas_pendientes: propias.length, tareas_vencidas: propias.filter(c => c.vencida).length } }) })
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Ver pendientes', exact: true }).click()
  await page.getByRole('dialog', { name: 'Pendientes del equipo', exact: true })
    .getByRole('button', { name: 'Ver tareas de Analista Norte Uno', exact: true }).click()
  const lista = page.getByRole('dialog', { name: 'Tareas de Analista Norte Uno', exact: true })
    .getByRole('list', { name: 'Lista de tareas pendientes' })
  const fila = lista.getByRole('listitem').filter({ hasText: 'CLIENTA INVERSIONISTA' })
  await expect(fila.getByText('Cliente', { exact: true })).toBeVisible()
  await expect(fila.getByText('Vencida', { exact: true })).toBeVisible()
  await expect(lista.getByText('CLIENTE SOLO PORTAL')).toHaveCount(0)
  expect(pedidos.at(-1)).toMatchObject({ p_analista_id: ANALISTA_UNO, p_solo_vencidas: false, p_limite: 25 })
  await fila.getByRole('button', { name: 'CLIENTA INVERSIONISTA', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`#/mi-cartera/.*${INVERSIONISTA}`))
})
