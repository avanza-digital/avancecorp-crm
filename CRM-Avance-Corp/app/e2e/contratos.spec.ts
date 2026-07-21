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

// Fase 6.1 (2026-07-21): la pantalla Contratos (tabla PLANA de contratos + picker
// de "+ Contrato") se RETIRÓ. La mayor parte de esta suite prueba ese layout
// obsoleto (columnas del portal, headings "Mis contratos"/"Contratos de la
// cartera", paginación POR CONTRATO, y el selector de cliente de "+ Contrato" que
// mi-cartera ya no usa — el alta de contrato ahora sale por-fila del cliente). Su
// cobertura de tabla/búsqueda/reloj/gating vive en `screens/mi-cartera.test.tsx`
// (vitest) y el detalle/corrección de contrato en `contrato-detalle.spec.ts`.
// SALDADO 2026-07-21: la CREACIÓN (numeración 2026-01-XXXXXX + co-titulares en
// p_contrato + "sin 6 dígitos no llama al server" + sub-fila sin reload) vive en
// `contrato-crear.spec.ts`, entrando por el "+ Contrato" por-cliente (sin picker).
test.skip(true, 'Fase 6: Contratos (tabla plana + picker) retirada — tabla en mi-cartera.test.tsx, detalle en contrato-detalle.spec.ts, creación en contrato-crear.spec.ts')

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
      // MÍA pero con la ventana VENCIDA (creada hace semanas) → sin botón Corregir.
      contratoReal({ id: 'ct-vencida', numero_contrato: '2026-01-000222', creado_por: UID, creado_en: '2026-07-01T00:00:00.000Z' }),
      // Viva pero AJENA (la creó otro del equipo) → sin reloj ni botón Corregir.
      contratoReal({ id: 'ct-ajena', numero_contrato: '2026-01-000333', creado_por: 'vend-1', creado_en: new Date().toISOString() }),
    ],
  })
  await loginReal(page)
  await irAContratos(page)

  // Columnas del espejo del portal. Estado y Categoría van FUSIONADAS en una
  // celda (fila densa); el nombre accesible completo de la ventana viaja en el
  // aria-label del th (el texto visible es 'Ventana').
  for (const th of ['N° contrato', 'Cliente', 'Capital', 'Estado', 'Registrado', 'Ventana de corrección', 'Acciones']) {
    await expect(page.getByRole('columnheader', { name: th })).toBeVisible()
  }

  const filaViva = page.getByRole('row', { name: /000111/ })
  await expect(filaViva.getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
  await expect(filaViva.getByRole('button', { name: 'Corregir' })).toBeEnabled()
  // La celda fusionada: badge de estado + badge de categoría en la misma fila.
  await expect(filaViva.getByText('activo')).toBeVisible()
  await expect(filaViva.getByText('Nuevo', { exact: true })).toBeVisible()

  // Propia pero VENCIDA: el reloj dice Bloqueado y el botón ya NI se ofrece
  // (el servidor lo rechazaría con P0001 — no se ofrece lo que fallaría).
  const filaVencida = page.getByRole('row', { name: /000222/ })
  await expect(filaVencida.getByText('Bloqueado')).toBeVisible()
  await expect(filaVencida.getByRole('button', { name: 'Corregir' })).toHaveCount(0)

  // AJENA: sin reloj (la ventana de 5 h es del asesor dueño, no del lector) y
  // sin botón — espejo de la regla POR FILA de la pantalla Clientes.
  const filaAjena = page.getByRole('row', { name: /000333/ })
  await expect(filaAjena.getByText(/Quedan \d+ h \d{2} m/)).toHaveCount(0)
  await expect(filaAjena.getByRole('button', { name: 'Corregir' })).toHaveCount(0)

  // El detalle vive en la FILA clicable (aria-label por fila, sin role=button):
  // SIEMPRE disponible, no depende de la ventana ni del creador.
  await expect(page.getByRole('row', { name: /Abrir detalle del contrato/ })).toHaveCount(3)
})

