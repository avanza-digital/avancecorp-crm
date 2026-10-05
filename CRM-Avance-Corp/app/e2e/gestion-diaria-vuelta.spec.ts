import { expect, test } from '@playwright/test'
import { leadReal, loginReal, montarBackendReal, UID } from './_helpers'
import { montarColaDiaV3 } from './_sla-cola'
import { paginarTrabajoDemo } from '../src/lib/gestion-diaria-cola-demo'
import type { FilaTrabajo, PedidoColaTrabajo } from '../src/lib/gestion-diaria-cola'
import muestra from '../src/data/gestion-diaria-cola-sql.fixture.json' with { type: 'json' }

const instante = '2026-09-30T15:00:00.000Z'
const idLead = (n: number) => `cccccccc-0000-4000-8000-${String(n).padStart(12, '0')}`

test('vuelta real: guardar, error recuperable, siguiente entre páginas y progreso al volver', async ({ page }, info) => {
  await page.clock.install({ time: new Date(instante) })
  const leads = Array.from({ length: 25 }, (_, i) => leadReal({ id: idLead(i + 1), nombre_completo: `COLA ${String(i + 1).padStart(2, '0')}`, vendedor_id: UID, etapa: 'contactado', fueraDelBoot: i > 7 }))
  const backend = await montarBackendReal(page, { rolCrm: 'vendedor', leads })
  // El día simulado del servidor comparte el reloj fijado en el navegador.
  await montarColaDiaV3(page, backend, [], () => Date.parse(instante))
  const gestionadas = new Map<string, string>()
  const pedidos: PedidoColaTrabajo[] = []
  const guardados: string[] = []
  let fallo = true
  await page.route('**/rest/v1/rpc/gestion_diaria_cola_trabajo_fn', async (route) => {
    const args = route.request().postDataJSON()
    const pedido: PedidoColaTrabajo = { filtro: args.p_filtro, pagina: args.p_pagina, limite: args.p_limite, elegido: args.p_elegido ?? null }
    pedidos.push(pedido)
    await new Promise((resolve) => setTimeout(resolve, 80))
    const filas = leads.map((lead, i) => ({ ...muestra.items[0], clave: `lead:${lead.id}`, lead_id: lead.id,
      nombre_completo: lead.nombre_completo, referencia_en: new Date(Date.parse(instante) - (40 * 1440 - i) * 60_000).toISOString(),
      senal: { ...muestra.items[0]!.senal, lead_id: lead.id, nombre_completo: lead.nombre_completo },
      estado_trabajo: gestionadas.has(lead.id) ? 'gestionado' : 'pendiente', proxima_tarea: null,
      ultima_gestion: gestionadas.has(lead.id) ? { actividad_id: lead.id, resultado: 'no_contesto', en: gestionadas.get(lead.id), tarea_id: null, etapa_anterior: 'contactado' } : null,
    })) as FilaTrabajo[]
    await route.fulfill({ json: paginarTrabajoDemo(filas, pedido, UID, '2026-09-30', Date.parse(instante) + guardados.length * 1000) })
  })
  await page.route('**/rest/v1/rpc/registrar_llamada_v4', async (route) => {
    const args = route.request().postDataJSON()
    guardados.push(args.p_lead_id)
    if (fallo) { fallo = false; return route.fulfill({ status: 500, json: { code: 'XX000', message: 'Guardado interrumpido de prueba' } }) }
    gestionadas.set(args.p_lead_id, new Date(Date.parse(instante) + guardados.length * 1000).toISOString())
    await route.fulfill({ json: { version: 2, ok: true, operacion_id: args.p_operacion_id, comando: 'registrar_llamada', lead_id: args.p_lead_id,
      actividad_id: args.p_operacion_id, resultado: 'no_contesto', siguiente_id: null, descartado: false, no_insista: false, replay: false, etapa: 'contactado', intento_n: 1 } })
  })
  await loginReal(page)
  await page.goto('/#/gestion-diaria')
  const ahora = page.getByRole('region', { name: 'Ahora' })
  const grupos = page.getByRole('tablist', { name: 'Grupos de la cola' })
  await expect(ahora.getByRole('button', { name: 'Abrir la ficha de COLA 01' })).toBeVisible()
  // La última fila de la primera página: siguiente debe llegar desde el servidor.
  const octava = page.getByRole('list', { name: /^Todo/ }).getByRole('button', { name: /COLA 08/ })
  await octava.focus()
  await octava.press('Enter')
  await expect(ahora.getByRole('button', { name: 'Abrir la ficha de COLA 08' })).toBeFocused()
  await ahora.getByRole('button', { name: /^Más acciones/ }).click()
  await page.getByRole('menuitem', { name: 'Registrar resultado', exact: true }).click()
  const formulario = ahora.getByRole('group', { name: /Qué pasó con la llamada/ })
  await formulario.getByRole('radio', { name: /No contest/ }).check()
  await formulario.getByRole('checkbox', { name: /Agendar próxima acción/ }).uncheck()
  await formulario.getByRole('button', { name: 'Guardar', exact: true }).click()
  await expect(formulario).toBeVisible()
  await expect(ahora).toContainText('COLA 08')
  await expect(formulario.getByRole('button', { name: /Reintentar/ })).toBeVisible()
  await formulario.getByRole('button', { name: /Reintentar/ }).click()
  await expect(formulario).toHaveCount(0)
  await expect(ahora.getByRole('button', { name: 'Abrir la ficha de COLA 09' })).toBeVisible()
  await expect(ahora.getByRole('button', { name: 'Abrir la ficha de COLA 09' })).toBeFocused()
  expect(guardados).toEqual([idLead(8), idLead(8)])
  // Releer, salir y volver, y recargar conservan la selección por clave.
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(ahora).toContainText('COLA 09')
  await page.getByRole('button', { name: 'Pipeline', exact: true }).click()
  await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
  await expect(ahora).toContainText('COLA 09')
  await page.reload()
  await expect(ahora).toContainText('COLA 09')
  await grupos.getByRole('tab', { name: /^Sin conversación/ }).click()
  await expect(ahora).toContainText('COLA 01')
  for (let i = 0; i < 3; i++) await page.getByRole('button', { name: 'Siguiente', exact: true }).click()
  const ultima = page.getByRole('list', { name: /^Sin conversación/ })
  await expect(ultima.getByRole('button', { name: /COLA 08/ })).toContainText('No contestó · 10:00')
  await expect(page.getByRole('status').filter({ hasText: '25–25 de 25' })).toBeVisible()
  await page.screenshot({ path: info.outputPath('vuelta-ultimo-gestionado.png'), fullPage: true })
  expect(pedidos.every((p) => p.limite === 8)).toBe(true)
  // Agotamos los demás en el servidor y cerramos el último desde la interfaz.
  for (const lead of leads) if (lead.id !== idLead(25)) gestionadas.set(lead.id, instante)
  await grupos.getByRole('tab', { name: /^Todo/ }).click()
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(ahora).toContainText('COLA 25')
  await ahora.getByRole('button', { name: /^Más acciones/ }).click()
  await page.getByRole('menuitem', { name: 'Registrar resultado', exact: true }).click()
  await formulario.getByRole('radio', { name: /No contest/ }).check()
  await formulario.getByRole('checkbox', { name: /Agendar próxima acción/ }).uncheck()
  await formulario.getByRole('button', { name: 'Guardar', exact: true }).click()
  await expect(ahora).toContainText('Vuelta completada')
  await expect(ahora.getByRole('button', { name: /^Más acciones/ })).toHaveCount(0)
  await page.screenshot({ path: info.outputPath('vuelta-completada.png'), fullPage: true })
})
