// E2E de la RUTA REAL (sesión autenticada, yo.demo=false) con TODO el HTTP de
// Supabase interceptado — cero escritura en prod (lo no mockeado responde 500).
// Verifica lo que la ruta demo no puede: gate de escritura ABIERTO sin marcas
// "(demo)", persistencia real (POST/PATCH), rollback honesto ante rechazo del
// servidor, descarte que preserva la nota (y su fallo parcial), a quién se le
// ofrece convertir (rol de portal + cartera) y pantalla de error de carga con
// reintento.
import { expect, test } from '@playwright/test'
import { abrirLead, irAPipeline, leadReal, loginReal, montarBackendReal, UID } from './_helpers'

// GATE DE LEADS CERRADO (config.ts FUNCIONES_LEADS_APROBADAS=false, decisión de
// Miguel 2026-07-16): las vistas de leads NO existen para cuentas reales, así
// que toda esta suite (que entra al Pipeline con sesión REAL) no puede correr.
// Reactivar al aprobar leads: borrar este test.skip — la suite queda intacta.
// (La cobertura demo de leads sigue viva en acciones-demo/demo-roles.)
test.skip(true, 'Gate FUNCIONES_LEADS_APROBADAS cerrado: sin vistas de leads para cuentas reales — reactivar al aprobar leads')

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

test('gate abierto: crear lead persiste (POST real) y el toast NO dice "(demo)"', async ({ page }) => {
  const estado = await montarBackendReal(page)
  await loginReal(page)
  await irAPipeline(page)

  await page.getByRole('button', { name: /nuevo lead/i }).click()
  const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
  await expect(modal).toBeVisible()
  await modal.locator('#nl-nombre').fill('LEAD REAL NUEVO')
  await modal.locator('#nl-telefono').fill('987222333')
  await modal.locator('#nl-monto').fill('5000')
  await modal.locator('#nl-origen').selectOption('landing')
  await modal.getByRole('button', { name: /crear lead/i }).click()

  await expect(page.getByText(/Lead creado —/i)).toBeVisible()
  await expect(page.getByText('(demo)')).toHaveCount(0)
  // P-048 revalida inmediatamente antes del INSERT (puede existir además la
  // consulta de blur, según cuánto tarde el llenado del formulario).
  await expect.poll(() => estado.llamadas.rpcDisponibilidadLead).toBeGreaterThanOrEqual(1)
  // La mutación SÍ viajó al servidor (aserción reintentante sobre estado async).
  await expect.poll(() => estado.llamadas.insertLead).toBe(1)
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
  expect(estado.llamadas.insertLead).toBe(0)
})

test('creación rechazada: rollback honesto y el POST sí se intentó', async ({ page }) => {
  const estado = await montarBackendReal(page, { fallarProximoPostLead: true })
  await loginReal(page)
  await irAPipeline(page)

  await page.getByRole('button', { name: /nuevo lead/i }).click()
  const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
  await modal.locator('#nl-nombre').fill('LEAD RECHAZADO')
  await modal.locator('#nl-telefono').fill('987333444')
  await modal.locator('#nl-monto').fill('5000')
  await modal.locator('#nl-origen').selectOption('formulario')
  await modal.getByRole('button', { name: /crear lead/i }).click()

  // El índice único ganó la carrera posterior al precheck: no hay falso éxito.
  await expect(page.getByRole('alert')).toContainText(
    'Este contacto acaba de ser registrado por otro usuario',
  )
  await expect.poll(() => estado.llamadas.insertLead).toBe(1)
})

