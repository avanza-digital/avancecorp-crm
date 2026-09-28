// Gestión Diaria · «Mi día» en demo con el diseño del 27/09/2026: franja de 4
// cifras, «Ahora» con aire de celular y una tarjeta con pestañas —«Cola de hoy»
// (filtros en pastilla, «Todo» primero), «Mi actividad» y «Mi seguimiento»—.
// Se comprueba lo que el analista necesita en cinco segundos: a quién llamar,
// su cola con el conteo de cada grupo, que el tiempo se diga en palabras y
// nunca con la sigla «SLA», y que la letra respete la escala del diseño.
import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

test('Analista: «Mi día» abre con la franja, «Ahora» y su cola con «Todo»', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria$/)

  await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toBeVisible()
  await expect(page.getByRole('group', { name: 'Tu día en cifras' }).getByRole('term')).toHaveText(['Llamadas', 'Contestaron', 'Contacto', 'Citas agendadas'])
  // El registro crudo vive en «Mi actividad», sin filtro de analista.
  await expect(page.getByRole('tablist', { name: 'Qué ver' }).getByRole('tab')).toHaveText([/^Cola de hoy/, 'Mi actividad', /^Mi seguimiento/])
  await expect(page.getByRole('combobox', { name: 'Analista' })).toHaveCount(0)

  // «Ahora» responde la pregunta: una persona y su única acción primaria.
  const ahora = page.getByRole('region', { name: 'Ahora' })
  await expect(ahora).toBeVisible()
  await expect(ahora.getByRole('button', { name: /^Más acciones para / })).toBeVisible()
  await expect(ahora.getByRole('link', { name: /Llamar a/ })
    .or(ahora.getByRole('button', { name: /Copiar el número de/ }))).toBeVisible()

  // «Todo» y los cuatro grupos, con su conteo; solo se ve una lista.
  const tabs = page.getByRole('tablist', { name: 'Grupos de la cola' })
  await expect(tabs.getByRole('tab')).toHaveCount(5)
  await expect(tabs.getByRole('tab', { name: /^Todo/ })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('list', { name: /^Todo \(\d+(–\d+)? de \d+\)$/ })).toHaveCount(1)
})

test('Analista: el tiempo se dice en palabras, sin la sigla SLA', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await expect(page.getByRole('region', { name: 'Ahora' })).toBeVisible()
  await expect(page.getByText(/^(Quedan |Se pasó hace |Sin conversación hace )/).first()).toBeVisible()
  await expect(page.getByText(/\bSLA\b/)).toHaveCount(0)
})

test('Analista: la fila elegida y «Ahora» son la misma persona, sin salir de «Todo»', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const ahora = page.getByRole('region', { name: 'Ahora' })
  await expect(ahora).toBeVisible()

  // Se elige la ÚLTIMA fila: así cambia de verdad quién está en «Ahora».
  const fila = page.getByRole('list', { name: /^Todo \(/ }).getByRole('listitem').last().getByRole('button')
  // El botón concatena iniciales, nombre y chip: se lee el span del nombre.
  const nombre = (await fila.locator('span > span').first().textContent() ?? '').trim()
  expect(nombre).not.toBe('')
  await fila.click()
  await expect(fila).toHaveAttribute('aria-current', 'true')
  await expect(ahora).toContainText(nombre)
  await expect(ahora.getByRole('button', { name: `Abrir la ficha de ${nombre}`, exact: true })).toBeFocused()
  await expect(page.getByRole('tablist', { name: 'Grupos de la cola' }).getByRole('tab', { name: /^Todo/ })).toHaveAttribute('aria-selected', 'true')
})

