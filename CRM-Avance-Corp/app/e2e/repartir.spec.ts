// E2E de C1 — "Repartir leads" por la RUTA REAL (sesión autenticada con rol
// `coordinador`, todo el HTTP de Supabase interceptado: cero escritura en prod).
//
// Prueba lo que ni el gate SQL ni los tests de componente cubren: que el rol
// nuevo ATERRIZA en su pantalla, que su navegación se reduce a lo suyo, que el
// reparto viaja con los argumentos correctos y saca la fila, y que los dos
// rechazos que importan — el veto legal (Ley 29571) y el lead que ya salió de la
// cola — avisan al usuario y fuerzan una resincronización en vez de mentir.
import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

const SUPERVISORES = [
  { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', activo: true, bandeja_pendiente: 2 },
  { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', activo: true, bandeja_pendiente: 0 },
]

const COLA = [
  {
    id: 'lead-usd',
    nombre_completo: 'MARTHA VILCA',
    distrito: 'Miraflores',
    origen: 'landing',
    categoria_interes: 'nuevo',
    monto_estimado: 45000,
    moneda: 'USD',
    creado_en: '2026-07-20T12:00:00.000Z',
  },
  {
    id: 'lead-pen',
    nombre_completo: 'JORGE CASTRO',
    distrito: 'San Isidro',
    origen: 'referido',
    categoria_interes: 'nuevo',
    monto_estimado: 120000,
    moneda: 'PEN',
    creado_en: '2026-07-21T12:00:00.000Z',
  },
]

/** Monta el backend con rol coordinador y entra; devuelve el estado mutable. */
async function entrarComoCoordinador(page: Parameters<typeof loginReal>[0], init = {}) {
  const backend = await montarBackendReal(page, {
    rolCrm: 'coordinador',
    rolPortal: 'comercial',
    colaReparto: COLA,
    supervisoresReparto: SUPERVISORES,
    ...init,
  })
  await loginReal(page)
  await expect(page.getByRole('heading', { name: 'Repartir leads' })).toBeVisible()
  return backend
}

test('el coordinador aterriza en Repartir y su navegación se reduce a lo suyo', async ({ page }) => {
  await entrarComoCoordinador(page)

  // Aterrizaje por capacidad (no por hash guardado): su vista base es 'repartir'.
  await expect(page).toHaveURL(/#\/repartir$/)

  // El nav NO le ofrece cartera, equipo ni configuración (espejo de la RLS: su
  // ámbito de leads es vacío y no tiene cartera propia).
  await expect(page.getByRole('button', { name: 'Repartir leads' })).toBeVisible()
  for (const ajena of ['Mi cartera', 'Cartera', 'Equipo', 'Configuración', 'Pipeline']) {
    await expect(page.getByRole('button', { name: ajena, exact: true })).toHaveCount(0)
  }
})

test('#/mi-cartera por URL expulsa al coordinador de vuelta a Repartir', async ({ page }) => {
  await entrarComoCoordinador(page)

  await page.evaluate(() => { window.location.hash = '#/mi-cartera' })

  await expect(page).toHaveURL(/#\/repartir$/)
  await expect(page.getByRole('heading', { name: 'Repartir leads' })).toBeVisible()
})

test('la cabecera separa el capital PEN del USD (jamás los suma)', async ({ page }) => {
  await entrarComoCoordinador(page)

  await expect(page.getByText('Capital en juego (PEN)')).toBeVisible()
  await expect(page.getByText('Capital en juego (USD)')).toBeVisible()
  await expect(page.getByText('S/ 120k')).toBeVisible()
  await expect(page.getByText('US$ 45k')).toBeVisible()
  // 165k sería la suma mezclada de dos monedas: no debe existir.
  await expect(page.getByText(/165k/)).toHaveCount(0)
})

test('repartir un lead lo saca de la cola y sube la bandeja del supervisor', async ({ page }) => {
  const backend = await entrarComoCoordinador(page)

  await expect(page.getByText('MARTHA VILCA')).toBeVisible()
  await page.getByLabel('Asignar MARTHA VILCA a un supervisor').selectOption('sup-1')
  await page.getByRole('button', { name: 'Repartir', exact: true }).first().click()

  // El servidor recibió el par correcto…
  await expect.poll(() => backend.llamadas.rpcRepartirLead).toBe(1)
  expect(backend.ultimoReparto).toEqual({ lead: 'lead-usd', supervisor: 'sup-1' })

  // …la fila desaparece de la cola y el capital USD se recalcula…
  await expect(page.getByText('MARTHA VILCA')).toHaveCount(0)
  await expect(page.getByText('US$ 0')).toBeVisible()
  // …y la bandeja del destino ya refleja el lead que acaba de recibir.
  await expect(page.getByLabel('Asignar JORGE CASTRO a un supervisor'))
    .toContainText('SUPERVISOR UNO (3 en bandeja)')
})

test('el veto legal (No Insista) avisa, NO mueve la fila y resincroniza la cola', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, {
    fallarProximoReparto: {
      code: 'P0429',
      message: 'Lead marcado No Insista (Ley 29571): no se puede repartir',
    },
  })

  const releidasAntes = backend.llamadas.rpcLeadsPorRepartir
  await page.getByLabel('Asignar MARTHA VILCA a un supervisor').selectOption('sup-2')
  await page.getByRole('button', { name: 'Repartir', exact: true }).first().click()

  // Mensaje LEGAL literal (no un "no tienes permiso" genérico).
  await expect(page.getByText('Lead marcado No Insista (Ley 29571): no se puede repartir'))
    .toBeVisible()
  // La fila NO se movió: el servidor revirtió y el frontend no miente.
  await expect(page.getByText('MARTHA VILCA')).toBeVisible()
  // Y la cola se relee: el estado local estaba desfasado respecto del servidor.
  await expect.poll(() => backend.llamadas.rpcLeadsPorRepartir).toBeGreaterThan(releidasAntes)
})

test('si el lead ya salió de la cola, avisa y resincroniza', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, {
    fallarProximoReparto: {
      code: 'P0002',
      message: 'El lead ya no está en la cola por repartir (tiene dueño, está cerrado o no existe)',
    },
  })

  const releidasAntes = backend.llamadas.rpcLeadsPorRepartir
  await page.getByLabel('Asignar JORGE CASTRO a un supervisor').selectOption('sup-1')
  await page.getByRole('button', { name: 'Repartir', exact: true }).nth(1).click()

  await expect(page.getByText(/ya no está en la cola por repartir/)).toBeVisible()
  await expect.poll(() => backend.llamadas.rpcLeadsPorRepartir).toBeGreaterThan(releidasAntes)
})

test('cola vacía: estado honesto que explica de dónde vendrán los leads', async ({ page }) => {
  await entrarComoCoordinador(page, { colaReparto: [] })

  await expect(page.getByText('No hay leads por repartir')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Repartir', exact: true })).toHaveCount(0)
})

test('sin supervisores activos no se puede repartir y la pantalla lo dice', async ({ page }) => {
  await entrarComoCoordinador(page, { supervisoresReparto: [] })

  await expect(page.getByText('No hay supervisores activos')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Repartir', exact: true })).toHaveCount(0)
})
