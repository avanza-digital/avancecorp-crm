import {expect, test, type Page} from '@playwright/test'
import {loginReal, montarBackendReal, irAMiCartera} from './_helpers'
import {carteraF5, fichaF5, FUENTE_F5, PERSONA_F5, inversionF5} from '../src/test/fixtures/f5'

async function montarF5(page:Page, rol:'vendedor'|'supervisor'|'gerencia'|'directorio'='vendedor', sinInversiones=false, empresa:'qorilazo'|'prodelco'='qorilazo') {
  const backend=await montarBackendReal(page,{rolCrm:rol,rolPortal:rol==='directorio'?'directorio':'analista',clientes:[],contratos:[]})
  const estado={revocado:false,preparaciones:0,confirmaciones:0,solicitud:null as Record<string,unknown>|null,bancos:0,sinInversiones,puerta:''}
  await page.route('**/rest/v1/rpc/*',async route=>{
    const nombre=new URL(route.request().url()).pathname.split('/').at(-1)
    const body=route.request().postDataJSON() ?? {}
    const json=(data:unknown,status=200)=>route.fulfill({status,json:data})
    if(nombre==='cartera_inversionistas_estado_fn') return json({version:1,habilitada:true,escritura_habilitada:rol!=='directorio',motivo:null})
    if(nombre==='cartera_inversionistas_filtrada_fn') {
      const totales=carteraF5.totales.map(t=>({...t,empresa:rol==='directorio'?'avance':t.empresa}))
      const filas=estado.revocado?[]:carteraF5.filas.map(p=>({...p,empresas:rol==='directorio'?['avance']:p.empresas,resumen:totales}))
      return json({...carteraF5,solo_avance:rol==='directorio',filas,total:filas.length,tamano:body.p_tamano,pagina:body.p_pagina,totales:estado.revocado?[]:totales})
    }
    if(nombre==='inversionista_ficha_fn') {
      if(estado.revocado) return json(null)
      const f=structuredClone(fichaF5)
      f.capacidades.postventa=rol!=='directorio'
      f.inversiones=f.inversiones.map(i=>({...i,empresa,numero:`${empresa.toUpperCase()} SINTÉTICO`}))
      if(estado.sinInversiones) {f.inversiones=[];f.inversiones_total=0;f.totales=[]}
      if(rol==='directorio') {f.capacidades.nueva_inversion=false;f.capacidades.contactar=false;f.capacidades.documentos=false;f.inversiones=[];f.inversiones_total=0;f.totales=[]}
      return json(f)
    }
    if(nombre==='inversionista_cuentas_fn') {estado.bancos++;return json([])}
    if(nombre==='postventa_estado_fn') return json({version:1,habilitada:rol!=='directorio'})
    if(nombre==='postventa_ficha_fn') return json({version:1,habilitada:rol!=='directorio',retiros:[]})
    if(nombre==='postventa_agenda_fn') return json([])
    if(nombre==='preparar_inversion_fn'||nombre==='preparar_upgrade_fn'||nombre==='preparar_reinversion_fn') {
      estado.preparaciones++
      estado.puerta=nombre
      estado.solicitud={solicitud_id:body.p_clave,estado:'preparada',inversion_id:null,inversionista_id:PERSONA_F5,inversionista_origen_id:PERSONA_F5,
        identidad_fusionada:false,responsable_esperado_id:fichaF5.persona.responsable_id,responsable_actual_id:fichaF5.persona.responsable_id,
        requiere_revision_responsable:false,revision_datos:0,revision_responsable:0,hash_datos:'huella-sintetica',resultado:null,
        necesita_portal:false,comprobante_bucket:'f4-comprobantes',comprobante_ruta:body.p_datos.evidencia.ruta,datos:body.p_datos,
        ...(nombre==='preparar_upgrade_fn'?{upgrade_origen_id:body.p_fuente}:nombre==='preparar_reinversion_fn'?{reinversion_origen_id:body.p_fuente}:{})}
      return json(estado.solicitud)
    }
    if(nombre==='solicitud_inversion_fn') return json(estado.solicitud)
    if(nombre==='confirmar_inversion_revisada_fn') {
      estado.confirmaciones++
      estado.sinInversiones=false
      return json({ok:true,solicitud_id:body.p_solicitud,inversion_id:FUENTE_F5,inversionista_id:PERSONA_F5,
        empresa,fuente:{cierre_id:FUENTE_F5},revision_datos:body.p_revision_datos_esperada})
    }
    return route.fallback()
  })
  await page.route('**/storage/v1/object/f4-comprobantes/**',route=>route.fulfill({json:{Key:'comprobante-f5'}}))
  await loginReal(page);await irAMiCartera(page)
  return {estado,backend}
}

