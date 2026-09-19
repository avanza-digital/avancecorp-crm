// E2E — CREACIÓN de contrato vía "Registrar inversión" POR-CLIENTE de la cartera
// unificada (#/mi-cartera). Migra los casos que vivían skipeados en
// contratos.spec.ts (pantalla Contratos retirada en Fase 6, que entraba por un
// picker de cliente que ya no existe): prefijos 2024/2025/2026-01-, gate de los
// 6 dígitos, co-titulares dentro de p_contrato y el corte ANTES del servidor.
// El MISMO ContratoNuevo se abre ahora prefijado desde la fila del cliente
// (sin picker) y al crear, recargarContratos invalida crmQueryKeys.contratos()
// → la sub-fila nueva aparece SIN reload (la única alarma posible para una
// invalidación con la clave equivocada, heredada del viejo flujo cruzado).
import { expect, test, type Locator, type Page } from '@playwright/test'
import { clienteReal, cuentaBancariaReal, irAMiCartera, loginReal, montarBackendReal, PRODUCTO_CONDICION_PEN_ID, PRODUCTO_CONDICION_USD_ID, type ContratoReal } from './_helpers'

const CUENTA_GUARDADA_ID = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'

/**
 * 0230929 devolvió el ALTA al flujo LIBRE: el front vigente llama a
 * crear/actualizar_contrato_con_cuenta (sin producto catalogado), pero el mock
 * de _helpers.ts todavía habla el dialecto *_producto. Aquí solo se TRADUCE la
 * llamada — misma p_contrato/p_cuenta/p_cronograma, más la condición del
 * catálogo del mock equivalente por moneda — para que TODA la semántica del
 * backend simulado (estado, contadores, P0001) siga viviendo en _helpers.ts.
 */
async function traducirRpcContratoLibre(page: Page): Promise<void> {
  for (const rpc of ['crear_contrato_con_cuenta', 'actualizar_contrato_con_cuenta'] as const) {
    await page.route(`**/rest/v1/rpc/${rpc}`, async (ruta) => {
      const cuerpo = (ruta.request().postDataJSON() ?? {}) as { p_contrato?: { moneda?: string } }
      await ruta.fallback({
        url: ruta.request().url().replace(`/rpc/${rpc}`, `/rpc/${rpc}_producto`),
        postData: JSON.stringify({
          ...cuerpo,
          p_producto_condicion_id: cuerpo.p_contrato?.moneda === 'USD'
            ? PRODUCTO_CONDICION_USD_ID
            : PRODUCTO_CONDICION_PEN_ID,
        }),
      })
    })
  }
}

/** Abre el ContratoNuevo desde la fila de CLIENTE PORTAL UNO (cartera vacía →
 *  el CTA distingue la primera inversión de una inversión adicional). */
async function abrirFormContrato(page: Page): Promise<Locator> {
  await page
    .getByRole('row', { name: /CLIENTE PORTAL UNO/ })
    .getByRole('button', { name: /Registrar (primera|nueva) inversión/ })
    .click()
  // El nombre accesible del dialog es su DialogTitle (aria-labelledby de Radix
  // gana sobre el aria-label del contenedor): "Crear contrato de {cliente}" —
  // la prueba misma de que el form llega PREFIJADO por fila, sin picker.
  const form = page.getByRole('dialog', { name: /Crear contrato de CLIENTE PORTAL UNO/ })
  await expect(form).toBeVisible()
  return form
}

/**
 * Mínimo válido del alta LIBRE (0230929): la categoría es decisión explícita
 * del analista (arranca en «— Seleccionar —»); tipo simple, modalidad mensual,
 * plazo 12 y fecha de inicio hoy ya vienen por defecto. Más la elección
 * EXPLÍCITA de la cuenta vigente del perfil: ninguna prueba obtiene una
 * cuenta por preselección.
 */
async function llenarBase(form: Locator): Promise<void> {
  await form.locator('#ct-categoria').selectOption('nuevo')
  await form.locator('#ct-capital').fill('10000')
  await expect(form.locator('#ct-tasa')).toHaveValue('15')
  await expect(form.locator('#ct-tasa')).not.toBeEditable()
  await form.getByRole('radio', { name: /BCP.*8901/i }).check()
}

