// E2E de la RUTA REAL (sesión autenticada, yo.demo=false) con TODO el HTTP de
// Supabase interceptado — cero escritura en prod (lo no mockeado responde 500).
// Verifica lo que la ruta demo no puede: gate de escritura ABIERTO sin marcas
// "(demo)", persistencia real (POST/PATCH), rollback honesto ante rechazo del
// servidor, descarte que preserva la nota (y su fallo parcial), a quién se le
// ofrece convertir (rol de portal + cartera) y pantalla de error de carga con
// reintento.
import { expect, test } from '@playwright/test'
import {
  abrirConversionAvance,
  abrirLead,
  irAPipeline,
  leadReal,
  loginReal,
  montarBackendReal,
  UID,
} from './_helpers'

// RESUCITADA el 2026-08-18: con la llave de leads abierta, la sesión REAL sí
// entra al Pipeline. (La cobertura demo sigue viva en acciones-demo/demo-roles.)

test('sesión real: entra al workspace y la UI NO muestra ninguna marca "(demo)"', async ({ page }) => {
  // El lead es SUYO: así el botón de convertir está (el gate exige que el
  // cliente vaya a quedar en tu cartera) y sirve de sonda para el sufijo demo.
  await montarBackendReal(page, { leads: [leadReal({ vendedor_id: UID })] })
  await loginReal(page)

  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  // Botón de convertir SIN sufijo demo…
  await expect(drawer.getByRole('button', { name: 'Convertir a cliente' })).toBeVisible()
  // …y NADA en toda la página dice "(demo)".
  await expect(page.getByText('(demo)')).toHaveCount(0)
})

test('gate abierto: crear lead persiste por RPC atómica y el toast NO dice "(demo)"', async ({ page }) => {
  const estado = await montarBackendReal(page)
  await loginReal(page)
  await irAPipeline(page)

  await page.getByRole('button', { name: /nuevo lead/i }).click()
  const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
  await expect(modal).toBeVisible()
  await modal.locator('#nl-nombre').fill('LEAD REAL NUEVO')
  await modal.locator('#nl-telefono').fill('987222333')
  await modal.locator('#nl-monto').fill('5000')
  // Regla D8 (2026-08-11): el alta manual solo ofrece lo que declara un humano
  // (Referido/Wallking/Otro). LANDING y FORMULARIO entran solos por el puente.
  await modal.locator('#nl-origen').selectOption('oficina')
  await modal.getByRole('button', { name: /crear lead/i }).click()

  await expect(page.getByText(/Lead creado —/i)).toBeVisible()
  await expect(page.getByText('(demo)')).toHaveCount(0)
  // P-048 revalida inmediatamente antes del alta (puede existir además la
  // consulta de blur, según cuánto tarde el llenado del formulario).
  await expect.poll(() => estado.llamadas.rpcDisponibilidadLead).toBeGreaterThanOrEqual(1)
  // La mutación usa una sola RPC y nunca el POST directo legacy.
  await expect.poll(() => estado.llamadas.rpcCrearLeadAtomico).toBe(1)
  expect(estado.llamadas.insertLeadDirecto).toBe(0)
})

test('P-048: un contacto en bolsa queda explicado y no llega al INSERT', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    disponibilidadLead: { estado: 'en_bolsa' },
  })
  await loginReal(page)
  await irAPipeline(page)

  await page.getByRole('button', { name: /nuevo lead/i }).click()
  const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
  await modal.locator('#nl-telefono').fill('987222333')
  await modal.locator('#nl-nombre').click() // blur del teléfono → debounce P-048

  await expect(modal.getByRole('alert')).toContainText('bolsa de leads')
  await expect(modal.getByRole('button', { name: /crear lead/i })).toBeDisabled()
  expect(estado.llamadas.rpcCrearLeadAtomico).toBe(0)
  expect(estado.llamadas.insertLeadDirecto).toBe(0)
})

test('creación rechazada: rollback honesto y la RPC sí se intentó', async ({ page }) => {
  const estado = await montarBackendReal(page, { fallarProximaCreacionLeadAtomica: true })
  await loginReal(page)
  await irAPipeline(page)

  await page.getByRole('button', { name: /nuevo lead/i }).click()
  const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
  await modal.locator('#nl-nombre').fill('LEAD RECHAZADO')
  await modal.locator('#nl-telefono').fill('987333444')
  await modal.locator('#nl-monto').fill('5000')
  await modal.locator('#nl-origen').selectOption('formulario')
  await modal.getByRole('button', { name: /crear lead/i }).click()

  // La última defensa única ganó una carrera externa: no hay falso éxito.
  await expect(page.getByRole('alert')).toContainText(
    'Este contacto acaba de ser registrado por otro usuario',
  )
  await expect.poll(() => estado.llamadas.rpcCrearLeadAtomico).toBe(1)
  expect(estado.llamadas.insertLeadDirecto).toBe(0)
})

test('rollback honesto: rechazo del servidor mapea el mensaje, restaura el valor y no miente', async ({ page }) => {
  const estado = await montarBackendReal(page, { fallarProximaEdicionTelefono: true })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await drawer.getByRole('button', { name: 'Editar', exact: true }).click()
  await drawer.locator('#ld-telefono').fill('999111222')
  await drawer.getByRole('button', { name: /^Guardar$/ }).click()

  // aErrorApi mapea 23505/uq_leads_telefono_vivo → mensaje de teléfono duplicado,
  // y persistir lo concatena con "se actualizó la vista con el estado del servidor".
  await expect(
    page.getByText(/Ese teléfono ya pertenece a otro lead abierto de la empresa.*se actualizó la vista con el estado del servidor/i),
  ).toBeVisible()
  await expect.poll(() => estado.llamadas.rpcEditarLead).toBe(1)
  expect(estado.llamadas.patchLead).toBe(0)
  // El rechazo conserva el formulario para corregir, sin anunciar éxito.
  await expect(drawer.getByRole('alert')).toContainText('Ese teléfono ya pertenece')
  await expect(page.getByText('Cambios guardados', { exact: true })).toHaveCount(0)
  await drawer.getByRole('button', { name: 'Cancelar', exact: true }).click()
  // El valor persistido se revirtió al del servidor (no quedó el optimista).
  await expect(drawer.getByText('+51999000111')).toBeVisible()
  await expect(page.getByText('(demo)')).toHaveCount(0)
})

