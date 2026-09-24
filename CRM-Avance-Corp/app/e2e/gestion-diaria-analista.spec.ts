// Gestión Diaria · «Mi día» en demo, layout de DOS PANELES (20/09/2026).
// Se comprueba lo que el analista necesita en cinco segundos: a quién llamar
// («Ahora»), su cola en pestañas con el conteo de cada grupo, que el tiempo se
// diga en palabras y nunca con la sigla «SLA», y que la letra no baje de 16 px.
// El marcador y los descartes ya no ocupan la pantalla: viven en «Mi actividad».
import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

test('Analista: «Mi día» abre con «Ahora» y su cola en pestañas', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await expect(page).toHaveURL(/#\/gestion-diaria$/)

  await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toBeVisible()
  // El registro crudo de la Fase 1 sigue debajo, sin filtro de analista.
  await expect(page.getByRole('heading', { name: /¿Qué hice hoy\?/ })).toBeVisible()
  await expect(page.getByRole('combobox', { name: 'Analista' })).toHaveCount(0)

  // «Ahora» responde la pregunta: una persona y su única acción primaria.
  const ahora = page.getByRole('region', { name: 'Ahora' })
  await expect(ahora).toBeVisible()
  await expect(ahora.getByRole('button', { name: /^Más acciones para / })).toBeVisible()
  await expect(ahora.getByRole('link', { name: /Llamar a/ })
    .or(ahora.getByRole('button', { name: /Copiar el número de/ }))).toBeVisible()

  // Los cuatro grupos están como pestañas con su conteo; solo se ve una lista.
  const tabs = page.getByRole('tablist', { name: 'Grupos de la cola' })
  await expect(tabs.getByRole('tab')).toHaveCount(4)
  await expect(tabs.getByRole('tab', { name: /^Sin primer intento/ })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('list', { name: /^Sin primer intento \(\d+(–\d+)? de \d+\)$/ })).toHaveCount(1)
})

test('Analista: el tiempo se dice en palabras, sin la sigla SLA', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await expect(page.getByRole('region', { name: 'Ahora' })).toBeVisible()
  await expect(page.getByText(/^(Quedan |Se pasó hace |Sin conversación hace )/).first()).toBeVisible()
  await expect(page.getByText(/\bSLA\b/)).toHaveCount(0)
})

test('Analista: la fila elegida y «Ahora» son la misma persona', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const ahora = page.getByRole('region', { name: 'Ahora' })
  await expect(ahora).toBeVisible()

  // Elegir la fila la marca y la sube a «Ahora». (Que elegir OTRA cambie el
  // panel se prueba en unitario: el demo trae una sola fila por grupo.)
  const fila = page.getByRole('list', { name: /\(\d+(–\d+)? de \d+\)$/ }).first().getByRole('listitem').first().getByRole('button')
  // El botón concatena nombre y chip sin separador: se lee el span del nombre.
  const nombre = (await fila.locator('span > span').first().textContent() ?? '').trim()
  expect(nombre).not.toBe('')
  await fila.click()
  await expect(fila).toHaveAttribute('aria-current', 'true')
  await expect(ahora).toContainText(nombre)
  await expect(ahora.getByRole('button', { name: `Abrir la ficha de ${nombre}`, exact: true })).toBeFocused()
})

test('Analista: cambiar de pestaña cambia a quién propone «Ahora»', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const ahora = page.getByRole('region', { name: 'Ahora' })
  await expect(ahora).toBeVisible()

  const tabs = page.getByRole('tablist', { name: 'Grupos de la cola' }).getByRole('tab')
  const conGente: number[] = []
  for (let i = 0; i < await tabs.count(); i += 1) {
    const n = Number.parseInt((await tabs.nth(i).textContent() ?? '').match(/(\d+)\s*$/)?.[1] ?? '0', 10)
    if (n > 0) conGente.push(i)
  }
  expect(conGente.length, 'el demo debe traer al menos dos grupos con gente').toBeGreaterThan(1)

  const primero = (await ahora.textContent() ?? '')
  await tabs.nth(conGente[1] ?? 0).click()
  await expect(tabs.nth(conGente[1] ?? 0)).toHaveAttribute('aria-selected', 'true')
  await expect(ahora).not.toHaveText(primero)
})

test('Analista: el panel de resultado se abre desde «Ahora»', async ({ page }) => {
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
  const panel = page.getByRole('dialog', { name: /Cómo salió la llamada/ })
  await expect(panel).toBeVisible({ timeout: 10_000 })
  await expect(panel.getByRole('radio', { name: /No contest/ })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(panel).toHaveCount(0)
})

test('Analista: detalle y registro plegados; la cola sigue visible al abrirlos', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const actividad = page.getByRole('heading', { name: /Mi actividad de hoy/ }).locator('xpath=ancestor::details')
  const registro = page.getByRole('heading', { name: /¿Qué hice hoy\?/ }).locator('xpath=ancestor::details')
  await expect(actividad).not.toHaveAttribute('open')
  await expect(registro).not.toHaveAttribute('open')
  await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).not.toBeVisible()
  await page.getByRole('button', { name: /^Mi actividad/ }).click()
  await expect(actividad).toHaveAttribute('open')
  await expect(actividad.locator('summary')).toBeFocused()
  await expect(page.getByRole('region', { name: 'Ahora' })).toBeVisible()
  await expect(actividad.getByRole('list', { name: 'Marcador de hoy' })).toBeVisible()
  await registro.locator('summary').click()
  await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).toBeVisible()
})

test('Analista: ningún texto de «Mi día» baja de 16 px', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await expect(page.getByRole('region', { name: 'Ahora' })).toBeVisible()

  // Se mide el tamaño REAL calculado de cada nodo con texto de los dos paneles:
  // es la queja literal de los analistas («muchas letras pequeñas»), así que se
  // comprueba en píxeles, no por la clase que se escribió.
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
        if (px < 16) fallos.push(`${px}px — «${propio.slice(0, 40)}»`)
      }
    }
    return fallos
  })
  expect(chicos, `Textos por debajo de 16 px:\n${chicos.join('\n')}`).toEqual([])
})

test('Analista: integración en dos columnas y móvil sin desbordamiento', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  const ahora = page.getByRole('region', { name: 'Ahora' })
  const cola = page.getByRole('region', { name: 'Cola de hoy' })
  await expect(ahora).toBeVisible()
  const a = (await ahora.boundingBox())!
  const c = (await cola.boundingBox())!
  expect(c.x).toBeGreaterThanOrEqual(a.x + a.width)
  expect(Math.abs(c.y - a.y)).toBeLessThan(2)
  await page.screenshot({ path: info.outputPath('analista-integracion-escritorio.png'), fullPage: true })
  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByRole('heading', { name: '¿A quién llamo ahora?' }).scrollIntoViewIfNeeded()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  const tabs = cola.getByRole('tablist')
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
    await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).toBeVisible()
  })
}
