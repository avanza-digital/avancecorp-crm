// E2E de "Mis clientes" (#/clientes) — la vista por DEFECTO de una cuenta real
// con el gate de leads cerrado (FUNCIONES_LEADS_APROBADAS=false): tras el login
// real se aterriza directo aquí. Todo el HTTP de Supabase va interceptado por
// montarBackendReal (fail-closed): nada llega a producción.
import { expect, test } from '@playwright/test'
import { bloquearSupabase, clienteReal, entrarDemo, loginReal, montarBackendReal } from './_helpers'

// Cartera de dos clientes: uno RECIÉN creado (ventana de 5 h viva) y uno viejo
// (ventana vencida) — el par exacto que necesita el reloj y el gate de corregir.
function carteraConVentanas() {
  return [
    clienteReal({
      id: 'cli-fresco-1',
      nombre_completo: 'CLIENTE FRESCO DOS',
      dni: '41112223',
      correo: 'fresco@correo.pe',
      creado_en: new Date().toISOString(),
    }),
    clienteReal(), // CLIENTE PORTAL UNO, creado_en 2026-07-01 → vencida hace rato
  ]
}

test('lista: pinta la cartera con columnas del portal y el contador', async ({ page }) => {
  await montarBackendReal(page, { clientes: carteraConVentanas() })
  await loginReal(page)

  // Con el gate cerrado la cuenta real cae directo en Clientes.
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  const filaVieja = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })
  await expect(filaVieja).toBeVisible()
  await expect(filaVieja.getByText('45781234')).toBeVisible()
  await expect(filaVieja.getByText('cliente1@correo.pe')).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE FRESCO DOS/ })).toBeVisible()

  // La regla de las 5 h se explica en pantalla (copy del portal).
  await expect(page.getByText(/El reloj de corrección corre 5 h/)).toBeVisible()
})

test('reloj de ventana: "Quedan…" para el recién creado y "Bloqueado" para el vencido', async ({ page }) => {
  await montarBackendReal(page, { clientes: carteraConVentanas() })
  await loginReal(page)
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  const filaFresca = page.getByRole('row', { name: /CLIENTE FRESCO DOS/ })
  const filaVieja = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })

  // Recién creado → quedan ~4 h 59 m; el formato exacto es 'Quedan H h MM m'.
  await expect(filaFresca.getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
  await expect(filaVieja.getByText('Bloqueado')).toBeVisible()
})

test('corregir: deshabilitado con la ventana vencida, habilitado con la ventana viva', async ({ page }) => {
  await montarBackendReal(page, { clientes: carteraConVentanas() })
  await loginReal(page)
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  const corregirVencido = page
    .getByRole('row', { name: /CLIENTE PORTAL UNO/ })
    .getByRole('button', { name: 'Corregir datos' })
  await expect(corregirVencido).toBeDisabled()

  const corregirVigente = page
    .getByRole('row', { name: /CLIENTE FRESCO DOS/ })
    .getByRole('button', { name: 'Corregir datos' })
  await expect(corregirVigente).toBeEnabled()

  // Con la ventana viva, el botón abre el formulario de corrección.
  await corregirVigente.click()
  await expect(page.getByRole('dialog')).toBeVisible()
})

test('"+ Contrato" abre el formulario de contrato del cliente (sin ventana: siempre activo)', async ({ page }) => {
  await montarBackendReal(page, { clientes: carteraConVentanas() })
  await loginReal(page)
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  // Incluso en la fila con la ventana de corrección VENCIDA: crear contrato no
  // tiene ventana (regla del portal).
  await page
    .getByRole('row', { name: /CLIENTE PORTAL UNO/ })
    .getByRole('button', { name: '+ Contrato' })
    .click()

  // El título del formulario (ContratoNuevo) nombra al cliente.
  await expect(page.getByRole('dialog', { name: /Crear contrato de CLIENTE PORTAL UNO/ })).toBeVisible()
})

// Regla del negocio: gerencia (rol de portal 'directorio') VE su cartera pero
// no da de alta ni corrige — la pantalla no le ofrece ninguna acción.
test('gerencia (rol de portal directorio): ve la lista SIN acciones de alta', async ({ page }) => {
  await montarBackendReal(page, { rolPortal: 'directorio', clientes: carteraConVentanas() })
  await loginReal(page)
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  await expect(page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Nuevo cliente' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Corregir datos' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: '+ Contrato' })).toHaveCount(0)
})

test('cartera vacía: estado vacío con el copy del portal', async ({ page }) => {
  await montarBackendReal(page, { clientes: [] })
  await loginReal(page)

  await expect(page.getByText('Mis clientes: 0')).toBeVisible()
  await expect(page.getByText('Aún no registraste clientes.')).toBeVisible()
  await expect(page.getByText(/Usa “\+ Nuevo cliente”/)).toBeVisible()
})

test('demo: la cartera se puebla con fixtures y el reloj corre — SIN pegarle a Supabase', async ({ page }) => {
  // Fail-closed: en demo NINGÚN request debe salir al host de Supabase. Si el
  // módulo intentara listar/crear, el route lo abortaría y el contador (== 0 al
  // final) lo delataría.
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Vendedor')
  await page.getByRole('button', { name: 'Clientes' }).click()

  // Contador y filas ficticias (incluye documentos CE y PASAPORTE).
  await expect(page.getByText('Mis clientes: 5')).toBeVisible()
  const filaViva = page.getByRole('row', { name: /ROSA MERCEDES AGUILAR VENTURA/ })
  await expect(filaViva).toBeVisible()
  await expect(page.getByRole('row', { name: /BRUNO ALEXIS FONSECA IPARRAGUIRRE/ }).getByText('PE1548792')).toBeVisible()

  // El reloj de 5 h: viva para el recién creado (−1 h), Bloqueado para el viejo (−40 d).
  await expect(filaViva.getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
  await expect(page.getByRole('row', { name: /GLADYS PILAR YUPANQUI ROJAS/ }).getByText('Bloqueado')).toBeVisible()

  // Acción demo: "+ Nuevo cliente" NO llama a la API — solo el toast "(demo)".
  await page.getByRole('button', { name: 'Nuevo cliente' }).click()
  await expect(page.getByText(/disponible solo con tu cuenta real \(demo\)/i)).toBeVisible()

  // Ninguna request salió al host de Supabase.
  expect(requestsSupabase()).toBe(0)
})
