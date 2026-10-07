import type { RegistroItem } from '../src/lib/gestion-diaria'
import {expect,test,type Page} from '@playwright/test'
import {randomUUID} from 'node:crypto'
import {loginReal,montarBackendReal,irAMiCartera,UID} from './_helpers'
import {carteraF5,fichaF5,PERSONA_F5,FUENTE_F5} from '../src/test/fixtures/f5'
import type {Tarea} from '../src/lib/tipos'
import type {RetiroPostventa} from '../src/lib/postventa'

async function montarF6(page:Page,rol:'vendedor'|'gerencia'|'directorio'='vendedor') {
  await montarBackendReal(page,{rolCrm:rol,rolPortal:rol==='directorio'?'directorio':'analista',clientes:[],contratos:[]})
  const estado={on:true,vetada:false,cortar:false,rechazarConfirmacion:false,negarFicha:false,fichaSinConexion:false,altas:0,financieras:0,claves:[] as string[],tareas:[] as Tarea[],eventos:[] as RegistroItem[],cierres:[] as Record<string,unknown>[],retiros:[] as RetiroPostventa[],recibos:new Set<string>()}
  const habilitada=()=>estado.on&&rol!=='directorio'
  function tarea(id:string,datos:Record<string,unknown>):Tarea {
    return {id,inversionista_id:PERSONA_F5,inversionista_canonico_id:PERSONA_F5,postventa_revision:1,
      lead_id:null,perfil_id:null,vendedor_id:UID,asignado_supervisor_id:null,tipo:'llamada',titulo:'Seguimiento F6',
      nota:null,vence_en:new Date(Date.now()+86400000).toISOString(),duracion_min:null,estado:'pendiente',
      modalidad_reunion:null,ubicacion_reunion:null,enlace_reunion:null,resultado_reunion:null,motivo_no_realizada:null,
      detalle_cierre_reunion:null,confirmada_en:null,reagendada_de:null,reprogramaciones:0,activo:true,creado_en:new Date().toISOString(),...datos}
  }
  await page.route('**/rest/v1/rpc/*',async route=>{
    const nombre=new URL(route.request().url()).pathname.split('/').at(-1)
    const b=route.request().postDataJSON()??{}
    const json=(data:unknown,status=200)=>route.fulfill({status,json:data})
    if(nombre==='cartera_inversionistas_estado_fn')return json({version:1,habilitada:true,escritura_habilitada:rol!=='directorio',motivo:null})
    if(nombre==='cartera_inversionistas_filtrada_fn')return json({...carteraF5,pagina:b.p_pagina,tamano:b.p_tamano})
    if(nombre==='inversionista_ficha_fn'){
      if(estado.fichaSinConexion)return json({message:'Interrupción temporal'},503)
      const f=structuredClone(fichaF5); f.persona.responsable_id=UID;f.persona.no_contactar=estado.vetada
      f.capacidades.postventa=habilitada();f.capacidades.contactar=habilitada()&&!estado.vetada
      f.capacidades.nueva_inversion=habilitada()&&!estado.vetada;f.tareas=estado.tareas.filter(t=>t.estado==='pendiente');f.tareas_total=f.tareas.length
      return json(f)
    }
    if(nombre==='registro_actividad_v2_fn')return json({version:2,zona:'America/Lima',desde:b.p_desde,hasta:b.p_hasta,generado_en:new Date().toISOString(),limite:b.p_limite,
      items:estado.eventos.filter(e=>(!b.p_analista_ids||b.p_analista_ids.includes(e.creado_por))&&(!b.p_tipos||b.p_tipos.includes(e.tipo))&&b.p_cartera!=='leads').toReversed().slice(0,b.p_limite)})
    if(nombre==='gestiones_resumen_fn'){
      const e=estado.eventos.filter(e=>e.metadata['estado']==='completada'),ll=e.filter(e=>e.tipo==='llamada_realizada'||e.tipo==='llamada_no_contestada')
      const cero={gestiones:0,llamadas:0,contestadas:0,entrevistas:0,ultima_llamada_en:null}
      const clientes={gestiones:e.length,llamadas:ll.length,contestadas:ll.filter(e=>e.tipo==='llamada_realizada').length,
        entrevistas:e.filter(e=>e.tipo==='reunion_realizada').length,ultima_llamada_en:ll.at(-1)?.creado_en??null}
      const metricas={leads:cero,clientes,total:clientes}
      return json({version:1,desde:b.p_desde,hasta:b.p_hasta,zona:'America/Lima',generado_en:new Date().toISOString(),totales:metricas,
        analistas:e.length?[{id:UID,nombre:'Analista de prueba',metricas}]:[]})
    }
    if(nombre==='citas_clientes_fn'){
      const citas=estado.tareas.filter(t=>t.tipo==='reunion')
      return json({version:1,desde:b.p_desde,hasta:b.p_hasta,generado_en:new Date().toISOString(),limite:b.p_limite,
        resumen:{total:citas.length,pendientes:citas.filter(t=>t.estado==='pendiente').length,entrevistas:citas.filter(t=>t.estado==='completada').length,
          no_asistio:citas.filter(t=>t.estado==='no_show').length,reprogramadas:citas.filter(t=>t.estado==='reprogramada').length,canceladas:citas.filter(t=>t.estado==='cancelada').length},
        items:citas.map(t=>({id:t.id,vence_en:t.vence_en,estado:t.estado,confirmada_en:t.confirmada_en,resultado_reunion:t.resultado_reunion,vendedor_id:UID,vendedor_nombre:'Analista de prueba',
          sujeto_tipo:'inversionista',sujeto_id:PERSONA_F5,sujeto_nombre:'ANA SINTÉTICA F5',inversionista_id:PERSONA_F5,perfil_id:null,identidad_visible:true})),hay_mas:false,siguiente_cursor:null})
    }
    if(nombre==='postventa_estado_fn')return json({version:1,habilitada:habilitada()})
    if(nombre==='postventa_agenda_fn')return json(habilitada()?estado.tareas.filter(t=>t.estado==='pendiente'):[])
    if(nombre==='postventa_ficha_fn')return estado.negarFicha
      ? json({code:'42501',message:'La postventa está fuera del ámbito vigente'},403)
      : json({version:1,habilitada:habilitada(),retiros:estado.retiros})
    if(nombre==='postventa_vencimientos_fn')return json({version:1,habilitada:habilitada(),pagina:b.p_pagina,tamano:25,total:1,filas:[{
      fuente_id:FUENTE_F5,inversionista_id:PERSONA_F5,empresa:'qorilazo',numero:'Vencimiento del ensayo',capital:1200,moneda:'PEN',vence_en:'2026-09-20',nombre:'ANA SINTÉTICA F5'}]})
    if(nombre==='postventa_operacion_estado_fn')return json({registrada:estado.recibos.has(b.p_clave)})
    if(nombre==='postventa_agendar_fn'){
      estado.altas++;estado.claves.push(b.p_clave)
      const t=tarea(b.p_clave,b.p_datos);estado.tareas.push(t);estado.recibos.add(b.p_clave)
      if(estado.cortar){estado.cortar=false;return route.abort('connectionreset')}
      return json({ok:true,tarea:t})
    }
    if(nombre==='postventa_tarea_fn'){
      if(b.p_accion==='confirmar'&&estado.rechazarConfirmacion)return json({code:'P0409',message:'La reunión cambió; recarga la agenda'},409)
      const t=estado.tareas.find(t=>t.id===b.p_tarea)!
      if(t.postventa_revision!==b.p_revision)return json({code:'P0409',message:'Tarea cambió'},409)
      t.postventa_revision++;let siguiente:Tarea|null=null
      if(b.p_accion==='cerrar'){
        estado.cierres.push(b.p_datos)
        estado.eventos.push({id:randomUUID(),origen:'postventa',sujeto_tipo:'inversionista',sujeto_id:PERSONA_F5,sujeto_nombre:'ANA SINTÉTICA F5',identidad_visible:true,
          inversionista_id:PERSONA_F5,perfil_id:null,lead_id:null,lead_nombre:null,lead_etapa:null,etapa_en_ese_momento:null,
          tipo:t.tipo==='reunion'&&b.p_datos.estado==='completada'?'reunion_realizada':t.tipo==='llamada'?(b.p_datos.resultado==='no_contesto'?'llamada_no_contestada':'llamada_realizada'):'nota',
          detalle:b.p_datos.detalle,metadata:{estado:b.p_datos.estado,resultado:b.p_datos.resultado,resultado_reunion:b.p_datos.resultado_reunion},
          creado_por:UID,autor_nombre:'Analista de prueba',creado_en:new Date().toISOString()})

        t.estado=b.p_datos.estado
        if(t.tipo==='reunion'&&t.estado==='completada')t.resultado_reunion=b.p_datos.resultado_reunion
        if(b.p_datos.siguiente){siguiente=tarea(randomUUID(),b.p_datos.siguiente);estado.tareas.push(siguiente)}
      }else if(b.p_accion==='reprogramar')t.vence_en=b.p_datos.vence_en
      else t.confirmada_en=new Date().toISOString()
      estado.recibos.add(b.p_clave);return json({ok:true,tarea:t,siguiente})
    }
    if(nombre==='postventa_veto_fn'){
      estado.vetada=b.p_vetar;estado.tareas.forEach(t=>{if(t.estado==='pendiente'&&estado.vetada)t.estado='cancelada'})
      estado.recibos.add(b.p_clave);return json({ok:true,no_contactar:estado.vetada})
    }
    if(nombre==='postventa_solicitar_retiro_fn'){
      const r:RetiroPostventa={id:b.p_clave,inversionista_id:PERSONA_F5,fuente_id:FUENTE_F5,empresa:'qorilazo',estado:'solicitada',motivo:b.p_motivo,resolucion:null,revision:1,creado_por:UID,revisado_por:null,creado_en:new Date().toISOString(),actualizado_en:new Date().toISOString()}
      estado.retiros.push(r);estado.recibos.add(b.p_clave);return json({ok:true,retiro:r})
    }
    if(nombre==='postventa_revisar_retiro_fn'){
      const r=estado.retiros.find(r=>r.id===b.p_retiro)!;r.estado=b.p_estado;r.resolucion=b.p_detalle;r.revision++
      estado.recibos.add(b.p_clave);return json({ok:true,retiro:r})
    }
    if(nombre==='preparar_inversion_fn'||nombre==='preparar_reinversion_fn'||nombre==='confirmar_inversion_revisada_fn')estado.financieras++
    return route.fallback()
  })
  await loginReal(page);await irAMiCartera(page)
  return estado
}
async function abrir(page:Page){await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click();await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeVisible()}
async function agendar(page:Page,titulo='Seguimiento F6'){
  await page.getByRole('button',{name:'Agendar gestión',exact:true}).click()
  await page.getByLabel('Gestión',{exact:true}).fill(titulo)
  await page.getByRole('button',{name:'Agendar gestión',exact:true}).click()
}

