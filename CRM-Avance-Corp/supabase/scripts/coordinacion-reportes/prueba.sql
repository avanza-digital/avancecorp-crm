-- ensayar.py aporta la siembra compartida y los cuerpos anteriores/nuevos.
-- No ejecutar directamente: requiere la guardia del banco exclusivo.
do $coord$
declare u uuid := gen_random_uuid(); z uuid := gen_random_uuid(); s uuid;
begin
  perform set_config('crm.op_privilegiada','on',true);
  select uid into s from pg_temp.f3b_actores where clase='sup1';
  insert into auth.users(id,email) values (u,u::text||'@coordinacion.test'),(z,z::text||'@coordinacion.test');
  insert into public.perfiles(id,nombre_completo,correo,rol,activo,tipo_documento,
      debe_cambiar_password,titular_distinto,titular_distinto_usd)
    values(u,'COORDINACION SINTETICA',u::text||'@coordinacion.test','comercial',true,'DNI',false,false,false),
          (z,'ANALISTA SIN VENTAS',z::text||'@coordinacion.test','comercial',true,'DNI',false,false,false);
  insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
    values(u,'coordinador',null,true),(z,'vendedor',s,true);
  insert into pg_temp.f3b_actores values('coordinador',u),('sin_ventas',z);
  -- Foto sintética de dos equipos de un mes cerrado, sin recalcular el pasado.
  insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura)
    values((date_trunc('month',now() at time zone 'America/Lima')-interval '2 months')::date,1,1,'{}');
  insert into crm.cierre_mes_vendedor(periodo,vendedor_id,nombre_completo,supervisor_id,supervisor_nombre,
      divisor,cierres_no_referidos,cierres_referidos,cierres_de_arrastre,numerador,conversion_pct,estado,
      referidos_recibidos,referidos_dados_de_alta,conversion_objetivo)
    select pc.periodo,e.perfil_id,p.nombre_completo,e.supervisor_id,'SUPERVISOR HISTORICO',10,2,0,0,2,20,'medible',0,0,15
    from crm.periodos_cerrados pc cross join crm.equipo e join public.perfiles p on p.id=e.perfil_id
    where e.rol_crm='vendedor' and e.perfil_id<>z;
  perform set_config('crm.op_privilegiada','',true);
end $coord$;

create temporary table resultados(clase text,periodo date,fase text,cifras jsonb);
create temporary table identificadores_privados as
  select id from crm.leads union all select id from public.contratos
  union all select id from crm.cierres_externos
  union all select id from public.perfiles where rol='cliente';
grant select on pg_temp.identificadores_privados to authenticated;
create temporary table nombres_privados as
  select nombre_completo from crm.leads union select nombre_completo from public.perfiles where rol='cliente';
grant select on pg_temp.nombres_privados to authenticated;
grant all on pg_temp.resultados to authenticated;
grant select on pg_temp.f3b_actores to authenticated;
create function pg_temp.sesion(u uuid) returns void language sql as $f$
  select set_config('request.jwt.claim.sub',u::text,true);
  select set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
$f$;
create function pg_temp.lectura(consulta text,mes date) returns jsonb language plpgsql as $f$
declare valor jsonb;
begin
  execute consulta into valor using mes;
  return valor;