// Gerencia/directorio leen, no operan: la tabla no les pinta Ventana/Acciones
// (~230 px de ruido menos) ni corre ningún reloj de 15 s por fila.
test('gerencia: sin columnas Ventana/Acciones ni relojes; la fila clicable abre el detalle', async ({ page }) => {
  await montarBackendReal(page, { rolPortal: 'directorio', contratos: [contratoReal()] })
  await loginReal(page)
  // Gerencia aterriza en su panel Hoy (gate parcial 2026-07-16): navega por el nav.
  await page.getByRole('button', { name: 'Contratos' }).click()

  // Título honesto: NO son "sus" contratos, son los de la empresa.
  await expect(page.getByRole('heading', { name: 'Contratos de la cartera' })).toBeVisible()
  await expect(page.getByRole('columnheader', { name: 'Ventana de corrección' })).toHaveCount(0)
  await expect(page.getByRole('columnheader', { name: 'Acciones' })).toHaveCount(0)
  await expect(page.getByText(/Quedan \d+ h \d{2} m/)).toHaveCount(0)
  await expect(page.getByRole('button', { name: '+ Contrato' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Corregir' })).toHaveCount(0)

  // La fila entera es el acceso al detalle (solo lectura, la RLS ya scopea).
  await page.getByRole('row', { name: /Abrir detalle del contrato 2026-01-000123/ }).getByText('2026-01-000123').click()
  await expect(page.getByRole('dialog', { name: /Contrato 2026-01-000123/ })).toBeVisible()
})

test('búsqueda y filtro por estado: contador "X de N", "Sin resultados" honesto y AND', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor',
    contratos: [
      contratoReal({ id: 'ct-1', numero_contrato: '2026-01-000111', cliente_nombre: 'ROSA MERCEDES AGUILAR VENTURA' }),
      contratoReal({ id: 'ct-2', numero_contrato: '2026-01-000222', cliente_nombre: 'JOSÉ ÑAÑEZ GÜISADO', estado: 'renovado' }),
    ],
  })
  await loginReal(page)
  await irAContratos(page)

  // Por cliente, insensible a acentos/mayúsculas (normalizar de la casa).
  await page.getByLabel('Buscar contratos').fill('ñañez')
  await expect(page.getByRole('row', { name: /000222/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /000111/ })).toHaveCount(0)
  await expect(page.getByText('1 de 2')).toBeVisible()

  // Sin coincidencias: estado honesto (no una tabla vacía muda).
  await page.getByLabel('Buscar contratos').fill('no-existe-este-contrato')
  await expect(page.getByText('Sin resultados')).toBeVisible()

  // Limpiar repone todo; el filtro por estado recorta solo (y compone en AND).
  await page.getByLabel('Buscar contratos').fill('')
  await page.getByLabel('Filtrar por estado').selectOption('renovado')
  await expect(page.getByRole('row', { name: /000222/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /000111/ })).toHaveCount(0)
  await expect(page.getByText('1 de 2')).toBeVisible()
  await page.getByLabel('Buscar contratos').fill('rosa')
  await expect(page.getByText('Sin resultados')).toBeVisible()
})