test('Analista: cambiar de grupo cambia a quién propone «Ahora»', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const ahora = page.getByRole('region', { name: 'Ahora' })
  await expect(ahora).toBeVisible()

  const tabs = page.getByRole('tablist', { name: 'Grupos de la cola' }).getByRole('tab')
  // Solo los GRUPOS (se salta «Todo», que es la cola entera).
  const conGente: number[] = []
  for (let i = 1; i < await tabs.count(); i += 1) {
    const n = Number.parseInt((await tabs.nth(i).textContent() ?? '').match(/(\d+)\s*$/)?.[1] ?? '0', 10)
    if (n > 0) conGente.push(i)
  }
  expect(conGente.length, 'el demo debe traer al menos dos grupos con gente').toBeGreaterThan(1)

  const primero = (await ahora.textContent() ?? '')
  await tabs.nth(conGente[1] ?? 1).click()
  await expect(tabs.nth(conGente[1] ?? 1)).toHaveAttribute('aria-selected', 'true')
  await expect(ahora).not.toHaveText(primero)
})

test('Analista: el resultado se abre DENTRO de «Ahora», sin ventana encima', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const ahora = page.getByRole('region', { name: 'Ahora' })
  await ahora.getByRole('button', { name: /^Más acciones para / }).click()
  const registrar = page.getByRole('menuitem', { name: 'Registrar resultado' })
  await expect(registrar).toBeInViewport({ ratio: 1 })
  await expect(page.getByRole('menuitem', { name: 'Ver la ficha completa' })).toBeInViewport({ ratio: 1 })
  expect(await registrar.evaluate((el) => Number.parseFloat(getComputedStyle(el).fontSize))).toBeGreaterThanOrEqual(16)
  await page.keyboard.press('Tab')
  await expect(page.getByRole('menu')).toHaveCount(0)
  expect(await page.evaluate(() => document.activeElement !== document.body)).toBe(true)
  await ahora.getByRole('button', { name: /^Más acciones para / }).click()
  await registrar.click()
  const panel = ahora.getByRole('group', { name: /Qué pasó con la llamada/ })
  await expect(panel).toBeVisible({ timeout: 10_000 })
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(panel.getByRole('radio')).toHaveCount(7)
  // El foco entra al formulario y los atajos 1–7 funcionan dentro de la tarjeta.
  await expect(panel.getByRole('radio', { name: /No contest/ })).toBeFocused()
  await page.keyboard.press('2')
  await expect(panel.getByRole('radio', { name: /volver a llamar/ })).toBeChecked()
  // Escape = cerrar sin registrar: vuelve la tarjeta normal de la misma persona.
  await page.keyboard.press('Escape')
  await expect(panel).toHaveCount(0)
  await expect(ahora.getByRole('button', { name: /^Más acciones para / })).toBeVisible()
})

test('Analista: «Mi actividad» y «Mi seguimiento» son pestañas; «Ahora» sigue a la vista', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const vistas = page.getByRole('tablist', { name: 'Qué ver' })
  await vistas.getByRole('tab', { name: /^Mi actividad/ }).click()
  await expect(page.getByRole('heading', { name: 'Llamadas por hora' })).toBeVisible()
  await expect(page.getByRole('heading', { name: '¿Qué hice hoy?' })).toBeVisible()
  await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).toBeVisible()
  await expect(page.getByRole('region', { name: 'Ahora' })).toBeVisible()
  await vistas.getByRole('tab', { name: /^Mi seguimiento/ }).click()
  await expect(page.getByRole('heading', { name: /^Mi seguimiento/ })).toBeVisible()
  await vistas.getByRole('tab', { name: /^Cola de hoy/ }).click()
  await expect(page.getByRole('tablist', { name: 'Grupos de la cola' })).toBeVisible()
})