test('un fallo de ficha conserva postventa visible y bloquea nuevas acciones hasta recuperar',async({page})=>{
  const s=await montarF6(page,'gerencia');await abrir(page)
  s.fichaSinConexion=true
  await page.evaluate(()=>window.dispatchEvent(new Event('focus')))
  await expect(page.getByText(/Se conservan los últimos datos confirmados/)).toBeVisible({timeout:18000})
  for(const name of ['Agendar gestión','Cambiar responsable','Marcar No contactar']) {
    await expect(page.getByRole('button',{name,exact:true})).toBeDisabled()
  }
  s.fichaSinConexion=false
  await page.getByRole('button',{name:'Reintentar actualización'}).click()
  await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeEnabled()
  expect(s.altas).toBe(0);expect(s.financieras).toBe(0)
})

test('agenda compartida, cierre con siguiente y enlace persistente a la ficha',async({page},info)=>{
  const s=await montarF6(page);await abrir(page);await agendar(page)
  await expect(page.getByText('Gestión agendada · la verás en Hoy y en Agenda',{exact:true})).toBeVisible()
  expect(s.altas).toBe(1);expect(s.tareas[0]?.perfil_id).toBeNull();expect(s.tareas[0]?.lead_id).toBeNull()
  await page.keyboard.press('Escape');await page.getByRole('button',{name:'Agenda',exact:true}).click()
  await page.getByRole('button',{name:/^Todo ·/}).click()
  await page.getByRole('button',{name:'Cerrar tarea — Seguimiento F6'}).click()
  await expect(page.getByRole('button',{name:'Guardar gestión',exact:true})).toBeDisabled()
  await page.getByLabel('¿Qué pasó en la llamada?').selectOption('no_contesto')
  await page.getByLabel('Detalle de la gestión').fill('Cliente solicita revisar condiciones al vencimiento')
  await page.getByRole('checkbox',{name:'Programar el siguiente contacto'}).check()
  await page.getByLabel('Próxima gestión').fill('Segunda gestión F6')
  await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  await expect(page.getByRole('button',{name:'Cerrar tarea — Segunda gestión F6'})).toBeVisible()
  expect(s.tareas[0]?.estado).toBe('completada');expect(s.tareas).toHaveLength(2);expect(s.financieras).toBe(0)
  expect(s.cierres[0]?.resultado).toBe('no_contesto')
  await page.getByRole('button',{name:'Abrir ficha — Segunda gestión F6',exact:true}).click()
  await expect(page).toHaveURL(new RegExp(`#/mi-cartera/inversionista/${PERSONA_F5}$`))
  await expect(page.getByText('Información del cliente')).toBeVisible();await page.reload()
  await expect(page.getByText('Información del cliente')).toBeVisible()
  await expect(page.getByText(/Preparando tu espacio de trabajo/)).toBeHidden()
  await page.screenshot({path:info.outputPath('f6-ficha-desktop.png'),fullPage:true})
})
test('la cita de cliente realizada exige resultado y queda registrada como entrevista',async({page})=>{
  const s=await montarF6(page);await abrir(page);await agendar(page)
  await expect(page.getByText('Gestión agendada · la verás en Hoy y en Agenda',{exact:true})).toBeVisible()
  Object.assign(s.tareas[0]!,{tipo:'reunion',modalidad_reunion:'virtual'})
  await page.keyboard.press('Escape');await page.getByRole('button',{name:'Agenda',exact:true}).click();await page.reload()
  await page.getByRole('button',{name:/^Todo ·/}).click()
  await page.getByRole('button',{name:'Cerrar tarea — Seguimiento F6'}).click()
  await page.getByLabel('Resultado o siguiente acción').selectOption('confirmar')
  await expect(page.getByText('Esto confirma la cita prevista. Después deberás indicar si se realizó para registrar la entrevista.')).toBeVisible()
  await page.getByLabel('Resultado o siguiente acción').selectOption('completada')
  await expect(page.getByText('Al marcarla como realizada, la cita quedará registrada como entrevista.')).toBeVisible()
  await page.getByLabel('Resultado comercial de la entrevista').selectOption('seguimiento')
  await page.getByLabel('Detalle de la gestión').fill('Conversamos sobre la renovación')
  await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  await expect(page.getByText('Entrevista registrada. La agenda está actualizada.')).toBeVisible()
  expect(s.cierres[0]?.resultado_reunion).toBe('seguimiento')
  expect(s.tareas[0]?.resultado_reunion).toBe('seguimiento')
})
test('una llamada que agenda cita conserva ambos resultados en el cierre',async({page})=>{
  const s=await montarF6(page);await abrir(page);await agendar(page)
  await expect(page.getByText('Gestión agendada · la verás en Hoy y en Agenda',{exact:true})).toBeVisible()
  await page.keyboard.press('Escape');await page.getByRole('button',{name:'Agenda',exact:true}).click()
  await page.getByRole('button',{name:/^Todo ·/}).click()
  await page.getByRole('button',{name:'Cerrar tarea — Seguimiento F6'}).click()
  await page.getByLabel('¿Qué pasó en la llamada?').selectOption('agendo_reunion')
  await expect(page.getByRole('checkbox',{name:'Agenda la cita o llamada acordada'})).toBeChecked()
  await expect(page.getByLabel('Tipo de contacto')).toHaveValue('reunion')
  await page.getByLabel('Modalidad de la cita').selectOption('virtual')
  await page.getByLabel('Detalle de la gestión').fill('Acordamos revisar la renovación en persona')
  await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  await expect(page.getByText('Gestión registrada. La agenda está actualizada.')).toBeVisible()
  expect(s.cierres[0]?.resultado).toBe('agendo_reunion')
  expect((s.cierres[0]?.siguiente as {tipo:string})?.tipo).toBe('reunion')
  expect(s.tareas[1]?.tipo).toBe('reunion')
})
for (const vista of [{nombre:'escritorio',width:1280,height:900},{nombre:'móvil',width:390,height:844}]) {
  test(`${vista.nombre}: cerrar la entrevista desde Seguimiento conserva abierta la ficha`,async({page},info)=>{
    const s=await montarF6(page)
    await page.setViewportSize({width:vista.width,height:vista.height})
    if(vista.nombre==='móvil')await page.getByRole('button',{name:'Ocultar menú'}).click()
    await abrir(page);await agendar(page,'Cita de renovación')
    await expect(page.getByText('Gestión agendada · la verás en Hoy y en Agenda',{exact:true})).toBeVisible()
    Object.assign(s.tareas[0]!,{tipo:'reunion',modalidad_reunion:'virtual'})
    await page.reload()
    const cerrar=page.getByRole('button',{name:'Cerrar tarea — Cita de renovación',exact:true})
    await expect(cerrar).toBeEnabled()
    await expect(page.getByText(/Preparando tu espacio de trabajo/)).toBeHidden()
    await cerrar.scrollIntoViewIfNeeded()
    await page.screenshot({path:info.outputPath(`seguimiento-cierre-${vista.nombre}.png`),fullPage:true})
    await cerrar.click()
    await page.getByLabel('Resultado comercial de la entrevista').selectOption('seguimiento')
    await page.getByLabel('Detalle de la gestión').fill('Asistió y pidió revisar una propuesta de renovación')
    await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
    await expect(page.getByText('Entrevista registrada. La agenda está actualizada.')).toBeVisible()
    await expect(page.getByText('Sin acciones pendientes.',{exact:true})).toBeVisible()
    await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeVisible()
    await expect(cerrar).toHaveCount(0)
    expect(s.cierres[0]?.resultado_reunion).toBe('seguimiento')
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
  })
}
test('móvil: recupera un alta confirmada cuya respuesta se cortó sin duplicarla',async({page},info)=>{
  const s=await montarF6(page);await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:'Ocultar menú'}).click()
  await abrir(page);s.cortar=true;await agendar(page,'Gestión con respuesta interrumpida')
  await expect(page.getByRole('button',{name:'Verificar envío guardado'})).toBeVisible()
  await page.reload();await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeVisible()
  await page.getByRole('button',{name:'Agendar gestión',exact:true}).click()
  await expect(page.getByRole('dialog',{name:'Gestionar a ANA SINTÉTICA F5'}).getByText('Gestión con respuesta interrumpida',{exact:true})).toBeVisible()
  await expect(page.getByText(/Preparando tu espacio de trabajo/)).toBeHidden()
  await page.screenshot({path:info.outputPath('f6-movil-recuperacion.png'),fullPage:true})
  await page.getByRole('button',{name:'Verificar envío guardado'}).click()
  await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeVisible()
  expect(s.altas).toBe(1);expect(s.tareas).toHaveLength(1)
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
})
test('veto impide contacto, pero permite registrar un retiro recibido sin mover dinero',async({page})=>{
  const s=await montarF6(page);await abrir(page)
  await page.getByRole('button',{name:'Marcar No contactar',exact:true}).click()
  await page.getByLabel('Motivo, sin números de documento').fill('Solicitado por el cliente durante el ensayo')
  await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeDisabled()
  await page.getByRole('button',{name:'Registrar solicitud de retiro',exact:true}).click()
  await page.getByLabel('Detalle',{exact:true}).fill('Cliente solicita que Gerencia revise su retiro')
  await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  await expect(page.getByRole('button',{name:'Cancelar solicitud',exact:true})).toBeVisible()
  await expect(page.getByRole('button',{name:'Revisar solicitud',exact:true})).toHaveCount(0)
  expect(s.retiros).toHaveLength(1);expect(s.financieras).toBe(0)
})
test('Gerencia consulta vencimientos y revisa retiros; reinversión conserva origen',async({page},info)=>{
  const s=await montarF6(page,'gerencia')
  await page.getByRole('button',{name:'Ver vencimientos',exact:true}).click()
  await page.getByRole('button',{name:'Ver vencimiento de ANA SINTÉTICA F5 en Qorilazo'}).click()
  await page.getByRole('button',{name:'Reinvertir desde esta inversión',exact:true}).click()
  await expect(page.getByText(/Reinversión vinculada a una inversión anterior/)).toBeVisible()
  await expect(page.getByLabel('Capital en soles (PEN)')).toBeVisible()
  await page.getByRole('button',{name:'Cerrar y continuar después'}).click()
  await page.getByRole('button',{name:'Registrar solicitud de retiro',exact:true}).click()
  await page.getByLabel('Detalle',{exact:true}).fill('Solicitud sintética para revisión interna')
  await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  await page.getByRole('button',{name:'Revisar solicitud',exact:true}).click()
  await page.getByLabel('Detalle',{exact:true}).fill('Documentación recibida para la revisión')
  await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  await expect(page.getByText('Qorilazo · En revisión',{exact:true})).toBeVisible()
  expect(s.retiros[0]?.estado).toBe('en_revision');expect(s.financieras).toBe(0)
  await page.getByRole('button',{name:'Revisar solicitud',exact:true}).click()
  await expect(page.getByRole('dialog',{name:'Revisar solicitud de retiro',exact:true})).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('button',{name:'Revisar solicitud',exact:true})).toBeFocused()
  await page.getByRole('button',{name:'Revisar solicitud',exact:true}).focus()
  await page.keyboard.press('Enter')
  await page.getByLabel('Estado de la revisión',{exact:true}).selectOption('revisada')
  await page.getByLabel('Detalle',{exact:true}).fill('Resolución administrativa sin modificar capital ni pagos')
  await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  await expect(page.getByText('Qorilazo · Revisada',{exact:true})).toBeVisible()
  await expect(page.getByRole('button',{name:'Revisar solicitud',exact:true})).toHaveCount(0)
  const ficha=page.getByRole('dialog',{name:'ANA SINTÉTICA F5',exact:true})
  await expect(ficha).toBeFocused()
  await page.keyboard.press('Tab')
  await expect(ficha.getByRole('button',{name:'Cerrar ficha',exact:true}).first()).toBeFocused()
  expect(s.retiros[0]?.estado).toBe('revisada');expect(s.retiros[0]?.revision).toBe(3);expect(s.financieras).toBe(0)
  await expect(page.getByText(/Preparando tu espacio de trabajo/)).toBeHidden()
  await page.screenshot({path:info.outputPath('f6-retiro-gerencia.png'),fullPage:true})
})
test('Directorio no recibe acciones ni agenda neutral',async({page})=>{
  await montarF6(page,'directorio')
  await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
  await expect(page.getByText('Información del cliente')).toBeVisible()
  await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toHaveCount(0)
  await expect(page.getByRole('button',{name:'Registrar solicitud de retiro',exact:true})).toHaveCount(0)
  for(const name of ['Cambiar responsable','Marcar No contactar']) await expect(page.getByRole('button',{name,exact:true})).toHaveCount(0)
  await expect(page.getByRole('heading',{name:'Solicitudes de retiro'})).toHaveCount(0)
})
test('un rechazo al confirmar reunión neutral muestra el error y conserva la tarea',async({page})=>{
  const s=await montarF6(page);await abrir(page);await agendar(page)
  await expect(page.getByText('Gestión agendada · la verás en Hoy y en Agenda',{exact:true})).toBeVisible()
  Object.assign(s.tareas[0]!,{tipo:'reunion',modalidad_reunion:'virtual'})
  s.rechazarConfirmacion=true
  await page.keyboard.press('Escape');await page.getByRole('button',{name:'Agenda',exact:true}).click();await page.reload()
  await page.getByRole('button',{name:/^Todo ·/}).click()
  await page.getByRole('button',{name:'Marcar confirmada — Seguimiento F6',exact:true}).click()
  await expect(page.getByText(/se actualizó la vista con el estado del servidor|Sin conexión con el servidor/)).toBeVisible()
  await expect(page.getByRole('button',{name:'Marcar confirmada — Seguimiento F6',exact:true})).toBeVisible()
  expect(s.tareas[0]?.confirmada_en).toBeNull()
  await expect(page.getByText('Cita confirmada',{exact:true})).toHaveCount(0)
})
test('un rechazo de postventa no cierra una ficha F5 que sigue autorizada',async({page})=>{
  const s=await montarF6(page);s.negarFicha=true
  await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
  await expect(page.getByText('Ya no tienes acceso a esta información.',{exact:true})).toBeVisible()
  await expect(page.getByText('Información del cliente')).toBeVisible()
  await expect(page.getByRole('button',{name:'Registrar nueva inversión',exact:true})).toBeVisible()
  await expect(page.getByRole('button',{name:'Cerrar ficha',exact:true}).last()).toBeVisible()
})

