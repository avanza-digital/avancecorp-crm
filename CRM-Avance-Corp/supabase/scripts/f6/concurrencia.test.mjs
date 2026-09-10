import test from 'node:test';import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';import {once} from 'node:events';import {randomUUID} from 'node:crypto';
import {como,contenedor,leer,literal as q,rpc,sql} from '../f5/banco-local.mjs';
async function bloquear(sentencia){
 const p=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']});
 const salida=once(p,'exit');let error='';p.stderr.on('data',x=>{error+=x;});
 const listo=new Promise((resolve,reject)=>{let texto='';p.stdout.on('data',x=>{texto+=x;if(texto.includes('F6_LOCK'))resolve();});p.once('exit',()=>reject(new Error(error||'Candado no adquirido')));});
 p.stdin.write(`begin;${sentencia};select 'F6_LOCK';\n`);await listo;return async()=>{p.stdin.end('rollback;\n\\q\n');await salida;};
}
const ok=r=>{assert.equal(r.ok,true,JSON.stringify(r.data));return r.data;};
test('F6: carreras reales entre sesiones sin commits parciales',async t=>{
 const f=leer('fixtures.json'),g=await como('gerencia'),v=await como('vendedor');
 const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
 const persona=randomUUID(),tarea=randomUUID();
 const datos={tipo:'llamada',titulo:'Gestión sintética concurrente F6',vence_en:new Date(Date.now()+86400000).toISOString()};
 try {
  sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','ficha_360_neutral','postventa_neutral','inversiones_escritura')");
  sql(`insert into crm.inversionistas(id,responsable_relacion_id,creado_por) values(${q(persona)},${q(f.usuarios.vendedor.id)},${q(f.usuarios.gerencia.id)})`);
  await t.test('cambio de modo pendiente devuelve 40001 y no crea tarea ni recibo',async()=>{
    const clave=randomUUID(),soltar=await bloquear("select nombre from crm.multiempresa_flags where nombre='postventa_neutral' for update");
    try {const r=await rpc('postventa_agendar_fn',{p_clave:clave,p_inversionista:persona,p_datos:datos},v);assert.equal(r.data.code,'40001');}
    finally {await soltar();}
    assert.equal(sql(`select count(*) from crm.postventa_operaciones where clave=${q(clave)}`),'0');
  });
  await t.test('persona bloqueada termina en conflicto reintentable, sin tarea parcial',async()=>{
    const clave=randomUUID(),soltar=await bloquear(`select id from crm.inversionistas where id=${q(persona)} for update`);
    try {const r=await rpc('postventa_agendar_fn',{p_clave:clave,p_inversionista:persona,p_datos:datos},v);assert.equal(r.data.code,'40001');}
    finally {await soltar();}
    assert.equal(sql(`select count(*) from crm.tareas where id=${q(clave)}`),'0');
  });
  await t.test('cierre, veto y reasignación simultáneos dejan una sola historia coherente',async()=>{
    ok(await rpc('postventa_agendar_fn',{p_clave:tarea,p_inversionista:persona,p_datos:datos},v));
    const resultados=await Promise.all([
      rpc('postventa_tarea_fn',{p_clave:randomUUID(),p_tarea:tarea,p_revision:1,p_accion:'cerrar',p_datos:{estado:'completada',detalle:'Cierre concurrente del ensayo'}},g),
      rpc('postventa_veto_fn',{p_clave:randomUUID(),p_inversionista:persona,p_vetar:true,p_motivo:'Veto concurrente solicitado en el ensayo'},g),
      rpc('reasignar_responsable_relacion_fn',{p_inversionista:persona,p_nuevo_responsable:f.usuarios.ajeno.id,p_motivo:'Reasignación concurrente del ensayo'},g),
    ]);
    for(const r of resultados)if(!r.ok)assert.ok(['P0409','40001'].includes(r.data.code),JSON.stringify(r.data));
    assert.equal(resultados[1].ok,true);assert.equal(resultados[2].ok,true);
    assert.ok(['completada','cancelada'].includes(sql(`select estado from crm.tareas where id=${q(tarea)}`)));
    assert.equal(sql(`select no_contactar from crm.inversionistas where id=${q(persona)}`),'t');
    assert.equal(sql(`select responsable_relacion_id from crm.inversionistas where id=${q(persona)}`),f.usuarios.ajeno.id);
    assert.equal(sql('select count(*) from crm.postventa_escrituras'),'0');
  });
  await t.test('fuente bloqueada impide preparar reinversión sin duplicar una solicitud',async()=>{
    const x=JSON.parse(sql(`select jsonb_build_object('id',fuente_id,'persona',inversionista_id) from private.cartera_f5_fuentes() where empresa='qorilazo' and estado='vigente' and identidad_coherente and not es_demo limit 1`));
    const clave=randomUUID(),soltar=await bloquear(`select id from crm.cierres_externos where id=${q(x.id)} for update`);
    try {const r=await rpc('preparar_reinversion_fn',{p_clave:clave,p_fuente:x.id,p_datos:{inversionista_id:x.persona,empresa:'qorilazo'}},g);assert.equal(r.data.code,'40001');}
    finally {await soltar();}
    assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(clave)}`),'0');
  });
 } finally {for(const [nombre,activo] of Object.entries(flags))sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);}
});
