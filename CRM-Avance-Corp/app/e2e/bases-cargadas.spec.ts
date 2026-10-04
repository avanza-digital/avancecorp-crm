// E2E de la pestaña «Bases» (F5) en sesión REAL con el HTTP de Supabase interceptado: el ESTADO DE PRODUCCIÓN (B10 sin
// aplicar → «disponible pronto»), cargar un CSV de punta a punta (vista previa → crear_base → lotes → informe →
// «Descargar informe»), y dentro de una base el reparto por cantidades y el seguimiento con «Recoger». Se comprueba lo
// que VIAJA a cada puerta (el contrato), no solo lo que se pinta.
import { readFile } from 'node:fs/promises'
import { expect, test, type Page } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

const BASE = '00000000-0000-4000-8000-0000000b0a5e'
const ANA = '00000000-0000-4000-8000-0000000a0a0a'
// El roster de montarBackendReal: «Analista Real Uno» (vend-1) y «Dos» (vend-2); la lista va por nombre: Dos, Uno.
const UID_EQUIPO = ['vend-1', 'vend-2']
const FILA_BASE = {
  base_id: BASE, nombre: 'Feria 2025', origen: 'archivo', supervisor_id: 'yo', supervisor_nombre: 'SUPERVISOR E2E', creado_en: '2026-10-01T15:00:00Z',
  total: 155, sin_repartir: 85, repartidos: 70, sin_tocar: 22, trabajados: 40, en_descanso: 3, citas: 4, reactivados: 1, avance: 0.57,
}
const PGRST202 = { code: 'PGRST202', message: 'Could not find the function in the schema cache', details: null, hint: null }

/** Entra directo a la pestaña «Bases» (la URL la lleva, como al recargar). */
async function entrarABases(page: Page) {
  await loginReal(page)
  await page.evaluate(() => {
    window.history.replaceState(window.history.state, '', '/?rescate_vista=bases#/hoy')
    window.location.hash = '#/rescate'
  })
  await expect(page.getByRole('tab', { name: 'Bases' })).toHaveAttribute('aria-selected', 'true')
}

test('ESTADO DE PRODUCCIÓN: sin la B10 la pestaña dice «Bases: disponible pronto» y no ofrece cargar', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'supervisor' })
  await page.route('**/rest/v1/rpc/seguimiento_bases', (route) => route.fulfill({ status: 404, json: PGRST202 }))
  await entrarABases(page)
  await expect(page.getByText('Bases: disponible pronto')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Cargar base' })).toHaveCount(0)
  // Las otras dos pestañas siguen ahí, intactas.
  await expect(page.getByRole('tab', { name: 'Descartes del mes' })).toBeVisible()
  await expect(page.getByRole('tab', { name: 'Gestión de la base' })).toBeVisible()
})

