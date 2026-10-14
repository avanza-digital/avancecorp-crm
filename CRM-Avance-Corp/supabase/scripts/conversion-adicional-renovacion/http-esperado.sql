-- Matriz de roles SQL con los perfiles reales de la branch; ROLLBACK obligatorio.

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

select jsonb_agg(jsonb_build_object('id',id,'rol',rol,'activo',activo,'dbrol',dbrol,'esperado',pg_temp.leer(id,dbrol))) as casos from actores;
rollback;
