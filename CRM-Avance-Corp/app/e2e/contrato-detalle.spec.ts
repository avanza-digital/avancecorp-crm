// E2E de "Ver detalle" + "Corregir contrato" (ruta REAL: sesión autenticada con
// TODO el backend Supabase interceptado, fail-closed — cero contacto con prod).
// Cubre lo que fija el contrato de construcción:
//  1) El detalle pinta términos + co-titulares + cronograma con una cuota pagada
//     (fecha y monto del pago real) y una pendiente, con totales.
//  2) Corregir PRECARGA notas y co-titulares, y el RPC del mock recibe AMBOS en
//     p_contrato (las 2 trampas del servidor: clave ausente = borrado/no tocar).
//  3) El error del servidor (P0001, ventana vencida) se muestra TAL CUAL.
// Depende de la pantalla Contratos: fila CLICABLE por contrato (abre el
// detalle) + botón "Corregir" solo en lo propio y vivo, paneles en <Dialog>.
import { expect, test, type Page } from '@playwright/test'
import { contratoReal, irAMiCartera, loginReal, montarBackendReal, PRODUCTO_CONDICION_PEN_ID, PRODUCTO_CONDICION_USD_ID, verTodaLaCartera } from './_helpers'

// Fase 6.1 (2026-07-21): la entrada migró a la cartera unificada (#/mi-cartera,
// la vista por defecto). Los contratos cuelgan del cliente como sub-filas; se
// expande CLIENTE PORTAL UNO para revelarlos. Los asserts del detalle/corrección
// (fila clicable "Abrir detalle…", <Dialog>, RPC) NO cambian.

const CONTRATO_ID = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'

// Una cuota PAGADA (con fecha_pago_real y monto_pagado), una PENDIENTE y el
// retorno del capital — el trío que exige el dibujo fino del cronograma.
const CUOTAS = [
  { id: 'q1', numero_cuota: 1, fecha_programada: '2026-08-01', monto_programado: 125, estado: 'pagado', tipo: 'cuota', fecha_pago_real: '2026-08-02', monto_pagado: 125 },
  { id: 'q2', numero_cuota: 2, fecha_programada: '2026-09-01', monto_programado: 125, estado: 'pendiente', tipo: 'cuota', fecha_pago_real: null, monto_pagado: null },
  { id: 'q3', numero_cuota: 3, fecha_programada: '2027-07-08', monto_programado: 10000, estado: 'pendiente', tipo: 'retorno', fecha_pago_real: null, monto_pagado: null },
]

const TITULARES = [
  { nombre_completo: 'MARIA CO TITULAR', tipo_documento: 'CE', documento: '001234567', orden: 1 },
]

/**
 * 0230929 devolvió la corrección al flujo LIBRE: el front vigente llama a
 * actualizar_contrato_con_cuenta (sin producto catalogado), pero el mock de
 * _helpers.ts todavía habla el dialecto *_producto. Aquí solo se TRADUCE la
 * llamada — mismos p_id/p_contrato/p_cronograma, más la condición del catálogo
 * del mock equivalente por moneda — para que TODA la semántica del backend
 * simulado (estado, contadores, el P0001 de la ventana) siga en _helpers.ts.
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

/** La cuenta real cae en #/mi-cartera (cartera unificada). Los contratos cuelgan
 *  del cliente: se expande CLIENTE PORTAL UNO para revelar la sub-fila del contrato. */
async function irAContratos(page: Page): Promise<void> {
  // La cartera arranca en el mes en curso y el contrato del fixture es de otro:
  // sin esto, su fila no está en la lista.
  await verTodaLaCartera(page)
  await page.getByRole('button', { name: /Expandir los contratos de CLIENTE PORTAL UNO/ }).click()
  await expect(page.getByText('2026-01-000123').first()).toBeVisible()
}

test('detalle: términos + co-titulares + cronograma (pagada y pendiente) + totales', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', 
    contratos: [contratoReal({ notas_internas: 'Cliente pidió doble constancia' })],
    cuotas: { [CONTRATO_ID]: CUOTAS },
    titulares: { [CONTRATO_ID]: TITULARES },
  })
  await loginReal(page)
  await irAMiCartera(page)
  await irAContratos(page)

  // El detalle vive en la FILA clicable (ya no hay botón "Ver detalle"); se
  // clickea la celda del N° para no rozar el botón Corregir de la fila.
  await page.getByRole('row', { name: /Abrir detalle del contrato 2026-01-000123/ }).getByText('2026-01-000123').click()
  const dialogo = page.getByRole('dialog', { name: /Contrato 2026-01-000123/ })
  await expect(dialogo).toBeVisible()

  // Términos del contrato (número ya está en el título del dialog).
  await expect(dialogo.getByText('CLIENTE PORTAL UNO')).toBeVisible()
  await expect(dialogo.getByText('S/ 10,000').first()).toBeVisible() // capital
  await expect(dialogo.getByText('15%')).toBeVisible() // tasa anual
  await expect(dialogo.getByText('Simple')).toBeVisible()
  await expect(dialogo.getByText('Mensual')).toBeVisible()
  await expect(dialogo.getByText('activo')).toBeVisible() // estado
  await expect(dialogo.getByText('Nuevo', { exact: true })).toBeVisible() // categoría
  await expect(dialogo.getByText('Cliente pidió doble constancia')).toBeVisible() // notas

  // Co-titulares (cuentas mancomunadas) con la sigla del documento.
  await expect(dialogo.getByText('MARIA CO TITULAR')).toBeVisible()
  await expect(dialogo.getByText(/CE 001234567/)).toBeVisible()

  // Cronograma completo con el dibujo fino del portal: cuota/retorno etiquetados…
  await expect(dialogo.getByText('Cuota #1')).toBeVisible()
  await expect(dialogo.getByText('Cuota #2')).toBeVisible()
  // exact: el título de la sección también dice "retorno del capital" (en minúscula).
  await expect(dialogo.getByText('RETORNO DEL CAPITAL', { exact: true })).toBeVisible()
  // …pagadas vs pendientes…
  await expect(dialogo.getByText('pagado', { exact: true })).toBeVisible()
  await expect(dialogo.getByText('pendiente', { exact: true }).first()).toBeVisible()
  // …el pago REAL (fecha · monto) solo en la cuota pagada…
  await expect(dialogo.getByText(/· S\/ 125/)).toBeVisible()
  // …y los totales (1 de 2 de interés; por pagar = 125 + 10,000 del retorno).
  await expect(dialogo.getByText(/1 de 2/)).toBeVisible()
  await expect(dialogo.getByText(/Por pagar/)).toBeVisible()
  await expect(dialogo.getByText('S/ 10,125')).toBeVisible()

  // Nada salió a producción de verdad (toda la sesión corre sobre el mock).
  await dialogo.getByRole('button', { name: /cerrar/i }).click()
  await expect(dialogo).toBeHidden()
})