exception when insufficient_privilege then return '{"denegado":true}'::jsonb;
end $f$;
create function pg_temp.reportes(u uuid,mes date) returns jsonb language plpgsql as $f$
declare r record; salida jsonb:='{}'; valor jsonb;
begin
  perform pg_temp.sesion(u);
  for r in select * from (values
    ('facturacion','select coalesce(jsonb_agg(to_jsonb(f) order by to_jsonb(f)::text),''[]''::jsonb) from crm.facturacion_diaria_fn($1) f'),
    ('lista','select crm.listar_operaciones_facturacion_fn($1,($1+interval ''1 month''-interval ''1 day'')::date)'),
    ('conversion','select crm.conversion_mensual_fn($1)'),
    ('metas','select crm.cumplimiento_metas_fn($1)'),
    ('cosecha','select crm.metricas_conversiones_equipo_fn($1,least((now() at time zone ''America/Lima'')::date,($1+interval ''1 month''-interval ''1 day'')::date))'),
    ('origen','select crm.metricas_conversiones_fn($1,least((now() at time zone ''America/Lima'')::date,($1+interval ''1 month''-interval ''1 day'')::date),null)'),
    ('origen_oficina','select crm.metricas_conversiones_fn($1,least((now() at time zone ''America/Lima'')::date,($1+interval ''1 month''-interval ''1 day'')::date),''oficina'')'),
    ('desglose','select crm.ranking_origen_vendedor_v2_fn($1,(select uid from pg_temp.f3b_actores where clase=''vendedor''))')
  ) llamadas(nombre,consulta) loop
    begin
      execute r.consulta into valor using mes;
      salida:=salida||jsonb_build_object(r.nombre,valor);
    exception when insufficient_privilege then
      salida:=salida||jsonb_build_object(r.nombre,jsonb_build_object('denegado',true));
    end;
  end loop;
  return salida;
end $f$;
-- CUERPOS ANTERIORES
-- SNAPSHOTS ANTES
-- CUERPOS NUEVOS
-- SNAPSHOTS DESPUES
set local role authenticated;
do $prueba$
declare r record; u uuid; mes date; pagina jsonb; fila jsonb; n integer; filas integer:=0;
begin
  raise notice 'Comprobando paridad de otros roles';
  if (select count(*) from pg_temp.resultados where fase='antes')<>15
    or (select count(*) from pg_temp.resultados where fase='despues')<>18 then
    raise exception 'Matriz incompleta';
  end if;
  if exists(select 1 from pg_temp.resultados a join pg_temp.resultados d using(clase,periodo)
    where a.fase='antes' and d.fase='despues' and a.cifras is distinct from d.cifras) then
    raise exception 'REGRESION: reportes de otro rol cambiaron';
  end if;
  raise notice 'Comprobando cifras globales de Coordinación';
  for r in select c.periodo,c.cifras,g.cifras as gerente
    from pg_temp.resultados c join pg_temp.resultados g using(periodo)
    where c.clase='coordinador' and g.clase='gerencia' and g.fase='despues' loop
    if r.cifras-'lista' is distinct from r.gerente-'lista' then
      raise exception 'Coordinación no recibe las mismas cifras globales del mes %',r.periodo;
    end if;
    if r.cifras->'lista'->'totales' is distinct from r.gerente->'lista'->'totales' then
      raise exception 'Totales de detalle diferentes';
    end if;
    -- La representación JSON conserva las claves en cualquier profundidad, incluidos arrays.
    if (r.cifras-'lista')::text ~ '"(cliente_id|lead_id|contrato_id|cierre_externo_id|inversionista_id|dni|telefono|correo|nombre_cliente|numero_contrato)"[[:space:]]*:'
      or exists(select 1 from pg_temp.identificadores_privados sujetos
        where (r.cifras-'lista')::text like '%'||sujetos.id::text||'%')
      or exists(select 1 from pg_temp.nombres_privados sujetos
        where (r.cifras-'lista')::text like '%'||sujetos.nombre_completo||'%') then
      raise exception 'El ranking o agregado de Facturación incluye PII o identificadores de clientes';
    end if;
  end loop;
  select uid into u from pg_temp.f3b_actores where clase='coordinador';
  perform pg_temp.sesion(u);
  raise notice 'Comprobando roster y RLS';
  if (select count(*) from crm.equipo_reportes_fn())<>6
    or not exists(select 1 from crm.equipo_reportes_fn() where nombre_completo='ANALISTA SIN VENTAS') then
    raise exception 'Roster no incluye todos los equipos y analistas sin ventas';
  end if;
  if exists(select 1 from crm.leads) then raise exception 'Coordinación ve leads por RLS'; end if;
  if exists(select 1 from public.perfiles where rol='cliente') then raise exception 'Coordinación ve clientes'; end if;
  if has_function_privilege('authenticated','private.es_coordinador_reportes()','execute') then
    raise exception 'El helper privado es invocable directamente';
  end if;
  begin
    raise notice 'Comprobando veto de publicación';
    perform crm.publicar_metas_vendedores(date_trunc('month',now())::date,0,'[]'::jsonb);
    raise exception 'Coordinación puede publicar metas';
  exception when insufficient_privilege then null; end;
  mes:=(date_trunc('month',now() at time zone 'America/Lima')-interval '1 month')::date;
  raise notice 'Comprobando anonimización';
  for n in 1..3 loop
    pagina:=crm.listar_operaciones_facturacion_fn(mes,(mes+interval '1 month'-interval '1 day')::date,
      p_pagina=>n,p_tamano=>100);
    for fila in select * from jsonb_array_elements(pagina->'filas') loop
      filas:=filas+1;
      if (fila->>'visible')::boolean is distinct from false
        or fila ?| array['cliente_id','lead_id','contrato_id','cierre_externo_id','operacion_id','inversionista_id','dni','telefono','correo']
        or fila->>'cliente_nombre' is distinct from 'Cliente de otro equipo' then
        raise exception 'Datos de cliente filtrados a Coordinación: %',fila;
      end if;
    end loop;
  end loop;
  if filas<200 then raise exception 'No se probaron varias páginas'; end if;
  perform crm.leads_por_repartir(); -- Su autorización debe seguir aceptando Coordinación.
  raise notice 'PASS: 120 comparaciones de reportes de otros roles, 24 lecturas globales de Coordinación, 3 páginas sin PII, roster, RLS y consulta de reparto';