test('el cierre de la ficha aparece con resultado en Resumen, Registro y Citas de gerencia',async({page},info)=>{
  const s=await montarF6(page,'gerencia');await abrir(page);await agendar(page,'Entrevista para renovar')
  Object.assign(s.tareas[0]!,{tipo:'reunion',modalidad_reunion:'virtual'})
  await page.reload()
  await page.getByRole('button',{name:'Cerrar tarea — Entrevista para renovar',exact:true}).click()
  await page.getByLabel('Resultado comercial de la entrevista').selectOption('propuesta')
  await page.getByLabel('Detalle de la gestión').fill('Entrevista realizada; propuesta de renovación enviada')
  await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  await expect(page.getByText('Entrevista registrada. La agenda está actualizada.')).toBeVisible()
  await page.evaluate(()=>{window.location.hash='#/hoy'})
  const resumen=page.getByRole('region',{name:'Gestión de leads y clientes',exact:true})
  await expect(resumen.getByRole('row',{name:'Clientes 0 0 1 1',exact:true})).toBeVisible()
  await resumen.getByRole('button',{name:'Ver gestiones',exact:true}).click()
  const registro=page.getByRole('dialog',{name:'Registro del día',exact:true})
  await expect(registro.getByText('Entrevista realizada; propuesta de renovación enviada',{exact:true})).toBeVisible()
  await expect(registro.getByRole('list').getByText('Entrevista realizada',{exact:true})).toBeVisible()
  await expect(registro.getByText('Propuesta presentada',{exact:true})).toBeVisible()
  await registro.getByRole('button',{name:'ANA SINTÉTICA F5',exact:true}).click()
  await expect(page.getByText('Información del cliente',{exact:true})).toBeVisible()
  await page.getByRole('button',{name:'Cerrar ficha',exact:true}).last().click()
  await page.getByRole('navigation').getByRole('button',{name:'Citas',exact:true}).click()
  const citas=page.getByRole('region',{name:'Citas de clientes',exact:true})
  await expect(citas.getByText('Entrevista realizada',{exact:true})).toBeVisible()
  await expect(citas.getByText('Propuesta presentada',{exact:true})).toBeVisible()
  await citas.screenshot({path:info.outputPath('citas-clientes-supervision.png')})
  expect(s.cierres).toHaveLength(1)
})
