// Gestión Diaria (Fase 1) en demo: el módulo existe en el menú para los tres
// roles operativos, abre su registro y no aparece para Directorio. En demo el
// registro sale del espejo puro sobre el ámbito; lo que se comprueba aquí es la
// navegación y la estructura, no cifras.
import { expect, test } from '@playwright/test'
import { entrarDemo } from './_helpers'

for (const rol of ['Analista', 'Supervisor', 'Gerencia'] as const) {
  test(`${rol} abre Gestión Diaria y ve su registro del día`, async ({ page }) => {
    await entrarDemo(page, rol)
    await page.getByRole('button', { name: 'Gestión Diaria' }).click()
    await expect(page).toHaveURL(/#\/gestion-diaria$/)
    if (rol === 'Analista') {
      // Desde la Fase 3 el analista abre con «Mi día»; y desde la densidad del
      // 20/09 su propio registro vive PLEGADO —es memoria, no trabajo
      // pendiente—, así que hay que abrirlo para verlo.
      await expect(page.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toBeVisible()
      await page.getByRole('heading', { name: /¿Qué hice hoy\?/ }).click()
    } else {
      await expect(page.getByRole('heading', { level: 2, name: /hoy/i })).toBeVisible()
    }
    await expect(page.getByRole('tablist', { name: 'Tipo de actividad' })).toBeVisible()
    await expect(page.getByRole('tab', { name: /Llamadas/ })).toHaveAttribute('aria-selected', 'true')
    await page.getByRole('tab', { name: 'Todo' }).click()
    await expect(page.getByRole('tab', { name: 'Todo' })).toHaveAttribute('aria-selected', 'true')
    // El demo tiene gestiones de HOY: la lista tiene filas con hora, chip y detalle.
    const lista = page.getByRole('list', { name: 'Registro de actividad' })
    await expect(lista.getByRole('listitem').first()).toBeVisible()
    await expect(lista.getByText(/Contestó|No contestó/).first()).toBeVisible()
    // `last()`: la pantalla del analista puede traer su propio tabpanel antes
    // que el del registro; el del registro es siempre el último.
    await expect(page.getByRole('tabpanel').last()).toBeVisible()
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
