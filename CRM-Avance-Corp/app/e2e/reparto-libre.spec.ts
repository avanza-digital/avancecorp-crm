import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'
import { irAModulo } from './_navegacion'

test('Gerencia activa y desactiva el permiso del rol desde Configuración', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  let config = { version: 1, coordinacion_libre: false, revision: 1, actualizado_en: '2026-10-07T15:00:00Z' }
  const cambios: unknown[] = []
  await page.route('**/rest/v1/rpc/configuracion_reparto_fn', async (route) => {
    await route.fulfill({ json: config })
  })
  await page.route('**/rest/v1/rpc/guardar_configuracion_reparto_fn', async (route) => {
    const pedido = route.request().postDataJSON() as { p_libre: boolean; p_revision: number }
    cambios.push(pedido)
    expect(pedido.p_revision).toBe(config.revision)
    config = { ...config, coordinacion_libre: pedido.p_libre, revision: config.revision + 1 }
    await route.fulfill({ json: config })
  })
  await loginReal(page)
  await irAModulo(page, 'Configuración')
  await expect(page.getByRole('heading', { name: 'Reparto libre de Coordinación' })).toBeVisible()
  await page.getByRole('button', { name: 'Activar reparto libre' }).click()
  await expect(page.getByText('Reparto libre activado para todo el rol Coordinadora.')).toBeVisible()
  await page.getByRole('button', { name: 'Desactivar reparto libre' }).click()
  await expect(page.getByText('Reparto libre desactivado. Coordinación vuelve a seguir el turno guardado.')).toBeVisible()
  expect(cambios).toEqual([{ p_libre: true, p_revision: 1 }, { p_libre: false, p_revision: 2 }])
  await page.getByRole('heading', { name: 'Reparto libre de Coordinación' }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: 'test-results/reparto-libre-gerencia.png' })
})

test('Coordinación puede repartir sin turno y vuelve al bloqueo si Gerencia lo apaga', async ({ page }) => {
  const backend = await montarBackendReal(page, {
    rolCrm: 'coordinador', rolPortal: 'comercial',
    colaReparto: [{ id: 'libre-1', nombre_completo: 'LEAD LIBRE', distrito: null, origen: 'landing', categoria_interes: 'nuevo', monto_estimado: 10000, moneda: 'PEN', creado_en: new Date().toISOString() }],
    supervisoresReparto: [{ perfil_id: 'sup-1', nombre: 'SUPERVISOR LIBRE', activo: true, bandeja_pendiente: 0 }],
    agendaReparto: { version: 1, fecha_desde: '2026-10-07', reparto_libre: true, destinos: [], dias: [] },
  })
  await loginReal(page)
  await page.getByRole('tab', { name: 'Cola de nuevos' }).click()
  const selector = page.getByLabel('Asignar LEAD LIBRE a un supervisor')
  await expect(selector).toBeEnabled()
  await selector.selectOption('sup-1')
  backend.agendaReparto = { ...backend.agendaReparto, reparto_libre: false }
  backend.fallarProximoReparto = { code: '22023', message: 'Antes de repartir Landing, guarda el turno de hoy.' }
  await page.getByRole('button', { name: 'Repartir a LEAD LIBRE' }).click()
  await expect(selector).toBeDisabled()
  await expect(page.getByText('LEAD LIBRE', { exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Repartir a LEAD LIBRE' })).toBeDisabled()
  expect(backend.colaReparto).toHaveLength(1)
})

test('Coordinación deriva a otro supervisor con un turno guardado', async ({ page }) => {
  const ahora = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date())
  const backend = await montarBackendReal(page, {
    rolCrm: 'coordinador', rolPortal: 'comercial',
    colaReparto: [{ id: 'libre-2', nombre_completo: 'LEAD OTRO DESTINO', distrito: null, origen: 'landing', categoria_interes: 'nuevo', monto_estimado: 10000, moneda: 'PEN', creado_en: new Date().toISOString() }],
    supervisoresReparto: [
      { perfil_id: 'sup-1', nombre: 'SUPERVISOR DE TURNO', activo: true, bandeja_pendiente: 0 },
      { perfil_id: 'sup-2', nombre: 'OTRO SUPERVISOR', activo: true, bandeja_pendiente: 0 },
    ],
    agendaReparto: {
      version: 1, fecha_desde: ahora, reparto_libre: true, destinos: [],
      dias: [{ fecha: ahora, asignaciones: [{ origen: 'landing', supervisor_id: 'sup-1', supervisor_nombre: 'SUPERVISOR DE TURNO', supervisor_alias: null, derivados: 0, fuera_turno: 0, entregas: [] }] }],
    },
  })
  await loginReal(page)
  await page.getByRole('tab', { name: 'Cola de nuevos' }).click()
  const selector = page.getByLabel('Asignar LEAD OTRO DESTINO a un supervisor')
  await expect(selector).toHaveValue('sup-1')
  await selector.selectOption('sup-2')
  await page.getByRole('button', { name: 'Repartir a LEAD OTRO DESTINO' }).click()
  await expect(page.getByText('No hay leads por repartir')).toBeVisible()
  expect(backend.ultimoReparto).toEqual({ lead: 'libre-2', supervisor: 'sup-2' })
})
