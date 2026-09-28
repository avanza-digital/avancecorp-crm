// Gestión Diaria (Fase 1) en demo: el módulo existe en el menú para los tres
// roles operativos, abre su registro y no aparece para Directorio. En demo el
// registro sale del espejo puro sobre el ámbito; lo que se comprueba aquí es la
// navegación y la estructura, no cifras.
import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

// Cada rol abre el registro con SU pregunta. Se nombran exactas porque el
// analista trae más encabezados con «hoy» y un locator suelto casaría con varios.
// G0 (27/09/2026): la gerencia demo abre el tablero «Toda la operación», como
// la real, y llega al registro por «Registro general».
const PREGUNTA_DEL_ROL = {
  Analista: '¿Qué hice hoy?',
  Supervisor: 'Mi equipo hoy',
  Gerencia: 'Toda la operación',
} as const

for (const rol of ['Analista', 'Supervisor', 'Gerencia'] as const) {
  test(`${rol} abre Gestión Diaria y ve su registro del día`, async ({ page }) => {
    await entrarDemo(page, rol)
    await page.getByRole('button', { name: 'Gestión Diaria' }).click()
    await expect(page).toHaveURL(/#\/gestion-diaria$/)
    if (rol === 'Analista') {
      await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toBeVisible()
      // Diseño del 27/09/2026: el registro vive en la pestaña «Mi actividad».
      await page.getByRole('tablist', { name: 'Qué ver' }).getByRole('tab', { name: /^Mi actividad/ }).click()
      await expect(page.getByRole('heading', { name: '¿Qué hice hoy?' })).toBeVisible()
    } else {
      await expect(page.getByRole('heading', { level: 2, name: PREGUNTA_DEL_ROL[rol], exact: true })).toBeVisible()
    }
    if (rol === 'Supervisor') await page.getByRole('button', { name: 'Registro del equipo', exact: true }).click()
    if (rol === 'Gerencia') await page.getByRole('button', { name: 'Registro general', exact: true }).click()
    await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).toBeVisible()
    await expect(page.getByRole('tab', { name: rol === 'Analista' ? 'Llamadas' : 'Todo', exact: true })).toHaveAttribute('aria-selected', 'true')
    await page.getByRole('tab', { name: 'Todo' }).click()
    await expect(page.getByRole('tab', { name: 'Todo' })).toHaveAttribute('aria-selected', 'true')
    // El demo tiene gestiones de HOY: la lista tiene filas con hora, chip y detalle.
    const lista = page.getByRole('list', { name: 'Registro de actividad' })
    await expect(lista.getByRole('listitem').first()).toBeVisible()
    await expect(lista.getByText(/Contestó|No contestó/).first()).toBeVisible()
    // El panel se nombra por su pestaña: «Mi día» aporta sus propios tabpanel
    // (los grupos de la cola), así que un `getByRole('tabpanel')` pelado casa
    // con varios en la pantalla del analista.
    await expect(page.getByRole('tabpanel', { name: 'Todo' })).toBeVisible()
    if (rol === 'Gerencia') {
      await expect(page.getByLabel('Día de la operación')).toBeVisible()
      await expect(page.getByRole('combobox', { name: 'Equipo', exact: true })).toBeVisible()
      await expect(page.getByRole('button', { name: /Exportar CSV/ })).toBeVisible()
    } else {
      await expect(page.getByRole('button', { name: /Exportar CSV/ })).toHaveCount(0)
    }
    // El selector de analista es un <select> nativo (combobox): «Analista» a secas
    // también es el rótulo del rol en la barra, por eso se busca por rol.
    if (rol === 'Analista') await expect(page.getByRole('combobox', { name: 'Analista' })).toHaveCount(0)
    else await expect(page.getByRole('combobox', { name: 'Analista' })).toBeVisible()
  })
}

test('Directorio no tiene Gestión Diaria en el menú', async ({ page }) => {
  await entrarDemo(page, 'Directorio')
  await expect(page.getByRole('button', { name: 'Gestión Diaria' })).toHaveCount(0)
})
