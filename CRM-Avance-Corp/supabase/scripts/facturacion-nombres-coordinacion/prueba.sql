grant select on pg_temp.f3b_actores to authenticated;
create function pg_temp.sesion(u uuid) returns void language sql as $f$
  select set_config('request.jwt.claim.sub',u::text,true);
  select set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
$f$;
create temporary table ids_privados as
  select id from public.perfiles where rol='cliente'
  union select id from public.contratos union select id from crm.leads
  union select id from crm.cierres_externos union select id from crm.inversionistas;
grant select on pg_temp.ids_privados to authenticated;
set local role authenticated;
do $paridad$
declare r record; mes date; antigua jsonb; nueva jsonb; comparaciones integer:=0;
begin
  for r in select * from pg_temp.f3b_actores where clase in ('gerencia','directorio','sup1','sup2','vendedor') loop
    perform pg_temp.sesion(r.uid);
    for mes in select (date_trunc('month',now() at time zone 'America/Lima')-n*interval '1 month')::date
      from generate_series(0,2) n loop
      antigua:=crm.listar_operaciones_facturacion_fn(mes,(mes+interval '1 month'-interval '1 day')::date,p_tamano=>100);
      nueva:=crm.listar_operaciones_facturacion_v2_fn(mes,(mes+interval '1 month'-interval '1 day')::date,p_tamano=>100);
      if nueva->>'version' is distinct from '2' or antigua-'version' is distinct from nueva-'version' then
        raise exception 'Cambió la visibilidad o cifra de otro rol: %',r.clase;
      end if;
      comparaciones:=comparaciones+1;
    end loop;
  end loop;
  if comparaciones<>15 then raise exception 'Matriz incompleta'; end if;
  raise notice 'PASS: 15 comparaciones exactas v1/v2 de otros roles, tres meses';
end $paridad$;
do $nombres$
declare mes date; n integer; antigua jsonb; nueva jsonb; gerente jsonb; fila jsonb;
  filas integer:=0; contratos integer:=0; cooperativas integer:=0; coord uuid; jefe uuid;
begin
  select uid into coord from pg_temp.f3b_actores where clase='coordinador';
  select uid into jefe from pg_temp.f3b_actores where clase='gerencia';
  for mes in select (date_trunc('month',now() at time zone 'America/Lima')-serie.mes_anterior*interval '1 month')::date
    from generate_series(0,2) as serie(mes_anterior) loop
    for n in 1..3 loop
      perform pg_temp.sesion(jefe);
      gerente:=crm.listar_operaciones_facturacion_fn(mes,(mes+interval '1 month'-interval '1 day')::date,p_pagina=>n,p_tamano=>100);
      perform pg_temp.sesion(coord);
      antigua:=crm.listar_operaciones_facturacion_fn(mes,(mes+interval '1 month'-interval '1 day')::date,p_pagina=>n,p_tamano=>100);
      nueva:=crm.listar_operaciones_facturacion_v2_fn(mes,(mes+interval '1 month'-interval '1 day')::date,p_pagina=>n,p_tamano=>100);
      if nueva-'filas'-'version' is distinct from antigua-'filas'-'version' then
        raise exception 'Cambió total, filtro o paginación de Coordinación';
      end if;
      if nueva->'totales' is distinct from gerente->'totales' then raise exception 'Cifras globales distintas'; end if;
      for fila in select * from jsonb_array_elements(nueva->'filas') loop
        filas:=filas+1;
        if fila->>'tipo'='cooperativa' then cooperativas:=cooperativas+1; else contratos:=contratos+1; end if;
        if fila->>'visible' is distinct from 'false' or fila->>'nombre_visible' is distinct from 'true'
          or fila->'cliente_nombre' is distinct from gerente->'filas'->((fila->>'n')::integer-(n-1)*100-1)->'cliente_nombre'
          or fila-'nombre_visible'-'cliente_nombre' is distinct from
             (antigua->'filas'->((fila->>'n')::integer-(n-1)*100-1))-'cliente_nombre'
          or exists(select 1 from jsonb_object_keys(fila) k where k<>all(array[
             'n','fecha','tipo','moneda','monto','anulado','analista_id','analista_nombre',
             'supervisor_id','supervisor_nombre','visible','cliente_nombre','nombre_visible']))
          or exists(select 1 from pg_temp.ids_privados i where fila::text like '%'||i.id::text||'%') then
          raise exception 'Contrato de nombres o privacidad incumplido en fila %',fila->>'n';
        end if;
      end loop;
      if exists(select 1 from jsonb_array_elements(antigua->'filas') f
        where f->>'cliente_nombre'<>'Cliente de otro equipo' or f ? 'nombre_visible') then
        raise exception 'La API v1 dejó de ser compatible';
      end if;
    end loop;
  end loop;
  if filas<200 or contratos=0 or cooperativas=0 then raise exception 'No se probaron tipos/páginas suficientes'; end if;
  if exists(select 1 from crm.leads) or exists(select 1 from public.perfiles where rol='cliente') then
    raise exception 'Coordinación obtiene fichas por RLS';
  end if;
  begin
    perform crm.publicar_metas_vendedores(date_trunc('month',now())::date,0,'[]'::jsonb);
    raise exception 'Coordinación puede publicar metas';
  exception when insufficient_privilege then null; end;
  perform crm.leads_por_repartir();
  raise notice 'PASS: % nombres exactos (% contratos, % cooperativas), tres páginas/mes, v1 intacta, sin IDs/contactos ni nuevas escrituras',filas,contratos,cooperativas;
end $nombres$;
reset role;
create function pg_temp.probar_baja() returns void language plpgsql as $f$
declare lista jsonb; mes date:=(date_trunc('month',now() at time zone 'America/Lima')-interval '1 month')::date;
begin
  lista:=crm.listar_operaciones_facturacion_v2_fn(mes,(mes+interval '1 month'-interval '1 day')::date,p_tamano=>100);
  if lista->>'total' is distinct from '0' or lista->'filas' is distinct from '[]'::jsonb then raise exception 'Nombres disponibles tras baja'; end if;
end $f$;
do $acl$ begin
  if has_function_privilege('authenticated','private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)','execute')
    or has_function_privilege('anon','crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)','execute')
    or has_function_privilege('service_role','crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)','execute') then
    raise exception 'La nueva consulta amplió ACL';
  end if;
  raise notice 'PASS: helper privado sellado, API v2 sin acceso anónimo/service_role';
end $acl$;
