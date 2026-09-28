import { expect, test, type Page } from '@playwright/test'
import { leadReal, loginReal, montarBackendReal, UID } from './_helpers'
import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'
import { idPendiente, paginaPendientes, tareaPendiente } from '../src/lib/gestion-diaria-pendientes.fixture'
import { fechaLima } from '../src/lib/agenda-derivada'

async function preparar(page: Page) {
  await page.setViewportSize({ width: 1512, height: 805 })
  const dia=fechaLima(Date.now()), analista=idPendiente(2)
  const lead=leadReal({ id:idPendiente(3),nombre_completo:'LEAD DE PENDIENTES',fueraDelBoot:true,asignado_supervisor_id:UID })
  await montarBackendReal(page,{rolCrm:'supervisor',leads:[lead],tareas:[]})
  const fila=filaEquipoPrueba({analista_id:analista,nombre_completo:'ANA H3',tareas_pendientes:55,tareas_vencidas:30})
  const estado={error:null as string|null,consultas:0,registro:0,equipo:0}
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn',route=>{
    estado.equipo++;return route.fulfill({json:{...diaEquipoPrueba([fila]),dia,supervisor_id:UID}})
  })
  await page.route('**/rest/v1/rpc/registro_actividad_fn',route=>{
    estado.registro++
    const items=Array.from({length:5},(_,i)=>({id:`actividad-${i}`,lead_id:lead.id,lead_nombre:lead.nombre_completo,
      lead_etapa:'nuevo',etapa_en_ese_momento:'nuevo',tipo:'llamada_realizada',detalle:`Gestión íntegra ${i}`,metadata:{},
      creado_por:analista,autor_nombre:'ANA H3',creado_en:`${dia}T15:0${5-i}:00Z`}))
    return route.fulfill({json:{version:1,zona:'America/Lima',desde:dia,hasta:dia,limite:26,generado_en:new Date().toISOString(),items}})
  })
  await page.route('**/rest/v1/rpc/gestion_diaria_pendientes_fn',route=>{
    estado.consultas++
    if(estado.error) return route.fulfill({status:estado.error==='42501'?403:400,json:{code:estado.error,message:'Error de prueba'}})
    const pedido=route.request().postDataJSON();expect(pedido.p_analista_id).toBe(analista)
    const todas=Array.from({length:55},(_,i)=>tareaPendiente(10+i,{vendedor_id:analista,
      vence_en:i<30?`${dia}T00:00:00Z`:`2099-01-01T00:00:00Z`,lead_id:lead.id,lead_nombre:lead.nombre_completo,
      ...(i===1?{referencia_tipo:'perfil',lead_id:null,lead_nombre:null}:i===2?{referencia_tipo:'postventa',lead_id:null,lead_nombre:null}:{}),
    }))
    const despues=pedido.p_despues_id?Number(pedido.p_despues_id.slice(-12)):0
    const posibles=todas.filter(t=>(!pedido.p_solo_vencidas||Number(t.id.slice(-12))<40)&&Number(t.id.slice(-12))>despues)
    const items=posibles.slice(0,25),ultimo=items.at(-1)!,hayMas=posibles.length>25,ahora=new Date().toISOString()
    return route.fulfill({json:paginaPendientes(items,{supervisor_id:UID,analista_id:analista,solo_vencidas:pedido.p_solo_vencidas,
      generado_en:ahora,pendientes_al:ahora,resumen:{tareas_pendientes:55,tareas_vencidas:30},hay_mas:hayMas,
      siguiente_cursor:hayMas?{despues_de:ultimo.vence_en,despues_id:ultimo.id}:null})})
  })
  await loginReal(page)
  await page.getByRole('button',{name:'Ocultar menú',exact:true}).click()
  await page.getByRole('button',{name:'Gestión Diaria',exact:true}).click()
  await page.mouse.move(900,90)
  await expect(page.locator('aside [data-splash-destino-visible]').first()).toHaveAttribute('data-splash-destino-visible','false')
  const vista=page.getByRole('region',{name:'Mi equipo hoy',exact:true})
  await vista.getByRole('button',{name:'Seleccionar a ANA H3'}).click()
  const panel=page.getByRole('region',{name:'Detalle de ANA H3',exact:true})
  return {estado,panel,vista,lead}
}