test('rollback honesto: rechazo del servidor mapea el mensaje, restaura el valor y no miente', async ({ page }) => {
  const estado = await montarBackendReal(page, { fallarProximoPatchTelefono: true })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await drawer.getByRole('button', { name: /editar/i }).click()
  await drawer.locator('#ld-telefono').fill('999111222')
  await drawer.getByRole('button', { name: /^Guardar$/ }).click()

  // aErrorApi mapea 23505/uq_leads_telefono_vivo → mensaje de teléfono duplicado,
  // y persistir lo concatena con "se restauró el estado anterior".
  await expect(
    page.getByText(/Ese teléfono ya pertenece a otro lead abierto de la empresa.*se restauró el estado anterior/i),
  ).toBeVisible()
  await expect.poll(() => estado.llamadas.patchLead).toBe(1)
  // El valor editado se revirtió al del servidor (no quedó el optimista).
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
  await expect(page.getByText(/se restauró el estado anterior/i)).toHaveCount(0)
})

test('convertir en real: pide los datos de la cuenta y valida antes de tocar el servidor', async ({ page }) => {
  await montarBackendReal(page, { leads: [leadReal({ vendedor_id: UID })] })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await drawer.getByRole('button', { name: /Convertir a cliente/i }).click()
  const dialogo = page.getByRole('dialog', { name: 'Convertir a cliente' })
  await expect(dialogo).toBeVisible()

  // Un correo inválido se rechaza EN EL CLIENTE: si saliera a la edge, el
  // backend fail-closed daría 500 y no veríamos este mensaje.
  await dialogo.locator('#cv-correo').fill('no-es-correo')
  await dialogo.getByRole('button', { name: /^Convertir a cliente$/ }).click()
  await expect(dialogo.getByText(/Ingresa un correo válido/i)).toBeVisible()
  await expect(page.getByText(/ahora es cliente/i)).toHaveCount(0)
})

// Regla del negocio (Miguel, 2026-07-16): el alta de clientes y contratos la
// hace el vendedor. Gerencia —Carlos, rol de portal 'directorio'— no la hace.
test('gerencia (rol de portal directorio) NO ve el botón de convertir', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'directorio' })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await expect(drawer.getByRole('button', { name: /Convertir a cliente/i })).toHaveCount(0)
  await expect(drawer.getByText(/El alta del cliente la registra el vendedor/i)).toBeVisible()
  // El resto de su trabajo sigue intacto (descartar, mover, etc.).
  await expect(drawer.getByRole('button', { name: /Descartar/i })).toBeVisible()
})

// El supervisor ES analista en el portal, así que pasa el chequeo de ROL de
// crear_contrato — pero NO el de cartera: la edge deja al cliente a nombre del
// vendedor dueño del lead, y la RPC solo deja contratar al dueño. Si se le
// ofreciera, crearía el cliente + le mandaría el correo de bienvenida a una
// persona real y RECIÉN ahí reventaría, con el lead ya cerrado.
test('supervisor sobre el lead de SU vendedor: no se le ofrece convertir (evita el cliente a medias)', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'supervisor',
    rolPortal: 'analista',
    leads: [leadReal({ vendedor_id: 'vend-1' })], // lead de su vendedor, no suyo
  })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await expect(drawer.getByRole('button', { name: /Convertir a cliente/i })).toHaveCount(0)
  await expect(drawer.getByText(/La conversión la cierra Vendedor/i)).toBeVisible()
  await expect(drawer.getByText(/reasígnate el lead/i)).toBeVisible()
})

// 0C elimina el fallback "asesor = quien convierte": la atribución debe existir
// ANTES del resultado. La UI y la Edge bloquean antes de crear Auth/perfil/correo.
test('supervisor sobre un lead de su bandeja: debe asignarlo antes de convertir', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'supervisor',
    rolPortal: 'analista',
    // "Parkeado": sin vendedor y en la bandeja del supervisor (espejo de F0).
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
  await loginReal(page)

  // No se pinta "no hay leads": se muestra el error con reintento.
  await expect(page.getByText(/No pudimos cargar tu información/i)).toBeVisible()
  const reintentar = page.getByRole('button', { name: /reintentar/i })
  await expect(reintentar).toBeVisible()

  // El servidor se recupera y el reintento carga el workspace.
  estado.leadsSiempreCaido = false
  await reintentar.click()
  await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible()
})
