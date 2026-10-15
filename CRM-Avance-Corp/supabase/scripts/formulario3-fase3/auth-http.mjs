// Pruebas con Auth y HTTP reales. Destino cerrado a la rama autorizada.
import { readFileSync, writeFileSync, existsSync, chmodSync } from 'node:fs'
import { randomBytes } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'
import assert from 'node:assert/strict'

const privado='/private/tmp/formulario3-fase3-privado/'
export const ref='bxkborlvpmuwttzjrjqn'
const entorno=JSON.parse(readFileSync(privado+'branch.json','utf8'))
export const url='https://'+ref+'.supabase.co'
assert.equal(entorno.SUPABASE_URL,url,'Solo rama temporal autorizada')
const anon=entorno.SUPABASE_ANON_KEY
const servicio=entorno.SUPABASE_SERVICE_ROLE_KEY
const secreto=readFileSync(privado+'importar.env','utf8').trim().split('=')[1]
assert.match(secreto,/^[0-9a-f]{64}$/)
const opciones={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}}
const admin=createClient(url,servicio,opciones)
const guardarPrivado=(f,d)=>{writeFileSync(privado+f,JSON.stringify(d,null,2),{mode:0o600});chmodSync(privado+f,0o600)}
const usuariosPath=privado+'usuarios.json'
export const usuarios=existsSync(usuariosPath)?JSON.parse(readFileSync(usuariosPath,'utf8')):{}
export const evidencia=[]
function ok(nombre,datos={}){evidencia.push({nombre,estado:'PASS',...datos});console.log('PASS: '+nombre)}
function grabar(){writeFileSync(new URL('./http-'+process.argv[2]+'.json',import.meta.url),JSON.stringify(evidencia,null,2)+'\n')}

export async function sesion(rol){
  const u=usuarios[rol];assert.ok(u,'Fixture creada: '+rol)
  const cliente=createClient(url,anon,opciones)
  const {data,error}=await cliente.auth.signInWithPassword({email:u.email,password:u.password})
  assert.equal(error,null,'Auth real: '+rol+(error?' '+error.message:''))
  assert.equal(data.user.id,u.id)
  return {cliente,session:data.session}
}

export async function importar(filas,{jwt=true,secret=true}={}){
  const headers={'Content-Type':'application/json'}
  if(jwt)headers.Authorization='Bearer '+anon
  if(secret)headers['x-importar-secret']=secreto
  const respuesta=await fetch(url+'/functions/v1/crm-importar-leads',{method:'POST',headers,body:JSON.stringify({filas}),signal:AbortSignal.timeout(45000)})
  return {status:respuesta.status,body:await respuesta.json()}
}

async function crear(){
  for(const [i,rol] of ['vendedor','gerencia','supervisor','vendedor_otro','supervisor_otro','coordinador','inactivo','directorio'].entries()){
    if(usuarios[rol]){assert.match(usuarios[rol].email,/@pruebas\.invalid$/);continue}
    const email='f3_'+rol+'_20261014@pruebas.invalid'
    const password=randomBytes(24).toString('base64url')+'aA8!'
    const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{nombre_completo:'PRUEBA F3 '+rol}})
    assert.equal(error,null,'Crear usuario ficticio '+rol+(error?' '+error.message:''))
    usuarios[rol]={id:data.user.id,email,password,dni:String(49430091+i)}
    guardarPrivado('usuarios.json',usuarios)
    ok('Auth creó '+rol+' sin enviar correo')
  }
  writeFileSync(new URL('./usuarios-sinteticos.json',import.meta.url),JSON.stringify(Object.fromEntries(Object.entries(usuarios).map(([rol,{password,...resto}])=>[rol,resto])),null,2)+'\n')
}

async function frontera(){
  assert.equal((await importar([],{jwt:false})).status,401);ok('Gateway rechaza solicitud sin JWT')
  assert.equal((await importar([],{secret:false})).status,401);ok('Importador rechaza solicitud sin secreto')
  assert.equal((await importar([])).status,400);ok('Dos capas de autenticación válidas llegan a validación de filas')
}

