import {expect, test} from '@playwright/test'
import {irAMiCartera, loginReal, montarBackendReal} from './_helpers'
import {carteraF5, fichaF5, inversionF5, FUENTE_F5, PERFIL_F5} from '../src/test/fixtures/f5'

for (const ancho of [1440,390]) test(`Admin elimina inversión vinculada con confirmación y auditoría (${ancho}px)`,async({page},info)=>{
  await montarBackendReal(page,{rolCrm:'gerencia',rolPortal:'admin',clientes:[],contratos:[]})
  let eliminado=false
  let solicitudes=0
  await page.route('**/rest/v1/rpc/*',async route=>{
    const nombre=new URL(route.request().url()).pathname.split('/').at(-1)
    if(nombre==='cartera_inversionistas_estado_fn') return route.fulfill({json:{version:1,habilitada:true,escritura_habilitada:true,motivo:null}})
    if(nombre==='cartera_inversionistas_filtrada_fn') return route.fulfill({json:carteraF5})
    if(nombre==='inversionista_ficha_fn') return route.fulfill({json:{...fichaF5,
      inversiones:eliminado?[]:[{...inversionF5,inversion_id:FUENTE_F5,empresa:'avance',perfil_id:PERFIL_F5,numero:'2026-01-999999',contrato:{fecha_inicio:'2026-09-01',tasa_anual:15,modalidad:'mensual',tipo_interes:'simple',categoria:'nuevo'}}],
      inversiones_total:eliminado?0:1,totales:eliminado?[]:fichaF5.totales}})
    return route.fallback()
  })
  await page.route('**/functions/v1/crm-contrato-pdf-v2',async route=>{
    expect(route.request().postDataJSON()).toEqual({action:'delete-audited',contratoId:FUENTE_F5})
    solicitudes++;eliminado=true
    return route.fulfill({json:{ok:true,contratoId:FUENTE_F5,auditoriaId:PERFIL_F5,archivosConservados:2}})
  })
  await loginReal(page);await irAMiCartera(page)
  await page.setViewportSize({width:ancho,height:ancho===390?844:1000})
  if(ancho===390) await page.getByRole('button',{name:'Ocultar menú'}).click()
  await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
  const eliminar=page.getByRole('button',{name:'Eliminar contrato 2026-01-999999'})
  await eliminar.click()
  const modal=page.getByRole('dialog',{name:'Eliminar contrato 2026-01-999999'})
  await expect(modal.getByRole('button',{name:'Eliminar y conservar auditoría'})).toBeDisabled()
  await modal.getByRole('button',{name:'Cancelar'}).click()
  await expect(eliminar).toBeFocused();expect(solicitudes).toBe(0)
  await eliminar.click()
  await modal.getByRole('textbox').fill('2026-01-999999')
  await expect(modal.getByText(/incluidos los pagos registrados/)).toBeVisible()
  expect(await modal.evaluate(el=>el.scrollWidth<=el.clientWidth)).toBe(true)
  await page.screenshot({path:info.outputPath('confirmacion-auditoria.png'),fullPage:true})
  await modal.getByRole('button',{name:'Eliminar y conservar auditoría'}).click()
  await expect(modal).toHaveCount(0)
  await expect(page.getByText('Este cliente todavía no tiene una inversión registrada.')).toBeVisible()
  expect(solicitudes).toBe(1)
})
