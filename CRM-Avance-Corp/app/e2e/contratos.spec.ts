// E2E de "Mis contratos" (ruta REAL: sesión autenticada + TODO el HTTP de
// Supabase interceptado fail-closed — cero escritura en prod). Cubre lo que
// pidió el traspaso del panel del analista:
//  - la tabla pinta las columnas del portal y el reloj de 5 h POR FILA
//    distingue viva ("Quedan X h") de vencida ("Bloqueado"),
//  - "Corregir" solo en el contrato PROPIO (creado_por = yo) y con ventana viva,
//  - "+ Contrato" crea con la numeración NUEVA: el POST a crear_contrato lleva
//    numero_contrato '2026-01-XXXXXX' (nunca vacío → adiós 'AC-2026-XXXX'),
//  - sin los 6 dígitos NO se llama al servidor,
//  - los co-titulares (mancomunadas) viajan DENTRO de p_contrato.
import { expect, test, type Page } from '@playwright/test'
import { clienteReal, bloquearSupabase, contratoReal, entrarDemo, loginReal, montarBackendReal, UID, type ContratoReal } from './_helpers'

/** Entra a la pantalla Contratos (con el gate de leads cerrado, la cuenta real
 * arranca en Clientes; el nav lateral sí ofrece Contratos). */
async function irAContratos(page: Page): Promise<void> {
  await page.getByRole('button', { name: 'Contratos' }).click()
  await expect(page.getByRole('heading', { name: 'Mis contratos' })).toBeVisible()
}

/** Abre "+ Contrato", elige el cliente semilla y llega al formulario. */
async function abrirFormNuevo(page: Page) {
  await page.getByRole('button', { name: '+ Contrato' }).click()
  const selector = page.getByRole('dialog', { name: 'Nuevo contrato' })
  await expect(selector).toBeVisible()
  await selector.getByLabel('Cliente').selectOption({ label: 'CLIENTE PORTAL UNO' })
  await selector.getByRole('button', { name: 'Continuar' }).click()
  const form = page.getByRole('dialog', { name: /Crear contrato de CLIENTE PORTAL UNO/ })
  await expect(form).toBeVisible()
  return form
}

// La regla de cartera del servidor también rige el PICKER: un supervisor ve en
// la vista a los clientes de su equipo, pero crear_contrato solo le acepta los
// SUYOS — el selector no debe ofrecer lo que el servidor rechazaría
// (hallazgo de revisión 2026-07-16: el bug sobrevivía por esta puerta).
test('picker de "+ Contrato": el supervisor solo ve su cartera PROPIA, no la del equipo', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'supervisor',
    clientes: [
      clienteReal({ id: 'cli-mio', nombre_completo: 'CLIENTE PROPIO SUP', dni: '40000001', asesor_perfil_id: UID, creado_por: UID }),
      clienteReal({ id: 'cli-equipo', nombre_completo: 'CLIENTE DEL EQUIPO', dni: '40000002', asesor_perfil_id: 'vend-1', creado_por: 'vend-1' }),
    ],
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Contratos' }).click()
  await page.getByRole('button', { name: '+ Contrato' }).click()

  const selector = page.getByRole('dialog', { name: 'Nuevo contrato' })
  await expect(selector.getByRole('option', { name: 'CLIENTE PROPIO SUP' })).toBeAttached()
  await expect(selector.getByRole('option', { name: 'CLIENTE DEL EQUIPO' })).toHaveCount(0)
})

