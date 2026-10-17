import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'
import { irAModulo } from './_navegacion'
import fixture from '../test-fixtures/capital-valorado/facturacion-rangos.json' with { type: 'json' }

const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }

test('Facturación conserva agosto/septiembre y concilia septiembre-octubre con sus dos regímenes', async ({ page }, info) => {
  await page.clock.setFixedTime(new Date('2026-10-16T17:00:00Z'))
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'comercial' })
  await page.route('**/rest/v1/rpc/facturacion_diaria_v2_fn', route => {
    const mes=route.request().postDataJSON().p_mes as keyof typeof fixture.meses
    return route.fulfill({headers:CORS,json:fixture.meses[mes]??{version:2,valoracion_activa:false,filas:[]}})
  })
  let actual = 3.1
  await page.route('**/functions/v1/crm-tipo-cambio', route => {
    const fecha=route.request().postDataJSON()?.fecha_corte as string | undefined
    const promedio=fecha==='2026-08-31'?3.6:fecha==='2026-09-30'?3.5:actual
    return route.fulfill({headers:CORS,json:{promedio,fuente:'BCRP',...(fecha?{fecha_corte:fecha}:{})}})
  })
  let pedidos=0
  await page.route('**/rest/v1/rpc/listar_operaciones_facturacion_v3_fn', route => {
    const body=route.request().postDataJSON()
    expect(body.p_desde).toBe('2026-09-28')
    expect(body.p_hasta).toBe('2026-10-04')
    expect(body.p_cortes).toEqual(fixture.pedido.p_cortes)
    expect(body).not.toHaveProperty('tasasLegadas')
    pedidos++
    return route.fulfill({headers:CORS,json:fixture.lista})
  })
  await loginReal(page)
  await irAModulo(page,'Facturación')
  const total=(cantidad:string)=>page.getByRole('button',{name:`Total facturado: S/ ${cantidad}, ver el desglose`,exact:true})
  await expect(total('197,800')).toBeVisible()
  await page.getByRole('button',{name:'Mes anterior',exact:true}).click()
  await expect(total('49,000')).toBeVisible()
  await page.getByRole('button',{name:'Mes anterior',exact:true}).click()
  await expect(total('10,800')).toBeVisible()
  await page.getByRole('button',{name:'Mes siguiente',exact:true}).click()
  await expect(total('49,000')).toBeVisible()
  await page.getByRole('button',{name:'Mes siguiente',exact:true}).click()
  await page.getByRole('group',{name:'Tramo que se mira'}).getByRole('button',{name:'Semana',exact:true}).click()
  // Al navegar Mes el ancla queda el 01/10: su semana cruza septiembre-octubre.
  await expect(total('185,100')).toBeVisible()
  for(const width of [1440,390]) {
    await page.setViewportSize({width,height:900})
    await total('185,100').click()
    const lista=page.locator('.lista-operaciones')
    await expect(lista).toContainText('Cuadra. Pulsaste S/ 185,100')
    await expect(lista).toContainText('S/ 68,000 equivalentes')
    await expect(lista).toContainText('Tipo de cambio S/ 3.4000')
    await expect(lista).toContainText('3.5000')
    if(width===390) await page.screenshot({path:info.outputPath('facturacion-semana-mixta-movil.png'),fullPage:true})
    await page.getByRole('button',{name:'Cerrar detalle',exact:true}).click()
    actual=4.5
    await expect(total('185,100')).toBeVisible()
  }
  expect(pedidos).toBeGreaterThan(0)
})
