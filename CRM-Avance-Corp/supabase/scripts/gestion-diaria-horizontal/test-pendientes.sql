-- Datos sintéticos; lecturas como authenticated/anon; todo termina en rollback.
begin;
set local statement_timeout = '120s';
do $$ begin if current_database() not in ('gestion_diaria_h3_20260923','gestion_diaria_h3_http_20260923') then raise exception 'Sólo el banco H3 sintético'; end if; end $$;
create temporary table h3_actores as
with vendedores as (select e.perfil_id, e.supervisor_id from crm.equipo e
  where private.rol_crm(e.perfil_id)='vendedor' and private.rol_crm(e.supervisor_id)='supervisor'
  order by e.perfil_id)
select (select perfil_id from vendedores limit 1) vendedor,
  (select supervisor_id from vendedores limit 1) supervisor,
  (select perfil_id from vendedores where supervisor_id<>(select supervisor_id from vendedores limit 1) limit 1) ajeno,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id)='coordinador' limit 1) coordinador,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id)='gerencia' limit 1) gerente,
  (select id from public.perfiles where activo and rol='directorio' limit 1) global,
  gen_random_uuid() lead, gen_random_uuid() oculto, gen_random_uuid() inversionista;
grant select on h3_actores to authenticated, anon;
create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'H3: %', mensaje; end if; end $$;
create function pg_temp.denegada(comando text, codigo text default '42501') returns void language plpgsql as $$
declare recibido text; begin
  begin execute comando; exception when others then recibido:=sqlstate; end;
  perform pg_temp.afirmar(recibido=codigo, format('Error esperado %s; recibido %s: %s',codigo,coalesce(recibido,'ninguno'),comando));
end $$;
select pg_temp.afirmar(vendedor is not null and supervisor is not null and ajeno is not null and gerente is not null
  and coordinador is not null and global is not null, 'faltan actores sintéticos') from h3_actores;
select set_config('request.jwt.claim.sub', gerente::text, true) from h3_actores;
select crm.crear_lead_si_disponible(p_nombre_completo=>'H3 REFERENCIA VISIBLE',p_telefono=>'999577781',
  p_origen=>'oficina',p_monto_estimado=>25000,p_moneda=>'PEN',p_id=>lead,p_vendedor_id=>vendedor) from h3_actores;
select crm.crear_lead_si_disponible(p_nombre_completo=>'H3 REFERENCIA OCULTA',p_telefono=>'999577782',
  p_origen=>'oficina',p_monto_estimado=>25000,p_moneda=>'PEN',p_id=>oculto,p_vendedor_id=>vendedor) from h3_actores;