test('la tabla pinta como el portal y el reloj de 5 h distingue viva de vencida; Corregir solo en lo propio y vivo', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor',
    contratos: [
      // Viva y MÍA → Corregir habilitado.
      contratoReal({ id: 'ct-viva', numero_contrato: '2026-01-000111', creado_por: UID, creado_en: new Date().toISOString() }),
      // MÍA pero con la ventana VENCIDA (creada hace semanas) → Corregir bloqueado.
      contratoReal({ id: 'ct-vencida', numero_contrato: '2026-01-000222', creado_por: UID, creado_en: '2026-07-01T00:00:00.000Z' }),
      // Viva pero AJENA (la creó otro del equipo) → sin botón Corregir.
      contratoReal({ id: 'ct-ajena', numero_contrato: '2026-01-000333', creado_por: 'vend-1', creado_en: new Date().toISOString() }),
    ],
  })
  await loginReal(page)
  await irAContratos(page)

  // Columnas del espejo del portal (7 de datos + Acciones).
  for (const th of ['N° contrato', 'Cliente', 'Capital', 'Estado', 'Categoría', 'Registrado', 'Ventana de corrección', 'Acciones']) {
    await expect(page.getByRole('columnheader', { name: th })).toBeVisible()
  }

  const filaViva = page.getByRole('row', { name: /000111/ })
  await expect(filaViva.getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
  await expect(filaViva.getByRole('button', { name: 'Corregir' })).toBeEnabled()

  const filaVencida = page.getByRole('row', { name: /000222/ })
  await expect(filaVencida.getByText('Bloqueado')).toBeVisible()
  await expect(filaVencida.getByRole('button', { name: 'Corregir' })).toBeDisabled()

  const filaAjena = page.getByRole('row', { name: /000333/ })
  await expect(filaAjena.getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
  await expect(filaAjena.getByRole('button', { name: 'Corregir' })).toHaveCount(0)

  // "Ver detalle" SIEMPRE disponible (no depende de la ventana ni del creador).
  await expect(page.getByRole('button', { name: 'Ver detalle' })).toHaveCount(3)
})

test('cartera sin contratos: el vacío del portal ("Aún no registraste contratos.")', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await loginReal(page)
  await irAContratos(page)

  await expect(page.getByText('Aún no registraste contratos.')).toBeVisible()
})

test('+ Contrato crea con la numeración nueva: el POST lleva numero_contrato 2026-01-XXXXXX', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await loginReal(page)
  await irAContratos(page)

  const form = await abrirFormNuevo(page)
  await form.locator('#ct-categoria').selectOption('nuevo')
  await form.locator('#ct-capital').fill('10000')
  await form.locator('#ct-tasa').fill('15')
  // El casillero filtra todo lo que no sea dígito (el maxLength=6 del DOM —
  // fiel al portal — recorta ANTES, así que se prueba con ≤6 caracteres).
  await form.locator('#ct-numero').fill('A1B2C3')
  await expect(form.locator('#ct-numero')).toHaveValue('123')
  await form.locator('#ct-numero').fill('000777')
  await form.getByRole('button', { name: /Crear contrato/ }).click()

  await expect(page.getByText(/Contrato 2026-01-000777 creado/)).toBeVisible()
  await expect.poll(() => estado.llamadas.rpcCrearContrato).toBe(1)
  // El servidor recibió el número COMPLETO (prefijo fijo + 6 dígitos), no vacío.
  expect(estado.contratos[0]?.numero_contrato).toBe('2026-01-000777')
  // La tabla se recarga y pinta el contrato nuevo con su ventana recién nacida.
  await expect(page.getByRole('row', { name: /000777/ }).getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
})

test('sin los 6 dígitos obligatorios NO se llama al servidor', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await loginReal(page)
  await irAContratos(page)

  const form = await abrirFormNuevo(page)
  await form.locator('#ct-categoria').selectOption('nuevo')
  await form.locator('#ct-capital').fill('10000')
  await form.locator('#ct-tasa').fill('15')
  await form.locator('#ct-numero').fill('123') // incompleto
  await form.getByRole('button', { name: /Crear contrato/ }).click()

  await expect(form.getByText(/exactamente 6 dígitos/)).toBeVisible()
  expect(estado.llamadas.rpcCrearContrato).toBe(0)
})