for(const empresa of ['qorilazo','prodelco'] as const) {
  test(`${empresa}: upgrade y reinversión separados, aporte adicional y recuperación móvil`,async({page},testInfo)=>{
    const {estado}=await montarF5(page,'vendedor',false,empresa)
    await page.setViewportSize({width:390,height:844})
    await page.getByRole('button',{name:'Ocultar menú'}).click()
    await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
    const inversiones=page.getByRole('region',{name:'Inversiones y contratos'})
    await expect(inversiones.getByRole('button',{name:'Registrar nueva inversión'})).toBeDisabled()
    await expect(inversiones.getByRole('button',{name:'Reinvertir desde esta inversión'})).toBeVisible()
    await inversiones.getByRole('button',{name:'Registrar upgrade',exact:true}).scrollIntoViewIfNeeded()
    await page.screenshot({path:testInfo.outputPath(`${empresa}-upgrade-y-reinversion.png`),fullPage:true})
    await inversiones.getByRole('button',{name:'Registrar upgrade',exact:true}).click()
    await expect(page.getByRole('heading',{name:/^Upgrade ·/})).toBeVisible()
    await page.getByLabel('Aporte adicional en soles (PEN)').fill('250')
    await page.getByLabel('Número de operación del depósito').fill('UPGRADE-E2E')
    await page.getByLabel('Plazo (meses)').fill('12')
    await page.getByLabel('Rentabilidad anual (%)').fill('12')
    await page.getByLabel('Referencia de la inversión').fill('APORTE SINTÉTICO')
    await page.getByLabel(/Comprobante PDF/).setInputFiles({name:'aporte.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4\n% comprobante sintético')})
    await page.getByRole('button',{name:'Revisar upgrade',exact:true}).click()
    await expect(page.getByRole('heading',{name:'Revisar upgrade'})).toBeVisible()
    expect(estado.puerta).toBe('preparar_upgrade_fn')
    expect(estado.solicitud).toMatchObject({upgrade_origen_id:FUENTE_F5,datos:{monto:250,empresa}})
    expect(estado.solicitud?.reinversion_origen_id).toBeUndefined()
    await page.getByRole('button',{name:'Cerrar y continuar después'}).click()
    await page.getByRole('button',{name:'Reinvertir desde esta inversión'}).click()
    await expect(page.getByRole('heading',{name:'Revisar upgrade'})).toBeVisible()
    await expect(page.getByRole('button',{name:'Confirmar upgrade'})).toBeEnabled()
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
    await page.screenshot({path:testInfo.outputPath(`${empresa}-upgrade-revision.png`),fullPage:true})
    await page.getByRole('button',{name:'Confirmar upgrade'}).click()
    await expect(page.getByRole('heading',{name:'Upgrade confirmado'})).toBeVisible()
    expect(estado.preparaciones).toBe(1)
    expect(estado.confirmaciones).toBe(1)
  })
}