async function permisos(){
  const filas=[
    {fila:11,nombre:'PRUEBA F3 Rol Legacy',telefono:'984300011',vendedor_correo:usuarios.vendedor.email},
    {fila:12,nombre:'PRUEBA F3 Rol Campaña',telefono:'984300012',vendedor_correo:usuarios.vendedor.email,campania_origen:'Formulario 3'},
    {fila:13,nombre:'PRUEBA F3 Rol Otro',telefono:'984300013',vendedor_correo:usuarios.vendedor_otro.email,campania_origen:'Formulario 3'},
  ].map(f=>({capital:'5000',moneda:'PEN',canal:'FORMULARIO',autorizo:'SI',fuente_consentimiento:'Prueba aislada F3',...f}))
  const alta=await importar(filas)
  assert.equal(alta.status,200);assert.equal(alta.body.resultados.length,3)
  assert.ok(alta.body.resultados.every(x=>['importado','duplicado'].includes(x.resultado)),JSON.stringify(alta.body))
  ok('HTTP real acepta campaña y envíos antiguos',{resultados:alta.body.resultados})
  const sesiones={}
  for(const rol of Object.keys(usuarios)){
    sesiones[rol]=await sesion(rol);ok('Auth real inicia sesión de '+rol)
  }
  const telefonos=filas.map(f=>'+51'+f.telefono)
  const columnas='id,nombre_completo,telefono,origen,campania_origen,vendedor_id,alta_manual,nota,creado_por,asignado_supervisor_id'
  const leer=cliente=>cliente.schema('crm').from('leads').select(columnas).in('telefono',telefonos).order('telefono')
  const todos=await leer(sesiones.gerencia.cliente);assert.equal(todos.error,null);assert.equal(todos.data.length,3)
  const [legacy,campania,otro]=todos.data
  assert.equal(legacy.campania_origen,null)
  assert.equal(campania.campania_origen,'Formulario 3');assert.equal(otro.campania_origen,'Formulario 3')
  assert.ok(todos.data.every(l=>l.origen==='formulario'&&!l.alta_manual&&l.creado_por===null))
  assert.equal(legacy.vendedor_id,usuarios.vendedor.id);assert.equal(campania.vendedor_id,usuarios.vendedor.id)
  assert.equal(otro.vendedor_id,usuarios.vendedor_otro.id)
  ok('Persistencia conserva campaña, canal y procedencia automática',{leads:todos.data})
  for(const [rol,n,c] of [['vendedor',2,1],['supervisor',2,1],['vendedor_otro',1,1],['supervisor_otro',1,1],['gerencia',3,2],['directorio',3,2],['coordinador',0,0],['inactivo',0,null]]){
    const cliente=sesiones[rol].cliente
    const r=await leer(cliente);assert.equal(r.error,null);assert.equal(r.data.length,n,rol+' lectura directa')
    ok('RLS HTTP: '+rol+' solo lee su ámbito',{cantidad:n})
    const filtro=await cliente.schema('crm').rpc('cartera_filtrada_fn',{p_texto:'PRUEBA F3 Rol',p_campania_origen:'Formulario 3'})
    if(c===null){assert.equal(filtro.error?.code,'42501');ok('RPC rechaza membresía CRM inactiva');continue}
    assert.equal(filtro.error,null,rol+' filtro: '+filtro.error?.message)
    assert.equal(filtro.data.items.length,c);assert.equal(filtro.data.resumen.totales.vivos,c)
    assert.ok(filtro.data.items.every(l=>l.campania_origen==='Formulario 3'))
    ok('Filtro y cifras HTTP: '+rol,{cantidad:c})
  }
  const cliente=sesiones.vendedor.cliente
  const bloqueado=await cliente.schema('crm').from('leads').update({campania_origen:'Alterada'}).eq('id',campania.id)
  assert.equal(bloqueado.error?.code,'42501');ok('PATCH humano de campaña rechazado')
  const permitido=await cliente.schema('crm').from('leads').update({nota:'Nota comercial de prueba F3'}).eq('id',campania.id).select('id,campania_origen,nota')
  assert.equal(permitido.error,null);assert.equal(permitido.data.length,1);assert.equal(permitido.data[0].campania_origen,'Formulario 3')
  ok('PATCH comercial permitido conserva campaña')
  const cruzado=await cliente.schema('crm').from('leads').update({nota:'No debe llegar'}).eq('id',otro.id).select('id')
  assert.equal(cruzado.error,null);assert.equal(cruzado.data.length,0);ok('PATCH cruzado no modifica otra cartera')
  const directa=await cliente.schema('crm').rpc('importar_lead_fn',{p_fila:{}})
  assert.ok(directa.error);ok('Usuario autenticado no ejecuta la puerta del servidor',{codigo:directa.error.code})
  const anonimo=createClient(url,anon,opciones)
  const sinSesion=await leer(anonimo);assert.ok(sinSesion.error);ok('Anónimo sin lectura de leads',{codigo:sinSesion.error.code})
  const antes=await leer(sesiones.gerencia.cliente)
  const repeticion=await importar(filas.map(f=>({...f,fila:f.fila+100})))
  assert.equal(repeticion.status,200);assert.ok(repeticion.body.resultados.every(r=>r.resultado==='duplicado'))
  const despues=await leer(sesiones.gerencia.cliente);assert.deepEqual(despues.data,antes.data)
  ok('Reenvío HTTP con otra fila no altera fichas ni crea leads',{resultados:repeticion.body.resultados})
  const invalida=await importar([{...filas[0],fila:99,telefono:'984300099',campania_origen:{}}])
  assert.equal(invalida.status,200);assert.equal(invalida.body.resultados[0].resultado,'rechazado')
  const noCreada=await sesiones.gerencia.cliente.schema('crm').from('leads').select('id').eq('telefono','+51984300099')
  assert.equal(noCreada.error,null);assert.deepEqual(noCreada.data,[]);ok('Campaña inválida rechazada sin alta parcial')
  guardarPrivado('e2e.json',{ref,url,anon,usuarios:Object.fromEntries(['vendedor','supervisor','gerencia','directorio'].map(rol=>[rol,usuarios[rol]]))})
}

