// Base sintética aislada; cada escenario termina en ROLLBACK.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import test from 'node:test';

function sql(consulta) {
  const r=spawnSync('docker',['exec','-i','supabase_db_crm-avance-corp-local','psql','-XqAt',
    '-U','postgres','-d','contratos_cotitular_v3_20260925','-v','ON_ERROR_STOP=1','-f','-'],
  {input:`begin; set local lock_timeout='3s'; ${consulta} rollback;`,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr || r.error?.message);
  return r.stdout.trim();
}
const fixture=`
  select p.id into strict a from public.perfiles p join crm.equipo e on e.perfil_id=p.id
    where p.rol='admin' and p.activo and e.activo and e.rol_crm='gerencia' limit 1;
  perform set_config('request.jwt.claim.sub',a::text,true);
  u:=gen_random_uuid();
  set local session_replication_role=replica;
  insert into auth.users(id,email) values(u,u||'@example.test');
  insert into auth.sessions(id,user_id) values(gen_random_uuid(),u);
  insert into auth.refresh_tokens(user_id,token) values(u::text,gen_random_uuid()::text);
  insert into public.perfiles select (jsonb_populate_record(null::public.perfiles,to_jsonb(p)||
    jsonb_build_object('id',u,'nombre_completo','ANALISTA SINTETICO','correo',u||'@example.test','dni',null,'rol','comercial'))).*
    from public.perfiles p where rol='analista' limit 1;
  insert into crm.equipo select (jsonb_populate_record(null::crm.equipo,to_jsonb(e)||jsonb_build_object('perfil_id',u))).*
    from crm.equipo e where rol_crm='vendedor' limit 1;
  set local session_replication_role=origin;
  select actualizado_en into vp from public.perfiles where id=u;
  select actualizado_en into ve from crm.equipo where perfil_id=u;
`;
const vars='a uuid; u uuid; vp timestamptz; ve timestamptz; r jsonb;';
const borrar="crm.eliminar_usuario_fn(u,'ANALISTA SINTETICO',vp,ve)";

test('Gerencia elimina identidad vacía, audita, revoca y admite replay',()=>sql(`do $$ declare ${vars} begin ${fixture}
  r:=${borrar};
  if r->>'resultado'<>'eliminado' or exists(select 1 from auth.users where id=u)
    or exists(select 1 from public.perfiles where id=u) or exists(select 1 from crm.equipo where perfil_id=u)
    or not exists(select 1 from private.usuarios_retirados where perfil_id=u and retirado_por=a)
    then raise exception 'Eliminación incompleta'; end if;
  if ${borrar} is distinct from r then raise exception 'Replay distinto'; end if;
end $$;`));

test('Conserva autor exacto y actividad, oculta directorio y bloquea reactivación',()=>sql(`do $$ declare ${vars} actividad uuid; begin ${fixture}
  set local session_replication_role=replica;
  insert into crm.actividades(lead_id,tipo,creado_por,detalle)
    select id,'nota',u,'HISTORIAL SINTETICO' from crm.leads limit 1 returning id into actividad;
  set local session_replication_role=origin;
  r:=${borrar};
  if r->>'resultado'<>'historial_conservado'
    or not exists(select 1 from public.perfiles where id=u and nombre_completo='ANALISTA SINTETICO' and not activo)
    or not exists(select 1 from crm.actividades where id=actividad and creado_por=u and detalle='HISTORIAL SINTETICO')
    or exists(select 1 from crm.equipo where perfil_id=u and activo)
    or exists(select 1 from auth.sessions where user_id=u)
    or exists(select 1 from auth.refresh_tokens where user_id=u::text)
    or exists(select 1 from crm.usuarios_administrables_fn(null,100,0) where perfil_id=u)
    then raise exception 'Historia, acceso o directorio incorrectos'; end if;
  begin update public.perfiles set activo=true where id=u; raise sqlstate 'ZX001'; exception when sqlstate 'P0001' then null; end;
  begin update public.perfiles set nombre_completo='OTRO AUTOR' where id=u; raise sqlstate 'ZX001'; exception when sqlstate 'P0001' then null; end;
  begin update crm.equipo set activo=true where perfil_id=u; raise sqlstate 'ZX001'; exception when sqlstate 'P0001' then null; end;
  begin delete from auth.users where id=u; raise sqlstate 'ZX001'; exception when sqlstate 'P0001' then null; end;
  perform set_config('request.jwt.claim.sub',u::text,true);
  if private.rol_crm(u) is not null then raise exception 'El JWT retirado conserva rol'; end if;
end $$;`));

for (const activo of [true,false]) test(`Pendientes bloquean y transfieren conservando autoría; activo=${activo}`,()=>sql(`do $$ declare ${vars} tarea uuid; reemplazo uuid; actividad uuid; begin ${fixture}
  select perfil_id into reemplazo from crm.equipo where rol_crm='vendedor' and activo and perfil_id<>u limit 1;
  set local session_replication_role=replica;
  insert into crm.tareas(lead_id,tipo,titulo,vence_en,vendedor_id,creado_por)
    select id,'tarea','PENDIENTE SINTETICO',now()+interval '1 day',u,a from crm.leads limit 1 returning id into tarea;
  insert into crm.actividades(lead_id,tipo,creado_por,detalle)
    select id,'nota',u,'AUTORIA CONSERVADA' from crm.leads limit 1 returning id into actividad;
  update crm.equipo set activo=${activo} where perfil_id=u;
  set local session_replication_role=origin;
  select actualizado_en into ve from crm.equipo where perfil_id=u;
  begin perform ${borrar}; raise sqlstate 'ZX001'; exception when sqlstate 'P0001' then
    if sqlerrm not like 'Transfiere primero%' then raise; end if;
  end;
  if not exists(select 1 from crm.equipo where perfil_id=u and activo=${activo}) then raise exception 'Baja parcial'; end if;
  perform crm.fijar_membresia_activa_fn(u,false,reemplazo,ve,gen_random_uuid());
  select actualizado_en into ve from crm.equipo where perfil_id=u;
  select actualizado_en into vp from public.perfiles where id=u;
  r:=${borrar};
  if r->>'resultado'<>'historial_conservado'
    or not exists(select 1 from crm.tareas where id=tarea and vendedor_id=reemplazo)
    or not exists(select 1 from crm.actividades where id=actividad and creado_por=u)
    then raise exception 'Transferencia/autoria incorrecta'; end if;
end $$;`));

for (const [nombre,cambio,codigo] of [
  ['analista',"perform set_config('request.jwt.claim.sub',u::text,true);",'42501'],
  ['anónimo',"perform set_config('request.jwt.claim.sub','',true);",'42501'],
  ['gerencia inactiva',"update public.perfiles set activo=false where id=a;",'42501'],
  ['nombre incorrecto',"update public.perfiles set nombre_completo='OTRO NOMBRE' where id=u;",'P0001'],
  ['version obsoleta',"vp:=vp-interval '1 second';",'40001'],
  ['cuenta portal protegida',"set local session_replication_role=replica; update public.perfiles set rol='admin' where id=u; set local session_replication_role=origin; select actualizado_en into vp from public.perfiles where id=u;",'P0001'],
]) test(`${nombre}: rechazo sin efectos`,()=>sql(`do $$ declare ${vars} begin ${fixture} ${cambio}
  begin perform ${borrar}; raise sqlstate 'ZX001'; exception when sqlstate '${codigo}' then null; end;
  if not exists(select 1 from auth.users where id=u) or exists(select 1 from private.usuarios_retirados where perfil_id=u)
    then raise exception 'Efectos parciales'; end if;
end $$;`));

test('Candidato sin membresía puede borrarse y no evade pendientes de clientes',()=>sql(`do $$ declare ${vars} cliente uuid; begin ${fixture}
  perform crm.purgar_membresia_crm(u,'Preparación sintética de candidato sin membresía'); ve:=null;
  select id into cliente from public.perfiles where rol='cliente' and activo limit 1;
  set local session_replication_role=replica;
  update public.perfiles set asesor_perfil_id=u where id=cliente;
  set local session_replication_role=origin;
  begin perform ${borrar}; raise sqlstate 'ZX001'; exception when sqlstate 'P0001' then
    if sqlerrm not like 'Transfiere primero%' then raise; end if;
  end;
  set local session_replication_role=replica;
  update public.perfiles set asesor_perfil_id=null where id=cliente;
  set local session_replication_role=origin;
  r:=${borrar};
  if r->>'resultado'<>'eliminado' then raise exception 'No eliminó candidato vacío'; end if;
end $$;`));

test('Una nueva FK CASCADE conserva al autor; auditoría y helpers inaccesibles',()=>sql(`
  create table crm.prueba_historial_usuario(autor uuid references public.perfiles(id) on delete cascade);
  do $$ declare ${vars} begin ${fixture}
    insert into crm.prueba_historial_usuario values(u);
    r:=${borrar};
    if r->>'resultado'<>'historial_conservado' or not exists(select 1 from crm.prueba_historial_usuario where autor=u)
      then raise exception 'Cascada destructiva'; end if;
    if has_function_privilege('anon','crm.eliminar_usuario_fn(uuid,text,timestamptz,timestamptz)','execute')
      or has_function_privilege('authenticated','private.usuario_tiene_historial(uuid)','execute')
      or has_table_privilege('authenticated','private.usuarios_retirados','select') then raise exception 'ACL insegura'; end if;
    begin delete from private.usuarios_retirados where perfil_id=u; raise sqlstate 'ZX001'; exception when insufficient_privilege then null; end;
  end $$;
`));

test('RPC se ejecuta como authenticated, sin acceso directo a la auditoría',()=>sql(`
  -- La copia aislada omite ACL de esquemas; USAGE está confirmado en producción.
  grant usage on schema crm to authenticated;
  do $$ declare ${vars} begin ${fixture}
    perform set_config('prueba.usuario',u::text,true);
    perform set_config('prueba.vp',vp::text,true);
    perform set_config('prueba.ve',ve::text,true);
  end $$;
  set local role authenticated;
  select crm.eliminar_usuario_fn(current_setting('prueba.usuario')::uuid,'ANALISTA SINTETICO',
    current_setting('prueba.vp')::timestamptz,current_setting('prueba.ve')::timestamptz);
  reset role;
`));

test('Un fallo al escribir auditoría revierte cuenta, membresía y sesiones',()=>sql(`
  create function pg_temp.fallar_usuario() returns trigger language plpgsql as $$
    begin raise exception 'Fallo sintético' using errcode='23514'; end $$;
  create trigger prueba_fallo before insert on private.usuarios_retirados
    for each row execute function pg_temp.fallar_usuario();
  do $$ declare ${vars} begin ${fixture}
    begin perform ${borrar}; raise sqlstate 'ZX001'; exception when check_violation then null; end;
    if not exists(select 1 from auth.users where id=u)
      or not exists(select 1 from public.perfiles where id=u and activo)
      or not exists(select 1 from crm.equipo where perfil_id=u and activo)
      or not exists(select 1 from auth.sessions where user_id=u)
      or exists(select 1 from private.usuarios_retirados where perfil_id=u)
      then raise exception 'Rollback incompleto'; end if;
  end $$;
`));

test('Postventa transfiere la tarea junto con la persona y conserva identidad',()=>sql(`do $$ declare ${vars} persona uuid; tarea uuid; reemplazo uuid; begin ${fixture}
  set local session_replication_role=replica;
  update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';
  select id into persona from crm.inversionistas where estado='activo' limit 1;
  select perfil_id into reemplazo from crm.equipo where rol_crm='vendedor' and activo and perfil_id<>u limit 1;
  update crm.inversionistas set responsable_relacion_id=u where id=persona;
  update crm.inversionista_responsables set hasta=now() where inversionista_id=persona and hasta is null;
  insert into crm.inversionista_responsables(inversionista_id,responsable_id,desde,motivo,por)
    values(persona,u,now(),'offboarding',a);
  insert into crm.tareas(inversionista_id,tipo,titulo,vence_en,vendedor_id,creado_por,postventa_revision)
    values(persona,'tarea','POSTVENTA SINTETICA',now()+interval '1 day',u,a,1) returning id into tarea;
  set local session_replication_role=origin;
  begin perform ${borrar}; raise sqlstate 'ZX001'; exception when sqlstate 'P0001' then
    if sqlerrm not like 'Transfiere primero%' then raise; end if;
  end;
  perform crm.fijar_membresia_activa_fn(u,false,reemplazo,ve,gen_random_uuid());
  select actualizado_en into ve from crm.equipo where perfil_id=u;
  select actualizado_en into vp from public.perfiles where id=u;
  r:=${borrar};
  if r->>'resultado'<>'historial_conservado'
    or not exists(select 1 from crm.tareas where id=tarea and vendedor_id=reemplazo)
    or not exists(select 1 from crm.inversionistas where id=persona and responsable_relacion_id=reemplazo)
    then raise exception 'Postventa no transferida'; end if;
end $$;`));

test('Bandera de identidad OFF no permite abandonar personas a cargo',()=>sql(`do $$ declare ${vars} begin ${fixture}
  set local session_replication_role=replica;
  update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';
  update crm.inversionistas set responsable_relacion_id=u where id=(select id from crm.inversionistas where estado='activo' limit 1);
  set local session_replication_role=origin;
  if not (crm.impacto_eliminacion_usuario_fn(u)->'pendientes'->>'requiere_reemplazo')::boolean
    then raise exception 'Ocultó responsabilidad existente'; end if;
  begin perform ${borrar}; raise sqlstate 'ZX001'; exception when sqlstate 'P0001' then
    if sqlerrm not like 'Transfiere primero%' then raise; end if;
  end;
end $$;`));

test('La protección serializa contra una baja en vuelo sin esperar ni asignar',async()=>{
  const destino=sql("select perfil_id from crm.equipo where rol_crm='vendedor' and activo limit 1;");
  const args=['exec','-i','supabase_db_crm-avance-corp-local','psql','-XqAt','-U','postgres',
    '-d','contratos_cotitular_v3_20260925','-v','ON_ERROR_STOP=1','-f','-'];
  const holder=spawn('docker',args,{stdio:['pipe','pipe','pipe']});
  let salida=''; let error='';
  holder.stderr.on('data',c=>{error+=c;});
  const fin=new Promise(resolve=>holder.on('close',resolve));
  const listo=new Promise((resolve,reject)=>{
    holder.stdout.on('data',c=>{salida+=c;if(salida.includes('LOCK_READY'))resolve();});
    holder.on('error',reject); holder.on('close',()=>reject(new Error(error||'No se obtuvo lock')));
  });
  holder.stdin.end(`begin; select 1 from crm.equipo where perfil_id='${destino}' for update;
    select 'LOCK_READY'; select pg_sleep(3); rollback;`);
  await listo;
  sql(`create temporary table leads(activo boolean,etapa text,vendedor_id uuid,asignado_supervisor_id uuid);
    create trigger prueba before insert on leads for each row execute function private.no_asignar_usuario_retirado();
    do $$ begin
      begin insert into leads values(true,'nuevo','${destino}',null); raise sqlstate 'ZX001';
      exception when serialization_failure then null; end;
      if exists(select 1 from leads) then raise exception 'Asignó durante la baja'; end if;
    end $$;`);
  assert.equal(await fin,0,error);
});
