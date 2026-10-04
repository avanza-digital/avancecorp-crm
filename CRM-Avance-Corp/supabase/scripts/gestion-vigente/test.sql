-- Banco exclusivamente sintético con seed-demo. Todo se revierte.
\set ON_ERROR_STOP on
begin;
set local session_replication_role=replica;
create temporary table casos (id uuid primary key,n integer,esperado boolean);
insert into casos select gen_random_uuid(),n,n between 1 and 5 from generate_series(1,100) n;
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,tenencia_desde,activo,etapa)
select c.id,'GESTIONADO PRUEBA '||c.n,'+51980000'||lpad(c.n::text,3,'0'),'otro',1000,
 case when c.n=11 then null else (select id from public.perfiles where nombre_completo='ANALISTA UNO') end,
 case when c.n=12 then null else '2026-10-01 10:00:00.000123+00'::timestamptz end,
 c.n<>13,case when c.n=14 then 'contactado' else 'nuevo' end from casos c;
insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select c.id,case c.n when 1 then 'llamada_realizada' when 2 then 'llamada_no_contestada'
 when 3 then 'whatsapp_enviado' when 4 then 'whatsapp_recibido' when 5 then 'reunion_realizada'
 when 9 then 'nota' else 'llamada_no_contestada' end,
 (select id from public.perfiles where nombre_completo='ANALISTA DOS'),
 case when c.n=6 then '2026-10-01 10:00:00.000122+00'::timestamptz else '2026-10-01 10:00:00.000123+00'::timestamptz end,
 case when c.n=7 then '{"deshecho_en":null}'::jsonb when c.n=8 then '{"deshecho_en":"2026-10-02"}'::jsonb else '{}'::jsonb end
from casos c where c.n<=14 and c.n<>10;
set local session_replication_role=origin;
create temporary table actores as select nombre_completo,id from public.perfiles
 where nombre_completo in ('ANALISTA UNO','ANALISTA DOS','SUPERVISOR UNO','SUPERVISOR DOS','GERENCIA DEMO','DIRECTORIO DEMO');
grant select on casos,actores to authenticated;
-- Guarda estructural: ambos lectores siguen invoker y estables.
do $$ begin
 if exists(select 1 from pg_proc where oid in ('crm.gestion_vigente_fn(uuid[])'::regprocedure,
 'private.gestion_vigente_lectura(uuid[])'::regprocedure) and (prosecdef or provolatile<>'s')) then raise exception 'Permisos/volatilidad'; end if;
 if has_function_privilege('anon','private.gestion_vigente_lectura(uuid[])','execute') or has_function_privilege('service_role','private.gestion_vigente_lectura(uuid[])','execute') then raise exception 'ACL núcleo'; end if;
 if has_function_privilege('anon','crm.gestion_vigente_fn(uuid[])','execute') or has_function_privilege('service_role','crm.gestion_vigente_fn(uuid[])','execute') then raise exception 'ACL pública'; end if;
end $$;
set local role authenticated;
do $$ declare actor record; respuesta jsonb; filas jsonb; ids uuid[]; r record; lote jsonb; esperado integer;
begin
 select array_agg(id order by n) into ids from casos;
 for actor in select * from actores loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor.id,'role','authenticated')::text,true);
  respuesta:=crm.gestion_vigente_fn(ids);
  if respuesta->>'version'<>'1' then raise exception 'Versión'; end if;
  filas:=respuesta->'items';
  esperado:=case when actor.nombre_completo in ('ANALISTA DOS','SUPERVISOR DOS') then 0
    when actor.nombre_completo in ('ANALISTA UNO','SUPERVISOR UNO') then 97 else 98 end;
  if jsonb_array_length(filas)<>esperado then raise exception 'Ámbito de %: % != %',actor.nombre_completo,jsonb_array_length(filas),esperado; end if;
  for r in select c.n,c.esperado,j.value from jsonb_array_elements(filas) j join casos c on c.id=(j.value->>'lead_id')::uuid loop
   if (r.value->>'gestion_vigente')::boolean is distinct from r.esperado then raise exception 'Clasificación caso % actor %',r.n,actor.nombre_completo; end if;
  end loop;
  lote:=crm.cartera_filtrada_fn(p_limite=>200,p_texto=>'GESTIONADO PRUEBA',p_etapa=>'nuevo',p_gestion=>'con_gestion');
  if (select count(*) from jsonb_array_elements(lote->'items'))<>(select count(*) from jsonb_array_elements(filas) x where (x->>'gestion_vigente')::boolean) then raise exception 'Difiere de filtro %: %',actor.nombre_completo,lote; end if;
  raise notice 'PASS %: ámbito, cinco contactos, microsegundo anterior, deshechos, nota, sin contacto, sin titular, sin tenencia, inactivo/avanzado y filtro',actor.nombre_completo;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',(select id from actores where nombre_completo='GERENCIA DEMO'),'role','authenticated')::text,true);
 if crm.gestion_vigente_fn('{}')<>jsonb_build_object('version',1,'items','[]'::jsonb) then raise exception 'Vacío'; end if;
 if jsonb_array_length(crm.gestion_vigente_fn(array[ids[1],ids[1]])->'items')<>1 then raise exception 'Duplicados'; end if;
 begin perform crm.gestion_vigente_fn(ids||ids[1]); raise exception 'Aceptó 101'; exception when sqlstate '22023' then null; end;
 begin perform crm.gestion_vigente_fn(null); raise exception 'Aceptó null'; exception when sqlstate '22023' then null; end;
 begin perform crm.gestion_vigente_fn(array[null::uuid]); raise exception 'Aceptó elemento null'; exception when sqlstate '22023' then null; end;
 begin perform crm.gestion_vigente_fn(array[array[ids[1]],array[ids[2]]]); raise exception 'Aceptó matriz'; exception when sqlstate '22023' then null; end;
 raise notice 'PASS vacío, duplicados, límite 100/101, null, elemento null y matriz';
end $$;
explain (analyze,buffers) select crm.gestion_vigente_fn((select array_agg(id) from casos));
reset role;
rollback;