async function reparto(){
  const filas=[
    {fila:21,nombre:'PRUEBA F3 Reparto Legacy',telefono:'984300021'},
    {fila:22,nombre:'PRUEBA F3 Reparto Campaña',telefono:'984300022',campania_origen:'Formulario 3'},
  ].map(f=>({capital:'5000',moneda:'PEN',canal:'FORMULARIO',autorizo:'SI',fuente_consentimiento:'Ensayo aislado F3',...f}))
  const alta=await importar(filas);assert.equal(alta.status,200)
  assert.ok(alta.body.resultados.every(r=>r.resultado==='importado'));ok('HTTP crea dos altas en la cola normal de FORMULARIO')
  const g=(await sesion('gerencia')).cliente.schema('crm')
  const c=(await sesion('coordinador')).cliente.schema('crm')
  const s=(await sesion('supervisor')).cliente.schema('crm')
  const v=(await sesion('vendedor')).cliente.schema('crm')
  const telefonos=filas.map(f=>'+51'+f.telefono)
  const leer=()=>g.from('leads').select('id,nombre_completo,origen,campania_origen,vendedor_id,asignado_supervisor_id,alta_manual').in('telefono',telefonos).order('telefono')
  const antes=await leer();assert.equal(antes.error,null);assert.equal(antes.data.length,2)
  assert.ok(antes.data.every(l=>!l.vendedor_id&&!l.asignado_supervisor_id&&!l.alta_manual&&l.origen==='formulario'))
  ok('Campaña y legacy llegan sin forzar vendedor ni supervisor')
  const config=await g.rpc('configuracion_reparto_fn');assert.equal(config.error,null)
  assert.equal(config.data.coordinacion_libre,true,'Se conserva la configuración copiada de producción')
  ok('Misma configuración vigente: Coordinación libre',{configuracion:config.data})
  for(const lead of antes.data){
    const denegado=await v.rpc('repartir_lead',{p_lead:lead.id,p_supervisor:usuarios.supervisor.id})
    assert.equal(denegado.error?.code,'42501');ok('Analista no reparte '+lead.nombre_completo)
    const r=await c.rpc('repartir_lead',{p_lead:lead.id,p_supervisor:usuarios.supervisor.id})
    assert.equal(r.error,null,r.error?.message);ok('Coordinación reparte '+lead.nombre_completo,{resultado:r.data})
    const duplicado=await c.rpc('repartir_lead',{p_lead:lead.id,p_supervisor:usuarios.supervisor.id})
    assert.equal(duplicado.error?.code,'P0002');ok('Segundo reparto rechazado para la misma ficha')
  }
  const ids=antes.data.map(l=>l.id)
  const derivado=await s.rpc('derivar_leads_equipo_fn',{p_lead_ids:ids,p_asesor_ids:ids.map(()=>usuarios.vendedor.id)})
  assert.equal(derivado.error,null,derivado.error?.message);assert.equal(derivado.data.derivados,2)
  ok('Supervisor deriva ambos al analista mediante la puerta normal',{resultado:derivado.data})
  const repetido=await s.rpc('derivar_leads_equipo_fn',{p_lead_ids:ids,p_asesor_ids:ids.map(()=>usuarios.vendedor.id)})
  assert.ok(repetido.error);ok('Segunda derivación rechazada',{codigo:repetido.error.code})
  const final=await leer();assert.equal(final.error,null)
  assert.ok(final.data.every(l=>l.vendedor_id===usuarios.vendedor.id&&!l.asignado_supervisor_id))
  assert.equal(final.data[0].campania_origen,null);assert.equal(final.data[1].campania_origen,'Formulario 3')
  ok('Reparto conserva campaña de origen y procedimiento comercial',{leads:final.data})
  const otraVez=await importar(filas.map(f=>({...f,fila:f.fila+300})))
  assert.equal(otraVez.status,200);assert.ok(otraVez.body.resultados.every(r=>r.resultado==='duplicado'))
  assert.deepEqual((await leer()).data,final.data);ok('Reenvío después del reparto conserva dueño y fichas')
}

if(process.argv[1]?.endsWith('/auth-http.mjs')||process.argv[1]?.endsWith('fase3/auth-http.mjs')){
  try {
    await ({crear,frontera,permisos,reparto}[process.argv[2]])()
    grabar()
  }catch(e){grabar();console.error(e.name+': '+e.message);process.exitCode=1}
}
