// E2E de la pantalla EQUIPO en modo DEMO (sin backend) — la red de seguridad
// del refactor de presentación: supervisor ve cards de SUS vendedores + su
// bandeja accionable; gerencia ve un bloque por supervisor con la TABLA
// comparativa y la bandeja global; directorio ve la misma radiografía SIN
// ningún botón de acción (espejo del write-gating de demo-roles.spec.ts).
// En todos: cero requests al host de Supabase (gate fail-closed).
import { expect, test } from '@playwright/test'
import { bloquearSupabase, entrarDemo } from './_helpers'

test('demo supervisor: cards de SUS vendedores, bandeja "Por repartir" y asignar con toast "(demo)"', async ({ page }) => {
  // Fail-closed: en demo NINGÚN request debe salir al host de Supabase.
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Supervisor')
  await page.getByRole('button', { name: 'Equipo' }).click()

  // Cards SOLO de sus vendedores directos (d-sup1 → d-v1 y d-v2); el equipo
  // de d-sup2 queda fuera del ámbito (anti-fuga, espejo de store-ambito).
  const cards = page.getByRole('list', { name: 'Vendedores de mi equipo' })
  await expect(cards.getByText('VENDEDOR UNO')).toBeVisible()
  await expect(cards.getByText('VENDEDOR DOS')).toBeVisible()
  await expect(cards.getByText('VENDEDOR TRES')).toHaveCount(0)

  // La bandeja trae SOLO los parkeados de SU bandeja (l5 y l11); el parkeado
  // de la bandeja de d-sup2 (l14) no existe para él. Se ancla en el select
  // accesible de cada fila (el nombre a secas también vive en la mini-cola).
  await expect(page.getByRole('heading', { name: 'Por repartir', exact: true })).toBeVisible()
  await expect(page.getByLabel('Asignar vendedor a LUIS GARCÍA FLORES')).toBeVisible()
  await expect(page.getByLabel('Asignar vendedor a RICARDO MAMANI CONDORI')).toBeVisible()
  await expect(page.getByText('SOFÍA HERRERA LUNA')).toHaveCount(0)

  // Asignar un parkeado: elegir vendedor + botón → el toast lleva "(demo)"
  // (mismo sufijo que el resto de mutaciones demo, guard yo?.demo).
  await page.getByLabel('Asignar vendedor a LUIS GARCÍA FLORES').selectOption({ label: 'VENDEDOR UNO' })
  await page.getByRole('button', { name: 'Asignar', disabled: false }).click()
  await expect(page.getByText('LUIS GARCÍA FLORES asignado a VENDEDOR UNO (demo)')).toBeVisible()

  expect(requestsSupabase()).toBe(0)
})

test('demo gerencia: un bloque por supervisor con la TABLA comparativa de vendedores', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Gerencia')
  await page.getByRole('button', { name: 'Equipo' }).click()

  // Un bloque por supervisor (orden por capital PEN desc: UNO primero).
  await expect(page.getByRole('heading', { name: 'Equipo de SUPERVISOR UNO' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Equipo de SUPERVISOR DOS' })).toBeVisible()

  // La comparativa por bloque es una TABLA real (columna a columna, no cards):
  // una cabecera por cada uno de los 2 equipos.
  for (const col of ['Vendedor', 'Últ. actividad', 'Activos', 'Capital PEN', 'Sin tocar', 'Conversión']) {
    await expect(page.getByRole('columnheader', { name: col })).toHaveCount(2)
  }

  // La fila de VENDEDOR TRES pinta sus números del ámbito global: S/ 113k en
  // proceso (l4+l13+l20), 25% de conversión (1 de 4) y el semáforo ROJO de
  // última actividad (l20 lleva 8 días sin movimiento — umbral >5 d).
  const filaV3 = page.getByRole('row', { name: /VENDEDOR TRES/ })
  await expect(filaV3.getByText('S/ 113k')).toBeVisible()
  await expect(filaV3.getByText('25%')).toBeVisible()
  await expect(filaV3.getByText('8 d sin act.')).toBeVisible()

  expect(requestsSupabase()).toBe(0)
})

test('demo gerencia: reparte desde la bandeja global (optgroup por equipo) con toast "(demo)"', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Gerencia')
  await page.getByRole('button', { name: 'Equipo' }).click()

  // La bandeja global existe para gerencia y ve parkeados de TODAS las
  // bandejas (l14 es de la bandeja de d-sup2).
  await expect(page.getByRole('heading', { name: 'Por repartir (toda la empresa)' })).toBeVisible()
  await expect(page.getByText('Bandeja: SUPERVISOR DOS')).toBeVisible()

  // Asignar cruzando de bandeja: SOFÍA (bandeja d-sup2) → VENDEDOR TRES.
  await page.getByLabel('Asignar vendedor a SOFÍA HERRERA LUNA').selectOption({ label: 'VENDEDOR TRES' })
  await page.getByRole('button', { name: 'Asignar', disabled: false }).click()
  await expect(page.getByText('SOFÍA HERRERA LUNA asignado a VENDEDOR TRES (demo)')).toBeVisible()

  expect(requestsSupabase()).toBe(0)
})

test('demo directorio: la misma radiografía en tabla pero SIN botones de acción', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Directorio')
  await page.getByRole('button', { name: 'Equipo' }).click()

  // Misma radiografía que gerencia: bloques por supervisor + tabla comparativa.
  await expect(page.getByText(/Vista de auditoría del Directorio/)).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Equipo de SUPERVISOR UNO' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Equipo de SUPERVISOR DOS' })).toBeVisible()
  await expect(page.getByRole('row', { name: /VENDEDOR UNO/ })).toBeVisible()

  // Solo lectura total: ni bandeja global ni un solo botón "Asignar"
  // (espejo del write-gating ya probado para el pipeline en demo-roles).
  await expect(page.getByRole('heading', { name: 'Por repartir (toda la empresa)' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Asignar' })).toHaveCount(0)

  expect(requestsSupabase()).toBe(0)
})