test('los co-titulares (mancomunadas) viajan DENTRO de p_contrato normalizados', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await loginReal(page)
  await irAContratos(page)

  const form = await abrirFormNuevo(page)
  await form.locator('#ct-categoria').selectOption('nuevo')
  await form.locator('#ct-capital').fill('10000')
  await form.locator('#ct-tasa').fill('15')
  await form.locator('#ct-numero').fill('000778')

  await form.getByRole('button', { name: /Agregar co-titular/ }).click()
  // exact: 'Documento' a secas — sin exact matchearía también 'Tipo de documento'.
  await form.getByLabel('Documento', { exact: true }).fill('87654321')
  // Minúsculas y espacios dobles a propósito: el núcleo normaliza como la BD.
  await form.getByLabel('Nombre completo del co-titular').fill('maría  julia pérez')
  await form.getByRole('button', { name: /Crear contrato/ }).click()

  await expect.poll(() => estado.llamadas.rpcCrearContrato).toBe(1)
  const creado = estado.contratos[0] as ContratoReal & { titulares?: unknown }
  expect(creado?.numero_contrato).toBe('2026-01-000778')
  // Lo que llegó al servidor dentro de p_contrato, ya normalizado (sin `orden`:
  // lo deriva la RPC del índice).
  expect(creado?.titulares).toEqual([
    { nombre_completo: 'MARÍA JULIA PÉREZ', tipo_documento: 'DNI', documento: '87654321' },
  ])
})

test('co-titular a medio llenar o duplicado corta el guardado ANTES del servidor', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await loginReal(page)
  await irAContratos(page)

  const form = await abrirFormNuevo(page)
  await form.locator('#ct-categoria').selectOption('nuevo')
  await form.locator('#ct-capital').fill('10000')
  await form.locator('#ct-tasa').fill('15')
  await form.locator('#ct-numero').fill('000779')

  // A medio llenar: documento sin nombre → error con la posición de la fila.
  await form.getByRole('button', { name: /Agregar co-titular/ }).click()
  await form.getByLabel('Documento', { exact: true }).fill('87654321')
  await form.getByRole('button', { name: /Crear contrato/ }).click()
  await expect(form.getByText(/Co-titular 1: Escribe el nombre completo/)).toBeVisible()

  // Duplicado: dos filas con el MISMO documento → error, nada sale al servidor.
  await form.getByLabel('Nombre completo del co-titular').fill('ANA UNO')
  await form.getByRole('button', { name: /Agregar co-titular/ }).click()
  await form.getByLabel('Documento', { exact: true }).nth(1).fill('87654321')
  await form.getByLabel('Nombre completo del co-titular').nth(1).fill('ANA DOS')
  await form.getByRole('button', { name: /Crear contrato/ }).click()
  await expect(form.getByText(/está repetido/)).toBeVisible()

  expect(estado.llamadas.rpcCrearContrato).toBe(0)
})


test('demo: contratos poblados, "Ver detalle" con cronograma fixture y SIN pegarle a Supabase', async ({ page }) => {
  // Fail-closed: en demo NINGÚN request debe salir al host de Supabase (ni la
  // lista ni el detalle — que en demo va PRECARGADO, sin fetch).
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Vendedor')
  await page.getByRole('button', { name: 'Contratos' }).click()
  await expect(page.getByRole('heading', { name: 'Mis contratos' })).toBeVisible()

  // Los 3 contratos fixture con su numeración 2026-01-0009xx.
  const filaViva = page.getByRole('row', { name: /2026-01-000901/ })
  await expect(filaViva).toBeVisible()
  await expect(page.getByRole('row', { name: /2026-01-000902/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /2026-01-000903/ })).toBeVisible()

  // Reloj: A (−2 h) vivo → Corregir habilitado; B (−3 d) vencido → Bloqueado.
  await expect(filaViva.getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
  await expect(filaViva.getByRole('button', { name: 'Corregir' })).toBeEnabled()
  await expect(page.getByRole('row', { name: /2026-01-000902/ }).getByText('Bloqueado')).toBeVisible()

  // "Ver detalle" del contrato A: cronograma PRECARGADO (3 de 12 cuotas pagadas).
  await filaViva.getByRole('button', { name: 'Ver detalle' }).click()
  const detalle = page.getByRole('dialog', { name: /Contrato 2026-01-000901/ })
  await expect(detalle).toBeVisible()
  await expect(detalle.getByText(/3 de 12/)).toBeVisible()
  await expect(detalle.getByText('RETORNO DEL CAPITAL', { exact: true })).toBeVisible()
  await detalle.getByRole('button', { name: /cerrar/i }).click()

  // Acción demo: "+ Contrato" solo emite el toast "(demo)".
  await page.getByRole('button', { name: '+ Contrato' }).click()
  await expect(page.getByText(/Nuevo contrato: disponible solo con tu cuenta real \(demo\)/i)).toBeVisible()

  expect(requestsSupabase()).toBe(0)
})
