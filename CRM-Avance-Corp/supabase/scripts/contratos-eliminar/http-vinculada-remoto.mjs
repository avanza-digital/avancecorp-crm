// Ensayo de Auth → Edge desplegada → PostgREST → SQL → Storage reales.
// Solo el banco temporal de banco-remoto.mjs; todos los datos son ficticios.
import assert from 'node:assert/strict';
import {randomUUID,randomBytes,createHash} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {sql,http,rpc,ref} from './banco-vinculada-remoto.mjs';

const q=s=>"'"+String(s).replaceAll("'","''")+"'";
const objeto=s=>JSON.parse(sql(s));
const resultados=[];
const comprobar=(nombre,fn)=>{fn();resultados.push({nombre,estado:'PASS'});};
const bien=r=>{assert.equal(r.ok,true,`${r.status}: ${r.data?.message??r.data?.error??'HTTP rechazado'}`);return r.data;};
const password=randomBytes(28).toString('base64url')+'aA1!';
const actores={};
for(const rol of ['admin','superadmin','analista','inactivo']) {
  const email=`contratos.${rol}.${randomUUID()}@pruebas.example`;
  const u=bien(await http('/auth/v1/admin/users',{admin:true,body:{email,password,email_confirm:true}}));
  assert(u.id);
  sql(`insert into public.perfiles(id,rol,nombre_completo,correo,activo)
    values(${q(u.id)},${q(rol==='inactivo'?'admin':rol)},'ENSAYO CONTRATOS',${q(email)},${rol!=='inactivo'});`);
  const s=bien(await http('/auth/v1/token?grant_type=password',{body:{email,password}}));
  assert.equal(s.user.id,u.id);actores[rol]={id:u.id,token:s.access_token};
}
const contratos=[randomUUID(),randomUUID(),randomUUID()];
const admin=actores.admin;
const bytes='%PDF-1.4\nEVIDENCIA SINTETICA CONTRATOS\n%%EOF';
const hash=createHash('sha256').update(bytes).digest('hex');
const c=contratos[0];
const documentos=[{bucket:'documentos',path:c+'/evidencia.pdf'},
  {bucket:'contratos-generados',path:c+'/contrato.pdf'}];
// Preparar un estado heredado, como hace el banco general. Las comprobaciones
// de eliminación se ejecutan después con TODOS los triggers habilitados.
sql(`begin;set local session_replication_role=replica;
  ${contratos.map(id=>`insert into public.contratos select (jsonb_populate_record(null::public.contratos,
    to_jsonb(t)||jsonb_build_object('id',${q(id)},'numero_contrato',${q('AUD-'+id.slice(0,8))},
      'fecha_inicio',current_date,'fecha_vencimiento',current_date+365,'periodo_comercial',date_trunc('month',current_date)::date))).*
    from public.contratos t where numero_contrato='AC-2026-0001';`).join('\n')}
  ${contratos.map(id=>`insert into crm.inversiones select (jsonb_populate_record(null::crm.inversiones,to_jsonb(x)||jsonb_build_object('id',gen_random_uuid(),'contrato_id',${q(id)}))).*
    from crm.inversiones x join public.contratos k on k.id=x.contrato_id where k.numero_contrato='AC-2026-0001';
    insert into crm.inversion_titulares select (jsonb_populate_record(null::crm.inversion_titulares,to_jsonb(t)||jsonb_build_object('id',gen_random_uuid(),'inversion_id',(select id from crm.inversiones where contrato_id=${q(id)})))).*
    from crm.inversion_titulares t join crm.inversiones x on x.id=t.inversion_id join public.contratos k on k.id=x.contrato_id where k.numero_contrato='AC-2026-0001';`).join('\n')}
  insert into public.cronograma_pagos(contrato_id,numero_cuota,fecha_programada,monto_programado,estado,fecha_pago_real,monto_pagado,registrado_por)
    values(${q(c)},1,current_date,125,'pagado',current_date,125,${q(admin.id)});
  insert into public.documentos(contrato_id,nombre,tipo,storage_path,subido_por)
    values(${q(c)},'EVIDENCIA SINTETICA.pdf','otro',${q(documentos[0].path)},${q(admin.id)});
  insert into private.contrato_pdfs(contrato_id,storage_path,nombre_archivo,sha256,bytes,template_version,snapshot,generado_por)
    values(${q(c)},${q(documentos[1].path)},'contrato.pdf',${q(hash)},${Buffer.byteLength(bytes)},'contrato-aep-17-v1','{}',${q(admin.id)});
  commit;`);