test('corregir: precarga notas y co-titulares, y el RPC recibe AMBOS en p_contrato', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor',
    contratos: [
      // creado_en FRESCO: la ventana de 5 h está viva y el botón Corregir activo.
      contratoReal({ notas_internas: 'Ajustar tasa el lunes', creado_en: new Date().toISOString() }),
    ],
    cuotas: { [CONTRATO_ID]: CUOTAS },
    titulares: { [CONTRATO_ID]: TITULARES },
  })
  await traducirRpcContratoLibre(page)
  await loginReal(page)
  await irAMiCartera(page)
  await irAContratos(page)

  await page.getByRole('button', { name: /corregir/i }).first().click()
  const dialogo = page.getByRole('dialog', { name: /Corregir contrato/ })
  await expect(dialogo).toBeVisible()

  // PRECARGA (las 2 trampas): notas y co-titulares YA en el formulario, y el
  // N° muestra solo los 6 dígitos (el prefijo 2026-01- es fijo).
  await expect(dialogo.locator('#cc-notas')).toHaveValue('Ajustar tasa el lunes')
  await expect(dialogo.getByLabel('Nombre del co-titular 1')).toHaveValue('MARIA CO TITULAR')
  // exact: el aria-label del select "Tipo de documento…" contiene este texto.
  await expect(dialogo.getByLabel('Documento del co-titular 1', { exact: true })).toHaveValue('001234567')
  await expect(dialogo.locator('#cc-numero')).toHaveValue('000123')

  await dialogo.getByRole('button', { name: /guardar corrección/i }).click()

  // Toast honesto del guardado + el RPC viajó una sola vez. La corrección ya
  // reserva una revisión PDF y comunica por separado si el render queda en
  // reintento, por eso no se acopla al texto histórico del cronograma.
  await expect(page.getByText(/Contrato corregido\./)).toBeVisible()
  await expect.poll(() => estado.llamadas.rpcActualizarContrato).toBe(1)
  // El mock APLICA p_contrato al estado: si notas o titulares no viajaran
  // (clave ausente), aquí faltarían — exactamente la trampa que se prueba.
  expect(estado.contratos.find((k) => k.id === CONTRATO_ID)?.notas_internas).toBe('Ajustar tasa el lunes')
  expect(estado.titulares[CONTRATO_ID]).toEqual([
    { nombre_completo: 'MARIA CO TITULAR', tipo_documento: 'CE', documento: '001234567', orden: 1 },
  ])
})

test('ventana vencida en el SERVIDOR: el P0001 de la RPC se muestra tal cual', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor',
    ventanaVencida: true,
    // Viva en el CLIENTE (creado_en fresco): así se prueba que la autoridad es
    // el servidor — el reloj local no basta para proteger la corrección.
    contratos: [contratoReal({ creado_en: new Date().toISOString() })],
    cuotas: { [CONTRATO_ID]: CUOTAS },
    titulares: { [CONTRATO_ID]: [] },
  })
  await traducirRpcContratoLibre(page)
  await loginReal(page)
  await irAMiCartera(page)
  await irAContratos(page)

  await page.getByRole('button', { name: /corregir/i }).first().click()
  const dialogo = page.getByRole('dialog', { name: /Corregir contrato/ })
  await expect(dialogo).toBeVisible()
  await dialogo.getByRole('button', { name: /guardar corrección/i }).click()

  // El mensaje del RAISE llega TAL CUAL (aErrorApi conserva el texto en P0001)…
  await expect(
    dialogo.getByText('Solo puedes corregir un contrato dentro de las 5 horas de creado'),
  ).toBeVisible()
  await expect.poll(() => estado.llamadas.rpcActualizarContrato).toBe(1)
  // …y no se mintió éxito.
  await expect(page.getByText(/Contrato corregido\./)).toHaveCount(0)
})
