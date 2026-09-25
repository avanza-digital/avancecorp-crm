import assert from 'node:assert/strict';
import {test,after} from 'node:test';
import {randomUUID,randomInt} from 'node:crypto';
import {spawn} from 'node:child_process';
import {sql,q,db,contenedor,credencialesLocales} from './banco.mjs';
import {crearHandlerAccesoInversion} from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';

const actor='c0000000-0000-4000-8000-000000000004';
const cred=credencialesLocales(),token=cred.actor(actor);
const claims=`select set_config('request.jwt.claim.sub',${q(actor)},false);`;
const base='http://127.0.0.1:59421';
async function transportar(url,options={}) {
  const u=new URL(url);assert.equal(u.origin,base);
  const pref=u.pathname.startsWith('/auth/v1/')?'/auth/v1':'/rest/v1';
  assert(u.pathname.startsWith(pref+'/'));
  return fetch(`http://127.0.0.1:${pref==='/auth/v1'?59426:59425}${u.pathname.slice(pref.length)}${u.search}`,
    {...options,redirect:'error'});
}
async function llamada(ruta,body,admin=false,actorToken=token) {
  const r=await transportar(base+ruta,{method:'POST',signal:AbortSignal.timeout(15000),headers:{
    apikey:admin?cred.servicio:cred.anon,Authorization:'Bearer '+(admin?cred.servicio:actorToken),
    'Content-Type':'application/json',...(ruta.startsWith('/rest/')?{'Content-Profile':'crm','Accept-Profile':'crm'}:{})},body:JSON.stringify(body)});
  return {status:r.status,data:await r.json()};
}
async function rpc(nombre,body,actorToken) {
  return llamada('/rest/v1/rpc/'+nombre,body,false,actorToken);
}
async function fixture(prefijo='correo') {
  const lead=randomUUID(),solicitud=randomUUID(),correo=prefijo+'.'+solicitud+'@example.invalid',doc=String(randomInt(80000000,89999999));
  const persona=sql(`${claims} insert into crm.leads(id,nombre_completo,telefono,monto_estimado,moneda,origen,etapa,vendedor_id,correo)
    values(${q(lead)},'PERSONA SINTETICA CORREO',${q('+519'+doc.slice(0,8))},5000,'PEN','formulario','nuevo',${q(actor)},${q(correo)});
    select crm.preparar_persona_lead_inversion_fn(${q(lead)},'DNI',${q(doc)},'PERSONA SINTETICA CORREO')->>'inversionista_id';`).split('\n').at(-1);
  const datos={inversionista_id:persona,lead_id:lead,empresa:'avance',contrato:{moneda:'PEN'},cronograma:[],cuenta:{},
    alta_portal:{correo,nombre_completo:'PERSONA SINTETICA CORREO',nombres:'PERSONA',apellidos:'SINTETICA CORREO',telefono:'999123456',domicilio:'AVENIDA SINTETICA 123 LIMA'}};
  let r=await rpc('preparar_inversion_fn',{p_clave:solicitud,p_datos:datos});assert.equal(r.status,200,JSON.stringify(r));
  const recuperacion='a'.repeat(48);
  r=await rpc('acceso_inversion_fn',{p_solicitud:solicitud,p_paso:'reclamar',p_payload:{token:recuperacion}});
  assert.equal(r.status,200,JSON.stringify(r));
  return {lead,solicitud,persona,datos,correo,claim:r.data.claim_id,recuperacion,reclamo:r.data};
}
const datosNuevos=(f,correo)=>({...f.datos,alta_portal:{...f.datos.alta_portal,correo}});
const peticionCorreccion=(f,correo)=>({p_solicitud:f.solicitud,p_clave:randomUUID(),p_revision_datos_esperada:0,
  p_datos:datosNuevos(f,correo),p_motivo:'Corregir correo del primer acceso en ensayo'});
