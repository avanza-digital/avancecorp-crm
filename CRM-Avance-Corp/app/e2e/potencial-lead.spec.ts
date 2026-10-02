// Potencial del lead (Frío · Tibio · Estrella) de punta a punta, con el backend
// simulado: la bandera apagada (el estado de producción hoy), marcar desde la
// ficha y ver el chip en la tabla, quién puede marcar, el rechazo del servidor,
// que el texto se lea sobre su color, la fila «Por potencial» que filtra Leads,
// el Pipeline y el modo demo.
import { expect, test, type Locator, type Page } from '@playwright/test'
import {
  abrirLead, bloquearSupabase, diaLimaReal, entrarDemo, irACartera, irAPipeline, leadReal, loginReal, montarBackendReal, UID,
} from './_helpers'

const LEAD = leadReal({
  id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', nombre_completo: 'GLORIA NAVARRO IBARRA', vendedor_id: UID, etapa: 'contactado',
})

const LEAD_FRIO = leadReal({
  id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', nombre_completo: 'MARTIN CHAVEZ LEON', vendedor_id: UID, etapa: 'contactado',
})

const LEAD_SIN = leadReal({
  id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', nombre_completo: 'LUCIA PAREDES MENDOZA', vendedor_id: UID, etapa: 'nuevo',
})

const porPotencial = (page: Page) => page.getByRole('group', { name: 'Distribución por potencial' })
const filasVisibles = (page: Page) => page.getByRole('row', { name: /^Abrir ficha de/ })

const filaDe = (page: Page, lead = LEAD) => page.getByRole('row', { name: `Abrir ficha de ${lead.nombre_completo}` })

/**
 * Contraste WCAG entre el texto y el fondo que el navegador pinta de verdad.
 * Con un degradado (Estrella) se mide contra CADA parada y manda la peor.
 */
async function contrasteDe(el: Locator): Promise<number> {
  const { tinta, fondo, imagen } = await el.evaluate((nodo) => {
    const estilo = getComputedStyle(nodo)
    return { tinta: estilo.color, fondo: estilo.backgroundColor, imagen: estilo.backgroundImage }
  })
  const luz = (color: string) => {
    // Un color translúcido no se mide así: mejor fallar que dar un número inventado.
    expect(color, 'color sólido').toMatch(/^rgb\(/)
    const [r = 0, g = 0, b = 0] = (color.match(/[\d.]+/g) ?? []).map((v) => {
      const c = Number(v) / 255
      return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
    })
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }
  const fondos = imagen.includes('gradient') ? imagen.match(/rgb\([^)]*\)/g) ?? [] : [fondo]
  expect(fondos.length, 'fondo medible').toBeGreaterThan(0)
  const deLaTinta = luz(tinta)
  return Math.min(...fondos.map((color) => {
    const delFondo = luz(color)
    return (Math.max(deLaTinta, delFondo) + 0.05) / (Math.min(deLaTinta, delFondo) + 0.05)
  }))
}

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
  // Tampoco hay fila «Por potencial»: el resumen no trae conteos.
  await expect(porPotencial(page)).toHaveCount(0)

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

test('el texto se lee sobre su color: Frío y Tibio pasan de 4,5 a 1 en el chip y en el botón elegido', async ({ page }) => {
  // Frío y Tibio son colores sólidos con texto encima. Un color cambiado sin su
  // tinta (naranja con letra blanca: 2,8 a 1) pasaría todos los demás tests.
  await montarBackendReal(page, {
    rolCrm: 'vendedor', leads: [LEAD, LEAD_FRIO], potencialHabilitado: true,
    potencial: { [LEAD.id]: 'tibio', [LEAD_FRIO.id]: 'frio' },
  })
  await loginReal(page)
  await irACartera(page)
  await expect.poll(() => contrasteDe(filaDe(page).getByTitle('Potencial: Tibio'))).toBeGreaterThanOrEqual(4.5)
  await expect.poll(() => contrasteDe(filaDe(page, LEAD_FRIO).getByTitle('Potencial: Frío'))).toBeGreaterThanOrEqual(4.5)

  const ficha = await abrirDesdeLaTabla(page)
  const grupo = ficha.getByRole('group', { name: 'Potencial del lead' })
  const tibio = grupo.getByRole('button', { name: 'Tibio' })
  await expect(tibio).toHaveAttribute('aria-pressed', 'true')
  await expect.poll(() => contrasteDe(tibio)).toBeGreaterThanOrEqual(4.5)
  // El botón de Frío, al elegirlo (el color hace una transición corta: por eso `poll`).
  const frio = grupo.getByRole('button', { name: 'Frío' })
  await frio.click()
  await expect(frio).toHaveAttribute('aria-pressed', 'true')
  await expect.poll(() => contrasteDe(frio)).toBeGreaterThanOrEqual(4.5)
})