test('Analista: la letra de «Mi día» respeta la escala del diseño (nada por debajo de 11 px)', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await expect(page.getByRole('region', { name: 'Ahora' })).toBeVisible()

  // Miguel, 27/09/2026: «hay demasiada letra, no está respetando el diseño».
  // Manda la escala del diseño (etiquetas de 11 px, cuerpo de 12–14 px); el
  // piso de 16 px del 20/09 queda sustituido. Se mide el tamaño REAL calculado
  // de cada nodo con texto de los dos paneles, en píxeles.
  const chicos = await page.evaluate(() => {
    const raices = Array.from(document.querySelectorAll('section[aria-labelledby]'))
      .filter((s) => ['Ahora', 'Cola de hoy'].includes(
        (document.getElementById(s.getAttribute('aria-labelledby') ?? '')?.textContent ?? '').trim()))
    const fallos: string[] = []
    for (const raiz of raices) {
      for (const el of raiz.querySelectorAll<HTMLElement>('*')) {
        const propio = Array.from(el.childNodes)
          .filter((n) => n.nodeType === Node.TEXT_NODE)
          .map((n) => (n.textContent ?? '').trim())
          .join('')
        if (propio === '') continue
        const px = Number.parseFloat(getComputedStyle(el).fontSize)
        if (px < 11) fallos.push(`${px}px — «${propio.slice(0, 40)}»`)
      }
    }
    return { fallos, raices: raices.length }
  })
  expect(chicos.raices, 'deben medirse los dos paneles').toBe(2)
  expect(chicos.fallos, `Textos por debajo de 11 px:\n${chicos.fallos.join('\n')}`).toEqual([])
})

test('Analista: dos columnas sin bajar a 1440×900 y móvil sin desbordamiento', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const ahora = page.getByRole('region', { name: 'Ahora' })
  const tarjeta = page.getByRole('region', { name: 'Tu cola y tu actividad' })
  await expect(ahora).toBeVisible()
  const a = (await ahora.boundingBox())!
  const c = (await tarjeta.boundingBox())!
  const titulo = (await page.getByRole('heading', { name: '¿A quién llamo ahora?' }).boundingBox())!
  const franja = (await page.getByRole('group', { name: 'Tu día en cifras' }).boundingBox())!
  // El teléfono ocupa TODO el alto a la izquierda (Miguel, 27/09): arranca a la
  // altura del título y acaba donde acaba la cola; título, cifras y cola a la derecha.
  for (const derecha of [c, titulo, franja]) expect(derecha.x).toBeGreaterThanOrEqual(a.x + a.width)
  expect(Math.abs(a.y - titulo.y)).toBeLessThan(12)
  expect(Math.abs((a.y + a.height) - (c.y + c.height))).toBeLessThan(2)
  // La pantalla cabe entera: el área de contenido no se desplaza.
  expect(await page.evaluate(() => {
    const area = document.querySelector('[data-vista-scroll]')
    return area instanceof HTMLElement && area.scrollHeight <= area.clientHeight + 1
  })).toBe(true)
  await page.screenshot({ path: info.outputPath('analista-integracion-escritorio.png'), fullPage: true })
  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByRole('heading', { name: '¿A quién llamo ahora?' }).scrollIntoViewIfNeeded()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  const tabs = page.getByRole('tablist', { name: 'Grupos de la cola' })
  expect(await tabs.evaluate((raiz) => Array.from(raiz.querySelectorAll('button')).every((boton) =>
    boton.scrollWidth <= boton.clientWidth && getComputedStyle(boton).whiteSpace === 'nowrap'))).toBe(true)
  await tabs.getByRole('tab').first().focus()
  await page.keyboard.press('End')
  await expect(tabs.getByRole('tab').last()).toBeFocused()
  await expect(tabs.getByRole('tab').last()).toHaveAttribute('aria-selected', 'true')
  await page.keyboard.press('Home')
  await page.screenshot({ path: info.outputPath('analista-integracion-movil.png'), fullPage: true })
})

for (const rol of ['Supervisor', 'Gerencia'] as const) {
  test(`${rol} conserva su vista y registro, sin la cola personal del analista`, async ({ page }) => {
    await entrarDemo(page, rol)
    await page.getByRole('button', { name: 'Gestión Diaria' }).click()
    await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toHaveCount(0)
    if (rol === 'Supervisor') await page.getByRole('button', { name: 'Registro del equipo', exact: true }).click()
    if (rol === 'Gerencia') await page.getByRole('button', { name: 'Registro general', exact: true }).click()
    await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).toBeVisible()
  })
}