const sqlCorreccion=(f,correo)=>`select crm.corregir_solicitud_inversion_fn(${q(f.solicitud)},${q(randomUUID())},0,${q(JSON.stringify(datosNuevos(f,correo)))}::jsonb,'Corregir correo del primer acceso en ensayo');`;
const crearAuth=(f,correo=f.correo)=>llamada('/auth/v1/admin/users',{email:correo,password:'SoloEnsayoLocal-2026!',email_confirm:true,app_metadata:{claim_id:f.claim}},true);
const contarAuth=f=>Number(sql(`select count(*) from auth.users where raw_app_meta_data->>'claim_id'=${q(f.claim)}`));
const handler=crearHandlerAccesoInversion({supabaseUrl:base,anonKey:cred.anon,serviceKey:cred.servicio,fetchImpl:transportar});
async function completar(f,atender=handler) {
  const r=await atender(new Request(base+'/functions/v1/crm-inversion-portal',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},
    body:JSON.stringify({solicitud_id:f.solicitud,token:f.recuperacion})}));
  return {status:r.status,data:await r.json()};
}
function sesion(sentencia,senal='LISTO') {
  const p=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-f','-']);
  let salida='',error='',avisado=false;
  let anunciar;const listo=new Promise(resolve=>{anunciar=resolve;});
  p.stdout.on('data',b=>{salida+=b;if(!avisado&&salida.includes(senal)){avisado=true;anunciar();}});
  p.stderr.on('data',b=>{error+=b;});
  const fin=new Promise(resolve=>p.on('close',status=>{if(!avisado)anunciar();resolve({status,salida,error});}));
  p.stdin.end(sentencia);return {listo,fin};
}
async function esperarAuthDentro() {
  const limite=Date.now()+10000;
  while(Date.now()<limite) {
    if(sql("select exists(select 1 from pg_locks where locktype='advisory' and classid=0 and objid=2026092501 and granted)")==='t')return;
    await new Promise(r=>setTimeout(r,30));
  }
  throw new Error('Auth no alcanzó la pausa transaccional del ensayo');
}
sql(`create or replace function private.correo_prueba_pausa_auth() returns trigger language plpgsql as $$
  begin if new.email like 'pausa.%' and new.raw_app_meta_data->>'claim_id' is not null and (tg_op='INSERT' or old.raw_app_meta_data->>'claim_id' is distinct from new.raw_app_meta_data->>'claim_id') then perform pg_advisory_xact_lock(2026092501);perform pg_sleep(2);end if;return new;end $$;
  create trigger zzz_correo_prueba_pausa_auth after insert or update of raw_app_meta_data on auth.users for each row execute function private.correo_prueba_pausa_auth();`);
after(()=>sql('drop trigger zzz_correo_prueba_pausa_auth on auth.users;drop function private.correo_prueba_pausa_auth();'));