test('Leads: la fila «Por potencial» filtra la tabla, los totales y no cambia sus números', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor', leads: [LEAD, LEAD_FRIO, LEAD_SIN], potencialHabilitado: true,
    potencial: { [LEAD.id]: 'tibio', [LEAD_FRIO.id]: 'frio' },
  })
  await loginReal(page)
  await irACartera(page)
  const fila = porPotencial(page)
  await expect(fila.getByRole('button')).toHaveText(['Frío 1', 'Tibio 1', 'Estrella 0', 'Sin marcar 1'])
  await expect(filasVisibles(page)).toHaveCount(3)
  // Una cifra en cero no se abre.
  await expect(fila.getByRole('button', { name: 'Estrella 0' })).toHaveAttribute('aria-disabled', 'true')

  // Tibio: el filtro viaja al servidor y la tabla, el total y las etapas se quedan con ese lead.
  const pedido = page.waitForRequest((r) => r.url().includes('/rpc/cartera_filtrada_fn') && r.postDataJSON()?.p_potencial === 'tibio')
  await fila.getByRole('button', { name: 'Tibio 1' }).click()
  await pedido
  await expect(fila.getByRole('button', { name: 'Tibio 1' })).toHaveAttribute('aria-pressed', 'true')
  // La pastilla pulsada no se desmonta mientras llega la lista: conserva el foco.
  await expect(fila.getByRole('button', { name: 'Tibio 1' })).toBeFocused()
  await expect(filasVisibles(page)).toHaveCount(1)
  await expect(filaDe(page)).toBeVisible()
  await expect(page.locator('[data-kpi="Total leads"]')).toContainText('1')
  // Los cuatro números son los de antes: se cuentan sin este filtro.
  await expect(fila.getByRole('button')).toHaveText(['Frío 1', 'Tibio 1', 'Estrella 0', 'Sin marcar 1'])
  await expect.poll(() => contrasteDe(fila.getByRole('button', { name: 'Tibio 1' }))).toBeGreaterThanOrEqual(4.5)

  // Un nivel a la vez: «Sin marcar» sustituye a Tibio.
  await fila.getByRole('button', { name: 'Sin marcar 1' }).click()
  await expect(fila.getByRole('button', { name: 'Tibio 1' })).toHaveAttribute('aria-pressed', 'false')
  await expect(filasVisibles(page)).toHaveCount(1)
  await expect(filaDe(page, LEAD_SIN)).toBeVisible()
  await expect.poll(() => contrasteDe(fila.getByRole('button', { name: 'Sin marcar 1' }))).toBeGreaterThanOrEqual(4.5)

  // Volver a tocarla quita el filtro; «Limpiar filtros» también lo suelta.
  await fila.getByRole('button', { name: 'Sin marcar 1' }).click()
  await expect(filasVisibles(page)).toHaveCount(3)
  await fila.getByRole('button', { name: 'Frío 1' }).click()
  await expect(filasVisibles(page)).toHaveCount(1)
  await expect.poll(() => contrasteDe(fila.getByRole('button', { name: 'Frío 1' }))).toBeGreaterThanOrEqual(4.5)
  await page.getByRole('button', { name: 'Limpiar filtros' }).click()
  await expect(filasVisibles(page)).toHaveCount(3)
  await expect(fila.getByRole('button', { name: 'Frío 1' })).toHaveAttribute('aria-pressed', 'false')
})