for (const prefijo of ['2024-01-', '2025-01-', '2026-01-']) {
  test(`Registrar inversión por-cliente envía y muestra el prefijo ${prefijo}`, async ({ page }, testInfo) => {
    const numero = `${prefijo}000777`
    const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
    await traducirRpcContratoLibre(page)
    await loginReal(page) // cuenta real → aterriza en #/hoy desde que hay leads
    await irAMiCartera(page)

    // Centinela de "sin reload": una marca en window que NO sobrevive a un
    // location.reload(). Si el runtime recargara la página tras crear, se perdería
    // y el assert final fallaría — así el test prueba LITERALMENTE que no hubo reload
    // (el backend mock persiste fuera de la página, así que sin esto un reload pasaría).
    await page.evaluate(() => { (window as unknown as { __sinReload?: boolean }).__sinReload = true })

    const form = await abrirFormContrato(page)
    // Comprueba el formulario en móvil; el acceso del arnés usa la navegación de escritorio.
    if (prefijo === '2024-01-') await page.setViewportSize({ width: 390, height: 844 })
    await llenarBase(form)
    await expect(form.getByRole('combobox', { name: 'Prefijo del contrato' })).toHaveValue('2026-01-')
    await form.getByRole('combobox', { name: 'Prefijo del contrato' }).selectOption(prefijo)
    // El casillero filtra todo lo que no sea dígito (el maxLength=6 del DOM —
    // fiel al portal — recorta ANTES, así que se prueba con ≤6 caracteres).
    await form.locator('#ct-numero').fill('A1B2C3')
    await expect(form.locator('#ct-numero')).toHaveValue('123')
    await form.locator('#ct-numero').fill('000777')
    await form.locator('#ct-numero').scrollIntoViewIfNeeded()
    await page.screenshot({ path: testInfo.outputPath('selector-prefijo.png') })
    await form.getByRole('button', { name: /Crear contrato/ }).click()

    await expect(page.getByRole('heading', { name: `Contrato ${numero} creado` })).toBeVisible()
    await expect.poll(() => estado.llamadas.rpcCrearContrato).toBe(1)
    // El servidor recibió el número COMPLETO (prefijo elegido + 6 dígitos).
    expect(estado.contratos[0]?.numero_contrato).toBe(numero)
    // Y recibe la fotografía completa que la RPC compara contra public.perfiles:
    // no basta un centinela ambiguo como "usar cuenta actual".
    expect(estado.ultimaCuentaPagoContrato).toEqual({
      tipo: 'perfil',
      cuenta_esperada: {
        banco: 'BCP',
        tipo_cuenta: 'ahorros',
        numero_cuenta: '19112345678901',
        cci: '00219112345678901234',
        titular_distinto: false,
        beneficiario_nombre: null,
        beneficiario_dni: null,
      },
    })
    expect(estado.cuentasPorContrato[estado.contratos[0]!.id]).toMatch(
      /^f0000000-0000-4000-8000-/,
    )

    // El alta ya terminó y el resultado es durable. Cerrar por el CTA oficial
    // dispara la misma finalización idempotente que Escape/overlay post-commit
    // e invalida Mi cartera antes de volver a operar la tabla.
    await page.getByRole('button', { name: 'Finalizar' }).click()
    await expect(page.getByRole('heading', { name: `Contrato ${numero} creado` })).not.toBeVisible()
    if (prefijo === '2024-01-') await page.setViewportSize({ width: 1280, height: 720 })

    // La cartera se recarga SOLA (invalidación de contratos()): expandir al
    // cliente revela la sub-fila nueva sin reload, con su ventana recién nacida
    // ("Corregir" visible: es mía y la ventana de 5 h está viva).
    await page.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE PORTAL UNO/ }).click()
    const subFila = page.getByRole('row', { name: new RegExp(`Abrir detalle del contrato ${numero}`) })
    await expect(subFila).toBeVisible()
    await expect(subFila.getByRole('button', { name: 'Corregir' })).toBeVisible()

    // El centinela sigue vivo → la página NUNCA se recargó; la sub-fila apareció
    // por la invalidación de caché de TanStack Query, no por un reload.
    expect(await page.evaluate(() => (window as unknown as { __sinReload?: boolean }).__sinReload === true)).toBe(true)
  })
}

