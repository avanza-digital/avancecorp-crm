// Gate focal de atención/venta: Auth real, PostgREST real y escritores legítimos.
// Destinos cerrados y desechables. Nunca admite la referencia productiva.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {randomUUID,randomBytes,randomInt} from 'node:crypto';
const destino=process.env.ATENCION_DESTINO ?? 'integracion';
assert(['integracion','rama'].includes(destino));
const local=destino==='integracion';
const carpeta='/private/tmp/avancecorp-atencion-integracion-20261013';
const cfg=local ? readFileSync(`${carpeta}/start.log`,'utf8').split('\n').filter(l=>l.startsWith('{')).map(l=>JSON.parse(l)).find(c=>c.API_URL)
  : JSON.parse(readFileSync('/private/tmp/atencion-branch-access.json','utf8'));
const url=local ? cfg.API_URL : cfg.SUPABASE_URL;
const anon=local ? cfg.ANON_KEY : cfg.SUPABASE_ANON_KEY;
const servicio=local ? cfg.SERVICE_ROLE_KEY : cfg.SUPABASE_SERVICE_ROLE_KEY;
assert.equal(url,local?'http://127.0.0.1:56461':'https://cdntljznxaubchkhusqo.supabase.co');
const db=new URL(local?cfg.DB_URL:cfg.POSTGRES_URL);
assert.equal(decodeURIComponent(db.username),local?'postgres':'postgres.cdntljznxaubchkhusqo');
if(local) { assert.equal(db.hostname,'127.0.0.1'); assert.equal(db.port,'56462'); }
else { assert(db.hostname.endsWith('.pooler.supabase.com')); db.port='5432'; }
const q=v=>v==null?'null':`'${String(v).replaceAll("'","''")}'`;
function sql(texto) {
  const env={...process.env};
  for(const n of ['PGHOSTADDR','PGSERVICE','PGSERVICEFILE']) delete env[n];
  Object.assign(env,{PGHOST:db.hostname,PGPORT:db.port||'5432',PGDATABASE:db.pathname.slice(1),
    PGUSER:decodeURIComponent(db.username),PGPASSWORD:decodeURIComponent(db.password),PGSSLMODE:local?'prefer':'require'});
  const r=spawnSync('/opt/homebrew/opt/postgresql@17/bin/psql',['-X','-qAt','-v','ON_ERROR_STOP=1','-f','-'],
    {env,input:texto,encoding:'utf8',maxBuffer:8*1024*1024});
  assert.equal(r.status,0,`SQL del banco: ${r.stderr}`);return r.stdout.trim();
}
async function http(ruta,{token=anon,body,method='POST',schema}={}) {
  assert(ruta.startsWith('/')&&!ruta.startsWith('//'));
  const r=await fetch(url+ruta,{method,signal:AbortSignal.timeout(15000),
    headers:{apikey:anon,Authorization:`Bearer ${token}`,'Content-Type':'application/json',
      ...(schema?{'Content-Profile':schema,'Accept-Profile':schema}:{}),Prefer:'return=representation'},
    ...(body===undefined?{}:{body:JSON.stringify(body)})});
  const texto=await r.text();let data;try{data=JSON.parse(texto)}catch{data=texto}
  return {status:r.status,data};
}
const rpc=(nombre,body,token)=>http(`/rest/v1/rpc/${nombre}`,{body,token,schema:'crm'});
const pruebas=[];
function ok(nombre,condicion,detalle='') {assert(condicion,`${nombre}: ${detalle}`);pruebas.push(nombre);console.log('PASS: '+nombre)}
function exito(r,nombre){assert.equal(r.status,200,`${nombre}: ${JSON.stringify(r.data)}`);return r.data}
const ejecucion=randomUUID();const clave='Banco-'+randomBytes(22).toString('base64url');
async function usuario(nombre,rol,crm=null,supervisor=null,activo=true) {
  const email=`atencion.${ejecucion}.${nombre}@pruebas.example`;
  const alta=await http('/auth/v1/admin/users',{token:servicio,body:{email,password:clave,email_confirm:true}});
  assert([200,201].includes(alta.status),`Auth alta: ${JSON.stringify(alta.data)}`);
  const id=alta.data.id;
  sql(`insert into public.perfiles(id,nombre_completo,correo,rol,activo,debe_cambiar_password)
    values(${q(id)},${q('PRUEBA ATENCION '+nombre)},${q(email)},${q(rol)},true,false)
    on conflict(id) do update set rol=excluded.rol,activo=true,debe_cambiar_password=false;
    ${crm?`insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) values(${q(id)},${q(crm)},${q(supervisor)},${activo});`:''}`);
  const login=await http('/auth/v1/token?grant_type=password',{body:{email,password:clave}});
  assert.equal(login.status,200,'Auth debe entregar una sesión real de prueba');
  return {id,token:login.data.access_token};
}
assert.equal(sql("select count(*) from pg_proc where oid=to_regprocedure('crm.previsualizar_cambio_responsabilidad_fn(text,uuid,uuid)')"),'1','Candidata no instalada');
const anteriores=JSON.parse(sql("select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags where nombre in('resolver_en_puertas','inversiones_escritura')"));
assert(Object.hasOwn(anteriores,'resolver_en_puertas'));
const actores={};
try {
  actores.gerencia=await usuario('gerencia','comercial','gerencia');
  actores.gerenciaAnalista=await usuario('gerencia_analista','analista','gerencia');
  actores.supervisor=await usuario('supervisor','analista','supervisor',actores.gerencia.id);
  actores.vendedor=await usuario('vendedor','analista','vendedor',actores.supervisor.id);
  actores.reemplazo=await usuario('reemplazo','analista','vendedor',actores.supervisor.id);
  actores.admin=await usuario('admin','admin');
  actores.superadmin=await usuario('superadmin','superadmin');
  actores.operaciones=await usuario('operaciones','operaciones');
  actores.revocado=await usuario('revocado','admin','gerencia',null,false);
  actores.anon={token:anon};actores.servicio={token:servicio};
  const cliente=await usuario('cliente','cliente');
  const g=actores.gerencia.id,a=actores.vendedor.id,b=actores.reemplazo.id;
  const venta=randomUUID(),tarea=randomUUID(),lead=randomUUID();
  const numero=`2026-01-${randomInt(900000,999999)}`;
  sql(`begin;update crm.multiempresa_flags set activo=(nombre='resolver_en_puertas') where nombre in('resolver_en_puertas','inversiones_escritura');
    update public.perfiles set asesor_perfil_id=${q(a)},tipo_documento='DNI',dni=${q(String(randomInt(60000000,69999999)))} where id=${q(cliente.id)};
    select private.asegurar_identidad_perfil(${q(cliente.id)},'ensayo_atencion');commit;`);
  const persona=sql(`select id from crm.inversionistas where perfil_id=${q(cliente.id)} and estado<>'fusionado'`);
  // Semilla histórica: un lead abierto anterior a convertirse en cliente.
  // Solo se apaga el resolver durante esta inserción; cada acción bajo prueba
  // entra después por Auth/PostgREST con identidad encendida y todos los guards.
  sql(`begin;
    update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';
    insert into crm.leads(id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,vendedor_id,creado_por,inversionista_id)
    values(${q(lead)},'PRUEBA ATENCION LEAD',${q('+519'+randomInt(10000000,99999999))},(select dni from public.perfiles where id=${q(cliente.id)}),150000,'oficina','contactado',${q(a)},${q(g)},${q(persona)});
    update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';
    insert into crm.postventa_escrituras(transaccion,tarea_id) values(pg_current_xact_id(),${q(tarea)});
    insert into crm.tareas(id,inversionista_id,tipo,titulo,vence_en,creado_por,vendedor_id)
    values(${q(tarea)},${q(persona)},'llamada','PRUEBA ATENCION PERSONA',now()+interval '1 day',${q(g)},${q(a)});
    insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,modalidad,tipo_interes,fecha_inicio,fecha_vencimiento,estado,categoria,creado_por,analista_cierre_id)
    values(${q(venta)},${q(numero)},${q(cliente.id)},150000,'PEN',15,'mensual','simple',current_date,current_date+365,'activo','nuevo',${q(g)},${q(a)});
    commit;`);
  const foto=()=>JSON.parse(sql(`select jsonb_build_object('asesor',(select asesor_perfil_id from public.perfiles where id=${q(cliente.id)}),
    'responsable',(select responsable_relacion_id from crm.inversionistas where id=${q(persona)}),
    'tarea',(select vendedor_id from crm.tareas where id=${q(tarea)}),'lead',(select vendedor_id from crm.leads where id=${q(lead)}),
    'venta',(select analista_cierre_id from public.contratos where id=${q(venta)}),
    'capital',(select capital from public.contratos where id=${q(venta)}),'creador',(select creado_por from public.contratos where id=${q(venta)}),
    'historial',(select count(*) from crm.reasignaciones_analista where contrato_id=${q(venta)}))`));
  for(const nombre of ['gerencia','gerenciaAnalista','admin','superadmin','operaciones','supervisor','vendedor','revocado','anon','servicio']) {
    for(const accion of ['venta','atencion_cliente','atencion_persona']) {
      const antes=foto();const actual=accion==='venta'?antes.venta:antes.responsable;
      const destinoId=actual===a?b:a;
      const args={p_accion:accion,p_id:accion==='venta'?venta:accion==='atencion_cliente'?cliente.id:persona,p_destino:destinoId};
      const permitido=['gerencia','gerenciaAnalista','admin','superadmin'].includes(nombre)||(nombre==='operaciones'&&accion==='venta');
      const pre=await rpc('previsualizar_cambio_responsabilidad_fn',args,actores[nombre].token);
      if(permitido) {
        const datos=exito(pre,`${nombre} preview ${accion}`);
        ok(`${nombre} previsualiza ${accion}`,typeof datos.version==='string');
        const conf=exito(await rpc('confirmar_cambio_responsabilidad_fn',{...args,p_motivo:'Ensayo sintético de permisos',p_version:datos.version},actores[nombre].token),'Confirmación');
        const despues=foto();
        ok(`${nombre} confirma ${accion}`,conf.ok===true&&despues.capital===antes.capital&&despues.creador===antes.creador);
        if(accion==='venta') ok(`${nombre} cambia solo venta`,despues.venta===destinoId&&despues.asesor===antes.asesor&&despues.responsable===antes.responsable&&despues.historial===antes.historial+1);
        else ok(`${nombre} alinea atención sin cambiar venta`,[despues.asesor,despues.responsable,despues.tarea,despues.lead].every(x=>x===destinoId)&&despues.venta===antes.venta&&despues.historial===antes.historial,JSON.stringify({antes,despues,destinoId}));
      } else {
        ok(`${nombre} preview ${accion} denegado`,[401,403].includes(pre.status)&&pre.data.code==='42501',JSON.stringify(pre));
        const version=exito(await rpc('previsualizar_cambio_responsabilidad_fn',args,actores.gerencia.token),'Preview del actor autorizado').version;
        const conf=await rpc('confirmar_cambio_responsabilidad_fn',{...args,p_motivo:'Ensayo denegado',p_version:version},actores[nombre].token);
        ok(`${nombre} confirm ${accion} denegado`,[401,403].includes(conf.status)&&conf.data.code==='42501',JSON.stringify(conf));
        assert.deepEqual(foto(),antes,'Rechazo no debe mutar ninguna fila de negocio');
      }
    }
  }
  const cambiar=async(destinoId,actor=actores.gerencia)=>{
    const args={p_accion:'atencion_cliente',p_id:cliente.id,p_destino:destinoId};
    const pre=exito(await rpc('previsualizar_cambio_responsabilidad_fn',args,actor.token),'Preview atención');
    return exito(await rpc('confirmar_cambio_responsabilidad_fn',{...args,p_motivo:'Ensayo de escritor legítimo',p_version:pre.version},actor.token),'Confirmación atención');
  };
  // Gerencia atiende la persona y sus tareas; el asesor operativo conserva su rol.
  const antesGerencia=foto();await cambiar(g);const despuesGerencia=foto();
  ok('Destino Gerencia mueve tarea por persona y conserva cartera operativa',despuesGerencia.responsable===g&&despuesGerencia.tarea===g&&despuesGerencia.asesor===antesGerencia.asesor&&despuesGerencia.lead===antesGerencia.lead&&despuesGerencia.venta===antesGerencia.venta);
  await cambiar(a);
  // Un editor normal no lleva las columnas de asesor en su payload.
  const legado=sql(`insert into public.asesores(id,nombre_completo,whatsapp)
    values(${q(randomUUID())},'PRUEBA LEGADO','999999999')
    on conflict(whatsapp) do update set nombre_completo=excluded.nombre_completo returning id`);
  sql(`update public.perfiles set asesor_id=${q(legado)} where id=${q(cliente.id)};`);
  for(const nombre of ['admin','vendedor']) {
    const r=await http(`/rest/v1/perfiles?id=eq.${cliente.id}`,{method:'PATCH',token:actores[nombre].token,body:{telefono:'999888777'}});
    ok(`${nombre} edita teléfono con asesor legado`,r.status===200,JSON.stringify(r));
    assert.equal(sql(`select asesor_id from public.perfiles where id=${q(cliente.id)}`),legado);
  }
  for(const nombre of ['admin','vendedor','servicio']) {
    const r=await http(`/rest/v1/perfiles?id=eq.${cliente.id}`,{method:'PATCH',token:actores[nombre].token,body:{asesor_perfil_id:b}});
    ok(`${nombre} no cambia asesor por PATCH directo`,r.status===403&&r.data.code==='42501',JSON.stringify(r));
  }
  // Baja real, no simulada mediante set_config de JWT ni UPDATE de membresía.
  // La matriz alterna destinos y termina en B. Dejar la venta en A por su
  // puerta real permite comprobar después la herencia efectiva de esa baja.
  const ventaDeA={p_accion:'venta',p_id:venta,p_destino:a};
  const previaVentaDeA=exito(await rpc('previsualizar_cambio_responsabilidad_fn',ventaDeA,actores.gerencia.token),'Preparar venta histórica de A');
  exito(await rpc('confirmar_cambio_responsabilidad_fn',{
    ...ventaDeA,p_motivo:'Preparar baja con venta histórica',p_version:previaVentaDeA.version
  },actores.gerencia.token),'Confirmar venta histórica de A');
  const antesBaja=foto();
  assert.equal(antesBaja.venta,a);
  const versionEquipo=sql(`select actualizado_en from crm.equipo where perfil_id=${q(a)}`);
  const bajaArgs={p_perfil_id:a,p_activo:false,p_reemplazo_id:b,p_version_equipo:versionEquipo,p_idempotencia:randomUUID()};
  const baja=exito(await rpc('fijar_membresia_activa_fn',bajaArgs,actores.gerencia.token),'Baja por puerta real');
  const despuesBaja=foto();
  ok('Baja con reemplazo alinea perfil, persona, lead y tarea',baja.activo_crm===false&&[despuesBaja.asesor,despuesBaja.responsable,despuesBaja.lead,despuesBaja.tarea].every(x=>x===b),JSON.stringify(despuesBaja));
  ok('Baja conserva capital y dueño histórico de la venta',despuesBaja.capital===antesBaja.capital&&despuesBaja.venta===antesBaja.venta&&despuesBaja.creador===antesBaja.creador);
  const repetida=exito(await rpc('fijar_membresia_activa_fn',bajaArgs,actores.gerencia.token),'Reintento de baja');
  ok('Baja idempotente deja un solo evento',repetida.idempotente===true&&sql(`select count(*) from crm.usuario_eventos where idempotencia=${q(bajaArgs.p_idempotencia)}`)==='1');
  const antesLegacy=foto();
  const previaLegacy=exito(await rpc('previsualizar_cambio_responsabilidad_fn',{
    p_accion:'atencion_persona',p_id:persona,p_destino:actores.supervisor.id
  },actores.gerencia.token),'Efecto de atención tras baja');
  assert(previaLegacy.efectos.some(e=>e.id===venta&&e.anterior!==e.previsto),'El caso debe mover atribución efectiva');
  const legadoAtencion=await rpc('reasignar_responsable_relacion_fn',{
    p_inversionista:persona,p_nuevo_responsable:actores.supervisor.id,p_motivo:'Ensayo legacy con venta heredada por baja'
  },actores.gerencia.token);
  ok('Atención legacy exige preview si mueve venta heredada',legadoAtencion.data.code==='P0409',JSON.stringify(legadoAtencion));
  assert.deepEqual(foto(),antesLegacy,'Legacy rechazada conserva atención, tareas, leads y venta');
} finally {
  for(const [nombre,activo] of Object.entries(anteriores)) sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);
  writeFileSync(`/private/tmp/atencion-integracion-${destino}.json`,JSON.stringify({destino,ejecucion,pruebas:pruebas.map(nombre=>({nombre,resultado:'PASS'}))},null,2)+'\n');
}
console.log(`PASS: ${pruebas.length} aserciones de atención/venta con Auth y API reales (${destino}).`);
