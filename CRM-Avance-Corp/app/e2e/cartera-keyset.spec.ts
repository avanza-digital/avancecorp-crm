// E2E de la cartera paginada por cursor keyset (F2), en sesión REAL y con todo
// el HTTP de Supabase interceptado. Lo que aquí se prueba no lo pueden probar
// los unitarios: que la pantalla PIDE páginas al servidor (y no recorta un
// array que ya tenía), que «Cargar más» concatena sin repetir, que filtrar
// vuelve a preguntar en vez de filtrar lo cargado, y que con la RPC caída la
// lista degrada sin prometer páginas que no existen.
import { expect, test } from '@playwright/test'
import { irACartera, leadReal, loginReal, montarBackendReal, UID } from './_helpers'

// RESUCITADA el 2026-08-18: la llave de leads se abrió para la fuerza de ventas
// y esta suite —escrita en su día contra el contrato NUEVO— vuelve a correr.

/** 60 leads con sellos decrecientes: 2 páginas de 50 + resto. */
function carteraGrande(n = 60) {
  return Array.from({ length: n }, (_, i) => leadReal({
    id: `bbbbbbbb-0000-4000-8000-${String(i).padStart(12, '0')}`,
    nombre_completo: `LEAD PAGINADO ${String(i).padStart(3, '0')}`,
    telefono: `+5199900${String(i).padStart(4, '0')}`,
    vendedor_id: UID,
    etapa: i % 2 === 0 ? 'nuevo' : 'contactado',
    actualizado_en: new Date(Date.UTC(2026, 7, 1) - i * 60_000).toISOString(),
  }))
}

test('la primera página trae 50 filas y «Cargar más» concatena sin repetir', async ({ page }) => {
  const estado = await montarBackendReal(page, { leads: carteraGrande() })
  await loginReal(page)
  await irACartera(page)

  const filas = page.getByRole('table', { name: 'Cartera de leads' }).locator('tbody tr')
  await expect(filas).toHaveCount(50)
  await expect(page.getByText('Total leads', { exact: true }).locator('..').locator('..')).toContainText('60')
  // El lead 51 NO está: la pantalla pinta lo que el servidor le dio, no todo.
  await expect(page.getByText('LEAD PAGINADO 050')).toHaveCount(0)

  await page.getByRole('button', { name: /cargar más leads/i }).click()

  await expect(filas).toHaveCount(60)
  await expect(page.getByText('LEAD PAGINADO 059')).toBeVisible()
  // Dos peticiones: la inicial y la del cursor. Si la pantalla hubiera
  // recortado un array propio, la segunda no existiría.
  await expect.poll(() => estado.llamadas.rpcCarteraPagina).toBe(2)
  // Agotada la lista, el botón desaparece: el servidor dijo que no hay más.
  await expect(page.getByRole('button', { name: /cargar más leads/i })).toHaveCount(0)
})

test('filtrar por etapa vuelve a preguntar al servidor', async ({ page }) => {
  const estado = await montarBackendReal(page, { leads: carteraGrande() })
  await loginReal(page)
  await irACartera(page)

  const llamadasIniciales = estado.llamadas.rpcCarteraPagina
  await page.getByLabel('Filtrar por etapa').selectOption('contactado')

  const filas = page.getByRole('table', { name: 'Cartera de leads' }).locator('tbody tr')
  await expect(filas).toHaveCount(30)
  await expect(page.getByText('Total leads', { exact: true }).locator('..').locator('..')).toContainText('30')
  await expect.poll(() => estado.llamadas.rpcCarteraPagina).toBeGreaterThan(llamadasIniciales)
})

test('buscar por nombre viaja al servidor y no recorta lo ya cargado', async ({ page }) => {
  const estado = await montarBackendReal(page, { leads: carteraGrande() })
  await loginReal(page)
  await irACartera(page)

  // «055» está en la página 2: filtrando en el cliente NO aparecería jamás.
  await page.getByLabel('Buscar en la cartera').fill('PAGINADO 055')

  await expect(page.getByText('LEAD PAGINADO 055')).toBeVisible()
  await expect.poll(() => estado.llamadas.rpcCarteraPagina).toBeGreaterThan(1)
})

test('RPC caída: la tabla degrada con aviso y NO ofrece más páginas', async ({ page }) => {
  await montarBackendReal(page, { leads: carteraGrande(), fallarCarteraPagina: true })
  await loginReal(page)

  await page.getByRole('button', { name: 'Leads', exact: true }).click()

  await expect(page.getByText(/No se pudo cargar la lista de leads/i)).toBeVisible()
  await expect(page.getByRole('button', { name: /reintentar/i })).toBeVisible()
  await expect(page.getByRole('button', { name: /cargar más leads/i })).toHaveCount(0)
})