test('PostgREST corrige una reserva activa y Edge/GoTrue crean el correo nuevo una sola vez',async()=>{
  const f=await fixture(),correo='nuevo.'+f.solicitud+'@example.invalid';
  const r=await rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,correo));assert.equal(r.status,200,JSON.stringify(r));
  assert.equal(sql(`select correo from crm.leads where id=${q(f.lead)}`),correo);
  const listo=await completar(f);assert.equal(listo.status,200,JSON.stringify(listo));assert.equal(contarAuth(f),1);
  assert.equal(sql(`select email from auth.users where raw_app_meta_data->>'claim_id'=${q(f.claim)}`),correo);
  assert.equal((await completar(f)).data.perfil_id,listo.data.perfil_id);assert.equal(contarAuth(f),1);
});
test('corrección gana la carrera: GoTrue rechaza la petición tardía y no deja Auth huérfano',async()=>{
  const f=await fixture(),nuevo='ganador.'+f.solicitud+'@example.invalid';
  const concurrente=sesion(`begin;${claims}${sqlCorreccion(f,nuevo)}\n\\echo LISTO\nselect pg_sleep(2);commit;`);
  await concurrente.listo;
  const r=await crearAuth(f);const fin=await concurrente.fin;assert.equal(fin.status,0,fin.error);
  assert.equal(r.status,500,JSON.stringify(r));assert.equal(contarAuth(f),0);
  assert.equal(sql(`select count(*) from auth.users where email=${q(f.correo)}`),'0','el INSERT sin marca también se revierte');
  assert.equal((await completar(f)).status,200);assert.equal(contarAuth(f),1);
});
test('Auth gana la carrera: rechaza corrección y conserva el correo ya creado',async()=>{
  const f=await fixture('pausa'),alta=crearAuth(f);await esperarAuthDentro();
  const correccion=rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,'rechazado.'+f.solicitud+'@example.invalid'));
  assert.equal((await alta).status,200);const r=await correccion;
  assert.notEqual(r.status,200);assert.equal(r.data.code,'P0409');assert.equal(contarAuth(f),1);
  assert.equal(sql(`select email from auth.users where raw_app_meta_data->>'claim_id'=${q(f.claim)}`),f.correo);
  assert.equal((await completar(f)).status,200);
});
test('REPEATABLE READ no ignora un Auth que se confirmó después de su snapshot',async()=>{
  const f=await fixture('pausa');
  const concurrente=sesion(`begin isolation level repeatable read;${claims}select revision_datos from crm.inversion_solicitudes where id=${q(f.solicitud)};
    \\echo SNAPSHOT
    select pg_sleep(1);${sqlCorreccion(f,'snapshot.'+f.solicitud+'@example.invalid')}commit;`,'SNAPSHOT');
  await concurrente.listo;const alta=crearAuth(f);await esperarAuthDentro();
  assert.equal((await alta).status,200);const fin=await concurrente.fin;
  assert.notEqual(fin.status,0);assert.match(fin.error,/0A000.*requiere READ COMMITTED|40001|PT409/);assert.equal(contarAuth(f),1);
  assert.equal(sql(`select datos#>>'{alta_portal,correo}' from crm.inversion_solicitudes where id=${q(f.solicitud)}`),f.correo);
});
test('respuesta perdida de GoTrue conserva cuenta y bloquea corrección, y un reintento recupera',async()=>{
  const f=await fixture();let perder=true;
  const conPerdida=crearHandlerAccesoInversion({supabaseUrl:base,anonKey:cred.anon,serviceKey:cred.servicio,fetchImpl:async(url,options)=>{
    const r=await transportar(url,options);
    if(perder&&url.endsWith('/auth/v1/admin/users')&&r.ok){perder=false;throw new Error('Respuesta perdida después de commit');}
    return r;
  }});
  const r=await completar(f,conPerdida);assert.notEqual(r.status,200);assert.equal(contarAuth(f),1);
  const corregir=await rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,'no.'+f.solicitud+'@example.invalid'));
  assert.equal(corregir.data.code,'P0409');assert.equal((await completar(f)).status,200);assert.equal(contarAuth(f),1);
});
test('importación sin actor no inventa auditoría: exige revisar la diferencia antes de Auth',async()=>{
  const f=await fixture(),nuevo='importado.'+f.solicitud+'@example.invalid';
  sql(`select set_config('request.jwt.claim.sub','',false);update crm.leads set correo=${q(nuevo)} where id=${q(f.lead)};`);
  const r=await completar(f);assert.notEqual(r.status,200);assert.match(r.data.error,/correo de la ficha cambió/);assert.equal(contarAuth(f),0);
  const actual=await rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,nuevo));assert.equal(actual.status,200);
  assert.equal((await completar(f)).status,200);
});
test('revisión antigua puede conservar explícitamente el correo de solicitud y sincronizar la ficha',async()=>{
  const f=await fixture();sql(`select set_config('request.jwt.claim.sub','',false);update crm.leads set correo=${q('otro.'+f.solicitud+'@example.invalid')} where id=${q(f.lead)};`);
  const r=await rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,f.correo));assert.equal(r.status,200,JSON.stringify(r));
  assert.equal(sql(`select correo from crm.leads where id=${q(f.lead)}`),f.correo);assert.equal((await completar(f)).status,200);
});
test('helpers sin grants directos y actualización de ficha fuera de ámbito denegada',async()=>{
  assert.equal(sql("select has_function_privilege('authenticated','private.inversion_corregir_reserva_acceso(uuid,jsonb)','execute')"),'f');
  const f=await fixture(),otro=cred.actor('c0000000-0000-4000-8000-000000000006');
  const r=await rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,'intruso.'+f.solicitud+'@example.invalid'),otro);
  assert.equal(r.data.code,'42501');assert.equal(contarAuth(f),0);
});

test('dos correcciones simultáneas conservan revisión única y la ficha consistente',async()=>{
  const f=await fixture(),uno='uno.'+f.solicitud+'@example.invalid',dos='dos.'+f.solicitud+'@example.invalid';
  const respuestas=await Promise.all([rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,uno)),rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,dos))]);
  assert.equal(respuestas.filter(r=>r.status===200).length,1,JSON.stringify(respuestas));
  const rechazo=respuestas.find(r=>r.status!==200);assert(['PT409','40001','55P03'].includes(rechazo.data.code),JSON.stringify(rechazo));
  const ganador=respuestas[0].status===200?uno:dos;
  assert.equal(sql(`select correo from crm.leads where id=${q(f.lead)}`),ganador);
  assert.equal(sql(`select revision_datos from crm.inversion_solicitudes where id=${q(f.solicitud)}`),'1');
  assert.equal((await completar(f)).status,200);assert.equal(contarAuth(f),1);
});
test('ficha editada mientras llega corrección devuelve conflicto sin sobrescribir el correo',async()=>{
  const f=await fixture(),ficha='ficha.'+f.solicitud+'@example.invalid';
  const concurrente=sesion(`begin;${claims}set local role authenticated;update crm.leads set correo=${q(ficha)} where id=${q(f.lead)};
    \\echo LISTO
    select pg_sleep(2);commit;`);
  await concurrente.listo;
  const r=await rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,'viejo.'+f.solicitud+'@example.invalid'));
  const fin=await concurrente.fin;assert.equal(fin.status,0,fin.error);assert.notEqual(r.status,200,JSON.stringify(r));
  assert(['PT409','40001','55P03'].includes(r.data.code),JSON.stringify(r));
  assert.equal(sql(`select correo from crm.leads where id=${q(f.lead)}`),ficha);
  assert.equal((await completar(f)).status,200);assert.equal(contarAuth(f),1);
});