end $prueba$;
reset role;
-- Baja CRM / baja Portal deben cortar todas las lecturas, sin cambio de JWT.
create function pg_temp.probar_baja() returns void language plpgsql as $bajas$
declare u uuid; r record;
begin
  select uid into u from pg_temp.f3b_actores where clase='coordinador';
    begin
      perform crm.equipo_reportes_fn();
      raise exception 'Roster visible tras baja';
    exception when insufficient_privilege then null; end;
    for r in select * from (values
      (date_trunc('month',now() at time zone 'America/Lima')::date),
      ((date_trunc('month',now() at time zone 'America/Lima')-interval '2 months')::date)
    ) m(periodo) loop
      if pg_temp.reportes(u,r.periodo)->'facturacion' <> '[]'::jsonb
        or pg_temp.reportes(u,r.periodo)->'lista'->>'total' <> '0'
        or not (pg_temp.reportes(u,r.periodo)->'conversion' @> '{"denegado":true}'::jsonb)
        or not (pg_temp.reportes(u,r.periodo)->'origen' @> '{"denegado":true}'::jsonb) then
        raise exception 'Reportes visibles tras baja';
      end if;
    end loop;
end $bajas$;
-- BAJAS EN SENTENCIAS INDEPENDIENTES
do $acl$ begin
  if has_function_privilege('anon','crm.equipo_reportes_fn()','execute')
    or has_function_privilege('authenticated','private.es_coordinador_reportes()','execute')
    or has_function_privilege('authenticated','private.cierre_mes_reportes_visible(date,uuid)','execute') then
    raise exception 'ACL inesperada de reportes';
  end if;
  if exists(select 1 from pg_trigger where tgrelid in ('crm.equipo'::regclass,'public.perfiles'::regclass)
    and not tgisinternal and tgenabled='D') then
    raise exception 'Quedó un trigger de fixture desactivado';
  end if;
  raise notice 'PASS: bajas de CRM/Portal con el mismo JWT, anonimato y helpers sellados';
end $acl$;