-- Únicamente preparar fixtures: jamás acreditar las lecturas como postgres.
alter table crm.tareas disable trigger user;
update crm.tareas set activo=false where vendedor_id=(select vendedor from h3_actores);
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,creado_por)
select a.lead,a.vendedor,'llamada','H3 TAREA '||i,now()-interval '1 hour',a.vendedor
from h3_actores a cross join generate_series(1,1005) i;
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,creado_por)
select oculto,vendedor,'llamada','H3 OCULTA',now()-interval '1 hour',vendedor from h3_actores;
insert into crm.tareas(perfil_id,vendedor_id,tipo,titulo,vence_en,creado_por)
select vendedor,vendedor,'tarea','H3 PERFIL',now()+interval '1 day',vendedor from h3_actores;
alter table crm.inversionistas disable trigger user;
insert into crm.inversionistas(id,responsable_relacion_id,creado_por)
select inversionista,vendedor,gerente from h3_actores;
alter table crm.inversionistas enable trigger user;
insert into crm.tareas(inversionista_id,postventa_revision,vendedor_id,tipo,titulo,vence_en,creado_por)
select inversionista,1,vendedor,'tarea','H3 POSTVENTA',now()-interval '1 hour',vendedor from h3_actores;
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,creado_por,estado,activo)
select lead,vendedor,'llamada','H3 EXCLUIDA',now()-interval '1 hour',vendedor,'completada',true from h3_actores
union all select lead,vendedor,'llamada','H3 EXCLUIDA',now()-interval '1 hour',vendedor,'pendiente',false from h3_actores
union all select lead,ajeno,'llamada','H3 EXCLUIDA',now()-interval '1 hour',ajeno,'pendiente',true from h3_actores;
alter table crm.tareas enable trigger user;
alter table crm.leads disable trigger user;
update crm.leads set vendedor_id=(select ajeno from h3_actores),asignado_supervisor_id=null where id=(select oculto from h3_actores);
alter table crm.leads enable trigger user;
create temporary table h3_paginas(n int, foto jsonb);
create temporary table h3_ids(id uuid primary key, item jsonb);
grant all on h3_paginas,h3_ids to authenticated;
select set_config('request.jwt.claim.sub',supervisor::text,true) from h3_actores;
set local role authenticated;
select pg_temp.afirmar(not exists(select 1 from crm.leads where id=(select oculto from h3_actores)), 'el lead ajeno no debe ser visible');
select pg_temp.afirmar(private.postventa_visible(inversionista), 'postventa visible bajo las banderas del banco') from h3_actores;
do $$ declare p jsonb; cursor_fecha timestamptz; cursor_id uuid; fila jsonb; n int:=0; anterior record;
begin
  loop
    p:=crm.gestion_diaria_pendientes_fn((select vendedor from h3_actores),false,100,cursor_fecha,cursor_id);
    n:=n+1; insert into h3_paginas values(n,p);
    perform pg_temp.afirmar((p#>>'{resumen,tareas_pendientes}')::int=1008 and (p#>>'{resumen,tareas_vencidas}')::int=1007,'totales completos y previos al cursor');
    perform pg_temp.afirmar(p->'generado_en'=p->'pendientes_al','una sola foto de la sentencia');
    perform pg_temp.afirmar(jsonb_array_length(p->'items')<=100,'limite respetado');
    for fila in select value from jsonb_array_elements(p->'items') loop
      perform pg_temp.afirmar((fila->>'vendedor_id')::uuid=(select vendedor from h3_actores),'responsable autorizado');
      perform pg_temp.afirmar((select count(*) from jsonb_object_keys(fila))=9 and not fila ?| array['telefono','correo','nota','monto','perfil_id','inversionista_id'],'referencia mínima exacta');
      select (item->>'vence_en')::timestamptz vence,id into anterior from h3_ids order by (item->>'vence_en')::timestamptz desc,id desc limit 1;
      if found then perform pg_temp.afirmar(((fila->>'vence_en')::timestamptz,(fila->>'id')::uuid)>(anterior.vence,anterior.id),'orden estricto entre páginas y empates'); end if;
      insert into h3_ids values((fila->>'id')::uuid,fila);
    end loop;
    exit when not (p->>'hay_mas')::boolean;
    cursor_fecha:=(p#>>'{siguiente_cursor,despues_de}')::timestamptz;
    cursor_id:=(p#>>'{siguiente_cursor,despues_id}')::uuid;
    perform pg_temp.afirmar(p#>>'{items,99,id}'=cursor_id::text,'cursor es última fila entregada');
    perform pg_temp.afirmar(n<20,'cursor debe terminar');
  end loop;
  perform pg_temp.afirmar(n=11 and (select count(*) from h3_ids)=1008,'recorrido sin tope de mil ni repetidos');
  perform pg_temp.afirmar(p->'siguiente_cursor'='null'::jsonb,'última página sin cursor');
end $$;
select pg_temp.afirmar(item->>'referencia_tipo'='lead' and item->'lead_id'='null'::jsonb and item->'lead_nombre'='null'::jsonb,'tarea de lead movido no desaparece ni revela referencia') from h3_ids where item->>'titulo'='H3 OCULTA';
select pg_temp.afirmar(item->>'referencia_tipo'='perfil' and item->'lead_id'='null'::jsonb,'perfil sin enlace inventado') from h3_ids where item->>'titulo'='H3 PERFIL';
select pg_temp.afirmar(item->>'referencia_tipo'='postventa' and item->'lead_id'='null'::jsonb,'postventa sin enlace inventado') from h3_ids where item->>'titulo'='H3 POSTVENTA';
select pg_temp.afirmar((p#>>'{resumen,tareas_pendientes}')::int=1008 and (p#>>'{resumen,tareas_vencidas}')::int=1007
  and not exists(select 1 from jsonb_array_elements(p->'items') i where (i->>'vence_en')::timestamptz>=(p->>'pendientes_al')::timestamptz),'filtro vencidas no recorta resumen')
from (select crm.gestion_diaria_pendientes_fn(vendedor,true,100) p from h3_actores) consulta;
-- Puerta y núcleo deben responder igual y rechazar los mismos parámetros.
select pg_temp.afirmar(crm.gestion_diaria_pendientes_fn(vendedor)=private.gestion_diaria_pendientes_core(vendedor,false,25,null,null),'núcleo invoker no abre otro alcance') from h3_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)',ajeno)) from h3_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)',gen_random_uuid()));
select pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null)',ajeno)) from h3_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L,false,%s)',vendedor,n),'22023') from h3_actores cross join unnest(array[0,101]) n;
select pg_temp.denegada('select crm.gestion_diaria_pendientes_fn(null)','22023');
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L,null,25)',vendedor),'22023') from h3_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L,false,null)',vendedor),'22023') from h3_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L,false,25,now(),null)',vendedor),'22023') from h3_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L,false,25,null,%L)',vendedor,gen_random_uuid()),'22023') from h3_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L,false,25,''infinity'',%L)',vendedor,gen_random_uuid()),'22023') from h3_actores;
reset role;
-- La consulta no es un snapshot histórico: insertar antes del cursor sólo se
-- recupera reiniciando; reprogramar hacia delante puede repetir un ID.
alter table crm.tareas disable trigger user;
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,creado_por)
select lead,vendedor,'tarea','H3 INSERTADA ANTES',now()-interval '2 hours',vendedor from h3_actores;
update crm.tareas set vence_en=now()+interval '2 days' where id=(select id from h3_ids order by (item->>'vence_en')::timestamptz,id limit 1);
alter table crm.tareas enable trigger user;
set local role authenticated;
select pg_temp.afirmar(p#>>'{items,0,titulo}'='H3 INSERTADA ANTES','reiniciar incluye las inserciones anteriores')
from (select crm.gestion_diaria_pendientes_fn(vendedor) p from h3_actores) q;
select pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(p->'items') i where i->>'titulo'='H3 INSERTADA ANTES'),'una página siguiente no promete snapshot')
from (select crm.gestion_diaria_pendientes_fn(vendedor,false,100,(foto#>>'{siguiente_cursor,despues_de}')::timestamptz,(foto#>>'{siguiente_cursor,despues_id}')::uuid) p from h3_actores,h3_paginas where n=1) q;
reset role;
-- Integridad fail-closed incluso si la fila dañada queda fuera del filtro/página.
alter table crm.tareas drop constraint tareas_un_solo_sujeto;
alter table crm.tareas disable trigger user;
update crm.tareas set perfil_id=(select vendedor from h3_actores) where titulo='H3 INSERTADA ANTES';
alter table crm.tareas enable trigger user;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L,true,1)',vendedor),'22000') from h3_actores;
reset role;
alter table crm.tareas disable trigger user;
update crm.tareas set perfil_id=null where titulo='H3 INSERTADA ANTES';
alter table crm.tareas enable trigger user;
alter table crm.tareas add constraint tareas_un_solo_sujeto check(num_nonnulls(lead_id,perfil_id,inversionista_id)=1);
-- Pérdida de visibilidad postventa deja de revelar su tarea.
alter table crm.inversionistas disable trigger user;
update crm.inversionistas set responsable_relacion_id=(select ajeno from h3_actores) where id=(select inversionista from h3_actores);
alter table crm.inversionistas enable trigger user;
set local role authenticated;
select pg_temp.afirmar((crm.gestion_diaria_pendientes_fn(vendedor)#>>'{resumen,tareas_pendientes}')::int=1008,'RLS postventa se revalida') from h3_actores;
reset role;
set local role authenticated;
do $$ declare p jsonb; cursor_fecha timestamptz; cursor_id uuid; vueltas int:=0; begin
  loop
    p:=crm.gestion_diaria_pendientes_fn((select vendedor from h3_actores),false,100,cursor_fecha,cursor_id);
    perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(p->'items') i where i->>'titulo'='H3 POSTVENTA'),'no revela la tarea de postventa revocada en ninguna página');
    exit when not (p->>'hay_mas')::boolean;
    vueltas:=vueltas+1; perform pg_temp.afirmar(vueltas<20,'termina al revalidar referencias');
    cursor_fecha:=(p#>>'{siguiente_cursor,despues_de}')::timestamptz;
    cursor_id:=(p#>>'{siguiente_cursor,despues_id}')::uuid;
  end loop;
end $$;
reset role;
-- Vacío confirmado, nunca inferido de un error.
alter table crm.tareas disable trigger user;
update crm.tareas set activo=false where vendedor_id=(select vendedor from h3_actores);
alter table crm.tareas enable trigger user;
set local role authenticated;
select pg_temp.afirmar(p->'items'='[]'::jsonb and p#>>'{resumen,tareas_pendientes}'='0'
  and p#>>'{resumen,tareas_vencidas}'='0' and p->'siguiente_cursor'='null'::jsonb and p->>'hay_mas'='false','cero completo y coherente')
from (select crm.gestion_diaria_pendientes_fn(vendedor) p from h3_actores) q;
reset role;
-- Vendedor, coordinador y lector global no tienen esta puerta. Gerencia la tiene desde
-- G4a (20260928043728); sus casos viven en supabase/scripts/g4/test-g4a.sql.
do $$ declare actor uuid; begin
  for actor in select unnest(array[vendedor,coordinador,global]) from h3_actores loop
    perform set_config('request.jwt.claim.sub',actor::text,true);
    execute 'set local role authenticated';
    perform pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)',(select vendedor from h3_actores)));
    perform pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null)',(select vendedor from h3_actores)));
    execute 'reset role';
  end loop;
end $$;
select set_config('request.jwt.claim.sub',supervisor::text,true) from h3_actores;
alter table crm.equipo disable trigger user;
update crm.equipo set activo=false where perfil_id=(select vendedor from h3_actores);
alter table crm.equipo enable trigger user;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)',vendedor)) from h3_actores;
reset role;
alter table crm.equipo disable trigger user;
update crm.equipo set activo=true where perfil_id=(select vendedor from h3_actores);
update crm.equipo set activo=false where perfil_id=(select supervisor from h3_actores);
alter table crm.equipo enable trigger user;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)',vendedor)) from h3_actores;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)',vendedor)) from h3_actores;
reset role;
set local role anon;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)',vendedor)) from h3_actores;
reset role;
-- Mutantes independientes: restauración automática de cada subtransacción.
do $$ declare comando text; detectado boolean; begin
  foreach comando in array array[
    'grant execute on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) to anon',
    'grant execute on function private.gestion_diaria_equipo_ambito(uuid) to public',
    'grant execute on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) to service_role',
    'revoke execute on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) from authenticated',
    'alter function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) security definer',
    'alter function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) set search_path=public',
    'alter function private.gestion_diaria_equipo_ambito(uuid) volatile'
  ] loop
    detectado:=false;
    begin
      execute comando;
      begin perform private.assert_gestion_diaria_pendientes(); exception when others then detectado:=true; end;
      raise exception 'Revertir mutante' using errcode='P0666';
    exception when sqlstate 'P0666' then null; end;
    perform pg_temp.afirmar(detectado,'mutante sobrevivió: '||comando);
  end loop;
end $$;
select private.assert_gestion_diaria_pendientes();
select 'H3_PENDIENTES_OK: 1008 tareas, 11 páginas, 3 anclas, permisos, errores, concurrencia y 7 mutantes';
rollback;
