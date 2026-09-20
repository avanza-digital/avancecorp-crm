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
  await expect(page.getByRole('heading', { level: 2, name: '¿Qué hice hoy?' })).toBeVisible()
  await expect(page.getByRole('combobox', { name: 'Analista' })).toHaveCount(0)

  // «Ahora» responde la pregunta: una persona y su única acción primaria.
  const ahora = page.getByRole('region', { name: 'Ahora' })
  await expect(ahora).toBeVisible()
  await expect(ahora.getByRole('button', { name: /^Registrar resultado de / })).toBeVisible()

  // Los cuatro grupos están como pestañas con su conteo; solo se ve una lista.
  const tabs = page.getByRole('tablist', { name: 'Grupos de la cola' })
  await expect(tabs.getByRole('tab')).toHaveCount(4)
  await expect(tabs.getByRole('tab', { name: /^Sin primer intento/ })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('list', { name: /^Sin primer intento \(\d+\)$/ })).toHaveCount(1)
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
  const fila = page.getByRole('list', { name: /\(\d+\)$/ }).first().getByRole('listitem').first().getByRole('button')
  // El botón concatena nombre y chip sin separador: se lee el span del nombre.
  const nombre = (await fila.locator('span > span').first().textContent() ?? '').trim()
  expect(nombre).not.toBe('')
  await fila.click()
  await expect(fila).toHaveAttribute('aria-current', 'true')
  await expect(ahora).toContainText(nombre)
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
  await ahora.getByRole('button', { name: /^Registrar resultado de / }).click()
  const panel = page.getByRole('dialog', { name: /Cómo salió la llamada/ })
  await expect(panel).toBeVisible({ timeout: 10_000 })
  await expect(panel.getByRole('radio', { name: /No contest/ })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(panel).toHaveCount(0)
})

test('Analista: el marcador y los descartes viven en «Mi actividad»', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  // En la pantalla principal NO están.
  await expect(page.getByRole('tablist', { name: 'Secciones de mi actividad' })).toHaveCount(0)

  await page.getByRole('button', { name: /^Mi actividad/ }).click()
  await expect(page.getByRole('heading', { level: 2, name: 'Mi actividad de hoy' })).toBeVisible()
  const secciones = page.getByRole('tablist', { name: 'Secciones de mi actividad' })
  await expect(secciones.getByRole('tab')).toHaveCount(4)
  await expect(page.getByText('Leads tocados')).toBeVisible()

  await page.getByRole('button', { name: 'Volver a mi día' }).click()
  await expect(page.getByRole('region', { name: 'Ahora' })).toBeVisible()
})

test('Analista: ningún texto de «Mi día» baja de 16 px', async ({ page }) => {
  await entrarDemo(page, 'Analista')
  await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  await expect(page.getByRole('region', { name: 'Ahora' })).toBeVisible()

  // Se mide el tamaño REAL calculado de cada nodo con texto de los dos paneles:
  // es la queja literal de los analistas («muchas letras pequeñas»), así que se
  // comprueba en píxeles, no por la clase que se escribió.
  const chicos = await page.evaluate(() => {
    const raices = [
      document.querySelector('[aria-label="Ahora"]'),
      document.querySelector('[aria-labelledby="cola-titulo"]'),
    ].filter((n): n is Element => n !== null)
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

for (const rol of ['Supervisor', 'Gerencia'] as const) {
  test(`${rol} no ve «Mi día» todavía (llega en la Fase 4)`, async ({ page }) => {
    await entrarDemo(page, rol)
    await page.getByRole('button', { name: 'Gestión Diaria' }).click()
    await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toHaveCount(0)
    await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).toBeVisible()
  })
}
