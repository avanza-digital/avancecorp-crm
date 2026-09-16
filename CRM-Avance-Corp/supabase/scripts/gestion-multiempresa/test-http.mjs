// Prueba con datos sintéticos contra Auth/PostgREST/Postgres reales. Solo admite
// la copia local o la rama de ensayo expresamente autorizada para esta entrega.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
const env=JSON.parse(readFileSync(process.argv[2],'utf8'));
const url=new URL(env.SUPABASE_URL),dbUrl=new URL(env.CRM_BANCO_PSQL_URL);
const remoto=env.CRM_GESTION_RAMA_REF!==undefined;
const db=dbUrl.pathname.slice(1);
if(remoto){
  assert.equal(env.CRM_GESTION_RAMA_REF,'ndjvbjdjotiszjhtbxik');
  assert.equal(url.origin,`https://${env.CRM_GESTION_RAMA_REF}.supabase.co`);
  assert.equal(decodeURIComponent(dbUrl.username),`postgres.${env.CRM_GESTION_RAMA_REF}`);
  assert.match(dbUrl.hostname,/\.pooler\.supabase\.com$/);
  assert.equal(db,'postgres');assert.equal(dbUrl.port,'5432');
}else{
  assert.equal(url.hostname,'127.0.0.1');assert.equal(dbUrl.hostname,'127.0.0.1');
  assert.match(db,/^gestion_multiempresa_\d{8}$/);
}
const checks=[];const pass=t=>{checks.push(t);console.log('PASS '+t);};
const q=x=>x===null?'null':"'"+String(x).replaceAll("'","''")+"'";
function sql(text){
  const args=['-X','-qAt','-v','ON_ERROR_STOP=1','-f','-'];
  const r=remoto
    ?spawnSync('psql',args,{input:text,encoding:'utf8',env:{...process.env,
      PGHOST:dbUrl.hostname,PGPORT:'5432',PGDATABASE:db,PGUSER:decodeURIComponent(dbUrl.username),
      PGPASSWORD:decodeURIComponent(dbUrl.password),PGSSLMODE:'require',PGCONNECT_TIMEOUT:'20'}})
    :spawnSync('docker',['exec','-i','supabase_db_avancecorp-f5-bank','psql','-U','supabase_admin','-d',db,...args],{input:text,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);return r.stdout.trim();
}
const obj=s=>JSON.parse(sql(s));
async function http(path,{token,service=false,body,method='POST',crm=true}={}){
  const r=await fetch(url+path.slice(1),{method,headers:{apikey:env.SUPABASE_ANON_KEY,
    Authorization:'Bearer '+(service?env.SUPABASE_SERVICE_ROLE_KEY:token??env.SUPABASE_ANON_KEY),
    'Content-Type':'application/json',...(crm?{'Accept-Profile':'crm','Content-Profile':'crm'}:{})},
    body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
  return {status:r.status,data:await r.json()};
}
const rpc=(fn,body,token)=>http('/rest/v1/rpc/'+fn,{body,token});
const ok=r=>{assert.equal(r.status,200,JSON.stringify(r.data));return r.data;};
const error=(r,code)=>{assert(r.status>=400,JSON.stringify(r));assert.equal(r.data.code,code,JSON.stringify(r.data));};
async function login(id){
  const u=await http('/auth/v1/admin/users/'+id,{service:true,crm:false,method:'PUT',body:{password:env.CRM_DEMO_PASSWORD}});
  assert.equal(u.status,200);
  return ok(await http('/auth/v1/token?grant_type=password',{crm:false,body:{email:u.data.email,password:env.CRM_DEMO_PASSWORD}})).access_token;
}
const equipo=obj("select jsonb_agg(jsonb_build_object('id',e.perfil_id,'rol',e.rol_crm,'nombre',p.nombre_completo)) from crm.equipo e join public.perfiles p on p.id=e.perfil_id where e.activo");
const actor=equipo.find(e=>e.nombre==='ANALISTA UNO').id,ajeno=equipo.find(e=>e.nombre==='ANALISTA DOS').id;
const gerente=equipo.find(e=>e.rol==='gerencia').id;
const supervisor=equipo.find(e=>e.nombre==='SUPERVISOR UNO').id;
const lector=sql("select id from public.perfiles where rol='directorio' limit 1");
// El banco de RLS contiene deliberadamente una fuente sin identidad para probar
// fail-closed. Retirarla SOLO de esta copia desechable antes de habilitar F5.
sql("begin;set local session_replication_role=replica;delete from crm.cierres_externos where inversionista_id is null;commit;update crm.multiempresa_flags set activo=true;");
const fuente=obj("select to_jsonb(ce) from crm.cierres_externos ce join crm.inversionistas i on i.id=ce.inversionista_id where ce.anulado_en is null and i.perfil_id is null and i.inversionista_canonico_id is null order by ce.id limit 1");
const persona=fuente.inversionista_id;
sql(`begin;set local session_replication_role=replica;
  update crm.inversionistas set creado_por=${q(actor)},responsable_relacion_id=${q(actor)},creado_en=now()-interval '1 hour' where id=${q(persona)};
  update crm.cierres_externos set creado_por=${q(actor)},vendedor_id=${q(actor)},creado_en=now()-interval '1 hour' where inversionista_id=${q(persona)};
  update crm.leads set creado_por=${q(actor)},creado_en=now()-interval '1 hour' where inversionista_id=${q(persona)};
  commit;`);
const tokens={actor:await login(actor),ajeno:await login(ajeno),gerente:await login(gerente),supervisor:await login(supervisor),lector:await login(lector)};
const contexto=(token=tokens.actor,id=persona,fuenteId)=>rpc('inversionista_gestion_fn',{p_inversionista:id,...(fuenteId?{p_fuente:fuenteId}:{})},token);
let ctx=ok(await contexto());assert.equal(ctx.contacto.puede_corregir,true);assert.equal(ctx.perfiles.length,0);
pass('Persona COOPAC sin Auth/perfil, autor y responsable vigente dentro de 5 h');
error(await contexto(tokens.ajeno),'42501');pass('Analista ajeno no lee la persona');
error(await rpc('inversionista_gestion_fn',{p_inversionista:persona}),'42501');
const datos={nombre_completo:'PERSONA CORREGIDA SINTÉTICA',telefono:'+51 999 111 222',domicilio:'DOMICILIO SINTÉTICO'};
const guardar=(revision,clave=randomUUID(),patch=datos,token=tokens.actor)=>rpc('inversionista_corregir_contacto_fn',{p_inversionista:persona,p_clave:clave,p_revision:revision,p_datos:patch},token);
const before=obj(`select to_jsonb(ce) from crm.cierres_externos ce where id=${q(fuente.id)}`);
const cuenta=tipo=>Number(sql(`select count(*) from crm.inversionista_gestiones where inversionista_id=${q(persona)} and tipo=${q(tipo)}`));
const contactosAntes=cuenta('correccion_contacto'),coopacAntes=cuenta('correccion_coopac');
const key=randomUUID(),rev=ctx.contacto.revision;
ok(await guardar(rev,key));ok(await guardar(rev,key));
assert.equal(cuenta('correccion_contacto'),contactosAntes+1);
assert.deepEqual(before,obj(`select to_jsonb(ce) from crm.cierres_externos ce where id=${q(fuente.id)}`));
ctx=ok(await contexto());assert.equal(ctx.contacto.nombre_completo,datos.nombre_completo);assert.equal(ctx.contacto.telefono,datos.telefono);
pass('Corrección contacta fuente neutral; conserva evidencia económica y devuelve recibo único al repetir');
error(await guardar(rev),'PT409');pass('Escritura con versión antigua rechazada');
let races=await Promise.all([guardar(ctx.contacto.revision,randomUUID(),{...datos,telefono:'999111223'}),guardar(ctx.contacto.revision,randomUUID(),{...datos,telefono:'999111224'})]);
assert.equal(races.filter(r=>r.status===200).length,1);error(races.find(r=>r.status!==200),'PT409');
pass('Dos guardados simultáneos: uno confirma y otro detecta conflicto');
ctx=ok(await contexto());
error(await guardar(ctx.contacto.revision,randomUUID(),{...datos,rol:'admin'}),'22023');
error(await http('/rest/v1/inversionista_datos_contacto?select=*',{token:tokens.actor,method:'GET'}),'42501');
pass('Campos extra y acceso directo a contacto rechazados');
// Mismo instante de transacción: prueba exactamente el límite, sin tolerancias.
for(const interval of ['4 hours 59 minutes 59 seconds','5 hours','5 hours 1 second']){
  const eligible=interval.startsWith('4');
  const s=sql(`begin;set local session_replication_role=replica;
    update crm.inversionistas set creado_en=now()-interval '${interval}' where id=${q(persona)};
    update crm.cierres_externos set creado_en=now()-interval '${interval}' where inversionista_id=${q(persona)};
    update crm.leads set creado_en=now()-interval '${interval}' where inversionista_id=${q(persona)};
    set local session_replication_role=origin;
    select set_config('request.jwt.claims',${q(JSON.stringify({sub:actor,role:'authenticated'}))},true);
    set local role authenticated;
    select crm.inversionista_gestion_fn(${q(persona)})#>>'{contacto,puede_corregir}';rollback;`);
  assert.equal(s.split('\n').at(-1),String(eligible));
}
pass('Ventana estricta antes, exactamente a las cinco horas y después');
sql(`begin;set local session_replication_role=replica;update crm.inversionistas set creado_en=now()-interval '2 days' where id=${q(persona)};commit;`);
assert.equal(ok(await contexto()).contacto.puede_corregir,false);error(await guardar(ctx.contacto.revision),'42501');
assert.equal(ok(await contexto(tokens.gerente)).contacto.puede_corregir,true);
ok(await guardar(rev,key));pass('Historia antigua no reinicia ventana; Gerencia conserva excepción y recibo anterior recuperable');
// Estado histórico real: no hay plazo/tasa; omitir vence_en no borra su fecha.
sql(`begin;set local session_replication_role=replica;
  update crm.cierres_externos set plazo_meses=null,tasa_anual=null,vence_en='2027-10-15' where id=${q(fuente.id)};
  set local session_replication_role=origin;
  select set_config('request.jwt.claims',${q(JSON.stringify({sub:gerente,role:'authenticated'}))},true);
  set local role authenticated;
  do $t$ declare c jsonb; begin
    c:=crm.inversionista_gestion_fn(${q(persona)},${q(fuente.id)});
    perform crm.inversionista_corregir_coopac_fn(${q(persona)},${q(fuente.id)},${q(randomUUID())},
      c#>>'{inversion,coopac,revision}',jsonb_build_object('monto',12345.67,'numero_transaccion',${q(fuente.numero_transaccion)},'nota','HISTÓRICA SINTÉTICA'));
    c:=crm.inversionista_gestion_fn(${q(persona)},${q(fuente.id)});
    assert c#>>'{inversion,coopac,vence_en}'='2027-10-15';
  end;$t$;rollback;`);
pass('COOPAC histórica sin condiciones: omitir vencimiento conserva la fecha anterior');
const coop=ok(await contexto(tokens.gerente,persona,fuente.id));assert.equal(coop.inversion.puede_corregir,true);
const coopDatos={monto:12345.67,numero_transaccion:'GESTION-'+randomUUID(),referencia:'CERTIFICADO SINTÉTICO',nota:'CORRECCIÓN SINTÉTICA',plazo_meses:12,tasa_anual:12.5,vence_en:null};
const coopKey=randomUUID();const patch={p_inversionista:persona,p_fuente:fuente.id,p_clave:coopKey,p_revision:coop.inversion.coopac.revision,p_datos:coopDatos};
error(await rpc('inversionista_corregir_coopac_fn',patch,tokens.actor),'42501');
ok(await rpc('inversionista_corregir_coopac_fn',patch,tokens.gerente));ok(await rpc('inversionista_corregir_coopac_fn',patch,tokens.gerente));
const after=ok(await contexto(tokens.gerente,persona,fuente.id)).inversion.coopac;
assert.equal(after.monto,12345.67);assert.equal(after.plazo_meses,12);assert.equal(after.tasa_anual,12.5);assert(after.vence_en);
assert.equal(cuenta('correccion_coopac'),coopacAntes+1);
error(await rpc('inversionista_corregir_coopac_fn',{...patch,p_clave:randomUUID()},tokens.gerente),'PT409');
pass('COOPAC Gerencia: monto, plazo, tasa, vencimiento atómicos, recibo y control de versión');
const contrato=obj("select to_jsonb(c) from public.contratos c join crm.inversionistas i on i.perfil_id=c.cliente_id where i.inversionista_canonico_id is null order by c.id limit 1");
const personaAvance=sql(`select id from crm.inversionistas where perfil_id=${q(contrato.cliente_id)} and inversionista_canonico_id is null`);
const av=ok(await contexto(tokens.gerente,personaAvance,contrato.id));assert.equal(av.inversion.contrato.id,contrato.id);assert.equal(av.inversion.coopac,null);
error(await contexto(tokens.gerente,persona,contrato.id),'P0409');
const di=ok(await contexto(tokens.lector,personaAvance,contrato.id));assert.equal(di.inversion.puede_corregir,false);assert.equal(di.inversion.puede_reasignar,false);assert(di.perfiles.every(p=>!p.puede_corregir&&p.domicilio===null));
assert.equal(di.contacto.domicilio,null);assert.equal(di.contacto.revision,null);
error(await contexto(tokens.lector,persona,fuente.id),'42501');
pass('Contrato concreto vinculado; inversión cruzada rechazada; Directorio lectura Avance sin correcciones');
const camposContrato=['id','numero_contrato','cliente_id','cliente_nombre','asesor_perfil_id','capital','moneda','tasa_anual','modalidad','tipo_interes','categoria','estado','fecha_inicio','fecha_vencimiento','notas_internas','creado_por','creado_en','producto_condicion_id','producto_id','producto_codigo','producto_version_id','producto_version','producto_nombre','producto_version_estado','fecha_cierre_comercial'];
assert.deepEqual(Object.keys(di.inversion.contrato).sort(),camposContrato.sort());
const vistaDirectorio=ok(await http('/rest/v1/contratos_cartera?id=eq.'+contrato.id,{token:tokens.lector,method:'GET'}))[0];
assert.deepEqual(di.inversion.contrato,vistaDirectorio);
pass('Directorio recibe exactamente las columnas y redacción del lector Avance publicado');
const pagoId=randomUUID(),titularId=randomUUID();
sql(`begin;set local session_replication_role=replica;
  insert into public.cronograma_pagos(id,contrato_id,numero_cuota,fecha_programada,monto_programado,estado,fecha_pago_real,monto_pagado,tipo)
    values(${q(pagoId)},${q(contrato.id)},9999,'2026-08-01',12.5,'pagado','2026-08-02',12.5,'cuota');
  insert into public.contrato_titulares(id,contrato_id,orden,nombre_completo,tipo_documento,documento,creado_por)
    values(${q(titularId)},${q(contrato.id)},5,'COTITULAR SINTÉTICO','DNI','99119911',${q(gerente)});
  commit;`);
const pagoAntes=obj(`select to_jsonb(c) from public.cronograma_pagos c where id=${q(pagoId)}`);
const titularesAntes=sql(`select jsonb_agg(to_jsonb(t) order by t.id) from public.contrato_titulares t where contrato_id=${q(contrato.id)}`);
const cuentasAntes=sql(`select jsonb_agg(to_jsonb(c) order by c.id) from crm.contrato_cuentas_pago c where contrato_id=${q(contrato.id)}`);
const correccion={p_id:contrato.id,p_contrato:{...Object.fromEntries(['capital','moneda','tasa_anual','modalidad','tipo_interes','categoria','fecha_inicio','fecha_vencimiento','numero_contrato'].map(k=>[k,contrato[k]])),notas_internas:'CORRECCIÓN MULTIEMPRESA DE ENSAYO'},
  p_cronograma:[{numero_cuota:9999,fecha_programada:'2026-08-01',monto_programado:99,tipo:'cuota'}]};
assert.equal(av.inversion.puede_corregir,true);
ok(await rpc('actualizar_contrato_con_cuenta_pdf_v3',correccion,tokens.gerente));
assert.deepEqual(obj(`select to_jsonb(c) from public.cronograma_pagos c where id=${q(pagoId)}`),pagoAntes);
assert.equal(sql(`select jsonb_agg(to_jsonb(t) order by t.id) from public.contrato_titulares t where contrato_id=${q(contrato.id)}`),titularesAntes);
assert.equal(sql(`select jsonb_agg(to_jsonb(c) order by c.id) from crm.contrato_cuentas_pago c where contrato_id=${q(contrato.id)}`),cuentasAntes);
pass('Escritor Avance real: Gerencia corrige histórico y conserva pago real, cotitulares omitidos y cuenta contractual');
const rolAnterior=sql(`select rol from public.perfiles where id=${q(actor)}`);
sql(`begin;set local session_replication_role=replica;update public.perfiles set rol='analista' where id=${q(actor)};
  update public.contratos set creado_por=${q(actor)},creado_en=now()-interval '1 hour' where id=${q(contrato.id)};commit;`);
assert.equal(ok(await contexto(tokens.actor,personaAvance,contrato.id)).inversion.puede_corregir,true);
ok(await rpc('actualizar_contrato_con_cuenta_pdf_v3',correccion,tokens.actor));
sql(`begin;set local session_replication_role=replica;update public.contratos set creado_en=now()-interval '5 hours' where id=${q(contrato.id)};commit;`);
assert.equal(ok(await contexto(tokens.actor,personaAvance,contrato.id)).inversion.puede_corregir,false);
error(await rpc('actualizar_contrato_con_cuenta_pdf_v3',correccion,tokens.actor),'42501');
sql(`begin;set local session_replication_role=replica;update public.perfiles set rol=${q(rolAnterior)} where id=${q(actor)};
  delete from public.cronograma_pagos where id=${q(pagoId)};delete from public.contrato_titulares where id=${q(titularId)};commit;`);
sql(`begin;set local session_replication_role=replica;
  update public.contratos set creado_en=now()-interval '1 hour' where id=${q(contrato.id)};commit;`);
assert.equal(ok(await contexto(tokens.actor,personaAvance,contrato.id)).inversion.puede_corregir,false);
error(await rpc('actualizar_contrato_con_cuenta_pdf_v3',correccion,tokens.actor),'42501');
pass('Vendedor comercial sin rol analista: capacidad coincide con rechazo del escritor PDF existente');
pass('Capacidad Avance coincide con escritor real para analista propio dentro y fuera de cinco horas');
for(const valor of [{monto:'no numérico'},{plazo_meses:12.5},{plazo_meses:null,tasa_anual:null}]){
  const revision=ok(await contexto(tokens.gerente,persona,fuente.id)).inversion.coopac.revision;
  error(await rpc('inversionista_corregir_coopac_fn',{...patch,p_clave:randomUUID(),p_revision:revision,p_datos:{...coopDatos,...valor}},tokens.gerente),'22023');
}
pass('Payload numérico inválido y quitar condiciones existentes producen rechazo definitivo 22023');
const anulada=obj("select to_jsonb(ce) from crm.cierres_externos ce where anulado_en is not null limit 1");
const ctxAnulada=ok(await contexto(tokens.gerente,anulada.inversionista_id,anulada.id));
assert.equal(ctxAnulada.inversion.puede_corregir,false);
error(await rpc('inversionista_corregir_coopac_fn',{...patch,p_inversionista:anulada.inversionista_id,p_fuente:anulada.id,p_clave:randomUUID(),p_revision:ctxAnulada.inversion.coopac.revision},tokens.gerente),'P0409');
pass('Inversión anulada: capacidad deshabilitada y rechazo del escritor');
const neutralAudit=obj(`select metadata from crm.inversionista_gestiones where inversionista_id=${q(persona)} and tipo='correccion_coopac' order by creado_en desc limit 1`);
assert.equal(neutralAudit.antes.monto,before.monto);assert.equal(neutralAudit.despues.monto,coopDatos.monto);
if(fuente.lead_id)assert.equal(sql(`select activo from crm.leads where id=${q(fuente.lead_id)}`),'f');
pass('COOPAC con lead archivado conserva antes/después económico en la gestión neutral');
const antesDirecto=obj(`select to_jsonb(ce) from crm.cierres_externos ce where id=${q(fuente.id)}`);
const directo=await rpc('corregir_cierre_externo',{p_cierre_id:fuente.id,p_monto:coopDatos.monto,p_moneda:fuente.moneda,p_cooperativa:fuente.cooperativa,p_numero_transaccion:coopDatos.numero_transaccion,p_referencia:coopDatos.referencia,p_vence_en:after.vence_en,p_nota:coopDatos.nota},tokens.gerente);
assert(directo.status>=400,JSON.stringify(directo));assert.match(directo.data.message,/lead.*responsable/i);
assert.deepEqual(obj(`select to_jsonb(ce) from crm.cierres_externos ce where id=${q(fuente.id)}`),antesDirecto);
pass('Llamada directa COOPAC sobre lead archivado conserva rechazo anterior y no deja cambios');
const rolGerente=sql(`select rol from public.perfiles where id=${q(gerente)}`);
assert.equal(ok(await contexto(tokens.gerente)).documento.puede_corregir,false);
sql(`begin;set local session_replication_role=replica;update public.perfiles set rol='admin' where id=${q(gerente)};commit;`);
const adminCtx=ok(await contexto(tokens.gerente));assert.equal(adminCtx.contacto.puede_corregir,true);assert.equal(adminCtx.documento.puede_corregir,true);
sql(`begin;set local session_replication_role=replica;update public.perfiles set rol=${q(rolGerente)} where id=${q(gerente)};commit;`);
pass('Administración conserva corrección documental; Gerencia sola no la recibe');
for(const autor of [actor,supervisor]){
  const valor=sql(`begin;set local session_replication_role=replica;
    update crm.inversionistas set responsable_relacion_id=${q(supervisor)},creado_por=${q(autor)},creado_en=now()-interval '1 hour' where id=${q(persona)};
    update crm.cierres_externos set creado_por=${q(autor)},creado_en=now()-interval '1 hour' where inversionista_id=${q(persona)};
    update crm.leads set creado_por=${q(autor)},creado_en=now()-interval '1 hour' where inversionista_id=${q(persona)};
    set local session_replication_role=origin;select set_config('request.jwt.claims',${q(JSON.stringify({sub:supervisor,role:'authenticated'}))},true);
    set local role authenticated;select crm.inversionista_gestion_fn(${q(persona)})#>>'{contacto,puede_corregir}';rollback;`);
  assert.equal(valor.split('\n').at(-1),String(autor===supervisor));
}
pass('Supervisor responsable: requiere autoría original dentro de su ventana');
// Un alias anterior no reinicia el reloj ni pierde el contacto vigente. Toda
// esta variante se revierte al finalizar para poder repetir el ensayo.
const alias=randomUUID();
const fusion=sql(`begin;set local session_replication_role=replica;
  insert into crm.inversionistas(id,estado,responsable_relacion_id,inversionista_canonico_id,fusionado_en,creado_en,creado_por)
    values(${q(alias)},'fusionado',${q(actor)},${q(persona)},now(),now()-interval '10 days',${q(ajeno)});
  insert into crm.inversionista_datos_contacto(inversionista_id,nombre_completo,telefono,revision,actualizado_por)
    values(${q(alias)},'CONTACTO DEL ALIAS','999111999',41,${q(gerente)});
  set local session_replication_role=origin;
  select set_config('request.jwt.claims',${q(JSON.stringify({sub:actor,role:'authenticated'}))},true);
  set local role authenticated;
  do $t$ declare c jsonb; begin
    c:=crm.inversionista_gestion_fn(${q(alias)});
    assert c->>'inversionista_id'=${q(persona)};
    assert c#>>'{contacto,nombre_completo}'='CONTACTO DEL ALIAS';
    assert (c#>>'{contacto,puede_corregir}')::boolean=false;
  end;$t$;
  reset role;select set_config('request.jwt.claims',${q(JSON.stringify({sub:gerente,role:'authenticated'}))},true);set local role authenticated;
  do $t$ declare c jsonb;r jsonb; begin
    c:=crm.inversionista_gestion_fn(${q(persona)});
    r:=crm.inversionista_corregir_contacto_fn(${q(alias)},${q(randomUUID())},c#>>'{contacto,revision}',${q(JSON.stringify(datos))}::jsonb);
    assert (r->>'revision')::integer=42;
    assert r->>'inversionista_id'=${q(persona)};
    c:=crm.inversionista_gestion_fn(${q(persona)});
    assert c#>>'{contacto,nombre_completo}'=${q(datos.nombre_completo)};
  end;$t$;
  reset role;
  do $t$ begin
    assert (select revision=42 from crm.inversionista_datos_contacto where inversionista_id=${q(persona)});
    assert (select revision=41 from crm.inversionista_datos_contacto where inversionista_id=${q(alias)});
    assert (select inversionista_id=${q(persona)} from crm.inversionista_gestiones where tipo='correccion_contacto' order by creado_en desc limit 1);
  end;$t$;rollback;`);
assert(fusion);pass('Fusión: autor y fecha más antiguos, contacto del alias y revisión monotónica');
sql(`begin;set local session_replication_role=replica;update crm.inversionistas set responsable_relacion_id=${q(ajeno)} where id=${q(persona)};commit;`);
error(await contexto(),'42501');error(await guardar(ctx.contacto.revision),'42501');
sql(`begin;set local session_replication_role=replica;update crm.inversionistas set responsable_relacion_id=${q(actor)} where id=${q(persona)};commit;`);
pass('Cambio de responsable invalida lectura y escritura del anterior');
sql(`begin;set local session_replication_role=replica;update crm.equipo set activo=false where perfil_id=${q(actor)};commit;`);
error(await contexto(),'42501');error(await guardar(ctx.contacto.revision),'42501');
sql(`begin;set local session_replication_role=replica;update crm.equipo set activo=true where perfil_id=${q(actor)};commit; update crm.multiempresa_flags set activo=false where nombre='postventa_neutral'`);
assert.equal(ok(await contexto(tokens.gerente)).contacto.puede_corregir,false);error(await guardar(ctx.contacto.revision,randomUUID(),datos,tokens.gerente),'P0409');
sql("update crm.multiempresa_flags set activo=true where nombre='postventa_neutral'");
pass('Revocación y apagado del módulo bloquean las escrituras por servidor');
writeFileSync(process.argv[3]??'/private/tmp/gestion-multiempresa-http-evidencia.json',JSON.stringify({fecha:new Date().toISOString(),destino:url.origin,db,checks},null,2)+'\n');
console.log(`${checks.length} grupos de verificaciones PASS; banco sintético ${remoto?'remoto autorizado':'local'}.`);
