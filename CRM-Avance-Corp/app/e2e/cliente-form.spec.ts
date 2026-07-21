// E2E del formulario de CLIENTE del portal dentro del CRM: alta en 2 pasos
// (edge crear-cliente + PATCH de bancarios) y corrección con la ventana de 5 h,
// sobre la RUTA REAL con TODO el HTTP de Supabase interceptado (fail-closed —
// cero prod). Con el gate de leads cerrado, la vista por defecto de una cuenta
// real ES #/clientes.
//
// DEPENDENCIA: la pantalla screens/clientes.tsx (de otro constructor) debe
// ofrecer un botón "Nuevo cliente" y una acción "Corregir" por fila (espejo del
// portal); el dialog en sí queda nombrado por el DialogTitle de ClienteForm
// ('Nuevo cliente' / 'Corregir cliente'), así que los selectores del modal son
// estables aunque la pantalla cambie.
import { expect, test, type Locator, type Page } from '@playwright/test'
import { clienteReal, loginReal, montarBackendReal } from './_helpers'

// Fase 6.1 (2026-07-21): la entrada al ClienteForm migró a la cartera unificada
// (#/mi-cartera, la vista por defecto de una cuenta real). El MISMO modal se abre
// con "Nuevo cliente" / "Corregir cliente"; los asserts del modal no cambian.

/** Entra con sesión real y abre el modal de alta desde la pantalla Clientes. */
async function abrirNuevoCliente(page: Page): Promise<Locator> {
  await loginReal(page)
  await page.getByRole('button', { name: /nuevo cliente/i }).click()
  const modal = page.getByRole('dialog', { name: /nuevo cliente/i })
  await expect(modal).toBeVisible()
  return modal
}

/** Abre "Corregir" del primer cliente de la cartera. */
async function abrirCorregirCliente(page: Page): Promise<Locator> {
  await loginReal(page)
  await page.getByRole('button', { name: /corregir/i }).first().click()
  const modal = page.getByRole('dialog', { name: /corregir cliente/i })
  await expect(modal).toBeVisible()
  return modal
}

/** Identidad + cuenta PEN completa (el mínimo válido del alta). */
async function llenarAltaMinima(modal: Locator): Promise<void> {
  await modal.locator('#cf-apellidos').fill('QA PRUEBA')
  await modal.locator('#cf-nombres').fill('MARIA JOSE')
  await modal.locator('#cf-documento').fill('45781299')
  await modal.locator('#cf-correo').fill('qa-cliente@correo.pe')
  await modal.locator('#cf-pen-banco').selectOption('BCP')
  await modal.locator('#cf-pen-tipo').selectOption('ahorros')
  await modal.locator('#cf-pen-numero').fill('19112345678901')
  await modal.locator('#cf-pen-cci').fill('00219112345678901234')
}

test('alta feliz: 2 pasos (edge + PATCH de bancarios) con el aviso de la clave temporal', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor' })
  const modal = await abrirNuevoCliente(page)

  // El aviso de la clave temporal se muestra como en el portal.
  await expect(modal.getByText(/clave temporal/i)).toBeVisible()

  await llenarAltaMinima(modal)
  await modal.getByRole('button', { name: /crear cliente/i }).click()

  // Paso 1 (edge crear-cliente) y paso 2 (PATCH a perfiles) viajaron, en ese orden.
  await expect.poll(() => estado.llamadas.altaCliente).toBe(1)
  await expect.poll(() => estado.llamadas.patchPerfil).toBe(1)
  // El 2º paso dejó los bancarios en el perfil RECIÉN creado (servidor con estado).
  await expect
    .poll(() => estado.clientes.find((c) => c.correo === 'qa-cliente@correo.pe')?.banco ?? null)
    .toBe('BCP')
  // .first(): sonner duplica el nodo del texto (copia para el lector de pantalla).
  await expect(page.getByText(/Cliente "QA PRUEBA MARIA JOSE" creado/).first()).toBeVisible()
})

