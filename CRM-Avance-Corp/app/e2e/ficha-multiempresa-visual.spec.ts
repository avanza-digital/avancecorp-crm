import {expect, test} from '@playwright/test'
import {clienteReal, contratoReal, irAMiCartera, loginReal, montarBackendReal, UID, verTodaLaCartera} from './_helpers'
import {carteraF5, fichaF5, inversionF5, PERSONA_F5} from '../src/test/fixtures/f5'

// Misma persona y contrato en las dos lecturas; sólo se sustituye la frontera
// del backend local interceptado. Nunca se consulta ni se escribe producción.
for (const rol of ['vendedor', 'gerencia'] as const) {
  for (const ancho of [1440, 390]) {
    test(`${rol} ${ancho}px: conserva la ficha anterior y abre el detalle multiempresa`, async ({page}, info) => {
      await page.setViewportSize({width: 1440, height: 1000})
      const persona = clienteReal({nombre_completo: 'ANA SINTÉTICA F5', nombres: 'ANA', apellidos: 'SINTÉTICA F5'})
      const contrato = contratoReal({cliente_nombre: persona.nombre_completo})
      await montarBackendReal(page, {rolCrm: rol, clientes: [persona], contratos: [contrato]})
      await loginReal(page)
      await irAMiCartera(page)
      await verTodaLaCartera(page)
      await page.setViewportSize({width: ancho, height: ancho === 390 ? 844 : 1000})
      if (ancho === 390) await page.getByRole('button', {name: 'Ocultar menú'}).click()
      await page.getByRole('button', {name: 'Ver detalle', exact: true}).click()
      const anterior = page.getByRole('dialog', {name: persona.nombre_completo})
      await expect(anterior.getByRole('button', {name: 'Ver contrato 2026-01-000123'})).toBeVisible()
      await anterior.getByRole('heading', {name: persona.nombre_completo}).scrollIntoViewIfNeeded()
      const medidaAnterior = await anterior.boundingBox()
      await page.screenshot({path: info.outputPath('ficha-anterior.png'), fullPage: true})
      await page.keyboard.press('Escape')

      const ficha = structuredClone(fichaF5)
      ficha.persona = {...ficha.persona, nombre: persona.nombre_completo, telefono: persona.telefono, correo: persona.correo,
        documento: persona.dni, perfil_id: persona.id, responsable_id: UID}
      ficha.capacidades.postventa = true
      ficha.continuidad = {proximo_vencimiento: contrato.fecha_vencimiento}
      ficha.inversiones = [{...inversionF5, empresa: 'avance', perfil_id: persona.id, numero: contrato.numero_contrato,
        estado: contrato.estado, capital: contrato.capital, vence_en: contrato.fecha_vencimiento,
        contrato: {fecha_inicio: contrato.fecha_inicio, tasa_anual: contrato.tasa_anual, modalidad: 'mensual', tipo_interes: 'simple', categoria: contrato.categoria}}]
      ficha.totales = [{empresa: 'avance', moneda: 'PEN', cantidad: 1, capital_activo: contrato.capital, capital_registrado: contrato.capital}]
      await page.route('**/rest/v1/rpc/*', async route => {
        const nombre = new URL(route.request().url()).pathname.split('/').at(-1)
        if (nombre === 'cartera_inversionistas_estado_fn') return route.fulfill({json: {version: 1, habilitada: true, escritura_habilitada: true, motivo: null}})
        if (nombre === 'cartera_inversionistas_filtrada_fn') return route.fulfill({json: {...carteraF5, filas: [{...carteraF5.filas[0], ...ficha.persona, empresas: ['avance'], resumen:ficha.totales}], totales: ficha.totales}})
        if (nombre === 'inversionista_ficha_fn') return route.fulfill({json: ficha})
        if (nombre === 'postventa_ficha_fn') return route.fulfill({json: {version: 1, habilitada: true, retiros: []}})
        return route.fallback()
      })
      await page.reload()
      await expect(page.getByRole('heading', {name: 'Cartera de inversionistas'})).toBeVisible()
      await page.getByRole('button', {name: `Abrir ficha de ${persona.nombre_completo}`}).click()
      const nueva = page.getByRole('dialog', {name: persona.nombre_completo})
      await expect(nueva.getByRole('button', {name: 'Agendar gestión', exact: true})).toBeVisible()
      expect(Math.abs((await nueva.boundingBox())!.width - medidaAnterior!.width)).toBeLessThanOrEqual(1)
      await expect(nueva.getByRole('button', {name: 'Cambiar responsable'})).toHaveCount(rol === 'gerencia' ? 1 : 0)
      await expect(nueva.getByRole('region', {name: 'Continuidad comercial del cliente'})).toContainText('S/ 10,000')
      await page.screenshot({path: info.outputPath('ficha-multiempresa.png'), fullPage: true})

      const abrirDetalle = nueva.getByRole('button', {name: /^(Ver inversión|Ocultar detalle de) 2026-01-000123$/})
      await abrirDetalle.focus()
      await page.keyboard.press('Enter')
      await expect(abrirDetalle).toHaveAttribute('aria-expanded', 'true')
      await expect(nueva.getByText('15% · mensual')).toBeVisible()
      await page.screenshot({path: info.outputPath('inversion-abierta.png'), fullPage: true})
      await expect(nueva.locator('[aria-expanded="true"]')).toBeFocused()
      await page.keyboard.press('Enter')
      await expect(nueva.getByText('15% · mensual')).toBeHidden()
      expect(await nueva.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
      await page.keyboard.press('Escape')
      await expect(page.getByRole('button', {name: `Abrir ficha de ${persona.nombre_completo}`})).toBeFocused()
      await expect(page).not.toHaveURL(new RegExp(PERSONA_F5))
    })
  }
}
