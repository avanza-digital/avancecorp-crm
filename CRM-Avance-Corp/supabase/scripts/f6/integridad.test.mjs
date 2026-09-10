import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {como,http,leer,literal as q,rpc,sql} from '../f5/banco-local.mjs';
const ok=r=>{assert.equal(r.ok,true,JSON.stringify(r.data));return r.data;};
const f=leer('fixtures.json'),actor=rol=>f.usuarios[rol].id;
const claims=rol=>`select set_config('request.jwt.claims',${q(JSON.stringify({sub:actor(rol),role:'authenticated'}))},true);`;
const asegurar=(c,m)=>`do $$begin if not (${c}) then raise exception '${m}'; end if; end$$;`;
const nueva=(id,responsable)=>`insert into crm.inversionistas(id,responsable_relacion_id,creado_por) values(${q(id)},${q(responsable)},${q(actor('gerencia'))});`;
const agendar=(id,tarea)=>`select crm.postventa_agendar_fn(${q(tarea)},${q(id)},jsonb_build_object('tipo','llamada','titulo','Gestión sintética de integridad F6','vence_en',clock_timestamp()+interval '2 days'));`;

test('F6: baja, fusión, cola Gerencia, calendario, recibos y fronteras',async t=>{
 const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
 try {
  sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','ficha_360_neutral','postventa_neutral')");
  await t.test('baja de vendedor transfiere tareas por persona sin el barrido legado',()=>{
    const persona=randomUUID(),tarea=randomUUID();
    sql(`begin;${nueva(persona,actor('vendedor'))}${claims('gerencia')}${agendar(persona,tarea)}
      set local role authenticated;
      select crm.fijar_membresia_activa_fn(${q(actor('vendedor'))},false,${q(actor('ajeno'))},(select actualizado_en from crm.equipo where perfil_id=${q(actor('vendedor'))}),${q(randomUUID())});
      reset role;
      ${claims('vendedor')}set local role authenticated;
      do $$begin begin perform crm.postventa_estado_fn();raise exception 'La membresía inactiva mantuvo acceso';exception when insufficient_privilege then null;end;end$$;
      reset role;
      ${asegurar(`(select vendedor_id=${q(actor('ajeno'))} and inversionista_id=${q(persona)} and postventa_revision=2 from crm.tareas where id=${q(tarea)})`,'La tarea no siguió a su responsable')}
      ${asegurar(`not (select activo from crm.equipo where perfil_id=${q(actor('vendedor'))})`,'No se desactivó la membresía')}
      ${asegurar('(select count(*)=0 from crm.postventa_escrituras)','Contexto residual')}
      rollback;`);
  });
  await t.test('sin responsable solo Gerencia ve la cola; puede asignarse y operar',()=>{
    const persona=randomUUID(),tarea=randomUUID();
    sql(`begin;${nueva(persona,null)}${claims('gerencia')}
      do $$begin begin perform crm.postventa_agendar_fn(${q(tarea)},${q(persona)},jsonb_build_object('tipo','llamada','titulo','Ensayo','vence_en',clock_timestamp()+interval '1 day'));
        raise exception 'Se permitió agendar sin responsable'; exception when sqlstate 'P0409' then null; end; end$$;
      select crm.reasignar_responsable_relacion_fn(${q(persona)},${q(actor('gerencia'))},'Asignar la cola del ensayo');${agendar(persona,tarea)}
      update crm.inversionistas set responsable_relacion_id=null where id=${q(persona)};
      ${asegurar(`(select vendedor_id is null and postventa_revision=2 from crm.tareas where id=${q(tarea)})`,'No se conservó la tarea en la cola')}
      ${asegurar(`private.postventa_visible_actor(${q(persona)},${q(actor('gerencia'))}) and not private.postventa_visible_actor(${q(persona)},${q(actor('vendedor'))})`,'Ámbito incorrecto de la cola')}
      rollback;`);
  });
  await t.test('fusión conserva sujeto histórico, responsable canónico y veto global',()=>{
    const perdedora=randomUUID(),canonica=randomUUID(),tarea=randomUUID();
    sql(`begin;${nueva(perdedora,actor('vendedor'))}${nueva(canonica,actor('ajeno'))}${claims('gerencia')}${agendar(perdedora,tarea)}
      select crm.fusionar_inversionistas_fn(${q(perdedora)},${q(canonica)},'Unificar personas sintéticas del ensayo',crm.fusion_previsualizar_fn(${q(perdedora)},${q(canonica)})->>'hash');
      ${asegurar(`(select inversionista_id=${q(perdedora)} and vendedor_id=${q(actor('ajeno'))} from crm.tareas where id=${q(tarea)})`,'Fusión perdió origen o responsable')}
      ${asegurar(`exists(select 1 from jsonb_array_elements(crm.postventa_agenda_fn()) x where x->>'id'=${q(tarea)} and x->>'inversionista_canonico_id'=${q(canonica)})`,'Agenda no resuelve la canónica')}
      ${asegurar(`exists(select 1 from crm.inversionista_gestiones where inversionista_id=${q(perdedora)} and tipo='fusion')`,'Falta traza de fusión')}
      select crm.postventa_veto_fn(${q(randomUUID())},${q(canonica)},true,'Veto del ensayo tras la fusión');
      ${asegurar(`(select estado='cancelada' from crm.tareas where id=${q(tarea)})`,'Veto omitió tarea histórica')}
      rollback;`);
  });
  await t.test('ICS no muestra tareas del dueño anterior ni con F6 OFF',()=>{
    const persona=randomUUID(),tarea=randomUUID(),tokenV=randomUUID(),tokenA=randomUUID();
    const contiene=token=>`exists(select 1 from jsonb_array_elements(private.agenda_ics_feed_implementacion(${q(token)},clock_timestamp()-interval '1 day')->'tareas') x where x->>'id'=${q(tarea)})`;
    sql(`begin;${nueva(persona,actor('vendedor'))}${claims('gerencia')}${agendar(persona,tarea)}
      insert into crm.agenda_ics(perfil_id,token) values(${q(actor('vendedor'))},${q(tokenV)}),(${q(actor('ajeno'))},${q(tokenA)}) on conflict(perfil_id) do update set token=excluded.token;
      select set_config('request.jwt.claims','{}',true);
      ${asegurar(contiene(tokenV),'ICS no contiene tarea inicial')}${claims('gerencia')}
      select crm.reasignar_responsable_relacion_fn(${q(persona)},${q(actor('ajeno'))},'Transferir agenda en el ensayo ICS');
      ${asegurar(`not (${contiene(tokenV)}) and (${contiene(tokenA)})`,'ICS filtra al dueño equivocado')}
      update crm.multiempresa_flags set activo=false where nombre='postventa_neutral';
      ${asegurar(`not (${contiene(tokenA)})`,'ICS expone postventa OFF')}
      rollback;`);
  });
  await t.test('READ COMMITTED obligatorio en las puertas de postventa',()=>{
    for(const nivel of ['repeatable read','serializable']) assert.throws(()=>sql(`begin isolation level ${nivel};${claims('gerencia')}select crm.postventa_estado_fn();rollback;`),/READ COMMITTED/);
  });
  await t.test('tablas sin acceso directo y RPC sin sesión o service_role rechazadas',async()=>{
    const token=await como('gerencia');
    for(const tabla of ['inversionista_gestiones','postventa_operaciones','postventa_escrituras','postventa_retiros','inversion_solicitud_origenes']) for(const acceso of [{token},{admin:true}]) {
      const r=await http(`/rest/v1/${tabla}?select=*`,{...acceso,method:'GET',headers:{'Accept-Profile':'crm'}});
      assert.equal(r.ok,false,`${tabla}: acceso directo permitido`);assert.equal(r.data.code,'42501');
    }
    for(const acceso of [{},{admin:true}]) {
      const r=await http('/rest/v1/rpc/postventa_estado_fn',{...acceso,body:{},headers:{'Content-Profile':'crm'}});
      assert.equal(r.ok,false);assert.equal(r.data.code,'42501');
    }
  });
  await t.test('recibo limitado al actor y recuperable con F6 OFF',async()=>{
    const clave=sql(`select clave from crm.postventa_operaciones where actor_id=${q(actor('vendedor'))} and respuesta is not null order by creado_en desc limit 1`);
    assert.ok(clave,'Ejecuta primero postventa.test.mjs');
    const vendedor=await como('vendedor'),ajeno=await como('ajeno'),directorio=await como('directorio');
    sql("update crm.multiempresa_flags set activo=false where nombre='postventa_neutral'");
    assert.deepEqual(ok(await rpc('postventa_operacion_estado_fn',{p_clave:clave},vendedor)),{registrada:true});
    assert.equal((await rpc('postventa_operacion_estado_fn',{p_clave:clave,p_actor:actor('ajeno')},vendedor)).data.code,'42501');
    assert.deepEqual(ok(await rpc('postventa_operacion_estado_fn',{p_clave:clave},ajeno)),{registrada:false});
    assert.deepEqual(ok(await rpc('postventa_operacion_estado_fn',{p_clave:randomUUID()},vendedor)),{registrada:false});
    assert.equal((await rpc('postventa_operacion_estado_fn',{p_clave:clave},directorio)).data.code,'42501');
    sql("update crm.multiempresa_flags set activo=true where nombre='postventa_neutral'");
  });
  await t.test('Directorio no lee contenido postventa a través de audit_log',async()=>{
    const r=await http('/rest/v1/audit_log?select=*&tabla=in.(postventa_operaciones,inversionista_gestiones)',{token:await como('directorio'),method:'GET'});
    if(r.ok) assert.deepEqual(r.data,[]);else assert.equal(r.data.code,'42501');
  });
 } finally {for(const [nombre,activo] of Object.entries(flags))sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);}
});