test('cargar un CSV: vista previa → crear_base + lotes → informe por veredicto → descargar (sin datos ajenos)', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'supervisor' })
  let creada = false
  await page.route('**/rest/v1/rpc/seguimiento_bases', (route) => route.fulfill({ json: creada ? [{ ...FILA_BASE, total: 2, sin_repartir: 2, repartidos: 0, sin_tocar: 0, trabajados: 0, citas: 0, avance: null }] : [] }))
  const crear: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/crear_base', async (route) => {
    crear.push(route.request().postDataJSON() as Record<string, unknown>)
    creada = true
    await route.fulfill({ json: { ok: true, operacion_id: crear[0]?.p_operacion_id, base_id: BASE, origen: 'archivo', supervisor_id: 'yo' } })
  })
  const lotes: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/cargar_base_lote', async (route) => {
    const cuerpo = route.request().postDataJSON() as { p_filas: { fila: number }[] }
    lotes.push(cuerpo)
    await route.fulfill({ json: {
      ok: true, base_id: BASE, lote: { filas: 3, cargadas: 2, ya_existian: 1, no_contactar: 0, invalidas: 0, repetidas: 0 }, base: { filas_recibidas: 3, cargadas: 2 },
      filas: [
        { fila: 2, veredicto: 'cargada' },
        { fila: 3, veredicto: 'ya_existia', motivo: 'con_dueno', lead_id: '00000000-0000-4000-8000-00000000dead' },
        { fila: 5, veredicto: 'cargada' },
      ],
    } })
  })

  await entrarABases(page)
  await expect(page.getByText('Todavía no hay bases')).toBeVisible()
  await page.getByRole('button', { name: 'Cargar base' }).first().click()
  const hoja = page.getByRole('dialog', { name: 'Cargar base' })
  const csv = ['Nombre;Celular;DNI;Distrito', 'ROSA QUISPE;987654321;45871236;Surco', 'LUIS RÍOS;987000111;;', 'SIN CELULAR;12345;;', 'ANA PÉREZ;987000222;;Lince'].join('\n')
  await hoja.getByLabel('Elegir el archivo').setInputFiles({ name: 'Feria 2025.csv', mimeType: 'text/csv', buffer: Buffer.from(csv, 'utf-8') })
  await expect(hoja.getByText('Feria 2025.csv · 4 filas con datos')).toBeVisible()
  await expect(hoja.getByRole('button', { name: /Se enviarán\s?:?\s?3/ })).toBeVisible()
  await expect(hoja.getByRole('button', { name: /Inválidas\s?:?\s?1/ })).toBeVisible()
  await expect(hoja.getByLabel('Nombre de la base')).toHaveValue('Feria 2025')
  await hoja.getByRole('button', { name: 'Cargar 3 contactos' }).click()

  await expect(hoja.getByRole('heading', { name: 'Informe de «Feria 2025»' })).toBeVisible()
  expect(crear).toEqual([{ p_operacion_id: expect.any(String), p_nombre: 'Feria 2025', p_origen: 'archivo', p_archivo_nombre: 'Feria 2025.csv' }])
  expect(lotes).toEqual([{
    p_operacion_id: expect.any(String), p_base_id: BASE,
    p_filas: [
      { fila: 2, nombre: 'ROSA QUISPE', telefono: '+51987654321', dni: '45871236', distrito: 'Surco' },
      { fila: 3, nombre: 'LUIS RÍOS', telefono: '+51987000111' },
      { fila: 5, nombre: 'ANA PÉREZ', telefono: '+51987000222', distrito: 'Lince' },
    ],
  }])
  // El id de la base no es el de la operación del lote: cada envío lleva el suyo.
  expect(lotes[0]?.p_operacion_id).not.toBe(crear[0]?.p_operacion_id)
  const tipos = hoja.getByRole('group', { name: 'Resultado por tipo' })
  await expect(tipos.getByRole('button', { name: /Cargadas\s?:?\s?2/ })).toBeVisible()
  await expect(tipos.getByRole('button', { name: /Ya existían\s?:?\s?1/ })).toBeVisible()
  await expect(tipos.getByRole('button', { name: /Inválidas\s?:?\s?1/ })).toBeVisible()

  const [descarga] = await Promise.all([page.waitForEvent('download'), hoja.getByRole('button', { name: 'Descargar informe' }).click()])
  expect(descarga.suggestedFilename()).toBe('informe-feria-2025.csv')
  const contenido = await readFile(await descarga.path(), 'utf-8')
  expect(contenido).toContain('"3","Ya existía","Ya es lead de un analista"')
  expect(contenido).toContain('"4","Inválida","El teléfono no es un celular peruano válido"')
  expect(contenido).not.toContain('dead')

  await hoja.getByRole('button', { name: 'Ver la base y repartir' }).click()
  await expect(page).toHaveURL(new RegExp(`rescate_base=${BASE}`))
  await expect(page.getByRole('heading', { level: 2, name: 'Feria 2025' })).toBeVisible()
})

