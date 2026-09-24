# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: f6-postventa.spec.ts >> un fallo de ficha conserva postventa visible y bloquea nuevas acciones hasta recuperar
- Location: e2e/f6-postventa.spec.ts:83:1

# Error details

```
Error: expect(locator).toBeVisible() failed

Locator: getByText(/Se conservan los últimos datos confirmados/)
Expected: visible
Timeout: 18000ms
Error: element(s) not found

Call log:
  - Expect "toBeVisible" with timeout 18000ms
  - waiting for getByText(/Se conservan los últimos datos confirmados/)

```

```yaml
- complementary:
  - img "Avance Corp"
  - paragraph: Avance Corp
  - paragraph: CRM Comercial
  - button "Ocultar menú" [expanded]
  - navigation:
    - group "Dirección":
      - paragraph: Dirección
      - button "Resumen"
      - button "Ranking"
      - button "Rendimiento"
      - button "Conversiones"
      - button "Citas"
      - button "Facturación"
      - button "Empresas"
    - group "Operación":
      - paragraph: Operación
      - button "Seguimiento"
      - button "Gestión Diaria"
      - button "Pipeline"
      - button "Leads"
      - button "Agenda"
      - button "Cartera"
      - button "Repartir leads"
      - button "Base para gestión"
      - button "Gestión de equipo"
    - group "Administración":
      - paragraph: Administración
      - button "Metas"
      - button "Configuración"
  - paragraph: Gerente Real
  - paragraph: Gerencia
  - button "Cerrar sesión"
- main:
  - heading "Cartera" [level=1]
  - paragraph: Tus clientes y el capital invertido
  - combobox "Buscar lead por nombre, teléfono o DNI"
  - text: /
  - status
  - button "Abrir ayuda del analista": Ayuda
  - link "Abrir pendientes":
    - /url: "#/alertas"
  - button "Nuevo lead"
  - heading "Cartera de inversionistas" [level=2]
  - paragraph: Una ficha por persona, con sus inversiones en cada empresa.
  - button "Actualizar cartera"
  - button "Nuevo cliente"
  - text: Buscar persona
  - searchbox "Buscar persona"
  - text: Mes de cierre comercial
  - combobox "Mes de cierre comercial":
    - option "Todos"
    - option "Sep. 2026" [selected]
    - option "Ago. 2026"
    - option "Sin fecha"
  - text: Empresa
  - combobox "Empresa":
    - option "Todas" [selected]
    - option "Avance"
    - option "Qorilazo"
    - option "Prodelco"
  - button "Más filtros"
  - paragraph: El mes corresponde al cierre comercial. La ficha conserva el historial completo.
  - button "Limpiar filtros"
  - term: Qorilazo · PEN
  - definition: S/ 1,200
  - definition: Capital registrado · 1 inversión
  - status: 1 persona · página 1
  - text: Por página
  - combobox "Por página":
    - option "10"
    - option "25" [selected]
    - option "50"
  - list:
    - listitem:
      - button "Abrir ficha de ANA SINTÉTICA F5": "ANA SINTÉTICA F5 DNI 93334444 Qorilazo Capital registrado según los filtros: Qorilazo · PEN S/ 1,200 Último cierre: 01 set. 2026 Responsable actual: ANALISTA F5"
  - navigation "Paginación de inversionistas":
    - paragraph: Página 1 de 1 · 1 registros
    - button "Anterior" [disabled]
    - button "Siguiente" [disabled]
  - heading "Vencimientos" [level=3]
  - button "Ver vencimientos"
- region "Notifications alt+T"
- dialog "Ficha del inversionista":
  - heading "Ficha del inversionista" [level=2]
  - button "Cerrar ficha"
  - paragraph: No se pudo recibir la respuesta del servidor. Comprueba tu conexión.
  - paragraph: Revisa tu conexión y vuelve a intentarlo — tu sesión sigue activa.
  - button "Reintentar"
```

# Test source

