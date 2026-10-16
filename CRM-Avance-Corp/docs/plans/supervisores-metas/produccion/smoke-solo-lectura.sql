begin read only;
set local statement_timeout='120s';
do $smoke$
declare a record; m date; r jsonb; evidencia jsonb:='[]'; negocio jsonb;
  esperadas jsonb:='{}'; mapa jsonb;
begin
 for a in
   select * from (
     select e.perfil_id,e.rol_crm,row_number() over(partition by e.rol_crm order by e.perfil_id) n
     from crm.equipo e join public.perfiles p on p.id=e.perfil_id
     where e.activo and p.activo and e.rol_crm in ('gerencia','supervisor','vendedor','coordinador','directorio')
   ) x where n=1 or rol_crm='supervisor'
 loop
   perform set_config('request.jwt.claim.sub',a.perfil_id::text,true);
   perform set_config('request.jwt.claims',jsonb_build_object('sub',a.perfil_id,'role','authenticated')::text,true);
   execute 'set local role authenticated';
   foreach m in array array[date '2026-09-01',date '2026-10-01'] loop
     r:=crm.cumplimiento_metas_fn(m);
     if a.rol_crm='gerencia' then
       select coalesce(jsonb_object_agg(md5(f->>'persona_id'),jsonb_build_object(
         'huella',md5(jsonb_build_array(f)::text),'filas',1)),'{}'::jsonb)
         into mapa from jsonb_array_elements(r->'fuera_ranking') f;
       esperadas:=jsonb_set(esperadas,array[m::text],mapa,true);
     end if;
     evidencia:=evidencia||jsonb_build_array(jsonb_build_object(
       'actor',md5(a.perfil_id::text),'rol',a.rol_crm,'mes',m,
       'base',md5((r-'fuera_ranking')::text),'fuera',md5((r->'fuera_ranking')::text),
       'filas_fuera',jsonb_array_length(r->'fuera_ranking'),
       'solo_propio',not exists(select 1 from jsonb_array_elements(r->'fuera_ranking') f where f->>'persona_id'<>a.perfil_id::text),
       'propias',coalesce((select jsonb_agg(f) from jsonb_array_elements(r->'fuera_ranking') f where f->>'persona_id'=a.perfil_id::text),'[]'::jsonb)
     ));
   end loop;
   execute 'reset role';
 end loop;
 -- La evidencia que se conserva no incluye nombres, UUID ni importes propios.
 select jsonb_agg((e-'propias')||jsonb_build_object('huella_propias',md5((e->'propias')::text),
   'esperadas',coalesce(esperadas#>array[e->>'mes',e->>'actor'],jsonb_build_object('huella',md5('[]'),'filas',0))))
   into evidencia from jsonb_array_elements(evidencia) e;
 select jsonb_build_object(
   'contratos',(select count(*) from public.contratos),
   'operaciones',(select count(*) from crm.operaciones_cartera),
   'sellos',(select count(*) from crm.periodos_cerrados),
   'contratos_hash',(select md5(jsonb_agg(to_jsonb(c) order by id)::text) from public.contratos c),
   'operaciones_hash',(select md5(jsonb_agg(to_jsonb(o) order by id)::text) from crm.operaciones_cartera o),
   'sellos_hash',(select md5(jsonb_agg(to_jsonb(p) order by periodo)::text) from crm.periodos_cerrados p)
 ) into negocio;
 raise notice 'SMOKE_SUPERVISORES %',jsonb_build_object('lecturas',evidencia,'negocio',negocio,
   'funcion',(select md5(prosrc) from pg_proc where oid='crm.cumplimiento_metas_fn(date)'::regprocedure));
end;
$smoke$;
rollback;
