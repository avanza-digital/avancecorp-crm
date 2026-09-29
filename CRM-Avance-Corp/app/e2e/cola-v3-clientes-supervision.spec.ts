// F3 de la cola v3 (29/09/2026): «Seguimiento comercial» y «Hoy» del supervisor
// leen `crm.cola_accion_v3_fn`, que suma a los leads las tareas de CLIENTES del
// día. Sesión real con transporte interceptado: la cola hace eco de los
// argumentos y aplica la regla del servidor para clientes (`p_etapa` los
// excluye; `p_analista_id` filtra a su responsable). No acredita RLS: eso lo
// hace el gate del banco.
import { expect, test, type Page } from '@playwright/test'
import { loginReal } from './_helpers'
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
  await montarColaEquipo(page, 'supervisor', 4, CLIENTES)
  await loginReal(page)
  const lista = page.getByRole('list', { name: /^Pendientes del equipo/ })
  const fila = lista.getByRole('link', { name: /^Abrir la ficha de CLIENTA INVERSIONISTA, cliente de la cartera, urgente: Gestión con cliente · venció/ })
  await expect(fila).toBeVisible()
  await expect(fila).toContainText('Cliente')
  await fila.click()
  await expect(page).toHaveURL(new RegExp(`#/mi-cartera/.*${INVERSIONISTA}`))
})
