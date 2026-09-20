// E2E del historial POR LEAD (Fase 1 «sin topes», 19/09/2026), en sesión REAL
// con todo el HTTP de Supabase interceptado. Lo que la ruta demo no puede
// probar: que la ficha ya NO depende de la lista global del ámbito (la que
// PostgREST recorta a 1 000 filas) y que un enlace abre un lead aunque la foto
// inicial no lo traiga.
import { expect, test } from '@playwright/test'
import { abrirLead, irAPipeline, leadReal, loginReal, montarBackendReal, UID } from './_helpers'

test('el historial de la ficha llega POR LEAD y sobrevive a recargar aunque la lista global venga vacía', async ({ page }) => {
  await montarBackendReal(page, { leads: [leadReal({ vendedor_id: UID })] })
  // La lista global del ámbito responde VACÍA a propósito: si la ficha siguiera
  // filtrando de ahí (el bug del 19/09), no vería la gestión que registra.
  await page.route('**/rest/v1/rpc/actividades_del_ambito_fn', (route) => route.fulfill({ json: [] }))
  const porLead: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/actividades_de_lead_fn', async (route) => {
    porLead.push(route.request().postDataJSON() as Record<string, unknown>)
    await route.fallback()
  })
  await loginReal(page)
  await irAPipeline(page)
  let ficha = await abrirLead(page, /CLIENTE REAL UNO/)
  await expect(ficha.getByText('Sin gestiones todavía.')).toBeVisible()

  await ficha.getByRole('button', { name: /Copiar el número .* y registrar la llamada/ }).click()
  // Gestión Diaria F2: la llamada se cierra con su resultado tipificado.
  const dialogo = page.getByRole('dialog', { name: /Cómo salió la llamada/ })
  await dialogo.getByRole('radio', { name: /^No contestó/ }).check()
  await dialogo.getByRole('button', { name: 'Guardar', exact: true }).click()
  await expect(dialogo).toHaveCount(0)
  await expect(ficha.locator('li', { hasText: 'Llamada no contestada' }).first()).toBeVisible()

  // Tras recargar, la foto optimista ya no existe: lo que se ve viene del servidor, por lead.
  await page.reload()
  await expect(page.locator('.ac-splash')).toBeHidden()
  ficha = page.getByRole('dialog', { name: /CLIENTE REAL UNO/ })
  await expect(ficha).toBeVisible()
  await expect(ficha.locator('li', { hasText: 'Llamada no contestada' }).first()).toBeVisible()
  await expect(ficha.getByText('Sin gestiones todavía.')).toHaveCount(0)
  expect(porLead.length).toBeGreaterThan(0)
  // Pide una fila de más que la página: así distingue «hay más» de «justo cabía».
  expect(porLead[0]).toMatchObject({ p_limite: 101 })
})

test('un lead que la foto inicial no trae se abre igual por enlace: la ficha lo relee por id', async ({ page }) => {
  const fueraId = '00000000-0000-4000-8000-00000000f0f0'
  await montarBackendReal(page, {
    leads: [
      leadReal({ vendedor_id: UID }),
      { ...leadReal({ id: fueraId, nombre_completo: 'CLIENTE FUERA DE LA FOTO', telefono: '+51999000111', vendedor_id: UID }), fueraDelBoot: true },
    ],
  })
  await loginReal(page)

  await page.evaluate((id) => { window.location.hash = `#/pipeline/lead/${id}` }, fueraId)

  await expect(page.getByRole('dialog', { name: /CLIENTE FUERA DE LA FOTO/ })).toBeVisible()
})
