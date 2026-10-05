import { irAModulo } from './_navegacion'
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

test('Gestionado busca fuera de la página cargada, pagina y no mezcla su caché con Nuevo', async ({ page }) => {
  const leads = carteraGrande(120).map(l => ({ ...l, etapa: 'nuevo', tenencia_desde: l.creado_en }))
  // Ninguno está en las primeras 50 filas de la lista sin filtro.
  const gestionados = leads.slice(60, 115)
  const consultas: Record<string, unknown>[] = []
  await montarBackendReal(page, { leads })
  await page.route('**/rest/v1/rpc/cartera_filtrada_fn', async route => {
    const body = route.request().postDataJSON() as Record<string, unknown>
    if (body.p_gestion !== 'con_gestion') return route.fallback()
    consultas.push(body)
    expect(body.p_etapa).toBe('nuevo')
    const inicio = body.p_antes_id ? gestionados.findIndex(l => l.id === body.p_antes_id) + 1 : 0
    await route.fulfill({ json: {
      version: 1, generado_en: new Date().toISOString(), desde: null, hasta: null,
      items: gestionados.slice(inicio, inicio + Number(body.p_limite)).map(l => ({
        ...l, ultimo_contacto_en: null, recibido_en: null, recepcion_aproximada: false,
      })),
      resumen: {
        totales: { vivos: 55, abiertos: 55, asignados: 55, parkeados: 0, convertidos: 0,
          descartados: 0, asignados_pen: 55, asignados_usd: 0, reasignados: 0 },
        capital: { asignado: { pen: 550000, usd: 0 }, parkeado: { pen: 0, usd: 0 }, ganado: { pen: 0, usd: 0 } },
        embudo: [{ etapa: 'nuevo', n: 55 }],
      },
    } })
  })
  await loginReal(page)
  await irACartera(page)
  const tabla = page.getByRole('table', { name: 'Cartera de leads' })
  const filas = tabla.locator('tbody tr')
  const etapa = page.getByLabel('Filtrar por etapa')
  await expect(filas).toHaveCount(50)
  await expect(page.getByText('LEAD PAGINADO 060')).toHaveCount(0)
  await etapa.selectOption('gestionado')
  await expect(page.getByText('LEAD PAGINADO 060')).toBeVisible()
  await expect(filas).toHaveCount(50)
  await expect(page.getByRole('button', { name: /Gestionado 55/ })).toBeVisible()
  await expect(filas.first()).toContainText('Gestionado')
  await page.getByRole('button', { name: /cargar más leads/i }).click()
  await expect(filas).toHaveCount(55)
  await expect(page.getByText('LEAD PAGINADO 114')).toBeVisible()
  expect(consultas).toHaveLength(2)
  expect(consultas[0]).not.toHaveProperty('p_antes_id')
  expect(consultas[1]?.p_antes_id).toBe(gestionados[49]?.id)
  await etapa.selectOption('nuevo')
  await expect(page.getByText('LEAD PAGINADO 000')).toBeVisible()
  await expect(filas).toHaveCount(50)
  await expect(page.getByText('LEAD PAGINADO 114')).toHaveCount(0)
})

test('reasignados muestra cifra, conserva procedencia y abre la ficha con ambas marcas', async ({ page }) => {
  const leads = [
    leadReal({ id: 'bbbbbbbb-0000-4000-8000-000000000101', nombre_completo: 'LEAD TRANSFERIDO',
      vendedor_id: UID, reasignado: true, alta_manual: true, creado_por: UID }),
    leadReal({ id: 'bbbbbbbb-0000-4000-8000-000000000102', nombre_completo: 'LEAD PRIMERA ENTREGA',
      vendedor_id: UID, reasignado: false, alta_manual: false, creado_por: null }),
  ]
  const estado = await montarBackendReal(page, { leads })
  await loginReal(page)
  await irACartera(page)

  const boton = page.getByRole('button', { name: 'Filtrar reasignados: 1' })
  await expect(boton).toHaveAttribute('aria-pressed', 'false')
  await expect(page.getByRole('row', { name: /LEAD TRANSFERIDO/ })).toContainText('Manual')
  await expect(page.getByRole('row', { name: /LEAD TRANSFERIDO/ })).toContainText('Reasignado')
  const consultas = estado.llamadas.rpcCarteraPagina
  await boton.click()
  await expect(page.getByRole('row', { name: /LEAD TRANSFERIDO/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /LEAD PRIMERA ENTREGA/ })).toHaveCount(0)
  await expect.poll(() => estado.llamadas.rpcCarteraPagina).toBeGreaterThan(consultas)
  await page.getByRole('row', { name: /LEAD TRANSFERIDO/ }).click()
  await expect(page.getByRole('dialog')).toContainText('Reasignado')
  await expect(page.getByRole('dialog')).toContainText('Manual')
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

  await irAModulo(page, 'Leads')

  await expect(page.getByText(/No se pudo cargar la lista de leads/i)).toBeVisible()
  await expect(page.getByRole('button', { name: /reintentar/i })).toBeVisible()
  await expect(page.getByRole('button', { name: /cargar más leads/i })).toHaveCount(0)
})
