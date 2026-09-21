// Gestión Diaria (Fase 1) en demo: el módulo existe en el menú para los tres
// roles operativos, abre su registro y no aparece para Directorio. En demo el
// registro sale del espejo puro sobre el ámbito; lo que se comprueba aquí es la
// navegación y la estructura, no cifras.
import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

// Cada rol abre el registro con SU pregunta. Se nombran exactas porque desde
// el layout de dos paneles (20/09/2026) el analista trae dos h2 más —«¿A quién
// llamo ahora?» y «Cola de hoy»—, y un locator por «hoy» ya casa con varios.
const PREGUNTA_DEL_ROL = {
  Analista: '¿Qué hice hoy?',
  Supervisor: '¿Qué está pasando hoy en mi equipo?',
  Gerencia: '¿Qué está pasando hoy?',
} as const

for (const rol of ['Analista', 'Supervisor', 'Gerencia'] as const) {
  test(`${rol} abre Gestión Diaria y ve su registro del día`, async ({ page }) => {
    await entrarDemo(page, rol)
    await page.getByRole('button', { name: 'Gestión Diaria' }).click()
    await expect(page).toHaveURL(/#\/gestion-diaria$/)
    await expect(page.getByRole('heading', { level: 2, name: PREGUNTA_DEL_ROL[rol], exact: true })).toBeVisible()
    if (rol === 'Supervisor') await page.getByRole('button', { name: 'Ver registro del equipo', exact: true }).click()
    await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).toBeVisible()
    await expect(page.getByRole('tab', { name: /Llamadas/ })).toHaveAttribute('aria-selected', 'true')
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
      await expect(page.getByLabel('Día del registro')).toBeVisible()
      await expect(page.getByRole('combobox', { name: 'Equipo' })).toBeVisible()
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