for(const [rol,id,permite] of [['gerencia','001',true],['supervisor propio','002',true],['supervisor ajeno','003',false],['vendedor propietario','004',true],['vendedor ajeno','006',false],['vendedor inactivo','008',false],['directorio','009',false],['coordinador','00a',false]]) {
  test(`RLS ficha: ${rol} ${permite?'sincroniza':'no modifica'} el acceso pendiente`,async()=>{
    const f=await fixture(),nuevo='rls.'+f.solicitud+'@example.invalid';
    const quien='c0000000-0000-4000-8000-000000000'+id;
    const r=await transportar(base+'/rest/v1/leads?id=eq.'+f.lead,{method:'PATCH',headers:{
      apikey:cred.anon,Authorization:'Bearer '+cred.actor(quien),'Content-Profile':'crm','Accept-Profile':'crm',
      'Content-Type':'application/json',Prefer:'return=representation'},body:JSON.stringify({correo:nuevo})});
    const actualizado=sql(`select datos#>>'{alta_portal,correo}' from crm.inversion_solicitudes where id=${q(f.solicitud)}`);
    assert.equal(actualizado,permite?nuevo:f.correo,`HTTP ${r.status}: ${await r.text()}`);
    assert.equal(sql(`select correo from crm.leads where id=${q(f.lead)}`),actualizado);
    if(permite)assert.equal(sql(`select corregido_por from crm.inversion_solicitud_correcciones where solicitud_id=${q(f.solicitud)}`),quien);
    assert.equal(contarAuth(f),0);
  });
}

test('vaciar correo de ficha antes de Auth conserva contacto y exige revisar antes de crear',async()=>{
  const f=await fixture();
  sql(`begin;${claims}set local role authenticated;update crm.leads set correo=null where id=${q(f.lead)};commit;`);
  assert.equal(sql(`select correo is null from crm.leads where id=${q(f.lead)}`),'t');
  assert.equal(sql(`select datos#>>'{alta_portal,correo}' from crm.inversion_solicitudes where id=${q(f.solicitud)}`),f.correo);
  assert.notEqual((await completar(f)).status,200);assert.equal(contarAuth(f),0);
  const r=await rpc('corregir_solicitud_inversion_fn',peticionCorreccion(f,f.correo));assert.equal(r.status,200,JSON.stringify(r));
  assert.equal((await completar(f)).status,200);
});
test('corregir teléfono no revierte un correo de ficha importado sin actor',async()=>{
  const f=await fixture(),nuevo='importado.'+f.solicitud+'@example.invalid';
  sql(`select set_config('request.jwt.claim.sub','',false);update crm.leads set correo=${q(nuevo)} where id=${q(f.lead)};`);
  const peticion=peticionCorreccion(f,f.correo);peticion.p_datos.alta_portal.telefono='999654321';
  const r=await rpc('corregir_solicitud_inversion_fn',peticion);assert.equal(r.status,200,JSON.stringify(r));
  assert.equal(sql(`select correo from crm.leads where id=${q(f.lead)}`),nuevo);
  assert.notEqual((await completar(f)).status,200);assert.equal(contarAuth(f),0);
});
test('resultado informa Auth ya creado sin perfil para que la UI permita recuperar',async()=>{
  const f=await fixture();assert.equal((await rpc('solicitud_inversion_fn',{p_solicitud:f.solicitud})).data.acceso_creado,false);
  assert.equal((await crearAuth(f)).status,200);
  sql(`${claims}update crm.leads set correo=${q('contacto.'+f.solicitud+'@example.invalid')} where id=${q(f.lead)};`);
  const r=await rpc('solicitud_inversion_fn',{p_solicitud:f.solicitud});assert.equal(r.status,200,JSON.stringify(r));
  assert.equal(r.data.acceso_creado,true);assert.equal(r.data.necesita_portal,true);
  assert.equal((await completar(f)).status,200);assert.equal(contarAuth(f),1);
});