test('Leads: marcar un lead mueve los números de «Por potencial» sin recargar', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor', leads: [LEAD, LEAD_SIN], potencialHabilitado: true, potencial: { [LEAD.id]: 'tibio' },
  })
  await loginReal(page)
  await irACartera(page)
  const fila = porPotencial(page)
  await expect(fila.getByRole('button')).toHaveText(['Frío 0', 'Tibio 1', 'Estrella 0', 'Sin marcar 1'])

  await filaDe(page, LEAD_SIN).click()
  const ficha = page.getByRole('dialog', { name: LEAD_SIN.nombre_completo })
  await ficha.getByRole('group', { name: 'Potencial del lead' }).getByRole('button', { name: 'Estrella' }).click()
  await expect(ficha.getByTitle('Potencial: Estrella')).toBeVisible()
  await ficha.getByRole('button', { name: 'Cerrar ficha' }).click()
  await expect(fila.getByRole('button')).toHaveText(['Frío 0', 'Tibio 1', 'Estrella 1', 'Sin marcar 0'])
})

test('Leads: gerencia no marca, pero sí filtra por potencial', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia', leads: [LEAD, LEAD_FRIO], potencialHabilitado: true, potencial: { [LEAD.id]: 'estrella' },
  })
  await loginReal(page)
  await irACartera(page)
  const fila = porPotencial(page)
  await expect(fila.getByRole('button')).toHaveText(['Frío 0', 'Tibio 0', 'Estrella 1', 'Sin marcar 1'])
  await fila.getByRole('button', { name: 'Estrella 1' }).click()
  await expect(filasVisibles(page)).toHaveCount(1)
  await expect(filaDe(page).getByTitle('Potencial: Estrella')).toBeVisible()
  // El dorado es un degradado: la tinta se lee sobre sus tres paradas, en la pastilla y en la etiqueta.
  await expect.poll(() => contrasteDe(fila.getByRole('button', { name: 'Estrella 1' }))).toBeGreaterThanOrEqual(4.5)
  await expect.poll(() => contrasteDe(filaDe(page).getByTitle('Potencial: Estrella'))).toBeGreaterThanOrEqual(4.5)
  // Una pastilla con cifra en cero sigue leyéndose (gris oscuro sobre blanco, sin opacidad).
  await expect.poll(() => contrasteDe(fila.getByRole('button', { name: 'Frío 0' }))).toBeGreaterThanOrEqual(4.5)
})

test('Leads: si el servidor apaga el potencial con el filtro puesto, el filtro se suelta solo, se avisa y el foco no se pierde', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    rolCrm: 'vendedor', leads: [LEAD, LEAD_FRIO], potencialHabilitado: true, potencial: { [LEAD.id]: 'tibio' },
  })
  await loginReal(page)
  await irACartera(page)
  const fila = porPotencial(page)
  await expect(fila.getByRole('button')).toHaveText(['Frío 0', 'Tibio 1', 'Estrella 0', 'Sin marcar 1'])
  // El interruptor de emergencia: la bandera se apaga en el servidor con la pantalla abierta.
  estado.potencialHabilitado = false
  await fila.getByRole('button', { name: 'Tibio 1' }).click()
  await expect(page.getByText('El filtro por potencial ya no está disponible. Se quitó de la lista.')).toBeVisible()
  // La lista vuelve entera, la fila «Por potencial» se retira y el foco pasa a «Total leads».
  await expect(porPotencial(page)).toHaveCount(0)
  await expect(filasVisibles(page)).toHaveCount(2)
  await expect(page.locator('[data-kpi="Total leads"]')).toBeFocused()
  // No es una avería de la lista: sin el aviso de «no se pudo cargar».
  await expect(page.getByText('No se pudo cargar la lista de leads.')).toHaveCount(0)
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

test('demo: la fila «Por potencial» filtra Leads con las marcas sembradas, sin red', async ({ page }) => {
  const intentos = await bloquearSupabase(page)
  await entrarDemo(page, 'Analista')
  await irACartera(page)
  const fila = porPotencial(page)
  await expect(fila.getByRole('button')).toHaveCount(4)
  const antes = await fila.getByRole('button').allTextContents()
  const estrella = fila.getByRole('button', { name: /^Estrella \d+$/ })
  const cuantas = Number((await estrella.textContent())?.match(/\d+/)?.[0] ?? '0')
  expect(cuantas).toBeGreaterThan(0)
  await estrella.click()
  await expect(estrella).toHaveAttribute('aria-pressed', 'true')
  await expect(filasVisibles(page)).toHaveCount(cuantas)
  for (const fila_ of await filasVisibles(page).all()) await expect(fila_.getByTitle('Potencial: Estrella')).toBeVisible()
  // Los números no cambian al elegir un nivel.
  expect(await fila.getByRole('button').allTextContents()).toEqual(antes)
  expect(intentos()).toBe(0)
})
