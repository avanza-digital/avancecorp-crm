import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {como,contenedor,http,leer,literal as q,rpc,sql} from '../f5/banco-local.mjs';

const ok=(r)=>{assert.equal(r.ok,true,`${r.status}: ${JSON.stringify(r.data)}`);return r.data;};
const rechazo=(r,codigo)=>{assert.equal(r.ok,false,JSON.stringify(r.data));assert.equal(r.data.code,codigo,JSON.stringify(r.data));};
const fecha=(dias=1)=>new Date(Date.now()+dias*86400000).toISOString();
const resumenFinanciero=()=>JSON.stringify(['public.contratos','public.cronograma_pagos','crm.inversiones','crm.cierres_externos','crm.depositos_reclamados'].map(tabla=>({tabla,huella:sql(`select md5(coalesce(string_agg(to_jsonb(t)::text,'' order by to_jsonb(t)::text),'')) from ${tabla} t`)})));
async function bloquear(consulta) {
  const p=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']});
  const salida=once(p,'exit'); let error='';p.stderr.on('data',x=>{error+=x;});
  const listo=new Promise((resolve,reject)=>{let texto='';p.stdout.on('data',x=>{texto+=x;if(texto.includes('F6_CANDADO'))resolve();});p.once('exit',()=>reject(new Error(error||'No se adquirió el candado')));});
  p.stdin.write(`begin;${consulta};select 'F6_CANDADO';\n`);await listo;
  return async()=>{p.stdin.end('rollback;\n\\q\n');await salida;};
}

