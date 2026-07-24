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
    clasificacion_auto: null,
    comentario: 'Quiero información sobre el plazo fijo para invertir',
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
    clasificacion_auto: null,
    comentario: null,
  },
]

/** C1-bis: lead que el clasificador marcó (menciona préstamo en el comentario). */
const LEAD_CREDITO = {
  id: 'lead-credito',
  nombre_completo: 'PEDRO HUAMÁN',
  distrito: 'Comas',
  origen: 'formulario',
  categoria_interes: null,
  monto_estimado: 1000,
  moneda: 'PEN',
  creado_en: '2026-07-22T12:00:00.000Z',
  clasificacion_auto: 'posible_credito',
  comentario: 'Necesito un préstamo urgente, mi número es [teléfono oculto]',
}

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

// ── C1-bis: el código marca, Rosa lee el comentario y cierra ────────────────

test('el lead marcado muestra la etiqueta "Posible crédito" y el comentario redactado', async ({ page }) => {
  await entrarComoCoordinador(page, { colaReparto: [...COLA, LEAD_CREDITO] })

  // La marca del clasificador es visible y el comentario (ya redactado por el
  // servidor) se lee en la fila: el dato con el que Rosa decide.
  await expect(page.getByText('Posible crédito')).toBeVisible()
  await expect(page.getByText(/Necesito un préstamo urgente/)).toBeVisible()
  // Los leads sin marca NO llevan etiqueta (una sola en toda la cola).
  await expect(page.getByText('Posible crédito')).toHaveCount(1)
  // El comentario del lead limpio también se muestra.
  await expect(page.getByText(/plazo fijo para invertir/)).toBeVisible()
})

test('descartar un lead marcado: motivo pre-propuesto, RPC exacta y fila fuera', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, { colaReparto: [...COLA, LEAD_CREDITO] })

  await page.getByRole('button', { name: 'Descartar a PEDRO HUAMÁN de la cola' }).click()
  // La marca del código PROPONE el motivo; el humano solo confirma.
  await expect(page.getByLabel('Motivo para descartar a PEDRO HUAMÁN')).toHaveValue('pide_credito')
  await page.getByRole('button', { name: 'Descartar', exact: true }).click()

  // El servidor recibió lead y motivo exactos, sin nota.
  await expect.poll(() => backend.llamadas.rpcDescartarLead).toBe(1)
  expect(backend.ultimoDescarte).toEqual({ lead: 'lead-credito', motivo: 'pide_credito', nota: null })

  // La fila salió de la cola (se asevera por sus CONTROLES: el toast de éxito
  // también contiene el nombre y un getByText lo confundiría con la fila).
  await expect(page.getByLabel(/PEDRO HUAMÁN/)).toHaveCount(0)
  await expect(page.getByLabel('Asignar MARTHA VILCA a un supervisor')).toBeVisible()
})

test('el descarte se puede deshacer desde el aviso y el lead vuelve a la cola', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, { colaReparto: [...COLA, LEAD_CREDITO] })

  await page.getByRole('button', { name: 'Descartar a PEDRO HUAMÁN de la cola' }).click()
  await page.getByRole('button', { name: 'Descartar', exact: true }).click()
  await expect(page.getByLabel(/PEDRO HUAMÁN/)).toHaveCount(0)

  // El aviso de éxito ofrece Deshacer (la ventana real de 24 h vive en la BD).
  await page.getByRole('button', { name: 'Deshacer' }).click()

  await expect.poll(() => backend.llamadas.rpcDeshacerDescarte).toBe(1)
  // Tras deshacer se relee la cola: la fila está de vuelta con sus controles.
  await expect(page.getByLabel('Asignar PEDRO HUAMÁN a un supervisor')).toBeVisible()
})

test('un lead sin marca exige elegir motivo antes de poder descartar', async ({ page }) => {
  const backend = await entrarComoCoordinador(page)

  await page.getByRole('button', { name: 'Descartar a MARTHA VILCA de la cola' }).click()
  // Sin marca no hay motivo pre-propuesto: el botón queda deshabilitado.
  await expect(page.getByLabel('Motivo para descartar a MARTHA VILCA')).toHaveValue('')
  await expect(page.getByRole('button', { name: 'Descartar', exact: true })).toBeDisabled()

  await page.getByLabel('Motivo para descartar a MARTHA VILCA').selectOption('no_responde')
  await page.getByRole('button', { name: 'Descartar', exact: true }).click()

  await expect.poll(() => backend.llamadas.rpcDescartarLead).toBe(1)
  expect(backend.ultimoDescarte).toEqual({ lead: 'lead-usd', motivo: 'no_responde', nota: null })
})

test('si el descarte pierde la carrera, avisa y resincroniza la cola', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, {
    fallarProximoDescarte: {
      code: 'P0002',
      message: 'El lead ya no está en la cola por repartir (carrera de descarte)',
    },
  })

  const releidasAntes = backend.llamadas.rpcLeadsPorRepartir
  await page.getByRole('button', { name: 'Descartar a MARTHA VILCA de la cola' }).click()
  await page.getByLabel('Motivo para descartar a MARTHA VILCA').selectOption('sin_interes')
  await page.getByRole('button', { name: 'Descartar', exact: true }).click()

  await expect(page.getByText(/carrera de descarte/)).toBeVisible()
  await expect.poll(() => backend.llamadas.rpcLeadsPorRepartir).toBeGreaterThan(releidasAntes)
})

test('Cancelar sale del modo descarte sin llamar al servidor', async ({ page }) => {
  const backend = await entrarComoCoordinador(page)

  await page.getByRole('button', { name: 'Descartar a MARTHA VILCA de la cola' }).click()
  await expect(page.getByLabel('Motivo para descartar a MARTHA VILCA')).toBeVisible()

  await page.getByRole('button', { name: 'Cancelar' }).click()

  await expect(page.getByLabel('Asignar MARTHA VILCA a un supervisor')).toBeVisible()
  expect(backend.llamadas.rpcDescartarLead).toBe(0)
})