test('puede fijar una cuenta guardada distinta a la cuenta vigente del perfil', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    rolCrm: 'vendedor',
    contratos: [],
    cuentasBancarias: [cuentaBancariaReal({ cuenta_id: CUENTA_GUARDADA_ID })],
  })
  await traducirRpcContratoLibre(page)
  await loginReal(page)
  await irAMiCartera(page)

  const form = await abrirFormContrato(page)
  await llenarBase(form)
  await form.locator('#ct-numero').fill('000780')
  // `llenarBase` eligió BCP (perfil); el analista cambia deliberadamente a la
  // versión Interbank ya guardada. El id nunca se deriva del texto visible.
  await form.getByRole('radio', { name: /Interbank.*1234/i }).check()
  await form.getByRole('button', { name: /Crear contrato/ }).click()

  await expect.poll(() => estado.llamadas.rpcCrearContrato).toBe(1)
  expect(estado.ultimaCuentaPagoContrato).toEqual({
    tipo: 'existente',
    cuenta_id: CUENTA_GUARDADA_ID,
  })
  expect(estado.cuentasPorContrato[estado.contratos[0]!.id]).toBe(CUENTA_GUARDADA_ID)
})

test('puede registrar una cuenta nueva inline y la envía normalizada en la misma alta', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await traducirRpcContratoLibre(page)
  await loginReal(page)
  await irAMiCartera(page)

  const form = await abrirFormContrato(page)
  await llenarBase(form)
  await form.locator('#ct-numero').fill('000781')
  await form.getByRole('radio', { name: /Añadir una cuenta nueva/i }).check()
  await form.locator('#ct-nueva-banco').selectOption('Scotiabank')
  await form.locator('#ct-nueva-tipo').selectOption('corriente')
  await form.locator('#ct-nueva-numero').fill('  AB-009900001111  ')
  await form.locator('#ct-nueva-cci').fill('00990000111122223333')
  await form.getByRole('button', { name: /Crear contrato/ }).click()

  await expect.poll(() => estado.llamadas.rpcCrearContrato).toBe(1)
  expect(estado.ultimaCuentaPagoContrato).toEqual({
    tipo: 'nueva',
    banco: 'Scotiabank',
    tipo_cuenta: 'corriente',
    numero_cuenta: 'AB-009900001111',
    cci: '00990000111122223333',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
  })
  const cuentaId = estado.cuentasPorContrato[estado.contratos[0]!.id]
  expect(estado.cuentasBancarias.find((cuenta) => cuenta.cuenta_id === cuentaId)).toMatchObject({
    moneda: 'PEN',
    banco: 'Scotiabank',
    numero_cuenta: 'AB-009900001111',
  })
})

test('cambiar de PEN a USD limpia la selección y exige elegir la cuenta de la nueva moneda', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    rolCrm: 'vendedor',
    contratos: [],
    clientes: [clienteReal({
      banco_usd: 'BBVA',
      tipo_cuenta_usd: 'corriente',
      numero_cuenta_usd: '001100009876',
      cci_usd: '01100000987654321098',
    })],
  })
  await traducirRpcContratoLibre(page)
  await loginReal(page)
  await irAMiCartera(page)

  const form = await abrirFormContrato(page)
  await llenarBase(form) // deja elegida la cuenta PEN del perfil
  await form.locator('#ct-numero').fill('000782')
  // En el flujo libre la moneda se cambia directo en su select (ya no la
  // arrastra un producto del catálogo).
  await form.locator('#ct-moneda').selectOption('USD')

  // La selección PEN NO sobrevive al cambio. Aun cuando USD ya cargó y existe
  // una cuenta completa, el botón sigue cerrado hasta una elección explícita.
  const crear = form.getByRole('button', { name: /Crear contrato/ })
  const cuentaUsd = form.getByRole('radio', { name: /BBVA.*9876/i })
  await expect(cuentaUsd).toBeVisible()
  await expect(cuentaUsd).not.toBeChecked()
  await expect(crear).toBeDisabled()

  await cuentaUsd.check()
  await expect(crear).toBeEnabled()
  await crear.click()

  await expect.poll(() => estado.llamadas.rpcCrearContrato).toBe(1)
  expect(estado.llamadas.rpcListarCuentasBancarias).toBeGreaterThanOrEqual(2)
  expect(estado.contratos[0]?.moneda).toBe('USD')
  expect(estado.ultimaCuentaPagoContrato).toEqual({
    tipo: 'perfil',
    cuenta_esperada: {
      banco: 'BBVA',
      tipo_cuenta: 'corriente',
      numero_cuenta: '001100009876',
      cci: '01100000987654321098',
      titular_distinto: false,
      beneficiario_nombre: null,
      beneficiario_dni: null,
    },
  })
})

