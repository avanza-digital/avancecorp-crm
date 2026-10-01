// Potencial del lead (Frío · Tibio · Estrella) de punta a punta, con el backend
// simulado: la bandera apagada (el estado de producción hoy), marcar desde la
// ficha y ver el chip en la tabla, quién puede marcar, el rechazo del servidor,
// el Pipeline y el modo demo.
import { expect, test, type Page } from '@playwright/test'
import {
  abrirLead, bloquearSupabase, diaLimaReal, entrarDemo, irACartera, irAPipeline, leadReal, loginReal, montarBackendReal, UID,
} from './_helpers'

const LEAD = leadReal({
  id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', nombre_completo: 'GLORIA NAVARRO IBARRA', vendedor_id: UID, etapa: 'contactado',
})

const filaDe = (page: Page) => page.getByRole('row', { name: `Abrir ficha de ${LEAD.nombre_completo}` })

/** Abre la ficha desde la tabla de Leads (la fila entera es el control). */
async function abrirDesdeLaTabla(page: Page) {
  await filaDe(page).click()
  const ficha = page.getByRole('dialog', { name: LEAD.nombre_completo })
  await expect(ficha).toBeVisible()
  return ficha
}

test('con el potencial apagado (producción hoy) ni la tabla ni la ficha lo muestran', async ({ page }) => {
  // Aunque el servidor tuviera una marca guardada, con la bandera apagada no viaja.
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', leads: [LEAD], potencial: { [LEAD.id]: 'estrella' } })
  await loginReal(page)
  await irACartera(page)
  await expect(filaDe(page)).toBeVisible()
  await expect(page.getByTitle(/^Potencial:/)).toHaveCount(0)
  await expect(filaDe(page)).not.toHaveAttribute('data-potencial')

  const ficha = await abrirDesdeLaTabla(page)
  await expect(ficha.getByRole('heading', { name: 'Datos' })).toBeVisible()
  await expect(ficha.getByRole('region', { name: 'Potencial' })).toHaveCount(0)
  await expect(ficha.getByTitle(/^Potencial:/)).toHaveCount(0)
  expect(estado.marcasPotencial).toEqual([])
})

test('el analista marca Estrella desde la ficha y el chip aparece en la tabla', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor', leads: [LEAD], potencialHabilitado: true })
  await loginReal(page)
  await irACartera(page)
  await expect(filaDe(page)).toBeVisible()
  // Encendido y sin marcas: la tabla sigue limpia.
  await expect(page.getByTitle(/^Potencial:/)).toHaveCount(0)

  const ficha = await abrirDesdeLaTabla(page)
  const seccion = ficha.getByRole('region', { name: 'Potencial' })
  await expect(seccion.getByText('Sin marcar. La cambian el analista del lead y su supervisor.')).toBeVisible()
  const grupo = seccion.getByRole('group', { name: 'Potencial del lead' })
  await expect(grupo.getByRole('button')).toHaveText(['Frío', 'Tibio', 'Estrella'])

  await grupo.getByRole('button', { name: 'Estrella' }).click()
  await expect(grupo.getByRole('button', { name: 'Estrella' })).toHaveAttribute('aria-pressed', 'true')
  await expect.poll(() => estado.marcasPotencial).toEqual([{ lead_id: LEAD.id, nivel: 'estrella' }])
  // La ficha enseña el chip en su cabecera y, cuando el servidor contesta, cuándo
  // bajará la marca (el front no lo calcula: mientras tanto dice «Guardando la marca…»).
  await expect(ficha.getByTitle('Potencial: Estrella')).toBeVisible()
  await expect(seccion.getByText(/^Baja a Tibio el .+ si no se gestiona \(cuentan lunes a sábado\)\.$/)).toBeVisible()
  await expect(grupo.getByRole('button', { name: 'Estrella' })).not.toHaveAttribute('aria-disabled')

  await ficha.getByRole('button', { name: 'Cerrar ficha' }).click()
  await expect(filaDe(page).getByTitle('Potencial: Estrella')).toBeVisible()
  await expect(filaDe(page)).toHaveAttribute('data-potencial', 'estrella')
})