test('H3: últimas tres comparten Registro; pendientes conservan páginas, ficha, filtro y refresco',async({page},info)=>{
  const {estado,panel,vista,lead}=await preparar(page)
  const ultimas=panel.getByRole('region',{name:'Últimas gestiones del analista'})
  await expect(ultimas.getByRole('listitem')).toHaveCount(3)
  expect(estado.consultas).toBe(0)
  const lecturasRegistro=estado.registro
  await panel.getByRole('tab',{name:'Registro',exact:true}).click()
  const registro=panel.getByRole('region',{name:'Registro seleccionado'})
  await expect(registro.getByRole('listitem')).toHaveCount(5)
  expect(estado.registro).toBe(lecturasRegistro)
  await panel.getByRole('tab',{name:'Resumen',exact:true}).click()
  // Resumen del diseño (27/09): el cuadro Pendientes muestra el 55 y su acceso «Ver pendientes».
  await expect(panel.getByRole('term').filter({hasText:/^Pendientes$/}).locator('xpath=following-sibling::dd[1]')).toContainText('55')
  await panel.getByRole('button',{name:'Ver pendientes de ANA H3'}).click()
  const lista=panel.getByRole('list',{name:'Lista de tareas pendientes'})
  await expect(panel.getByRole('heading',{name:'Pendientes de ANA H3'})).toBeFocused()
  await expect(lista.getByRole('listitem')).toHaveCount(25)
  await expect(lista.getByText('Tarea de perfil')).toBeVisible()
  await expect(lista.getByText('Tarea de postventa')).toBeVisible()
  await page.screenshot({path:info.outputPath('h3-pendientes-escritorio.png')})
  await panel.getByRole('button',{name:'Ver más',exact:true}).click()
  await expect(lista.getByRole('listitem')).toHaveCount(50)
  const n=estado.consultas
  await panel.getByRole('tab',{name:'Registro',exact:true}).click()
  await panel.getByRole('tab',{name:'Pendientes',exact:true}).click()
  await expect(lista.getByRole('listitem')).toHaveCount(50);expect(estado.consultas).toBe(n)
  await panel.getByRole('button',{name:'Ampliar panel'}).click()
  const enlace=lista.getByRole('button',{name:lead.nombre_completo}).first()
  await enlace.click()
  await expect(page.getByRole('dialog',{name:lead.nombre_completo})).toBeVisible()
  await page.keyboard.press('Escape');await expect(enlace).toBeFocused()
  await expect(lista.getByRole('listitem')).toHaveCount(50)
  await panel.getByRole('button',{name:'Restaurar panel'}).click()
  await panel.getByRole('button',{name:'Ver más',exact:true}).click()
  await expect(lista.getByRole('listitem')).toHaveCount(55)
  await panel.getByRole('button',{name:/^Vencidas/}).click()
  await expect(lista.getByRole('listitem')).toHaveCount(25)
  await panel.getByRole('button',{name:'Ver más',exact:true}).click()
  await expect(lista.getByRole('listitem')).toHaveCount(30)
  await vista.getByRole('button',{name:'Actualizar',exact:true}).click()
  await expect(lista.getByRole('listitem')).toHaveCount(25)
  await expect(panel.getByRole('button',{name:/^Vencidas/})).toHaveAttribute('aria-pressed','true')
  await page.setViewportSize({width:390,height:844})
  await expect(page.getByRole('dialog',{name:'Detalle de ANA H3'})).toBeVisible()
  expect(await panel.evaluate(e=>e.scrollWidth<=e.clientWidth)).toBe(true)
  await panel.getByRole('heading',{name:'Pendientes de ANA H3'}).scrollIntoViewIfNeeded()
  await page.screenshot({path:info.outputPath('h3-pendientes-movil.png')})
})

for(const codigo of ['PGRST202','XX000','42501']) test(`H3: ${codigo} no se presenta como lista vacía`,async({page})=>{
  const {estado,panel}=await preparar(page)
  await panel.getByRole('tab',{name:'Pendientes',exact:true}).click()
  const lista=panel.getByRole('list',{name:'Lista de tareas pendientes'})
  await expect(lista.getByRole('listitem')).toHaveCount(25)
  estado.error=codigo
  await panel.getByRole('button',{name:'Ver más',exact:true}).click()
  await expect(panel.getByRole('alert')).toBeVisible()
  await expect(panel.getByText('Sin tareas pendientes.')).toHaveCount(0)
  if(codigo==='42501') {await expect(lista.getByRole('listitem')).toHaveCount(0);expect(estado.equipo).toBeGreaterThan(1)}
  else if(codigo==='XX000') {await expect(lista.getByRole('listitem')).toHaveCount(25);await expect(panel.getByText(/Datos anteriores/)).toBeVisible()}
  else await expect(panel.getByText(/Detalle de tareas no disponible/)).toBeVisible()
})
