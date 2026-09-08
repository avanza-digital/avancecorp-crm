import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { crearCopiaSql } from './copia-sql-local.mjs';
import { sql as originalSql, literal as q, leer } from './banco-local.mjs';
import { contratoPrueba } from './operaciones-fixture.mjs';
const f=leer('fixtures.json'),base=leer('operaciones-base.json'),g=f.usuarios.gerencia.id,v=f.usuarios.vendedor.id;
const copia=crearCopiaSql('correccion_datos'),{sql}=copia,pruebas=[];
const j=v=>q(JSON.stringify(v)),claims=actor=>`set local request.jwt.claims=${j({sub:actor,role:'authenticated'})};set local role authenticated;`;
const como=(actor,consulta)=>sql(`\\set VERBOSITY verbose
begin;set local statement_timeout='15s';${claims(actor)}${consulta};commit;`);
const llamada=(fn,args)=>`select crm.${fn}(${args.join(',')})`;
const rpc=(fn,args,actor=g)=>JSON.parse(como(actor,llamada(fn,args)));
const motivo='Corrección explícita de las condiciones ficticias antes de confirmar';
const corregir=(s,d,rev=0,key=randomUUID(),m=motivo,actor=g)=>rpc('corregir_solicitud_inversion_fn',[q(s),q(key),rev,j(d),q(m)],actor);
const consulta=s=>rpc('solicitud_inversion_fn',[q(s)]);
const confirmar=(s,rev)=>rev===undefined?rpc('confirmar_inversion_fn',[q(s)]):rpc('confirmar_inversion_revisada_fn',[q(s),rev]);
const tablas=['public.contratos','public.cronograma_pagos','crm.cierres_externos','crm.operaciones_cartera','crm.inversiones','crm.inversion_titulares','crm.periodos_cerrados'];
const fotoSql=`select private.idem_hash(jsonb_object_agg(tabla,filas)) from (${tablas.map(t=>`select ${q(t)} tabla,coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') filas from ${t} t`).join(' union all ')}) x`;
const original=originalSql(fotoSql);
function caso(nombre,fn){fn();pruebas.push({nombre,conforme:true});console.log('PASS: '+nombre);}
function coop(empresa='qorilazo'){
 const id=randomUUID(),datos={inversionista_id:base.identidades.avance,empresa,monto:100,moneda:'PEN',fecha_comercial:'2026-09-01',
 vence_en:'2027-09-01',numero_transaccion:'F4-CD-'+id,referencia:'ENSAYO FICTICIO',evidencia:{ruta:`${base.identidades.avance}/${id}/comprobante.png`}};
 rpc('preparar_inversion_fn',[q(id),j(datos)]);
 // Metadatos de Storage sólo en la copia SQL. El transporte real tiene su banco HTTP independiente.
 sql(`insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',${q(datos.evidencia.ruta)},'{"size":12,"mimetype":"image/png"}')`);
 return {id,datos};
}
function avance(persona=base.identidades.avance,perfil=f.usuarios.cliente.id){
 const id=randomUUID(),d=contratoPrueba(perfil,v,{inicio:'2026-09-01'}),datos={inversionista_id:persona,empresa:'avance',...d};
 if(!perfil) datos.alta_portal={correo:`f4-correccion-${id}@example.test`,nombre_completo:'PERSONA FICTICIA DE CORRECCION',domicilio:'AVENIDA FICTICIA 123, LIMA, PERU'};
 rpc('preparar_inversion_fn',[q(id),j(datos)]);return {id,datos};
}
try {
 sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
 const s=coop(),edit={...s.datos,monto:235.12,referencia:'Referencia ficticia corregida',numero_transaccion:'F4-EDIT-'+s.id};const key=randomUUID();
 const finAntes=sql(fotoSql),hashOriginal=sql(`select hash_payload from crm.inversion_solicitudes where id=${q(s.id)}`);
 caso('Corrección cambia la misma solicitud, aumenta versión y conserva la huella inicial',()=>{
  const r=corregir(s.id,edit,0,key);assert.equal(r.revision_datos,1);assert.equal(r.revision_aplicada,1);
  assert.equal(sql(`select hash_payload from crm.inversion_solicitudes where id=${q(s.id)}`),hashOriginal);
  assert.equal(sql(fotoSql),finAntes);assert.deepEqual(consulta(s.id).datos,edit);
 });
 caso('Preparar original recupera los datos corregidos; misma clave con otros datos falla',()=>{
  assert.equal(rpc('preparar_inversion_fn',[q(s.id),j(s.datos)]).revision_datos,1);
  assert.throws(()=>rpc('preparar_inversion_fn',[q(s.id),j(edit)]),/P0409/);
 });
 caso('Clave de corrección es idempotente y está ligada también al motivo',()=>{
  assert.equal(corregir(s.id,edit,0,key).reintento,true);
  assert.throws(()=>corregir(s.id,edit,0,key,'Otro motivo ficticio diferente al original'),/P0409/);
  assert.throws(()=>corregir(s.id,{...edit,monto:500},0,key),/P0409/);
  assert.equal(sql(`select count(*) from crm.inversion_solicitud_correcciones where solicitud_id=${q(s.id)}`),'1');
 });
 caso('Edición obsoleta y confirmación antigua fallan antes de escribir fuentes',()=>{
  assert.throws(()=>corregir(s.id,{...edit,monto:500},0),/40001/);
  assert.throws(()=>confirmar(s.id),/40001/);assert.throws(()=>confirmar(s.id,0),/40001/);assert.throws(()=>confirmar(s.id,2),/40001/);
  assert.equal(sql(fotoSql),finAntes);
 });
 caso('No se puede sustituir persona, empresa ni ruta del comprobante',()=>{
  for(const datos of [{...edit,empresa:'prodelco'},{...edit,inversionista_id:base.identidades.qorilazo},
   {...edit,evidencia:{ruta:`${base.identidades.avance}/${s.id}/otro.png`}}]) assert.throws(()=>corregir(s.id,datos,1),/22023/);
 });
 caso('Validador compartido rechaza importes, monedas, fechas y campos inválidos',()=>{
  for(const cambio of [{monto:0},{monto:1.001},{monto:'NaN'},{moneda:'USD'},{vence_en:'2026-08-01'},{fecha_comercial:'infinity'},{intruso:true}])
   assert.throws(()=>corregir(s.id,{...edit,...cambio},1),/22023/);
  assert.equal(sql(fotoSql),finAntes);
 });
 caso('No-op sin cambio no consume una revisión ni una clave',()=>{
  assert.throws(()=>corregir(s.id,edit,1),/22023/);assert.equal(consulta(s.id).revision_datos,1);
 });
 let confirmada;
 caso('Confirmación revisada crea una única fuente con las condiciones corregidas',()=>{
  confirmada=confirmar(s.id,1);assert.equal(confirmada.revision_datos,1);
  const c=JSON.parse(sql(`select to_jsonb(c) from crm.cierres_externos c where id=${q(confirmada.fuente.cierre_id)}`));
  assert.equal(c.monto,235.12);assert.equal(c.numero_transaccion,edit.numero_transaccion.toUpperCase());assert.equal(c.referencia_externa,edit.referencia);
 });
 caso('Confirmada conserva replay con versión antigua; nuevas correcciones se rechazan',()=>{
  const antes=sql(fotoSql);assert.equal(confirmar(s.id).inversion_id,confirmada.inversion_id);assert.equal(confirmar(s.id,99).inversion_id,confirmada.inversion_id);
  assert.equal(corregir(s.id,edit,0,key).reintento,true);assert.throws(()=>corregir(s.id,{...edit,monto:700},1),/P0409/);assert.equal(sql(fotoSql),antes);
 });
 caso('Historial de correcciones es inmutable y la auditoría omite datos y motivos',()=>{
  for(const comando of [`update crm.inversion_solicitud_correcciones set motivo='otro motivo'`,`delete from crm.inversion_solicitud_correcciones`])
   assert.throws(()=>sql(`\\set VERBOSITY verbose
    ${comando} where solicitud_id=${q(s.id)}`),/P0409/);
  const filas=JSON.parse(sql(`select coalesce(jsonb_agg(data_despues),'[]') from public.audit_log where tabla='crm.inversion_solicitud_correcciones' and fila_id=${q(key)}`));
  assert.equal(filas.length,1);for(const campo of ['datos_anteriores','datos_nuevos','motivo','hash_peticion','hash_anterior','hash_nuevo']) assert.equal(filas[0][campo],'***');
 });
 caso('Lectura y replay revalidan permisos actuales y no entregan datos a terceros',()=>{
  for(const rol of ['ajeno','supervisor_ajeno','directorio','cliente']){
   assert.throws(()=>rpc('solicitud_inversion_fn',[q(s.id)],f.usuarios[rol].id),/42501/);
   assert.throws(()=>corregir(s.id,edit,0,key,motivo,f.usuarios[rol].id),/42501/);
  }
 });
 caso('Segunda cooperativa confirma corrección con el mismo control de versión',()=>{
  const p=coop('prodelco');corregir(p.id,{...p.datos,monto:347.56});const r=confirmar(p.id,1);
  assert.equal(sql(`select monto from crm.cierres_externos where id=${q(r.fuente.cierre_id)}`),'347.56');
 });
 const av=avance(),avEdit={...av.datos,...contratoPrueba(f.usuarios.cliente.id,v,{inicio:'2026-09-01',capital:1800})};
 caso('Avance conserva cliente y analista originales en la corrección',()=>{
  for(const campo of ['cliente_id','analista_cierre_id']) assert.throws(()=>corregir(av.id,{...avEdit,contrato:{...avEdit.contrato,[campo]:randomUUID()}}),/22023/);
 });
 caso('Corrección Avance confirma capital, cronograma, cuenta y snapshot coherentes',()=>{
  corregir(av.id,avEdit);const r=confirmar(av.id,1);
  assert.equal(sql(`select capital from public.contratos where id=${q(r.fuente.id)}`),'1800.00');
  assert.equal(sql(`select count(*) from public.cronograma_pagos where contrato_id=${q(r.fuente.id)}`),'13');
  assert.equal(sql(`select private.contrato_documental_congelado(${q(r.fuente.id)})`),'t');
 });
 const reserva=avance(base.identidades.qorilazo,null),reservaEdit={...reserva.datos,contrato:{...reserva.datos.contrato,capital:2100}};
 caso('Se puede corregir alta Portal antes de reservarla',()=>{
  reservaEdit.alta_portal={...reserva.datos.alta_portal,nombre_completo:'NOMBRE LEGAL FICTICIO CORREGIDO'};
  corregir(reserva.id,reservaEdit);assert.equal(consulta(reserva.id).revision_datos,1);
 });
 caso('Claim real congela datos Auth; corrección económica conserva token, versión y contexto',()=>{
  rpc('acceso_inversion_fn',[q(reserva.id),"'reclamar'","'{}'"]);
  const foto=()=>sql(`select private.idem_hash(jsonb_build_object('contexto',s.auth_contexto,'claim',s.auth_claim_id,'saga',to_jsonb(m)))
   from crm.inversion_solicitudes s join crm.multiempresa_idempotencia m on m.clave='auth_persona:'||s.inversionista_id::text where s.id=${q(reserva.id)}`);
  const antes=foto();assert.throws(()=>corregir(reserva.id,{...reservaEdit,alta_portal:{...reservaEdit.alta_portal,correo:'otro-ficticio@example.test'}},1),/P0409/);
  corregir(reserva.id,{...reservaEdit,cronograma:contratoPrueba(null,v,{inicio:'2026-09-01',capital:2100}).cronograma},1);
  assert.equal(foto(),antes);
 });
 const rr=avance(),rrEdit={...rr.datos,...contratoPrueba(f.usuarios.cliente.id,v,{inicio:'2026-09-01',capital:1900})};
 caso('Cambio de responsable exige revisión explícita antes de corregir condiciones',()=>{
  rpc('reasignar_responsable_relacion_fn',[q(base.identidades.avance),q(f.usuarios.ajeno.id),"'Reasignación ficticia del ensayo de corrección de condiciones'"]);
  assert.throws(()=>corregir(rr.id,rrEdit),/P0409/);
  rpc('revisar_solicitud_inversion_fn',[q(rr.id),q(f.usuarios.ajeno.id),0,"'Revisión explícita del responsable ficticio antes de confirmar'"]);
  corregir(rr.id,rrEdit);const r=confirmar(rr.id,1);
  assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(r.fuente.id)}`),f.usuarios.ajeno.id);
  assert.equal(consulta(rr.id).datos.contrato.analista_cierre_id,v);
 });
 async function carrera(nombre,primero,segundo,codigo){
  const a=copia.abrirSesion('f4_revision_primero'),b=copia.abrirSesion('f4_revision_segundo');
  a.enviar(`\\set VERBOSITY verbose\nbegin;${claims(g)}${primero};select 'PRIMERO_LISTO';`);
  await copia.esperar(()=>a.salida().includes('PRIMERO_LISTO'),'Primera operación no llegó a la barrera');
  b.enviar(`\\set VERBOSITY verbose\nbegin;set local statement_timeout='12s';${claims(g)}${segundo};commit;`);
  await copia.esperar(()=>sql("select count(*) from pg_stat_activity where datname=current_database() and application_name='f4_revision_segundo' and wait_event_type='Lock'")==='1','La segunda operación no esperó el bloqueo');
  assert.equal((await a.cerrar('commit;')).codigo,0);const r=await b.cerrar('');
  assert.notEqual(r.codigo,0);assert(r.error.includes(codigo),r.error);pruebas.push({nombre,conforme:true});console.log('PASS: '+nombre);
 }
 const race=coop(),d1={...race.datos,monto:222},d2={...race.datos,monto:333};
 const corSql=(p,d)=>llamada('corregir_solicitud_inversion_fn',[q(p.id),q(randomUUID()),0,j(d),q(motivo)]);
 await carrera('Dos correcciones simultáneas sólo aceptan una revisión',corSql(race,d1),corSql(race,d2),'40001');
 assert.equal(consulta(race.id).datos.monto,222);
 const race2=coop();await carrera('Corrección antes de confirmar rechaza pantalla desactualizada',corSql(race2,{...race2.datos,monto:444}),llamada('confirmar_inversion_fn',[q(race2.id)]),'40001');
 assert.equal(consulta(race2.id).estado,'preparada');
 const race3=coop();await carrera('Confirmación antes de corregir conserva fuente y rechaza edición tardía',llamada('confirmar_inversion_fn',[q(race3.id)]),corSql(race3,{...race3.datos,monto:555}),'P0409');
 assert.equal(consulta(race3.id).estado,'confirmada');
} finally {assert.equal(originalSql(fotoSql),original);}
writeFileSync(new URL(`../evidencia-f4/correccion-solicitud-${copia.id}.json`,import.meta.url),JSON.stringify({
 entorno:'avancecorp-f4-bank',baseCopia:copia.nombre,terminadoEn:new Date().toISOString(),pruebas,bancoOriginalSinCambios:true,
 sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
 limite:'SQL con rol/claims sintéticos y metadatos Storage del ensayo. Preparación, corrección, reserva Auth, revisión y confirmación por RPC real; no envía correo ni procesa bytes PDF.',
},null,2)+'\n',{flag:'wx'});
console.log(`Corrección de solicitudes: ${pruebas.length} grupos conformes.`);