test('a qué nivel baja lo dice el servidor: una Estrella vencida anuncia Frío para mañana', async ({ page }) => {
  // Después de la última pasada de la madrugada, una Estrella con 9 días sin
  // gestión llega con `baja_el` = mañana y `baja_a` = el nivel de ESE día.
  await montarBackendReal(page, {
    rolCrm: 'vendedor', leads: [LEAD], potencialHabilitado: true,
    potencial: { [LEAD.id]: { nivel: 'estrella', dias_sin_gestion: 9, baja_a: 'frio', baja_el: diaLimaReal(1) } },
  })
  await loginReal(page)
  await irACartera(page)
  const ficha = await abrirDesdeLaTabla(page)
  const seccion = ficha.getByRole('region', { name: 'Potencial' })
  await expect(seccion.getByRole('button', { name: 'Estrella' })).toHaveAttribute('aria-pressed', 'true')
  await expect(seccion.getByText('Baja a Frío mañana si no se gestiona.')).toBeVisible()
})

test('gerencia ve la marca pero no la cambia', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    rolCrm: 'gerencia', leads: [LEAD], potencialHabilitado: true, potencial: { [LEAD.id]: 'tibio' },
  })
  await loginReal(page)
  await irACartera(page)
  await expect(filaDe(page).getByTitle('Potencial: Tibio')).toBeVisible()

  const ficha = await abrirDesdeLaTabla(page)
  const seccion = ficha.getByRole('region', { name: 'Potencial' })
  await expect(seccion.getByTitle('Potencial: Tibio')).toBeVisible()
  await expect(seccion.getByRole('button')).toHaveCount(0)
  expect(estado.marcasPotencial).toEqual([])
})

test('si el servidor rechaza la marca, se deshace y se avisa', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    rolCrm: 'vendedor', leads: [LEAD], potencialHabilitado: true,
    fallarProximaMarcaPotencial: { code: '42501', message: 'Solo el analista del lead o su supervisor pueden marcar su potencial' },
  })
  await loginReal(page)
  await irACartera(page)
  const ficha = await abrirDesdeLaTabla(page)
  const grupo = ficha.getByRole('group', { name: 'Potencial del lead' })
  await grupo.getByRole('button', { name: 'Frío' }).click()
  await expect(page.getByText('Solo el analista del lead o su supervisor pueden marcar su potencial.')).toBeVisible()
  await expect(grupo.getByRole('button', { name: 'Frío' })).toHaveAttribute('aria-pressed', 'false')
  await expect(ficha.getByTitle(/^Potencial:/)).toHaveCount(0)
  expect(estado.marcasPotencial).toEqual([])
})

test('el Pipeline pinta el chip y la franja en la tarjeta', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor', leads: [LEAD], potencialHabilitado: true, potencial: { [LEAD.id]: 'estrella' },
  })
  await loginReal(page)
  await irAPipeline(page)
  const tarjeta = page.getByRole('button', { name: /GLORIA NAVARRO IBARRA/ }).first()
  await expect(tarjeta.getByTitle('Potencial: Estrella')).toBeVisible()
  await expect(tarjeta).toHaveAttribute('data-potencial', 'estrella')
  // La tarjeta con marca sigue abriendo su ficha.
  await tarjeta.click()
  await expect(page.getByRole('dialog', { name: LEAD.nombre_completo })).toBeVisible()
})

test('demo: trae marcas sembradas y marcar funciona sin red', async ({ page }) => {
  const intentos = await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  await irAPipeline(page)
  // «GLORIA NAVARRO IBÁÑEZ» viene sembrada como Estrella.
  await expect(page.getByRole('button', { name: /GLORIA NAVARRO IBÁÑEZ/ }).first().getByTitle('Potencial: Estrella')).toBeVisible()

  // «TERESA GONZALES PAZ» no trae marca: se marca desde su ficha.
  const ficha = await abrirLead(page, /TERESA GONZALES PAZ/)
  const grupo = ficha.getByRole('group', { name: 'Potencial del lead' })
  await grupo.getByRole('button', { name: 'Tibio' }).click()
  await expect(grupo.getByRole('button', { name: 'Tibio' })).toHaveAttribute('aria-pressed', 'true')
  await expect(ficha.getByTitle('Potencial: Tibio')).toBeVisible()
  await ficha.getByRole('button', { name: 'Cerrar ficha' }).click()
  await expect(page.getByRole('button', { name: /TERESA GONZALES PAZ/ }).first().getByTitle('Potencial: Tibio')).toBeVisible()
  expect(intentos()).toBe(0)
})
