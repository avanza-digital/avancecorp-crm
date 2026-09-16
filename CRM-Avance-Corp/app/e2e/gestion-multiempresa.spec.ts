import {expect,test,type Page} from '@playwright/test'
import {contratoReal,irAMiCartera,loginReal,montarBackendReal} from './_helpers'
import {carteraF5,fichaF5,FUENTE_F5,PERSONA_F5} from '../src/test/fixtures/f5'
import type {GestionInversionista} from '../src/data/gestion-inversionista'

async function montar(page:Page,avance=false){
  const contrato=contratoReal({id:FUENTE_F5,cliente_nombre:'ANA SINTÉTICA F5',notas_internas:'NOTA CONTRACTUAL CONSERVADA'})
  await montarBackendReal(page,{rolCrm:'gerencia',rolPortal:'comercial',contratos:[contrato],cuotas:{[FUENTE_F5]:[
    {id:'q1',numero_cuota:1,fecha_programada:'2026-08-01',monto_programado:125,estado:'pagado',tipo:'cuota',fecha_pago_real:'2026-08-02',monto_pagado:125},
    {id:'q2',numero_cuota:2,fecha_programada:'2026-09-01',monto_programado:125,estado:'pendiente',tipo:'cuota',fecha_pago_real:null,monto_pagado:null},
  ]},titulares:{[FUENTE_F5]:[{nombre_completo:'MARÍA COTITULAR',tipo_documento:'CE',documento:'001234567',orden:1}]}})
  const ficha=structuredClone(fichaF5)
  if(avance)ficha.inversiones=[{...ficha.inversiones[0]!,empresa:'avance',numero:contrato.numero_contrato,perfil_id:contrato.cliente_id,
    contrato:{fecha_inicio:contrato.fecha_inicio,tasa_anual:15,modalidad:'mensual',tipo_interes:'simple',categoria:'nuevo'}}]
  const gestion:GestionInversionista={version:1,inversionista_id:PERSONA_F5,perfiles:[],
    contacto:{nombre_completo:ficha.persona.nombre,telefono:ficha.persona.telefono,domicilio:null,creado_en:new Date().toISOString(),sin_limite:true,puede_corregir:true,revision:'rev1'},
    documento:{id:null,tipo:'DNI',numero:ficha.persona.documento,puede_corregir:false},
    inversion:avance?{empresa:'avance',fuente_id:FUENTE_F5,contrato,coopac:null,puede_corregir:true,sin_limite:true,puede_reasignar:true,operaciones:[]}:null}
  const estado={guardados:0,listasContrato:0}
  page.on('request',r=>{if(new URL(r.url()).pathname.endsWith('/contratos_cartera'))estado.listasContrato++})
  await page.route('**/rest/v1/rpc/*',async route=>{
    const nombre=new URL(route.request().url()).pathname.split('/').at(-1),body=route.request().postDataJSON()
    if(nombre==='cartera_inversionistas_estado_fn')return route.fulfill({json:{version:1,habilitada:true,escritura_habilitada:true,motivo:null}})
    if(nombre==='cartera_inversionistas_filtrada_fn')return route.fulfill({json:carteraF5})
    if(nombre==='inversionista_ficha_fn')return route.fulfill({json:ficha})
    if(nombre==='inversionista_gestion_fn')return route.fulfill({json:{...gestion,inversion:body.p_fuente?gestion.inversion:null}})
    if(nombre==='historial_tasa_cliente_fn')return route.fulfill({json:{version:1,cliente_id:contrato.cliente_id,contratos:[],solicitudes:[]}})
    if(nombre==='inversionista_corregir_contacto_fn'){
      estado.guardados++;expect(body.p_revision).toBe('rev1');ficha.persona.nombre=body.p_datos.nombre_completo
      return route.fulfill({json:{ok:true,inversionista_id:PERSONA_F5}})
    }
    return route.fallback()
  })
  await loginReal(page);await irAMiCartera(page)
  return estado
}
for(const ancho of [1440,390]){
  test(`contacto neutral ${ancho}px: guarda, conserva filtro y vuelve al foco de la ficha`,async({page},info)=>{
    const estado=await montar(page)
    await page.setViewportSize({width:ancho,height:ancho===390?844:1000})
    if(ancho===390)await page.getByRole('button',{name:'Ocultar menú'}).click()
    await page.getByLabel('Buscar persona').fill('9333')
    await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
    await page.getByRole('button',{name:'Datos y correcciones'}).click()
    await page.getByRole('button',{name:'Corregir datos de contacto'}).click()
    const modal=page.getByRole('dialog',{name:'Corregir datos del cliente'})
    await modal.getByLabel('Nombres y apellidos').fill('ANA CORREGIDA SINTÉTICA')
    await modal.getByLabel('Domicilio').fill('DOMICILIO SINTÉTICO CONSERVADO')
    expect(await modal.evaluate(el=>el.scrollWidth<=el.clientWidth)).toBe(true)
    expect(await modal.evaluate(el=>{
      const caja=el.getBoundingClientRect()
      return [...el.querySelectorAll('button')].every(b=>{
        const r=b.getBoundingClientRect();return r.left>=caja.left && r.right<=caja.right
      })
    })).toBe(true)
    await page.screenshot({path:info.outputPath('correccion-contacto.png'),fullPage:true})
    await modal.getByRole('button',{name:'Guardar corrección'}).click()
    await expect(modal).toHaveCount(0);expect(estado.guardados).toBe(1)
    await expect(page.getByRole('dialog',{name:'ANA CORREGIDA SINTÉTICA'})).toBeVisible()
    await expect(page.getByRole('button',{name:'Datos y correcciones'})).toBeFocused()
    await page.keyboard.press('Escape')
    await expect(page.getByLabel('Buscar persona')).toHaveValue('9333')
  })
  test(`detalle Avance ${ancho}px: cronograma y corrección puntual sin recargar la cartera`,async({page},info)=>{
    const estado=await montar(page,true)
    await page.setViewportSize({width:ancho,height:ancho===390?844:1000})
    if(ancho===390)await page.getByRole('button',{name:'Ocultar menú'}).click()
    await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
    await page.getByRole('button',{name:'Ver inversión 2026-01-000123'}).click()
    const antes=estado.listasContrato
    await page.getByRole('button',{name:'Detalle completo de 2026-01-000123'}).click()
    const modal=page.getByRole('dialog',{name:/2026-01-000123/})
    await expect(modal.getByText('NOTA CONTRACTUAL CONSERVADA')).toBeVisible()
    await expect(modal.getByText('MARÍA COTITULAR')).toBeVisible()
    await expect(modal.getByRole('row',{name:/Cuota #1/})).toContainText('125')
    await expect(modal.getByRole('region',{name:'Resumen del cronograma'})).toBeVisible()
    expect(estado.listasContrato).toBe(antes)
    expect(await modal.evaluate(el=>el.scrollWidth<=el.clientWidth)).toBe(true)
    await page.screenshot({path:info.outputPath('detalle-avance.png'),fullPage:true})
    await modal.getByRole('button',{name:'Corregir contrato',exact:true}).click()
    await expect(modal.locator('#cc-notas')).toHaveValue('NOTA CONTRACTUAL CONSERVADA')
    await expect(modal.getByLabel('Nombre del co-titular 1')).toHaveValue('MARÍA COTITULAR')
    await expect(modal.locator('#cc-moneda')).toBeDisabled()
    await page.screenshot({path:info.outputPath('correccion-avance.png'),fullPage:true})
    await page.keyboard.press('Escape')
    await expect(page.getByRole('dialog',{name:'ANA SINTÉTICA F5'})).toBeVisible()
    await expect(page.getByRole('button',{name:'Detalle completo de 2026-01-000123'})).toBeFocused()
  })
}