test('F6: agenda, ámbito, veto y retiros administrativos sin modificar dinero',async t=>{
  const f=leer('fixtures.json');
  const tokens=Object.fromEntries(await Promise.all(Object.keys(f.usuarios).map(async rol=>[rol,await como(rol)])));
  const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
  const persona=sql(`select i.id from crm.inversionistas i where i.perfil_id is null and i.estado='activo'
    and not i.no_contactar and i.responsable_relacion_id=${q(f.usuarios.vendedor.id)}
    and exists(select 1 from private.cartera_f5_fuentes() x where x.inversionista_id=i.id and x.empresa='qorilazo') order by i.id limit 1`);
  assert.ok(persona,'Se requiere la persona cooperativa sintética del banco F5');
  const fuente=sql(`select fuente_id from private.cartera_f5_fuentes() where inversionista_id=${q(persona)} and empresa='qorilazo' and estado='vigente' limit 1`);
  const lead=sql(`select x from private.leads_de_persona_veto(${q(persona)}) x limit 1`);
  const llamar=(nombre,datos={},rol='vendedor')=>rpc(nombre,datos,tokens[rol]);
  const agendar=(tipo='llamada')=>llamar('postventa_agendar_fn',{p_clave:randomUUID(),p_inversionista:persona,p_datos:{tipo,titulo:'Gestión sintética F6',vence_en:fecha(),...(tipo==='reunion'?{modalidad_reunion:'virtual'}:{})}}).then(ok);
  const finanzas=resumenFinanciero();
  let tarea,reunion;
  try {
    sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','ficha_360_neutral','postventa_neutral')");
    await t.test('banderas apagadas impiden crear; Directorio y Cliente no gestionan',async()=>{
      sql("update crm.multiempresa_flags set activo=false where nombre='postventa_neutral'");
      assert.equal(ok(await llamar('postventa_estado_fn')).habilitada,false);
      rechazo(await llamar('postventa_agendar_fn',{p_clave:randomUUID(),p_inversionista:persona,p_datos:{}}),'P0409');
      sql("update crm.multiempresa_flags set activo=true where nombre='postventa_neutral'");
      assert.equal(ok(await llamar('postventa_estado_fn')).habilitada,true);
      assert.equal(ok(await llamar('postventa_estado_fn',{},'directorio')).habilitada,false);
      for(const rol of ['directorio','cliente','ajeno']) rechazo(await llamar('postventa_agendar_fn',{p_clave:randomUUID(),p_inversionista:persona,p_datos:{}},rol),'42501');
    });
    await t.test('una tarea por clave, campos reales y rechazo de contenido diferente',async()=>{
      const entrada={p_clave:randomUUID(),p_inversionista:persona,p_datos:{tipo:'llamada',titulo:'Llamar por vencimiento F6',vence_en:fecha()}};
      tarea=ok(await llamar('postventa_agendar_fn',entrada)).tarea;
      assert.equal(tarea.inversionista_id,persona);assert.equal(tarea.lead_id,null);assert.equal(tarea.perfil_id,null);assert.equal(tarea.postventa_revision,1);
      assert.deepEqual(ok(await llamar('postventa_agendar_fn',entrada)).tarea,tarea);
      rechazo(await llamar('postventa_agendar_fn',{...entrada,p_datos:{...entrada.p_datos,titulo:'Otro contenido'}}),'P0409');
      assert.equal(sql(`select count(*) from crm.tareas where id=${q(tarea.id)}`),'1');
      assert.equal(sql('select count(*) from crm.postventa_escrituras'),'0');
    });
    await t.test('misma tarea en agenda y ficha; ningún acceso de otro árbol o Directorio',async()=>{
      for(const rol of ['vendedor','supervisor','gerencia']) {
        const agenda=ok(await llamar('postventa_agenda_fn',{},rol));assert.equal(agenda.filter(x=>x.id===tarea.id).length,1);
      }
      for(const rol of ['ajeno','supervisor_ajeno','directorio']) {
        const agenda=ok(await llamar('postventa_agenda_fn',{},rol));assert.ok(!agenda.some(x=>x.id===tarea.id));
        const directo=ok(await http(`/rest/v1/tareas?select=id,inversionista_id&id=eq.${tarea.id}`,{method:'GET',token:tokens[rol],headers:{'Accept-Profile':'crm'}}));assert.deepEqual(directo,[]);
      }
      const ficha=ok(await llamar('inversionista_ficha_fn',{p_inversionista:persona}));
      assert.ok(ficha.tareas.some(x=>x.id===tarea.id));assert.ok(ficha.historial.some(x=>x.origen==='postventa'&&x.tipo==='agenda'));
    });
    await t.test('RPC antigua rechaza tarea neutral y no consume recibo SLA',async()=>{
      const clave=randomUUID();
      rechazo(await llamar('cerrar_tarea_v2',{p_operacion_id:clave,p_tarea_id:tarea.id,p_estado:'completada',p_resultado_tipo:'llamada_realizada'}),'42501');
      assert.equal(sql(`select count(*) from crm.sla_operacion_recibos where operacion_id=${q(clave)}`),'0');
      assert.equal(sql(`select estado from crm.tareas where id=${q(tarea.id)}`),'pendiente');
      assert.throws(()=>sql(`begin;set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:f.usuarios.vendedor.id,role:'authenticated'}))},true);
        select set_config('crm.op_tarea','on',true);select set_config('crm.op_privilegiada','on',true);
        select crm.cerrar_tarea(${q(tarea.id)},'completada','llamada_realizada');commit;`),/Usa el comando de postventa/);
    });
    await t.test('confirmar y reprogramar reunión conserva la cita anterior',async()=>{
      reunion=(await agendar('reunion')).tarea;
      const c=ok(await llamar('postventa_tarea_fn',{p_clave:randomUUID(),p_tarea:reunion.id,p_revision:1,p_accion:'confirmar'}));
      assert.equal(c.tarea.postventa_revision,2);assert.ok(c.tarea.confirmada_en);
      const entrada={p_clave:randomUUID(),p_tarea:reunion.id,p_revision:2,p_accion:'reprogramar',p_datos:{vence_en:fecha(2),detalle:'Nueva fecha acordada en el ensayo'}};
      const r=ok(await llamar('postventa_tarea_fn',entrada));
      assert.equal(r.tarea.estado,'reprogramada');assert.equal(r.siguiente.reagendada_de,reunion.id);assert.equal(r.siguiente.inversionista_id,persona);
      assert.deepEqual(ok(await llamar('postventa_tarea_fn',entrada)),r);
      reunion=r.siguiente;
    });
    await t.test('cierre trazado, revisión obsoleta y siguiente gestión atómica',async()=>{
      rechazo(await llamar('postventa_tarea_fn',{p_clave:randomUUID(),p_tarea:tarea.id,p_revision:0,p_accion:'cerrar',p_datos:{estado:'completada',detalle:'Conversación del ensayo'}}),'P0409');
      const datos={p_clave:randomUUID(),p_tarea:tarea.id,p_revision:1,p_accion:'cerrar',p_datos:{estado:'completada',detalle:'Conversación de postventa del ensayo',siguiente:{tipo:'whatsapp',titulo:'Enviar condiciones de la renovación',vence_en:fecha(3)}}};
      const r=ok(await llamar('postventa_tarea_fn',datos));assert.equal(r.tarea.estado,'completada');assert.ok(r.siguiente.id);
      assert.deepEqual(ok(await llamar('postventa_tarea_fn',datos)),r);
      assert.equal(sql(`select count(*) from crm.actividades where id=${q(datos.p_clave)}`),'0');
    });
    await t.test('concurrencia: tarea bloqueada devuelve 40001, nunca deadlock',async()=>{
      const soltar=await bloquear(`select id from crm.tareas where id=${q(reunion.id)} for update`);
      try {
        rechazo(await llamar('postventa_tarea_fn',{p_clave:randomUUID(),p_tarea:reunion.id,p_revision:1,p_accion:'cerrar',p_datos:{estado:'completada',detalle:'Cierre concurrente del ensayo'}}),'40001');
        rechazo(await llamar('postventa_veto_fn',{p_clave:randomUUID(),p_inversionista:persona,p_vetar:true,p_motivo:'Prueba concurrente del veto global'}),'40001');
        rechazo(await llamar('reasignar_responsable_relacion_fn',{p_inversionista:persona,p_nuevo_responsable:f.usuarios.ajeno.id,p_motivo:'Prueba concurrente de reasignación'},'gerencia'),'40001');
      } finally {await soltar();}
      assert.equal(sql(`select responsable_relacion_id from crm.inversionistas where id=${q(persona)}`),f.usuarios.vendedor.id);
    });
    await t.test('responsable actual manda sobre el JWT anterior',async()=>{
      ok(await llamar('reasignar_responsable_relacion_fn',{p_inversionista:persona,p_nuevo_responsable:f.usuarios.ajeno.id,p_motivo:'Cambiar responsable en el ensayo de F6'},'gerencia'));
      assert.ok(!ok(await llamar('postventa_agenda_fn')).some(x=>x.inversionista_id===persona));
      assert.ok(ok(await llamar('postventa_agenda_fn',{},'ajeno')).some(x=>x.id===reunion.id));
      rechazo(await llamar('postventa_tarea_fn',{p_clave:randomUUID(),p_tarea:reunion.id,p_revision:1,p_accion:'confirmar'}),'42501');
      ok(await llamar('reasignar_responsable_relacion_fn',{p_inversionista:persona,p_nuevo_responsable:f.usuarios.vendedor.id,p_motivo:'Restaurar responsable tras el ensayo de F6'},'gerencia'));
    });
    await t.test('veto global cancela tareas de contacto, levantarlo no las revive',async()=>{
      ok(await llamar('postventa_veto_fn',{p_clave:randomUUID(),p_inversionista:persona,p_vetar:true,p_motivo:'El cliente solicitó suspender los contactos'}));
      assert.equal(sql(`select count(*) from crm.tareas where inversionista_id=${q(persona)} and estado='pendiente'`),'0');
      rechazo(await llamar('postventa_agendar_fn',{p_clave:randomUUID(),p_inversionista:persona,p_datos:{tipo:'llamada',titulo:'No debe nacer',vence_en:fecha()}}),'P0429');
      rechazo(await llamar('postventa_veto_fn',{p_clave:randomUUID(),p_inversionista:persona,p_vetar:false,p_motivo:'Solicitar levantar el veto desde rol incorrecto'}),'42501');
    });
    await t.test('retiro solicitado con veto: trámite, duplicados y revisión solo Gerencia',async()=>{
      const datos={p_clave:randomUUID(),p_inversionista:persona,p_fuente:fuente,p_motivo:'Solicitud de retiro recibida del cliente en el ensayo'};
      const r=ok(await llamar('postventa_solicitar_retiro_fn',datos)).retiro;
      assert.deepEqual(ok(await llamar('postventa_solicitar_retiro_fn',datos)).retiro,r);
      rechazo(await llamar('postventa_solicitar_retiro_fn',{...datos,p_clave:randomUUID()}),'P0409');
      const revision={p_clave:randomUUID(),p_retiro:r.id,p_revision:1,p_estado:'en_revision',p_detalle:'Gerencia recibe la solicitud para revisión'};
      rechazo(await llamar('postventa_revisar_retiro_fn',revision),'42501');
      assert.equal(ok(await llamar('postventa_revisar_retiro_fn',revision,'gerencia')).retiro.estado,'en_revision');
      const fin={p_clave:randomUUID(),p_retiro:r.id,p_revision:2,p_estado:'revisada',p_detalle:'Revisión administrativa registrada sin liquidación ni pago'};
      assert.equal(ok(await llamar('postventa_revisar_retiro_fn',fin,'gerencia')).retiro.estado,'revisada');
      assert.equal(ok(await llamar('postventa_revisar_retiro_fn',fin,'gerencia')).retiro.revision,3);
      rechazo(await llamar('postventa_revisar_retiro_fn',{...fin,p_clave:randomUUID()},'gerencia'),'P0409');
      assert.equal(resumenFinanciero(),finanzas);
      ok(await llamar('postventa_veto_fn',{p_clave:randomUUID(),p_inversionista:persona,p_vetar:false,p_motivo:'Restaurar contacto tras la prueba aislada'},'gerencia'));
      assert.equal(sql(`select count(*) from crm.tareas where inversionista_id=${q(persona)} and estado='pendiente'`),'0');
    });
    await t.test('legado re-veta una persona ya vetada y limpia las pendientes neutrales',async()=>{
      assert.ok(lead,'El fixture inicial cooperativo debe tener antecedente de captación');
      const nueva=(await agendar()).tarea;
      // Simula una pendiente histórica anterior al mecanismo F6; solo este banco local.
      sql(`begin;alter table crm.inversionistas disable trigger trg_inversionistas_postventa;
        update crm.inversionistas set no_contactar=true,no_contactar_en=clock_timestamp(),
          no_contactar_por=${q(f.usuarios.vendedor.id)} where id=${q(persona)};
        alter table crm.inversionistas enable trigger trg_inversionistas_postventa;commit;`);
      ok(await llamar('marcar_no_contactar',{p_lead_id:lead,p_motivo:'Repetir veto de la persona sintética'}));
      assert.equal(sql(`select estado from crm.tareas where id=${q(nueva.id)}`),'cancelada');
      ok(await llamar('postventa_veto_fn',{p_clave:randomUUID(),p_inversionista:persona,p_vetar:false,p_motivo:'Restaurar contacto tras el ensayo de re-veto'},'gerencia'));
    });
    await t.test('reversa OFF oculta la agenda neutral y conserva las tareas históricas',async()=>{
      const nueva=(await agendar()).tarea;
      sql("update crm.multiempresa_flags set activo=false where nombre='postventa_neutral'");
      assert.deepEqual(ok(await llamar('postventa_agenda_fn')),[]);
      rechazo(await llamar('postventa_tarea_fn',{p_clave:randomUUID(),p_tarea:nueva.id,p_revision:1,p_accion:'cerrar',p_datos:{estado:'completada',detalle:'No debe cerrar mientras está apagado'}}),'P0409');
      assert.equal(sql(`select estado from crm.tareas where id=${q(nueva.id)}`),'pendiente');
      sql("update crm.multiempresa_flags set activo=true where nombre='postventa_neutral'");
    });
    assert.equal(resumenFinanciero(),finanzas);
    assert.equal(sql('select count(*) from crm.postventa_escrituras'),'0');
  } finally {
    sql(`begin;select set_config('crm.op_privilegiada','on',true);
      update crm.inversionistas set no_contactar=false,responsable_relacion_id=${q(f.usuarios.vendedor.id)} where id=${q(persona)};
      update crm.leads set no_contactar=false where id in(select private.leads_de_persona_veto(${q(persona)}));commit;`);
    for(const [nombre,activo] of Object.entries(flags)) sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);
  }
});
