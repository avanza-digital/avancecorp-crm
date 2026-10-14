-- Matriz de roles SQL con los perfiles reales de la branch; ROLLBACK obligatorio.
\set ON_ERROR_STOP on
begin;
set local statement_timeout='90s';
create temp table funcion_nueva as select pg_get_functiondef(
  'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure) sql;
create temp table actores as select perfil_id id,rol_crm rol,activo,'authenticated'::text dbrol from crm.equipo;
insert into actores values (null,'sin_sesion',false,'anon'),
  (md5('sin-equipo-adicional')::uuid,'sin_equipo',false,'authenticated'),
  (null,'servicio',false,'service_role');
create function pg_temp.leer(uid uuid,dbrol text) returns jsonb language plpgsql as $$
declare j jsonb;
begin
  perform set_config('request.jwt.claim.sub',coalesce(uid::text,''),true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role',dbrol)::text,true);
  execute format('set local role %I',dbrol);
  begin
    j:=crm.conversion_mensual_fn('2026-10-01')-'generado_en';
  exception when others then j:=jsonb_build_object('sqlstate',sqlstate,'error',sqlerrm);
  end;
  reset role;
  return j;
end $$;
\ir nucleo-anterior.sql
create temp table antes as select row_number() over() n,a.*,pg_temp.leer(id,dbrol) j from actores a;
do $$ begin execute(select sql from funcion_nueva); end $$;
create temp table despues as select n,id,rol,activo,dbrol,pg_temp.leer(id,dbrol) j from antes;
do $test$
declare a record; d jsonb; r record; r2 jsonb; delta numeric; visibles int;
begin
  for a in select * from antes loop
    select j into strict d from despues where n=a.n;
    if a.j ? 'sqlstate' or d ? 'sqlstate' then
      if a.j<>d then raise exception 'Cambió denegación del rol % activo %',a.rol,a.activo; end if;
    else
      if (select array_agg(x->>'vendedor_id' order by x->>'vendedor_id') from jsonb_array_elements(a.j->'responsables') x)
        is distinct from
        (select array_agg(x->>'vendedor_id' order by x->>'vendedor_id') from jsonb_array_elements(d->'responsables') x)
        then raise exception 'Cambió ámbito del rol % activo %',a.rol,a.activo; end if;
      for r in select x j from jsonb_array_elements(a.j->'responsables') x loop
        select x into strict r2 from jsonb_array_elements(d->'responsables') x where x->>'vendedor_id'=r.j->>'vendedor_id';
        delta:=case when r.j->>'vendedor_id'='2c10b18a-a15d-4952-952b-c4ab91b96153' then 1 else 0 end;
        if r2->'divisor'<>r.j->'divisor' or (r2->>'numerador')::numeric-(r.j->>'numerador')::numeric<>delta then
          raise exception 'Cambio inesperado para rol %',a.rol;
        end if;
      end loop;
      select count(*) into visibles from jsonb_array_elements(d->'responsables') x
        where x->>'vendedor_id'='2c10b18a-a15d-4952-952b-c4ab91b96153';
      if d#>'{total,divisor}'<>a.j#>'{total,divisor}'
        or (d#>>'{total,numerador}')::numeric-(a.j#>>'{total,numerador}')::numeric<>visibles then
        raise exception 'Total fuera del ámbito para rol %',a.rol;
      end if;
    end if;
  end loop;
  if has_function_privilege('anon','private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)','EXECUTE')
    or has_function_privilege('authenticated','private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)','EXECUTE')
    or has_function_privilege('service_role','private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)','EXECUTE') then
    raise exception 'El núcleo privado quedó expuesto';
  end if;
end $test$;
select rol,activo,dbrol,count(*) actores,bool_or(j ? 'sqlstate') denegacion
from despues group by rol,activo,dbrol order by rol,activo;
rollback;