test('alta con bancarios fallando: aviso honesto y SIN encadenar al contrato', async ({ page }) => {
  // ventanaVencida hace que el PATCH a perfiles responda 200 con [] (0 filas,
  // SIN error) — exactamente cómo falla el paso 2 en el mundo real.
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', ventanaVencida: true })
  const modal = await abrirNuevoCliente(page)

  await llenarAltaMinima(modal)
  await modal.getByRole('button', { name: /crear cliente/i }).click()

  await expect(page.getByText(/los datos bancarios NO se guardaron — corrígelo ahora \(tienes 5 horas\)/)).toBeVisible()
  await expect.poll(() => estado.llamadas.altaCliente).toBe(1)
  await expect.poll(() => estado.llamadas.patchPerfil).toBe(1)
  // NO se encadenó al contrato: ni RPC ni modal de contrato a la vista.
  expect(estado.llamadas.rpcCrearContrato).toBe(0)
  await expect(page.getByRole('dialog', { name: /contrato/i })).toHaveCount(0)
  // Estado terminal: no queda botón "Crear cliente" que permita un alta doble.
  await expect(page.getByRole('button', { name: /crear cliente/i })).toHaveCount(0)
})

test('alta duplicada: el 409 de la edge se muestra tal cual y no hay 2º paso', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', fallarProximaAlta: true })
  const modal = await abrirNuevoCliente(page)

  await llenarAltaMinima(modal)
  await modal.getByRole('button', { name: /crear cliente/i }).click()

  await expect(modal.getByText('Este documento ya está registrado para otro cliente.')).toBeVisible()
  await expect.poll(() => estado.llamadas.altaCliente).toBe(1)
  expect(estado.llamadas.patchPerfil).toBe(0)
})

test('corregir feliz: precarga todo, correo bloqueado y el PATCH llega al servidor', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor',
    // Ventana viva: el botón "Corregir" de la fila no puede estar bloqueado.
    clientes: [clienteReal({ creado_en: new Date().toISOString() })],
  })
  const modal = await abrirCorregirCliente(page)

  // Precarga del detalle (obtenerClienteDetalle) + correo = cuenta de acceso.
  await expect(modal.locator('#cf-apellidos')).toHaveValue('PORTAL UNO')
  await expect(modal.locator('#cf-correo')).toBeDisabled()
  await expect(modal.locator('#cf-pen-banco')).toHaveValue('BCP')
  await expect(modal.getByText(/Ventana de corrección: Quedan/)).toBeVisible()

  await modal.locator('#cf-telefono').fill('999111222')
  await modal.getByRole('button', { name: /guardar corrección/i }).click()

  await expect.poll(() => estado.llamadas.patchPerfil).toBe(1)
  // .first(): sonner duplica el nodo del texto (copia para el lector de pantalla).
  await expect(page.getByText('Datos del cliente corregidos.').first()).toBeVisible()
  // El servidor simulado aplicó el cambio (no fue un éxito de mentira).
  await expect.poll(() => estado.clientes[0]?.telefono).toBe('999111222')
})

test('corregir con la ventana vencida: 0 filas sin error → mensaje de NO guardado', async ({ page }) => {
  // LA TRAMPA: el reloj local dice "vigente" (creado_en reciente) pero el
  // servidor ya no matchea la fila → 200 con [] y ningún error.
  await montarBackendReal(page, { rolCrm: 'vendedor',
    clientes: [clienteReal({ creado_en: new Date().toISOString() })],
    ventanaVencida: true,
  })
  const modal = await abrirCorregirCliente(page)

  await modal.locator('#cf-telefono').fill('999111222')
  await modal.getByRole('button', { name: /guardar corrección/i }).click()

  await expect(modal.getByText(
    'La ventana de corrección venció: los cambios NO se guardaron. Pide el cambio a administración.',
  )).toBeVisible()
  // Jamás se dice "guardado" sin filas confirmadas.
  await expect(page.getByText('Datos del cliente corregidos.')).toHaveCount(0)
})
