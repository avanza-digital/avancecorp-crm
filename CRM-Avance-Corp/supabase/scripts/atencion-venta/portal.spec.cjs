// HTML y módulos reales del portal; auth y transporte sintéticos. Sin red externa.
const {test,expect}=require('../../../app/node_modules/@playwright/test')
const {readFile}=require('node:fs/promises')
const path=require('node:path')
const portal=process.env.ATENCION_PORTAL_DIR || path.resolve(__dirname,'../../../../public_html')
test('portal revisa, invalida al editar y confirma por la misma puerta sin UPDATE directo',async({page})=>{
  const llamadas=[],ediciones=[]
  await page.addInitScript(()=>localStorage.setItem('sb-banco-atencion','sintetico'))
  let intento=0
  const previa={accion:'atencion_cliente',id:'cliente',destino:'jorge',version:'vista-1',anterior_nombre:'Fiorella',destino_nombre:'Jorge',aviso:'La venta conserva su dueño.',leads:2,tareas:3,efectos:[]}
  await page.route('**/*',async route=>{
    const u=new URL(route.request().url())
    if(u.host!=='portal.test') return route.abort()
    if(u.pathname==='/patch') {
      ediciones.push(route.request().postDataJSON())
      return route.fulfill({json:{data:null,error:null}})
    }
    if(u.pathname==='/rpc'){
      const body=route.request().postDataJSON();llamadas.push(body)
      if(body.nombre==='cuentas_bancarias_cliente_fn')return route.fulfill({json:{data:[],error:null}})
      if(body.nombre==='previsualizar_cambio_responsabilidad_fn')return route.fulfill({json:{data:previa,error:null}})
      if(body.nombre==='confirmar_cambio_responsabilidad_fn'){
        intento++
        return route.fulfill({json:intento===1?{data:null,error:{code:'PT409',message:'La información cambió. Revisa de nuevo.'}}:{data:{ok:true,version_confirmada:'vista-1'},error:null}})
      }
      throw Error('RPC inesperada: '+body.nombre)
    }
    let body
    if(u.pathname==='/js/supabase.js') body=`
      const cliente={id:'cliente',nombre_completo:'CLIENTE SINTETICO',correo:'cliente@example.test',activo:true,asesor_perfil_id:'fiorella',asesor_id:'asesor-legado'};
      const miembros=[{id:'fiorella',nombre_completo:'Fiorella',activo:true},{id:'jorge',nombre_completo:'Jorge',activo:true}];
      export const supabase={schema:n=>{if(n!=='crm')throw Error('Schema inesperado');return {rpc:async(nombre,args)=>fetch('/rpc',{method:'POST',body:JSON.stringify({nombre,args})}).then(r=>r.json())}},from:tabla=>{
        let listado=false,escritura=null;const q=new Proxy({},{get:(_,k)=>{
          if(k==='then')return resolve=>escritura?escritura.then(resolve):Promise.resolve(resolve({data:tabla==='perfiles'?(listado?[cliente]:miembros):[],count:1,error:null}));
          if(k==='update')return payload=>{if(tabla!=='perfiles')throw Error('Tabla inesperada');escritura=fetch('/patch',{method:'POST',body:JSON.stringify(payload)}).then(r=>r.json());return q;};
          if(['insert','delete'].includes(k))throw Error('Escritura directa prohibida');
          return (...args)=>{if(k==='eq'&&args[0]==='rol')listado=true;return q;};
        }});return q;
      }};`
    else if(u.pathname==='/js/auth.js') body=`export const verificarGestorCartera=async()=>({rol:'admin'});`
    else if(u.pathname==='/js/admin/_helpers.js') body=`
      export const formatearFecha=()=>'';export const escapeHtml=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
      export const setText=(id,t)=>{const e=document.getElementById(id);if(e)e.textContent=t};
      export const setupAdminShell=async({perfil})=>perfil;export const mostrarError=console.error;
      export const mostrarExito=t=>{document.body.dataset.exito=t};export const quitarSkeletons=()=>{};`
    else if(u.pathname==='/js/mobile-menu.js') body='export const initMobileMenu=()=>{};'
    else {
      try{body=await readFile(path.join(portal,u.pathname))}catch{return route.fulfill({status:404,body:''})}
    }
    const ext=path.extname(u.pathname)
    return route.fulfill({body,contentType:({'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml'})[ext]||'application/octet-stream'})
  })
  await page.goto('http://portal.test/admin/clientes.html')
  await page.locator('[data-action="asignar"]').click()
  await page.locator('#asg_asesor').selectOption('jorge')
  await page.locator('#asg_motivo').fill('Cambio por continuidad de atención')
  await page.getByRole('button',{name:'Revisar efecto',exact:true}).click()
  await expect(page.locator('#asg_previa')).toContainText('Fiorella → Jorge')
  expect(llamadas.map(x=>x.nombre)).toEqual(['previsualizar_cambio_responsabilidad_fn'])
  await page.locator('#asg_motivo').fill('Motivo definitivo de la atención')
  await expect(page.locator('#asg_previa')).toBeEmpty()
  await page.getByRole('button',{name:'Revisar efecto',exact:true}).click()
  await page.getByRole('button',{name:'Confirmar cambio de atención',exact:true}).click()
  await expect(page.locator('#modalAsignarError')).toContainText('Revisa de nuevo')
  await expect(page.getByRole('button',{name:'Revisar efecto',exact:true})).toBeVisible()
  await page.getByRole('button',{name:'Revisar efecto',exact:true}).click()
  await page.getByRole('button',{name:'Confirmar cambio de atención',exact:true}).click()
  await expect(page.locator('#modalAsignarAsesor')).toBeHidden()
  const confirmaciones=llamadas.filter(x=>x.nombre==='confirmar_cambio_responsabilidad_fn')
  expect(confirmaciones).toHaveLength(2)
  expect(confirmaciones[1].args).toEqual({p_accion:'atencion_cliente',p_id:'cliente',p_destino:'jorge',p_motivo:'Motivo definitivo de la atención',p_version:'vista-1'})
  expect(ediciones).toHaveLength(0)
  await page.locator('[data-action="editar"]').click()
  await page.locator('#e_telefono').fill('999888777')
  await page.locator('#btnGuardarEditar').click()
  await expect(page.locator('#modalEditar')).toBeHidden()
  expect(ediciones).toHaveLength(1)
  expect(ediciones[0]).toEqual({telefono:'999888777',actualizado_en:expect.any(String)})
})