```ts
  1   | import {expect,test,type Page} from '@playwright/test'
  2   | import {randomUUID} from 'node:crypto'
  3   | import {loginReal,montarBackendReal,irAMiCartera,UID} from './_helpers'
  4   | import {carteraF5,fichaF5,PERSONA_F5,FUENTE_F5} from '../src/test/fixtures/f5'
  5   | import type {Tarea} from '../src/lib/tipos'
  6   | import type {RetiroPostventa} from '../src/lib/postventa'
  7   | 
  8   | async function montarF6(page:Page,rol:'vendedor'|'gerencia'|'directorio'='vendedor') {
  9   |   await montarBackendReal(page,{rolCrm:rol,rolPortal:rol==='directorio'?'directorio':'analista',clientes:[],contratos:[]})
  10  |   const estado={on:true,vetada:false,cortar:false,rechazarConfirmacion:false,negarFicha:false,fichaSinConexion:false,altas:0,financieras:0,claves:[] as string[],tareas:[] as Tarea[],retiros:[] as RetiroPostventa[],recibos:new Set<string>()}
  11  |   const habilitada=()=>estado.on&&rol!=='directorio'
  12  |   function tarea(id:string,datos:Record<string,unknown>):Tarea {
  13  |     return {id,inversionista_id:PERSONA_F5,inversionista_canonico_id:PERSONA_F5,postventa_revision:1,
  14  |       lead_id:null,perfil_id:null,vendedor_id:UID,asignado_supervisor_id:null,tipo:'llamada',titulo:'Seguimiento F6',
  15  |       nota:null,vence_en:new Date(Date.now()+86400000).toISOString(),duracion_min:null,estado:'pendiente',
  16  |       modalidad_reunion:null,ubicacion_reunion:null,enlace_reunion:null,resultado_reunion:null,motivo_no_realizada:null,
  17  |       detalle_cierre_reunion:null,confirmada_en:null,reagendada_de:null,reprogramaciones:0,activo:true,creado_en:new Date().toISOString(),...datos}
  18  |   }
  19  |   await page.route('**/rest/v1/rpc/*',async route=>{
  20  |     const nombre=new URL(route.request().url()).pathname.split('/').at(-1)
  21  |     const b=route.request().postDataJSON()??{}
  22  |     const json=(data:unknown,status=200)=>route.fulfill({status,json:data})
  23  |     if(nombre==='cartera_inversionistas_estado_fn')return json({version:1,habilitada:true,escritura_habilitada:rol!=='directorio',motivo:null})
  24  |     if(nombre==='cartera_inversionistas_filtrada_fn')return json({...carteraF5,pagina:b.p_pagina,tamano:b.p_tamano})
  25  |     if(nombre==='inversionista_ficha_fn'){
  26  |       if(estado.fichaSinConexion)return json({message:'Interrupción temporal'},503)
  27  |       const f=structuredClone(fichaF5); f.persona.responsable_id=UID;f.persona.no_contactar=estado.vetada
  28  |       f.capacidades.postventa=habilitada();f.capacidades.contactar=habilitada()&&!estado.vetada
  29  |       f.capacidades.nueva_inversion=habilitada()&&!estado.vetada;f.tareas=estado.tareas.filter(t=>t.estado==='pendiente');f.tareas_total=f.tareas.length
  30  |       return json(f)
  31  |     }
  32  |     if(nombre==='postventa_estado_fn')return json({version:1,habilitada:habilitada()})
  33  |     if(nombre==='postventa_agenda_fn')return json(habilitada()?estado.tareas.filter(t=>t.estado==='pendiente'):[])
  34  |     if(nombre==='postventa_ficha_fn')return estado.negarFicha
  35  |       ? json({code:'42501',message:'La postventa está fuera del ámbito vigente'},403)
  36  |       : json({version:1,habilitada:habilitada(),retiros:estado.retiros})
  37  |     if(nombre==='postventa_vencimientos_fn')return json({version:1,habilitada:habilitada(),pagina:b.p_pagina,tamano:25,total:1,filas:[{
  38  |       fuente_id:FUENTE_F5,inversionista_id:PERSONA_F5,empresa:'qorilazo',numero:'Vencimiento del ensayo',capital:1200,moneda:'PEN',vence_en:'2026-09-20',nombre:'ANA SINTÉTICA F5'}]})
  39  |     if(nombre==='postventa_operacion_estado_fn')return json({registrada:estado.recibos.has(b.p_clave)})
  40  |     if(nombre==='postventa_agendar_fn'){
  41  |       estado.altas++;estado.claves.push(b.p_clave)
  42  |       const t=tarea(b.p_clave,b.p_datos);estado.tareas.push(t);estado.recibos.add(b.p_clave)
  43  |       if(estado.cortar){estado.cortar=false;return route.abort('connectionreset')}
  44  |       return json({ok:true,tarea:t})
  45  |     }
  46  |     if(nombre==='postventa_tarea_fn'){
  47  |       if(b.p_accion==='confirmar'&&estado.rechazarConfirmacion)return json({code:'P0409',message:'La reunión cambió; recarga la agenda'},409)
  48  |       const t=estado.tareas.find(t=>t.id===b.p_tarea)!
  49  |       if(t.postventa_revision!==b.p_revision)return json({code:'P0409',message:'Tarea cambió'},409)
  50  |       t.postventa_revision++;let siguiente:Tarea|null=null
  51  |       if(b.p_accion==='cerrar'){
  52  |         t.estado=b.p_datos.estado
  53  |         if(b.p_datos.siguiente){siguiente=tarea(randomUUID(),b.p_datos.siguiente);estado.tareas.push(siguiente)}
  54  |       }else if(b.p_accion==='reprogramar')t.vence_en=b.p_datos.vence_en
  55  |       else t.confirmada_en=new Date().toISOString()
  56  |       estado.recibos.add(b.p_clave);return json({ok:true,tarea:t,siguiente})
  57  |     }
  58  |     if(nombre==='postventa_veto_fn'){
  59  |       estado.vetada=b.p_vetar;estado.tareas.forEach(t=>{if(t.estado==='pendiente'&&estado.vetada)t.estado='cancelada'})
  60  |       estado.recibos.add(b.p_clave);return json({ok:true,no_contactar:estado.vetada})
  61  |     }
  62  |     if(nombre==='postventa_solicitar_retiro_fn'){
  63  |       const r:RetiroPostventa={id:b.p_clave,inversionista_id:PERSONA_F5,fuente_id:FUENTE_F5,empresa:'qorilazo',estado:'solicitada',motivo:b.p_motivo,resolucion:null,revision:1,creado_por:UID,revisado_por:null,creado_en:new Date().toISOString(),actualizado_en:new Date().toISOString()}
  64  |       estado.retiros.push(r);estado.recibos.add(b.p_clave);return json({ok:true,retiro:r})
  65  |     }
  66  |     if(nombre==='postventa_revisar_retiro_fn'){
  67  |       const r=estado.retiros.find(r=>r.id===b.p_retiro)!;r.estado=b.p_estado;r.resolucion=b.p_detalle;r.revision++
  68  |       estado.recibos.add(b.p_clave);return json({ok:true,retiro:r})
  69  |     }
  70  |     if(nombre==='preparar_inversion_fn'||nombre==='preparar_reinversion_fn'||nombre==='confirmar_inversion_revisada_fn')estado.financieras++
  71  |     return route.fallback()
  72  |   })
  73  |   await loginReal(page);await irAMiCartera(page)
  74  |   return estado
  75  | }
  76  | async function abrir(page:Page){await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click();await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeVisible()}
  77  | async function agendar(page:Page,titulo='Seguimiento F6'){
  78  |   await page.getByRole('button',{name:'Agendar gestión',exact:true}).click()
  79  |   await page.getByLabel('Gestión',{exact:true}).fill(titulo)
  80  |   await page.getByRole('button',{name:'Agendar gestión',exact:true}).click()
  81  | }
  82  | 
  83  | test('un fallo de ficha conserva postventa visible y bloquea nuevas acciones hasta recuperar',async({page})=>{
  84  |   const s=await montarF6(page,'gerencia');await abrir(page)
  85  |   s.fichaSinConexion=true
  86  |   await page.evaluate(()=>window.dispatchEvent(new Event('focus')))
> 87  |   await expect(page.getByText(/Se conservan los últimos datos confirmados/)).toBeVisible({timeout:18000})
      |                                                                              ^ Error: expect(locator).toBeVisible() failed
  88  |   for(const name of ['Agendar gestión','Cambiar responsable','Marcar No contactar']) {
  89  |     await expect(page.getByRole('button',{name,exact:true})).toBeDisabled()
  90  |   }
  91  |   s.fichaSinConexion=false
  92  |   await page.getByRole('button',{name:'Reintentar actualización'}).click()
  93  |   await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeEnabled()
  94  |   expect(s.altas).toBe(0);expect(s.financieras).toBe(0)
  95  | })
  96  | 
  97  | test('agenda compartida, cierre con siguiente y enlace persistente a la ficha',async({page},info)=>{
  98  |   const s=await montarF6(page);await abrir(page);await agendar(page)
  99  |   await expect(page.getByText('Gestión agendada · la verás en Hoy y en Agenda',{exact:true})).toBeVisible()
  100 |   expect(s.altas).toBe(1);expect(s.tareas[0]?.perfil_id).toBeNull();expect(s.tareas[0]?.lead_id).toBeNull()
  101 |   await page.keyboard.press('Escape');await page.getByRole('button',{name:'Agenda',exact:true}).click()
  102 |   await page.getByRole('button',{name:/^Todo ·/}).click()
  103 |   await page.getByRole('button',{name:'Cerrar tarea — Seguimiento F6'}).click()
  104 |   await page.getByLabel('Detalle de la gestión').fill('Cliente solicita revisar condiciones al vencimiento')
  105 |   await page.getByRole('checkbox',{name:'Programar el siguiente contacto'}).check()
  106 |   await page.getByLabel('Próxima gestión').fill('Segunda gestión F6')
  107 |   await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  108 |   await expect(page.getByRole('button',{name:'Cerrar tarea — Segunda gestión F6'})).toBeVisible()
  109 |   expect(s.tareas[0]?.estado).toBe('completada');expect(s.tareas).toHaveLength(2);expect(s.financieras).toBe(0)
  110 |   await page.getByRole('button',{name:'Abrir ficha — Segunda gestión F6',exact:true}).click()
  111 |   await expect(page).toHaveURL(new RegExp(`#/mi-cartera/inversionista/${PERSONA_F5}$`))
  112 |   await expect(page.getByText('Información del cliente')).toBeVisible();await page.reload()
  113 |   await expect(page.getByText('Información del cliente')).toBeVisible()
  114 |   await expect(page.getByText(/Preparando tu espacio de trabajo/)).toBeHidden()
  115 |   await page.screenshot({path:info.outputPath('f6-ficha-desktop.png'),fullPage:true})
  116 | })
  117 | test('móvil: recupera un alta confirmada cuya respuesta se cortó sin duplicarla',async({page},info)=>{
  118 |   const s=await montarF6(page);await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:'Ocultar menú'}).click()
  119 |   await abrir(page);s.cortar=true;await agendar(page,'Gestión con respuesta interrumpida')
  120 |   await expect(page.getByRole('button',{name:'Verificar envío guardado'})).toBeVisible()
  121 |   await page.reload();await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeVisible()
  122 |   await page.getByRole('button',{name:'Agendar gestión',exact:true}).click()
  123 |   await expect(page.getByRole('dialog',{name:'Gestionar a ANA SINTÉTICA F5'}).getByText('Gestión con respuesta interrumpida',{exact:true})).toBeVisible()
  124 |   await expect(page.getByText(/Preparando tu espacio de trabajo/)).toBeHidden()
  125 |   await page.screenshot({path:info.outputPath('f6-movil-recuperacion.png'),fullPage:true})
  126 |   await page.getByRole('button',{name:'Verificar envío guardado'}).click()
  127 |   await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeVisible()
  128 |   expect(s.altas).toBe(1);expect(s.tareas).toHaveLength(1)
  129 |   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
  130 | })
  131 | test('veto impide contacto, pero permite registrar un retiro recibido sin mover dinero',async({page})=>{
  132 |   const s=await montarF6(page);await abrir(page)
  133 |   await page.getByRole('button',{name:'Marcar No contactar',exact:true}).click()
  134 |   await page.getByLabel('Motivo, sin números de documento').fill('Solicitado por el cliente durante el ensayo')
  135 |   await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  136 |   await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toBeDisabled()
  137 |   await page.getByRole('button',{name:'Registrar solicitud de retiro',exact:true}).click()
  138 |   await page.getByLabel('Detalle',{exact:true}).fill('Cliente solicita que Gerencia revise su retiro')
  139 |   await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  140 |   await expect(page.getByRole('button',{name:'Cancelar solicitud',exact:true})).toBeVisible()
  141 |   await expect(page.getByRole('button',{name:'Revisar solicitud',exact:true})).toHaveCount(0)
  142 |   expect(s.retiros).toHaveLength(1);expect(s.financieras).toBe(0)
  143 | })
  144 | test('Gerencia consulta vencimientos y revisa retiros; reinversión conserva origen',async({page},info)=>{
  145 |   const s=await montarF6(page,'gerencia')
  146 |   await page.getByRole('button',{name:'Ver vencimientos',exact:true}).click()
  147 |   await page.getByRole('button',{name:'Ver vencimiento de ANA SINTÉTICA F5 en Qorilazo'}).click()
  148 |   await page.getByRole('button',{name:'Reinvertir desde esta inversión',exact:true}).click()
  149 |   await expect(page.getByText(/Reinversión vinculada a una inversión anterior/)).toBeVisible()
  150 |   await expect(page.getByLabel('Capital en soles (PEN)')).toBeVisible()
  151 |   await page.getByRole('button',{name:'Cerrar y continuar después'}).click()
  152 |   await page.getByRole('button',{name:'Registrar solicitud de retiro',exact:true}).click()
  153 |   await page.getByLabel('Detalle',{exact:true}).fill('Solicitud sintética para revisión interna')
  154 |   await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  155 |   await page.getByRole('button',{name:'Revisar solicitud',exact:true}).click()
  156 |   await page.getByLabel('Detalle',{exact:true}).fill('Documentación recibida para la revisión')
  157 |   await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  158 |   await expect(page.getByText('Qorilazo · En revisión',{exact:true})).toBeVisible()
  159 |   expect(s.retiros[0]?.estado).toBe('en_revision');expect(s.financieras).toBe(0)
  160 |   await page.getByRole('button',{name:'Revisar solicitud',exact:true}).click()
  161 |   await expect(page.getByRole('dialog',{name:'Revisar solicitud de retiro',exact:true})).toBeVisible()
  162 |   await page.keyboard.press('Escape')
  163 |   await expect(page.getByRole('button',{name:'Revisar solicitud',exact:true})).toBeFocused()
  164 |   await page.getByRole('button',{name:'Revisar solicitud',exact:true}).focus()
  165 |   await page.keyboard.press('Enter')
  166 |   await page.getByLabel('Estado de la revisión',{exact:true}).selectOption('revisada')
  167 |   await page.getByLabel('Detalle',{exact:true}).fill('Resolución administrativa sin modificar capital ni pagos')
  168 |   await page.getByRole('button',{name:'Guardar gestión',exact:true}).click()
  169 |   await expect(page.getByText('Qorilazo · Revisada',{exact:true})).toBeVisible()
  170 |   await expect(page.getByRole('button',{name:'Revisar solicitud',exact:true})).toHaveCount(0)
  171 |   const ficha=page.getByRole('dialog',{name:'ANA SINTÉTICA F5',exact:true})
  172 |   await expect(ficha).toBeFocused()
  173 |   await page.keyboard.press('Tab')
  174 |   await expect(ficha.getByRole('button',{name:'Cerrar ficha',exact:true}).first()).toBeFocused()
  175 |   expect(s.retiros[0]?.estado).toBe('revisada');expect(s.retiros[0]?.revision).toBe(3);expect(s.financieras).toBe(0)
  176 |   await expect(page.getByText(/Preparando tu espacio de trabajo/)).toBeHidden()
  177 |   await page.screenshot({path:info.outputPath('f6-retiro-gerencia.png'),fullPage:true})
  178 | })
  179 | test('Directorio no recibe acciones ni agenda neutral',async({page})=>{
  180 |   await montarF6(page,'directorio')
  181 |   await page.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}).click()
  182 |   await expect(page.getByText('Información del cliente')).toBeVisible()
  183 |   await expect(page.getByRole('button',{name:'Agendar gestión',exact:true})).toHaveCount(0)
  184 |   await expect(page.getByRole('button',{name:'Registrar solicitud de retiro',exact:true})).toHaveCount(0)
  185 |   for(const name of ['Cambiar responsable','Marcar No contactar']) await expect(page.getByRole('button',{name,exact:true})).toHaveCount(0)
  186 |   await expect(page.getByRole('heading',{name:'Solicitudes de retiro'})).toHaveCount(0)
  187 | })
```