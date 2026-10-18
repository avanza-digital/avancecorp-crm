import {expect,test} from '@playwright/test'
import {irAMiCartera,leadReal,loginReal,montarBackendReal} from './_helpers'
import {carteraF5,fichaF5,inversionF5,FUENTE_F5,PERFIL_F5} from '../src/test/fixtures/f5'

for(const movil of [false,true]) test(`Coordinación consulta Leads y corrige categoría, ${movil?'móvil':'escritorio'}`,async({page},testInfo)=>{
  await page.clock.setFixedTime(new Date('2026-10-15T15:00:00Z'))
  await page.setViewportSize({width:1440,height:1000})
  await montarBackendReal(page,{rolCrm:'coordinador',rolPortal:'comercial',leads:[leadReal({nombre_completo:'LEAD DE TODA LA EMPRESA'})]})
  let categoria='nuevo'
  let escrituras=0
  const f=structuredClone(fichaF5)
  f.capacidades={...f.capacidades,nueva_inversion:false,postventa:false,documentos:false,cuentas_perfil_ids:[]}
  f.inversiones=[{...inversionF5,empresa:'avance',numero:'CONTRATO SINTÉTICO',perfil_id:PERFIL_F5,
    contrato:{fecha_inicio:'2026-10-05',tasa_anual:15,modalidad:'mensual',tipo_interes:'simple',categoria}}]
  await page.route('**/rest/v1/rpc/*',async route=>{
    const nombre=new URL(route.request().url()).pathname.split('/').at(-1)
    if(route.request().method()!=='POST') return route.fallback()
    if(nombre==='cartera_inversionistas_estado_fn') return route.fulfill({json:{version:1,habilitada:true,escritura_habilitada:false,motivo:null}})
    if(nombre==='cartera_inversionistas_filtrada_fn') return route.fulfill({json:carteraF5})
    if(nombre==='inversionista_ficha_fn') return route.fulfill({json:{...f,inversiones:f.inversiones.map(i=>({...i,contrato:{...i.contrato,categoria}}))}})
    if(nombre==='corregir_categoria_contrato_fn') {
      const body=route.request().postDataJSON()
      expect(body).toEqual({p_contrato_id:FUENTE_F5,p_categoria:'renovacion',p_motivo:'El analista seleccionó Nuevo por error'})
      categoria=body.p_categoria;escrituras++
      return route.fulfill({json:{ok:true,cambio:true,contrato_id:FUENTE_F5,categoria}})
    }
    return route.fallback()
  })
  await loginReal(page)
  await expect(page).toHaveURL(/#\/repartir$/)
  await page.getByRole('button',{name:'Leads',exact:true}).click()
  await expect(page).toHaveURL(/#\/cartera$/)
  const lead=page.getByRole('row',{name:'Abrir ficha de LEAD DE TODA LA EMPRESA'})
  await expect(lead).toBeVisible()
  await expect(page.getByRole('button',{name:'Nuevo lead',exact:true})).toHaveCount(0)
  await lead.click()
  const fichaLead=page.getByRole('dialog',{name:'LEAD DE TODA LA EMPRESA',exact:true})
  await expect(fichaLead).toBeVisible()
  await expect(fichaLead.getByRole('button',{name:'Editar datos',exact:true})).toHaveCount(0)
  await fichaLead.getByRole('button',{name:'Cerrar ficha',exact:true}).click()
  await irAMiCartera(page)
  if(movil) {
    await page.getByRole('button',{name:'Ocultar menú'}).click()
    await page.setViewportSize({width:390,height:844})
  }
  await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
  await expect(page.getByRole('button',{name:'Datos y correcciones'})).toHaveCount(0)
  await expect(page.getByRole('button',{name:'Registrar nueva inversión'})).toHaveCount(0)
  await page.getByRole('button',{name:'Corregir categoría de CONTRATO SINTÉTICO'}).click()
  const dialogo=page.getByRole('dialog',{name:'Corregir categoría de inversión'})
  await expect(dialogo.getByRole('button',{name:'Guardar corrección'})).toBeDisabled()
  await dialogo.getByLabel('Categoría correcta').selectOption('renovacion')
  await dialogo.getByLabel('Motivo de la corrección').fill('El analista seleccionó Nuevo por error')
  await page.screenshot({path:testInfo.outputPath(`categoria-${movil?'movil':'escritorio'}.png`),fullPage:true})
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
  await dialogo.getByRole('button',{name:'Guardar corrección'}).click()
  await expect(dialogo).toHaveCount(0)
  await expect(page.getByRole('region',{name:'Inversiones y contratos'}).getByText('Renovación',{exact:true})).toBeVisible()
  expect(escrituras).toBe(1)
})