for(const rol of ['vendedor','supervisor','gerencia','directorio'] as const) {
  test(`${rol}: ficha neutral, retorno de foco y permisos por rol`,async({page},testInfo)=>{
    const {estado}=await montarF5(page,rol)
    await expect(page.getByRole('heading',{name:'Cartera de inversionistas'})).toBeVisible()
    const abrir=page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    await abrir.focus();await page.keyboard.press('Enter')
    const dialog=page.getByRole('dialog',{name:'ANA SINTÉTICA F5'})
    await expect(dialog.getByText('Información del cliente')).toBeVisible()
    await expect(dialog.getByText('ana.f5@pruebas.example')).toBeVisible()
    if(rol==='directorio') {
      await expect(dialog.getByRole('button',{name:'Registrar nueva inversión'})).toHaveCount(0)
      await expect(dialog.getByRole('link',{name:'Llamar'})).toHaveCount(0)
    } else {
      await expect(dialog.getByRole('button',{name:'Registrar nueva inversión'})).toBeDisabled()
      await expect(dialog.getByText(/ya tiene una inversión registrada/)).toBeVisible()
    }
    expect(estado.bancos).toBe(0)
    await page.screenshot({path:testInfo.outputPath(`f5-${rol}-ficha.png`),fullPage:true})
    await page.keyboard.press('Escape');await expect(dialog).toHaveCount(0)
    await expect(abrir).toBeFocused()
  })
}
test('móvil: búsqueda conservada, formulario nativo, revisión y confirmación única',async({page},testInfo)=>{
  const {estado}=await montarF5(page,'vendedor',true)
  await page.setViewportSize({width:390,height:844})
  await page.getByRole('button',{name:'Ocultar menú'}).click()
  await page.getByLabel('Buscar persona').fill('9333')
  await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
  await page.getByRole('button',{name:'Registrar primera inversión',exact:true}).click()
  await page.getByRole('button',{name:'Qorilazo',exact:true}).click()
  await page.getByLabel('Capital en soles (PEN)').fill('2500')
  await page.getByLabel('Número de operación del depósito').fill('F5-UI-SINTETICO')
  await page.getByLabel('Fecha comercial (inicio)').fill('2026-01-31')
  await page.getByLabel('Plazo (meses)').fill('1')
  await expect(page.getByLabel('Vencimiento')).toHaveValue('2026-02-28')
  await page.getByLabel('Rentabilidad anual (%)').fill('12,50')
  await page.screenshot({path:testInfo.outputPath('coopac-plazo-rentabilidad-movil.png'),fullPage:true})
  await page.getByLabel('Referencia de la inversión').fill('ENSAYO F5 DE NAVEGADOR')
  await page.getByLabel(/Comprobante PDF/).setInputFiles({name:'prueba.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4\n ENSAYO FICTICIO')})
  await page.getByLabel('Rentabilidad anual (%)').fill('12,345')
  await page.getByRole('button',{name:'Revisar inversión',exact:true}).click()
  await expect(page.getByRole('alert')).toContainText('rentabilidad anual pactada')
  await expect(page.getByLabel('Rentabilidad anual (%)')).toHaveAttribute('aria-invalid','true')
  await expect(page.getByLabel('Rentabilidad anual (%)')).toHaveAttribute('aria-describedby',/f5-condiciones-error/)
  await page.getByLabel('Rentabilidad anual (%)').fill('12,50')
  await page.getByRole('button',{name:'Revisar inversión',exact:true}).click()
  await expect(page.getByRole('heading',{name:'Revisar inversión'})).toBeVisible()
  expect(estado.confirmaciones).toBe(0)
  expect(estado.solicitud?.datos).toMatchObject({plazo_meses:1,tasa_anual:12.5,vence_en:'2026-02-28'})
  await expect(page.getByText('12.5% anual')).toBeVisible()
  await expect(page.getByRole('button',{name:'Confirmar inversión'})).toBeEnabled()
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
  await page.screenshot({path:testInfo.outputPath('f5-movil-revision.png'),fullPage:true})
  await page.getByRole('button',{name:'Confirmar inversión'}).click()
  await expect(page.getByRole('heading',{name:'Inversión confirmada'})).toBeVisible()
  expect(estado.preparaciones).toBe(1);expect(estado.confirmaciones).toBe(1)
  await page.getByRole('button',{name:'Volver a la ficha'}).click()
  await expect(page.getByRole('region',{name:'Inversiones y contratos'})).toBeFocused()
  await expect(page.getByRole('button',{name:'Registrar nueva inversión',exact:true})).toBeDisabled()
  await page.keyboard.press('Escape')
  await expect(page.getByLabel('Buscar persona')).toHaveValue('9333')
  await page.screenshot({path:testInfo.outputPath('f5-movil-cartera.png'),fullPage:true})
})
test('revocación con ficha abierta retira identidad y evita reutilizar datos anteriores',async({page})=>{
  const {estado}=await montarF5(page)
  await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
  await expect(page.getByText('ana.f5@pruebas.example')).toBeVisible()
  estado.revocado=true
  await page.evaluate(()=>window.dispatchEvent(new Event('focus')))
  await expect(page.getByText('ana.f5@pruebas.example')).toHaveCount(0,{timeout:18000})
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page.getByText(/El acceso cambió/)).toBeVisible()
})
test('tres empresas y dos monedas: la ficha mantiene cada capital separado',async({page},testInfo)=>{
  await montarF5(page)
  await page.route('**/rest/v1/rpc/inversionista_ficha_fn',route=>{
    const monedas=[['avance','PEN',15000],['avance','USD',3000],['qorilazo','PEN',1200],['prodelco','PEN',2000]] as const
    return route.fulfill({json:{...fichaF5,inversiones_total:4,
      inversiones:monedas.map(([empresa,moneda,capital],n)=>({...inversionF5,empresa,moneda,capital,
        estado:empresa==='avance'?'activo':'vigente',numero_transaccion:empresa==='avance'?null:inversionF5.numero_transaccion,
        fuente_id:`55555555-5555-4555-8555-${String(n+1).padStart(12,'0')}`,numero:`INVERSIÓN SINTÉTICA ${empresa.toUpperCase()} ${moneda}`})),
      totales:monedas.map(([empresa,moneda,capital])=>({empresa,moneda,cantidad:1,capital_registrado:capital,capital_activo:empresa==='avance'?capital:null}))}})
  })
  await page.setViewportSize({width:1440,height:1200})
  await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
  const dialog=page.getByRole('dialog',{name:'ANA SINTÉTICA F5'})
  for(const nombre of ['Avance · PEN','Avance · USD','Qorilazo · PEN','Prodelco · PEN']) {
    await expect(dialog.getByRole('heading',{name:nombre,exact:true})).toHaveCount(1)
  }
  await expect(dialog.getByText('4 inversiones en esta ficha')).toBeVisible()
  await page.screenshot({path:testInfo.outputPath('f5-tres-empresas.png'),fullPage:true})
})