test('descartar real: persiste la nota como actividad aparte, toast sin "(demo)"', async ({ page }) => {
  const estado = await montarBackendReal(page)
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await drawer.getByRole('button', { name: /descartar/i }).click()
  const dialogo = page.getByRole('dialog', { name: 'Descartar lead' })
  await dialogo.locator('#ld-nota-descarte').fill('Sin fondos ahora; retomar en Q4')
  await dialogo.getByRole('button', { name: /descartar/i }).click()

  // Banner del drawer (el toast homónimo vive en un portal aparte: se scopea al
  // drawer para no chocar en strict-mode cuando ambos coexisten).
  await expect(drawer.getByText('Lead descartado')).toBeVisible()
  await expect(page.getByText('(demo)')).toHaveCount(0)
  // El UPDATE y la nota (actividad 'nota') viajaron al servidor.
  await expect.poll(() => estado.llamadas.patchLead).toBe(1)
  await expect.poll(() => estado.llamadas.insertActividad).toBe(1)
})

test('descartar real con nota fallida: avisa el fallo parcial SIN mentir "se restauró"', async ({ page }) => {
  await montarBackendReal(page, { fallarProximoInsertActividad: true })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await drawer.getByRole('button', { name: /descartar/i }).click()
  const dialogo = page.getByRole('dialog', { name: 'Descartar lead' })
  await dialogo.locator('#ld-nota-descarte').fill('Nota que no se podrá guardar')
  await dialogo.getByRole('button', { name: /descartar/i }).click()

  // El descarte SÍ persistió; solo la nota falló → aviso puntual, no rollback falso.
  await expect(page.getByText(/no se pudo guardar la nota del descarte/i)).toBeVisible()
  await expect(drawer.getByText('Lead descartado')).toBeVisible()
  await expect(page.getByText(/se actualizó la vista con el estado del servidor/i)).toHaveCount(0)
})

test('convertir en real: pide los datos de la cuenta y valida antes de tocar el servidor', async ({ page }) => {
  await montarBackendReal(page, { leads: [leadReal({ vendedor_id: UID })] })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  const dialogo = await abrirConversionAvance(page, drawer)

  // Un correo inválido se rechaza EN EL CLIENTE: si saliera a la edge, el
  // backend fail-closed daría 500 y no veríamos este mensaje.
  const correo=dialogo.getByLabel('Correo de acceso Avance')
  await correo.fill('no-es-correo')
  await dialogo.getByRole('button', { name: 'Revisar acceso Avance' }).click()
  expect(await correo.evaluate((e:HTMLInputElement)=>e.validity.typeMismatch)).toBe(true)
  await expect(page.getByText(/ahora es cliente/i)).toHaveCount(0)
})

// Gerencia puede cerrar la conversión con una identidad Portal operativa. El
// cliente conserva al analista del lead como responsable comercial.
test('gerencia puede convertir un lead asignado', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  // La ficha le ofrece las dos salidas; se comprueba ANTES de abrir el diálogo
  // porque el modal deja la ficha inerte mientras está encima.
  await expect(drawer.getByRole('button', { name: /Descartar/i })).toBeVisible()
  await abrirConversionAvance(page, drawer)
})

// Desde el 15/09 el supervisor puede iniciar la conversión de su equipo.
// El preflight de servidor valida el ámbito antes de crear cliente o contrato.
test('supervisor sobre el lead de SU analista: puede abrir la conversión', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'supervisor',
    rolPortal: 'analista',
    leads: [leadReal({ vendedor_id: 'vend-1' })], // lead de su analista, no suyo
  })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await expect(drawer.getByRole('button', { name: /Convertir a cliente/i })).toBeVisible()
  await abrirConversionAvance(page, drawer)
})

// 0C elimina el fallback que hacía responsable al conversor: la atribución debe existir
// ANTES del resultado. La UI y la Edge bloquean antes de crear Auth/perfil/correo.
test('supervisor sobre un lead de su bandeja: debe asignarlo antes de convertir', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'supervisor',
    rolPortal: 'analista',
    // "Parkeado": sin analista y en la bandeja del supervisor (espejo de F0).
    leads: [leadReal({ vendedor_id: null, asignado_supervisor_id: UID })],
  })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await expect(drawer.getByRole('button', { name: /Convertir a cliente/i })).toHaveCount(0)
  await expect(drawer.getByText(/Asigna primero el lead a un analista/i)).toBeVisible()
})

test('carga inicial caída: pantalla de error con Reintentar (no pinta el CRM vacío)', async ({ page }) => {
  const estado = await montarBackendReal(page, { leadsSiempreCaido: true })
  await loginReal(page, { esperarWorkspace: false })

  // No se pinta "no hay leads": se muestra el error con reintento.
  await expect(page.getByText(/No pudimos cargar tu información/i)).toBeVisible()
  const reintentar = page.getByRole('button', { name: /reintentar/i })
  await expect(reintentar).toBeVisible()

  // El servidor se recupera y el reintento carga el workspace.
  estado.leadsSiempreCaido = false
  await reintentar.click()
  await expect(page.getByRole('button', { name: 'Ocultar menú', exact: true })).toBeVisible()
})
