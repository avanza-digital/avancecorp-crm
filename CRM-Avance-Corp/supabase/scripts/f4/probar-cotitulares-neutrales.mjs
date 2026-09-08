import assert from 'node:assert/strict';
import { randomInt, randomUUID, createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { crearCopiaSql } from './copia-sql-local.mjs';
import { sql as sqlOriginal, literal as q, leer } from './banco-local.mjs';
import { contratoPrueba } from './operaciones-fixture.mjs';
const f=leer('fixtures.json'),base=leer('operaciones-base.json'),gerente=f.usuarios.gerencia.id,vendedor=f.usuarios.vendedor.id;
const copia=crearCopiaSql('cotitulares'),{sql}=copia,pruebas=[];
const j=v=>q(JSON.stringify(v)),claims=actor=>`set local request.jwt.claims=${j({sub:actor,role:'authenticated'})};set local role authenticated;`;
const como=(actor,consulta)=>sql(`\\set VERBOSITY verbose
begin;set local statement_timeout='15s';${claims(actor)}${consulta};commit;`);
const rpc=(fn,args,actor=gerente)=>JSON.parse(como(actor,`select crm.${fn}(${args.join(',')})`));
function caso(nombre,fn){fn();pruebas.push({nombre,conforme:true});console.log('PASS: '+nombre);}
const tablas=['public.contratos','public.contrato_titulares','public.cronograma_pagos','crm.cierres_externos','crm.operaciones_cartera','private.contrato_pdfs','crm.inversion_cotitular_origenes'];
const foto=(ts)=>sql(`select private.idem_hash(jsonb_object_agg(tabla,filas)) from (${ts.map(t=>`select ${q(t)} tabla,coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') filas from ${t} t`).join(' union all ')}) x`);
const fotoOriginal=sqlOriginal('select private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by id),\'[]\')) from crm.inversiones t');
const doc=()=>`008${String(randomInt(1_000_000)).padStart(6,'0')}`;
function persona(documento=doc()){
 const id=randomUUID(); sql(`insert into crm.inversionistas(id,creado_por) values(${q(id)},${q(gerente)})`);
 rpc('corregir_documento_inversionista_fn',[q(id),"'CE'",q(documento),"'Verificación documental de persona ficticia del ensayo'"]);
 rpc('reasignar_responsable_relacion_fn',[q(id),q(vendedor),"'Asignación de persona ficticia para ensayo de cotitularidad'"]);
 return {id,documento,tipo:'CE'};
}
const titular=p=>({nombre_completo:'COTITULAR FICTICIO F4',tipo_documento:p.tipo,documento:p.documento});
function alta(titulares){
 const datos=contratoPrueba(f.usuarios.cliente.id,vendedor,{inicio:'2026-09-01'});
 datos.contrato.titulares=titulares;
 const r=rpc('crear_contrato_con_cuenta_pdf_v2',[j(datos.contrato),j(datos.cronograma),j(datos.cuenta)]);
 return {contrato:r.id,inversion:sql(`select id from crm.inversiones where contrato_id=${q(r.id)}`)};
}
const estado=i=>rpc('inversion_cotitulares_fn',[q(i)]);
const conciliar=i=>rpc('conciliar_cotitulares_inversion_fn',[q(i)]);
function fusion(p,c){
 const pre=rpc('fusion_previsualizar_fn',[q(p),q(c)]); assert.equal(pre.viable,true,JSON.stringify(pre.bloqueos));
 return rpc('fusionar_inversionistas_fn',[q(p),q(c),"'Fusión autorizada de identidades ficticias del ensayo'",q(pre.hash)]);
}
try {
 sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
 const a=persona(),b=persona(),pendiente={tipo:'CE',documento:doc()};
 const principal=JSON.parse(sql(`select jsonb_build_object('tipo',tipo_documento,'documento',documento_normalizado)
 from crm.inversionista_identificadores where inversionista_id=${q(base.identidades.avance)} and verificado and estado='vigente' limit 1`));
 sql(`update crm.inversionistas set no_contactar=true,no_contactar_en=now(),no_contactar_por=${q(gerente)} where id=${q(a.id)}`);
 const cuentasAntes=sql('select count(*) from auth.users'),leadsAntes=sql('select count(*) from crm.leads');
 const op=alta([titular(a),titular(a),titular(principal),titular(pendiente)]);
 caso('Alta real con snapshot vincula cotitular verificado aunque tenga No insistir',()=>{
  const e=estado(op.inversion);assert.equal(e.length,4);assert.equal(e[0].estado,'vinculado');assert.equal(e[0].inversionista_id,a.id);
  assert.equal(e[0].origen_registro,'alta');assert.equal(e[3].estado,'pendiente');
 });
 caso('Dos filas documentales conservan dos procedencias y una sola membresía',()=>{
  assert.equal(sql(`select count(*) from crm.inversion_titulares where inversion_id=${q(op.inversion)} and inversionista_id=${q(a.id)}`),'1');
  assert.equal(sql(`select count(*) from crm.inversion_cotitular_origenes where inversion_id=${q(op.inversion)} and persona_origen_id=${q(a.id)}`),'2');
 });
 caso('Cotitular igual al principal conserva rol principal, Auth y leads',()=>{
  assert.equal(sql(`select rol from crm.inversion_titulares where inversion_id=${q(op.inversion)} and inversionista_id=${q(base.identidades.avance)}`),'principal');
  assert.equal(sql('select count(*) from auth.users'),cuentasAntes);assert.equal(sql('select count(*) from crm.leads'),leadsAntes);
 });
 caso('Datos de procedencia no se filtran en lector ni auditoría',()=>{
  assert(!/hash_fuente|identificador_id|fuente_snapshot|identificador_snapshot/.test(JSON.stringify(estado(op.inversion))));
  const auditoria=JSON.parse(sql(`select jsonb_agg(data_despues) from public.audit_log where tabla='crm.inversion_cotitular_origenes' and data_despues->>'inversion_id'=${q(op.inversion)}`));
  assert.equal(auditoria.length,3);for(const fila of auditoria) for(const campo of ['hash_fuente','fuente_snapshot','identificador_snapshot']) assert.equal(fila[campo],'***');
  for(const rol of ['anon','authenticated','service_role']) assert.equal(sql(`select has_table_privilege(${q(rol)},'crm.inversion_cotitular_origenes','SELECT,INSERT,UPDATE,DELETE')`),'f');
 });
 caso('Conciliación repetida no duplica relaciones ni reescribe fuentes',()=>{
  const antes=foto(tablas);conciliar(op.inversion);conciliar(op.inversion);assert.equal(foto(tablas),antes);
 });
 caso('Procedencia y fuente quedan inmutables incluso con válvula documental',()=>{
  assert.throws(()=>sql(`\\set VERBOSITY verbose
  update crm.inversion_cotitular_origenes set origen_registro='conciliacion' where inversion_id=${q(op.inversion)}`),/P0409/);
  assert.throws(()=>sql(`\\set VERBOSITY verbose
  delete from crm.inversion_cotitular_origenes where inversion_id=${q(op.inversion)}`),/P0409/);
  assert.throws(()=>sql(`\\set VERBOSITY verbose
  begin;select set_config('crm.op_privilegiada','on',true);update public.contrato_titulares set nombre_completo='OTRO NOMBRE' where contrato_id=${q(op.contrato)} and orden=1;commit;`),/55000/);
  assert.throws(()=>sql(`\\set VERBOSITY verbose
  delete from public.contrato_titulares where contrato_id=${q(op.contrato)} and orden=1`),/55000/);
  sql(`update public.contrato_titulares set nombre_completo=nombre_completo where contrato_id=${q(op.contrato)}`);
 });
 const fuentes=foto(['public.contratos','public.contrato_titulares','public.cronograma_pagos','private.contrato_pdfs','crm.inversion_cotitular_origenes']);
 caso('Corrección real F3 no vuelve a resolver el documento antiguo del cotitular',()=>{
  rpc('corregir_documento_inversionista_fn',[q(a.id),"'CE'",q(doc()),"'Corrección documental ficticia posterior al contrato'"]);
  assert.equal(estado(op.inversion)[0].inversionista_id,a.id);assert.equal(foto(['public.contratos','public.contrato_titulares','public.cronograma_pagos','private.contrato_pdfs','crm.inversion_cotitular_origenes']),fuentes);
 });
 caso('Documento histórico reutilizado no transfiere una procedencia existente',()=>{
  persona(a.documento);assert.equal(estado(op.inversion)[0].inversionista_id,a.id);
  const ambigua=alta([titular(a)]);assert.equal(estado(ambigua.inversion)[0].motivo,'documento_reutilizado');
 });
 caso('Fusión real F3 conserva el origen y sigue la canónica vigente',()=>{
  fusion(a.id,b.id);const e=estado(op.inversion)[0];assert.equal(e.inversionista_id,b.id);assert.equal(e.persona_origen_id,a.id);
  assert.equal(e.estado,'vinculado');
 });
 caso('Fusión cotitular con principal deduplica membresía y conserva procedencias',()=>{
  fusion(b.id,base.identidades.avance);const e=estado(op.inversion);assert.equal(e[0].inversionista_id,base.identidades.avance);
  assert.equal(sql(`select count(*) from crm.inversion_titulares where inversion_id=${q(op.inversion)}`),'1');
  assert.equal(sql(`select count(*) from crm.inversion_cotitular_origenes where inversion_id=${q(op.inversion)}`),'3');
  assert.equal(e[0].estado,'vinculado');
 });
 caso('Verificación posterior permite recuperar pendiente por RPC sin rehacer PDF',()=>{
  persona(pendiente.documento);const antes=foto(['public.contratos','public.contrato_titulares','public.cronograma_pagos','private.contrato_pdfs']);
  assert.equal(conciliar(op.inversion)[3].estado,'vinculado');assert.equal(foto(['public.contratos','public.contrato_titulares','public.cronograma_pagos','private.contrato_pdfs']),antes);
 });
 caso('Fuera de ámbito, Directorio y cliente no leen ni concilian cotitularidad',()=>{
  for(const rol of ['ajeno','supervisor_ajeno','directorio','cliente']) for(const fn of ['inversion_cotitulares_fn','conciliar_cotitulares_inversion_fn'])
   assert.throws(()=>rpc(fn,[q(op.inversion)],f.usuarios[rol].id),/42501/);
 });
 rpc('levantar_no_contactar',[q(sql(`select id from crm.leads where inversionista_id=${q(base.identidades.avance)} limit 1`)),"'Fin del ensayo ficticio de propagación del veto por fusión'"]);
 const ocupada=persona();
 const lock=copia.abrirSesion('f4_cotitular_ocupado');
 lock.enviar(`begin;select private.identidad_bloquear_documento('CE',${q(ocupada.documento)});select 'LOCK_READY';`);
 await copia.esperar(()=>lock.salida().includes('LOCK_READY'),'No se tomó el candado documental');
 let diferida;
 try {caso('Documento ocupado no rompe el alta financiera; queda recuperable',()=>{
  diferida=alta([titular(ocupada)]);assert.equal(sql(`select count(*) from crm.inversion_cotitular_origenes where inversion_id=${q(diferida.inversion)}`),'0');
 });} finally {assert.equal((await lock.cerrar()).codigo,0);}
 caso('Tras liberar el candado se recupera una sola procedencia',()=>{
  assert.equal(conciliar(diferida.inversion)[0].estado,'vinculado');conciliar(diferida.inversion);
  assert.equal(sql(`select count(*) from crm.inversion_cotitular_origenes where inversion_id=${q(diferida.inversion)}`),'1');
 });
 caso('Mantenimiento histórico exige SQL privilegiado y F4 apagada',()=>{
  assert.throws(()=>sql(`\\set VERBOSITY verbose
    select private.inversion_cotitulares_historicos(${q(op.inversion)})`),/P0409/);
  assert.throws(()=>como(gerente,`select private.inversion_cotitulares_historicos(${q(op.inversion)})`),/42501/);
  sql("update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura'");
  assert.equal(JSON.parse(sql(`select private.inversion_cotitulares_historicos(${q(op.inversion)})`))[0].estado,'vinculado');
 });
} finally {assert.equal(sqlOriginal('select private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by id),\'[]\')) from crm.inversiones t'),fotoOriginal);}
writeFileSync(new URL(`../evidencia-f4/cotitulares-neutrales-${copia.id}.json`,import.meta.url),JSON.stringify({
 entorno:'avancecorp-f4-bank',baseCopia:copia.nombre,terminadoEn:new Date().toISOString(),pruebas,bancoOriginalSinCambios:true,
 sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
 limite:'SQL con rol/claims sintéticos; alta y snapshot, corrección, fusión y conciliación por RPC reales. No procesa el PDF ni duplica Storage.',
},null,2)+'\n',{flag:'wx'});
console.log(`Cotitulares neutrales: ${pruebas.length} grupos conformes.`);