for(const movil of [false,true]) test(`filtros comerciales: ${movil?'móvil':'escritorio'}, selección completa y ficha conservada`,async({page},testInfo)=>{
  await montarF5(page,'supervisor')
  await page.setViewportSize({width:movil?390:1440,height:movil?844:1000})
  if(movil) await page.getByRole('button',{name:'Ocultar menú'}).click()
  const peticiones:Record<string,unknown>[]=[]
  const resumen=[
    {empresa:'avance',moneda:'PEN',cantidad:2,capital_registrado:25000,capital_activo:15000},
    {empresa:'avance',moneda:'USD',cantidad:1,capital_registrado:3500,capital_activo:3500},
    {empresa:'qorilazo',moneda:'PEN',cantidad:1,capital_registrado:12000,capital_activo:null},
  ]
  await page.route('**/rest/v1/rpc/cartera_inversionistas_filtrada_fn',async route=>{
    const b=route.request().postDataJSON();peticiones.push(b)
    const vacio=b.p_mes==='2026-07'
    const nombres=['ANA SINTÉTICA F5','BRUNO CLIENTE DE PRUEBA','CARMEN CLIENTE DE PRUEBA','DANIEL CLIENTE DE PRUEBA','ELENA CLIENTE DE PRUEBA']
    return route.fulfill({json:{...carteraF5,pagina:b.p_pagina,tamano:b.p_tamano,total:vacio?0:5,
      opciones_meses:['2026-09','2026-08','2026-07'],
      filas:vacio?[]:nombres.map((nombre,n)=>({...carteraF5.filas[0],nombre,
        inversionista_id:n===0?PERSONA_F5:`55555555-5555-4555-8555-${String(n).padStart(12,'0')}`,
        empresas:['avance','qorilazo'],resumen})),totales:vacio?[]:resumen}})
  })
  await page.getByRole('button',{name:'Actualizar cartera'}).click()
  await expect(page.getByText('5 personas · página 1')).toBeVisible()
  if(movil) await expect(page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})).toBeInViewport()
  await page.screenshot({path:testInfo.outputPath(`cartera-filtros-${movil?'movil':'escritorio'}.png`),fullPage:true})
  await page.getByLabel('Mes de cierre comercial').selectOption('2026-08')
  await page.getByRole('button',{name:'Más filtros',exact:true}).click()
  await page.getByLabel('Moneda',{exact:true}).selectOption('USD')
  await page.getByLabel('Estado de inversión').selectOption('vigente')
  await expect.poll(()=>peticiones.at(-1)).toMatchObject({p_mes:'2026-08',p_moneda:'USD',p_estado:'vigente',p_pagina:1})
  await page.screenshot({path:testInfo.outputPath(`cartera-filtros-abiertos-${movil?'movil':'escritorio'}.png`),fullPage:true})
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
  const filtro=page.getByLabel('Moneda',{exact:true});await filtro.focus()
  await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
  await expect(page.getByRole('dialog',{name:'ANA SINTÉTICA F5'})).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByLabel('Mes de cierre comercial')).toHaveValue('2026-08')
  await expect(filtro).toHaveValue('USD')
  await page.getByLabel('Mes de cierre comercial').selectOption('2026-07')
  await expect(page.getByText('No hay personas que coincidan con estos filtros.')).toBeVisible()
  await expect(page.getByText('US$ 3,500')).toHaveCount(0)
  await page.getByRole('button',{name:'Ver toda la cartera'}).click()
  await expect(page.getByLabel('Mes de cierre comercial')).toHaveValue('')
  await expect(page.getByText('5 personas · página 1')).toBeVisible()
})