test('dentro de una base: repartir por cantidades («En partes iguales») y seguimiento con «Recoger»', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'supervisor' })
  await page.route('**/rest/v1/rpc/seguimiento_bases', (route) => route.fulfill({ json: [FILA_BASE] }))
  await page.route('**/rest/v1/rpc/seguimiento_base', (route) => route.fulfill({ json: [{
    analista_id: ANA, analista_nombre: 'ANA E2E', asignados: 40, sin_tocar: 12, sin_tocar_3_dias: 5, trabajados: 28, en_descanso: 2, citas: 3, reactivados: 1,
    ultimo_intento_en: '2026-10-03T15:00:00Z', movidos_otra_via: 1,
  }] }))
  const detalle: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/seguimiento_base_detalle', async (route) => {
    detalle.push(route.request().postDataJSON() as Record<string, unknown>)
    await route.fulfill({ json: [{ lead_id: 'l1', nombre_completo: 'ROSA SIN TOCAR', estado: 'sin_tocar', asignado_en: '2026-09-29T15:00:00Z', ultimo_intento_en: null, ultimo_resultado: null }] })
  })
  const repartos: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/repartir_base', async (route) => {
    repartos.push(route.request().postDataJSON() as Record<string, unknown>)
    await route.fulfill({ json: { repartidos: 85, por_analista: [{ analista_id: 'vend-1', cantidad: 43 }, { analista_id: 'vend-2', cantidad: 42 }], omitidos: [] } })
  })
  const recoger: Record<string, unknown>[] = []
  await page.route('**/rest/v1/rpc/recoger_de_base', async (route) => {
    recoger.push(route.request().postDataJSON() as Record<string, unknown>)
    await route.fulfill({ json: { recogidos: 12, omitidos: 28 } })
  })

  await loginReal(page)
  await page.evaluate((base) => {
    window.history.replaceState(window.history.state, '', `/?rescate_vista=bases&rescate_base=${base}#/hoy`)
    window.location.hash = '#/rescate'
  }, BASE)
  await expect(page.getByRole('heading', { level: 2, name: 'Feria 2025' })).toBeVisible()

  await expect(page.getByText('0 de 85 por repartir')).toBeVisible()
  await page.getByRole('button', { name: 'En partes iguales' }).click()
  await expect(page.getByText('85 de 85 por repartir')).toBeVisible()
  await page.getByRole('button', { name: 'Repartir 85' }).click()
  await expect.poll(() => repartos.length).toBe(1)
  expect(repartos[0]).toEqual({
    p_operacion_id: expect.any(String), p_base_id: BASE,
    p_reparto: { modo: 'bloque', asignaciones: [{ analista_id: UID_EQUIPO[1], cantidad: 43 }, { analista_id: UID_EQUIPO[0], cantidad: 42 }] },
  })

  const seguimiento = page.getByRole('region', { name: 'Seguimiento de Feria 2025 por analista' })
  await seguimiento.getByRole('button', { name: /ANA E2E, sin tocar 3 días/ }).click()
  await expect(page.getByRole('dialog', { name: /Sin tocar 3 días/ }).getByText('ROSA SIN TOCAR')).toBeVisible()
  expect(detalle).toContainEqual({ p_base_id: BASE, p_analista_id: ANA, p_cifra: 'sin_tocar_3_dias' })
  await page.keyboard.press('Escape')

  await seguimiento.getByRole('button', { name: 'Recoger lo que ANA E2E no tocó' }).click()
  await page.getByRole('dialog', { name: '¿Recoger lo que ANA E2E no tocó?' }).getByRole('button', { name: 'Recoger' }).click()
  await expect.poll(() => recoger.length).toBe(1)
  expect(recoger[0]).toEqual({ p_operacion_id: expect.any(String), p_base_id: BASE, p_analista_id: ANA })
  await expect(page.getByText(/Recogidos 12/)).toBeVisible()
})