assert.equal(sql(`select count(*) from public.contratos where id in(${contratos.map(q).join(',')});`),'3');
for(const d of documentos) {
  const bucket=await http('/storage/v1/bucket',{admin:true,body:{id:d.bucket,name:d.bucket,public:false}});
  assert(bucket.ok||bucket.data?.statusCode==='409'||bucket.data?.error==='Duplicate',JSON.stringify(bucket.data));
  bien(await http('/storage/v1/object/'+d.bucket+'/'+d.path,
    {admin:true,body:bytes,headers:{'Content-Type':'application/pdf','x-upsert':'false'}}));
}
const antes=objeto(`select jsonb_build_object('contrato',to_jsonb(c),
  'inversion',(select to_jsonb(i) from crm.inversiones i where i.contrato_id=c.id),
  'inversion_titulares',(select jsonb_agg(to_jsonb(t) order by t.id) from crm.inversion_titulares t join crm.inversiones i on i.id=t.inversion_id where i.contrato_id=c.id),'cronograma',
  (select jsonb_agg(to_jsonb(p) order by p.id) from public.cronograma_pagos p where p.contrato_id=c.id))
  from public.contratos c where c.id=${q(c)};`);
const edge=(token,id=c,action='delete-audited')=>http('/functions/v1/crm-contrato-pdf-v2',
  {token,body:{action,contratoId:id},headers:{Origin:'https://crm.miavance.com'}});