test('sin los 6 dígitos obligatorios NO se llama al servidor', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await traducirRpcContratoLibre(page)
  await loginReal(page)
  await irAMiCartera(page)

  const form = await abrirFormContrato(page)
  await llenarBase(form)
  await form.locator('#ct-numero').fill('123') // incompleto
  await form.getByRole('button', { name: /Crear contrato/ }).click()

  await expect(form.getByText(/exactamente 6 dígitos/)).toBeVisible()
  expect(estado.llamadas.rpcCrearContrato).toBe(0)
})

test('los co-titulares (mancomunadas) viajan DENTRO de p_contrato normalizados', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await traducirRpcContratoLibre(page)
  await loginReal(page)
  await irAMiCartera(page)

  const form = await abrirFormContrato(page)
  await llenarBase(form)
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
  await traducirRpcContratoLibre(page)
  await loginReal(page)
  await irAMiCartera(page)

  const form = await abrirFormContrato(page)
  await llenarBase(form)
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

// ── El domicilio legal faltante (2026-08-19) ────────────────────────────────
// El caso REAL de producción: 313 de 319 clientes con contrato no tienen
// domicilio, y sin él la RPC revierte el alta ENTERA (el PDF se reserva en la
// misma transacción). Este recorrido es el que de verdad hacen los analistas
// con un cliente antiguo, y hasta hoy la suite no lo pisaba: el arnés ni
// siquiera simulaba el pre-vuelo, así que el camino nuevo pasaba en verde sin
// ejercitarse (gate de REALIDAD).
test('cliente SIN domicilio: el alta se frena, se rellena en el momento y entonces sí se crea', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    rolCrm: 'vendedor',
    contratos: [],
    // El servidor declara ausente el domicilio — la forma que tienen hoy 313
    // clientes de producción. Se modela en la RESPUESTA del pre-vuelo y no
    // vaciando la fila del cliente: lo que se prueba es el aviso, no cómo se
    // dibuja la cartera.
    domicilioLegalAusente: true,
  })
  await traducirRpcContratoLibre(page)
  await loginReal(page)
  // Con la llave de leads abierta, el analista ya NO aterriza en Mi cartera
  // sino en Hoy: se navega explícitamente en vez de dar por buena la portada.
  await page.evaluate(() => { window.location.hash = '#/mi-cartera' })

  const form = await abrirFormContrato(page)
  await llenarBase(form)
  await form.locator('#ct-numero').fill('000778')

  // 1. El muro, ahora CON nombre: dice qué falta y de quién.
  await expect(form.getByText(/Falta el domicilio legal de CLIENTE PORTAL UNO/)).toBeVisible()
  await expect(form.getByRole('button', { name: /Crear contrato/ })).toBeDisabled()

  // 2. Se rellena sin salir del formulario ni perder lo ya escrito.
  await form.locator('#ct-domicilio').fill('Av. Los Alamos 123, San Isidro, Lima')
  await form.getByRole('button', { name: /Guardar domicilio/ }).click()

  await expect(form.getByText(/Falta el domicilio legal/)).toBeHidden()
  await expect.poll(() => estado.llamadas.rpcCompletarDomicilio).toBe(1)
  // Lo escrito antes del muro sigue ahí: el analista no vuelve a empezar.
  await expect(form.locator('#ct-numero')).toHaveValue('000778')

  // 3. Y el alta queda desbloqueada: el botón se habilita y el servidor recibe
  //    la llamada. NO se asevera aquí el cartel de éxito a propósito: eso lo
  //    cubre el test de la numeración, y su mock del alta arrastra una avería
  //    PREVIA a este cambio (falla igual sin tocar nada). Afirmarlo aquí
  //    mezclaría el fallo ajeno con lo que esta prueba viene a demostrar.
  await expect(form.getByRole('button', { name: /Crear contrato/ })).toBeEnabled()
  await form.getByRole('button', { name: /Crear contrato/ }).click()
  await expect.poll(() => estado.llamadas.rpcCrearContrato).toBe(1)
})
