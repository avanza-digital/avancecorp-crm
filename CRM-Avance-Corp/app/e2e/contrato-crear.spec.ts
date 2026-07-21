// E2E — CREACIÓN de contrato vía el "+ Contrato" POR-CLIENTE de la cartera
// unificada (#/mi-cartera). Migra los casos que vivían skipeados en
// contratos.spec.ts (pantalla Contratos retirada en Fase 6, que entraba por un
// picker de cliente que ya no existe): numeración 2026-01-XXXXXX, gate de los
// 6 dígitos, co-titulares dentro de p_contrato y el corte ANTES del servidor.
// El MISMO ContratoNuevo se abre ahora prefijado desde la fila del cliente
// (sin picker) y al crear, recargarContratos invalida crmQueryKeys.contratos()
// → la sub-fila nueva aparece SIN reload (la única alarma posible para una
// invalidación con la clave equivocada, heredada del viejo flujo cruzado).
import { expect, test, type Locator, type Page } from '@playwright/test'
import { loginReal, montarBackendReal, type ContratoReal } from './_helpers'

/** Abre el ContratoNuevo desde la fila de CLIENTE PORTAL UNO (cartera vacía →
 *  el CTA dice "+ Primer contrato"; con contratos previos, "+ Contrato"). */
async function abrirFormContrato(page: Page): Promise<Locator> {
  await page
    .getByRole('row', { name: /CLIENTE PORTAL UNO/ })
    .getByRole('button', { name: /\+ (Primer contrato|Contrato)/ })
    .click()
  // El nombre accesible del dialog es su DialogTitle (aria-labelledby de Radix
  // gana sobre el aria-label del contenedor): "Crear contrato de {cliente}" —
  // la prueba misma de que el form llega PREFIJADO por fila, sin picker.
  const form = page.getByRole('dialog', { name: /Crear contrato de CLIENTE PORTAL UNO/ })
  await expect(form).toBeVisible()
  return form
}

/** Mínimo válido del alta (categoría manual obligatoria + capital + tasa). */
async function llenarBase(form: Locator): Promise<void> {
  await form.locator('#ct-categoria').selectOption('nuevo')
  await form.locator('#ct-capital').fill('10000')
  await form.locator('#ct-tasa').fill('15')
}

test('+ Contrato por-cliente crea con la numeración nueva: el POST lleva numero_contrato 2026-01-XXXXXX', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await loginReal(page) // cuenta real → aterriza en #/mi-cartera

  const form = await abrirFormContrato(page)
  await llenarBase(form)
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

  // La cartera se recarga SOLA (invalidación de contratos()): expandir al
  // cliente revela la sub-fila nueva sin reload, con su ventana recién nacida
  // ("Corregir" visible: es mía y la ventana de 5 h está viva).
  await page.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE PORTAL UNO/ }).click()
  const subFila = page.getByRole('row', { name: /Abrir detalle del contrato 2026-01-000777/ })
  await expect(subFila).toBeVisible()
  await expect(subFila.getByRole('button', { name: 'Corregir' })).toBeVisible()
})

test('sin los 6 dígitos obligatorios NO se llama al servidor', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await loginReal(page)

  const form = await abrirFormContrato(page)
  await llenarBase(form)
  await form.locator('#ct-numero').fill('123') // incompleto
  await form.getByRole('button', { name: /Crear contrato/ }).click()

  await expect(form.getByText(/exactamente 6 dígitos/)).toBeVisible()
  expect(estado.llamadas.rpcCrearContrato).toBe(0)
})

test('los co-titulares (mancomunadas) viajan DENTRO de p_contrato normalizados', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
  await loginReal(page)

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
  await loginReal(page)

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