for(const rol of ['anon','admin','superadmin','analista']) {
  const r=await rpc('contrato_eliminar_auditado',{p_contrato_id:c,p_actor_id:admin.id},
    {token:actores[rol]?.token});
  comprobar(rol+' no suplanta service_role por RPC',()=>{assert.equal(r.ok,false);assert(['42501','PGRST301'].includes(r.data?.code));});
}
for(const rol of ['anon','analista','inactivo']) {
  const r=await edge(actores[rol]?.token);
  comprobar('Edge rechaza '+rol,()=>assert.equal(r.status,rol==='anon'?401:403));
}
const falso=await edge('token-invalido');
comprobar('Edge rechaza token inválido',()=>assert.equal(falso.status,401));
for(const nombre of ['contrato_eliminacion_preparar','contrato_eliminacion_finalizar']) {
  const r=await rpc(nombre,{p_contrato_id:c,p_actor_id:admin.id,
    ...(nombre.endsWith('finalizar')?{p_token:randomUUID()}:{})},{admin:true});
  comprobar('Puerta antigua cerrada: '+nombre,()=>{assert.equal(r.ok,false);assert.equal(r.data?.code,'42501');});
}
let [r1,r2]=await Promise.all([edge(admin.token),edge(admin.token)]);
// El límite de espera SQL puede pedir un reintento durante una carrera real.
for(const [i,r] of [r1,r2].entries()) {
  if(r.status===409) {
    assert.equal(r.data?.error,'El contrato está siendo actualizado. Espera unos segundos y reintenta.');
    const reintento=await edge(admin.token);
    if(i===0)r1=reintento;else r2=reintento;
  }
}
const recibo=bien(r1);bien(r2);
comprobar('Admin elimina un pago y concurrencia devuelve el mismo acuse',()=>{
  assert.equal(recibo.ok,true);assert.equal(recibo.contratoId,c);
  assert.equal(recibo.auditoriaId,r2.data.auditoriaId);assert.equal(recibo.archivosConservados,2);
});
const archivo=objeto(`select to_jsonb(a) from crm.contratos_eliminados_auditoria a where contrato_id=${q(c)};`);
comprobar('Copia exacta de contrato y pago, con actor e identidad del cliente',()=>{
  assert.deepEqual(archivo.snapshot.contrato,antes.contrato);
  assert.equal(archivo.snapshot.version,2);
  assert.deepEqual(archivo.snapshot.inversion,antes.inversion);
  assert.deepEqual(archivo.snapshot.inversion_titulares,antes.inversion_titulares);
  assert.equal(sql(`select count(*) from crm.inversiones where contrato_id=${q(c)};`),'0');
  assert.equal(sql(`select count(*) from crm.inversion_titulares where inversion_id=${q(antes.inversion.id)};`),'0');
  assert.deepEqual(archivo.snapshot.cronograma,antes.cronograma);
  assert.equal(archivo.eliminado_por,admin.id);assert.equal(archivo.id,recibo.auditoriaId);
  assert.equal(archivo.snapshot.cliente.id,antes.contrato.cliente_id);
  assert.deepEqual(archivo.archivos,documentos.toSorted((a,b)=>a.bucket.localeCompare(b.bucket)));
  assert.equal(sql(`select count(*) from public.contratos where id=${q(c)};`),'0');
  assert.equal(sql(`select count(*) from public.cronograma_pagos where contrato_id=${q(c)};`),'0');
  assert.equal(sql(`select count(*) from public.audit_log where tabla='contratos' and operacion='DELETE' and fila_id=${q(c)} and usuario_id=${q(admin.id)};`),'1');
});
for(const d of documentos) {
  const r=await http('/storage/v1/object/authenticated/'+d.bucket+'/'+d.path,{admin:true,method:'GET'});
  comprobar('Archivo conservado byte a byte: '+d.bucket,()=>{bien(r);assert.equal(r.data,bytes);});
  const publico=await http('/storage/v1/object/'+d.bucket+'/'+d.path,{method:'GET'});
  comprobar('Archivo sigue privado: '+d.bucket,()=>assert.equal(publico.ok,false));
}
for(const rol of ['anon','admin','superadmin','service_role']) {
  const r=await http('/rest/v1/contratos_eliminados_auditoria?select=id',
    {method:'GET',token:actores[rol]?.token,admin:rol==='service_role',headers:{'Accept-Profile':'crm'}});
  comprobar('Copia no expuesta a '+rol,()=>{assert.equal(r.ok,false);assert.equal(r.data?.code,'42501');});
}
const legacy=bien(await edge(admin.token,contratos[1],'delete'));
comprobar('Cliente anterior conserva su respuesta compatible',()=>assert.deepEqual(legacy,{ok:true,contratoId:contratos[1],archivosEliminados:0}));
const superadmin=bien(await edge(actores.superadmin.token,contratos[2]));
comprobar('Superadmin conserva acceso con copia de auditoría',()=>assert(superadmin.auditoriaId));
const protegido=sql(`select i.contrato_id from crm.inversiones i where i.contrato_id is not null and exists(select 1 from crm.inversion_eventos e where e.inversion_id=i.id) limit 1;`);
const rechazo=await edge(admin.token,protegido);
comprobar('Historial propio responde 409 sin perder contrato ni inversión',()=>{
  assert.equal(rechazo.status,409);assert.match(rechazo.data.error,/historial propio/);
  assert.equal(sql(`select exists(select 1 from public.contratos where id=${q(protegido)}) and exists(select 1 from crm.inversiones where contrato_id=${q(protegido)}) and not exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=${q(protegido)});`),'t');
});
const informe={proyecto:ref,fecha:new Date().toISOString(),datos:'exclusivamente ficticios',resultados};
writeFileSync(new URL('./http-vinculada-remoto.resultado.json',import.meta.url),JSON.stringify(informe,null,2)+'\n');
console.log('HTTP/Auth/Edge/Storage: '+resultados.length+' comprobaciones PASS');