test('paginación: 60 contratos → 2 páginas de 50 con Anterior/Siguiente', async ({ page }) => {
  // Fábrica en bucle: 60 filas con creado_en decreciente (100001 la más nueva)
  // para que el orden desc del servidor sea determinista, y creado_por ajeno
  // (sin reloj) — 60 relojes de 15 s no aportan nada a esta prueba.
  const base = Date.parse('2026-07-01T12:00:00.000Z')
  const cartera = Array.from({ length: 60 }, (_, i) => {
    const n = String(i + 1).padStart(3, '0')
    return contratoReal({
      id: `ct-pag-${n}`,
      numero_contrato: `2026-01-100${n}`,
      creado_por: 'vend-1',
      creado_en: new Date(base - i * 60_000).toISOString(),
    })
  })
  await montarBackendReal(page, { rolCrm: 'vendedor', contratos: cartera })
  await loginReal(page)
  await irAContratos(page)

  await expect(page.getByText('Mis contratos: 60')).toBeVisible()
  await expect(page.getByText('Página 1 de 2 · 60 registros')).toBeVisible()
  await expect(page.getByRole('row', { name: /100001/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /100060/ })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Anterior' })).toBeDisabled()

  await page.getByRole('button', { name: 'Siguiente' }).click()
  await expect(page.getByText('Página 2 de 2 · 60 registros')).toBeVisible()
  await expect(page.getByRole('row', { name: /100060/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /100001/ })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Siguiente' })).toBeDisabled()

  await page.getByRole('button', { name: 'Anterior' }).click()
  await expect(page.getByRole('row', { name: /100001/ })).toBeVisible()
})

test('error de carga: panel con Reintentar (sin tumbar la sesión) que repone la tabla', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', fallarProximaCargaContratos: true })
  await loginReal(page)
  await page.getByRole('button', { name: 'Contratos' }).click()

  // El panel de error de la casa: mensaje es-PE + recordatorio de sesión viva.
  await expect(page.getByText('No se pudieron cargar tus contratos.')).toBeVisible()
  await expect(page.getByText(/tu sesión sigue activa/)).toBeVisible()
  expect(estado.contratos.length).toBe(1) // el mock tiene data; solo falló el GET

  await page.getByRole('button', { name: 'Reintentar' }).click()
  await expect(page.getByRole('row', { name: /000123/ })).toBeVisible()
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


// Flujo CRUZADO Clientes → Contratos sobre la caché compartida de TanStack
// Query: es la ÚNICA alarma posible para una invalidación con la clave
// equivocada, que no falla ruidosa — solo dejaría la tabla de Contratos con su
// versión vieja (fresca < 30 s) al volver sin reload.
test('crear contrato desde la fila de Clientes: la tabla de Contratos lo pinta al volver SIN reload', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await loginReal(page)

  // 1) Cebar la caché de Contratos con la lista VACÍA: si la invalidación no
  //    corriera, esta versión seguiría fresca y la fila nueva NO aparecería.
  await irAContratos(page)
  await expect(page.getByText('Aún no registraste contratos.')).toBeVisible()

  // 2) En Clientes, "+ Contrato" sobre la fila del cliente semilla (el flujo
  //    del asesor: contrato directo desde su cartera, sin pasar por el picker).
  await page.getByRole('button', { name: 'Clientes' }).click()
  await expect(page.getByText('Mis clientes: 1')).toBeVisible()
  await page
    .getByRole('row', { name: /CLIENTE PORTAL UNO/ })
    .getByRole('button', { name: '+ Contrato' })
    .click()
  const form = page.getByRole('dialog', { name: /Crear contrato de CLIENTE PORTAL UNO/ })
  await expect(form).toBeVisible()
  await form.locator('#ct-categoria').selectOption('nuevo')
  await form.locator('#ct-capital').fill('10000')
  await form.locator('#ct-tasa').fill('15')
  await form.locator('#ct-numero').fill('000555')
  await form.getByRole('button', { name: /Crear contrato/ }).click()
  await expect(page.getByText(/Contrato 2026-01-000555 creado/)).toBeVisible()

  // 3) Volver a Contratos por el nav (sin recargar la página): la invalidación
  //    de crmQueryKeys.contratos() obliga a releer y la fila nueva está ahí.
  await irAContratos(page)
  await expect(page.getByRole('row', { name: /000555/ })).toBeVisible()
})

test('demo: contratos poblados, detalle por fila clicable con cronograma fixture y SIN pegarle a Supabase', async ({ page }) => {
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

  // Reloj: A (−2 h) vivo → Corregir habilitado; B (−3 d) vencido → Bloqueado y
  // el botón ya ni se ofrece (regla nueva: solo lo propio Y vivo).
  await expect(filaViva.getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
  await expect(filaViva.getByRole('button', { name: 'Corregir' })).toBeEnabled()
  const filaVencida = page.getByRole('row', { name: /2026-01-000902/ })
  await expect(filaVencida.getByText('Bloqueado')).toBeVisible()
  await expect(filaVencida.getByRole('button', { name: 'Corregir' })).toHaveCount(0)

  // Detalle del contrato A por la FILA clicable (click en la celda del N°, no
  // en el botón Corregir): cronograma PRECARGADO (3 de 12 cuotas pagadas).
  await filaViva.getByText('2026-01-000901').click()
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
